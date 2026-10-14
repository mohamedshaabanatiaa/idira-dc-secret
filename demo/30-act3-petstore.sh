#!/usr/bin/env bash
# Act 3, part 1: pet store moves to the Secretless sidecar. App holds no password.
set -e
D="$(cd "$(dirname "$0")/../vm1-k8s" && pwd)"
"$D/22-migrate-petstore.sh"
"$D/90-status.sh"
