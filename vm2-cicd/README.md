# VM2: Jenkins + GitLab runner

Two CI tools, each proving its identity with a JWT, each getting a 2-hour deploy
token for exactly one namespace. No credential is stored in Jenkins or GitLab.

| Pipeline | Identity in Secrets Manager | Can deploy | Visible result |
|---|---|---|---|
| Jenkins `idira/boa-deploy` | `bank/cicd/jenkins/boa-deploy` | Bank of Anthos only | Bank name changes on the frontend |
| GitLab `idira-petstore-deploy` (main) | `bank/cicd/gitlab/<project path>` | Pet store only | Rolling restart, annotated with the pipeline id |

Each pipeline also tries the other's namespace and secret: both denied, both in the audit.
About 1 minute each, short enough for the panel.

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
   | `kube-server` | `bank/cicd/kube-server` |
   | `kube-ca` | `bank/cicd/kube-ca` |
   | `kube-token` | `bank/cicd/jenkins/kube-token` |
5. Inside the folder: **New Item > Pipeline** named `boa-deploy`. Pipeline script: paste `jenkins/Jenkinsfile` (or *from SCM* pointing at this repo, path `vm2-cicd/jenkins/Jenkinsfile`).
6. Run `./20-conjur-setup.sh` now (it reads the plugin's JWKS). Then **Build with Parameters**.

If JWT auth will not work in time: `./20-conjur-setup.sh --fallback-key`, and in step 2 pick API key auth with login `host/bank/cicd/jenkins/fallback`. That key only works from VM2's IP. Say so in the demo: it is the honest fallback, JWT is the target.

## GitLab steps (gitlab.com)

1. Create project `idira-petstore-deploy` under your user. Set `GITLAB_PROJECT_PATH` in `../lab.env` to `<user>/idira-petstore-deploy`.
2. **Settings > CI/CD > Runners > New project runner**: tag `idira-vm2`, *run untagged* off. Copy the `glrt-` token into `./11-install-gitlab-runner.sh`.
3. Commit `gitlab/.gitlab-ci.yml` to the project root on `main`. The pipeline starts by itself.
4. Bonus demo: push the same file on a branch `feature-x`. Same project, same runner, **denied**: policy only trusts `ref: main`.

## Troubleshooting

| Symptom | Look at |
|---|---|
| Jenkins 401 | leader log `grep authn-jwt`; issuer mismatch -> rerun with `JENKINS_ISSUER='http://VM2_IP:8080/'`; host id must equal the `jenkins_name` claim |
| GitLab 401 | `GITLAB_PROJECT_PATH` matches exactly; job runs on `main`; leader can reach `gitlab.com` |
| kubectl `Unauthorized` | token expired: rerun `vm1-k8s/25-cicd-deployers.sh` (that is the rotation) |
| kubectl x509 | k3s was installed before `--tls-san VM1_IP` was added: reinstall or use the node hostname |
