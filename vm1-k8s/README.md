# idira-k8s-lab

Two real apps on k3s, moved from hardcoded DB credentials to Idira Secrets Manager (Self-Hosted), with rotation and a full revert.

| App | Before | After | Refresh on rotation |
|---|---|---|---|
| Bank of Anthos (Google) | Passwords in ConfigMaps | Secrets Provider job fills K8s Secrets from Secrets Manager | Re-sync + rolling restart of the consumers only |
| Pet store (CyberArk demo) | Password in Deployment env | Secretless Broker sidecar, app holds no password | None. Same pod keeps working |

Two patterns on purpose: one for apps you can't touch (env vars, zero code change), one where the app never sees a credential at all.

## Where it runs

DevOps VM1 (Ubuntu), as root. VM1 must reach the Secrets Manager VM on 443 and the internet (image pulls).

See ../ROTATION.md for which rotation to show and why nothing breaks.

## Order

```bash
vi ../lab.env                 # CONJUR_HOST, CONJUR_IP, CONJUR_ACCOUNT, VM IPs (lab-wide)
./00-install-k3s.sh           # k3s, jq, /etc/hosts entry for the leader
./10-install-boa.sh           # Bank of Anthos, original state
./11-install-petstore.sh      # Pet store, original state
./20-conjur-setup.sh          # cert, authn-jwt/k3s, identities, secrets, grants
#  -> one manual step on the leader (script prints it): allowlist authn-jwt/k3s
./21-migrate-boa.sh           # BoA -> Secrets Manager
./22-migrate-petstore.sh      # Pet store -> Secretless
./23-native-rotation-petstore.sh  # Secrets Manager rotates the pet store DB password itself (PT5M)
./25-cicd-deployers.sh        # Jenkins/GitLab deploy tokens (2h) into Secrets Manager; rerun = rotate
./30-rotate-boa.sh            # rotate accounts-db   (--ledger for ledger-db)
./31-rotate-petstore.sh       # rotate pet store, no restart (--kick drops open connections)
./90-status.sh                # where do the credentials live right now?
./40-revert-boa.sh            # back to hardcoded, rehearse again
./41-revert-petstore.sh
./99-uninstall-k3s.sh         # nuke k3s
```

The admin password is prompted once per run. Or `export CONJUR_ADMIN_PASSWORD=...` in the shell. Never commit it.

## What it uses in Secrets Manager

Defined in `../policies/prod.yml` (loaded from the Windows CLI first):

```
prod/k8s/system:serviceaccount:boa:<workload>            7 hosts, layer prod/k8s/boa (one per microservice)
prod/k8s/system:serviceaccount:petstore:petstore-app     host, layer prod/k8s/petstore
prod/boa/accounts-db/{password,uri}, prod/boa/ledger-db/password
prod/petstore/db/{host,port,username,password}
```

Each identity can read only what it uses. Identity comes from the Kubernetes service account token (audience `conjur`), so there is no API key anywhere in the cluster.

## Bank of Anthos: one identity per microservice (since 19 Oct)

Before: one shared sync Job (service account `secrets-provider`) fetched all three Bank of Anthos secrets and every service shared two Kubernetes Secrets.

Now every workload has its own service account, its own host in Secrets Manager, and its own permit:

| Workload | Service account = host | Gets only | Kubernetes Secret |
|---|---|---|---|
| accounts-db (database) | `boa:accounts-db` | `prod/boa/accounts-db/password` | `accounts-db-creds` |
| userservice (login) | `boa:userservice` | `prod/boa/accounts-db/uri` | `userservice-creds` |
| contacts | `boa:contacts` | `prod/boa/accounts-db/uri` | `contacts-creds` |
| ledger-db (database) | `boa:ledger-db` | `prod/boa/ledger-db/password` | `ledger-db-creds` |
| ledgerwriter (payments) | `boa:ledgerwriter` | `prod/boa/ledger-db/password` | `ledgerwriter-creds` |
| balancereader | `boa:balancereader` | `prod/boa/ledger-db/password` | `balancereader-creds` |
| transactionhistory | `boa:transactionhistory` | `prod/boa/ledger-db/password` | `transactionhistory-creds` |

How it works:
1. Each pod has a Secrets Provider **init container** running as the pod's own service account.
2. It logs in through `authn-jwt/k3s` with that service account token (audience `conjur`).
3. It fills only its own Kubernetes Secret. A Role lets that service account `get`/`update` that one Secret, nothing else.
4. The app container starts after it and reads the Secret with `envFrom`. Zero code change.
5. Refresh or rotation = restart the workload (`./sync-boa.sh`). The init container fetches again.

What it proves: no microservice can read the other database's secrets, and every fetch in the audit log names the exact microservice.

Limit, honestly: the services of one database still share one database user, so per-service identity gives least privilege on Secrets Manager and per-service audit, not separate database rights. Next step in production: one database user per service, read-only where possible (balancereader, transactionhistory).

Moving an existing lab to this model: load `prod.yml` (update), then once `conjur policy update -b prod -f once-boa-per-service.yml` (removes the old shared rule and host), then `../demo/00-reset.sh` and `../demo/01-prepare.sh`.

Roll back: `git checkout 46f6cf7 -- policies/prod.yml demo/01-prepare.sh vm1-k8s/` then reload prod.yml and reset.

## Demo flow (5 minutes)

1. `./90-status.sh` -> passwords visible in ConfigMaps and env. "This is what your auditors find."
2. `./21-migrate-boa.sh` -> ConfigMaps clean, app still works. Log in, send a payment.
3. `./22-migrate-petstore.sh` -> app env has no password, only a sidecar.
4. `./30-rotate-boa.sh` -> new password, only 2 deployments restart, each refetches with its own identity.
5. `./31-rotate-petstore.sh` -> new password, same pod, zero restarts.
6. Secrets Manager audit (UI or `/audit` on the leader): every fetch tied to a named workload identity.

## Verify on day 1 (untested in your exact lab)

- [ ] Leader cert SAN contains `CONJUR_HOST`. If not, use the hostname that is in it.
- [ ] API path: `curl --cacert .conjur-cert.pem https://$CONJUR_HOST/info`. If 404, set `CONJUR_API_PREFIX="/api"`.
- [ ] `authn-jwt/k3s` shows as enabled in `/info` after `evoke configuration apply`.
- [ ] `cyberark/demo-app` boots behind Secretless with `sslmode=disable` (if Spring complains, drop `?sslmode=disable` from DB_URL).
- [ ] Image tags in `config.env` exist (`docker pull` from VM1 or check Docker Hub).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `sync failed`, 401 in job log | authenticator not allowlisted, or host id does not match `sub` |
| 401 with "audience" | projected token audience must be `conjur` |
| x509 error | cert hostname, or hostAliases IP wrong |
| 403 on a variable | layer not granted to the consumers group |
| Pet store CrashLoop on start | Spring started before Secretless; it recovers after a restart or two |

Authenticator log on the leader: `docker logs <conjur container> 2>&1 | grep -i authn-jwt` (or the appliance log path for your install).

## Production notes (for Q&A, not for the lab)

- Secrets Provider in **standalone** mode on a schedule + Reloader replaces the manual job + restart.
- Followers next to the cluster for read scale; the leader stays the write point.
- DB rotation by a rotator (or PAM) instead of `openssl rand` in a script.
