#!/usr/bin/env bash
# One-time cleanup on VM3: removes the old settlement batch job (SPIRE entry, Linux user,
# script, Secrets Manager host and secret). Safe to run twice. Delete this file afterwards.
source "$(dirname "$0")/../common/lib.sh"
SRV=/opt/spire/bin/spire-server
log "SPIRE entry"
ID=$("$SRV" entry show -spiffeID spiffe://bank.local/batch/settlement | awk '/Entry ID/ {print $4}')
if [[ -n "$ID" ]]; then "$SRV" entry delete -entryID "$ID" >/dev/null && ok "entry deleted"; else ok "already gone"; fi
log "Linux user and script"
id settlement >/dev/null 2>&1 && userdel -r settlement 2>/dev/null; rm -f /opt/spire/bin/workload.sh
ok "user settlement and workload.sh removed"
log "Secrets Manager host and secret"
conjur_ready
f=$(mktemp)
printf -- '- !delete\n  record: !host spiffe/settlement-batch\n- !delete\n  record: !variable batch/core-banking-api-key\n' > "$f"
conjur policy update -b prod -f "$f" >/dev/null 2>&1 && ok "host and secret deleted" || ok "already gone"
rm -f "$f"
"$(dirname "$0")/40-show.sh"
