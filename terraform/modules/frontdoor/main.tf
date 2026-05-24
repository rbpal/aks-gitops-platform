# Azure Front Door Standard — global edge for the eastus2 web app.
# Path: user --HTTPS(managed cert)--> FD --HTTP:80--> AzFW public IP (origin)
#       --DNAT--> internal LB --> ingress-nginx --> payments-api
# FD is a GLOBAL resource (no location). FD->origin is HTTP for the lab; prod
# would use end-to-end TLS (cert at the ingress + certificate_name_check).

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.prefix}-fd"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.prefix}-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "${var.prefix}-og"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = false

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = var.health_probe_path
    request_type        = "GET"
    protocol            = "Http"
    interval_in_seconds = 30
  }
}

resource "azurerm_cdn_frontdoor_origin" "this" {
  name                          = "${var.prefix}-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  enabled                       = true

  # Origin is the firewall's public IP over HTTP — there's no cert to validate.
  certificate_name_check_enabled = false

  host_name          = var.origin_host
  origin_host_header = var.origin_host
  http_port          = 80
  https_port         = 443
  priority           = 1
  weight             = 1000
}

resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "${var.prefix}-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.this.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpOnly" # FD -> origin over HTTP:80
  https_redirect_enabled = true       # user -> FD always upgraded to HTTPS
  link_to_default_domain = true
}
