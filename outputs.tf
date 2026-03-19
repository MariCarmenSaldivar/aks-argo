output "resource_group_name" {
  description = "Resource group that holds the AKS cluster."
  value       = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "aks_kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "argocd_server_service_type" {
  description = "Service type configured for the Argo CD server."
  value       = var.argocd_server_service_type
}

output "argocd_namespace" {
  description = "Namespace where Argo CD is installed."
  value       = var.argocd_namespace
}

output "argocd_application_name" {
  description = "Argo CD Application name for MyDumper."
  value       = var.app_name
}

output "backup_storage_account_name" {
  description = "Storage account used for MyDumper backups."
  value       = azurerm_storage_account.backup.name
}

output "backup_blob_container_name" {
  description = "Azure Blob container used for MyDumper backups."
  value       = azurerm_storage_container.backup.name
}

output "backup_storage_primary_access_key" {
  description = "Primary access key for the backup storage account."
  value       = azurerm_storage_account.backup.primary_access_key
  sensitive   = true
}
