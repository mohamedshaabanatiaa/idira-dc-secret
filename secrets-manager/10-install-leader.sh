#!/usr/bin/env bash
# Installs the Secrets Manager Self-Hosted leader (single node) as a container.
# Follows the official CyberArk docs:
#   https://docs.cyberark.com/secrets-manager-sh/latest/en/content/deployment/dap/dap-before-deploy-vm.htm
#   https://docs.cyberark.com/secrets-manager-sh/latest/en/content/deployment/dap/dap-deploy-dap.htm
# Usage (as root):
#   ./10-install-leader.sh "/home/skytap/Secrets Manager Self-Hosted Appliance/conjur-appliance-Rls-v13.10.0.tar.gz"
source "$(dirname "$0")/../common/lib.sh"
[[ $EUID -eq 0 ]] || die "run as root"
TARBALL="${1:-}"
NAME="conjur-leader"

log "Container runtime"
if ! command -v docker >/dev/null; then
  apt-get update -qq && apt-get install -y -qq docker.io jq curl openssl >/dev/null
  systemctl enable --now docker
fi
ok "$(docker --version)"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  ok "container $NAME already exists, skipping load/run"
else
  [[ -f "$TARBALL" ]] || die "pass the appliance tarball path, e.g. ./10-install-leader.sh ~/conjur-appliance-13.x.tar.gz"
  log "Loading image from $TARBALL (takes a few minutes)"
  IMAGE=$(docker load -i "$TARBALL" | awk -F': ' '/Loaded image/{print $2}' | tail -1)
  [[ -n "$IMAGE" ]] || die "could not read image name from docker load"
  ok "image $IMAGE"

  log "Folders and config file (per CyberArk docs: dap-before-deploy-vm)"
  mkdir -p /opt/cyberark/conjur/{security,config,backups,seeds,logs}
  touch /opt/cyberark/conjur/config/conjur.yml
  chmod o+x /opt/cyberark/conjur/config
  chmod o+r /opt/cyberark/conjur/config/conjur.yml

  log "Seccomp profile shipped inside the image (adds keyring calls to Docker's default)"
  docker run --rm --entrypoint /bin/cat "$IMAGE" /usr/share/doc/conjur/examples/seccomp.json \
    > /opt/cyberark/conjur/security/seccomp.json
  ok "/opt/cyberark/conjur/security/seccomp.json"

  log "Starting $NAME"
  docker network inspect conjur >/dev/null 2>&1 || docker network create conjur >/dev/null
  docker run --name "$NAME" --detach --restart unless-stopped \
    --network conjur --network-alias "$CONJUR_HOST" \
    --security-opt seccomp=/opt/cyberark/conjur/security/seccomp.json \
    --publish "443:443" --publish "444:444" --publish "5432:5432" --publish "1999:1999" \
    --cap-add AUDIT_WRITE \
    --log-driver journald \
    --volume /opt/cyberark/conjur/config:/etc/conjur/config:z \
    --volume /opt/cyberark/conjur/security:/opt/cyberark/conjur/security:z \
    --volume /opt/cyberark/conjur/backups:/opt/conjur/backup:z \
    --volume /opt/cyberark/conjur/logs:/var/log/conjur:z \
    "$IMAGE"
  sleep 10
fi

if curl -sk https://localhost/info 2>/dev/null | jq -e .role >/dev/null 2>&1; then
  ok "leader already configured"
else
  log "Configuring leader: host ${CONJUR_HOST}, account ${CONJUR_ACCOUNT}"
  ensure_pw
  docker exec "$NAME" evoke configure leader --accept-eula \
    --hostname "$CONJUR_HOST" \
    --leader-altnames "${CONJUR_HOST}" \
    --admin-password "$CONJUR_ADMIN_PASSWORD" \
    "$CONJUR_ACCOUNT"
fi

ensure_hosts_entry
log "Health"
curl -sk https://localhost/health | jq '{ok, database: .database.ok}' || true
curl -sk https://localhost/info | jq '{role, release: .release, authenticators: .authenticators}' || true
ok "Leader ready. UI: https://${CONJUR_HOST} from the Windows jump host (add the hosts entry there too)"
