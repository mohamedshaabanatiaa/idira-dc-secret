#!/usr/bin/env bash
# Rotates the pet store DB password with NO restart.
# Secretless fetches credentials per NEW connection. Open connections stay
# valid after ALTER ROLE, so nothing breaks. --kick also drops open
# connections to prove the new password is used immediately.
source "$(dirname "$0")/lib.sh"
NS="$PET_NS"
NEW=$(new_password)
IP=$(hostname -I | awk '{print $1}')
POD_BEFORE=$(k -n "$NS" get pod -l app=petstore -o jsonpath='{.items[0].metadata.name}')

log "Rotating pet store DB password"
# DB first, then Secrets Manager right after: the gap is one API call, and
# only NEW connections opened inside that gap would retry.
k -n "$NS" exec petstore-db-0 -- psql -U "$PET_DB_USER" -d "$PET_DB_NAME" -qc "ALTER ROLE \"${PET_DB_USER}\" WITH PASSWORD '${NEW}';"
conjur_set bank/petstore/db/password "$NEW"
ok "database and Secrets Manager updated"

if [[ "${1:-}" == "--kick" ]]; then
  log "Dropping open connections (Secretless reconnects with the new value)"
  k -n "$NS" exec petstore-db-0 -- psql -U "$PET_DB_USER" -d "$PET_DB_NAME" -qtc \
    "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND usename='${PET_DB_USER}';"
fi

log "Proof: same pod, app still works"
sleep 3
for _ in 1 2 3; do curl -s -o /dev/null -w "  GET /pets -> %{http_code}\n" "http://${IP}:${PET_NODEPORT}/pets"; sleep 1; done
POD_AFTER=$(k -n "$NS" get pod -l app=petstore -o jsonpath='{.items[0].metadata.name}')
[[ "$POD_BEFORE" == "$POD_AFTER" ]] && ok "pod ${POD_AFTER} was never restarted" || warn "pod changed: ${POD_BEFORE} -> ${POD_AFTER}"
