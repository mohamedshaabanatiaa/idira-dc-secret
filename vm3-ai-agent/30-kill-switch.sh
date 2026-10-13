#!/usr/bin/env bash
# ./30-kill-switch.sh off   -> support-agent loses the Claude key on its NEXT turn
# ./30-kill-switch.sh on    -> access restored
# No redeploy, no key rotation at Anthropic, one policy change, fully audited.
source "$(dirname "$0")/../common/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
f="$HERE/.ks.yml"
case "${1:-}" in
  off) echo '- !revoke { role: !group llm-users, member: !host support-agent }' > "$f"
       conjur_policy bank/agents "$f" PATCH >/dev/null; ok "support-agent cut off" ;;
  on)  echo '- !grant { role: !group llm-users, member: !host support-agent }' > "$f"
       conjur_policy bank/agents "$f" POST >/dev/null; ok "support-agent restored" ;;
  *)   die "usage: $0 off|on" ;;
esac
rm -f "$f"
