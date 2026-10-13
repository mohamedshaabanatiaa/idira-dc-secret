#!/usr/bin/env bash
# Bank of Anthos: hardcoded ConfigMaps -> Secrets Manager.
# Pattern: Secrets Provider for Kubernetes (application mode, run as a Job)
# writes the values into Kubernetes Secrets. The apps keep reading env vars,
# zero code change. Refresh = re-run the job + rolling restart.
source "$(dirname "$0")/lib.sh"
NS="$BOA_NS"
k -n "$NS" get cm conjur-connect >/dev/null 2>&1 || die "run 20-conjur-setup.sh first"

log "Identity + RBAC for the sync job (it may only get/update secrets in ${NS})"
cat <<YAML | k -n "$NS" apply -f -
apiVersion: v1
kind: ServiceAccount
metadata: { name: secrets-provider }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: secrets-provider }
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: secrets-provider }
subjects: [ { kind: ServiceAccount, name: secrets-provider } ]
roleRef: { kind: Role, name: secrets-provider, apiGroup: rbac.authorization.k8s.io }
YAML

log "Kubernetes Secrets that only hold a MAP to Secrets Manager paths (no values)"
cat <<YAML | k -n "$NS" apply -f -
apiVersion: v1
kind: Secret
metadata: { name: accounts-db-creds }
type: Opaque
stringData:
  conjur-map: |-
    POSTGRES_PASSWORD: bank/boa/accounts-db/password
    ACCOUNTS_DB_URI: bank/boa/accounts-db/uri
---
apiVersion: v1
kind: Secret
metadata: { name: ledger-db-creds }
type: Opaque
stringData:
  conjur-map: |-
    POSTGRES_PASSWORD: bank/boa/ledger-db/password
    SPRING_DATASOURCE_PASSWORD: bank/boa/ledger-db/password
YAML

"$HERE/sync-boa.sh"

log "Removing hardcoded passwords from the ConfigMaps"
for pair in "accounts-db-config:POSTGRES_PASSWORD" "accounts-db-config:ACCOUNTS_DB_URI" \
            "ledger-db-config:POSTGRES_PASSWORD" "ledger-db-config:SPRING_DATASOURCE_PASSWORD"; do
  cm=${pair%%:*}; key=${pair##*:}
  if k -n "$NS" get cm "$cm" -o json | jq -e --arg k "$key" '.data | has($k)' >/dev/null; then
    k -n "$NS" patch cm "$cm" --type=json -p "[{\"op\":\"remove\",\"path\":\"/data/${key}\"}]" >/dev/null
    ok "removed ${cm}.${key}"
  fi
done

log "Pointing workloads at the synced Secrets"
add_secret_envfrom "$NS" statefulset accounts-db        accounts-db-config accounts-db-creds
add_secret_envfrom "$NS" deployment  userservice        accounts-db-config accounts-db-creds
add_secret_envfrom "$NS" deployment  contacts           accounts-db-config accounts-db-creds
add_secret_envfrom "$NS" statefulset ledger-db          ledger-db-config   ledger-db-creds
add_secret_envfrom "$NS" deployment  ledgerwriter       ledger-db-config   ledger-db-creds
add_secret_envfrom "$NS" deployment  balancereader      ledger-db-config   ledger-db-creds
add_secret_envfrom "$NS" deployment  transactionhistory ledger-db-config   ledger-db-creds

log "Waiting for rollouts (the patch already triggered them)"
k -n "$NS" rollout status statefulset/accounts-db --timeout=300s
k -n "$NS" rollout status statefulset/ledger-db --timeout=300s
for d in userservice contacts ledgerwriter balancereader transactionhistory; do
  k -n "$NS" rollout status deploy/$d --timeout=300s
done

log "Proof: ConfigMaps no longer hold credentials"
k -n "$NS" get cm accounts-db-config ledger-db-config -o json | jq -r '.items[] | "  \(.metadata.name): \(.data|keys|join(", "))"'
ok "Bank of Anthos now gets DB credentials from Secrets Manager. Log in and send a payment to prove it."
