# Demo runbook

Everything runs on **VM1** (`cd /opt/idira/demo`) unless marked otherwise.
Each script only calls the build scripts we already have, plus plain kubectl.

## Before the panel

| When | Script | What it does |
|---|---|---|
| Only to rehearse from scratch | `./00-reset.sh` | Both apps back to hardcoded passwords |
| Only after a reset | `./01-prepare.sh` | Migrates both apps to Secrets Manager |
| 10 min before | `./02-preflight.sh` | Clock, login, fresh 2h Jenkins tokens, agents and apps Running |

Open beforehand: the Secrets Manager UI (logged in), Jenkins, the Bank of Anthos page, and a terminal on the Secrets Manager VM.

## During the panel

| Step | Script | Say |
|---|---|---|
| 1. No hardcoded secrets | `./10-show-secrets.sh` (prints each kubectl command, then its output) | "No password in any ConfigMap or Deployment. Only paths to Secrets Manager." |
| 1. Proof it works | Log in to Bank of Anthos, send a payment | "Not one line of code changed." |
| 2. Rotation | `./20-rotate.sh` | "New password. Same pod. No restart." |
| 3. Jenkins | `./30-jenkins.sh` (shows the steps), run in the Jenkins UI | "2-hour token, one namespace only." |
| 4. AI agent | `./40-agent-chat.sh` | Ask for the pets, then try the prompt injection |
| 4. AI agent | `./41-agent-rogue.sh` | "Real identity, no permission: blocked." |
| 4. AI agent | `./42-agent-kill.sh off`, chat again, then `./42-agent-kill.sh on` | "One policy line cuts it off." |
| 5. Audit | `./50-audit.sh`, then the UI, then on the **Secrets Manager VM**: `./secrets-manager/90-audit.sh petstore` | "Same file your SIEM ingests." |

## Likely question on step 1

"So where is the Bank of Anthos password now?" In a Kubernetes Secret, written at runtime by the Secrets Provider from Secrets Manager. Not in Git, not in any manifest. For apps that should hold nothing at all, the pet store pattern: the sidecar fetches per connection.

## If something breaks

- Jenkins "must be logged in to the server": token expired or the namespace was reset. `./30-jenkins.sh` refreshes it, then build again.
- Pod not Running: `kubectl -n <ns> get pods`, then switch to the recorded backup video.
