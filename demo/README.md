# Demo runbook

Everything runs on **VM1** (`cd /opt/idira/demo`) unless marked otherwise.
Each script only calls the build scripts we already have. Nothing new.

## Before the panel

| When | Script | What it does |
|---|---|---|
| 30 to 60 min before | `./00-reset.sh` | Both apps back to hardcoded (the "before" state) |
| 10 min before | `./01-preflight.sh` | Clock, login, fresh 2h Jenkins tokens, agents and apps Running |

Open beforehand: the Secrets Manager UI (logged in), Jenkins, the Bank of Anthos page, and a terminal on the Secrets Manager VM.

## During the panel

| Act | Script | Say |
|---|---|---|
| 1. Before | `./10-act1-before.sh` | "Anyone with cluster or Git read access has these." |
| 2. Bank of Anthos | `./20-act2-boa.sh`, then log in and send a payment | "Not one line of code changed." |
| 3. Pet store | `./30-act3-petstore.sh` | "The app has no password at all." |
| 3. Rotation | `./31-act3-rotate.sh` | "New password. Same pod. No restart." |
| 4. Jenkins | `./40-act4-jenkins.sh` (shows the steps), run in the Jenkins UI | "2-hour token, one namespace only." |
| AI agent | `./50-agent-chat.sh` | Ask for the pets, then try the prompt injection |
| AI agent | `./51-agent-rogue.sh` | "Real identity, no permission: blocked." |
| AI agent | `./52-agent-kill.sh off`, chat again, then `./52-agent-kill.sh on` | "One policy line cuts it off." |
| Audit | `./60-audit-check.sh`, then the UI, then on the **Secrets Manager VM**: `./secrets-manager/90-audit.sh petstore` | "Same file your SIEM ingests." |

## If something breaks

- Jenkins token expired: `./01-preflight.sh` again.
- Pod not Running: `kubectl -n <ns> get pods`, then switch to the recorded backup video.
- Short on time: skip Act 1, go straight to Act 3.
