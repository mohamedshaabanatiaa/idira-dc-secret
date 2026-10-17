#!/usr/bin/env bash
# Linux twin of update-policies.bat (VM1, VM2, VM3 or the Secrets Manager VM).
# Pulls the latest policy files from Git, then applies all 3 with "conjur policy update":
# adds and changes, never deletes what a file leaves out. Never "policy replace".
#   ./update-policies.sh
source "$(dirname "$0")/../common/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
log "git pull"
git -C "$HERE/.." pull --ff-only || warn "git pull failed, using the local files"
conjur_ready
apply() {  # apply <branch> <file>
  log "conjur policy update -b $1 -f $2"
  conjur policy update -b "$1" -f "$HERE/$2" || die "stopped at $2: the steps after it were not applied"
}
apply root root.yml
apply prod prod.yml
apply root authenticators.yml
ok "all 3 policies applied. Nothing was deleted."
