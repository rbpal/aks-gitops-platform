"""Settlement worker.

Pulls signed transfers off the Service Bus queue, VERIFIES the signature against
the Key Vault key (integrity check), then "settles" them by flipping the ledger
entry to SETTLED. KEDA scales this Deployment 0..N on queue depth, so when the
queue is empty there are zero worker pods running.

Competing-consumers: run N replicas and Service Bus hands each message to exactly
one of them.
"""
import json
import os
import time

from prometheus_client import start_http_server

import common as c


def settle(rec: dict) -> bool:
    # Integrity gate: a transfer whose signature doesn't verify is never settled.
    if not c.verify_payload(c.canonical(rec), rec.get("signature", "")):
        c.SETTLE_FAIL.inc()
        c.LOG.warning(f"signature INVALID for {rec['id']} — refusing to settle")
        return False
    time.sleep(c.SETTLE_SECONDS)            # simulate settlement work
    rec["status"] = "SETTLED"
    rec["settled_at"] = c.now_iso()
    c.save_transfer(rec)
    c.SETTLEMENTS.inc()
    c.LOG.info(f"settled {rec['id']} {rec['asset']} {rec['amount']}")
    return True


def run():
    start_http_server(int(os.getenv("METRICS_PORT", "8080")))  # expose /metrics
    if not c.SB_CONN:
        c.LOG.error("SERVICEBUS_CONNECTION not set; worker has nothing to consume — idling")
        while True:
            time.sleep(30)

    from azure.servicebus import ServiceBusClient

    c.LOG.info("settlement-worker starting; polling Service Bus")
    with ServiceBusClient.from_connection_string(c.SB_CONN) as client:
        with client.get_queue_receiver(c.QUEUE_NAME, max_wait_time=5) as receiver:
            while True:
                msgs = receiver.receive_messages(max_message_count=10, max_wait_time=5)
                for m in msgs:
                    try:
                        rec = c.get_transfer(json.loads(str(m)).get("id"))
                        if rec and rec["status"] == "PENDING":
                            settle(rec)
                        receiver.complete_message(m)        # ack — removes from queue
                    except Exception as e:  # noqa: BLE001
                        c.LOG.error(f"error processing message: {e}")
                        receiver.abandon_message(m)          # release for redelivery


if __name__ == "__main__":
    run()
