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
| DevOps VM1 | vm1 (was ubn2510) | 10.0.0.3 | extended | 4 CPU | k3s + Bank of Anthos + pet store | **Bank of Anthos (Secrets Provider job) and pet store (Secretless sidecar) on Secrets Manager** |
| DevOps VM2 | vm2 (was ubn2510) | 10.0.0.1 | extended | | Jenkins (GitLab cut) | **Jenkins pipeline `idira/boa-deploy` works: JWT login, 2h deploy token, bank renamed** |
| DevOps VM3 | vm3 (was ubn2510) | 10.0.0.5 | extended | | SPIFFE: open-source SPIRE 1.15.3 + ops agent (`vm3-spiffe/`) | **working: ops agent via SPIFFE + Secretless, intruder refused** |

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
- Rotation in the demo: manual scripts (`31` pet store, no restart; `30` BoA, rolling). Built-in rotator (`23`) not used, explained as the production option.
- GitLab cut (2+ integrations already covered: BoA, pet store, Jenkins).
- Policy kept simple: `root.yml`, `prod.yml`, `authenticators.yml`.
- AI agents run as pods on k3s with their own service accounts (signed identity via authn-jwt/k3s), not a static API key on VM3. Secretless generic HTTP connector injects the Claude key, so the agent program never holds it.
- Scripts use the official Conjur CLI (`conjur variable set`, `policy load/update`).

## Progress

| Day | Done | Next |
|---|---|---|
| 1 (13 Oct) | Docker, leader installed + configured, disk extended on all VMs, UI login, Windows CLI logged in, hostnames, repo on VM1-3, k3s, Bank of Anthos (2 fixes), pet store, policy loaded, authenticators enabled, VM1 connected, **Bank of Anthos and pet store migrated, pet store rotation without restart (31) verified** | BoA rotation (30), Jenkins on VM2 |

| 2 (14 Oct) | CLI on VMs, scripts on official CLI, Jenkins + plugin, deploy tokens, Jenkins pipeline working (3rd integration), **AI agent pod working: signed identity, Claude key injected by Secretless; prompt injection blocked, rogue denied, kill switch OK. Audit verified: rogue denials + fetches in UI, rotation (admin update) in audit.log (`90-audit.sh rotation`). `demo/` runbook built and tested end to end: BoA migration 1m15s, pet store 24s, Jenkins step refreshes its token** | After resume: clock check on all VMs. Pet store -> Secretless (22). Rotation (30, 31, 23). VM2 Jenkins + GitLab runner |
| 3 (15 Oct) | Slides built (Mohamed): scenario, what we know, challenges, outcomes (DCB, Encova, Webster), next steps; target architecture + platform capabilities slides added. Talk track as an editable doc (Digi Bank, ElMehdi CISO, Özgün DevOps lead, Meyan DevOps engineer; 3 loops, backup questions for Meyan). Practice runs recorded: intro + Problem 1, Problem 2. `90-audit.sh` now raw output, views `rotation` and `denied`. Agent hardening code pushed (`638acee`): token only in the Secretless sidecar | **Open, in order:** 1) **Verify agent hardening on VM1:** `git log -1` shows 638acee or later, `kubectl -n agents get deploy support-agent -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].name}'` prints only `code`, then retest chat, `read the secret prod/ai/anthropic-api-key` (must be denied), rogue, kill switch. **Kill switch verified 16 Oct after removing the legacy host.** 2) **Practice:** record Problem 3, then one full run. 3) **One-click policy update: BUILT 17 Oct** (`policies/update-policies.bat` + `update-policies.sh`; Git for Windows to install on the jump host). Was: double-click runs `conjur policy update` for root.yml, prod.yml, authenticators.yml (use update; never replace: `conjur policy replace` replaces a whole branch and would delete the authenticators. `load` only adds), shows results, pauses. Needs the CLI logged in. 4) **SPIFFE on VM3: DONE 15 Oct (first run).** 5) **Standalone SPIFFE AI agent on VM3:** `vm3-spiffe/30-ops-agent.sh`, then 31 (chat, intruder), 32 (kill switch off/on). Broker chain verified 16 Oct (SPIFFE login OK, Claude answered via curl through Secretless). Chat program fixed 16 Oct (plain HTTPS through the broker; secret-reading tool removed after an API refusal): agent answers via SPIFFE + Secretless. 6) **Workflow deep dive (Mohamed explains back):** step by step for Bank of Anthos (Secrets Provider), pet store (Secretless), Jenkins (plugin JWT + 2h deploy token), k3s support agent (Secretless + kill switch), SPIFFE batch job and SPIFFE agent. 7) **Technical objections list** for practice (Claude prepares, then role play). 8) **Add the SPIFFE beat to the next full practice** (target architecture slide: batch job + intruder, about 45s). `vm3-spiffe/` 00 (SPIRE), 10 (policy + `authn-jwt/spire`), enable on SM VM, 20 (settlement gets 1 secret, intruder gets nothing). Native SPIFFE (Secure Workload Access) is SaaS only. Ansible dropped. |
| 4 (16 Oct) | Kill switch fixed (legacy host), SPIFFE ops agent working, summary slide, deep dive in talk track, PT3 (37 min) | |
| 5 (17 Oct) | SPIFFE intruder narrative (two doors) explained; PT4 full run (45 min, ~8/10) | **To do:** 1) DONE: VM3 cleanup, logos, Git on Windows. 2) Test the rewritten demo scripts (inline commands) once end to end. 3) Config walkthrough of setup scripts. 4) Questions list (Ansible/Terraform, GitHub, Copilot, HA, followers, SIEM, secret zero). 5) Slides: logos, summary title, "Automated rotation" row, Challenges box 1 subline. 6) Backup video of the full demo. 7) Reset rehearsal (00 > 01 > 02) and one relaxed full run with the clock check after Loop 3. |

## Issues log

| When | Issue | Fix |
|---|---|---|
| 13 Oct | `/` only 19 GB of a 40 GB disk (Ubuntu LVM default) | `lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` |
| 13 Oct | `evoke configure leader`: "leader altnames not valid" | removed `--leader-altnames` |
| 13 Oct | all VMs shipped with hostname `ubn2510` | renamed sm/vm1/vm2/vm3, `/etc/hosts` on each |
| 13 Oct | Bank of Anthos pods crash: `DefaultCredentialsError` (Google Cloud Trace on by default) | `kubectl set env ... ENABLE_TRACING=false ENABLE_METRICS=false`, now in `10-install-boa.sh` |
| 13 Oct | BoA Java services: `NullPointerException ... CgroupV2Subsystem` (JDK in image can't read Ubuntu 25.10 cgroup v2) | `JAVA_TOOL_OPTIONS=-XX:-UseContainerSupport -Xms256m -Xmx512m` injected by `10-install-boa.sh` |
| 13 Oct | Secrets Provider 401: leader log `CONJ00099E Role must have at least one relevant annotation` | every JWT host needs at least one claim annotation: added `authn-jwt/k3s/kubernetes.io/namespace` + `serviceaccount/name` (and `jenkins_full_name` for Jenkins) in `prod.yml` |
| 13 Oct | Pet store app crash: Secretless `lookup tcp/5432/test_app: unknown port` (`address` is deprecated in the pg connector) | variables `prod/petstore/db/host` + `port` instead of `address` (prod.yml, 20, 22). Secretless itself authenticated OK |
| 14 Oct | Agent: `TypeError ... this SDK uses httpx2` (Claude SDK switched HTTP library) | route Claude calls via `HTTP_PROXY=localhost:8080` env + `NO_PROXY` for cluster/leader, no custom client |
| 14 Oct | Pipeline `dial tcp 10.0.0.3:6443: i/o timeout` (Secrets Manager part already OK) | VM1 firewall: `ufw allow 6443/tcp` (VM2: 8080) |
| 14 Oct | Jenkins plugin SSL certificate drop-down empty; Certificate credential needs a private key (`expected one key got 0`) | leader cert + CA imported into Java `cacerts` on VM2 (`keytool -importcert -cacerts`), plugin cert field left empty. Plugin JWT audience left at default `cyberark-conjur` |
| 14 Oct | Jenkins apt repo: `NO_PUBKEY 7198F4B714ABFC68` | Jenkins rotated its repo signing key: `jenkins.io-2026.key` (was 2023) in `10-install-jenkins.sh` |
| 14 Oct | Rotation (admin update) not visible in the UI, fetches and denials are | UI shows a filtered view per object. Full record in `/opt/cyberark/conjur/logs/audit.log` on the SM VM; demo it with `90-audit.sh rotation` (raw) + version number in UI |
| 15 Oct | Support agent could read the Claude key itself via `read_secret` (agent container had the same signed token as the sidecar) | token mounted only in the sidecar, `automountServiceAccountToken: false`; agent process holds no credential (verification pending) |
| 16 Oct | Kill switch looked broken: a leftover day-2 host `prod/agents/support-agent` (API-key design) still had access to the Claude key (`policy load` never removes) | deleted (one-time `!delete`, verified 16 Oct); kill switch now prints who can use the key |
| 15 Oct | `90-audit.sh` hid rotation events (last 30 lines full of fetch/check) | views `rotation` (last update + first fetches after it) and `denied`; output kept raw |
| 13 Oct | nginx "cannot load certificate" during configure | harmless, cert created later in the run |
