#!/usr/bin/env bash
# Installs CyberArk's pet store demo app in its ORIGINAL state:
# DB username and password hardcoded in the Deployment env.
source "$(dirname "$0")/lib.sh"

log "Creating namespace ${PET_NS}"
k create namespace "$PET_NS" --dry-run=client -o yaml | k apply -f -

log "Deploying Postgres (persistent volume, so rotations survive restarts)"
cat <<YAML | k -n "$PET_NS" apply -f -
apiVersion: v1
kind: Service
metadata: { name: petstore-db }
spec:
  selector: { app: petstore-db }
  ports: [ { port: 5432, targetPort: 5432 } ]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: petstore-db }
spec:
  serviceName: petstore-db
  replicas: 1
  selector: { matchLabels: { app: petstore-db } }
  template:
    metadata: { labels: { app: petstore-db } }
    spec:
      containers:
      - name: postgres
        image: ${PG_IMAGE}
        env:
        - { name: POSTGRES_DB,       value: "${PET_DB_NAME}" }
        - { name: POSTGRES_USER,     value: "${PET_DB_USER}" }
        - { name: POSTGRES_PASSWORD, value: "${PET_DB_PASS}" }   # hardcoded
        - { name: PGDATA,            value: /var/lib/postgresql/data/pgdata }
        ports: [ { containerPort: 5432 } ]
        volumeMounts: [ { name: data, mountPath: /var/lib/postgresql/data } ]
  volumeClaimTemplates:
  - metadata: { name: data }
    spec:
      accessModes: [ ReadWriteOnce ]
      resources: { requests: { storage: 1Gi } }
YAML
k -n "$PET_NS" rollout status statefulset/petstore-db --timeout=300s

log "Deploying pet store app with hardcoded DB credentials"
cat <<YAML | k -n "$PET_NS" apply -f -
apiVersion: v1
kind: ServiceAccount
metadata: { name: petstore-app }
---
apiVersion: v1
kind: Service
metadata: { name: petstore }
spec:
  type: NodePort
  selector: { app: petstore }
  ports: [ { port: 8080, targetPort: 8080, nodePort: ${PET_NODEPORT} } ]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: petstore }
spec:
  replicas: 1
  selector: { matchLabels: { app: petstore } }
  template:
    metadata: { labels: { app: petstore } }
    spec:
      serviceAccountName: petstore-app
      containers:
      - name: app
        image: ${PET_IMAGE}
        env:
        - { name: DB_URL,      value: "postgresql://petstore-db.${PET_NS}.svc.cluster.local:5432/${PET_DB_NAME}" }
        - { name: DB_USERNAME, value: "${PET_DB_USER}" }   # hardcoded
        - { name: DB_PASSWORD, value: "${PET_DB_PASS}" }   # hardcoded
        - { name: DB_PLATFORM, value: postgres }
        - { name: JAVA_TOOL_OPTIONS, value: "-XX:-UseContainerSupport -Xmx384m" }   # same cgroup v2 fix as BoA
        ports: [ { containerPort: 8080 } ]
        readinessProbe:
          httpGet: { path: /pets, port: 8080 }
          initialDelaySeconds: 20
          periodSeconds: 5
YAML
k -n "$PET_NS" rollout status deploy/petstore --timeout=300s

log "Hardcoded secrets in the original install:"
k -n "$PET_NS" get deploy petstore -o json | jq -r '.spec.template.spec.containers[0].env[] | select(.name|test("USER|PASS")) | "  \(.name)=\(.value)"'

IP=$(hostname -I | awk '{print $1}')
curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"Mr. Sniffles"}' "http://${IP}:${PET_NODEPORT}/pet" >/dev/null || true
ok "Pet store: curl http://${IP}:${PET_NODEPORT}/pets"
curl -s "http://${IP}:${PET_NODEPORT}/pets"; echo
