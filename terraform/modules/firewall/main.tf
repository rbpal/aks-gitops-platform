# Azure Firewall BASIC (sandbox-allowed SKU). Basic REQUIRES a management IP
# configuration (its own subnet + public IP) on top of the data IP configuration.
# Both public IPs must be Standard SKU + Static. The firewall's private IP comes
# from AzureFirewallSubnet in the HUB (first usable, e.g. 10.10.0.4) — that's the
# next hop the spoke subnets' 0/0 route points at (see the network module).

resource "azurerm_public_ip" "data" {
  name                = "${var.prefix}-azfw-data-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_public_ip" "mgmt" {
  name                = "${var.prefix}-azfw-mgmt-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  name                = "${var.prefix}-azfw-pol"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic" # must match the firewall sku_tier
  tags                = var.tags
}

resource "azurerm_firewall" "this" {
  name                = "${var.prefix}-azfw"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.this.id

  ip_configuration {
    name                 = "data"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.data.id
  }

  # Basic SKU only — the management plane NIC.
  management_ip_configuration {
    name                 = "mgmt"
    subnet_id            = var.firewall_mgmt_subnet_id
    public_ip_address_id = azurerm_public_ip.mgmt.id
  }

  tags = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "main" {
  name               = "${var.prefix}-rcg"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 1000

  # Azure rejects policy rule changes while the firewall is still provisioning
  # (400 InternalServerError). The RCG attaches to the POLICY, not the firewall,
  # so without this it races the ~8-min firewall create. Serialize it after.
  depends_on = [azurerm_firewall.this]

  # INBOUND: Front Door -> AzFW data public IP:80 -> internal LB frontend IP:80.
  # source lock = Front Door backend IPs in prod (var); '*' for lab + FDID check.
  nat_rule_collection {
    name     = "inbound-dnat"
    priority = 100
    action   = "Dnat"

    rule {
      name                = "frontdoor-to-ingress"
      protocols           = ["TCP"]
      source_addresses    = var.frontdoor_source_addresses
      destination_address = azurerm_public_ip.data.ip_address
      destination_ports   = ["80"] # FD forwards to the origin over HTTP:80
      translated_address  = var.internal_lb_ip # AKS node IP
      translated_port     = "30080"            # ingress-nginx NodePort (no internal LB; sandbox denies the role assignment one needs)
    }
  }

  # EGRESS at L4 (network rules). Azure Firewall BASIC reliably accepts L4 network
  # rules; an FQDN-TAG application rule (destination_fqdn_tags=["AzureKubernetesService"])
  # triggered a 400 InternalServerError on this Basic policy, so egress is expressed
  # at L4. NTP + 443 (AKS API server, MCR, ghcr, AAD) + 80 (bootstrap) + the AKS
  # secure-tunnel ports keep nodes able to join the control plane under UDR egress.
  # Prod note: Premium SKU adds FQDN/L7 application rules + IDPS for tighter egress.
  network_rule_collection {
    name     = "egress-network"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "ntp"
      protocols             = ["UDP"]
      source_addresses      = var.workload_source_cidrs
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }

    rule {
      name                  = "https-egress" # AKS API server, MCR, ghcr, AAD/Entra, KV/SB mgmt
      protocols             = ["TCP"]
      source_addresses      = var.workload_source_cidrs
      destination_addresses = ["*"]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "servicebus-amqp" # payments-api + worker -> Service Bus over AMQP/TLS
      protocols             = ["TCP"]
      source_addresses      = var.workload_source_cidrs
      destination_addresses = ["*"]
      destination_ports     = ["5671", "5672"]
    }

    rule {
      name                  = "http-egress" # package + bootstrap over HTTP
      protocols             = ["TCP"]
      source_addresses      = var.workload_source_cidrs
      destination_addresses = ["*"]
      destination_ports     = ["80"]
    }

    rule {
      name                  = "aks-tunnel" # AKS secure tunnel (legacy 1194/9000; harmless to allow)
      protocols             = ["UDP", "TCP"]
      source_addresses      = var.workload_source_cidrs
      destination_addresses = ["*"]
      destination_ports     = ["1194", "9000"]
    }
  }
}
