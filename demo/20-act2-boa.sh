#!/usr/bin/env bash
# Act 2: Bank of Anthos moves to Secrets Manager (Secrets Provider). No code change.
set -e
D="$(cd "$(dirname "$0")/../vm1-k8s" && pwd)"
"$D/21-migrate-boa.sh"
"$D/90-status.sh"
echo; echo "Now: browser http://<VM1 IP>/, log in, send a payment."
