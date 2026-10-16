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

import requests

MODEL = os.environ.get("AGENT_MODEL", "claude-sonnet-5-5")
BROKER_ID = "spiffe://bank.local/agents/ops-agent"
BROKER = {"http": "http://127.0.0.1:8090", "https": "http://127.0.0.1:8090"}
# Plain HTTP to the broker. No API key here: the broker adds x-api-key and upgrades to https.
CLAUDE_URL = "http://api.anthropic.com/v1/messages"


class Refused(Exception):
    pass


def claude(messages):
    try:
        r = requests.post(CLAUDE_URL, proxies=BROKER, timeout=60,
                          headers={"anthropic-version": "2023-06-01", "content-type": "application/json"},
                          json={"model": MODEL, "max_tokens": 800, "tools": TOOLS, "messages": messages,
                                "system": SYSTEM})
    except requests.RequestException as e:
        raise Refused(f"no connection to the broker ({type(e).__name__})")
    if r.status_code != 200:
        raise Refused(f"HTTP {r.status_code}: {r.text[:160]}")
    return r.json()


TOOLS = [
    {"name": "server_status", "description": "Uptime, load and disk usage of this server.",
     "input_schema": {"type": "object", "properties": {}}},
]


def server_status():
    du = shutil.disk_usage("/")
    up = open("/proc/uptime").read().split()[0]
    return f"uptime {float(up)/3600:.1f}h, load {os.getloadavg()}, disk / {du.used*100//du.total}% used"


def run_tool(name, args):
    if name == "server_status":
        return server_status()
    return "unknown tool"


SYSTEM = ("You are a friendly IT helpdesk assistant for the server vm3. Be brief. "
          "For questions about the server's health (status, uptime, disk, load) call the server_status tool "
          "and report its numbers.")


def turn(history):
    while True:
        try:
            resp = claude(history)
        except Refused as e:
            print(f"\033[31m[Secretless] Claude call refused ({e}): this agent has no access to the Claude key right now.\033[0m")
            history.pop()
            return
        history.append({"role": "assistant", "content": resp["content"]})
        if resp["stop_reason"] != "tool_use":
            txt = "".join(b.get("text", "") for b in resp["content"] if b["type"] == "text")
            if not txt:
                print(f"  \033[2m[debug] stop_reason={resp.get('stop_reason')} blocks={[b.get('type') for b in resp['content']]} "
                      f"raw={json.dumps(resp)[:300]}\033[0m")
            print("agent> " + txt)
            return
        results = []
        for b in resp["content"]:
            if b["type"] == "tool_use":
                print(f"  \033[2m[tool] {b['name']} {json.dumps(b['input'])}\033[0m")
                out = run_tool(b["name"], b["input"])
                print(f"  \033[2m[result] {out}\033[0m")
                results.append({"type": "tool_result", "tool_use_id": b["id"], "content": out})
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
