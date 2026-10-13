# Lab tracker

Live state of the lab. **No passwords here** (tracked outside the repo).

## Environment

| Item | Value | Status |
|---|---|---|
| Access | MobaXterm on the Windows jump host, SSH as `skytap`, then `sudo -i` | ok |
| Repo on VMs | `/opt/idira` (private, read-only GitHub token) | pending |

| VM | Hostname | IP | Disk / | RAM | Role | Status |
|---|---|---|---|---|---|---|
| Windows jump host | | | | | Browser, Conjur CLI 9.3.0, MobaXterm | **CLI logged in as admin** |
| Secrets Manager | ubn2510 | 10.0.0.2 | 37 GB (extended) | 15 GB | Leader | **leader up** |
| DevOps VM1 | | | extend pending | | k3s + Bank of Anthos + pet store | pending |
| DevOps VM2 | | | extend pending | | Jenkins + GitLab runner | pending |
| DevOps VM3 | | | extend pending | | AI agent | pending |

## Secrets Manager

| Item | Value |
|---|---|
| Version | Self-Hosted 13.10.0 (`registry.tld/conjur-appliance:13.10.0`) |
| Install files | `/home/skytap/Secrets Manager Self-Hosted Appliance/` (+ CLI, Secretless, Summon, OpenShift/K8s components, signing key) |
| Container | `conjur-leader`, Docker, network `conjur`, restart unless-stopped |
| Security | CyberArk seccomp profile, `AUDIT_WRITE`, journald logging |
| Data on host | `/opt/cyberark/conjur/{config,security,backups,seeds,logs}` |
| Hostname | `conjur-leader.bank.local` |
| Cert SAN | `conjur-leader.bank.local`, `localhost`, `conjur` (self-signed) |
| Account | `bank` |
| Admin user | `admin` |
| Topology | single node (leader). Production: + 2 standbys, followers per cluster/region |
| UI | `https://conjur-leader.bank.local` (Windows hosts entry `10.0.0.2 conjur-leader.bank.local` added), admin login ok |
| Windows CLI | `C:\Program Files\Conjur\conjur.exe` (from Desktop\Secrets Manager CLI, `conjur_windows_amd64.exe`), on PATH, `conjur init -u https://conjur-leader.bank.local -a bank --self-signed` |
| Linux CLI | `conjur-cli_9.3.0_amd64.deb` in the same Desktop folder (copy to VMs via MobaXterm SFTP) |
| Role in `/info` | `master` (= leader, legacy name in the API) |

## Decisions

- Docker (no runtime on the VM; appliance ships as a container image only).
- Seccomp: CyberArk profile from the image, not `unconfined`.
- `--leader-altnames` dropped: single node, hostname already in the cert.
- Build every VM in its "before" state (hardcoded secrets) first, then migrate.

## Progress

| Day | Done | Next |
|---|---|---|
| 1 (13 Oct) | Docker, leader installed + configured, disk extended on SM VM, UI login, Windows CLI logged in | Disks + repo on VM1-3, VM1 baseline (k3s + apps), bank policy model |

## Issues log

| When | Issue | Fix |
|---|---|---|
| 13 Oct | `/` only 19 GB of a 40 GB disk (Ubuntu LVM default) | `lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` |
| 13 Oct | `evoke configure leader`: "leader altnames not valid" | removed `--leader-altnames` |
| 13 Oct | nginx "cannot load certificate" during configure | harmless, cert created later in the run |
