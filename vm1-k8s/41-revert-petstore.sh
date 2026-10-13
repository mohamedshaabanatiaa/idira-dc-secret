#!/usr/bin/env bash
# Puts the pet store back to its ORIGINAL hardcoded state.
source "$(dirname "$0")/lib.sh"
log "Deleting namespace ${PET_NS} (including the DB volume)"
k delete namespace "$PET_NS" --ignore-not-found --wait=true --timeout=300s

if [[ -s "$CERT_FILE" ]]; then
  log "Resetting Secrets Manager value to the original"
  conjur_set prod/petstore/db/password "$PET_DB_PASS"
fi

"$HERE/11-install-petstore.sh"
[[ -s "$CERT_FILE" ]] && publish_conjur_connect "$PET_NS"
ok "Back to the original hardcoded state. Migrate again with ./22-migrate-petstore.sh"
