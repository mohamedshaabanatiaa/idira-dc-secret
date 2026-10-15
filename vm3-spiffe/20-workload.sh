#!/usr/bin/env bash
# Demo: a VM batch job gets its secret with a SPIFFE identity. No password anywhere.
#   ./20-workload.sh             as user "settlement" (registered)  -> gets its one secret
#   ./20-workload.sh intruder    same VM, other user (not registered) -> no identity
# Run on VM3 as root.
source "$(dirname "$0")/../common/lib.sh"
WHO="${1:-settlement}"
install -m 755 "$(dirname "$0")/workload.sh" /opt/spire/bin/workload.sh
runuser -u "$WHO" -- /opt/spire/bin/workload.sh "$CONJUR_URL" "$CONJUR_ACCOUNT" /opt/spire/conf/conjur.pem
