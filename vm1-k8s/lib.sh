#!/usr/bin/env bash
# Shared helpers. Sourced by every script.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../common/lib.sh"
# shellcheck disable=SC1091
source "$HERE/config.env"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

k() { kubectl "$@"; }

new_password() { openssl rand -hex 16; }

# Adds "envFrom: secretRef <secret>" to the container that already
# loads configmap <cm>. Idempotent.
add_secret_envfrom() {
  local ns=$1 kind=$2 name=$3 cm=$4 secret=$5 idx
  idx=$(k -n "$ns" get "$kind" "$name" -o json | jq -r --arg cm "$cm" '
    .spec.template.spec.containers | to_entries[]
    | select(.value.envFrom // [] | map(.configMapRef.name) | index($cm))
    | .key' | head -1)
  [[ -n "$idx" ]] || die "$kind/$name has no container using $cm"
  if k -n "$ns" get "$kind" "$name" -o json | jq -e --arg s "$secret" --argjson i "$idx" \
      '.spec.template.spec.containers[$i].envFrom | map(.secretRef.name) | index($s)' >/dev/null; then
    ok "$kind/$name already uses secret $secret"; return
  fi
  k -n "$ns" patch "$kind" "$name" --type=json \
    -p "[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/${idx}/envFrom/-\",\"value\":{\"secretRef\":{\"name\":\"${secret}\"}}}]"
  ok "$kind/$name now reads $secret"
}

# Publishes the Secrets Manager connection details + leader cert into a namespace
publish_conjur_connect() {
  conjur_cert
  k -n "$1" create configmap conjur-connect \
    --from-literal=CONJUR_APPLIANCE_URL="${CONJUR_URL}" \
    --from-literal=CONJUR_AUTHN_URL="${CONJUR_URL}/authn-jwt/${AUTHN_ID}" \
    --from-literal=CONJUR_ACCOUNT="${CONJUR_ACCOUNT}" \
    --from-file=ssl-certificate="$CERT_FILE" \
    --dry-run=client -o yaml | k apply -f - >/dev/null
  ok "conjur-connect published in $1"
}
