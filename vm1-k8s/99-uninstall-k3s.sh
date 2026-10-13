#!/usr/bin/env bash
# Removes k3s completely from the VM. Secrets Manager policy is untouched.
source "$(dirname "$0")/lib.sh"
read -r -p "Remove k3s and every app on this VM? [y/N] " a
[[ "$a" == "y" ]] || exit 0
/usr/local/bin/k3s-uninstall.sh
ok "k3s removed"
