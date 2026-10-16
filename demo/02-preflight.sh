#!/usr/bin/env bash
# Run 10 min BEFORE the panel, on VM1. Checks everything is ready.
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
echo "== clock (must match the Secrets Manager VM)"; date -u
echo "== Secrets Manager login"; conjur whoami
echo "== Jenkins deploy access (must be revoked before the panel; ./30-jenkins.sh issues it live)"
if kubectl -n boa get sa jenkins-deployer >/dev/null 2>&1; then echo "   still active: run $R/vm1-k8s/26-revoke-deployers.sh"; else echo "   revoked, ok"; fi
echo "== AI agents"; kubectl -n agents get pods
echo "== apps"; "$R/vm1-k8s/90-status.sh"
echo; echo "Ready if: all pods Running. Then ./10-show-secrets.sh should show NO passwords."
