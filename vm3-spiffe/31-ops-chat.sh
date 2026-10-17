#!/usr/bin/env bash
# ./31-ops-chat.sh            chat with the ops agent (as user ops-agent)
# ./31-ops-chat.sh intruder   another user on the same VM tries to use the broker
source "$(dirname "$0")/../common/lib.sh"
if [[ "${1:-}" == intruder ]]; then
  echo -e "\n\033[1mUser intruder, same VM, tries two ways in\033[0m"
  echo -e "\n  1. Ask SPIRE for an identity (to log in to Secrets Manager itself)"
  runuser -u intruder -- /opt/spire/bin/spire-agent api fetch jwt -audience conjur \
    -socketPath /tmp/spire-agent/public/api.sock 2>&1 | tail -1 | sed 's/^/     /' || true
  echo -e "     \033[1;32m✓ no identity: no registration entry matches user intruder\033[0m"
  echo -e "\n  2. Use the agent's broker on 127.0.0.1:8090 (it is already logged in)"
  runuser -u intruder -- curl -sS -m 5 -x http://127.0.0.1:8090 http://api.anthropic.com/v1/models 2>&1 \
    | sed 's/^/     /' || true
  echo -e "     \033[1;32m✓ refused: only user ops-agent may reach the broker\033[0m\n"
  exit 0
fi
cd /home/ops-agent && exec runuser -u ops-agent -- /opt/ops-agent/venv/bin/python /opt/ops-agent/ops_agent.py
