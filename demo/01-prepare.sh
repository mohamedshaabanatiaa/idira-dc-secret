#!/usr/bin/env bash
# Loop 1, live: moves both apps from hardcoded passwords to Secrets Manager. Run on VM1.
#   Bank of Anthos -> Secrets Provider job fills Kubernetes Secrets (apps unchanged)
#   Pet store      -> Secretless sidecar (app holds no password at all)
set -euo pipefail
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
cd "$(dirname "$0")"
source ../lab.env; source ../vm1-k8s/config.env      # settings only

# ---------------------------------------------------------------- BANK OF ANTHOS
echo "== BoA 1. Identity for the sync job: service account secrets-provider, may only update Secrets in boa"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: secrets-provider }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: secrets-provider }
rules: [ { apiGroups: [""], resources: ["secrets"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: secrets-provider }
subjects: [ { kind: ServiceAccount, name: secrets-provider } ]
roleRef: { kind: Role, name: secrets-provider, apiGroup: rbac.authorization.k8s.io }
YAML

echo "== BoA 2. Kubernetes Secrets that hold only a MAP to Secrets Manager paths, no values"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata: { name: accounts-db-creds }
stringData:
  conjur-map: |-
    POSTGRES_PASSWORD: prod/boa/accounts-db/password
    ACCOUNTS_DB_URI: prod/boa/accounts-db/uri
---
apiVersion: v1
kind: Secret
metadata: { name: ledger-db-creds }
stringData:
  conjur-map: |-
    POSTGRES_PASSWORD: prod/boa/ledger-db/password
    SPRING_DATASOURCE_PASSWORD: prod/boa/ledger-db/password
YAML

echo "== BoA 3. Secrets Provider job: logs in with its service account token (authn-jwt/k3s), writes the values"
kubectl -n boa delete job secrets-sync --ignore-not-found
kubectl -n boa apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata: { name: secrets-sync }
spec:
  backoffLimit: 0
  template:
    spec:
      serviceAccountName: secrets-provider
      restartPolicy: Never
      hostAliases: [ { ip: "${CONJUR_IP}", hostnames: [ "${CONJUR_HOST}" ] } ]
      containers:
      - name: secrets-provider
        image: ${SP_IMAGE}
        imagePullPolicy: IfNotPresent
        env:
        - { name: CONTAINER_MODE,      value: application }
        - { name: SECRETS_DESTINATION, value: k8s_secrets }
        - { name: K8S_SECRETS,         value: "accounts-db-creds,ledger-db-creds" }
        - { name: JWT_TOKEN_PATH,      value: /var/run/secrets/tokens/jwt }
        - name: MY_POD_NAME
          valueFrom: { fieldRef: { fieldPath: metadata.name } }
        - name: MY_POD_NAMESPACE
          valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
        - name: CONJUR_APPLIANCE_URL
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } }
        - name: CONJUR_AUTHN_URL
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } }
        - name: CONJUR_ACCOUNT
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } }
        - name: CONJUR_SSL_CERTIFICATE
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } }
        volumeMounts: [ { name: jwt, mountPath: /var/run/secrets/tokens, readOnly: true } ]
      volumes:
      - name: jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 } } ]
YAML
kubectl -n boa wait --for=condition=complete job/secrets-sync --timeout=120s

echo "== BoA 4. Remove the hardcoded passwords from the ConfigMaps"
for pair in accounts-db-config:POSTGRES_PASSWORD accounts-db-config:ACCOUNTS_DB_URI \
            ledger-db-config:POSTGRES_PASSWORD ledger-db-config:SPRING_DATASOURCE_PASSWORD; do
  cm=${pair%%:*}; key=${pair##*:}
  kubectl -n boa patch configmap "$cm" --type=json -p "[{\"op\":\"remove\",\"path\":\"/data/${key}\"}]" 2>/dev/null || true
done

echo "== BoA 5. Each workload reads the synced Secret next to its ConfigMap (envFrom). No code change"
for w in statefulset/accounts-db:accounts deployment/userservice:accounts deployment/contacts:accounts \
         statefulset/ledger-db:ledger deployment/ledgerwriter:ledger deployment/balancereader:ledger \
         deployment/transactionhistory:ledger; do
  obj=${w%%:*}; db=${w##*:}
  # find the container that already loads <db>-db-config, add the Secret to the same container
  i=$(kubectl -n boa get "$obj" -o json | jq -r --arg cm "${db}-db-config" \
      '.spec.template.spec.containers | to_entries[] | select(.value.envFrom // [] | map(.configMapRef.name) | index($cm)) | .key' | head -1)
  kubectl -n boa get "$obj" -o json | jq -e --arg s "${db}-db-creds" --argjson i "$i" \
      '.spec.template.spec.containers[$i].envFrom | map(.secretRef.name) | index($s)' >/dev/null && continue
  kubectl -n boa patch "$obj" --type=json \
    -p "[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/${i}/envFrom/-\",\"value\":{\"secretRef\":{\"name\":\"${db}-db-creds\"}}}]"
done
for w in statefulset/accounts-db statefulset/ledger-db deploy/userservice deploy/contacts \
         deploy/ledgerwriter deploy/balancereader deploy/transactionhistory; do
  kubectl -n boa rollout status "$w" --timeout=300s
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
