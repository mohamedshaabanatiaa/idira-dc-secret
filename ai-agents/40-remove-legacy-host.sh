#!/usr/bin/env bash
# One-time cleanup: deletes the day-2 host prod/agents/support-agent (old API-key design).
# "policy load" only adds, so it was never removed and still had access to the Claude key.
source "$(dirname "$0")/../vm1-k8s/lib.sh"
conjur_ready
f=$(mktemp)
printf -- '- !delete\n  record: !host agents/support-agent\n' > "$f"
conjur policy update -b prod -f "$f" >/dev/null && ok "deleted host prod/agents/support-agent"
rm -f "$f"
echo "  Who can use the Claude key now:"
conjur resource permitted-roles "${CONJUR_ACCOUNT}:variable:prod/ai/anthropic-api-key" execute | sed 's/^/   /'
