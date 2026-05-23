#!/usr/bin/env python3
"""Fire demo transfers at the payments API (reached via kubectl port-forward).

Usage:
  kubectl -n payments port-forward svc/payments-api 8080:80   # in another terminal
  python3 scripts/send_transfers.py 20        # send 20 random transfers
  python3 scripts/send_transfers.py ledger    # print the ledger (PENDING/SETTLED)

Override the target with PAYMENTS_URL (default http://localhost:8080).
Pure stdlib — no pip installs needed.
"""
import json
import os
import random
import sys
import urllib.request

BASE = os.getenv("PAYMENTS_URL", "http://localhost:8080")
ASSETS = ["USDC", "USDT", "ETH", "BTC"]
NAMES = ["alice", "bob", "carol", "dave", "erin", "frank"]


def post_transfer() -> dict:
    body = {
        "sender": random.choice(NAMES),
        "recipient": random.choice(NAMES),
        "asset": random.choice(ASSETS),
        "amount": round(random.uniform(1, 500), 2),
    }
    req = urllib.request.Request(
        f"{BASE}/transfer",
        data=json.dumps(body).encode(),
        headers={"content-type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def show_ledger() -> None:
    with urllib.request.urlopen(f"{BASE}/ledger") as r:
        data = json.loads(r.read())
    for t in data["transfers"]:
        print(f"{t['id'][:8]}  {t['status']:8}  {t['sender']:6} -> {t['recipient']:6}  {t['amount']:>8} {t['asset']}")
    print(f"total: {len(data['transfers'])}")


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else "5"
    if arg == "ledger":
        show_ledger()
    else:
        n = int(arg)
        for i in range(n):
            res = post_transfer()
            print(f"sent {i + 1}/{n}: {res['id'][:8]} {res['status']} {res['asset']} {res['amount']}")
