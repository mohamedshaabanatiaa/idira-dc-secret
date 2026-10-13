#!/usr/bin/env bash
# Installs a GitLab runner (shell executor) on VM2. Outbound only: the runner
# polls gitlab.com, nothing connects in.
#   ./11-install-gitlab-runner.sh            (prompts for the runner token)
# Get the token: GitLab project > Settings > CI/CD > Runners > New project runner,
# tag "idira-vm2", copy the glrt-... token.
source "$(dirname "$0")/../common/lib.sh"
[[ $EUID -eq 0 ]] || die "run as root"
ensure_hosts_entry

if ! command -v gitlab-runner >/dev/null; then
  log "Installing gitlab-runner binary"
  curl -sL -o /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
  chmod +x /usr/local/bin/gitlab-runner
  id gitlab-runner >/dev/null 2>&1 || useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
  gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
  gitlab-runner start
fi
rm -f /home/gitlab-runner/.bash_logout   # known Ubuntu issue that breaks shell jobs
ok "$(gitlab-runner --version | head -1)"

log "Installing conjur-fetch helper and leader cert for jobs"
install -m 0755 "$(dirname "$0")/bin/conjur-fetch" /usr/local/bin/conjur-fetch
conjur_cert
install -D -m 0644 "$CERT_FILE" /etc/idira/conjur.pem
cat > /etc/idira/conjur.env <<ENV
CONJUR_URL=${CONJUR_URL}
CONJUR_ACCOUNT=${CONJUR_ACCOUNT}
CONJUR_CERT=/etc/idira/conjur.pem
ENV
ok "/usr/local/bin/conjur-fetch, /etc/idira/conjur.{pem,env}"

if gitlab-runner list 2>&1 | grep -q idira-vm2; then
  ok "runner already registered"
else
  read -r -s -p "GitLab runner token (glrt-...): " GLRT; echo
  gitlab-runner register --non-interactive --url https://gitlab.com --token "$GLRT" \
    --executor shell --description idira-vm2
  unset GLRT
fi
gitlab-runner list
ok "Runner online. Check it shows green in GitLab > Settings > CI/CD > Runners."
