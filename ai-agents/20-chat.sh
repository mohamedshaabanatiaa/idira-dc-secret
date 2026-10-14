#!/usr/bin/env bash
# Chat with the support agent (runs inside its pod).
#   ./20-chat.sh                         interactive
#   ./20-chat.sh "What pets do we have?" one question
exec kubectl -n agents exec -it deploy/support-agent -c agent -- python /app/agent.py "$@"
