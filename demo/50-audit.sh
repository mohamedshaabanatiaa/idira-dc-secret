#!/usr/bin/env bash
# Audit, part 1 (VM1): who CAN get the Claude key? Policy answers yes/no.
K=variable:prod/ai/anthropic-api-key
H=host:prod/k8s/system:serviceaccount:agents
echo "== who can fetch the Claude key"; conjur resource permitted-roles "$K" execute
echo "== support-agent:"; conjur check "$K" execute -r "$H:support-agent"
echo "== rogue-agent:";   conjur check "$K" execute -r "$H:rogue-agent"
cat <<TXT

Audit, part 2 (UI): rogue-agent host -> denied attempts.
                    variable prod/petstore/db/password -> fetches + version number.
Audit, part 3 (Secrets Manager VM): ./secrets-manager/90-audit.sh petstore
TXT
