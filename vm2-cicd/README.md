# VM2: Jenkins + GitLab runner

Two CI tools, each proving its identity with a JWT, each getting a 2-hour deploy
token for exactly one namespace. No credential is stored in Jenkins or GitLab.

| Pipeline | Identity in Secrets Manager | Can deploy | Visible result |
|---|---|---|---|
| Jenkins `idira/boa-deploy` | `prod/jenkins/boa-deploy` | Bank of Anthos only | Bank name changes on the frontend |
| GitLab `idira-petstore-deploy` (main) | `prod/gitlab/mohamedshaabanatiaa/idira-petstore-deploy` | Pet store only | Release recorded on the Deployment, no restart (`RESTART=true` for a real rolling restart) |

Each pipeline also tries the other's namespace and secret: both denied, both in the audit.
About 1 minute each, short enough for the panel.

**Safe by design:** preflight health check, server-side dry run, rolling update (old pod serves until the new one is Ready), automatic rollback. To undo the Jenkins change: run it again with `BANK_NAME='Bank of Anthos'`.

Run `vm1-k8s/25-cicd-deployers.sh` within 2 hours of the demo (or `TOKEN_TTL=8h`), so the tokens have not expired. An expired token fails the pipeline, never the app.

## Order

```bash
../readiness/check.sh vm2
./10-install-jenkins.sh            # Jenkins LTS + plugins, admin user, no wizard
#    -> Jenkins UI steps below
./11-install-gitlab-runner.sh      # runner + conjur-fetch helper (needs the glrt- token)
#    -> on VM1 first: ./25-cicd-deployers.sh
./20-conjur-setup.sh               # authn-jwt/jenkins + authn-jwt/gitlab + identities
```

## Jenkins UI steps (from the Windows jump host, http://VM2_IP:8080)

1. **Manage Jenkins > Credentials > System > Global > Add credentials**, kind *Secret file* or *Certificate*: upload `/etc/idira/conjur.pem` (copy it to the jump host, or paste). ID `conjur-cert`.
2. **Manage Jenkins > System > Secrets Manager Configuration**
   - Authentication type: **JWT**
   - Account: `bank` (your `CONJUR_ACCOUNT`)
   - Appliance URL: `https://<CONJUR_HOST>`
   - SSL certificate: `conjur-cert`
   - **JWT Authentication**: Service ID `authn-jwt/jenkins`, Audience `conjur`, Signing Key Lifetime `10080`, Token Duration `120`, *Enable Identity Format Fields* **off**
   - Save. Check `curl http://localhost:8080/jwtauth/conjur-jwk-set` on VM2 returns keys.
3. **New Item > Folder** named `idira`.
4. Inside the folder: **Credentials > Add**, kind **Secrets Manager Secret Credentials**, three times:

   | ID | Variable path |
   |---|---|
   | `kube-server` | `prod/cicd/kube-server` |
   | `kube-ca` | `prod/cicd/kube-ca` |
   | `kube-token` | `prod/cicd/jenkins-token` |
5. Inside the folder: **New Item > Pipeline** named `boa-deploy`. Pipeline script: paste `jenkins/Jenkinsfile` (or *from SCM* pointing at this repo, path `vm2-cicd/jenkins/Jenkinsfile`).
6. Run `./20-conjur-setup.sh` now (it reads the plugin's JWKS). Then **Build with Parameters**.


## GitLab steps (gitlab.com)

1. Create project `idira-petstore-deploy` under your user. If the path is not `mohamedshaabanatiaa/idira-petstore-deploy`, change the gitlab host id in `../policies/bank.yml` and reload it.
2. **Settings > CI/CD > Runners > New project runner**: tag `idira-vm2`, *run untagged* off. Copy the `glrt-` token into `./11-install-gitlab-runner.sh`.
3. Commit `gitlab/.gitlab-ci.yml` to the project root on `main`. The pipeline starts by itself.
4. Bonus demo: push the same file on a branch `feature-x`. Same project, same runner, **denied**: policy only trusts `ref: main`.

## Troubleshooting

| Symptom | Look at |
|---|---|
| Jenkins 401 | leader log `grep authn-jwt`; issuer mismatch -> rerun with `JENKINS_ISSUER='http://VM2_IP:8080/'`; host id must equal the `jenkins_name` claim |
| GitLab 401 | host id in `policies/bank.yml` matches the project path exactly; job runs on `main`; leader can reach `gitlab.com` |
| kubectl `Unauthorized` | token expired: rerun `vm1-k8s/25-cicd-deployers.sh` (that is the rotation) |
| kubectl x509 | k3s was installed before `--tls-san VM1_IP` was added: reinstall or use the node hostname |
