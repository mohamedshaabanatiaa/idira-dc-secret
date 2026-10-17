#!/usr/bin/env bash
# Linux twin of update-policies.bat (VM1, VM3 or the Secrets Manager VM).
# Pulls the latest policy files, then applies all 3 with "conjur policy update":
# adds and changes, never deletes what a file leaves out. Never "policy replace".
# Needs the Conjur CLI logged in as admin (conjur login -i admin).
set -euo pipefail
cd "$(dirname "$0")"

echo "== git pull"
git pull --ff-only || echo "   warn: git pull failed, using the local files"

echo "== Logged in as:"
conjur whoami

echo "== 1/3 conjur policy update -b root -f root.yml             (environments: prod, dev)"
conjur policy update -b root -f root.yml

echo "== 2/3 conjur policy update -b prod -f prod.yml             (secrets, identities, permits)"
conjur policy update -b prod -f prod.yml

echo "== 3/3 conjur policy update -b root -f authenticators.yml   (login doors: k3s, jenkins, gitlab, spire)"
conjur policy update -b root -f authenticators.yml

echo "== Done: all 3 policies applied. Nothing was deleted."
