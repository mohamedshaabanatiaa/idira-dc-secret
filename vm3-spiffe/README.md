# SPIFFE identity for an AI agent on a VM (VM3)

An AI agent on a plain Linux VM, no Kubernetes, calls Claude with a **SPIFFE identity**.
SPIRE (open source, CNCF) attests the broker process; Secrets Manager trusts SPIRE's signing keys
through a standard `authn-jwt` authenticator. The agent holds no key, no token, no identity.

```
ops-agent (Linux user)          holds nothing, not in SPIRE, can only talk to 127.0.0.1:8090
  -> Secretless Broker           runs as ops-agent-broker, the ONLY user registered in SPIRE:
     (ops-agent-broker)          spiffe://bank.local/agents/ops-agent (5-minute JWT-SVID)
       -> Secrets Manager        authn-jwt/spire, host prod/spiffe/ops-agent, Claude key fetched per request
       -> api.anthropic.com      key added as x-api-key, https
intruder (other user)           blocked from 8090 (iptables owner rule), no SPIFFE identity
```

Native SPIFFE in Idira (Secure Workload Access) is SaaS. On Self-Hosted, this is the pattern:
SPIRE as the identity issuer, authn-jwt as the door, policy as usual.

## Order

| Where | Step |
|---|---|
| VM3 | `cd /opt/idira && git pull && cd vm3-spiffe` |
| VM3 | `./00-install-spire.sh`  SPIRE server + agent, node attested |
| VM3 | `./10-connect-conjur.sh`  policy (add only), authenticator keys |
| Secrets Manager VM | `./secrets-manager/20-enable-authenticators.sh`  allowlist `authn-jwt/spire` |
| VM3 | `./30-ops-agent.sh`  registration entry, broker, agent |

Needs the Conjur CLI on VM3 (`dpkg -i conjur-cli_9.3.0_amd64.deb`).

## Demo

| Step | Run (VM3) |
|---|---|
| Who runs what | `./40-show.sh` (open the chat in another terminal first) |
| Chat | `./31-ops-chat.sh`, ask "server status" |
| Other user | `./31-ops-chat.sh intruder` (connection refused) |
| Kill switch | `./32-ops-kill.sh off`, one chat message (refused), `./32-ops-kill.sh on` |

What to say: "Same agent pattern, different platform, open identity standard. The agent holds nothing. Its broker holds a SPIFFE identity that lives 5 minutes. One policy line cuts it off."
