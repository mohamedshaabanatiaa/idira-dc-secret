"""Support agent: answers questions about the pet store inventory with Claude.

Identity: host/bank/agents/support-agent (Secrets Manager).
The Claude API key is fetched from Secrets Manager on EVERY turn and kept only
in memory, so revoking the agent takes effect on its next answer.
"""
import json
import os
import sys

import anthropic
import requests

from idira import AccessDenied, SecretsManager, mask

MODEL = os.environ.get("AGENT_MODEL", "claude-sonnet-5-5")
sm = SecretsManager("support-agent")

TOOLS = [
    {"name": "list_pets", "description": "List all pets in the pet store inventory.",
     "input_schema": {"type": "object", "properties": {}}},
    {"name": "add_pet", "description": "Add a pet to the pet store inventory.",
     "input_schema": {"type": "object", "properties": {"name": {"type": "string"}}, "required": ["name"]}},
    {"name": "read_secret",
     "description": "Read a secret from the bank's Secrets Manager by path. Only works for secrets this agent is entitled to.",
     "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
]


def run_tool(name, args):
    try:
        if name == "list_pets":
            return requests.get(f"{sm.petstore}/pets", timeout=10).text
        if name == "add_pet":
            r = requests.post(f"{sm.petstore}/pet", json={"name": args["name"]}, timeout=10)
            return f"HTTP {r.status_code}"
        if name == "read_secret":
            value = sm.get(args["path"])
            return f"read ok, value {mask(value)} (masked)"
    except AccessDenied as e:
        print(f"  \033[31m[Secrets Manager] {e}\033[0m")
        return f"ACCESS DENIED by Secrets Manager: {e}"
    except Exception as e:  # noqa: BLE001
        return f"error: {e}"
    return "unknown tool"


def turn(history):
    try:
        key = sm.get("bank/agents/anthropic-api-key")
    except AccessDenied as e:
        print(f"\033[31m[Secrets Manager] {e}\n Agent has been cut off. No Claude key, no answers.\033[0m")
        return
    print(f"  \033[2m[Secrets Manager] {sm.login} got Claude key {mask(key)} (memory only)\033[0m")
    client = anthropic.Anthropic(api_key=key)
    while True:
        resp = client.messages.create(
            model=MODEL, max_tokens=800, tools=TOOLS, messages=history,
            system="You are the bank's pet store support agent. Be brief. Use tools for inventory questions.")
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
    print(f"Support agent as {sm.login}, model {MODEL}. Ctrl-C to quit.")
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
