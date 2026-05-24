# SANDBOX LIMITS (Pluralsight): max 3 clusters, max 3 nodes/cluster, and you
# CANNOT view/manage the secondary "MC_<rg>_<cluster>_<region>" node resource
# group AKS auto-creates. AKS itself manages that RG via the cluster identity,
# so Terraform create/destroy still works — but `az aks create`/portal may emit
# an ignorable error about it. If `terraform apply` errors AFTER the cluster is
# actually up (check `az aks show -g <rg> -n <prefix>-aks`), re-run apply /
# `terraform refresh` to reconcile state.
resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.prefix}-aks"

  kubernetes_version        = var.kubernetes_version # null => AKS default; pin in tfvars for prod
  sku_tier                  = "Free"                 # control plane free; saves ~$73/mo vs Standard SLA tier
  automatic_upgrade_channel = "patch"                # azurerm 4.x name (was `automatic_channel_upgrade` in 3.x)

  # Both flags required for Workload Identity (Step 02). Missing the OIDC issuer
  # one is the classic "why won't federation work" bug.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name                         = "system"
    vm_size                      = var.node_vm_size
    node_count                   = var.node_count
    vnet_subnet_id               = var.aks_subnet_id
    os_disk_size_gb              = 30
    only_critical_addons_enabled = false # single pool: let workloads schedule here (lab cost trade-off)

    # AKS auto-sets this default; declare it so it isn't perpetual plan drift.
    upgrade_settings {
      max_surge = "10%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium" # eBPF dataplane; pairs with network_policy = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = var.outbound_type # userDefinedRouting => egress via the firewall UDR
  }

  identity {
    type = "SystemAssigned" # cluster identity; pod Workload Identity is separate (Step 02)
  }

  workload_autoscaler_profile {
    keda_enabled = true # managed KEDA addon (Step 05)
  }

  tags = var.tags
}
