#!/usr/bin/env bash
# Run 10 min BEFORE the panel, on VM1. Checks everything is ready.
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

echo "== Clock (must match the Secrets Manager VM)"
date -u

echo "== Secrets Manager CLI logged in"
conjur whoami

echo "== Jenkins deploy access (must be revoked before the panel; ./30-jenkins.sh issues it live)"
kubectl -n boa get serviceaccount jenkins-deployer 2>/dev/null && echo "   still active: run ./00-reset.sh" || echo "   revoked, ok"

echo "== Pods (all must be Running)"
kubectl -n boa get pods
kubectl -n petstore get pods
kubectl -n agents get pods

echo; echo "Ready if all pods are Running. ./10-show-secrets.sh should show 3 of 3 HARDCODED (before Loop 1)."
