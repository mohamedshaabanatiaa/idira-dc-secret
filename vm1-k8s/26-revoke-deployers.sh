#!/usr/bin/env bash
# Revokes every CI deploy token at once: deletes the deployer service accounts.
# Kubernetes bound tokens die with their service account (bound to its UID), so any
# token already handed out stops working immediately, even before its 2h expiry.
# The values in Secrets Manager are overwritten too. ./25-cicd-deployers.sh re-issues.
source "$(dirname "$0")/lib.sh"
conjur_ready
log "Revoking CI deploy access"
k -n "$BOA_NS" delete sa,role,rolebinding jenkins-deployer --ignore-not-found >/dev/null
k -n "$PET_NS" delete sa,role,rolebinding gitlab-deployer --ignore-not-found >/dev/null
conjur variable set -i prod/cicd/jenkins-token -v "revoked" >/dev/null
conjur variable set -i prod/cicd/gitlab-token -v "revoked" >/dev/null
ok "jenkins-deployer and gitlab-deployer deleted: every token they issued is dead now"
