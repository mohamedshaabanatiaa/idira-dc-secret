#!/usr/bin/env bash
# ./30-kill-switch.sh off   -> support-agent loses the Claude key on its NEXT turn
# ./30-kill-switch.sh on    -> access restored
# No redeploy, no key rotation at Anthropic, one policy change, fully audited.
source "$(dirname "$0")/../common/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
conjur_ready
f="$HERE/.ks.yml"
case "${1:-}" in
  off) echo '- !deny { role: !host agents/support-agent, privileges: [ read, execute ], resource: !variable ai/anthropic-api-key }' > "$f"
       conjur policy update -b prod -f "$f" >/dev/null; ok "support-agent cut off" ;;
  on)  echo '- !permit { role: !host agents/support-agent, privileges: [ read, execute ], resource: !variable ai/anthropic-api-key }' > "$f"
       conjur policy load -b prod -f "$f" >/dev/null; ok "support-agent restored" ;;
  *)   die "usage: $0 off|on" ;;
esac
rm -f "$f"
