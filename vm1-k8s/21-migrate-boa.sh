#!/usr/bin/env bash
# Bank of Anthos: hardcoded ConfigMaps -> Secrets Manager, one identity per microservice.
# Same commands as the Bank of Anthos part of demo/01-prepare.sh (kept in sync by hand).
# Pattern: Secrets Provider for Kubernetes as an INIT CONTAINER in every workload.
#   - each workload runs as its own service account = its own host in Secrets Manager
#   - its init container logs in with that token and fills only <workload>-creds
#   - the app keeps reading env vars (envFrom), zero code change
# Refresh / rotation = restart the workload: the init container fetches again.
set -euo pipefail
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
cd "$(dirname "$0")"
source ../lab.env; source ./config.env
kubectl -n boa get cm conjur-connect >/dev/null || { echo "run 20-conjur-setup.sh first"; exit 1; }

# ---------------------------------------------------------------- BANK OF ANTHOS
# One identity per microservice. Each pod runs Secrets Provider as an init container:
# it logs in with the pod's own service account token and fills only that pod's Secret.
#   workload                 reads its env from     gets only this from Secrets Manager
BOA=(
  "statefulset/accounts-db        accounts-db-config  POSTGRES_PASSWORD:prod/boa/accounts-db/password"
  "deployment/userservice         accounts-db-config  ACCOUNTS_DB_URI:prod/boa/accounts-db/uri"
  "deployment/contacts            accounts-db-config  ACCOUNTS_DB_URI:prod/boa/accounts-db/uri"
  "statefulset/ledger-db          ledger-db-config    POSTGRES_PASSWORD:prod/boa/ledger-db/password"
  "deployment/ledgerwriter        ledger-db-config    SPRING_DATASOURCE_PASSWORD:prod/boa/ledger-db/password"
  "deployment/balancereader       ledger-db-config    SPRING_DATASOURCE_PASSWORD:prod/boa/ledger-db/password"
  "deployment/transactionhistory  ledger-db-config    SPRING_DATASOURCE_PASSWORD:prod/boa/ledger-db/password"
)

echo "== BoA: policy as code. One identity + one permit per microservice (prod.yml), old shared rule removed"
conjur whoami >/dev/null || { echo "   Secrets Manager CLI not logged in: conjur login -i admin"; exit 1; }
conjur policy update -b prod -f ../policies/prod.yml >/dev/null
conjur policy update -b prod -f ../policies/once-boa-per-service.yml >/dev/null 2>&1 || true   # no-op once done
conjur resource show host:prod/k8s/system:serviceaccount:boa:userservice >/dev/null && echo "   7 identities ready"

for row in "${BOA[@]}"; do
  read -r obj cm map <<<"$row"; name=${obj#*/}
  echo "== BoA ${name}: own service account, a Secret holding only a MAP (${map}), rights on that one Secret"
  kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: ${name} }
---
apiVersion: v1
kind: Secret
metadata: { name: ${name}-creds }
stringData:
  conjur-map: "${map%%:*}: ${map#*:}"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ${name}-creds }
rules: [ { apiGroups: [""], resources: ["secrets"], resourceNames: ["${name}-creds"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: ${name}-creds }
subjects: [ { kind: ServiceAccount, name: ${name} } ]
roleRef: { kind: Role, name: ${name}-creds, apiGroup: rbac.authorization.k8s.io }
YAML
done

echo "== BoA: remove the hardcoded passwords from the ConfigMaps"
for pair in accounts-db-config:POSTGRES_PASSWORD accounts-db-config:ACCOUNTS_DB_URI \
            ledger-db-config:POSTGRES_PASSWORD ledger-db-config:SPRING_DATASOURCE_PASSWORD; do
  cm=${pair%%:*}; key=${pair##*:}
  kubectl -n boa patch configmap "$cm" --type=json -p "[{\"op\":\"remove\",\"path\":\"/data/${key}\"}]" 2>/dev/null || true
done

echo "== BoA: add the Secrets Provider init container to each workload, run it as the workload's own service account"
for row in "${BOA[@]}"; do
  read -r obj cm map <<<"$row"; name=${obj#*/}
  INIT=$(cat <<JSON
{ "name": "secrets-provider", "image": "${SP_IMAGE}", "imagePullPolicy": "IfNotPresent",
  "env": [
    { "name": "CONTAINER_MODE",      "value": "init" },
    { "name": "SECRETS_DESTINATION", "value": "k8s_secrets" },
    { "name": "K8S_SECRETS",         "value": "${name}-creds" },
    { "name": "JWT_TOKEN_PATH",      "value": "/var/run/secrets/tokens/jwt" },
    { "name": "MY_POD_NAME",      "valueFrom": { "fieldRef": { "fieldPath": "metadata.name" } } },
    { "name": "MY_POD_NAMESPACE", "valueFrom": { "fieldRef": { "fieldPath": "metadata.namespace" } } },
    { "name": "CONJUR_APPLIANCE_URL",   "valueFrom": { "configMapKeyRef": { "name": "conjur-connect", "key": "CONJUR_APPLIANCE_URL" } } },
    { "name": "CONJUR_AUTHN_URL",       "valueFrom": { "configMapKeyRef": { "name": "conjur-connect", "key": "CONJUR_AUTHN_URL" } } },
    { "name": "CONJUR_ACCOUNT",         "valueFrom": { "configMapKeyRef": { "name": "conjur-connect", "key": "CONJUR_ACCOUNT" } } },
    { "name": "CONJUR_SSL_CERTIFICATE", "valueFrom": { "configMapKeyRef": { "name": "conjur-connect", "key": "ssl-certificate" } } } ],
  "volumeMounts": [ { "name": "conjur-jwt", "mountPath": "/var/run/secrets/tokens", "readOnly": true } ] }
JSON
)
  kubectl -n boa get "$obj" -o json | jq \
    --arg sa "$name" --arg cm "$cm" --arg sec "${name}-creds" --arg ip "$CONJUR_IP" --arg host "$CONJUR_HOST" --argjson init "$INIT" '
    .spec.template.spec.serviceAccountName = $sa
    | .spec.template.spec.hostAliases = [ { ip: $ip, hostnames: [ $host ] } ]
    | .spec.template.spec.volumes = ((.spec.template.spec.volumes // []) | map(select(.name != "conjur-jwt"))
        + [ { name: "conjur-jwt", projected: { sources: [ { serviceAccountToken: { path: "jwt", audience: "conjur", expirationSeconds: 600 } } ] } } ])
    | .spec.template.spec.initContainers = ((.spec.template.spec.initContainers // []) | map(select(.name != "secrets-provider")) + [ $init ])
    | .spec.template.spec.containers |= map(
        if ((.envFrom // []) | map(.configMapRef.name) | index($cm)) != null
        then .envFrom = ((.envFrom | map(select(.secretRef.name != $sec))) + [ { secretRef: { name: $sec } } ])
        else . end)' \
  | kubectl replace -f -
done

for row in "${BOA[@]}"; do
  read -r obj _ _ <<<"$row"
  kubectl -n boa rollout status "$obj" --timeout=300s
done

echo "Bank of Anthos: every microservice now gets only its own secret, with its own identity."
