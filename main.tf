resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  cluster_name         = "${var.cluster_name}-${random_string.suffix.result}"
  dns_prefix           = "${var.dns_prefix}-${random_string.suffix.result}"
  storage_account_name = substr(lower(replace("${var.storage_account_name_prefix}${random_string.suffix.result}", "-", "")), 0, 24)
  argocd_helm_values = merge(
    {
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      server = {
        service = {
          type = var.argocd_server_service_type
        }
      }
    },
    var.argocd_admin_password == null ? {} : {
      configs = {
        params = {
          "server.insecure" = true
        }
        secret = {
          argocdServerAdminPassword = var.argocd_admin_password
        }
      }
    }
  )
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "backup" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  min_tls_version          = "TLS1_2"

  allow_nested_items_to_be_public = false

  tags = {
    workload = "aks-argo"
    purpose  = "mydumper-backups"
  }
}

resource "azurerm_storage_container" "backup" {
  name                  = var.backup_blob_container_name
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = local.dns_prefix
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                 = "system"
    node_count           = var.node_count
    vm_size              = var.node_vm_size
    os_disk_size_gb      = var.node_os_disk_size_gb
    auto_scaling_enabled = false
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  role_based_access_control_enabled = true

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    workload = "aks-argo"
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.acr_pull_enabled && var.acr_id != null ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.this.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)
  load_config_file       = false
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false
  atomic           = true
  timeout          = 900

  values = [yamlencode(local.argocd_helm_values)]

  depends_on = [
    azurerm_kubernetes_cluster.this,
    kubernetes_namespace.argocd
  ]
}

resource "kubectl_manifest" "backup_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.app_namespace
      labels = {
        "app.kubernetes.io/name" = var.app_name
      }
    }
  })

  depends_on = [azurerm_kubernetes_cluster.this]
}

resource "kubectl_manifest" "azure_blob_credentials" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = var.azure_blob_secret_name
      namespace = var.app_namespace
    }
    type = "Opaque"
    stringData = {
      azurestorageaccountname = azurerm_storage_account.backup.name
      azurestorageaccountkey  = azurerm_storage_account.backup.primary_access_key
    }
  })

  depends_on = [
    kubectl_manifest.backup_namespace,
    azurerm_storage_container.backup
  ]
}

resource "kubectl_manifest" "mydumper_backup_pv" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolume"
    metadata = {
      name = "mydumper-backups-pv"
      labels = {
        "app.kubernetes.io/name" = var.app_name
      }
    }
    spec = {
      capacity = {
        storage = "${var.backup_blob_capacity_gb}Gi"
      }
      accessModes                   = ["ReadWriteMany"]
      persistentVolumeReclaimPolicy = "Retain"
      storageClassName              = var.backup_blob_storage_class_name
      csi = {
        driver       = "blob.csi.azure.com"
        readOnly     = false
        volumeHandle = "${azurerm_resource_group.this.name}#${azurerm_storage_account.backup.name}#${azurerm_storage_container.backup.name}"
        volumeAttributes = {
          resourceGroup  = azurerm_resource_group.this.name
          storageAccount = azurerm_storage_account.backup.name
          containerName  = azurerm_storage_container.backup.name
          protocol       = var.backup_blob_protocol
        }
        nodeStageSecretRef = {
          name      = var.azure_blob_secret_name
          namespace = var.app_namespace
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.azure_blob_credentials,
    azurerm_storage_container.backup
  ]
}

resource "kubectl_manifest" "mydumper_backup_pvc" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "mydumper-backups"
      namespace = var.app_namespace
      labels = {
        "app.kubernetes.io/name" = var.app_name
      }
    }
    spec = {
      accessModes      = ["ReadWriteMany"]
      storageClassName = var.backup_blob_storage_class_name
      volumeName       = "mydumper-backups-pv"
      resources = {
        requests = {
          storage = "${var.backup_blob_capacity_gb}Gi"
        }
      }
    }
  })

  depends_on = [kubectl_manifest.mydumper_backup_pv]
}

resource "kubectl_manifest" "mydumper_application" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.app_name
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.app_repo_url
        targetRevision = var.app_repo_revision
        path           = var.app_repo_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.app_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.mydumper_backup_pvc
  ]
}
