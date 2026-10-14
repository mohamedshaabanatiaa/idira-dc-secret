#!/usr/bin/env bash
# Act 1: where do the database passwords live? One plain line per app,
# with the kubectl command shown in grey underneath for the technical audience.
RED='\033[1;31m'; GRN='\033[1;32m'; GRY='\033[0;90m'; B='\033[1m'; N='\033[0m'
HARD=0

bad()  { printf "  ${RED}✗ HARDCODED${N}  %-28s %s\n" "$1" "$2"; HARD=$((HARD+1)); }
good() { printf "  ${GRN}✓ PROTECTED${N}  %-28s %s\n" "$1" "$2"; }

echo -e "\n${B}  Where do the database passwords live?${N}\n"

# Bank of Anthos: ConfigMap value, or a map to Secrets Manager
for db in accounts ledger; do
  name="Bank of Anthos, ${db} DB"
  C="kubectl -n boa get configmap ${db}-db-config -o jsonpath='{.data.POSTGRES_PASSWORD}'"
  val=$(bash -c "$C" 2>/dev/null)
  if [[ -n "$val" ]]; then
    bad "$name" "in a config file, readable: ${val}"
  else
    M="kubectl -n boa get secret ${db}-db-creds -o jsonpath='{.data.conjur-map}' | base64 -d | grep POSTGRES_PASSWORD"
    path=$(bash -c "$M" 2>/dev/null | awk '{print $2}')
    good "$name" "fetched from Secrets Manager: ${path}"
    C="$M"
  fi
  printf "${GRY}      \$ %s${N}\n\n" "$C"
done

# Pet store: password in the app env, or a Secretless sidecar
name="Pet store"
C="kubectl -n petstore get deployment petstore -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"DB_PASSWORD\")].value}'"
val=$(bash -c "$C" 2>/dev/null)
if [[ -n "$val" ]]; then
  bad "$name" "in the app settings, readable: ${val}"
else
  good "$name" "app holds NO password, sidecar fetches it"
  C="kubectl -n petstore get deployment petstore -o jsonpath='{.spec.template.spec.containers[*].name}'"
  printf "${GRY}      \$ %s  ->  %s${N}\n\n" "$C" "$(bash -c "$C" 2>/dev/null)"
  C=""
fi
[[ -n "$C" ]] && printf "${GRY}      \$ %s${N}\n\n" "$C"

if (( HARD > 0 )); then
  echo -e "  ${RED}${HARD} of 3 passwords readable by anyone with cluster or Git access.${N}\n"
else
  echo -e "  ${GRN}0 of 3 passwords stored in the cluster config. All delivered by identity at runtime.${N}\n"
fi
