#!/usr/bin/env bash
# Run BEFORE the panel, on VM1, only if the apps are in the hardcoded state
# (fresh install or after ./00-reset.sh). Moves both apps to Secrets Manager.
set -e
D="$(cd "$(dirname "$0")/../vm1-k8s" && pwd)"
"$D/21-migrate-boa.sh"
"$D/22-migrate-petstore.sh"
echo; echo "Both apps migrated. Next: ./02-preflight.sh"
