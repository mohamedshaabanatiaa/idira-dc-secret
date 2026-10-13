#!/usr/bin/env bash
# Shows the last Secrets Manager audit events: who fetched what, allowed or denied.
#   ./90-audit.sh            last 30 events
#   ./90-audit.sh agent      filter on a word (agent, jenkins, gitlab, boa, denied)
source "$(dirname "$0")/../common/lib.sh"
FILTER="${1:-}"
docker exec conjur-leader bash -c 'ls /var/log/conjur/ 2>/dev/null' | sed 's/^/  log: /'
docker exec conjur-leader bash -c 'tail -n 400 /var/log/conjur/audit.json 2>/dev/null || tail -n 400 /var/log/conjur/audit.log' \
  | grep -i -- "${FILTER}" | tail -n 30 \
  | (jq -r '"\(.timestamp // .time)  \(.message // .msg)"' 2>/dev/null || cat)
