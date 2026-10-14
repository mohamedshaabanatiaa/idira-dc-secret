#!/usr/bin/env bash
# Deploys two AI agents as pods on k3s (run on VM1), each with its OWN signed
# identity (Kubernetes service account). No API key anywhere.
#   support-agent : Claude agent + Secretless sidecar that injects the Claude key
#   rogue-agent   : unapproved agent, same kind of identity, no access
# Prereqs: policies/prod.yml + authenticators.yml updated from Windows (agents layer).
source "$(dirname "$0")/../vm1-k8s/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
NS=agents
conjur_ready

log "Claude API key -> Secrets Manager (prod/ai/anthropic-api-key)"
if [[ "${1:-}" == "--new-key" ]] || ! conjur variable get -i prod/ai/anthropic-api-key >/dev/null 2>&1; then
  read -r -s -p "Paste the Claude API key (sk-ant-...): " AK; echo
  conjur variable set -i prod/ai/anthropic-api-key -v "$AK"; unset AK
else
  ok "already stored (use --new-key to replace)"
fi

log "Namespace, identities, code"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f - >/dev/null
publish_conjur_connect "$NS"
k -n "$NS" create serviceaccount support-agent --dry-run=client -o yaml | k apply -f - >/dev/null
k -n "$NS" create serviceaccount rogue-agent   --dry-run=client -o yaml | k apply -f - >/dev/null
k -n "$NS" create configmap agent-code --from-file="$HERE/app/" --dry-run=client -o yaml | k apply -f - >/dev/null
ok "service accounts support-agent, rogue-agent; code in configmap agent-code"

log "Secretless config: inject the Claude key into calls to api.anthropic.com only"
cat <<'YAML' | k -n "$NS" apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata: { name: secretless-claude }
data:
  secretless.yml: |
    version: "2"
    services:
      claude:
        connector: generic_http
        listenOn: tcp://localhost:8080
        credentials:
          apikey:
            from: conjur
            get: prod/ai/anthropic-api-key
        config:
          headers:
            x-api-key: "{{ .apikey }}"
          forceSSL: true
          upstreamURL: "http://api.anthropic.com"
          authenticateURLsMatching:
            - ^http://api\.anthropic\.com
YAML

agent_pod() {  # agent_pod <name> <service-account> <with-secretless:yes|no>
  local sidecar=""
  if [[ "$3" == yes ]]; then sidecar=$(cat <<YAML
      - name: secretless
        image: ${SECRETLESS_IMAGE}
        args: [ "-f", "/etc/secretless/secretless.yml" ]
        env:
        - { name: JWT_TOKEN_PATH, value: /var/run/secrets/tokens/jwt }
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
        - { name: secretless, mountPath: /etc/secretless, readOnly: true }
        - { name: jwt, mountPath: /var/run/secrets/tokens, readOnly: true }
YAML
); fi
  cat <<YAML | k -n "$NS" apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata: { name: $1 }
spec:
  replicas: 1
  selector: { matchLabels: { app: $1 } }
  template:
    metadata: { labels: { app: $1 } }
    spec:
      serviceAccountName: $2
      hostAliases: [ { ip: "${CONJUR_IP}", hostnames: [ "${CONJUR_HOST}" ] } ]
      containers:
      - name: agent
        image: python:3.12-slim
        command: [ "sh", "-c", "pip install -q --no-cache-dir anthropic requests && touch /tmp/ready && sleep infinity" ]
        workingDir: /app
        env:
        - { name: PETSTORE_URL, value: "http://petstore.${PET_NS}.svc.cluster.local:8080" }
        - { name: JWT_TOKEN_PATH, value: /var/run/secrets/tokens/jwt }
        - { name: PYTHONUNBUFFERED, value: "1" }
        - name: CONJUR_APPLIANCE_URL
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_APPLIANCE_URL } }
        - name: CONJUR_AUTHN_URL
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_AUTHN_URL } }
        - name: CONJUR_ACCOUNT
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: CONJUR_ACCOUNT } }
        - name: CONJUR_SSL_CERTIFICATE
          valueFrom: { configMapKeyRef: { name: conjur-connect, key: ssl-certificate } }
        readinessProbe:
          exec: { command: [ "test", "-f", "/tmp/ready" ] }
          periodSeconds: 5
        volumeMounts:
        - { name: code, mountPath: /app, readOnly: true }
        - { name: jwt, mountPath: /var/run/secrets/tokens, readOnly: true }
${sidecar}
      volumes:
      - name: code
        configMap: { name: agent-code }
      - name: secretless
        configMap: { name: secretless-claude }
      - name: jwt
        projected:
          sources:
          - serviceAccountToken: { path: jwt, audience: conjur, expirationSeconds: 3600 }
YAML
  ok "deployment $1 (identity: system:serviceaccount:${NS}:$2)"
}

log "Agents"
agent_pod support-agent support-agent yes
agent_pod rogue-agent   rogue-agent   no
k -n "$NS" rollout restart deploy/support-agent deploy/rogue-agent >/dev/null   # pick up code changes
k -n "$NS" rollout status deploy/support-agent --timeout=300s
k -n "$NS" rollout status deploy/rogue-agent --timeout=300s
ok "Ready. Chat: ./20-chat.sh   Rogue: ./21-rogue.sh   Kill switch: ./30-kill-switch.sh off|on"
