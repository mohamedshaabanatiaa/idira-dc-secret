# Readiness

Run this on every VM before anything else, and again after every Skytap resume.

## 1. Get the repo onto a VM (Ubuntu, as root)

```bash
sudo -i
apt-get update -qq && apt-get install -y git curl jq openssl
git --version
```

The repo is private, so cloning needs a GitHub token. Create a **fine-grained token** at
GitHub → Settings → Developer settings → Personal access tokens → Fine-grained:
- Repository access: only `idira-dc-secret`
- Permissions: Contents → **Read-only**
- Expiry: 7 days (the lab lasts 5)

```bash
# keep the token in memory for 5 days, never on disk
git config --global credential.helper 'cache --timeout=432000'
git clone https://github.com/mohamedshaabanatiaa/idira-dc-secret.git /opt/idira
#   Username: mohamedshaabanatiaa
#   Password: <paste the token>
cd /opt/idira
```

## 2. Daily commands

```bash
cd /opt/idira
git pull                      # get the latest scripts
git log --oneline -5          # what changed
git status                    # local edits? (config.env is expected)
git stash && git pull && git stash pop   # pull without losing your config.env edits
```

If `git pull` asks for a password again, the cache expired: paste the token again.

## 3. Check the VM

```bash
./readiness/check.sh sm     # on the Secrets Manager VM
./readiness/check.sh vm1    # DevOps VM1 (k3s + apps)
./readiness/check.sh vm2    # DevOps VM2 (Jenkins + GitLab runner)
./readiness/check.sh vm3    # DevOps VM3 (AI agent)
```

It checks sizing, clock, outbound access per role, and that the Secrets Manager leader answers on 443.
Red = fix before you build. Yellow = know about it.

## 4. After every Skytap resume

Suspend/resume makes the VM clock drift. JWT logins fail with a clock that is off by more than a few minutes, and the error looks like an auth problem.

```bash
timedatectl                                # "System clock synchronized: yes"
systemctl restart systemd-timesyncd        # if not
./readiness/check.sh <role>
```

## 5. Windows jump host

Nothing from this repo runs there. Use it for the browser (Secrets Manager UI) and the Conjur CLI:

```powershell
conjur --version
conjur init -u https://<CONJUR_HOST> -a <account> --self-signed
conjur login -i admin
conjur whoami
```
