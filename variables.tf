variable "subscription_id" {
  description = "Azure subscription ID used for all resources."
  type        = string
}

variable "location" {
  description = "Azure region for the resource group and AKS cluster."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
  default     = "rg-aks-argo"
}

variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
  default     = "aks-argo"
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS API server."
  type        = string
  default     = "aks-argo"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Leave null to use the Azure default supported version."
  type        = string
  default     = null
}

variable "node_count" {
  description = "Number of nodes in the default AKS node pool."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for the default AKS node pool."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "node_os_disk_size_gb" {
  description = "OS disk size for the AKS node pool."
  type        = number
  default     = 128
}

variable "acr_pull_enabled" {
  description = "Whether to attach the cluster kubelet identity to AcrPull on an existing ACR."
  type        = bool
  default     = false
}

variable "acr_id" {
  description = "Optional existing Azure Container Registry resource ID for AcrPull assignment."
  type        = string
  default     = null
}

variable "argocd_namespace" {
  description = "Namespace for the Argo CD installation."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version."
  type        = string
  default     = "7.8.23"
}

variable "argocd_server_service_type" {
  description = "Kubernetes Service type for the Argo CD server."
  type        = string
  default     = "LoadBalancer"
}

variable "argocd_admin_password" {
  description = "Optional bcrypt hash for the Argo CD admin password. If null, Argo CD generates the initial secret."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_name" {
  description = "Argo CD Application name for the MyDumper CronJob."
  type        = string
  default     = "mydumper-cronjob"
}

variable "app_namespace" {
  description = "Namespace where the MyDumper CronJob will run."
  type        = string
  default     = "backup-jobs"
}

variable "app_repo_url" {
  description = "Git repository URL that Argo CD should watch for the MyDumper app manifests."
  type        = string
}

variable "app_repo_revision" {
  description = "Git revision tracked by Argo CD."
  type        = string
  default     = "main"
}

variable "app_repo_path" {
  description = "Path inside the Git repository that contains the MyDumper manifests."
  type        = string
  default     = "apps/mydumper-cronjob"
}

variable "storage_account_name_prefix" {
  description = "Prefix used to generate the backup storage account name (lowercase letters and numbers only)."
  type        = string
  default     = "stmydump"
}

variable "storage_account_tier" {
  description = "Performance tier for the backup storage account."
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Replication type for the backup storage account."
  type        = string
  default     = "LRS"
}

variable "backup_blob_container_name" {
  description = "Azure Blob container name used by MyDumper backups."
  type        = string
  default     = "mydumper-backups"
}

variable "backup_blob_capacity_gb" {
  description = "Requested capacity in GiB for the Blob CSI-backed persistent volume."
  type        = number
  default     = 100
}

variable "azure_blob_secret_name" {
  description = "Kubernetes secret name holding Azure Blob storage credentials."
  type        = string
  default     = "azure-blob-credentials"
}

variable "backup_blob_storage_class_name" {
  description = "Storage class name used for the Blob CSI static PV/PVC binding."
  type        = string
  default     = "azureblob-fuse-csi"
}

variable "backup_blob_protocol" {
  description = "Protocol used by Azure Blob CSI (fuse or nfs)."
  type        = string
  default     = "fuse"
}
