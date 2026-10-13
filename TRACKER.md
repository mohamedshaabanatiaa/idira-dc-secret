# Lab tracker

Live state of the lab. **No passwords here** (tracked outside the repo).

## Environment

| Item | Value | Status |
|---|---|---|
| Access | MobaXterm on the Windows jump host, SSH as `skytap`, then `sudo -i` | ok |
| Repo on VMs | `/opt/idira` (private, read-only GitHub token) | cloned on VM1-3 |

| VM | Hostname | IP | Disk / | RAM | Role | Status |
|---|---|---|---|---|---|---|
| Windows jump host | | | | | Browser, Conjur CLI 9.3.0, MobaXterm | **CLI logged in as admin** |
| Secrets Manager | sm (was ubn2510) | 10.0.0.2 | 37 GB (extended) | 15 GB | Leader | **leader up** |
| DevOps VM1 | vm1 (was ubn2510) | 10.0.0.3 | extended | 4 CPU | k3s + Bank of Anthos + pet store | **k3s, Bank of Anthos and pet store running (before state)** |
| DevOps VM2 | vm2 (was ubn2510) | 10.0.0.1 | extended | | Jenkins + GitLab runner | repo cloned |
| DevOps VM3 | vm3 (was ubn2510) | 10.0.0.5 | extended | | AI agent | repo cloned |

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
| Policy | `policies/root.yml`, `prod.yml`, `authenticators.yml` loaded from Windows CLI (13 Oct). 11 secrets under `prod/`, 3 JWT authenticators defined (not yet enabled/configured) |
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
| 1 (13 Oct) | Docker, leader installed + configured, disk extended on all VMs, UI login, Windows CLI logged in, hostnames, repo on VM1-3, k3s, Bank of Anthos (2 fixes), pet store, policy loaded | Enable authenticators on leader, connect VM1 (20, 21, 22) |

## Issues log

| When | Issue | Fix |
|---|---|---|
| 13 Oct | `/` only 19 GB of a 40 GB disk (Ubuntu LVM default) | `lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` |
| 13 Oct | `evoke configure leader`: "leader altnames not valid" | removed `--leader-altnames` |
| 13 Oct | all VMs shipped with hostname `ubn2510` | renamed sm/vm1/vm2/vm3, `/etc/hosts` on each |
| 13 Oct | Bank of Anthos pods crash: `DefaultCredentialsError` (Google Cloud Trace on by default) | `kubectl set env ... ENABLE_TRACING=false ENABLE_METRICS=false`, now in `10-install-boa.sh` |
| 13 Oct | BoA Java services: `NullPointerException ... CgroupV2Subsystem` (JDK in image can't read Ubuntu 25.10 cgroup v2) | `JAVA_TOOL_OPTIONS=-XX:-UseContainerSupport -Xms256m -Xmx512m` injected by `10-install-boa.sh` |
| 13 Oct | Secrets Provider 401: leader log `CONJ00099E Role must have at least one relevant annotation` | every JWT host needs at least one claim annotation: added `authn-jwt/k3s/kubernetes.io/namespace` + `serviceaccount/name` (and `jenkins_full_name` for Jenkins) in `prod.yml` |
| 13 Oct | nginx "cannot load certificate" during configure | harmless, cert created later in the run |
