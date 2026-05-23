# aks-gitops-platform

A hands-on Azure platform-engineering lab: a Terraform-provisioned **AKS** cluster running a full **GitOps + event-driven autoscaling** stack.

## What it demonstrates

- **Azure CNI Overlay + Cilium** — pod IPs decoupled from VNet space, eBPF dataplane
- **Workload Identity** — a pod reads a Key Vault secret via OIDC federation, with no stored credentials
- **Helm** — package-based application deploys
- **ArgoCD** — GitOps: this repo is the source of truth and the cluster reconciles to it
- **KEDA** — scaling a workload off Azure Service Bus queue depth (including scale-to-zero)
- **Terraform** — all Azure infrastructure as code, organized into reusable modules
- **Payments settlement app** — a demo service that ties it all together: signs transfers with a Key Vault key via Workload Identity, then settles them on a KEDA-autoscaled worker (see below)

## Architecture

```
                              git push
                                 |
                                 v
            +------------------------------------------------+
            |  GitHub repo  --  Git is the source of truth   |
            +------------------------------------------------+
                                 ^
                                 |  ArgoCD pulls manifests (outbound HTTPS only;
                                 |  no cluster credentials ever live in CI)
                                 |
   +------------------------------------------------------------------------+
   |  Azure Subscription  >  Resource Group                  region: westus |
   +------------------------------------------------------------------------+
                                 |
                                 v
   +------------------------------------------------------------------------+
   |  VNet  10.10.0.0/16                                                    |
   |    \__ Subnet aks-nodes 10.10.1.0/24  (only NODES consume VNet IPs)    |
   |          node-0 10.10.1.x   node-1 10.10.1.x   [ Standard_B2s x2 ]     |
   +------------------------------------------------------------------------+
                                 |
                                 v
   +------------------------------------------------------------------------+
   |  AKS   aksgitops-aks                                                   |
   |    control plane : Free tier  -  SystemAssigned cluster identity       |
   |    dataplane     : Azure CNI Overlay + Cilium (eBPF)                   |
   |    Pod CIDR 10.244.0.0/16 (overlay)   Service CIDR 10.0.0.0/16         |
   |    OIDC issuer + Workload Identity [on]   Managed KEDA addon [on]      |
   |                                                                        |
   |    in-cluster  (overlay net; every Service = ClusterIP, no public LB): |
   |      kube-system : cilium . azure-cns . csi (DaemonSets) . coredns     |
   |      argocd      : server . repo-server . app-controller (StatefulSet) |
   |      demo        : podinfo x3           (ArgoCD-synced from Git)       |
   |                    kv-reader            (Workload Identity)            |
   |                    queue-worker 0..5    (KEDA, standalone demo)        |
   |      payments    : payments-api . redis . settlement-worker 0..5       |
   |                    (KV-key signing; KEDA-scaled; default-deny netpol)  |
   +------------------------------------------------------------------------+
        |                                 |
   Workload Identity                 KEDA polls queue depth
   (kv-reader reads a secret;        (SAS connection string;
    payments signs with a KV key)     drives both KEDA demos)
        v                                 v
   +---------------------------+    +------------------------------+
   | Key Vault                 |    | Service Bus > demo-queue     |
   |   secret: demo-secret     |    |   Basic SKU                  |
   |   key:    signing key     |    |   one queue, both demos      |
   +---------------------------+    +------------------------------+
```

**Three flows worth tracing:**

1. **GitOps delivery (pull).** You `git push`; ArgoCD inside the cluster pulls and reconciles the live state to match Git. CI never holds cluster credentials.
2. **Workload Identity (no secrets).** The `kv-reader` pod's ServiceAccount token is federated (OIDC) to an Azure managed identity and exchanged for an AAD token to read Key Vault — nothing stored in the cluster. The payments API uses the same path to sign with a Key Vault **key**.
3. **Event-driven scaling.** KEDA watches `demo-queue` depth on Service Bus and scales a worker between 0 and 5 replicas, including scale-to-zero when idle — both the standalone `queue-worker` and the payments `settlement-worker` scale this way.

> Pod IPs (`10.244.0.0/16`) are an **overlay** — they don't consume VNet address space, so the `/24` node subnet supports far more pods than its 250-odd IPs. Every Service is `ClusterIP`; there is no public load balancer.

## Layout

```
terraform/
  modules/
    network/      # VNet + node subnet
    aks/          # cluster: Overlay, Cilium, OIDC, Workload Identity, KEDA
    identity/     # Key Vault (secret + signing key), UAMI, federated creds
    servicebus/   # Service Bus namespace + demo-queue
  *.tf            # root: wires the modules to a target subscription
app/
  payments/       # FastAPI settlement service (api + worker share one image)
k8s/
  apps/           # application manifests
    podinfo/      #   sample app, ArgoCD-synced from Git
    payments/     #   the settlement app: api, worker, redis, NetworkPolicy, KEDA
    queue-worker/ #   stand-in worker for the standalone KEDA demo
    keyvault-reader-sa.yaml / kv-reader-cli.yaml  # Workload Identity -> Key Vault
  keda/           # standalone KEDA ScaledObject + TriggerAuthentication (demo ns)
  argocd/         # ArgoCD Application CRs
scripts/          # deploy_payments.sh, send_transfers.py, send_messages.py
.github/
  workflows/      # CI: build & push the payments image to ghcr.io
```

## Quick start

```bash
# 1. Set subscription / tenant / resource group in terraform/terraform.tfvars
terraform -chdir=terraform init
terraform -chdir=terraform apply

# 2. Connect kubectl
az aks get-credentials -g <resource-group> -n aksgitops-aks --overwrite-existing
```

## Standalone KEDA demo

The leanest way to see scale-to-zero, independent of the payments app: a busybox
`queue-worker` that does no real work, scaled purely on `demo-queue` depth.

```bash
kubectl create namespace demo
# servicebus-conn Secret holds the SAS connection string (from terraform output)
kubectl -n demo create secret generic servicebus-conn \
  --from-literal=connection-string="$(terraform -chdir=terraform output -raw servicebus_keda_connection_string)"
kubectl apply -f k8s/apps/queue-worker/ -f k8s/keda/

SB_CONN="$(terraform -chdir=terraform output -raw servicebus_keda_connection_string)"
SB_CONN="$SB_CONN" python3 scripts/send_messages.py 20   # enqueue -> KEDA scales 0 -> N
watch kubectl -n demo get pods                            # then idle -> back to 0
SB_CONN="$SB_CONN" python3 scripts/send_messages.py drain # empty the queue
```

## Payments settlement app (demo)

A small tokenized-asset settlement service that exercises the whole platform. **Simulated only — no real funds, wallets, or exchange keys.**

```
POST /transfer ─► payments-api ──sign (Key Vault key, via Workload Identity)──┐
                                 ──store PENDING──► Redis ledger               │
                                 ──enqueue──► Service Bus (demo-queue)         │
                                                     │ KEDA scales 0..N        │
                                                     ▼                          │
                              settlement-worker ──verify sig──► settle ──► Redis (SETTLED)
GET /ledger ◄── payments-api ◄── reads ◄────────────────────────────────────────┘
```

- **One image, two roles** — `app/payments` builds a single image; the API and the worker run it with different commands. Built by GitHub Actions → `ghcr.io/rbpal/payments-api`.
- **Security** — transfers are signed by a Key Vault **key** that never leaves the vault; idempotency keys prevent double-spend; the `payments` namespace runs under a Cilium **default-deny** NetworkPolicy with an explicit allowlist; containers are non-root, read-only-rootfs, drop all caps.
- **Durable vs ephemeral** — the image (ghcr) and manifests (Git) persist; the running pods are recreated each session.

```bash
# Deploy into the current cluster (substitutes placeholders, creates the SB secret)
./scripts/deploy_payments.sh

# Reach it privately (no public IP) and test
kubectl -n payments port-forward svc/payments-api 8080:80   # keep running
open http://localhost:8080/docs                              # Swagger UI
python3 scripts/send_transfers.py 20                         # fire 20 transfers
python3 scripts/send_transfers.py ledger                     # watch PENDING -> SETTLED
watch kubectl -n payments get pods                           # KEDA scales 0 -> N -> 0
```

> The Key Vault **signing key** + a federated credential for the `payments-api` ServiceAccount are added in the Terraform identity module; the image must be a **public** ghcr package (or add an imagePullSecret) for AKS to pull it.

## Notes

A learning / portfolio lab — cost-conscious and meant to be torn down between sessions. Deliberately not production-hardened (single node pool, lab SKUs); the trade-offs are intentional.
