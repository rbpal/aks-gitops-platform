# payments — settlement service (demo)

A small tokenized-asset settlement service that runs on the AKS GitOps platform.
**Simulated only — no real funds, wallets, or exchange keys.**

```
POST /transfer ─► payments-api ──sign (Key Vault key, via Workload Identity)──┐
                                 ──store PENDING──► Redis ledger               │
                                 ──enqueue──► Service Bus (demo-queue)         │
                                                     │ KEDA scales 0..N        │
                                                     ▼                          │
                              settlement-worker ──verify sig──► settle ──► Redis (SETTLED)
GET /ledger ◄── payments-api ◄── reads ◄────────────────────────────────────────┘
```

## One image, two roles
`app.py` (API) and `worker.py` (settler) ship in **one** image; the Deployments
pick the role via the container command. `common.py` holds the shared config,
Redis ledger, Key Vault signing, and Service Bus client.

## Endpoints
| Method | Path | Purpose |
|--------|------|---------|
| POST | `/transfer` | accept + sign + enqueue a transfer |
| GET | `/ledger` | list transfers and their status |
| GET | `/transfers/{id}` | one transfer |
| GET | `/healthz` `/readyz` | liveness / readiness |
| GET | `/metrics` | Prometheus metrics |
| GET | `/docs` | interactive Swagger UI |

## Config (env, injected by the manifests)
`REDIS_HOST`, `SERVICEBUS_CONNECTION` (SAS), `SERVICEBUS_QUEUE`,
`KEY_VAULT_NAME`, `SIGNING_KEY_NAME`, `SETTLE_SECONDS`.

> Signing and Service Bus **degrade to a labelled dev mode** when their config is
> absent, so the app boots before the Phase 3 Terraform (KV signing key +
> federated credential) is applied.

## Build (CI does this — Phase 2)
Built by GitHub Actions and pushed to `ghcr.io/rbpal/payments-api`. The image is
durable; only the running pods are ephemeral.
