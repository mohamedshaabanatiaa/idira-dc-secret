#!/usr/bin/env bash
# Runs as the broker user. Keeps a fresh SPIFFE JWT-SVID (5 min life) on disk for Secretless.
# Only this user is registered in SPIRE; only this user can read the file.
OUT=/var/lib/ops-agent-broker/jwt
while true; do
  /opt/spire/bin/spire-agent api fetch jwt -audience conjur -socketPath /tmp/spire-agent/public/api.sock 2>/dev/null \
    | awk '/^token\(/ {getline; gsub(/[[:space:]]/, ""); print; exit}' > "$OUT.tmp"
  [[ -s "$OUT.tmp" ]] && mv -f "$OUT.tmp" "$OUT"
  sleep 60
done
