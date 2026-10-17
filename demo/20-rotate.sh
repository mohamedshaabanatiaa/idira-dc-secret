#!/usr/bin/env bash
# Loop 2: rotate the pet store database password. Same pod, no restart. Run on VM1.
set -euo pipefail
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
NEW=$(openssl rand -hex 16)   # new password: 32 random hex characters, generated here, never printed
POD=$(kubectl -n petstore get pod -l app=petstore -o jsonpath='{.items[0].metadata.name}')
IP=$(hostname -I | awk '{print $1}')

HASH="select substr(rolpassword,1,40) from pg_authid where rolname='test_app';"   # stored hash, not the password

echo "== Pod before: $POD"
echo "== Password hash in the database BEFORE:"
kubectl -n petstore exec petstore-db-0 -- psql -U test_app -d test_app -tAc "$HASH"

echo "== 1. Change the password in the database (PostgreSQL)"
kubectl -n petstore exec petstore-db-0 -- psql -U test_app -d test_app -qc "ALTER ROLE test_app WITH PASSWORD '${NEW}';"

echo "== Password hash in the database AFTER (different = the password really changed):"
kubectl -n petstore exec petstore-db-0 -- psql -U test_app -d test_app -tAc "$HASH"

echo "== 2. Store the new password in Secrets Manager (new version, audited)"
conjur variable set -i prod/petstore/db/password -v "$NEW"

echo "== 3. Drop open database connections, so every query now uses the new password"
kubectl -n petstore exec petstore-db-0 -- psql -U test_app -d test_app -qtc \
  "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND usename='test_app';"

echo "== 4. Proof: the app still answers, from the same pod"
sleep 3
for _ in 1 2 3; do curl -s -o /dev/null -w "   GET /pets -> %{http_code}\n" "http://${IP}:30080/pets"; sleep 1; done
kubectl -n petstore get pod "$POD" -o custom-columns=POD:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount
