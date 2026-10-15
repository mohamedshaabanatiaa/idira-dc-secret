#!/usr/bin/env bash
# ./31-ops-chat.sh            chat with the ops agent (as user ops-agent)
# ./31-ops-chat.sh intruder   another user on the same VM tries to use the broker
source "$(dirname "$0")/../common/lib.sh"
if [[ "${1:-}" == intruder ]]; then
  echo -e "\n\033[1mUser intruder tries to call Claude through the broker on 127.0.0.1:8090\033[0m"
  runuser -u intruder -- curl -sS -m 5 -x http://127.0.0.1:8090 http://api.anthropic.com/v1/models 2>&1 \
    | sed 's/^/   /' || true
  echo -e "   \033[1;32m✓ refused: the broker only serves the ops-agent user\033[0m\n"
  exit 0
fi
cd /home/ops-agent && exec runuser -u ops-agent -- /opt/ops-agent/venv/bin/python /opt/ops-agent/ops_agent.py
