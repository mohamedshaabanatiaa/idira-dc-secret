#!/usr/bin/env bash
# Connects Jenkins and GitLab to Secrets Manager with JWT (no stored API keys).
# Prereqs: policies loaded (prod.yml, authenticators.yml), vm1-k8s/25-cicd-deployers.sh done,
#          Jenkins plugin configured for JWT (README).
source "$(dirname "$0")/../common/lib.sh"
conjur_ready
need jq; need curl
JENKINS_URL="http://${VM2_IP}:8080"
JENKINS_ISSUER="${JENKINS_ISSUER:-$JENKINS_URL}"

conjur_cert

log "Jenkins authenticator (keys pulled from the plugin's JWKS endpoint)"
JWKS=$(curl -s --fail "${JENKINS_URL}/jwtauth/conjur-jwk-set") \
  || die "no JWKS at ${JENKINS_URL}/jwtauth/conjur-jwk-set: configure the plugin for JWT first (README)"
conjur variable set -i conjur/authn-jwt/jenkins/public-keys -v "{\"type\":\"jwks\",\"value\":${JWKS}}"
conjur variable set -i conjur/authn-jwt/jenkins/issuer -v "$JENKINS_ISSUER"
conjur variable set -i conjur/authn-jwt/jenkins/token-app-property -v "jenkins_name"
conjur variable set -i conjur/authn-jwt/jenkins/identity-path -v "prod/jenkins"
conjur variable set -i conjur/authn-jwt/jenkins/audience -v "cyberark-conjur"   # Jenkins plugin default

log "GitLab authenticator (leader fetches gitlab.com keys itself)"
conjur variable set -i conjur/authn-jwt/gitlab/jwks-uri -v "https://gitlab.com/oauth/discovery/keys"
conjur variable set -i conjur/authn-jwt/gitlab/issuer -v "https://gitlab.com"
conjur variable set -i conjur/authn-jwt/gitlab/token-app-property -v "project_path"
conjur variable set -i conjur/authn-jwt/gitlab/identity-path -v "prod/gitlab"
conjur variable set -i conjur/authn-jwt/gitlab/audience -v "conjur"

ok "Done. If Jenkins auth fails with an issuer error, rerun with JENKINS_ISSUER='${JENKINS_URL}/'"
warn "The plugin rotates its signing key: set 'Signing Key Lifetime' to 10080 min, or rerun this script after a rotation."
