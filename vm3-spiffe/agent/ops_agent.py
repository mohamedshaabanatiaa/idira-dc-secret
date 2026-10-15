"""Ops agent on VM3: answers questions about this server with Claude.

It runs as Linux user "ops-agent" and holds NO credential: no API key, no token,
no SPIFFE identity. Claude calls go through the Secretless broker on 127.0.0.1:8090,
which runs as a different user ("ops-agent-broker"), is the only one registered in
SPIRE, and adds the Claude key from Secrets Manager to each request on its way out.
"""
import getpass
import json
import os
import shutil
import subprocess

os.environ["HTTP_PROXY"] = os.environ["http_proxy"] = "http://127.0.0.1:8090"
os.environ["NO_PROXY"] = os.environ["no_proxy"] = ".bank.local,localhost"

import anthropic  # noqa: E402

MODEL = os.environ.get("AGENT_MODEL", "claude-sonnet-5-5")
BROKER_ID = "spiffe://bank.local/agents/ops-agent"
claude = anthropic.Anthropic(base_url="http://api.anthropic.com",
                             api_key="injected-by-secretless", timeout=60, max_retries=0)

TOOLS = [
    {"name": "server_status", "description": "Uptime, load and disk usage of this server.",
     "input_schema": {"type": "object", "properties": {}}},
    {"name": "read_secret",
     "description": "Read a secret from the bank's Secrets Manager using this agent's own identity.",
     "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
]


def server_status():
    du = shutil.disk_usage("/")
    up = open("/proc/uptime").read().split()[0]
    return f"uptime {float(up)/3600:.1f}h, load {os.getloadavg()}, disk / {du.used*100//du.total}% used"


def read_secret(path):
    # The agent asks SPIRE who it is. It is not registered, so it gets nothing to log in with.
    r = subprocess.run(["/opt/spire/bin/spire-agent", "api", "fetch", "jwt", "-audience", "conjur",
                        "-socketPath", "/tmp/spire-agent/public/api.sock"], capture_output=True, text=True)
    if "token(" not in r.stdout:
        msg = f"this agent has no identity (SPIRE: no identity issued to user {getpass.getuser()}), so it cannot reach Secrets Manager"
        print(f"  \033[31m[DENIED] {msg}\033[0m")
        return "ACCESS DENIED: " + msg
    return "unexpected: this agent got an identity"


def run_tool(name, args):
    if name == "server_status":
        return server_status()
    if name == "read_secret":
        return read_secret(args["path"])
    return "unknown tool"


def turn(history):
    while True:
        try:
            resp = claude.messages.create(
                model=MODEL, max_tokens=800, tools=TOOLS, messages=history,
                system="You are the bank's server operations agent on vm3. Be brief. Use tools.")
        except (anthropic.APIStatusError, anthropic.APIConnectionError) as e:
            code = getattr(e, "status_code", "no connection")
            print(f"\033[31m[Secretless] Claude call refused ({code}): this agent has no access to the Claude key right now.\033[0m")
            history.pop()
            return
        history.append({"role": "assistant", "content": resp.content})
        if resp.stop_reason != "tool_use":
            print("agent> " + "".join(b.text for b in resp.content if b.type == "text"))
            return
        results = []
        for b in resp.content:
            if b.type == "tool_use":
                print(f"  \033[2m[tool] {b.name} {json.dumps(b.input)}\033[0m")
                results.append({"type": "tool_result", "tool_use_id": b.id, "content": run_tool(b.name, b.input)})
        history.append({"role": "user", "content": results})


def main():
    print(f"Ops agent on vm3 · runs as {getpass.getuser()} (holds no credential) · "
          f"Claude via Secretless, identity {BROKER_ID} · model {MODEL}")
    history = []
    while True:
        try:
            q = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if q in ("exit", "quit"):
            return
        if q:
            history.append({"role": "user", "content": q})
            turn(history)


if __name__ == "__main__":
    main()
