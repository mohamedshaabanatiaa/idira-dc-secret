#!/usr/bin/env bash
# ./32-ops-kill.sh off   -> ops agent loses the Claude key on its NEXT call (one policy line)
# ./32-ops-kill.sh on    -> restored
source "$(dirname "$0")/../common/lib.sh"
conjur_ready
f=$(mktemp)
RULE='{ role: !host spiffe/ops-agent, privileges: [ read, execute ], resource: !variable ai/anthropic-api-key }'
case "${1:-}" in
  off) echo "- !deny $RULE"   > "$f"; conjur policy update -b prod -f "$f"; ok "ops agent cut off" ;;
  on)  echo "- !permit $RULE" > "$f"; conjur policy load   -b prod -f "$f"; ok "ops agent restored" ;;
  *)   die "usage: $0 off|on" ;;
esac
rm -f "$f"
echo "  Who can use the Claude key now:"
conjur resource permitted-roles "${CONJUR_ACCOUNT}:variable:prod/ai/anthropic-api-key" execute | grep -E 'host:' | sed 's/^/   /'
