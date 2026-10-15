#!/usr/bin/env bash
# Standalone AI agent on VM3 with a SPIFFE identity. Nothing on VM1 changes.
#   user ops-agent         runs the agent. Holds nothing. Not registered in SPIRE.
#   user ops-agent-broker  runs Secretless Broker. Registered in SPIRE as
#                          spiffe://bank.local/agents/ops-agent, the only one that can log in.
# Run on VM3 as root, after 00 and 10. Safe to run again.
source "$(dirname "$0")/../common/lib.sh"
need curl; need jq
HERE="$(cd "$(dirname "$0")" && pwd)"
SRV=/opt/spire/bin/spire-server
BROKER_ID="spiffe://bank.local/agents/ops-agent"
OPT=/opt/ops-agent; STATE=/var/lib/ops-agent-broker

log "Users"
id ops-agent        >/dev/null 2>&1 || useradd -r -m -s /bin/bash ops-agent
id ops-agent-broker >/dev/null 2>&1 || useradd -r -M -s /usr/sbin/nologin ops-agent-broker
install -d -m 700 -o ops-agent-broker -g ops-agent-broker "$STATE"
ok "ops-agent (agent), ops-agent-broker (Secretless)"

log "SPIRE entry: user ops-agent-broker on vm3 -> ${BROKER_ID}"
if "$SRV" entry show -spiffeID "$BROKER_ID" | grep -q "Entry ID"; then ok "already registered"
else "$SRV" entry create -parentID spiffe://bank.local/node/vm3 -spiffeID "$BROKER_ID" -selector unix:user:ops-agent-broker >/dev/null; ok "registered"; fi

log "Policy (add only): host prod/spiffe/ops-agent may use the Claude key"
conjur_ready
conjur policy load -b prod -f "$LAB_ROOT/policies/prod.yml" >/dev/null
conjur policy load -b root -f "$LAB_ROOT/policies/authenticators.yml" >/dev/null
ok "loaded"

log "Secretless Broker binary"
if [[ ! -x "$OPT/bin/secretless-broker" ]]; then
  mkdir -p "$OPT/bin"; tmp=$(mktemp -d)
  URL=$(curl -fsSL https://api.github.com/repos/cyberark/secretless-broker/releases/latest \
        | jq -r '.assets[].browser_download_url | select(test("linux_amd64\\.tar\\.gz$"))' | head -1)
  if [[ -n "$URL" ]]; then
    curl -fsSL -o "$tmp/s.tgz" "$URL" && tar -xzf "$tmp/s.tgz" -C "$tmp"
    find "$tmp" -type f -name secretless-broker -exec cp {} "$OPT/bin/" \;
  elif command -v docker >/dev/null; then
    docker create --name sb-extract cyberark/secretless-broker:latest >/dev/null
    docker cp sb-extract:/usr/local/bin/secretless-broker "$OPT/bin/"; docker rm sb-extract >/dev/null
  fi
  rm -rf "$tmp"
  [[ -x "$OPT/bin/secretless-broker" ]] || die "could not get the Secretless binary (no release asset, no docker)"
fi
ok "$OPT/bin/secretless-broker"

log "Agent program (Python venv with the Claude SDK)"
python3 -m venv --help >/dev/null 2>&1 && python3 -c 'import ensurepip' 2>/dev/null \
  || { apt-get update -qq && apt-get install -y -qq python3-venv >/dev/null; }
[[ -x "$OPT/venv/bin/python" ]] || python3 -m venv "$OPT/venv"
"$OPT/venv/bin/pip" install -q --upgrade anthropic
install -m 644 "$HERE/agent/ops_agent.py" "$OPT/ops_agent.py"
install -m 644 "$HERE/agent/secretless.yml" "$OPT/secretless.yml"
install -m 755 "$HERE/agent/svid-refresh.sh" "$OPT/bin/svid-refresh.sh"
ok "installed in $OPT"

log "Services (run as ops-agent-broker)"
cat > /etc/systemd/system/ops-agent-svid.service <<UNIT
[Unit]
Description=Ops agent: keep a fresh SPIFFE JWT-SVID for Secretless
After=spire-agent.service
[Service]
User=ops-agent-broker
ExecStart=$OPT/bin/svid-refresh.sh
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/ops-agent-secretless.service <<UNIT
[Unit]
Description=Ops agent: Secretless Broker (Claude key from Secrets Manager, SPIFFE login)
After=ops-agent-svid.service
Requires=ops-agent-svid.service
[Service]
User=ops-agent-broker
Environment=CONJUR_APPLIANCE_URL=${CONJUR_URL}
Environment=CONJUR_AUTHN_URL=${CONJUR_URL}/authn-jwt/spire
Environment=CONJUR_ACCOUNT=${CONJUR_ACCOUNT}
Environment=CONJUR_AUTHN_LOGIN=host/prod/spiffe/ops-agent
Environment=JWT_TOKEN_PATH=${STATE}/jwt
Environment=CONJUR_AUTHN_TOKEN_FILE=${STATE}/access-token
Environment=CONJUR_CERT_FILE=/opt/spire/conf/conjur.pem
ExecStartPre=/usr/bin/timeout 30 /bin/sh -c 'until [ -s ${STATE}/jwt ]; do sleep 1; done'
ExecStart=$OPT/bin/secretless-broker -f $OPT/secretless.yml
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable ops-agent-svid ops-agent-secretless >/dev/null 2>&1
systemctl restart ops-agent-svid; systemctl restart ops-agent-secretless
sleep 5
systemctl is-active --quiet ops-agent-secretless || die "Secretless not running: journalctl -u ops-agent-secretless -n 40"
ok "Secretless listening on 127.0.0.1:8090"

log "Only the ops-agent user may use the broker (on a shared VM, localhost is not private)"
command -v iptables >/dev/null || { apt-get update -qq && apt-get install -y -qq iptables >/dev/null; }
RULE=(OUTPUT -o lo -p tcp --dport 8090 -m owner ! --uid-owner ops-agent -j REJECT)
iptables -C "${RULE[@]}" 2>/dev/null || iptables -I "${RULE[@]}"
ok "other users get 'connection refused' on 8090 (rule is not persistent: rerun after a reboot)"

ok "Ready. ./31-ops-chat.sh   (then ./31-ops-chat.sh intruder, ./32-ops-kill.sh off|on)"
