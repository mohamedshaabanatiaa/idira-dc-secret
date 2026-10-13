#!/usr/bin/env bash
# Connects k3s to Secrets Manager Self-Hosted:
#  1. trusts the leader certificate
#  2. creates the authn-jwt/<AUTHN_ID> authenticator from the k3s issuer + JWKS
#  3. loads app identities, secrets and grants
#  4. seeds the secrets with the CURRENT (original) values
# Run on DevOps VM1 after 00/10/11. Uses the REST API, no CLI needed.
source "$(dirname "$0")/lib.sh"
need jq; need curl; need openssl; need python3

fetch_cert

log "Loading authenticator policy conjur/authn-jwt/${AUTHN_ID}"
sed "s/__AUTHN_ID__/${AUTHN_ID}/g" "$HERE"/policies/authn-jwt-k3s.yml.tmpl > "$HERE/.authn.yml"
conjur_policy root "$HERE/.authn.yml"

log "Configuring authenticator from k3s"
ISSUER=$(k get --raw /.well-known/openid-configuration | jq -r .issuer)
JWKS=$(k get --raw /openid/v1/jwks)
conjur_set "conjur/authn-jwt/${AUTHN_ID}/public-keys" "{\"type\":\"jwks\",\"value\":${JWKS}}"
conjur_set "conjur/authn-jwt/${AUTHN_ID}/issuer" "$ISSUER"
conjur_set "conjur/authn-jwt/${AUTHN_ID}/token-app-property" "sub"
conjur_set "conjur/authn-jwt/${AUTHN_ID}/identity-path" "$APP_IDENTITY_PATH"
conjur_set "conjur/authn-jwt/${AUTHN_ID}/audience" "conjur"
ok "issuer=${ISSUER}"

log "Loading app identities, secrets and grants (policy bank)"
sed -e "s/__AUTHN_ID__/${AUTHN_ID}/g" -e "s/__BOA_NS__/${BOA_NS}/g" -e "s/__PET_NS__/${PET_NS}/g" \
  "$HERE"/policies/bank-apps.yml.tmpl > "$HERE/.bank.yml"
conjur_policy root "$HERE/.bank.yml"

log "Seeding secrets with today's values (rotation comes later)"
conjur_set bank/boa/accounts-db/username "$BOA_ACCOUNTS_USER"
conjur_set bank/boa/accounts-db/password "$BOA_ACCOUNTS_PASS"
conjur_set bank/boa/accounts-db/uri "postgresql://${BOA_ACCOUNTS_USER}:${BOA_ACCOUNTS_PASS}@accounts-db:5432/${BOA_ACCOUNTS_DB}"
conjur_set bank/boa/ledger-db/username "$BOA_LEDGER_USER"
conjur_set bank/boa/ledger-db/password "$BOA_LEDGER_PASS"
conjur_set bank/petstore/db/address "petstore-db.${PET_NS}.svc.cluster.local:5432/${PET_DB_NAME}"
conjur_set bank/petstore/db/username "$PET_DB_USER"
conjur_set bank/petstore/db/password "$PET_DB_PASS"

log "Publishing leader cert to both namespaces"
for ns in "$BOA_NS" "$PET_NS"; do publish_conjur_connect "$ns"; done
rm -f "$HERE/.authn.yml" "$HERE/.bank.yml"

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
