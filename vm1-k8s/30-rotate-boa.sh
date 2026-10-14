#!/usr/bin/env bash
# Rotates a Bank of Anthos DB password with no outage.
#   ./30-rotate-boa.sh            -> accounts-db (login, contacts)
#   ./30-rotate-boa.sh --ledger   -> ledger-db (balances, payments)
# Order matters (smallest possible window):
#   1. new value in Secrets Manager   (running pods unaffected)
#   2. sync job refreshes K8s Secret  (running pods still unaffected, env read at start)
#   3. ALTER the DB password          (open pooled connections stay valid)
#   4. rolling restart                (new pod Ready with new password before old pod stops)
source "$(dirname "$0")/lib.sh"
conjur_ready
NS="$BOA_NS"
NEW=$(new_password)

if [[ "${1:-}" == "--ledger" ]]; then
  DB=ledger-db-0; C=postgres; USER_="$BOA_LEDGER_USER"; DBN="$BOA_LEDGER_DB"
  APPS="ledgerwriter balancereader transactionhistory"
  log "1. Secrets Manager: new ledger-db password"
  conjur variable set -i prod/boa/ledger-db/password -v "$NEW"
else
  DB=accounts-db-0; C=accounts-db; USER_="$BOA_ACCOUNTS_USER"; DBN="$BOA_ACCOUNTS_DB"
  APPS="userservice contacts"
  log "1. Secrets Manager: new accounts-db password"
  conjur variable set -i prod/boa/accounts-db/password -v "$NEW"
  conjur variable set -i prod/boa/accounts-db/uri -v "postgresql://${USER_}:${NEW}@accounts-db:5432/${DBN}"
fi

log "2. Sync into Kubernetes Secrets"
"$HERE/sync-boa.sh"

log "3. Database: ALTER password"
k -n "$NS" exec "$DB" -c "$C" -- psql -U "$USER_" -d "$DBN" -qc "ALTER USER \"${USER_}\" WITH PASSWORD '${NEW}';"
ok "database updated"

log "4. Rolling restart: ${APPS}"
for d in $APPS; do k -n "$NS" rollout restart deploy/$d >/dev/null; done
for d in $APPS; do k -n "$NS" rollout status deploy/$d --timeout=300s; done
ok "Rotated with no outage. New password starts ${NEW:0:4}..., no human saw it."
