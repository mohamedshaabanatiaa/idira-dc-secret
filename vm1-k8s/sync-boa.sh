#!/usr/bin/env bash
# Bank of Anthos refresh: restart the workloads. Each pod's Secrets Provider init
# container logs in with its own service account and fetches its secret again.
# (Was a shared sync Job before 19 Oct; now one identity per microservice.)
set -euo pipefail
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
APPS="${*:-userservice contacts ledgerwriter balancereader transactionhistory}"
for d in $APPS; do kubectl -n boa rollout restart deploy/$d; done
for d in $APPS; do kubectl -n boa rollout status  deploy/$d --timeout=300s; done
