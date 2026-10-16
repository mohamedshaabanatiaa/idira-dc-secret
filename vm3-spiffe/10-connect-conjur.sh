#!/usr/bin/env bash
# Connects SPIRE to Secrets Manager: a new authn-jwt authenticator that trusts SPIRE's
# JWT signing keys, plus the policy (host, secret, permit). Run on VM3 as root, after 00.
# Policy is loaded with "conjur policy load" = add only, nothing existing is removed.
source "$(dirname "$0")/../common/lib.sh"
need jq
SRV=/opt/spire/bin/spire-server
A=conjur/authn-jwt/spire

ensure_hosts_entry
fetch_cert
cp "$CERT_FILE" /opt/spire/conf/conjur.pem; chmod 644 /opt/spire/conf/conjur.pem
conjur_ready

log "Policy (add only): prod.yml, then authenticators.yml"
conjur policy load -b prod -f "$LAB_ROOT/policies/prod.yml" >/dev/null
conjur policy load -b root -f "$LAB_ROOT/policies/authenticators.yml" >/dev/null
ok "authenticator ${A} and the spiffe hosts"

log "Authenticator ${A}: trust SPIRE's JWT signing keys"
KEYS=$("$SRV" bundle show -format spiffe | jq -c '{keys: [.keys[] | select(.use == "jwt-svid") | del(.use)]}')
[[ $(jq '.keys | length' <<<"$KEYS") -ge 1 ]] || die "no JWT signing key in the SPIRE bundle"
conjur variable set -i "$A/public-keys" -v "{\"type\":\"jwks\",\"value\":${KEYS}}"
conjur variable set -i "$A/issuer"      -v "https://spire.bank.local"
conjur variable set -i "$A/audience"    -v "conjur"
ok "$(jq -r '.keys[].kid' <<<"$KEYS" | sed 's/^/kid /' | paste -sd' ')"

cat <<MSG

  One step on the Secrets Manager VM (allowlist the new authenticator):
      cd /opt/idira && git pull && ./secrets-manager/20-enable-authenticators.sh
  The output must list authn-jwt/spire. Then here: ./30-ops-agent.sh

MSG
