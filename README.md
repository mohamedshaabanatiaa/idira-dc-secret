# idira-dc-secret

Idira Secrets technical challenge lab (Skytap, 5 VMs). One folder per VM.

| Folder | VM | What runs there | Status |
|---|---|---|---|
| `readiness/` | every VM | install git, clone, pull, per-VM checks, after-resume fixes | ready |
| `secrets-manager/` | Secrets Manager VM | Self-Hosted leader install, authenticator allowlist, audit | ready to test |
| `vm1-k8s/` | DevOps VM1 | k3s, Bank of Anthos, pet store, migrate, rotate, revert | ready to test |
| `vm2-cicd/` | DevOps VM2 | Jenkins + GitLab runner, JWT auth, scoped deploys to k3s | ready to test |
| `ai-agents/` | DevOps VM1 (k3s) | Claude agent pod with its own signed identity, Secretless injects the key, rogue agent, kill switch | ready to test |

Edit `lab.env` once (IPs, leader hostname, account). Every VM reads it.

## Build order

1. All VMs: `readiness/` (git, clone, `check.sh`)
2. Secrets Manager VM: `secrets-manager/10`, `20`
3. VM1: `vm1-k8s/00`, `10`, `11`, `20`, `21`, `22`, `23`, then `25`
4. VM2: `vm2-cicd/10`, Jenkins UI steps, `11`, `20`
5. VM1: `ai-agents/10` (agents run as pods; VM3 is spare)

Live lab state: [TRACKER.md](TRACKER.md). Rotation story and why nothing breaks: [ROTATION.md](ROTATION.md).

Start here: [readiness/README.md](readiness/README.md).

Windows jump host: Conjur CLI and browser only, nothing to install from here.

Rules: no real passwords in this repo. Admin password is prompted at runtime.
