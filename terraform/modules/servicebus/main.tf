# Service Bus — the event source KEDA scales off of.

resource "random_string" "sb" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_servicebus_namespace" "this" {
  name                = "${var.prefix}-sb-${random_string.sb.result}" # globally unique
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic" # sandbox Azure Policy "service-bus-basic" forces Basic. Basic supports QUEUES (no topics) — all KEDA needs here.
  tags                = var.tags
}

resource "azurerm_servicebus_queue" "demo" {
  name                  = "demo-queue"
  namespace_id          = azurerm_servicebus_namespace.this.id
  max_size_in_megabytes = 1024
}

# SANDBOX ADAPTATION: KEDA → Service Bus via a SAS connection string, because the
# sandbox denies the "Azure Service Bus Data Receiver" ROLE ASSIGNMENT the
# Workload-Identity path would need. This rule's connection string is put in a
# K8s Secret and referenced by KEDA's TriggerAuthentication. (manage = true so
# KEDA can read queue depth via the management API; send/listen come with it.)
resource "azurerm_servicebus_namespace_authorization_rule" "keda" {
  name         = "keda-lab"
  namespace_id = azurerm_servicebus_namespace.this.id

  listen = true
  send   = true
  manage = true
}
