"""Rogue agent: has an identity, has no grants. Shows what it can NOT do."""
from idira import AccessDenied, SecretsManager, mask

sm = SecretsManager("rogue-agent")
print(f"Rogue agent running as {sm.login}\n")
for path in ["prod/ai/anthropic-api-key",
             "prod/boa/accounts-db/password",
             "prod/cicd/jenkins-token"]:
    try:
        print(f"  \033[33mLEAK\033[0m {path} = {mask(sm.get(path))}")
    except AccessDenied as e:
        print(f"  \033[32mBLOCKED\033[0m {e}")
print("\nEvery attempt above is in the Secrets Manager audit, tied to this identity.")
