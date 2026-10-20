#!/usr/bin/env bash
# Loop 1, live: moves both apps from hard-coded passwords to Secrets Manager. Run on VM1.
#   Part 1  Pet store       -> Secretless sidecar. The app holds no password at all.
#   Part 2  Bank of Anthos  -> each microservice has its own identity (service account).
#                              A Secrets Provider init container fetches only its own secret.
# Plain commands, one block per microservice. (Older loop version: 01-prepare-loop.sh)
set -euo pipefail
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
cd "$(dirname "$0")"

# ================================================================ PART 1: PET STORE (Secretless)
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
      hostAliases: [ { ip: "10.0.0.2", hostnames: [ "conjur-leader.bank.local" ] } ]
      containers:
      - name: app
        image: cyberark/demo-app:latest
        env:
        - { name: DB_URL,      value: "postgresql://localhost:5432/test_app?sslmode=disable" }
        - { name: DB_USERNAME, value: "secretless" }   # placeholder, ignored by Secretless
        - { name: DB_PASSWORD, value: "" }             # no password in the app
        - { name: DB_PLATFORM, value: postgres }
        - { name: JAVA_TOOL_OPTIONS, value: "-XX:-UseContainerSupport -Xmx384m" }
        ports: [ { containerPort: 8080 } ]
        readinessProbe: { httpGet: { path: /pets, port: 8080 }, initialDelaySeconds: 20, periodSeconds: 5 }
      - name: secretless
        image: cyberark/secretless-broker:latest
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


# ================================================================ PART 2: BANK OF ANTHOS (Secrets Provider)
echo "== BoA 1. Policy as code: one identity + one permit per microservice"
conjur whoami >/dev/null || { echo "   Secrets Manager CLI not logged in: conjur login -i admin"; exit 1; }
conjur policy update -b prod -f ../policies/prod.yml >/dev/null
conjur policy update -b prod -f ../policies/once-boa-per-service.yml >/dev/null 2>&1 || true   # no-op once done
echo "   identities loaded"

echo "== BoA 2. Remove the hard-coded passwords from the ConfigMaps"
kubectl -n boa patch configmap accounts-db-config --type=json -p '[{"op":"remove","path":"/data/POSTGRES_PASSWORD"}]' 2>/dev/null || true
kubectl -n boa patch configmap accounts-db-config --type=json -p '[{"op":"remove","path":"/data/ACCOUNTS_DB_URI"}]' 2>/dev/null || true
kubectl -n boa patch configmap ledger-db-config   --type=json -p '[{"op":"remove","path":"/data/POSTGRES_PASSWORD"}]' 2>/dev/null || true
kubectl -n boa patch configmap ledger-db-config   --type=json -p '[{"op":"remove","path":"/data/SPRING_DATASOURCE_PASSWORD"}]' 2>/dev/null || true

# ---------------------------------------------------------------- accounts-db (accounts database)
echo "== BoA 3. accounts-db: own service account, own Secret (map only), may update only that Secret"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: accounts-db }
---
apiVersion: v1
kind: Secret
metadata: { name: accounts-db-creds }
stringData:
  conjur-map: "POSTGRES_PASSWORD: prod/boa/accounts-db/password"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: accounts-db-creds }
rules: [ { apiGroups: [""], resources: ["secrets"], resourceNames: ["accounts-db-creds"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: accounts-db-creds }
subjects: [ { kind: ServiceAccount, name: accounts-db } ]
roleRef: { kind: Role, name: accounts-db-creds, apiGroup: rbac.authorization.k8s.io }
YAML

echo "   accounts-db: run as its service account, add the Secrets Provider init container, app reads POSTGRES_PASSWORD from its Secret"
kubectl -n boa patch statefulset accounts-db --type=strategic -p "$(cat <<YAML
spec:
  template:
    spec:
      serviceAccountName: accounts-db
      hostAliases: [ { ip: "10.0.0.2", hostnames: [ "conjur-leader.bank.local" ] } ]
      initContainers:
      - name: secrets-provider
        image: cyberark/secrets-provider-for-k8s:1.11.1
        imagePullPolicy: IfNotPresent
        env:
        - { name: CONTAINER_MODE,      value: init }
        - { name: SECRETS_DESTINATION, value: k8s_secrets }
        - { name: K8S_SECRETS,         value: accounts-db-creds }
        - { name: JWT_TOKEN_PATH,      value: /var/run/secrets/tokens/jwt }
        - { name: MY_POD_NAME,      valueFrom: { fieldRef: { fieldPath: metadata.name } } }
        - { name: MY_POD_NAMESPACE, valueFrom: { fieldRef: { fieldPath: metadata.namespace } } }
        - { name: CONJUR_APPLIANCE_URL,   valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } } }
        - { name: CONJUR_AUTHN_URL,       valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } } }
        - { name: CONJUR_ACCOUNT,         valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } } }
        - { name: CONJUR_SSL_CERTIFICATE, valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } } }
        volumeMounts: [ { name: conjur-jwt, mountPath: /var/run/secrets/tokens, readOnly: true } ]
      containers:
      - name: accounts-db
        env:
        - { name: POSTGRES_PASSWORD, valueFrom: { secretKeyRef: { name: accounts-db-creds, key: POSTGRES_PASSWORD } } }
      volumes:
      - name: conjur-jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 } } ]
YAML
)"

# ---------------------------------------------------------------- userservice (login service)
echo "== BoA 4. userservice: own service account, own Secret (map only), may update only that Secret"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: userservice }
---
apiVersion: v1
kind: Secret
metadata: { name: userservice-creds }
stringData:
  conjur-map: "ACCOUNTS_DB_URI: prod/boa/accounts-db/uri"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: userservice-creds }
rules: [ { apiGroups: [""], resources: ["secrets"], resourceNames: ["userservice-creds"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: userservice-creds }
subjects: [ { kind: ServiceAccount, name: userservice } ]
roleRef: { kind: Role, name: userservice-creds, apiGroup: rbac.authorization.k8s.io }
YAML

echo "   userservice: run as its service account, add the Secrets Provider init container, app reads ACCOUNTS_DB_URI from its Secret"
kubectl -n boa patch deployment userservice --type=strategic -p "$(cat <<YAML
spec:
  template:
    spec:
      serviceAccountName: userservice
      hostAliases: [ { ip: "10.0.0.2", hostnames: [ "conjur-leader.bank.local" ] } ]
      initContainers:
      - name: secrets-provider
        image: cyberark/secrets-provider-for-k8s:1.11.1
        imagePullPolicy: IfNotPresent
        env:
        - { name: CONTAINER_MODE,      value: init }
        - { name: SECRETS_DESTINATION, value: k8s_secrets }
        - { name: K8S_SECRETS,         value: userservice-creds }
        - { name: JWT_TOKEN_PATH,      value: /var/run/secrets/tokens/jwt }
        - { name: MY_POD_NAME,      valueFrom: { fieldRef: { fieldPath: metadata.name } } }
        - { name: MY_POD_NAMESPACE, valueFrom: { fieldRef: { fieldPath: metadata.namespace } } }
        - { name: CONJUR_APPLIANCE_URL,   valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } } }
        - { name: CONJUR_AUTHN_URL,       valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } } }
        - { name: CONJUR_ACCOUNT,         valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } } }
        - { name: CONJUR_SSL_CERTIFICATE, valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } } }
        volumeMounts: [ { name: conjur-jwt, mountPath: /var/run/secrets/tokens, readOnly: true } ]
      containers:
      - name: userservice
        env:
        - { name: ACCOUNTS_DB_URI, valueFrom: { secretKeyRef: { name: userservice-creds, key: ACCOUNTS_DB_URI } } }
      volumes:
      - name: conjur-jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 } } ]
YAML
)"

# ---------------------------------------------------------------- contacts (contacts service)
echo "== BoA 5. contacts: own service account, own Secret (map only), may update only that Secret"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: contacts }
---
apiVersion: v1
kind: Secret
metadata: { name: contacts-creds }
stringData:
  conjur-map: "ACCOUNTS_DB_URI: prod/boa/accounts-db/uri"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: contacts-creds }
rules: [ { apiGroups: [""], resources: ["secrets"], resourceNames: ["contacts-creds"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: contacts-creds }
subjects: [ { kind: ServiceAccount, name: contacts } ]
roleRef: { kind: Role, name: contacts-creds, apiGroup: rbac.authorization.k8s.io }
YAML

echo "   contacts: run as its service account, add the Secrets Provider init container, app reads ACCOUNTS_DB_URI from its Secret"
kubectl -n boa patch deployment contacts --type=strategic -p "$(cat <<YAML
spec:
  template:
    spec:
      serviceAccountName: contacts
      hostAliases: [ { ip: "10.0.0.2", hostnames: [ "conjur-leader.bank.local" ] } ]
      initContainers:
      - name: secrets-provider
        image: cyberark/secrets-provider-for-k8s:1.11.1
        imagePullPolicy: IfNotPresent
        env:
        - { name: CONTAINER_MODE,      value: init }
        - { name: SECRETS_DESTINATION, value: k8s_secrets }
        - { name: K8S_SECRETS,         value: contacts-creds }
        - { name: JWT_TOKEN_PATH,      value: /var/run/secrets/tokens/jwt }
        - { name: MY_POD_NAME,      valueFrom: { fieldRef: { fieldPath: metadata.name } } }
        - { name: MY_POD_NAMESPACE, valueFrom: { fieldRef: { fieldPath: metadata.namespace } } }
        - { name: CONJUR_APPLIANCE_URL,   valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } } }
        - { name: CONJUR_AUTHN_URL,       valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } } }
        - { name: CONJUR_ACCOUNT,         valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } } }
        - { name: CONJUR_SSL_CERTIFICATE, valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } } }
        volumeMounts: [ { name: conjur-jwt, mountPath: /var/run/secrets/tokens, readOnly: true } ]
      containers:
      - name: contacts
        env:
        - { name: ACCOUNTS_DB_URI, valueFrom: { secretKeyRef: { name: contacts-creds, key: ACCOUNTS_DB_URI } } }
      volumes:
      - name: conjur-jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 } } ]
YAML
)"

# ---------------------------------------------------------------- ledger-db (ledger database)
echo "== BoA 6. ledger-db: own service account, own Secret (map only), may update only that Secret"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: ledger-db }
---
apiVersion: v1
kind: Secret
metadata: { name: ledger-db-creds }
stringData:
  conjur-map: "POSTGRES_PASSWORD: prod/boa/ledger-db/password"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ledger-db-creds }
rules: [ { apiGroups: [""], resources: ["secrets"], resourceNames: ["ledger-db-creds"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: ledger-db-creds }
subjects: [ { kind: ServiceAccount, name: ledger-db } ]
roleRef: { kind: Role, name: ledger-db-creds, apiGroup: rbac.authorization.k8s.io }
YAML

echo "   ledger-db: run as its service account, add the Secrets Provider init container, app reads POSTGRES_PASSWORD from its Secret"
kubectl -n boa patch statefulset ledger-db --type=strategic -p "$(cat <<YAML
spec:
  template:
    spec:
      serviceAccountName: ledger-db
      hostAliases: [ { ip: "10.0.0.2", hostnames: [ "conjur-leader.bank.local" ] } ]
      initContainers:
      - name: secrets-provider
        image: cyberark/secrets-provider-for-k8s:1.11.1
        imagePullPolicy: IfNotPresent
        env:
        - { name: CONTAINER_MODE,      value: init }
        - { name: SECRETS_DESTINATION, value: k8s_secrets }
        - { name: K8S_SECRETS,         value: ledger-db-creds }
        - { name: JWT_TOKEN_PATH,      value: /var/run/secrets/tokens/jwt }
        - { name: MY_POD_NAME,      valueFrom: { fieldRef: { fieldPath: metadata.name } } }
        - { name: MY_POD_NAMESPACE, valueFrom: { fieldRef: { fieldPath: metadata.namespace } } }
        - { name: CONJUR_APPLIANCE_URL,   valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } } }
        - { name: CONJUR_AUTHN_URL,       valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } } }
        - { name: CONJUR_ACCOUNT,         valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } } }
        - { name: CONJUR_SSL_CERTIFICATE, valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } } }
        volumeMounts: [ { name: conjur-jwt, mountPath: /var/run/secrets/tokens, readOnly: true } ]
      containers:
      - name: postgres
        env:
        - { name: POSTGRES_PASSWORD, valueFrom: { secretKeyRef: { name: ledger-db-creds, key: POSTGRES_PASSWORD } } }
      volumes:
      - name: conjur-jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 } } ]
YAML
)"

# ---------------------------------------------------------------- ledgerwriter (payments)
echo "== BoA 7. ledgerwriter: own service account, own Secret (map only), may update only that Secret"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: ledgerwriter }
---
apiVersion: v1
kind: Secret
metadata: { name: ledgerwriter-creds }
stringData:
  conjur-map: "SPRING_DATASOURCE_PASSWORD: prod/boa/ledger-db/password"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ledgerwriter-creds }
rules: [ { apiGroups: [""], resources: ["secrets"], resourceNames: ["ledgerwriter-creds"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: ledgerwriter-creds }
subjects: [ { kind: ServiceAccount, name: ledgerwriter } ]
roleRef: { kind: Role, name: ledgerwriter-creds, apiGroup: rbac.authorization.k8s.io }
YAML

echo "   ledgerwriter: run as its service account, add the Secrets Provider init container, app reads SPRING_DATASOURCE_PASSWORD from its Secret"
kubectl -n boa patch deployment ledgerwriter --type=strategic -p "$(cat <<YAML
spec:
  template:
    spec:
      serviceAccountName: ledgerwriter
      hostAliases: [ { ip: "10.0.0.2", hostnames: [ "conjur-leader.bank.local" ] } ]
      initContainers:
      - name: secrets-provider
        image: cyberark/secrets-provider-for-k8s:1.11.1
        imagePullPolicy: IfNotPresent
        env:
        - { name: CONTAINER_MODE,      value: init }
        - { name: SECRETS_DESTINATION, value: k8s_secrets }
        - { name: K8S_SECRETS,         value: ledgerwriter-creds }
        - { name: JWT_TOKEN_PATH,      value: /var/run/secrets/tokens/jwt }
        - { name: MY_POD_NAME,      valueFrom: { fieldRef: { fieldPath: metadata.name } } }
        - { name: MY_POD_NAMESPACE, valueFrom: { fieldRef: { fieldPath: metadata.namespace } } }
        - { name: CONJUR_APPLIANCE_URL,   valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } } }
        - { name: CONJUR_AUTHN_URL,       valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } } }
        - { name: CONJUR_ACCOUNT,         valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } } }
        - { name: CONJUR_SSL_CERTIFICATE, valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } } }
        volumeMounts: [ { name: conjur-jwt, mountPath: /var/run/secrets/tokens, readOnly: true } ]
      containers:
      - name: ledgerwriter
        env:
        - { name: SPRING_DATASOURCE_PASSWORD, valueFrom: { secretKeyRef: { name: ledgerwriter-creds, key: SPRING_DATASOURCE_PASSWORD } } }
      volumes:
      - name: conjur-jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 } } ]
YAML
)"

# ---------------------------------------------------------------- balancereader (balances)
echo "== BoA 8. balancereader: own service account, own Secret (map only), may update only that Secret"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: balancereader }
---
apiVersion: v1
kind: Secret
metadata: { name: balancereader-creds }
stringData:
  conjur-map: "SPRING_DATASOURCE_PASSWORD: prod/boa/ledger-db/password"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: balancereader-creds }
rules: [ { apiGroups: [""], resources: ["secrets"], resourceNames: ["balancereader-creds"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: balancereader-creds }
subjects: [ { kind: ServiceAccount, name: balancereader } ]
roleRef: { kind: Role, name: balancereader-creds, apiGroup: rbac.authorization.k8s.io }
YAML

echo "   balancereader: run as its service account, add the Secrets Provider init container, app reads SPRING_DATASOURCE_PASSWORD from its Secret"
kubectl -n boa patch deployment balancereader --type=strategic -p "$(cat <<YAML
spec:
  template:
    spec:
      serviceAccountName: balancereader
      hostAliases: [ { ip: "10.0.0.2", hostnames: [ "conjur-leader.bank.local" ] } ]
      initContainers:
      - name: secrets-provider
        image: cyberark/secrets-provider-for-k8s:1.11.1
        imagePullPolicy: IfNotPresent
        env:
        - { name: CONTAINER_MODE,      value: init }
        - { name: SECRETS_DESTINATION, value: k8s_secrets }
        - { name: K8S_SECRETS,         value: balancereader-creds }
        - { name: JWT_TOKEN_PATH,      value: /var/run/secrets/tokens/jwt }
        - { name: MY_POD_NAME,      valueFrom: { fieldRef: { fieldPath: metadata.name } } }
        - { name: MY_POD_NAMESPACE, valueFrom: { fieldRef: { fieldPath: metadata.namespace } } }
        - { name: CONJUR_APPLIANCE_URL,   valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } } }
        - { name: CONJUR_AUTHN_URL,       valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } } }
        - { name: CONJUR_ACCOUNT,         valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } } }
        - { name: CONJUR_SSL_CERTIFICATE, valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } } }
        volumeMounts: [ { name: conjur-jwt, mountPath: /var/run/secrets/tokens, readOnly: true } ]
      containers:
      - name: balancereader
        env:
        - { name: SPRING_DATASOURCE_PASSWORD, valueFrom: { secretKeyRef: { name: balancereader-creds, key: SPRING_DATASOURCE_PASSWORD } } }
      volumes:
      - name: conjur-jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 } } ]
YAML
)"

# ---------------------------------------------------------------- transactionhistory (history)
echo "== BoA 9. transactionhistory: own service account, own Secret (map only), may update only that Secret"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: transactionhistory }
---
apiVersion: v1
kind: Secret
metadata: { name: transactionhistory-creds }
stringData:
  conjur-map: "SPRING_DATASOURCE_PASSWORD: prod/boa/ledger-db/password"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: transactionhistory-creds }
rules: [ { apiGroups: [""], resources: ["secrets"], resourceNames: ["transactionhistory-creds"], verbs: ["get", "update"] } ]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: transactionhistory-creds }
subjects: [ { kind: ServiceAccount, name: transactionhistory } ]
roleRef: { kind: Role, name: transactionhistory-creds, apiGroup: rbac.authorization.k8s.io }
YAML

echo "   transactionhistory: run as its service account, add the Secrets Provider init container, app reads SPRING_DATASOURCE_PASSWORD from its Secret"
kubectl -n boa patch deployment transactionhistory --type=strategic -p "$(cat <<YAML
spec:
  template:
    spec:
      serviceAccountName: transactionhistory
      hostAliases: [ { ip: "10.0.0.2", hostnames: [ "conjur-leader.bank.local" ] } ]
      initContainers:
      - name: secrets-provider
        image: cyberark/secrets-provider-for-k8s:1.11.1
        imagePullPolicy: IfNotPresent
        env:
        - { name: CONTAINER_MODE,      value: init }
        - { name: SECRETS_DESTINATION, value: k8s_secrets }
        - { name: K8S_SECRETS,         value: transactionhistory-creds }
        - { name: JWT_TOKEN_PATH,      value: /var/run/secrets/tokens/jwt }
        - { name: MY_POD_NAME,      valueFrom: { fieldRef: { fieldPath: metadata.name } } }
        - { name: MY_POD_NAMESPACE, valueFrom: { fieldRef: { fieldPath: metadata.namespace } } }
        - { name: CONJUR_APPLIANCE_URL,   valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } } }
        - { name: CONJUR_AUTHN_URL,       valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } } }
        - { name: CONJUR_ACCOUNT,         valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } } }
        - { name: CONJUR_SSL_CERTIFICATE, valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } } }
        volumeMounts: [ { name: conjur-jwt, mountPath: /var/run/secrets/tokens, readOnly: true } ]
      containers:
      - name: transactionhistory
        env:
        - { name: SPRING_DATASOURCE_PASSWORD, valueFrom: { secretKeyRef: { name: transactionhistory-creds, key: SPRING_DATASOURCE_PASSWORD } } }
      volumes:
      - name: conjur-jwt
        projected:
          sources: [ { serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 } } ]
YAML
)"

echo "== BoA 10. Wait for the rollouts (each pod: init container fetches, then the app starts)"
kubectl -n boa rollout status statefulset/accounts-db        --timeout=300s
kubectl -n boa rollout status statefulset/ledger-db          --timeout=300s
kubectl -n boa rollout status deployment/userservice         --timeout=300s
kubectl -n boa rollout status deployment/contacts            --timeout=300s
kubectl -n boa rollout status deployment/ledgerwriter        --timeout=300s
kubectl -n boa rollout status deployment/balancereader       --timeout=300s
kubectl -n boa rollout status deployment/transactionhistory  --timeout=300s

echo; echo "Both apps migrated. Show it: ./10-show-secrets.sh"
