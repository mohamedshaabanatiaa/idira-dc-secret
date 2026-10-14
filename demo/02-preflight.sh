#!/usr/bin/env bash
# Run 10 min BEFORE the panel, on VM1. Checks everything is ready.
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
echo "== clock (must match the Secrets Manager VM)"; date -u
echo "== Secrets Manager login"; conjur whoami
echo "== fresh 2h deploy tokens for Jenkins"; "$R/vm1-k8s/25-cicd-deployers.sh"
echo "== AI agents"; kubectl -n agents get pods
echo "== apps"; "$R/vm1-k8s/90-status.sh"
echo; echo "Ready if: all pods Running. Then ./10-show-secrets.sh should show NO passwords."
