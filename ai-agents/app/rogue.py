"""Rogue agent: a real identity (its own service account) that nobody approved."""
from idira import AccessDenied, get_secret, identity, mask

print(f"Rogue agent · identity {identity()}\n")
for path in ["prod/ai/anthropic-api-key", "prod/boa/accounts-db/password", "prod/cicd/jenkins-token"]:
    try:
        print(f"  \033[33mLEAK\033[0m    {path} = {mask(get_secret(path))}")
    except AccessDenied as e:
        print(f"  \033[32mBLOCKED\033[0m {e}")
print("\nEvery attempt is in the Secrets Manager audit, under this identity.")
