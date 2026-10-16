#!/usr/bin/env bash
# Run 30 to 60 min BEFORE the panel, on VM1.
# Puts both apps back to the hardcoded "before" state, so Acts 1-3 run live,
# and revokes the CI deploy tokens, so the Jenkins job fails until ./30-jenkins.sh.
set -e
D="$(cd "$(dirname "$0")/../vm1-k8s" && pwd)"
"$D/40-revert-boa.sh"
"$D/41-revert-petstore.sh"
"$D/26-revoke-deployers.sh"     # Jenkins has no deploy access until ./30-jenkins.sh
echo; echo "Reset done. Next: ./01-prepare.sh then ./02-preflight.sh"
