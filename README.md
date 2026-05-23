# aks-gitops-platform

A hands-on Azure platform-engineering lab: a Terraform-provisioned **AKS** cluster running a full **GitOps + event-driven autoscaling** stack.

## What it demonstrates

- **Azure CNI Overlay + Cilium** — pod IPs decoupled from VNet space, eBPF dataplane
- **Workload Identity** — a pod reads a Key Vault secret via OIDC federation, with no stored credentials
- **Helm** — package-based application deploys
- **ArgoCD** — GitOps: this repo is the source of truth and the cluster reconciles to it
- **KEDA** — scaling a workload off Azure Service Bus queue depth (including scale-to-zero)
- **Terraform** — all Azure infrastructure as code, organized into reusable modules

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
   |                    queue-worker 0..5    (KEDA-scaled)                  |
   +------------------------------------------------------------------------+
        |                                 |
   OIDC federation                   poll queue depth
   (token exchange,                  (SAS connection string)
    no stored secret)                                        
        v                                 v
   +---------------------------+    +------------------------------+
   | Key Vault (access-policy) |    | Service Bus > demo-queue     |
   |   secret: demo-secret     |    |   (Basic SKU)                |
   +---------------------------+    +------------------------------+
```

**Three flows worth tracing:**

1. **GitOps delivery (pull).** You `git push`; ArgoCD inside the cluster pulls and reconciles the live state to match Git. CI never holds cluster credentials.
2. **Workload Identity (no secrets).** The `kv-reader` pod's ServiceAccount token is federated (OIDC) to an Azure managed identity and exchanged for an AAD token to read Key Vault — nothing stored in the cluster.
3. **Event-driven scaling.** KEDA watches `demo-queue` depth on Service Bus and scales `queue-worker` between 0 and 5 replicas, including scale-to-zero when idle.

> Pod IPs (`10.244.0.0/16`) are an **overlay** — they don't consume VNet address space, so the `/24` node subnet supports far more pods than its 250-odd IPs. Every Service is `ClusterIP`; there is no public load balancer.

## Layout

```
terraform/
  modules/
    network/    # VNet + node subnet
    aks/        # cluster: Overlay, Cilium, OIDC, Workload Identity, KEDA
    identity/   # Key Vault, user-assigned identity, federated credential
  *.tf          # root: wires the modules to a target subscription
k8s/
  apps/         # application manifests (synced by ArgoCD)
```

## Quick start

```bash
# 1. Set subscription / tenant / resource group in terraform/terraform.tfvars
terraform -chdir=terraform init
terraform -chdir=terraform apply

# 2. Connect kubectl
az aks get-credentials -g <resource-group> -n aksgitops-aks --overwrite-existing
```

## Notes

A learning / portfolio lab — cost-conscious and meant to be torn down between sessions. Deliberately not production-hardened (single node pool, lab SKUs); the trade-offs are intentional.
