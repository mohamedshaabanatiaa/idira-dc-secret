# Rotation: what we rotate, how, and what the app feels

Rule for the demo: **nothing breaks**. Every rotation below keeps the app answering.

| # | Secret | How it rotates | App impact | Script | Show live? |
|---|---|---|---|---|---|
| 1 | Pet store DB password | **Secrets Manager rotates it itself** on a timer (built-in Postgres rotator) | None. Secretless uses the new value on the next connection, same pod | `vm1-k8s/23-native-rotation-petstore.sh` | **Yes, the hero.** "It rotated while we were talking." |
| 2 | Pet store DB password (fallback) | Script: ALTER ROLE, then Secrets Manager | None, same pod | `vm1-k8s/31-rotate-petstore.sh` | If #1 is not firing |
| 3 | Bank of Anthos DB passwords | Script: Secrets Manager, sync, ALTER, rolling restart | None. New pod Ready before old pod stops | `vm1-k8s/30-rotate-boa.sh [--ledger]` | Yes, short. The "apps you can't touch" story |
| 4 | Jenkins/GitLab deploy tokens | Short-lived by design (2h). Re-issue = rotation, old one dies by itself | None. Next pipeline run fetches the new one | `vm1-k8s/25-cicd-deployers.sh` | Mention, don't run |
| 5 | Claude API key | Replace the value in Secrets Manager | None. Agent fetches it every turn | `vm3-ai-agent/10-setup.sh --new-key` | Mention with the kill switch |

## Why each one doesn't break the app

- **Postgres keeps open connections alive after a password change.** Only new logins need the new password.
- **Secretless** asks Secrets Manager for the password on every new connection, so the pod never needs it, never restarts.
- **Bank of Anthos** reads env vars at start, so the order is: new value stored and synced first (running pods unaffected), then ALTER, then a rolling restart where Kubernetes waits for the new pod to be Ready before stopping the old one (1 replica, `maxUnavailable` 0, readiness probes on every service).
- **Pipelines** run a preflight, a server-side dry run, and roll back automatically if the new pod is not Ready. The GitLab job only writes a release annotation unless `RESTART=true`.

## What to say (30 seconds)

"Three rotation models, picked per app, not one size fits all.
For the pet store, Secrets Manager rotates the database password itself, every five minutes, and the app never restarts because it never held the password.
For Bank of Anthos, which reads env vars and we can't change, rotation is stored, synced, then a rolling restart, zero downtime.
And for pipelines, the best rotation is not needing one: tokens live two hours and expire on their own."

## Production version (Q&A)

- Rotation schedule set by policy (`rotation/ttl`), owned by security, not by app teams.
- Secrets Provider standalone mode + Reloader instead of a script for env-var apps.
- Dual-account (A/B user) rotation for apps that can't tolerate any reconnect.
- PAM (Privilege Cloud CPM) rotates the DB accounts it already manages, Secrets Hub/sync delivers them to apps: one rotation, both human and machine consumers.
