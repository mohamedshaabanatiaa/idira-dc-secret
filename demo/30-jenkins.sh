#!/usr/bin/env bash
# Act 4: Jenkins. The run itself is in the Jenkins UI.
cat <<TXT
Jenkins: http://10.0.0.1:8080  ->  idira / boa-deploy  ->  Build with Parameters
Show in the console log:
  1. JWT login to Secrets Manager (no stored Jenkins credential)
  2. 2h deploy token fetched
  3. bank name changed on Bank of Anthos
  4. pet store namespace: Forbidden
Token expired? run ./02-preflight.sh again (or vm1-k8s/25-cicd-deployers.sh)
TXT
