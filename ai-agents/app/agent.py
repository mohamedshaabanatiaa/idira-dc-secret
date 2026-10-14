"""Support agent: answers pet store questions with Claude.

Identity: the pod's service account, system:serviceaccount:agents:support-agent.
The Claude API key never enters this program. Claude is called through the
Secretless sidecar on localhost:8080, which fetches the key from Secrets Manager
with the pod's identity and adds it to the request on its way out.
"""
import json
import os
import sys

import anthropic
import requests

from idira import AccessDenied, get_secret, identity, mask

MODEL = os.environ.get("AGENT_MODEL", "claude-sonnet-5-5")
PETSTORE = os.environ["PETSTORE_URL"]

# All Claude calls go through the Secretless sidecar on localhost:8080.
# Only Claude traffic uses that proxy; the pet store and Secrets Manager do not.
os.environ["HTTP_PROXY"] = os.environ["http_proxy"] = "http://localhost:8080"
os.environ["NO_PROXY"] = os.environ["no_proxy"] = ".svc.cluster.local,.bank.local,localhost,127.0.0.1"
claude = anthropic.Anthropic(
    base_url="http://api.anthropic.com",          # Secretless upgrades this to https
    api_key="injected-by-secretless",             # placeholder, replaced in the sidecar
    timeout=60,
)

TOOLS = [
    {"name": "list_pets", "description": "List all pets in the pet store.",
     "input_schema": {"type": "object", "properties": {}}},
    {"name": "add_pet", "description": "Add a pet to the pet store.",
     "input_schema": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}},
    {"name": "read_secret",
     "description": "Read a secret from the bank's Secrets Manager. Only works for secrets this agent is allowed.",
     "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
]


def run_tool(name, args):
    try:
        if name == "list_pets":
            return requests.get(f"{PETSTORE}/pets", timeout=10).text
        if name == "add_pet":
            return f"HTTP {requests.post(f'{PETSTORE}/pet', json={'name': args['name']}, timeout=10).status_code}"
        if name == "read_secret":
            return f"read ok: {mask(get_secret(args['path']))} (masked)"
    except AccessDenied as e:
        print(f"  \033[31m[Secrets Manager] {e}\033[0m")
        return f"ACCESS DENIED by Secrets Manager: {e}"
    except Exception as e:  # noqa: BLE001
        return f"error: {e}"
    return "unknown tool"


def turn(history):
    while True:
        try:
            resp = claude.messages.create(
                model=MODEL, max_tokens=800, tools=TOOLS, messages=history,
                system="You are the bank's pet store support agent. Be brief. Use tools.")
        except anthropic.APIStatusError as e:
            print(f"\033[31m[Secretless] Claude call refused ({e.status_code}): this agent has no access to the Claude key right now.\033[0m")
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
    print(f"Support agent · identity {identity()} · model {MODEL}")
    print("Claude key: held by the Secretless sidecar, never by this program. Ctrl-C to quit.")
    history = []
    if len(sys.argv) > 1:
        history.append({"role": "user", "content": " ".join(sys.argv[1:])})
        turn(history)
        return
    while True:
        try:
            q = input("\nyou> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if q:
            history.append({"role": "user", "content": q})
            turn(history)


if __name__ == "__main__":
    main()
