#!/usr/bin/env bash
# Connects k3s to Secrets Manager Self-Hosted.
# Prereq: policies/prod.yml and policies/authenticators.yml loaded from the Windows CLI.
#  1. trusts the leader certificate
#  2. configures authn-jwt/k3s with this cluster's issuer + signing keys
#  3. seeds the secrets with the CURRENT (original) values
#  4. publishes the connection details + cert into both namespaces
# Run on DevOps VM1 after 00/10/11. Uses the REST API, no CLI needed.
source "$(dirname "$0")/lib.sh"
need jq; need curl; need openssl; need python3

fetch_cert
conjur_ready

log "Configuring authenticator from k3s"
ISSUER=$(k get --raw /.well-known/openid-configuration | jq -r .issuer)
JWKS=$(k get --raw /openid/v1/jwks)
conjur variable set -i "conjur/authn-jwt/${AUTHN_ID}/public-keys" -v "{\"type\":\"jwks\",\"value\":${JWKS}}"
conjur variable set -i "conjur/authn-jwt/${AUTHN_ID}/issuer" -v "$ISSUER"
conjur variable set -i "conjur/authn-jwt/${AUTHN_ID}/token-app-property" -v "sub"
conjur variable set -i "conjur/authn-jwt/${AUTHN_ID}/identity-path" -v "$APP_IDENTITY_PATH"
conjur variable set -i "conjur/authn-jwt/${AUTHN_ID}/audience" -v "conjur"
ok "issuer=${ISSUER}"

log "Seeding secrets with today's values (rotation comes later)"
conjur variable set -i prod/boa/accounts-db/password -v "$BOA_ACCOUNTS_PASS"
conjur variable set -i prod/boa/accounts-db/uri -v "postgresql://${BOA_ACCOUNTS_USER}:${BOA_ACCOUNTS_PASS}@accounts-db:5432/${BOA_ACCOUNTS_DB}"
conjur variable set -i prod/boa/ledger-db/password -v "$BOA_LEDGER_PASS"
conjur variable set -i prod/petstore/db/host -v "petstore-db.${PET_NS}.svc.cluster.local"
conjur variable set -i prod/petstore/db/port -v "5432"
conjur variable set -i prod/petstore/db/username -v "$PET_DB_USER"
conjur variable set -i prod/petstore/db/password -v "$PET_DB_PASS"

log "Publishing leader cert to both namespaces"
for ns in "$BOA_NS" "$PET_NS"; do publish_conjur_connect "$ns"; done

ok "VM1 is connected. Next: ./21-migrate-boa.sh and ./22-migrate-petstore.sh"
