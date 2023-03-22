locals {
  airflow_url = var.environment == "prod" ? "https://bas-orchestrator.eaton.com/api/v1" : format("https://bas-orchestrator-%s.eaton.com/api/v1", var.environment)
}

resource "azurerm_app_service_plan" "function_app_service_plan" {
  name                = "bas-api-${var.environment}-${var.location}-p01"
  resource_group_name = var.target_app_rg
  location            = var.location
  kind                = "linux"
  sku {
    tier     = "PremiumV2"
    size     = "P1v2"
    capacity = "1"
  }
  reserved = true
}

resource "azurerm_monitor_diagnostic_setting" "app-service-evh-diag" {
  name                           = "${azurerm_app_service_plan.function_app_service_plan.name}-sp-evh-diag-setting"
  target_resource_id             = azurerm_app_service_plan.function_app_service_plan.id
  eventhub_authorization_rule_id = module.azure-logs-event-hub.authorization_keys_id[var.eventhub-log-authorization-name]
  eventhub_name                  = "${var.eventhub-logging-name}-${var.environment}-${var.location}-p01"

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "app-service-st-diag" {
  name               = "${azurerm_app_service_plan.function_app_service_plan.name}-sp-st-diag-setting"
  target_resource_id = azurerm_app_service_plan.function_app_service_plan.id
  storage_account_id = module.azure-logs-storage-account.id


  metric {
    category = "AllMetrics"
    enabled  = true
    retention_policy {
      enabled = false
      days    = 0
    }
  }
}

# can't be used here because apim might not have been created yet, as it's the case with production at the moment
# data "azurerm_api_management" "bas_apim" {
#   name = "apim-bas-${var.environment}-${var.location}-p01"
#   resource_group_name = "ETN-ES-BAS-apim"
# }
resource "azurerm_linux_function_app" "function_app" {
  name                       = "bas-api-${var.environment}-${var.location}-p01"
  location                   = var.location
  resource_group_name        = var.target_app_rg
  storage_account_name       = module.storage-account.name
  storage_account_access_key = module.storage-account.primary_access_key
  service_plan_id            = azurerm_app_service_plan.function_app_service_plan.id
  https_only                 = true
  app_settings = {
    FUNCTIONS_EXTENSION_VERSION = "~4"
    FUNCTION_APP_EDIT_MODE      = "readOnly"
    AzureWebJobsStorage         = module.storage-account.primary_connection_string
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = false
    DOCKER_REGISTRY_SERVER_URL          = azurerm_container_registry.main.login_server
    DOCKER_REGISTRY_SERVER_USERNAME     = azurerm_container_registry.main.admin_username
    DOCKER_REGISTRY_SERVER_PASSWORD     = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "acr-password")
    DOCKER_CUSTOM_IMAGE_NAME            = "${azurerm_container_registry.main.login_server}/bas-api:latest"
    AIRFLOW_URL                         = local.airflow_url
    COSMOS_DB_CONN                      = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "config-store-connection")
    AIRFLOW_API_FERNET_KEY              = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "AIRFLOW-API-FERNET-KEY")
    POSTGRES_HOST                       = format("%s.postgres.database.azure.com", azurerm_postgresql_server.postgresql-server.name)
    POSTGRES_CONN                       = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "airflow-postgres")
    INSIGHTS_BLOB_CONN                  = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "insights-blob-connection")
  }

  lifecycle {
    ignore_changes = [
      app_settings["DOCKER_CUSTOM_IMAGE_NAME"],
      app_settings["COSMOS_DB_CONN"],
      app_settings["POSTGRES_HOST"],
      app_settings["POSTGRES_CONN"],
      app_settings["INSIGHTS_BLOB_CONN"],
      app_settings["WEBSITES_ENABLE_APP_SERVICE_STORAGE"],
    ]
  }

  site_config {
    always_on        = true
    linux_fx_version = "DOCKER|${azurerm_container_registry.main.login_server}/bas-api:latest"

  ip_restriction {
      ip_address = "${azurerm_api_management.main.public_ip_addresses[0]}/32"
      priority   = 1000
      name       = "APIM Access Only"
    }
  }

  key_vault_reference_identity_id = azurerm_user_assigned_identity.bas_api_function.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.bas_api_function.id]
  }
  version = "~4"

  auth_settings {
    enabled          = true
    default_provider = "MicrosoftAccount"
    active_directory {
      client_id = azurerm_user_assigned_identity.bas_api_function.client_id
    }
  }
}
# resource "azurerm_function_app" "function_app" {
#   name                       = "bas-api-${var.environment}-${var.location}-p01"
#   location                   = var.location
#   resource_group_name        = var.target_app_rg
#   app_service_plan_id        = azurerm_app_service_plan.function_app_service_plan.id
#   storage_account_name       = module.storage-account.name
#   storage_account_access_key = module.storage-account.primary_access_key
#   app_settings = {
#     FUNCTIONS_EXTENSION_VERSION         = "~4"
#     FUNCTION_APP_EDIT_MODE              = "readOnly"
#     https_only                          = true
#     WEBSITES_ENABLE_APP_SERVICE_STORAGE = false
#     AzureWebJobsStorage                 = module.storage-account.primary_connection_string
#     DOCKER_REGISTRY_SERVER_URL          = azurerm_container_registry.main.login_server
#     DOCKER_REGISTRY_SERVER_USERNAME     = azurerm_container_registry.main.admin_username
#     DOCKER_REGISTRY_SERVER_PASSWORD     = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "acr-password")
#     DOCKER_CUSTOM_IMAGE_NAME            = "${azurerm_container_registry.main.login_server}/bas-api:latest"
#     AIRFLOW_URL                         = local.airflow_url
#     COSMOS_DB_CONN                      = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "config-store-connection")
#     AIRFLOW_API_FERNET_KEY              = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "AIRFLOW-API-FERNET-KEY")
#     POSTGRES_HOST                       = format("%s.postgres.database.azure.com", azurerm_postgresql_server.postgresql-server.name)
#     POSTGRES_CONN                       = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "airflow-postgres")
#     INSIGHTS_BLOB_CONN                  = format("@Microsoft.KeyVault(VaultName=%s;SecretName=%s)", module.aks-key-vault.key_vault_name, "insights-blob-connection")
#   }

#   lifecycle {
#     ignore_changes = [
#       app_settings["DOCKER_CUSTOM_IMAGE_NAME"],
#       app_settings["COSMOS_DB_CONN"],
#       app_settings["POSTGRES_HOST"],
#       app_settings["POSTGRES_CONN"],
#       app_settings["INSIGHTS_BLOB_CONN"],
#       app_settings["WEBSITES_ENABLE_APP_SERVICE_STORAGE"],
#     ]
#   }

#   site_config {
#     always_on        = true
#     linux_fx_version = "DOCKER|${azurerm_container_registry.main.login_server}/bas-api:latest"

#     ip_restriction {
#       ip_address = "${azurerm_api_management.main.public_ip_addresses[0]}/32"
#       priority   = 1000
#       name       = "APIM Access Only"
#     }
#   }

#   key_vault_reference_identity_id = azurerm_user_assigned_identity.bas_api_function.id

#   identity {
#     type         = "UserAssigned"
#     identity_ids = [azurerm_user_assigned_identity.bas_api_function.id]
#   }
#   version = "~4"

#   auth_settings {
#     enabled          = true
#     default_provider = "MicrosoftAccount"
#     active_directory {
#       client_id = azurerm_user_assigned_identity.bas_api_function.client_id
#     }
#   }
# }

resource "azurerm_user_assigned_identity" "bas_api_function" {
  resource_group_name = var.target_app_rg
  location            = var.location
  name                = "bas-api-function"
}

resource "azurerm_key_vault_access_policy" "example" {
  key_vault_id = module.aks-key-vault.id
  tenant_id    = azurerm_user_assigned_identity.bas_api_function.tenant_id
  object_id    = azurerm_user_assigned_identity.bas_api_function.principal_id

  key_permissions = [
    "Get",
  ]

  secret_permissions = [
    "Get",
  ]
}

resource "azurerm_app_service_virtual_network_swift_connection" "example" {
  app_service_id = azurerm_linux_function_app.function_app.id
  subnet_id      = azurerm_subnet.subnet-afa-secure.id
}

resource "azurerm_monitor_diagnostic_setting" "airflow-func-evh-diag" {
  name                           = "${azurerm_linux_function_app.function_app.name}-fn-evh-diag-setting"
  target_resource_id             = azurerm_linux_function_app.function_app.id
  eventhub_authorization_rule_id = module.azure-logs-event-hub.authorization_keys_id[var.eventhub-log-authorization-name]
  eventhub_name                  = "${var.eventhub-logging-name}-${var.environment}-${var.location}-p01"

  log {
    category = "FunctionAppLogs"
    enabled  = true
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "airflow-func-st-diag" {
  name               = "${azurerm_linux_function_app.function_app.name}-fn-st-diag-setting"
  target_resource_id = azurerm_linux_function_app.function_app.id
  storage_account_id = module.azure-logs-storage-account.id


  log {
    category = "FunctionAppLogs"
    enabled  = true
    retention_policy {
      enabled = false
      days    = 0
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true
    retention_policy {
      enabled = false
      days    = 0
    }
  }
}
