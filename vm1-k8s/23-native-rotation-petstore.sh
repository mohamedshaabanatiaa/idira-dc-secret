#!/usr/bin/env bash
# Turns on Secrets Manager's built-in Postgres rotator for the pet store.
# No script, no cron, no restart: the leader rotates on a timer and Secretless
# picks up the new value on the next connection.
#   ./23-native-rotation-petstore.sh          rotate every 5 minutes (demo)
#   ROTATION_TTL=P1D ./23-native-rotation-petstore.sh   daily
#   ./23-native-rotation-petstore.sh --off    stop (sets TTL to 10 years)
# Timebox this to 30 minutes on day 2. If it will not fire, 31-rotate-petstore.sh
# shows the same outcome.
source "$(dirname "$0")/lib.sh"
NS="$PET_NS"; PORT=30432
export ROTATION_TTL="${ROTATION_TTL:-PT5M}"
[[ "${1:-}" == "--off" ]] && ROTATION_TTL="P10Y"

log "Exposing the pet store DB to the leader on ${VM1_IP}:${PORT} (lab only)"
cat <<YAML | k -n "$NS" apply -f - >/dev/null
apiVersion: v1
kind: Service
metadata: { name: petstore-db-rotator }
spec:
  type: NodePort
  selector: { app: petstore-db }
  ports: [ { port: 5432, targetPort: 5432, nodePort: ${PORT} } ]
YAML
ok "NodePort ${PORT}"

log "Rotation policy (ttl ${ROTATION_TTL})"
render "$HERE/policies/petstore-native-rotation.yml.tmpl" > "$HERE/.rot.yml"
conjur_policy prod "$HERE/.rot.yml" >/dev/null && ok "annotations set"
rm -f "$HERE/.rot.yml"
conjur_set prod/petstore/db/url "${VM1_IP}:${PORT}/${PET_DB_NAME}"

cat <<MSG

Watch it: the DB password hash changes every ${ROTATION_TTL}, the app keeps answering, the pod never restarts.
  watch -n 20 "kubectl -n ${NS} exec petstore-db-0 -- psql -U ${PET_DB_USER} -d ${PET_DB_NAME} -tAc \\"select md5(rolpassword) from pg_authid where rolname='${PET_DB_USER}'\\"; curl -s -o /dev/null -w 'GET /pets %{http_code}\\n' http://${VM1_IP}:${PET_NODEPORT}/pets; kubectl -n ${NS} get pod -l app=petstore --no-headers"
Leader side: docker logs conjur-leader 2>&1 | grep -i rotat
MSG
