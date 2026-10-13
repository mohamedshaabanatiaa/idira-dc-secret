#!/usr/bin/env bash
# Shared helpers. Sourced by every script.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
CERT_FILE="$HERE/.conjur-cert.pem"
CONJUR_URL="https://${CONJUR_HOST}${CONJUR_API_PREFIX}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    ok: %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    warn: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m    error: %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

k() { kubectl "$@"; }

new_password() { openssl rand -hex 16; }

# ---------- Secrets Manager REST helpers (no CLI dependency) ----------
conjur_cert() {
  [[ -s "$CERT_FILE" ]] || die "no leader cert yet, run 20-conjur-setup.sh first"
}

ensure_pw() {
  # Ask once per run, then reuse (exported for child scripts).
  if [[ -z "${CONJUR_ADMIN_PASSWORD}" ]]; then
    read -r -s -p "Secrets Manager password for ${CONJUR_ADMIN_USER}: " CONJUR_ADMIN_PASSWORD; echo
    export CONJUR_ADMIN_PASSWORD
  fi
}

conjur_token() {
  # Returns a base64 access token for the admin user.
  conjur_cert
  local api_key
  api_key=$(curl -sS --fail --cacert "$CERT_FILE" \
    --user "${CONJUR_ADMIN_USER}:${CONJUR_ADMIN_PASSWORD}" \
    "${CONJUR_URL}/authn/${CONJUR_ACCOUNT}/login") || die "login failed"
  curl -sS --fail --cacert "$CERT_FILE" \
    -H "Accept-Encoding: base64" --data "$api_key" \
    "${CONJUR_URL}/authn/${CONJUR_ACCOUNT}/${CONJUR_ADMIN_USER}/authenticate" \
    || die "authenticate failed"
}

# conjur_policy <branch> <file> : append (POST) policy into branch
conjur_policy() {
  ensure_pw
  local token; token=$(conjur_token)
  curl -sS --fail --cacert "$CERT_FILE" -X POST \
    -H "Authorization: Token token=\"${token}\"" \
    --data-binary @"$2" \
    "${CONJUR_URL}/policies/${CONJUR_ACCOUNT}/policy/$1" || die "policy load failed: $2"
  echo
}

# conjur_set <variable-id> <value>
conjur_set() {
  ensure_pw
  local token enc
  token=$(conjur_token)
  enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1")
  curl -sS --fail --cacert "$CERT_FILE" -X POST \
    -H "Authorization: Token token=\"${token}\"" \
    --data-binary "$2" \
    "${CONJUR_URL}/secrets/${CONJUR_ACCOUNT}/variable/${enc}" || die "set failed: $1"
  ok "set $1"
}

# conjur_get <variable-id>
conjur_get() {
  ensure_pw
  local token enc
  token=$(conjur_token)
  enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1")
  curl -sS --fail --cacert "$CERT_FILE" \
    -H "Authorization: Token token=\"${token}\"" \
    "${CONJUR_URL}/secrets/${CONJUR_ACCOUNT}/variable/${enc}"
}

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
