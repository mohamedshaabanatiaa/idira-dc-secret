# Secrets Manager VM (Self-Hosted leader)

Run as root on the Secrets Manager VM. Edit `../lab.env` first (`CONJUR_HOST`, `CONJUR_IP`, `CONJUR_ACCOUNT`).

```bash
../readiness/check.sh sm
./10-install-leader.sh /path/to/conjur-appliance-<version>.tar.gz   # load, run, evoke configure leader
./20-enable-authenticators.sh                                     # authn-jwt for k3s, jenkins, gitlab
./90-audit.sh [filter]                                            # audit trail for the demo
```

Admin password is prompted and goes only into `evoke`. Write it somewhere safe; every other script asks for it.

## Verify against what the lab gave you

- [ ] Image tarball name and whether it's Docker or Podman. If the lab VM already has Podman, replace `docker` with `podman` in the scripts.
- [ ] `evoke configure leader` flags for your version (older releases say `configure master`).
- [ ] If the lab guide prescribes a different install procedure, follow the guide. These scripts are a shortcut, not the source of truth.

## After the leader is up

1. Windows jump host: add `<CONJUR_IP> <CONJUR_HOST>` to `C:\Windows\System32\drivers\etc\hosts`, open `https://<CONJUR_HOST>`, log in as admin.
2. Run `vm1-k8s/20-conjur-setup.sh` on VM1, then the VM2 and VM3 setups.
