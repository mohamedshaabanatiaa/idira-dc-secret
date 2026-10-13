#!/usr/bin/env bash
# Creates one Kubernetes deployer identity per CI tool, each limited to one
# namespace, and stores a SHORT-LIVED token for each in Secrets Manager.
#   Jenkins -> can patch deployments in boa only
#   GitLab  -> can patch deployments in petstore only
# Secrets come from policies/prod.yml (prod/cicd/*).
# Re-run any time = rotation (new token, old one expires on its own).
#   TOKEN_TTL=2h ./25-cicd-deployers.sh
source "$(dirname "$0")/lib.sh"
TTL="${TOKEN_TTL:-2h}"


deployer() {  # deployer <sa-name> <namespace>
  cat <<YAML | k -n "$2" apply -f - >/dev/null
apiVersion: v1
kind: ServiceAccount
metadata: { name: $1 }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: $1 }
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "patch"]
- apiGroups: ["apps"]
  resources: ["replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: $1 }
subjects: [ { kind: ServiceAccount, name: $1 } ]
roleRef: { kind: Role, name: $1, apiGroup: rbac.authorization.k8s.io }
YAML
  ok "$1 can deploy in namespace $2 only"
}

log "Deployer identities in the cluster"
deployer jenkins-deployer "$BOA_NS"
deployer gitlab-deployer "$PET_NS"

log "Issuing ${TTL} tokens and storing them in Secrets Manager"
conjur_set prod/cicd/kube-server "https://${VM1_IP}:6443"
conjur_set prod/cicd/kube-ca "$(k config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)"
conjur_set prod/cicd/jenkins-token "$(k -n "$BOA_NS" create token jenkins-deployer --duration="$TTL")"
conjur_set prod/cicd/gitlab-token "$(k -n "$PET_NS" create token gitlab-deployer --duration="$TTL")"
ok "Tokens expire in ${TTL}. Nobody saw them, nothing stored in Jenkins or GitLab."
