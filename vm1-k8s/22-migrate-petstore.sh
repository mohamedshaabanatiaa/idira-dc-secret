#!/usr/bin/env bash
# Pet store: hardcoded env -> Secretless Broker sidecar.
# The app connects to localhost:5432 with NO password. Secretless fetches the
# real credentials from Secrets Manager per connection, so a rotation needs
# no restart at all.
source "$(dirname "$0")/lib.sh"
NS="$PET_NS"
k -n "$NS" get cm conjur-connect >/dev/null 2>&1 || die "run 20-conjur-setup.sh first"

log "Secretless config: where to listen, which Secrets Manager paths to use"
cat <<YAML | k -n "$NS" apply -f -
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
          address:
            from: conjur
            get: bank/petstore/db/address
          username:
            from: conjur
            get: bank/petstore/db/username
          password:
            from: conjur
            get: bank/petstore/db/password
          sslmode: disable
YAML

log "Redeploying the app: credentials removed, Secretless sidecar added"
cat <<YAML | k -n "$NS" apply -f -
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
      hostAliases:
      - ip: "${CONJUR_IP}"
        hostnames: [ "${CONJUR_HOST}" ]
      containers:
      - name: app
        image: ${PET_IMAGE}
        env:
        - { name: DB_URL,      value: "postgresql://localhost:5432/${PET_DB_NAME}?sslmode=disable" }
        - { name: DB_USERNAME, value: "secretless" }   # placeholder, ignored by Secretless
        - { name: DB_PASSWORD, value: "" }             # no password in the app
        - { name: DB_PLATFORM, value: postgres }
        ports: [ { containerPort: 8080 } ]
        readinessProbe:
          httpGet: { path: /pets, port: 8080 }
          initialDelaySeconds: 20
          periodSeconds: 5
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
      - name: config
        configMap: { name: secretless-config }
      - name: jwt
        projected:
          sources:
          - serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 3600 }
YAML

if ! k -n "$NS" rollout status deploy/petstore --timeout=300s; then
  k -n "$NS" logs deploy/petstore -c secretless --tail=40 || true
  die "rollout failed (Secretless log above)"
fi

log "Proof: no credentials in the Deployment"
k -n "$NS" get deploy petstore -o json | jq -r '.spec.template.spec.containers[0].env[] | "  \(.name)=\(.value)"'
IP=$(hostname -I | awk '{print $1}')
ok "Pet store still serves data through Secretless:"
curl -s "http://${IP}:${PET_NODEPORT}/pets"; echo
