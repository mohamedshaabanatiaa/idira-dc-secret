#!/usr/bin/env bash
# Run 30 to 60 min BEFORE the panel, on VM1.
# Puts both apps back to the hardcoded "before" state, so Acts 1-3 run live.
set -e
D="$(cd "$(dirname "$0")/../vm1-k8s" && pwd)"
"$D/40-revert-boa.sh"
"$D/41-revert-petstore.sh"
echo; echo "Reset done. Next: ./01-prepare.sh then ./02-preflight.sh"
