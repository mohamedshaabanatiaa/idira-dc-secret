# Policy: the bank's secrets model

Three files, one per concern. Applied by Security as admin, in this order.

**One click:** `update-policies.bat` (Windows, double-click) or `./update-policies.sh` (Linux). Both pull from Git, then run `conjur policy update` on all 3 files and stop on the first error. `update` adds and changes but never deletes what a file leaves out. Never use `policy replace`: it replaces a whole branch.

By hand:

```powershell
conjur policy update -b root -f root.yml             # the environments: prod, dev
conjur policy update -b prod -f prod.yml             # prod secrets, identities, rules
conjur policy update -b root -f authenticators.yml   # login doors (JWT authenticators)
```

Why separate files: each environment can get its own owner and review process (prod changes need approval, dev doesn't), and authenticators are platform plumbing owned by Security.

## The model in one picture

```
root
├── prod                         ENVIRONMENT
│   ├── secrets (variables)      boa/*, petstore/*, cicd/*, ai/*
│   ├── identities (hosts)       k8s/*, jenkins/*, gitlab/*, agents/*
│   ├── layers                   k8s/boa, k8s/petstore, jenkins/pipelines, gitlab/pipelines
│   └── rules (permit)           layer X may read + use secrets Y
├── dev                          ENVIRONMENT (empty: prod identities can't reach it)
└── conjur/authn-jwt/{k3s,jenkins,gitlab}    one login door per platform
```

## The 4 words you need

| Word | Meaning | Example |
|---|---|---|
| **policy** (branch) | A folder with an owner. We use it for environments | `prod`, `dev` |
| **variable** | A secret | `prod/boa/accounts-db/password` |
| **host** | One machine identity | `prod/k8s/system:serviceaccount:boa:secrets-provider` |
| **layer** | A group of hosts that get the same access | `prod/k8s/boa` |

One rule type: `!permit` a role (layer or host) `read` (see it exists) + `execute` (get the value) on variables.

## Who can read what

| Identity | Can read | Logs in with |
|---|---|---|
| layer `k8s/boa` | `boa/*` | Kubernetes service account JWT |
| layer `k8s/petstore` | `petstore/*` | Kubernetes service account JWT |
| layer `jenkins/pipelines` | `cicd/kube-server`, `cicd/kube-ca`, `cicd/jenkins-token` | Jenkins plugin JWT |
| layer `gitlab/pipelines` | `cicd/kube-server`, `cicd/kube-ca`, `cicd/gitlab-token` | GitLab ID token, main branch only |
| host `agents/support-agent` | `ai/anthropic-api-key` | API key, valid only from VM3's IP |
| host `agents/rogue-agent` | nothing | API key, valid only from VM3's IP |

## Prove it live (Windows CLI)

```powershell
conjur list -k variable                                              # every secret
conjur list -k host                                                  # every identity
conjur resource permitted-roles variable:prod/boa/accounts-db/password execute   # who can get this secret?
conjur role memberships host:prod/k8s/system:serviceaccount:boa:secrets-provider # what is this pod part of?
```

## Likely panel questions

- **What are the `authn-jwt/k3s/...` annotations on the hosts?** Extra checks on the token. Besides the name, the pod's token must also say namespace `boa` and service account `secrets-provider`. Secrets Manager requires at least one such check per JWT host (`CONJ00099E` otherwise).

- **Why a layer and not a permit per host?** Add a second pod or pipeline: put it in the layer, no rule changes.
- **Why `read` and `execute`?** `read` lets you see the secret exists (metadata, audit). `execute` returns the value. An auditor would get `read` only.
- **Where is dev?** Same structure, own branch. Nothing in prod is permitted on dev, so a prod pod can never fetch a dev secret, and the reverse.
- **Who changes policy?** Security, through Git and `conjur policy load` (or a pipeline). Every load is audited.
