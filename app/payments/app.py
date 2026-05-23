"""Payments Settlement API (FastAPI).

POST /transfer  -> validate, idempotency-check, SIGN via Key Vault (Workload
                   Identity), store PENDING in the Redis ledger, enqueue to
                   Service Bus. The settlement-worker drains the queue and flips
                   the status to SETTLED.

Reach it with:  kubectl -n payments port-forward svc/payments-api 8080:80
Then open:      http://localhost:8080/docs
"""
import uuid

from fastapi import FastAPI, HTTPException
from fastapi.responses import RedirectResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field, condecimal

import common as c

app = FastAPI(
    title="Payments Settlement API",
    version="0.1.0",
    description="Demo tokenized-asset settlement service running on AKS "
    "(Workload Identity signing + KEDA-autoscaled settlement). Simulated only — no real funds.",
)


class TransferRequest(BaseModel):
    sender: str = Field(..., min_length=1, max_length=64, examples=["alice"])
    recipient: str = Field(..., min_length=1, max_length=64, examples=["bob"])
    asset: str = Field(..., examples=["USDC"], description="One of: USDC, USDT, ETH, BTC")
    amount: condecimal(gt=0) = Field(..., examples=["50.00"])
    idempotency_key: str | None = Field(
        None, description="Optional. Re-sending the same key returns the original transfer (no double-spend)."
    )


@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse("/docs")


@app.get("/healthz", tags=["ops"])
def healthz():
    """Liveness — process is up."""
    return {"status": "ok"}


@app.get("/readyz", tags=["ops"])
def readyz():
    """Readiness — can we reach the ledger?"""
    try:
        c.redis_client().ping()
    except Exception as e:  # noqa: BLE001
        raise HTTPException(503, f"redis not ready: {e}")
    return {"status": "ready"}


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/transfer", status_code=202, tags=["payments"])
def create_transfer(req: TransferRequest):
    if req.asset not in c.SUPPORTED_ASSETS:
        raise HTTPException(422, f"unsupported asset {req.asset!r}; supported: {sorted(c.SUPPORTED_ASSETS)}")

    # Idempotency: a retried request with the same key never double-spends.
    if req.idempotency_key:
        existing = c.idem_lookup(req.idempotency_key)
        if existing:
            return c.get_transfer(existing)

    tid = str(uuid.uuid4())
    rec = {
        "id": tid,
        "sender": req.sender,
        "recipient": req.recipient,
        "asset": req.asset,
        "amount": str(req.amount),
        "status": "PENDING",
        "created_at": c.now_iso(),
        "settled_at": None,
        "idempotency_key": req.idempotency_key,
    }
    rec["signature"] = c.sign_payload(c.canonical(rec))   # Key Vault key via Workload Identity
    c.save_transfer(rec)
    if req.idempotency_key:
        c.idem_store(req.idempotency_key, tid)
    c.send_to_queue({"id": tid})                          # hand off to the worker via Service Bus
    c.TRANSFERS.labels(asset=req.asset).inc()
    c.LOG.info(f"accepted transfer {tid} {req.asset} {req.amount}")
    return rec


@app.get("/ledger", tags=["payments"])
def ledger(limit: int = 100):
    """The shared ledger — watch entries flip PENDING -> SETTLED as the worker drains the queue."""
    return {"transfers": c.list_transfers(limit)}


@app.get("/transfers/{tid}", tags=["payments"])
def get_one(tid: str):
    rec = c.get_transfer(tid)
    if not rec:
        raise HTTPException(404, "transfer not found")
    return rec
