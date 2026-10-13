#!/usr/bin/env bash
# Installs the Secrets Manager Self-Hosted leader as a container on this VM.
#   ./10-install-leader.sh /path/to/conjur-appliance-<version>.tar.gz
# Check the file name and image tag against what the lab gave you.
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

  log "Starting $NAME"
  mkdir -p /opt/cyberark/conjur/{security,config,backups,seeds,logs}
  docker run --name "$NAME" -d --restart=unless-stopped \
    --security-opt seccomp=unconfined \
    -p 443:443 -p 444:444 -p 5432:5432 -p 1999:1999 \
    -v /opt/cyberark/conjur/security:/opt/cyberark/conjur/security \
    -v /opt/cyberark/conjur/config:/etc/conjur/config \
    -v /opt/cyberark/conjur/backups:/opt/conjur/backup \
    -v /opt/cyberark/conjur/seeds:/opt/cyberark/conjur/seeds \
    -v /opt/cyberark/conjur/logs:/var/log/conjur \
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
    --leader-altnames "${CONJUR_HOST},$(hostname)" \
    --admin-password "$CONJUR_ADMIN_PASSWORD" \
    "$CONJUR_ACCOUNT"
fi

ensure_hosts_entry
log "Health"
curl -sk https://localhost/health | jq '{ok, database: .database.ok}' || true
curl -sk https://localhost/info | jq '{role, release: .release, authenticators: .authenticators}' || true
ok "Leader ready. UI: https://${CONJUR_HOST} from the Windows jump host (add the hosts entry there too)"
