# Unique suffix for globally unique names (storage account, function app).
# Generated once and kept in state, so names stay stable across applies.
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  suffix = random_string.suffix.result

  resource_group_name  = "shopping-lab-${local.suffix}-rg"
  storage_account_name = "shoppinglab${local.suffix}funcsa" # 23 chars, alphanumeric only
  function_app_name    = "products-lab-${local.suffix}-func"

  # Only set optional settings that have a value, so unset features fall back
  # to their defaults (no OAuth2 validation, dummy notifier).
  optional_app_settings = {
    for k, v in {
      OAUTH2_JWKS_URI          = var.oauth2_jwks_uri
      OAUTH2_ISSUER            = var.oauth2_issuer
      OAUTH2_AUDIENCE          = var.oauth2_audience
      PRODUCT_UPDATED_BASE_URL = var.product_updated_base_url
      PRODUCT_UPDATED_KEY      = var.product_updated_key
    } : k => v if trimspace(v) != ""
  }
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "func" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_kind             = "StorageV2"
  account_tier             = "Standard" # Premium has no free allowance
  account_replication_type = "LRS"      # cheapest redundancy; free-account 5 GB grant is LRS
  access_tier              = "Hot"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${local.function_app_name}-law"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018" # first 5 GB/month ingestion is free
  retention_in_days   = 30          # 31 days retention is included at no cost
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                 = "${local.function_app_name}-appi"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  workspace_id         = azurerm_log_analytics_workspace.this.id
  application_type     = "Node.JS"
  retention_in_days    = 30
  daily_data_cap_in_gb = var.log_daily_quota_gb
  tags                 = var.tags
}

# Flex Consumption (FC1) plan. Used instead of the classic Consumption (Y1)
# plan, which many new subscriptions have zero quota for. Its free grant is
# 100,000 GB-s and 250,000 executions per month.
# (The App Service Free/F1 plan does not support Function Apps.)
resource "azurerm_service_plan" "this" {
  name                = "${local.function_app_name}-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = var.tags
}

# Flex Consumption deploys the app package to this blob container.
resource "azurerm_storage_container" "deploy" {
  name                  = "app-package"
  storage_account_id    = azurerm_storage_account.func.id
  container_access_type = "private"
}

resource "azurerm_function_app_flex_consumption" "this" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.func.primary_blob_endpoint}${azurerm_storage_container.deploy.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.func.primary_access_key

  runtime_name    = "node"
  runtime_version = var.node_version

  # Smallest instance size and lowest allowed scale-out cap, to stretch the
  # free GB-s grant and bound worst-case cost.
  instance_memory_in_mb  = var.instance_memory_in_mb
  maximum_instance_count = 40

  https_only      = true
  zip_deploy_file = var.app_package_path

  site_config {
    application_insights_connection_string = azurerm_application_insights.this.connection_string

    cors {
      allowed_origins = var.cors_allowed_origins
    }
  }

  app_settings = local.optional_app_settings

  tags = var.tags
}

# Host keys, used to call upsertProduct via the x-functions-key header.
data "azurerm_function_app_host_keys" "this" {
  name                = azurerm_function_app_flex_consumption.this.name
  resource_group_name = azurerm_resource_group.this.name
}
