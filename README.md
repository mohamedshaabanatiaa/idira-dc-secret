# idira-dc-secret

Idira Secrets technical challenge lab (Skytap, 5 VMs). One folder per VM.

| Folder | VM | What runs there | Status |
|---|---|---|---|
| `secrets-manager/` | Secrets Manager VM | Self-Hosted leader install, authenticator allowlist | next |
| `vm1-k8s/` | DevOps VM1 | k3s, Bank of Anthos, pet store, migrate, rotate, revert | ready to test |
| `vm2-cicd/` | DevOps VM2 | Jenkins + GitLab runner (shell executor, outbound only) | next |
| `vm3-ai-agent/` | DevOps VM3 | AI agent with its own workload identity + rogue agent | next |

Windows jump host: Conjur CLI and browser only, nothing to install from here.

Rules: no real passwords in this repo. Admin password is prompted at runtime.
