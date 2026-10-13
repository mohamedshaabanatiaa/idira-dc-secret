"""Tiny Secrets Manager client for agents: authenticate as a host, read one secret."""
import urllib.parse

import requests


def _env():
    cfg = {}
    with open("/etc/idira/conjur.env") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                cfg[k] = v
    return cfg


class AccessDenied(Exception):
    pass


class SecretsManager:
    def __init__(self, agent: str):
        cfg = _env()
        self.url, self.account, self.cert = cfg["CONJUR_URL"], cfg["CONJUR_ACCOUNT"], cfg["CONJUR_CERT"]
        self.petstore = cfg.get("PETSTORE_URL", "")
        self.login = f"host/bank/agents/{agent}"
        with open(f"/etc/idira/{agent}.key") as f:
            self._api_key = f.read().strip()

    def _token(self) -> str:
        r = requests.post(
            f"{self.url}/authn/{self.account}/{urllib.parse.quote(self.login, safe='')}/authenticate",
            data=self._api_key, headers={"Accept-Encoding": "base64"}, verify=self.cert, timeout=10)
        if r.status_code != 200:
            raise AccessDenied(f"{self.login} could not authenticate ({r.status_code})")
        return r.text

    def get(self, variable: str) -> str:
        r = requests.get(
            f"{self.url}/secrets/{self.account}/variable/{urllib.parse.quote(variable, safe='')}",
            headers={"Authorization": f'Token token="{self._token()}"'}, verify=self.cert, timeout=10)
        if r.status_code in (401, 403, 404):
            raise AccessDenied(f"{self.login} denied on {variable} ({r.status_code})")
        r.raise_for_status()
        return r.text


def mask(s: str) -> str:
    return s[:10] + "..." + s[-4:] if len(s) > 16 else "****"


