#!/usr/bin/env bash
# Sets up the AI agent on VM3:
#  - two agent identities in Secrets Manager (support-agent, rogue-agent)
#  - your Claude API key stored in Secrets Manager, NOT on this VM
#  - each agent gets only its login key (0600, root), usable only from this IP
source "$(dirname "$0")/../common/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
[[ $EUID -eq 0 ]] || die "run as root"
APP=/opt/idira-agent
ensure_hosts_entry

log "Python runtime"
apt-get update -qq && apt-get install -y -qq python3-venv python3-pip curl jq openssl >/dev/null
mkdir -p "$APP" /etc/idira
[[ -d "$APP/venv" ]] || python3 -m venv "$APP/venv"
"$APP/venv/bin/pip" install -q --upgrade pip anthropic requests
cp "$HERE"/app/*.py "$APP/"
ok "$("$APP/venv/bin/python" -c 'import anthropic;print("anthropic", anthropic.__version__)')"

log "Leader trust"
conjur_cert
install -m 0644 "$CERT_FILE" /etc/idira/conjur.pem
cat > /etc/idira/conjur.env <<ENV
CONJUR_URL=${CONJUR_URL}
CONJUR_ACCOUNT=${CONJUR_ACCOUNT}
CONJUR_CERT=/etc/idira/conjur.pem
PETSTORE_URL=http://${VM1_IP}:30080
ENV

log "Agent login keys (identities come from policies/bank.yml: prod/agents/*)"

for a in support-agent rogue-agent; do
  umask 077; conjur_host_key "prod/agents/$a" > "/etc/idira/$a.key"
  ok "/etc/idira/$a.key (root only, works only from ${VM3_IP})"
done

log "Claude API key -> Secrets Manager"
if conjur_get prod/ai/anthropic-api-key >/dev/null 2>&1; then
  ok "already stored (rerun with --new-key to replace)"
fi
if [[ "${1:-}" == "--new-key" ]] || ! conjur_get prod/ai/anthropic-api-key >/dev/null 2>&1; then
  read -r -s -p "Paste the Claude API key (sk-ant-...): " AK; echo
  conjur_set prod/ai/anthropic-api-key "$AK"; unset AK
fi
ok "Ready: sudo $APP/venv/bin/python $APP/agent.py"
