#!/usr/bin/env bash
# AI agent kill switch:  ./52-agent-kill.sh off   then chat (fails)   then ./52-agent-kill.sh on
exec "$(dirname "$0")/../ai-agents/30-kill-switch.sh" "${1:?usage: $0 off|on}"
