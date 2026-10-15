#!/usr/bin/env bash
# Shows Secrets Manager audit events in plain form: time (UTC), then what happened.
# Run on the Secrets Manager VM as root.
#   ./90-audit.sh               last 1000 events, readable (pipe to grep)
#   ./90-audit.sh rotation      the pet store password: who changed it, who fetched it (demo, Loop 2)
#   ./90-audit.sh denied        failed attempts only (demo, Loop 3: rogue agent)
#   ./90-audit.sh <word>        last 30 events matching a word (petstore, jenkins, support-agent)
#   ./90-audit.sh check         health check: is the audit pipeline writing at all?
# Audit file (official): /var/log/conjur/audit.log in the container,
# mounted on the host at /opt/cyberark/conjur/logs.
LOGDIR=/opt/cyberark/conjur/logs
LOG="$LOGDIR/audit.log"
MODE="${1:-}"

# "2026-10-15T10:43:21.182+00:00 ... ] bank:user:admin updated bank:variable:..."
#   ->  "10:43:21  admin updated prod/petstore/db/password"
pretty() {
  sed -E 's/^<[0-9]+>1 [0-9-]+T([0-9:]{8})[^ ]* .*\] (bank:.*)$/\1  \2/' \
  | sed -E 's/bank:(user|host|variable|webservice|layer):?//g; s/bank://g'
}

case "$MODE" in
  check)
    echo "== files"; ls -la "$LOGDIR"/audit* 2>/dev/null || echo "  no audit files in $LOGDIR"
    echo "== last 3 lines"; tail -n 3 "$LOG" 2>/dev/null | pretty
    ;;
  rotation)
    # The last change, then the first 3 fetches after it (Secretless fetches a lot,
    # so showing every fetch would hide the change).
    echo "Pet store DB password: last change, and the first fetches after it"
    grep 'prod/petstore/db/password' "$LOG" | grep -E 'operation="(update|fetch)"' \
      | awk '/operation="update"/ { n = NR } { line[NR] = $0 }
             END { if (!n) { print "  no change recorded yet"; exit }
                   print line[n]; c = 0
                   for (i = n + 1; i <= NR && c < 3; i++) if (line[i] ~ /operation="fetch"/) { print line[i]; c++ } }' \
      | pretty
    ;;
  denied)
    echo "Denied attempts (last 15)"
    grep -E 'result="failure"' "$LOG" | tail -n 15 | pretty
    ;;
  "")
    tail -n 1000 "$LOG" | pretty
    ;;
  *)
    grep -i -- "$MODE" "$LOG" | grep -v 'operation="check"' | tail -n 30 | pretty
    ;;
esac
