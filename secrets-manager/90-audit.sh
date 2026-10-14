#!/usr/bin/env bash
# Shows the last Secrets Manager audit events: who fetched or changed what, allowed or denied.
# Run on the Secrets Manager VM as root.
#   ./90-audit.sh               last 30 events
#   ./90-audit.sh rogue         filter on a word (rogue, support-agent, jenkins, petstore, failed)
#   ./90-audit.sh check         health check: is the audit pipeline writing at all?
# Audit files (official): /var/log/conjur/audit.log (syslog) and audit.json, inside the container.
# Our install mounts that folder on the host at /opt/cyberark/conjur/logs.
LOGDIR=/opt/cyberark/conjur/logs
FILTER="${1:-}"

if [ "$FILTER" = "check" ]; then
  echo "== files"; ls -la "$LOGDIR"/audit* 2>/dev/null || echo "  no audit files in $LOGDIR"
  echo "== services inside the container"
  docker exec conjur-leader bash -c 'sv status /etc/service/* 2>/dev/null' | grep -Ei 'audit|syslog|postgres|conjur|ui' || true
  echo "== last 3 lines"; tail -n 3 "$LOGDIR/audit.log" 2>/dev/null
  exit 0
fi

tail -n 2000 "$LOGDIR/audit.log" | grep -i -- "$FILTER" | tail -n 30
