#!/usr/bin/env bash
# Kill switch for the support agent:  ./42-agent-kill.sh off   (chat fails)   ./42-agent-kill.sh on
# One policy line, effective on the agent's NEXT call. No redeploy, no key rotation. Audited.
set -euo pipefail
RULE='{ role: !host k8s/system:serviceaccount:agents:support-agent, privileges: [ read, execute ], resource: !variable ai/anthropic-api-key }'
case "${1:-}" in
  off) echo "- !deny $RULE"   > /tmp/kill.yml; conjur policy update -b prod -f /tmp/kill.yml ;;   # update = may remove
  on)  echo "- !permit $RULE" > /tmp/kill.yml; conjur policy load   -b prod -f /tmp/kill.yml ;;   # load = add only
  *)   echo "usage: $0 off|on"; exit 1 ;;
esac
echo "== Policy applied:"; cat /tmp/kill.yml; rm -f /tmp/kill.yml
echo "== Who can use the Claude key now:"
conjur resource permitted-roles bank:variable:prod/ai/anthropic-api-key execute | grep host: || true
