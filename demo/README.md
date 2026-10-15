# Demo runbook

Everything runs on **VM1** (`cd /opt/idira/demo`) unless marked otherwise.
Each script only calls the build scripts we already have, plus plain kubectl.

## Before the panel

| When | Script | What it does |
|---|---|---|
| 30 to 60 min before | `./00-reset.sh` | Both apps back to hardcoded passwords |
| Live in Loop 1 (or before, if you skip the live migration) | `./01-prepare.sh` | Migrates both apps to Secrets Manager |
| 10 min before | `./02-preflight.sh` | Clock, login, fresh 2h Jenkins tokens, agents and apps Running |

Open beforehand: the Secrets Manager UI (logged in), Jenkins, the Bank of Anthos page, and a terminal on the Secrets Manager VM.

## During the panel: three loops (questions, demo, questions)

Full questions and lines are in the speaker notes of the "Three problems" slide.

| Loop | Scripts | Say |
|---|---|---|
| 1. Secret sprawl | `./10-show-secrets.sh`, `./01-prepare.sh`, `./10-show-secrets.sh`, payment in Bank of Anthos, `./30-jenkins.sh` + Jenkins build | "3 of 3 readable" then "0 of 3. Not one line of code changed." |
| 2. Rotation breaks things | `./20-rotate.sh`, UI version number, on the **Secrets Manager VM**: `./secrets-manager/90-audit.sh rotation` | "Same pod. No restart. Every change on record." |
| 3. AI agents | `./40-agent-chat.sh`, `./41-agent-rogue.sh`, `./42-agent-kill.sh off` / `on`, `./50-audit.sh`, UI rogue-agent host | "The agent never had the key. One policy line cuts it off." |

## Likely question on step 1

"So where is the Bank of Anthos password now?" In a Kubernetes Secret, written at runtime by the Secrets Provider from Secrets Manager. Not in Git, not in any manifest. For apps that should hold nothing at all, the pet store pattern: the sidecar fetches per connection.

## If something breaks

- Jenkins "must be logged in to the server": token expired or the namespace was reset. `./30-jenkins.sh` refreshes it, then build again.
- Pod not Running: `kubectl -n <ns> get pods`, then switch to the recorded backup video.
