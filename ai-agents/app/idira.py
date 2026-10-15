"""Secrets Manager login for a pod: uses the pod's Kubernetes service account
token (a signed JWT) with the authn-jwt/k3s login door. No password, no API key."""
import base64
import json
import os
import urllib.parse

import requests

URL = os.environ["CONJUR_APPLIANCE_URL"]
ACCOUNT = os.environ["CONJUR_ACCOUNT"]
AUTHN_URL = os.environ["CONJUR_AUTHN_URL"]          # .../authn-jwt/k3s
JWT_PATH = os.environ.get("JWT_TOKEN_PATH", "/var/run/secrets/tokens/jwt")
CERT = "/tmp/conjur.pem"
with open(CERT, "w") as f:
    f.write(os.environ["CONJUR_SSL_CERTIFICATE"])


class AccessDenied(Exception):
    pass


NO_CREDENTIAL = "this agent holds no credential: only its sidecar can reach Secrets Manager"


def identity() -> str:
    """Who this pod is, read from its own token (for display only)."""
    if not os.path.exists(JWT_PATH):
        return os.environ.get("AGENT_IDENTITY", "unknown") + " (token held by the sidecar only)"
    payload = open(JWT_PATH).read().split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))["sub"]


def _access_token() -> str:
    if not os.path.exists(JWT_PATH):
        raise AccessDenied(NO_CREDENTIAL)
    r = requests.post(f"{AUTHN_URL}/{ACCOUNT}/authenticate",
                      data={"jwt": open(JWT_PATH).read().strip()},
                      headers={"Accept-Encoding": "base64"}, verify=CERT, timeout=10)
    if r.status_code != 200:
        raise AccessDenied(f"login refused ({r.status_code})")
    return r.text


def get_secret(variable: str) -> str:
    r = requests.get(f"{URL}/secrets/{ACCOUNT}/variable/{urllib.parse.quote(variable, safe='')}",
                     headers={"Authorization": f'Token token="{_access_token()}"'},
                     verify=CERT, timeout=10)
    if r.status_code in (401, 403, 404):
        raise AccessDenied(f"{variable} denied ({r.status_code})")
    r.raise_for_status()
    return r.text


def mask(s: str) -> str:
    return s[:6] + "..." + s[-4:] if len(s) > 12 else "****"
