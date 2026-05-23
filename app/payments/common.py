"""Shared helpers for the payments settlement demo.

Both the API (app.py) and the worker (worker.py) import this. It centralises:
  - config (all from env; the K8s manifests inject these)
  - the Redis ledger (shared state between the api pod and the worker pods)
  - Key Vault signing/verify via Workload Identity (private key never leaves the vault)
  - Service Bus send (api enqueues) — receive lives in the worker
  - Prometheus metrics

Design note: signing and Service Bus both "degrade gracefully" to a clearly
labelled dev mode when their config is absent, so this runs locally / in Phase 1
before the Phase 3 Terraform (KV signing key + federated credential) exists.
"""
import os
import json
import time
import base64
import hashlib
import logging
from datetime import datetime, timezone

import redis as redislib

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format='{"ts":"%(asctime)s","level":"%(levelname)s","comp":"payments","msg":"%(message)s"}',
)
LOG = logging.getLogger("payments")

# ---- config (env-injected by the manifests) ----
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
QUEUE_NAME = os.getenv("SERVICEBUS_QUEUE", "demo-queue")
SB_CONN = os.getenv("SERVICEBUS_CONNECTION", "")       # SAS connection string (sandbox path)
KEY_VAULT_NAME = os.getenv("KEY_VAULT_NAME", "")        # e.g. aksgitops-kv-xxxxxx
SIGNING_KEY_NAME = os.getenv("SIGNING_KEY_NAME", "tx-signer")
SETTLE_SECONDS = float(os.getenv("SETTLE_SECONDS", "2"))
SUPPORTED_ASSETS = {"USDC", "USDT", "ETH", "BTC"}

LEDGER_INDEX = "ledger:index"          # redis sorted set of transfer ids (by time)


def _key(tid: str) -> str:
    return f"transfer:{tid}"


def _idem(key: str) -> str:
    return f"idem:{key}"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ---- Redis ledger (shared between api + worker) ----
_redis = None


def redis_client():
    global _redis
    if _redis is None:
        _redis = redislib.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    return _redis


def save_transfer(rec: dict) -> None:
    r = redis_client()
    r.set(_key(rec["id"]), json.dumps(rec))
    r.zadd(LEDGER_INDEX, {rec["id"]: time.time()})


def get_transfer(tid: str):
    raw = redis_client().get(_key(tid))
    return json.loads(raw) if raw else None


def list_transfers(limit: int = 100):
    r = redis_client()
    out = []
    for tid in r.zrevrange(LEDGER_INDEX, 0, limit - 1):
        raw = r.get(_key(tid))
        if raw:
            out.append(json.loads(raw))
    return out


def idem_lookup(key: str):
    return redis_client().get(_idem(key))


def idem_store(key: str, tid: str) -> None:
    redis_client().set(_idem(key), tid)


# ---- signing: Key Vault key via Workload Identity ----
# The transfer is signed with an EC key that lives in Key Vault. We send only a
# SHA-256 digest to the vault's `sign` API; the private key never enters the pod.
_crypto = None


def _crypto_client():
    global _crypto
    if _crypto is None:
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.keys import KeyClient
        from azure.keyvault.keys.crypto import CryptographyClient

        cred = DefaultAzureCredential()  # picks up the Workload Identity env + token file
        kc = KeyClient(vault_url=f"https://{KEY_VAULT_NAME}.vault.azure.net", credential=cred)
        _crypto = CryptographyClient(kc.get_key(SIGNING_KEY_NAME), credential=cred)
    return _crypto


def canonical(rec: dict) -> str:
    """Deterministic string the signature commits to."""
    return "|".join(str(rec[f]) for f in ("id", "sender", "recipient", "asset", "amount", "created_at"))


def sign_payload(canonical_str: str) -> str:
    if not KEY_VAULT_NAME:
        # Phase 1 / local: not wired to Key Vault yet — label it honestly.
        return "dev-unsigned:" + hashlib.sha256(canonical_str.encode()).hexdigest()[:16]
    from azure.keyvault.keys.crypto import SignatureAlgorithm

    digest = hashlib.sha256(canonical_str.encode()).digest()
    res = _crypto_client().sign(SignatureAlgorithm.es256, digest)
    return "kv:" + base64.urlsafe_b64encode(res.signature).decode()


def verify_payload(canonical_str: str, signature: str) -> bool:
    if signature.startswith("dev-unsigned:"):
        return signature == "dev-unsigned:" + hashlib.sha256(canonical_str.encode()).hexdigest()[:16]
    if not signature.startswith("kv:"):
        return False
    from azure.keyvault.keys.crypto import SignatureAlgorithm

    digest = hashlib.sha256(canonical_str.encode()).digest()
    sig = base64.urlsafe_b64decode(signature[3:].encode())
    return _crypto_client().verify(SignatureAlgorithm.es256, digest, sig).is_valid


# ---- Service Bus (api enqueues; worker consumes in worker.py) ----
def send_to_queue(body: dict) -> None:
    if not SB_CONN:
        LOG.warning("SERVICEBUS_CONNECTION not set; skipping enqueue (dev mode)")
        return
    from azure.servicebus import ServiceBusClient, ServiceBusMessage

    with ServiceBusClient.from_connection_string(SB_CONN) as client:
        with client.get_queue_sender(QUEUE_NAME) as sender:
            sender.send_messages(ServiceBusMessage(json.dumps(body)))


# ---- metrics ----
from prometheus_client import Counter  # noqa: E402

TRANSFERS = Counter("payments_transfers_total", "Transfers accepted by the API", ["asset"])
SETTLEMENTS = Counter("payments_settlements_total", "Transfers settled by the worker")
SETTLE_FAIL = Counter("payments_settlement_failures_total", "Settlement failures (e.g. bad signature)")
