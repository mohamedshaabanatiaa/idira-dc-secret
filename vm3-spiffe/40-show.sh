#!/usr/bin/env bash
# Shows who runs what on VM3: SPIRE, the Secretless broker, the agent. Run as root.
# Tip: open ./31-ops-chat.sh in another terminal first, so the agent process shows too.
B='\033[1m'; G='\033[0;90m'; N='\033[0m'
row() { printf "  %-22s %-18s %s\n" "$1" "$2" "$3"; }

echo -e "\n${B}  Processes on vm3, and the Linux user each runs as${N}\n"
row "COMPONENT" "USER" "PID"
show() {  # show <label> <pattern>
  local line; line=$(ps -eo user:18,pid,args | grep -E "$2" | grep -v grep | head -1)
  if [[ -n "$line" ]]; then row "$1" "$(awk '{print $1}' <<<"$line")" "$(awk '{print $2}' <<<"$line")"
  else row "$1" "-" "not running"; fi
}
show "SPIRE server"        "spire-server run"
show "SPIRE agent"         "spire-agent run"
show "SVID refresher"      "svid-refresh"
show "Secretless broker"   "secretless-broker"
show "Ops agent"           "ops_agent.py"

echo -e "\n${B}  Identities SPIRE hands out${N}"
/opt/spire/bin/spire-server entry show 2>/dev/null | awk '/SPIFFE ID/ {id=$4} /Selector/ {printf "  %-40s <- %s\n", id, $3}'

echo -e "\n${B}  Listening (localhost only)${N}"
ss -ltnp 2>/dev/null | awk '/:8081 |:8090 / {print "  " $4}' | sed 's/:8081/:8081  SPIRE server/; s/:8090/:8090  Secretless broker/'
echo -e "${G}  Only user ops-agent may reach 8090: $(iptables -S OUTPUT 2>/dev/null | grep -c 8090) firewall rule${N}\n"
