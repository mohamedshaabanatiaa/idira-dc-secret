#!/usr/bin/env bash
# Installs Bank of Anthos in its ORIGINAL state: DB passwords hardcoded in ConfigMaps.
source "$(dirname "$0")/lib.sh"
SRC="$HERE/vendor/bank-of-anthos"

if [[ ! -d "$SRC" ]]; then
  log "Cloning Bank of Anthos ${BOA_VERSION}"
  git clone -q --depth 1 --branch "$BOA_VERSION" \
    https://github.com/GoogleCloudPlatform/bank-of-anthos.git "$SRC"
fi

log "Creating namespace ${BOA_NS}"
k create namespace "$BOA_NS" --dry-run=client -o yaml | k apply -f -

log "Applying JWT signing key (app login tokens, not a DB secret)"
k -n "$BOA_NS" apply -f "$SRC/extras/jwt/jwt-secret.yaml"

log "Applying manifests (skipping loadgenerator)"
for f in "$SRC"/kubernetes-manifests/*.yaml; do
  [[ "$(basename "$f")" == "loadgenerator.yaml" ]] && continue
  k -n "$BOA_NS" apply -f "$f"
done

log "Turning off Google Cloud tracing/metrics (they need GCP credentials and crash the pods off-GCP)"
for d in userservice contacts frontend; do
  k -n "$BOA_NS" set env deploy/$d ENABLE_TRACING=false ENABLE_METRICS=false >/dev/null
done
# Java (Spring) services: belt and braces, the GCP auto-config is switched off explicitly too
for d in ledgerwriter balancereader transactionhistory; do
  k -n "$BOA_NS" set env deploy/$d ENABLE_TRACING=false ENABLE_METRICS=false \
    SPRING_CLOUD_GCP_TRACE_ENABLED=false SPRING_SLEUTH_ENABLED=false \
    SPRING_CLOUD_GCP_CORE_ENABLED=false MANAGEMENT_TRACING_ENABLED=false >/dev/null
done
ok "tracing and metrics disabled"

log "Waiting for pods (first pull takes a few minutes)"
k -n "$BOA_NS" rollout status statefulset/accounts-db --timeout=600s
k -n "$BOA_NS" rollout status statefulset/ledger-db --timeout=600s
for d in userservice contacts ledgerwriter balancereader transactionhistory frontend; do
  k -n "$BOA_NS" rollout status deploy/$d --timeout=600s
done

log "Hardcoded secrets in the original install:"
k -n "$BOA_NS" get cm accounts-db-config ledger-db-config -o json \
  | jq -r '.items[] | .metadata.name as $n | .data | to_entries[] | select(.key|test("PASSWORD|URI|URL")) | "  \($n): \(.key)=\(.value)"'

IP=$(hostname -I | awk '{print $1}')
ok "Bank of Anthos: http://${IP}/   login testuser / bankofanthos"
