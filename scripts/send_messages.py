#!/usr/bin/env python3
"""Send to / drain an Azure Service Bus queue using a SAS connection string.

Stdlib only — no `azure-servicebus` install needed. Builds a SAS token from the
connection string and uses the Service Bus REST API.

    SB_CONN='Endpoint=sb://<ns>.servicebus.windows.net/;SharedAccessKeyName=...;SharedAccessKey=...' \
      python3 scripts/send_messages.py 20      # send 20 messages
      python3 scripts/send_messages.py drain   # destructively receive until empty
"""
import base64
import hashlib
import hmac
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def parse_conn(conn):
    parts = dict(p.split("=", 1) for p in conn.split(";") if "=" in p)
    host = parts["Endpoint"].rstrip("/").replace("sb://", "https://")
    queue = parts.get("EntityPath") or os.environ.get("SB_QUEUE", "demo-queue")
    return host, queue, parts["SharedAccessKeyName"], parts["SharedAccessKey"]


def sas_token(uri, key_name, key, ttl=3600):
    expiry = str(int(time.time()) + ttl)
    enc = urllib.parse.quote_plus(uri)
    sig = base64.b64encode(
        hmac.new(key.encode(), (enc + "\n" + expiry).encode(), hashlib.sha256).digest()
    )
    return f"SharedAccessSignature sr={enc}&sig={urllib.parse.quote_plus(sig)}&se={expiry}&skn={key_name}"


def send(uri, token, n):
    for i in range(n):
        req = urllib.request.Request(
            f"{uri}/messages",
            data=f"msg-{i}".encode(),
            headers={"Authorization": token, "Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req).read()
    print(f"sent {n} messages")


def drain(uri, token):
    # Destructive receive on the queue head; ?timeout=2 makes the empty read
    # return 204 after ~2s instead of blocking.
    count = 0
    for _ in range(500):  # safety cap
        req = urllib.request.Request(
            f"{uri}/messages/head?timeout=2", headers={"Authorization": token}, method="DELETE"
        )
        try:
            resp = urllib.request.urlopen(req)
            if resp.status == 204:  # no message available => empty
                break
            resp.read()
            count += 1
        except urllib.error.HTTPError as e:
            if e.code in (204, 404):
                break
            raise
    print(f"drained {count} messages")


def main():
    conn = os.environ["SB_CONN"]
    host, queue, key_name, key = parse_conn(conn)
    uri = f"{host}/{queue}"
    token = sas_token(uri, key_name, key)
    arg = sys.argv[1] if len(sys.argv) > 1 else "20"
    if arg == "drain":
        drain(uri, token)
    else:
        send(uri, token, int(arg))


if __name__ == "__main__":
    main()
