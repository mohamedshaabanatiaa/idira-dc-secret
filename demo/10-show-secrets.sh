#!/usr/bin/env bash
# Act 1: is any password hardcoded in the cluster? Shows each kubectl command, then its output.
# Before migration: passwords visible. After: none, only Secrets Manager paths.
run() { printf '\n\033[1;36m$ %s\033[0m\n' "$1"; bash -c "$1"; echo; }

echo -e "\n\033[1m== Bank of Anthos: database settings in the ConfigMaps\033[0m"
run "kubectl -n boa get configmap accounts-db-config -o jsonpath='{.data}'"
run "kubectl -n boa get configmap ledger-db-config -o jsonpath='{.data}'"

echo -e "\033[1m== Bank of Anthos: where the password comes from now (paths, not values)\033[0m"
run "kubectl -n boa get secret accounts-db-creds -o jsonpath='{.data.conjur-map}' | base64 -d"

echo -e "\033[1m== Pet store: app settings in the Deployment\033[0m"
run "kubectl -n petstore get deployment petstore -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\n\"}{end}'"

echo -e "\033[1m== Pet store: containers in the pod (app + Secretless sidecar)\033[0m"
run "kubectl -n petstore get deployment petstore -o jsonpath='{.spec.template.spec.containers[*].name}'"
