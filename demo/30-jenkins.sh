#!/usr/bin/env bash
# Jenkins, live: after ./00-reset.sh the pipeline has NO deploy access. Build once (fails),
# run this (issues a 2-hour deploy token into Secrets Manager), build again (works). Run on VM1.
set -euo pipefail
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

echo "== 1. Deployer identity in Kubernetes: jenkins-deployer, may change deployments in boa ONLY"
kubectl -n boa apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: jenkins-deployer }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: jenkins-deployer }
rules:
- { apiGroups: ["apps"], resources: ["deployments"], verbs: ["get", "list", "watch", "patch"] }
- { apiGroups: ["apps"], resources: ["replicasets"], verbs: ["get", "list", "watch"] }
- { apiGroups: [""], resources: ["pods"], verbs: ["get", "list"] }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: jenkins-deployer }
subjects: [ { kind: ServiceAccount, name: jenkins-deployer } ]
roleRef: { kind: Role, name: jenkins-deployer, apiGroup: rbac.authorization.k8s.io }
YAML

echo "== 2. Issue a token that expires in 2 hours, straight into Secrets Manager (nobody sees it)"
conjur variable set -i prod/cicd/kube-server   -v "https://$(hostname -I | awk '{print $1}'):6443"
conjur variable set -i prod/cicd/kube-ca       -v "$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)"
conjur variable set -i prod/cicd/jenkins-token -v "$(kubectl -n boa create token jenkins-deployer --duration=2h)"

cat <<TXT

Now in Jenkins: http://10.0.0.1:8080 -> idira / boa-deploy -> Build with Parameters
The console log shows: JWT login to Secrets Manager, the 2h token fetched,
bank name changed, then the pet store namespace: Forbidden.
TXT
