#!/usr/bin/env bash
# Puts Bank of Anthos back to its ORIGINAL hardcoded state, so you can
# rehearse the migration again. Policy in Secrets Manager is kept; secret
# values are reset to the originals so the next migration matches.
source "$(dirname "$0")/lib.sh"
log "Deleting namespace ${BOA_NS}"
k delete namespace "$BOA_NS" --ignore-not-found --wait=true --timeout=300s

if [[ -s "$CERT_FILE" ]]; then
  conjur_ready
  log "Resetting Secrets Manager values to the originals"
  conjur variable set -i prod/boa/accounts-db/password -v "$BOA_ACCOUNTS_PASS"
  conjur variable set -i prod/boa/accounts-db/uri -v "postgresql://${BOA_ACCOUNTS_USER}:${BOA_ACCOUNTS_PASS}@accounts-db:5432/${BOA_ACCOUNTS_DB}"
  conjur variable set -i prod/boa/ledger-db/password -v "$BOA_LEDGER_PASS"
fi

"$HERE/10-install-boa.sh"
[[ -s "$CERT_FILE" ]] && publish_conjur_connect "$BOA_NS"
ok "Back to the original hardcoded state. Migrate again with ./21-migrate-boa.sh"
