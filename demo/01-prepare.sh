#!/usr/bin/env bash
# Loop 1, live: moves both apps from hardcoded passwords to Secrets Manager. Run on VM1.
#   Bank of Anthos -> Secrets Provider init container per microservice, own identity each (apps unchanged)
#   Pet store      -> Secretless sidecar (app holds no password at all)
set -euo pipefail
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
cd "$(dirname "$0")"
source ../lab.env; source ../vm1-k8s/config.env      # settings only

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

# ---------------------------------------------------------------- PET STORE
echo "== Pet store 1. Secretless config: listen on localhost:5432 as the database, credentials from Secrets Manager"
kubectl -n petstore apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata: { name: secretless-config }
data:
  secretless.yml: |
    version: "2"
    services:
      petstore-db:
        connector: pg
        listenOn: tcp://localhost:5432
        credentials:
          host:     { from: conjur, get: prod/petstore/db/host }
          port:     { from: conjur, get: prod/petstore/db/port }
          username: { from: conjur, get: prod/petstore/db/username }
          password: { from: conjur, get: prod/petstore/db/password }
          sslmode: disable
YAML

echo "== Pet store 2. Redeploy: no password in the app, Secretless sidecar added (only it gets the conjur token)"
kubectl -n petstore apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: petstore }
spec:
  replicas: 1
  selector: { matchLabels: { app: petstore } }
  template:
    metadata: { labels: { app: petstore } }
    spec:
      serviceAccountName: petstore-app
      hostAliases: [ { ip: "${CONJUR_IP}", hostnames: [ "${CONJUR_HOST}" ] } ]
      containers:
      - name: app
        image: ${PET_IMAGE}
        env:
        - { name: DB_URL,      value: "postgresql://localhost:5432/${PET_DB_NAME}?sslmode=disable" }
        - { name: DB_USERNAME, value: "secretless" }   # placeholder, ignored by Secretless
        - { name: DB_PASSWORD, value: "" }             # no password in the app
        - { name: DB_PLATFORM, value: postgres }
        - { name: JAVA_TOOL_OPTIONS, value: "-XX:-UseContainerSupport -Xmx384m" }
        ports: [ { containerPort: 8080 } ]
        readinessProbe: { httpGet: { path: /pets, port: 8080 }, initialDelaySeconds: 20, periodSeconds: 5 }
      - name: secretless
        image: ${SECRETLESS_IMAGE}
        imagePullPolicy: IfNotPresent
        args: [ "-f", "/etc/secretless/secretless.yml" ]
        env:
        - { name: JWT_TOKEN_PATH, value: /var/run/secrets/tokens/jwt }
        - name: MY_POD_NAME
          valueFrom: { fieldRef: { fieldPath: metadata.name } }
        - name: MY_POD_NAMESPACE
          valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
        - name: MY_POD_IP
          valueFrom: { fieldRef: { fieldPath: status.podIP } }
        - name: CONJUR_APPLIANCE_URL
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } }
        - name: CONJUR_AUTHN_URL
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } }
        - name: CONJUR_ACCOUNT
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } }
        - name: CONJUR_SSL_CERTIFICATE
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } }
        volumeMounts:
        - { name: config, mountPath: /etc/secretless, readOnly: true }
        - { name: jwt, mountPath: /var/run/secrets/tokens, readOnly: true }
      volumes:
      - { name: config, configMap: { name: secretless-config } }
      - name: jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 3600 } } ]
YAML
kubectl -n petstore rollout status deploy/petstore --timeout=300s

echo; echo "Both apps migrated. Show it: ./10-show-secrets.sh"
