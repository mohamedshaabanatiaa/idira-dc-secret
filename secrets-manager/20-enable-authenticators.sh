#!/usr/bin/env bash
# Allowlists every authenticator the lab uses. Run on the Secrets Manager VM.
# Safe to run again; authenticators whose policy is not loaded yet are just inactive.
source "$(dirname "$0")/../common/lib.sh"
NAME="conjur-leader"
AUTHNS=(authn authn-jwt/k3s authn-jwt/jenkins authn-jwt/gitlab authn-jwt/spire)

log "Writing /etc/conjur/config/conjur.yml inside $NAME"
{
  echo "authenticators:"
  for a in "${AUTHNS[@]}"; do echo "  - $a"; done
} | docker exec -i "$NAME" bash -c 'cat > /etc/conjur/config/conjur.yml'
docker exec "$NAME" cat /etc/conjur/config/conjur.yml

log "Applying"
if ! docker exec "$NAME" evoke configuration apply; then
  warn "configuration apply failed, falling back to evoke variable set"
  docker exec "$NAME" evoke variable set CONJUR_AUTHENTICATORS "$(IFS=,; echo "${AUTHNS[*]}")"
fi
sleep 5
log "Enabled authenticators"
curl -sk https://localhost/info | jq '.authenticators'
