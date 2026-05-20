# aks-gitops-platform

A hands-on Azure platform-engineering lab: a Terraform-provisioned **AKS** cluster running a full **GitOps + event-driven autoscaling** stack.

## What it demonstrates

- **Azure CNI Overlay + Cilium** — pod IPs decoupled from VNet space, eBPF dataplane
- **Workload Identity** — a pod reads a Key Vault secret via OIDC federation, with no stored credentials
- **Helm** — package-based application deploys
- **ArgoCD** — GitOps: this repo is the source of truth and the cluster reconciles to it
- **KEDA** — scaling a workload off Azure Service Bus queue depth (including scale-to-zero)
- **Terraform** — all Azure infrastructure as code, organized into reusable modules

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
