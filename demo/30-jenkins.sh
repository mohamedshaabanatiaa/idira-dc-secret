#!/usr/bin/env bash
# Act: Jenkins. After ./00-reset.sh the pipeline has NO deploy access: build once to show
# it fail, then run this script (issues a 2h deploy token into Secrets Manager), build again.
set -e
"$(dirname "$0")/../vm1-k8s/25-cicd-deployers.sh" >/dev/null
echo "Fresh 2h deploy token stored in Secrets Manager (revoke all: ../vm1-k8s/26-revoke-deployers.sh)."
cat <<TXT

Jenkins: http://10.0.0.1:8080  ->  idira / boa-deploy  ->  Build with Parameters
Show in the console log:
  1. JWT login to Secrets Manager (no stored Jenkins credential)
  2. 2h deploy token fetched
  3. bank name changed on Bank of Anthos
  4. pet store namespace: Forbidden
TXT
