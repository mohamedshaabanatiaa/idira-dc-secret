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

log "Configuring authenticator from k3s"
ISSUER=$(k get --raw /.well-known/openid-configuration | jq -r .issuer)
JWKS=$(k get --raw /openid/v1/jwks)
conjur_set "conjur/authn-jwt/${AUTHN_ID}/public-keys" "{\"type\":\"jwks\",\"value\":${JWKS}}"
conjur_set "conjur/authn-jwt/${AUTHN_ID}/issuer" "$ISSUER"
conjur_set "conjur/authn-jwt/${AUTHN_ID}/token-app-property" "sub"
conjur_set "conjur/authn-jwt/${AUTHN_ID}/identity-path" "$APP_IDENTITY_PATH"
conjur_set "conjur/authn-jwt/${AUTHN_ID}/audience" "conjur"
ok "issuer=${ISSUER}"

log "Seeding secrets with today's values (rotation comes later)"
conjur_set prod/boa/accounts-db/password "$BOA_ACCOUNTS_PASS"
conjur_set prod/boa/accounts-db/uri "postgresql://${BOA_ACCOUNTS_USER}:${BOA_ACCOUNTS_PASS}@accounts-db:5432/${BOA_ACCOUNTS_DB}"
conjur_set prod/boa/ledger-db/password "$BOA_LEDGER_PASS"
conjur_set prod/petstore/db/address "petstore-db.${PET_NS}.svc.cluster.local:5432/${PET_DB_NAME}"
conjur_set prod/petstore/db/username "$PET_DB_USER"
conjur_set prod/petstore/db/password "$PET_DB_PASS"

log "Publishing leader cert to both namespaces"
for ns in "$BOA_NS" "$PET_NS"; do publish_conjur_connect "$ns"; done

cat <<MSG

$(printf '\033[1;33m')ONE MANUAL STEP ON THE SECRETS MANAGER VM (as root):$(printf '\033[0m')
  The authenticator must be allowlisted on the leader. Edit /etc/conjur/config/conjur.yml:

    authenticators:
      - authn
      - authn-jwt/${AUTHN_ID}

  then run:   evoke configuration apply
  check with: curl -sk https://localhost/info | jq .authenticators

Next: ./21-migrate-boa.sh and ./22-migrate-petstore.sh
MSG
