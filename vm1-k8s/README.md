# idira-k8s-lab

Two real apps on k3s, moved from hardcoded DB credentials to Idira Secrets Manager (Self-Hosted), with rotation and a full revert.

| App | Before | After | Refresh on rotation |
|---|---|---|---|
| Bank of Anthos (Google) | Passwords in ConfigMaps | Secrets Provider job fills K8s Secrets from Secrets Manager | Re-sync + rolling restart of the consumers only |
| Pet store (CyberArk demo) | Password in Deployment env | Secretless Broker sidecar, app holds no password | None. Same pod keeps working |

Two patterns on purpose: one for apps you can't touch (env vars, zero code change), one where the app never sees a credential at all.

## Where it runs

DevOps VM1 (Ubuntu), as root. VM1 must reach the Secrets Manager VM on 443 and the internet (image pulls).

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
./25-cicd-deployers.sh        # Jenkins/GitLab deploy tokens (2h) into Secrets Manager; rerun = rotate
./30-rotate-boa.sh            # rotate accounts-db   (--ledger for ledger-db)
./31-rotate-petstore.sh       # rotate pet store, no restart
./90-status.sh                # where do the credentials live right now?
./40-revert-boa.sh            # back to hardcoded, rehearse again
./41-revert-petstore.sh
./99-uninstall-k3s.sh         # nuke k3s
```

The admin password is prompted once per run. Or `export CONJUR_ADMIN_PASSWORD=...` in the shell. Never commit it.

## What gets created in Secrets Manager

```
conjur/authn-jwt/k3s                      JWT authenticator, trusts the k3s token issuer
bank/k8s/system:serviceaccount:boa:secrets-provider     host (layer bank/k8s/boa)
bank/k8s/system:serviceaccount:petstore:petstore-app    host (layer bank/k8s/petstore)
bank/boa/accounts-db/{username,password,uri}
bank/boa/ledger-db/{username,password}
bank/petstore/db/{address,username,password}
```

Each layer can read only its own app's secrets. Identity comes from the Kubernetes service account token (audience `conjur`), so there is no API key anywhere in the cluster.

## Demo flow (5 minutes)

1. `./90-status.sh` -> passwords visible in ConfigMaps and env. "This is what your auditors find."
2. `./21-migrate-boa.sh` -> ConfigMaps clean, app still works. Log in, send a payment.
3. `./22-migrate-petstore.sh` -> app env has no password, only a sidecar.
4. `./30-rotate-boa.sh` -> new password, only 2 deployments restart.
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
