#!/usr/bin/env bash
# One-screen view for the demo: where do the credentials live right now?
source "$(dirname "$0")/lib.sh"
IP=$(hostname -I | awk '{print $1}')

log "Bank of Anthos (${BOA_NS})"
k -n "$BOA_NS" get pods -o wide 2>/dev/null | awk 'NR==1||/Running|Error|Crash|Pending/' || warn "not installed"
echo "  Credentials in ConfigMaps:"
k -n "$BOA_NS" get cm accounts-db-config ledger-db-config -o json 2>/dev/null \
  | jq -r '.items[] | .metadata.name as $n | .data|to_entries[]|select(.key|test("PASSWORD|URI"))|"    \($n): \(.key)=\(.value)"' \
  | grep . || echo "    none"
echo "  Secrets synced from Secrets Manager:"
k -n "$BOA_NS" get secret accounts-db-creds userservice-creds contacts-creds ledger-db-creds ledgerwriter-creds balancereader-creds transactionhistory-creds 2>/dev/null | sed 's/^/    /' || echo "    none"
echo "  URL: http://${IP}/  (testuser / bankofanthos)"

log "Pet store (${PET_NS})"
k -n "$PET_NS" get pods 2>/dev/null || warn "not installed"
echo "  App env:"
k -n "$PET_NS" get deploy petstore -o json 2>/dev/null | jq -r '.spec.template.spec.containers[0].env[]|select(.name|test("USER|PASS"))|"    \(.name)=\(.value)"'
echo "  Containers: $(k -n "$PET_NS" get deploy petstore -o jsonpath='{.spec.template.spec.containers[*].name}' 2>/dev/null)"
echo "  URL: http://${IP}:${PET_NODEPORT}/pets"
