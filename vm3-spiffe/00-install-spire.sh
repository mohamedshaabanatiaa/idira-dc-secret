#!/usr/bin/env bash
# Installs open-source SPIRE (server + agent) on VM3. Workloads are registered by
# 30-ops-agent.sh. User "intruder" gets no registration (the negative test).
# Run on VM3 as root. Safe to run again.
source "$(dirname "$0")/../common/lib.sh"
need curl; need jq; need tar
TD="bank.local"
NODE_ID="spiffe://${TD}/node/vm3"
D=/opt/spire
SRV="$D/bin/spire-server"; AGT="$D/bin/spire-agent"

log "SPIRE binaries"
if [[ ! -x "$SRV" ]]; then
  V="${SPIRE_VERSION:-$(curl -fsSL https://api.github.com/repos/spiffe/spire/releases/latest | jq -r .tag_name | sed 's/^v//')}"
  [[ -n "$V" && "$V" != null ]] || die "could not find the SPIRE version. Run: SPIRE_VERSION=<x.y.z> $0"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/spire.tgz" "https://github.com/spiffe/spire/releases/download/v${V}/spire-${V}-linux-amd64-musl.tar.gz"
  tar -xzf "$tmp/spire.tgz" -C "$tmp"
  mkdir -p "$D/bin"; cp "$tmp"/spire-*/bin/spire-server "$tmp"/spire-*/bin/spire-agent "$D/bin/"
  rm -rf "$tmp"
fi
ok "$("$SRV" --version 2>&1 | head -1)"
mkdir -p "$D/conf" "$D/data/server" "$D/data/agent"

log "Server config (trust domain ${TD}, JWT issuer https://spire.${TD})"
cat > "$D/conf/server.conf" <<HCL
server {
  bind_address         = "127.0.0.1"
  bind_port            = "8081"
  trust_domain         = "${TD}"
  data_dir             = "${D}/data/server"
  log_level            = "INFO"
  ca_key_type          = "rsa-2048"
  jwt_key_type         = "rsa-2048"
  ca_ttl               = "720h"   # lab: signing keys stay stable past the panel date
  default_jwt_svid_ttl = "5m"     # every workload token lives 5 minutes
  agent_ttl            = "720h"   # the node (agent) identity itself, renewed by the agent
  jwt_issuer           = "https://spire.${TD}"
}
plugins {
  DataStore "sql" {
    plugin_data {
      database_type     = "sqlite3"
      connection_string = "${D}/data/server/datastore.sqlite3"
    }
  }
  KeyManager "disk" { plugin_data { keys_path = "${D}/data/server/keys.json" } }
  NodeAttestor "join_token" { plugin_data {} }
}
HCL

cat > /etc/systemd/system/spire-server.service <<UNIT
[Unit]
Description=SPIRE server
After=network-online.target
[Service]
ExecStart=${SRV} run -config ${D}/conf/server.conf
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable spire-server >/dev/null 2>&1
systemctl restart spire-server
for _ in $(seq 1 30); do "$SRV" healthcheck >/dev/null 2>&1 && break; sleep 1; done
"$SRV" healthcheck >/dev/null 2>&1 || die "SPIRE server not healthy: journalctl -u spire-server -n 50"
ok "SPIRE server healthy"

log "Agent (node attestation: a fresh one-time join token at every start)"
"$SRV" bundle show > "$D/conf/bootstrap.crt"
cat > "$D/conf/agent.conf" <<HCL
agent {
  data_dir          = "${D}/data/agent"
  log_level         = "INFO"
  server_address    = "127.0.0.1"
  server_port       = "8081"
  socket_path       = "/tmp/spire-agent/public/api.sock"
  trust_bundle_path = "${D}/conf/bootstrap.crt"
  trust_domain      = "${TD}"
}
plugins {
  NodeAttestor "join_token" { plugin_data {} }
  KeyManager "disk" { plugin_data { directory = "${D}/data/agent" } }
  WorkloadAttestor "unix" { plugin_data {} }
}
HCL
# A join token works once. Server and agent share this VM, so the agent asks for a new
# one each time it starts (reboot, crash, restart) instead of reusing a spent token.
cat > "$D/bin/spire-agent-start.sh" <<SH
#!/bin/sh
for i in \$(seq 1 30); do
  T=\$(${SRV} token generate -spiffeID ${NODE_ID} 2>/dev/null | awk '/Token/ {print \$2}')
  [ -n "\$T" ] && break; sleep 2
done
[ -n "\$T" ] || { echo "no join token from the SPIRE server"; exit 1; }
exec ${AGT} run -config ${D}/conf/agent.conf -joinToken "\$T"
SH
chmod 755 "$D/bin/spire-agent-start.sh"
rm -f "$D/conf/agent.env"
cat > /etc/systemd/system/spire-agent.service <<UNIT
[Unit]
Description=SPIRE agent
After=spire-server.service
Requires=spire-server.service
[Service]
ExecStart=${D}/bin/spire-agent-start.sh
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable spire-agent >/dev/null 2>&1
systemctl restart spire-agent
for _ in $(seq 1 30); do "$AGT" healthcheck -socketPath /tmp/spire-agent/public/api.sock >/dev/null 2>&1 && break; sleep 1; done
"$AGT" healthcheck -socketPath /tmp/spire-agent/public/api.sock >/dev/null 2>&1 || die "SPIRE agent not healthy: journalctl -u spire-agent -n 50"
ok "SPIRE agent healthy, node ${NODE_ID}"

log "Negative-test user"
id intruder >/dev/null 2>&1 || useradd -r -m -s /bin/bash intruder
ok "intruder (never registered)"

ok "SPIRE ready. Next: ./10-connect-conjur.sh"
