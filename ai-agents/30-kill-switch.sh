#!/usr/bin/env bash
# ./30-kill-switch.sh off   -> support-agent loses the Claude key on its NEXT call
# ./30-kill-switch.sh on    -> access restored
# One policy change, effective immediately, audited. No redeploy, no key rotation.
source "$(dirname "$0")/../vm1-k8s/lib.sh"
conjur_ready
f=$(mktemp)
RULE='{ role: !host k8s/system:serviceaccount:agents:support-agent, privileges: [ read, execute ], resource: !variable ai/anthropic-api-key }'
case "${1:-}" in
  off) echo "- !deny $RULE"   > "$f"; conjur policy update -b prod -f "$f" >/dev/null; ok "support-agent cut off" ;;
  on)  echo "- !permit $RULE" > "$f"; conjur policy load   -b prod -f "$f" >/dev/null; ok "support-agent restored" ;;
  *)   die "usage: $0 off|on" ;;
esac
rm -f "$f"
echo "  Who can use the Claude key now:"
conjur resource permitted-roles "${CONJUR_ACCOUNT}:variable:prod/ai/anthropic-api-key" execute | grep host: | sed 's/^/   /' || true
