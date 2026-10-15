#!/usr/bin/env bash
# The batch job itself. It holds no password, no API key, no secret file.
# It asks SPIRE "who am I?", then shows that identity to Secrets Manager.
set -uo pipefail
URL="$1"; ACCOUNT="$2"; CERT="$3"
SOCK=/tmp/spire-agent/public/api.sock
HOST_ID="host/prod/spiffe/settlement-batch"
VAR="prod/batch/core-banking-api-key"
B='\033[1m'; G='\033[1;32m'; R='\033[1;31m'; Y='\033[0;90m'; N='\033[0m'
enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

echo -e "\n${B}1. Who am I?${N}  (running as Linux user: $(id -un), on $(hostname))"
echo -e "${Y}   spire-agent api fetch jwt -audience conjur${N}"
OUT=$(/opt/spire/bin/spire-agent api fetch jwt -audience conjur -socketPath "$SOCK" 2>&1)
JWT=$(awk '/^token\(/ {getline; gsub(/[[:space:]]/, ""); print; exit}' <<<"$OUT")
if [[ -z "$JWT" ]]; then
  echo -e "   ${R}✗ SPIRE issued no identity to this process.${N}"
  echo -e "${Y}   $(tail -1 <<<"$OUT")${N}"
  echo -e "   ${R}No identity, nothing to show Secrets Manager. Stops here.${N}\n"
  exit 1
fi
python3 - "$JWT" <<'PY'
import sys, json, base64, time
p = sys.argv[1].split(".")[1]; c = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
print(f"   \033[1;32m✓ SPIFFE ID:\033[0m {c['sub']}")
print(f"     audience {c['aud']}, issuer {c.get('iss','-')}, expires in {int(c['exp'] - time.time())}s")
PY

echo -e "\n${B}2. Log in to Secrets Manager with that token${N}"
echo -e "${Y}   POST /authn-jwt/spire/${ACCOUNT}/${HOST_ID}/authenticate${N}"
TOKEN=$(curl -sS --cacert "$CERT" -X POST -H "Accept-Encoding: base64" \
  --data-urlencode "jwt=${JWT}" \
  "${URL}/authn-jwt/spire/${ACCOUNT}/$(enc "$HOST_ID")/authenticate" -w '\n%{http_code}')
CODE=$(tail -1 <<<"$TOKEN"); TOKEN=$(head -n -1 <<<"$TOKEN")
if [[ "$CODE" != 200 ]]; then echo -e "   ${R}✗ login refused (HTTP ${CODE})${N}\n"; exit 1; fi
echo -e "   ${G}✓ logged in as ${HOST_ID#host/}${N} (session token, 8 minutes)"

echo -e "\n${B}3. Fetch the one secret this job is allowed${N}"
echo -e "${Y}   GET /secrets/${ACCOUNT}/variable/${VAR}${N}"
SECRET=$(curl -sS --cacert "$CERT" -H "Authorization: Token token=\"${TOKEN}\"" \
  "${URL}/secrets/${ACCOUNT}/variable/$(enc "$VAR")" -w '\n%{http_code}')
CODE=$(tail -1 <<<"$SECRET"); SECRET=$(head -n -1 <<<"$SECRET")
if [[ "$CODE" != 200 ]]; then echo -e "   ${R}✗ denied (HTTP ${CODE})${N}\n"; exit 1; fi
echo -e "   ${G}✓ ${VAR}${N} = ${SECRET:0:4}**************** (used in memory, never written to disk)"

echo -e "\n${B}4. Anything else?${N}"
echo -e "${Y}   GET /secrets/${ACCOUNT}/variable/prod/ai/anthropic-api-key${N}"
CODE=$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$CERT" -H "Authorization: Token token=\"${TOKEN}\"" \
  "${URL}/secrets/${ACCOUNT}/variable/$(enc prod/ai/anthropic-api-key)")
[[ "$CODE" == 200 ]] && echo -e "   ${R}✗ readable: policy too wide${N}\n" \
                     || echo -e "   ${G}✓ denied (HTTP ${CODE}): least privilege${N}\n"
