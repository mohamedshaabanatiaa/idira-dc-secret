#!/usr/bin/env bash
# Installs single-node k3s on DevOps VM1 plus the tools the other scripts need.
# Run as root (sudo -i).
source "$(dirname "$0")/lib.sh"
[[ $EUID -eq 0 ]] || die "run as root"

log "Installing base tools"
apt-get update -qq
apt-get install -y -qq curl jq git openssl python3 ca-certificates >/dev/null
ok "curl jq git openssl python3"

log "Mapping ${CONJUR_HOST} -> ${CONJUR_IP} in /etc/hosts"
grep -q " ${CONJUR_HOST}\$" /etc/hosts || echo "${CONJUR_IP} ${CONJUR_HOST}" >> /etc/hosts
ok "$(grep " ${CONJUR_HOST}\$" /etc/hosts)"

if command -v k3s >/dev/null; then
  ok "k3s already installed: $(k3s --version | head -1)"
else
  log "Installing k3s (traefik disabled, servicelb kept for LoadBalancer services)"
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -
fi

log "Waiting for node to be Ready"
for _ in {1..30}; do k get nodes >/dev/null 2>&1 && break; sleep 4; done
k wait --for=condition=Ready node --all --timeout=180s
mkdir -p "$HOME/.kube" && cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
k get nodes -o wide

log "Service account token issuer (needed for the JWT authenticator)"
k get --raw /.well-known/openid-configuration | jq -r .issuer
ok "k3s ready"
