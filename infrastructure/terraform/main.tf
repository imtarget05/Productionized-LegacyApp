terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  # Terraform State lưu trên Azure Storage Account — uncomment sau khi tạo backend:
  # backend "azurerm" {
  #   resource_group_name  = "tfstate-rg"
  #   storage_account_name = "tfstate12345"
  #   container_name       = "tfstate"
  #   key                  = "inventory-sync.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "legacy" {
  name     = "rg-legacy-apps"
  location = var.location
}

# 1. Tận dụng ACR chung (yêu cầu admin_enabled = true trên ACR đó)
data "azurerm_container_registry" "acr" {
  name                = "sharedacr"
  resource_group_name = "rg-shared-infra"
}

# 2. Deploy Legacy App lên Azure Web App for Containers
resource "azurerm_service_plan" "app_plan" {
  name                = "asp-legacy-inventory"
  location            = var.location
  resource_group_name = azurerm_resource_group.legacy.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "app" {
  name                = "app-legacy-inventory-sync"
  location            = var.location
  resource_group_name = azurerm_resource_group.legacy.name
  service_plan_id     = azurerm_service_plan.app_plan.id

  site_config {
    always_on = true
    # App Service health probe: traffic chỉ đến instance healthy (endpoint /health).
    health_check_path = "/health"
    application_stack {
      docker_image_name        = "legacy-inventory-worker:latest"
      docker_registry_url      = "https://${data.azurerm_container_registry.acr.login_server}"
      docker_registry_username = data.azurerm_container_registry.acr.admin_username
      docker_registry_password = data.azurerm_container_registry.acr.admin_password
    }
  }

  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "PORT"                                = "3000"
  }

  logs {
    application_logs {
      file_system_level = "Information"
    }
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  tags = {
    project  = "02-productionized-legacy-app"
    managed_by = "terraform"
  }
}

output "app_url" {
  value = "https://${azurerm_linux_web_app.app.default_hostname}"
}
