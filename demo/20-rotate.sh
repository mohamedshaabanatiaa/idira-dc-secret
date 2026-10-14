#!/usr/bin/env bash
# Act 3, part 2: rotate the pet store DB password. Same pod, no restart.
exec "$(dirname "$0")/../vm1-k8s/31-rotate-petstore.sh" --kick
