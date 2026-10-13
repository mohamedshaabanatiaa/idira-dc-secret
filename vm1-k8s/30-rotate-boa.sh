#!/usr/bin/env bash
# Rotates a Bank of Anthos DB password end to end.
#   ./30-rotate-boa.sh            -> accounts-db (login, contacts)
#   ./30-rotate-boa.sh --ledger   -> ledger-db (balances, payments)
# Steps: new password in the DB -> new value in Secrets Manager ->
#        sync job -> rolling restart of the consumers only.
source "$(dirname "$0")/lib.sh"
NS="$BOA_NS"
NEW=$(new_password)

if [[ "${1:-}" == "--ledger" ]]; then
  log "Rotating ledger-db password"
  k -n "$NS" exec ledger-db-0 -c postgres -- \
    psql -U "$BOA_LEDGER_USER" -d "$BOA_LEDGER_DB" -qc "ALTER USER \"${BOA_LEDGER_USER}\" WITH PASSWORD '${NEW}';"
  ok "database updated"
  conjur_set bank/boa/ledger-db/password "$NEW"
  APPS="ledgerwriter balancereader transactionhistory"
else
  log "Rotating accounts-db password"
  k -n "$NS" exec accounts-db-0 -- \
    psql -U "$BOA_ACCOUNTS_USER" -d "$BOA_ACCOUNTS_DB" -qc "ALTER USER \"${BOA_ACCOUNTS_USER}\" WITH PASSWORD '${NEW}';"
  ok "database updated"
  conjur_set bank/boa/accounts-db/password "$NEW"
  conjur_set bank/boa/accounts-db/uri "postgresql://${BOA_ACCOUNTS_USER}:${NEW}@accounts-db:5432/${BOA_ACCOUNTS_DB}"
  APPS="userservice contacts"
fi

"$HERE/sync-boa.sh"

log "Rolling restart of consumers: ${APPS}"
for d in $APPS; do k -n "$NS" rollout restart deploy/$d >/dev/null; done
for d in $APPS; do k -n "$NS" rollout status deploy/$d --timeout=300s; done
ok "Rotated. New password starts with ${NEW:0:4}... and no human ever handled it."
