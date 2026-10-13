#!/usr/bin/env bash
# Readiness check per VM role: ./readiness/check.sh sm|vm1|vm2|vm3
# Reads CONJUR_HOST / CONJUR_IP from vm1-k8s/config.env (edit that first).
set -uo pipefail
ROLE="${1:-}"; [[ "$ROLE" =~ ^(sm|vm1|vm2|vm3)$ ]] || { echo "usage: $0 sm|vm1|vm2|vm3"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/vm1-k8s/config.env"
FAIL=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

hdr "Host ($ROLE)"
. /etc/os-release 2>/dev/null && pass "$PRETTY_NAME, $(hostname), $(hostname -I | awk '{print $1}')"
[[ $EUID -eq 0 ]] && pass "running as root" || warn "not root (most scripts need sudo -i)"

CPU=$(nproc); MEM=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)
DISK=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
case $ROLE in sm) NC=4; NM=8; ND=30;; vm1) NC=4; NM=8; ND=30;; vm2) NC=2; NM=4; ND=20;; vm3) NC=2; NM=2; ND=10;; esac
(( CPU  >= NC )) && pass "CPU ${CPU}"        || warn "CPU ${CPU} (want ${NC}+)"
(( MEM  >= NM-1 )) && pass "RAM ${MEM} GB"   || warn "RAM ${MEM} GB (want ${NM}+)"
(( DISK >= ND )) && pass "disk free ${DISK} GB" || warn "disk free ${DISK} GB (want ${ND}+)"

hdr "Clock (JWT auth breaks if it drifts)"
if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then
  pass "NTP synchronized, $(date -u +%H:%M:%S) UTC"
else
  fail "clock not synchronized: systemctl restart systemd-timesyncd"
fi

hdr "Tools"
for t in git curl jq openssl; do command -v $t >/dev/null && pass "$t" || fail "$t missing: apt-get install -y $t"; done
case $ROLE in
  sm)  { command -v docker || command -v podman; } >/dev/null && pass "container runtime" || warn "no docker/podman yet (needed for the Self-Hosted image)";;
  vm1) command -v k3s >/dev/null && pass "k3s $(k3s --version | head -1 | awk '{print $3}')" || warn "k3s not installed yet (vm1-k8s/00-install-k3s.sh)";;
  vm2) command -v java >/dev/null && pass "java" || warn "java not installed yet (Jenkins)";;
  vm3) command -v python3 >/dev/null && pass "python3 $(python3 -V | awk '{print $2}')" || fail "python3 missing";;
esac

hdr "Outbound access"
probe() { local code; code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$1"); [[ "$code" != "000" ]] && pass "$1 ($code)" || fail "$1 unreachable"; }
probe https://github.com
case $ROLE in
  sm)  probe https://registry-1.docker.io/v2/ ;;
  vm1) probe https://get.k3s.io; probe https://registry-1.docker.io/v2/; probe https://us-central1-docker.pkg.dev/v2/ ;;
  vm2) probe https://gitlab.com; probe https://pkg.jenkins.io; probe https://packages.gitlab.com ;;
  vm3) probe https://api.anthropic.com; probe https://pypi.org/simple/ ;;
esac

hdr "Secrets Manager leader (${CONJUR_HOST} / ${CONJUR_IP})"
if [[ $ROLE == sm ]]; then
  code=$(curl -sk -o /dev/null -m 5 -w '%{http_code}' https://localhost/info)
  [[ $code == 200 ]] && pass "leader answers locally (/info 200)" || warn "leader not answering yet (/info $code)"
  if [[ $code == 200 ]]; then
    curl -sk https://localhost/info | jq -r '.authenticators.enabled // .authenticators // empty' 2>/dev/null | sed 's/^/       /'
  fi
else
  getent hosts "$CONJUR_HOST" >/dev/null && pass "$CONJUR_HOST resolves to $(getent hosts "$CONJUR_HOST" | awk '{print $1}')" \
    || warn "$CONJUR_HOST does not resolve: echo \"$CONJUR_IP $CONJUR_HOST\" >> /etc/hosts"
  timeout 5 bash -c "</dev/tcp/$CONJUR_IP/443" 2>/dev/null && pass "TCP 443 open to $CONJUR_IP" || fail "cannot reach $CONJUR_IP:443"
  SAN=$(echo | timeout 5 openssl s_client -connect "$CONJUR_IP:443" -servername "$CONJUR_HOST" 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>/dev/null | tail -1)
  [[ -n "$SAN" ]] && { [[ "$SAN" == *"$CONJUR_HOST"* ]] && pass "cert SAN includes $CONJUR_HOST" || warn "cert SAN is [$SAN], set CONJUR_HOST to one of these"; } \
    || warn "could not read leader cert"
fi

hdr "Repo"
git -C "$ROOT" fetch -q 2>/dev/null && {
  B=$(git -C "$ROOT" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
  (( B == 0 )) && pass "repo up to date ($(git -C "$ROOT" log -1 --format=%h))" || warn "$B new commit(s): git pull"
} || warn "could not fetch (token cache expired?)"

echo
(( FAIL == 0 )) && printf '\033[32mREADY\033[0m for %s\n' "$ROLE" || printf '\033[31mNOT READY\033[0m: fix the FAIL lines\n'
exit $FAIL
