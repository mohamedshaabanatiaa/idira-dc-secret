# SPIFFE identity on a VM (VM3)

A batch job on a plain Linux VM, no Kubernetes, gets its secret with a **SPIFFE identity**.
SPIRE (open source, CNCF) attests the process; Secrets Manager trusts SPIRE's signing keys
through a standard `authn-jwt` authenticator. No password, no API key, no secret file.

```
settlement job (Linux user "settlement" on vm3)
  1. asks the local SPIRE agent "who am I?"  -> JWT-SVID, sub = spiffe://bank.local/batch/settlement, 5 min
  2. shows it to Secrets Manager (authn-jwt/spire) -> signature, issuer, audience, sub checked
  3. reads prod/batch/core-banking-api-key, and nothing else
intruder (other user, same VM) -> SPIRE gives no identity, stops at step 1
```

Native SPIFFE in Idira (Secure Workload Access) is SaaS. On Self-Hosted, this is the pattern:
SPIRE as the identity issuer, authn-jwt as the door, policy as usual.

## Order

| Where | Step |
|---|---|
| VM3 | `cd /opt/idira && git pull && cd vm3-spiffe` |
| VM3 | `./00-install-spire.sh`  SPIRE server + agent, node attested, workload registered |
| VM3 | `./10-connect-conjur.sh`  policy (add only), authenticator keys, secret |
| Secrets Manager VM | `./secrets-manager/20-enable-authenticators.sh`  allowlist `authn-jwt/spire` |
| VM3 | `./20-workload.sh`  then `./20-workload.sh intruder` |

Needs the Conjur CLI on VM3 (`dpkg -i conjur-cli_9.3.0_amd64.deb`).

## What to say
"Same VM, two processes. One has a SPIFFE identity and gets exactly one secret. The other has no identity and gets nothing. No password was ever installed on this box."

## AI agent with a SPIFFE identity (standalone, VM3)

Same pattern as the k3s support agent, on a plain VM. Nothing on VM1 changes.

```
ops-agent (Linux user)          holds nothing, not in SPIRE, can only talk to 127.0.0.1:8090
  -> Secretless Broker           runs as ops-agent-broker, the ONLY user registered in SPIRE:
     (ops-agent-broker)          spiffe://bank.local/agents/ops-agent
       -> Secrets Manager        authn-jwt/spire, host prod/spiffe/ops-agent, Claude key fetched per request
       -> api.anthropic.com      key added as x-api-key, https
intruder (other user)           blocked from 8090 (iptables owner rule), no SPIFFE identity
```

| Step | Run (VM3) |
|---|---|
| Install | `./30-ops-agent.sh` |
| Chat | `./31-ops-chat.sh`  try: "server status", then "read the secret prod/ai/anthropic-api-key" (denied: the agent has no identity) |
| Other user | `./31-ops-chat.sh intruder`  (connection refused) |
| Kill switch | `./32-ops-kill.sh off`, one chat message (refused), `./32-ops-kill.sh on` |

What to say: "Same agent pattern, different platform, open identity standard. The agent holds nothing. Its broker holds a SPIFFE identity that lives 5 minutes. One policy line cuts it off."
