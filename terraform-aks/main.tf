##################################################################################
# RESOURCES
##################################################################################

#retrieve the version of Kubernetes supported by Azure Kubernetes Service.
data "azurerm_kubernetes_service_versions" "current" {
  location = var.resource_group_location
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}-rg"
  location = var.resource_group_location

  tags = {
    creationSource = var.creationSource
    env            = var.environment
  }
}

#an attempt to keep the AKS name (and dns label) unique
resource "random_integer" "random_int" {
  min = 1000
  max = 9999
}

resource "tls_private_key" "key" {
  algorithm   = "RSA"
  ecdsa_curve = "P224"
  rsa_bits    = "2048"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_group_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  tags = {
    creationSource = var.creationSource
    env            = var.environment
  }
}

resource "azurerm_subnet" "frontend" {
  name                 = "frontend"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefix       = "10.0.1.0/28"
}

resource "azurerm_subnet" "backend" {
  name                 = "backend"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefix       = "10.0.2.0/24"
}

# resource "azurerm_role_assignment" "role" {
#   scope                = "${data.azurerm_subscription.subscription.id}/resourceGroups/${azurerm_resource_group.rg.name}"
#   role_definition_name = "Owner"
#   principal_id         = "${var.client_id}"
# }

resource "azurerm_kubernetes_cluster" "main" {
  name       = "${var.aks_name}-${random_integer.random_int.result}"
  location   = "${azurerm_resource_group.rg.location}"
  dns_prefix = "${var.aks_name}-${random_integer.random_int.result}-k8s"

  resource_group_name = azurerm_resource_group.rg.name

  linux_profile {
    admin_username = var.linux_admin_username

    ssh_key {
      key_data = "${trimspace(tls_private_key.key.public_key_openssh)}"
    }
  }

  kubernetes_version = "${data.azurerm_kubernetes_service_versions.current.latest_version}"

  agent_pool_profile {
    name            = "default"
    count           = var.aks_node_count
    vm_size         = "Standard_DS2_v2"
    os_type         = "Linux"
    os_disk_size_gb = 30
    vnet_subnet_id  = azurerm_subnet.backend.id
    type            = "AvailabilitySet"
    max_pods        = 30
  }

  # agent_pool_profile {
  #   name    = "pool2"
  #   count   = 1
  #   vm_size = "Standard_DS1_v2"
  #   os_type = "Linux"
  #   os_disk_size_gb = 30
  #   vnet_subnet_id = azurerm_subnet.backend.id
  #   type = "VirtualMachineScaleSets"
  #   max_pods       = 30
  # }

  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }

  role_based_access_control {
    enabled = true
  }

  network_profile {
    network_plugin     = "azure"
    service_cidr       = "10.100.0.0/16"
    dns_service_ip     = "10.100.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }

  tags = {
    creationSource = var.creationSource
    env            = var.environment
  }
}
