#!/usr/bin/env bash
# Connects Jenkins and GitLab to Secrets Manager with JWT (no stored API keys).
# Prereqs: policies loaded (bank.yml, authn.yml), vm1-k8s/25-cicd-deployers.sh done,
#          Jenkins plugin configured for JWT (README).
source "$(dirname "$0")/../common/lib.sh"
need jq; need curl
JENKINS_URL="http://${VM2_IP}:8080"
JENKINS_ISSUER="${JENKINS_ISSUER:-$JENKINS_URL}"

conjur_cert

log "Jenkins authenticator (keys pulled from the plugin's JWKS endpoint)"
JWKS=$(curl -s --fail "${JENKINS_URL}/jwtauth/conjur-jwk-set") \
  || die "no JWKS at ${JENKINS_URL}/jwtauth/conjur-jwk-set: configure the plugin for JWT first (README)"
conjur_set conjur/authn-jwt/jenkins/public-keys "{\"type\":\"jwks\",\"value\":${JWKS}}"
conjur_set conjur/authn-jwt/jenkins/issuer "$JENKINS_ISSUER"
conjur_set conjur/authn-jwt/jenkins/token-app-property "jenkins_name"
conjur_set conjur/authn-jwt/jenkins/identity-path "prod/jenkins"
conjur_set conjur/authn-jwt/jenkins/audience "conjur"

log "GitLab authenticator (leader fetches gitlab.com keys itself)"
conjur_set conjur/authn-jwt/gitlab/jwks-uri "https://gitlab.com/oauth/discovery/keys"
conjur_set conjur/authn-jwt/gitlab/issuer "https://gitlab.com"
conjur_set conjur/authn-jwt/gitlab/token-app-property "project_path"
conjur_set conjur/authn-jwt/gitlab/identity-path "prod/gitlab"
conjur_set conjur/authn-jwt/gitlab/audience "conjur"

ok "Done. If Jenkins auth fails with an issuer error, rerun with JENKINS_ISSUER='${JENKINS_URL}/'"
warn "The plugin rotates its signing key: set 'Signing Key Lifetime' to 10080 min, or rerun this script after a rotation."
