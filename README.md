# idira-dc-secret

Idira Secrets technical challenge lab (Skytap, 5 VMs). One folder per VM.

| Folder | VM | What runs there | Status |
|---|---|---|---|
| `readiness/` | every VM | install git, clone, pull, per-VM checks, after-resume fixes | ready |
| `secrets-manager/` | Secrets Manager VM | Self-Hosted leader install, authenticator allowlist, audit | ready to test |
| `vm1-k8s/` | DevOps VM1 | k3s, Bank of Anthos, pet store, migrate, rotate, revert | ready to test |
| `vm2-cicd/` | DevOps VM2 | Jenkins + GitLab runner, JWT auth, scoped deploys to k3s | ready to test |
| `vm3-ai-agent/` | DevOps VM3 | Claude agent with its own identity, rogue agent, kill switch | ready to test |

Edit `lab.env` once (IPs, leader hostname, account). Every VM reads it.

## Build order

1. All VMs: `readiness/` (git, clone, `check.sh`)
2. Secrets Manager VM: `secrets-manager/10`, `20`
3. VM1: `vm1-k8s/00`, `10`, `11`, `20`, `21`, `22`, `23`, then `25`
4. VM2: `vm2-cicd/10`, Jenkins UI steps, `11`, `20`
5. VM3: `vm3-ai-agent/10`

Rotation story and why nothing breaks: [ROTATION.md](ROTATION.md).

Start here: [readiness/README.md](readiness/README.md).

Windows jump host: Conjur CLI and browser only, nothing to install from here.

Rules: no real passwords in this repo. Admin password is prompted at runtime.
