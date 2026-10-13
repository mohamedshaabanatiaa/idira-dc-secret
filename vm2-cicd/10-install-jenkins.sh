#!/usr/bin/env bash
# Installs Jenkins LTS on VM2 with the plugins the demo needs, no setup wizard.
# Run as root. Admin password is prompted (not the Secrets Manager one).
source "$(dirname "$0")/../common/lib.sh"
[[ $EUID -eq 0 ]] || die "run as root"
ensure_hosts_entry

log "Java, kubectl and tools"
apt-get update -qq
apt-get install -y -qq openjdk-21-jre-headless fontconfig curl jq git openssl python3 >/dev/null
if ! command -v kubectl >/dev/null; then
  curl -sLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi
ok "$(java -version 2>&1 | head -1), kubectl $(kubectl version --client -o json | jq -r .clientVersion.gitVersion)"

if ! command -v jenkins >/dev/null && [[ ! -d /usr/share/java/jenkins.war && ! -f /usr/share/java/jenkins.war ]]; then
  log "Jenkins LTS repo"
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key -o /etc/apt/keyrings/jenkins-keyring.asc
  echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    > /etc/apt/sources.list.d/jenkins.list
  apt-get update -qq || die "Jenkins repo key rejected? check https://pkg.jenkins.io/debian-stable/ for the current key"
  apt-get install -y -qq jenkins >/dev/null
fi
ok "Jenkins $(dpkg -s jenkins | awk '/^Version/{print $2}')"

log "Skipping the setup wizard, creating admin user"
mkdir -p /etc/systemd/system/jenkins.service.d /var/lib/jenkins/init.groovy.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<CONF
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"
CONF
if [[ ! -f /var/lib/jenkins/.admin-created ]]; then
  read -r -s -p "New Jenkins admin password: " JPW; echo
  cat > /var/lib/jenkins/init.groovy.d/01-bootstrap.groovy <<GROOVY
import jenkins.model.*
import hudson.security.*
def j = Jenkins.get()
def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount("admin", '${JPW}')
j.setSecurityRealm(realm)
def auth = new FullControlOnceLoggedInAuthorizationStrategy(); auth.setAllowAnonymousRead(false)
j.setAuthorizationStrategy(auth)
JenkinsLocationConfiguration.get().setUrl("http://${VM2_IP}:8080/")
j.save()
new File("/var/lib/jenkins/.admin-created").text = "ok"
GROOVY
  unset JPW
fi

log "Plugins (pipeline, git, credentials binding, CyberArk Secrets Manager)"
PM=/opt/jenkins-plugin-manager.jar
if [[ ! -f $PM ]]; then
  URL=$(curl -s https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest \
        | jq -r '.assets[] | select(.name|test("jenkins-plugin-manager-.*\\.jar$")) | .browser_download_url' | head -1)
  [[ -n "$URL" && "$URL" != null ]] || URL="https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.13.2/jenkins-plugin-manager-2.13.2.jar"
  curl -sL -o $PM "$URL"
fi
java -jar $PM --war /usr/share/java/jenkins.war --plugin-download-directory /var/lib/jenkins/plugins \
  --plugins workflow-aggregator git credentials-binding pipeline-stage-view conjur-credentials >/dev/null
chown -R jenkins:jenkins /var/lib/jenkins

systemctl daemon-reload && systemctl enable jenkins >/dev/null 2>&1 && systemctl restart jenkins
log "Waiting for Jenkins"
for _ in {1..60}; do curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login | grep -q 200 && break; sleep 5; done
rm -f /var/lib/jenkins/init.groovy.d/01-bootstrap.groovy   # password no longer on disk
ok "Jenkins up: http://${VM2_IP}:8080  (admin). Next: README section 'Jenkins UI steps'."
warn "Jenkins has no ingress from your laptop: open it from the Windows jump host browser."
