#!/usr/bin/env bash
# Run 30 to 60 min BEFORE the panel, on VM1.
# Puts both apps back to the hardcoded "before" state and revokes the CI deploy tokens.
set -euo pipefail
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
cd "$(dirname "$0")"
source ../lab.env; source ../vm1-k8s/config.env      # settings only: host names, original values

echo "== 1. Delete both apps"
kubectl delete namespace boa petstore --ignore-not-found --wait=true --timeout=300s

echo "== 2. Put the original values back in Secrets Manager"
conjur variable set -i prod/boa/accounts-db/password -v "$BOA_ACCOUNTS_PASS"
conjur variable set -i prod/boa/accounts-db/uri      -v "postgresql://${BOA_ACCOUNTS_USER}:${BOA_ACCOUNTS_PASS}@accounts-db:5432/${BOA_ACCOUNTS_DB}"
conjur variable set -i prod/boa/ledger-db/password   -v "$BOA_LEDGER_PASS"
conjur variable set -i prod/petstore/db/password     -v "$PET_DB_PASS"

echo "== 3. Reinstall both apps in their original, hardcoded state"
../vm1-k8s/10-install-boa.sh
../vm1-k8s/11-install-petstore.sh

echo "== 4. Give both namespaces the Secrets Manager address and certificate"
for ns in boa petstore; do
  kubectl -n "$ns" create configmap conjur-connect \
    --from-literal=CONJUR_APPLIANCE_URL="https://${CONJUR_HOST}" \
    --from-literal=CONJUR_AUTHN_URL="https://${CONJUR_HOST}/authn-jwt/k3s" \
    --from-literal=CONJUR_ACCOUNT="${CONJUR_ACCOUNT}" \
    --from-file=ssl-certificate=../.conjur-cert.pem \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo "== 5. Revoke CI deploy access: delete the deployer service accounts (their tokens die with them)"
kubectl -n boa      delete sa,role,rolebinding jenkins-deployer --ignore-not-found
kubectl -n petstore delete sa,role,rolebinding gitlab-deployer  --ignore-not-found
conjur variable set -i prod/cicd/jenkins-token -v revoked
conjur variable set -i prod/cicd/gitlab-token  -v revoked

echo; echo "Reset done. Next: ./02-preflight.sh (./01-prepare.sh runs live in Loop 1)"
