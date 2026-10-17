#!/usr/bin/env bash
# Runs the Secrets Provider once: authenticates to Secrets Manager with the
# pod's service account JWT and fills accounts-db-creds / ledger-db-creds.
source "$(dirname "$0")/lib.sh"
NS="$BOA_NS"

log "Running Secrets Provider job (authn-jwt/${AUTHN_ID})"
k -n "$NS" delete job secrets-sync --ignore-not-found >/dev/null
cat <<YAML | k -n "$NS" apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: secrets-sync }
spec:
  backoffLimit: 0
  template:
    metadata: { labels: { app: secrets-sync } }
    spec:
      serviceAccountName: secrets-provider
      restartPolicy: Never
      hostAliases:
      - ip: "${CONJUR_IP}"
        hostnames: [ "${CONJUR_HOST}" ]
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
        volumeMounts:
        - { name: jwt, mountPath: /var/run/secrets/tokens, readOnly: true }
        securityContext:
          allowPrivilegeEscalation: false
          capabilities: { drop: [ ALL ] }
      volumes:
      - name: jwt
        projected:
          sources:
          - serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 600 }
YAML

if ! k -n "$NS" wait --for=condition=complete job/secrets-sync --timeout=120s; then
  k -n "$NS" logs job/secrets-sync --tail=50 || true
  die "sync failed (see log above). Common causes: authenticator not allowlisted, cert hostname, API prefix"
fi
k -n "$NS" logs job/secrets-sync --tail=5 || true
for s in accounts-db-creds ledger-db-creds; do
  ok "$s keys: $(k -n "$NS" get secret $s -o json | jq -r '.data|keys|join(", ")')"
done
