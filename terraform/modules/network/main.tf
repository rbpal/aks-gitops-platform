# Network module: regional HUB-SPOKE.
#   HUB VNet   — Azure Firewall (data + management subnets).
#   SPOKE VNet — AKS nodes (+ the internal LB frontend, default) and PEs.
#   Hub <-> Spoke peering: the spoke routes 0/0 to the hub firewall, and the
#   firewall DNATs inbound to / forwards return from the spoke.
# Does NOT manage the resource group — the sandbox pre-creates it.

# ----------------------------- HUB -----------------------------
resource "azurerm_virtual_network" "hub" {
  name                = "${var.prefix}-hub-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.hub_address_space
  tags                = var.tags
}

# Azure Firewall DATA plane. Name + min /26 are FIXED by Azure.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = var.firewall_subnet_prefix
}

# Azure Firewall MANAGEMENT plane — REQUIRED by the Basic SKU. Name + /26 FIXED.
resource "azurerm_subnet" "firewall_mgmt" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = var.firewall_mgmt_subnet_prefix
}

# ----------------------------- SPOKE -----------------------------
resource "azurerm_virtual_network" "spoke" {
  name                = "${var.prefix}-spoke-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.spoke_address_space
  tags                = var.tags
}

# AKS node subnet. Hosts BOTH the LB backend pool (the nodes) AND the internal
# LB frontend VIP (pinned to 10.11.1.250) — same subnet, the AKS default, so no
# cross-subnet role assignment is needed (the sandbox blocks role assignments).
resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = var.node_subnet_prefix
}

# Private Endpoints for PaaS (Key Vault / Service Bus). Net-policies Enabled so
# the NSG below actually governs the PE NICs.
resource "azurerm_subnet" "pe" {
  name                              = "peSubnet"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.spoke.name
  address_prefixes                  = var.pe_subnet_prefix
  private_endpoint_network_policies = "Enabled"
}

# ------------------------ HUB <-> SPOKE PEERING ------------------------
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_forwarded_traffic      = true # firewall forwards spoke traffic
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_forwarded_traffic      = true
  allow_virtual_network_access = true
}

# ------------------- SPOKE ROUTING: 0/0 -> HUB FIREWALL -------------------
# Force every spoke subnet's egress to the hub firewall's PRIVATE IP (reachable
# via the peering). The hub firewall subnets carry NO such route (Azure forbids
# 0/0 -> firewall on the firewall's own subnet).
resource "azurerm_route_table" "spoke" {
  name                = "${var.prefix}-spoke-rt"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }
}

resource "azurerm_subnet_route_table_association" "aks_nodes" {
  subnet_id      = azurerm_subnet.aks_nodes.id
  route_table_id = azurerm_route_table.spoke.id
}

resource "azurerm_subnet_route_table_association" "pe" {
  subnet_id      = azurerm_subnet.pe.id
  route_table_id = azurerm_route_table.spoke.id
}

# ------------------------------ SPOKE NSGs ------------------------------
# Baseline NSG on the AKS node subnet (compliance: every subnet gets an NSG).
resource "azurerm_network_security_group" "aks_nodes" {
  name                = "${var.prefix}-aks-nodes-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks_nodes.id
}

# Locked NSG on the PE subnet: only the AKS node subnet may reach the endpoints.
resource "azurerm_network_security_group" "pe" {
  name                = "${var.prefix}-pe-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "allow-aks-to-pe"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = var.node_subnet_prefix
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_ranges    = ["443", "5671"]
  }

  security_rule {
    name                       = "allow-azure-lb"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "AzureLoadBalancer"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}
