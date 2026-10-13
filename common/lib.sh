#!/usr/bin/env bash
# Shared helpers for every VM. Sourced, never run.
set -euo pipefail
LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$LAB_ROOT/lab.env"
CERT_FILE="$LAB_ROOT/.conjur-cert.pem"
CONJUR_URL="https://${CONJUR_HOST}${CONJUR_API_PREFIX}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    ok: %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    warn: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m    error: %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
urlenc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

ensure_hosts_entry() {
  grep -q " ${CONJUR_HOST}\$" /etc/hosts || echo "${CONJUR_IP} ${CONJUR_HOST}" >> /etc/hosts
}

# Pulls the leader certificate chain and verifies TLS against it.
fetch_cert() {
  log "Fetching leader certificate from ${CONJUR_IP}:443 (SNI ${CONJUR_HOST})"
  openssl s_client -showcerts -connect "${CONJUR_IP}:443" -servername "${CONJUR_HOST}" </dev/null 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > "$CERT_FILE"
  [[ -s "$CERT_FILE" ]] || die "could not read certificate"
  curl -sS --fail --cacert "$CERT_FILE" "${CONJUR_URL}/info" >/dev/null \
    && ok "TLS to ${CONJUR_URL} verified" \
    || warn "TLS check failed: is ${CONJUR_HOST} in the cert SAN? is the API prefix right?"
}
conjur_cert() { [[ -s "$CERT_FILE" ]] || fetch_cert; }

ensure_pw() {
  if [[ -z "${CONJUR_ADMIN_PASSWORD}" ]]; then
    read -r -s -p "Secrets Manager password for ${CONJUR_ADMIN_USER}: " CONJUR_ADMIN_PASSWORD; echo
    export CONJUR_ADMIN_PASSWORD
  fi
}

conjur_token() {
  local api_key
  api_key=$(curl -sS --fail --cacert "$CERT_FILE" \
    --user "${CONJUR_ADMIN_USER}:${CONJUR_ADMIN_PASSWORD}" \
    "${CONJUR_URL}/authn/${CONJUR_ACCOUNT}/login") || die "admin login failed"
  curl -sS --fail --cacert "$CERT_FILE" -H "Accept-Encoding: base64" --data "$api_key" \
    "${CONJUR_URL}/authn/${CONJUR_ACCOUNT}/${CONJUR_ADMIN_USER}/authenticate" || die "authenticate failed"
}

# conjur_policy <branch> <file> [POST|PATCH|PUT] : POST appends, PATCH can delete/revoke
conjur_policy() {
  conjur_cert; ensure_pw
  local token; token=$(conjur_token)
  curl -sS --fail --cacert "$CERT_FILE" -X "${3:-POST}" \
    -H "Authorization: Token token=\"${token}\"" --data-binary @"$2" \
    "${CONJUR_URL}/policies/${CONJUR_ACCOUNT}/policy/$1" || die "policy load failed: $2"
  echo
}

conjur_set() {
  conjur_cert; ensure_pw
  local token; token=$(conjur_token)
  curl -sS --fail --cacert "$CERT_FILE" -X POST \
    -H "Authorization: Token token=\"${token}\"" --data-binary "$2" \
    "${CONJUR_URL}/secrets/${CONJUR_ACCOUNT}/variable/$(urlenc "$1")" || die "set failed: $1 (is policies/prod.yml loaded? see policies/README.md)"
  ok "set $1"
}

conjur_get() {
  conjur_cert; ensure_pw
  local token; token=$(conjur_token)
  curl -sS --fail --cacert "$CERT_FILE" -H "Authorization: Token token=\"${token}\"" \
    "${CONJUR_URL}/secrets/${CONJUR_ACCOUNT}/variable/$(urlenc "$1")"
}

# Rotates a host's API key and prints the new one: conjur_host_key <host-id>
conjur_host_key() {
  conjur_cert; ensure_pw
  local token; token=$(conjur_token)
  curl -sS --fail --cacert "$CERT_FILE" -X PUT -H "Authorization: Token token=\"${token}\"" \
    "${CONJUR_URL}/authn/${CONJUR_ACCOUNT}/api_key?role=$(urlenc "host:$1")" || die "api key rotation failed: $1"
}

# Renders a template: replaces __VAR__ with the value of $VAR for every __X__ found
render() {
  local out; out=$(cat "$1")
  for tok in $(grep -o '__[A-Z0-9_]*__' "$1" | sort -u); do
    local name=${tok#__}; name=${name%__}
    out=${out//$tok/${!name}}
  done
  printf '%s\n' "$out"
}
