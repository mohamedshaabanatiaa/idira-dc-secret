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

log "Applying manifests (skipping loadgenerator), Google Cloud tracing/metrics off"
# The upstream manifests turn on Google Cloud Trace/Metrics, which crash off-GCP
# (DefaultCredentialsError). We flip them to "false" before applying, so every
# workload starts once, correctly, with no second rollout.
for f in "$SRC"/kubernetes-manifests/*.yaml; do
  [[ "$(basename "$f")" == "loadgenerator.yaml" ]] && continue
  python3 - "$f" <<'PYEOF' | k -n "$BOA_NS" apply -f -
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r'(- name: ENABLE_(?:TRACING|METRICS)\n\s+value: )"true"', r'\1"false"', s)
print(s)
PYEOF
done

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
