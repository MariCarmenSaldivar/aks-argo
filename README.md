# AKS + Argo CD + MyDumper

This repository provisions an Azure Kubernetes Service (AKS) cluster, installs Argo CD with Terraform, and creates an Argo CD `Application` that syncs a MyDumper backup `CronJob` from this repository.

## What gets created

- Azure resource group
- AKS cluster with a system node pool
- Argo CD namespace and Helm release
- Argo CD `Application` named `mydumper-cronjob`
- Azure Storage Account and Azure Blob container for backups
- Kubernetes namespace, Azure Blob credentials secret, persistent volume, and persistent volume claim for backup storage
- Kubernetes manifests for a MyDumper `CronJob`, service account, and support resources

## Repository layout

- `versions.tf`: Terraform version and provider requirements
- `variables.tf`: Input variables
- `main.tf`: Azure, Helm, and Kubernetes resources
- `outputs.tf`: Useful outputs after apply
- `terraform.tfvars.example`: Example input values
- `apps/mydumper-cronjob`: Argo CD application manifests

## Prerequisites

- Azure subscription with permission to create AKS and role assignments
- `terraform` 1.6+
- Azure CLI authenticated with `az login`
- A Git repository URL that Argo CD can reach

## Quick start

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and update the values.
2. Push this repository to your Git provider.
3. Run Terraform.
4. Create the MyDumper config secret in the target namespace.
5. Trigger or wait for the CronJob.

## Example Terraform commands

```powershell
Set-Location "c:\Users\CarmenSaldivar\Documents\POC\aks-argo"
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Required inputs

The most important values in `terraform.tfvars` are:

- `subscription_id`: Azure subscription ID
- `app_repo_url`: Git URL for this repository, for example `https://github.com/your-org/aks-argo.git`
- `app_repo_revision`: Branch or tag to track, usually `main`
- `app_repo_path`: Path containing the app manifests, default `apps/mydumper-cronjob`
- `storage_account_name_prefix`: Prefix used for the backup storage account name
- `backup_blob_container_name`: Azure Blob container name used by the CronJob backup volume
- `backup_blob_capacity_gb`: Requested capacity for the Blob CSI-backed volume in GiB
- `backup_blob_storage_class_name`: Storage class label used for the static Blob CSI PV/PVC binding
- `backup_blob_protocol`: Blob CSI protocol (`fuse` or `nfs`)

## Argo CD access

If `argocd_server_service_type = "LoadBalancer"`, Azure assigns a public IP to the Argo CD server service.

After apply, get the service endpoint and initial admin password:

```powershell
az aks get-credentials --resource-group rg-aks-argo --name <aks-cluster-name> --overwrite-existing
kubectl get svc argocd-server -n argocd
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

## MyDumper secret

The CronJob expects a secret named `mydumper-config` with a `mydumper.cnf` key. A template is available in `apps/mydumper-cronjob/mydumper-config-secret.example.yaml`.

Create it after Argo CD syncs the namespace:

```powershell
kubectl apply -f .\apps\mydumper-cronjob\mydumper-config-secret.example.yaml
```

Update the secret with your real MySQL hostname, username, password, and database before applying it.

## Backup storage mount

Terraform provisions an Azure Storage Account and Azure Blob container, then creates:

- Namespace `backup-jobs`
- Secret `azure-blob-credentials`
- PersistentVolume `mydumper-backups-pv`
- PersistentVolumeClaim `mydumper-backups`

The CronJob mounts this PVC at `/backup`, so each run writes backups to the Azure Blob container through the Blob CSI driver.

Useful outputs:

- `backup_storage_account_name`
- `backup_blob_container_name`

## CronJob behavior

- Schedule: daily at `02:00`
- Image: `mydumper/mydumper:latest`
- Output path: `/backup/<timestamp>`
- Retention: keeps the 7 most recent backup directories
- Storage: Azure Blob container mounted via Blob CSI `PersistentVolumeClaim` (`ReadWriteMany`)

## Notes

- The Argo CD `Application` points back to this repo, so the repo must be pushed before `terraform apply`.
- If you want a private Argo CD endpoint, set `argocd_server_service_type = "ClusterIP"` and use port-forwarding or an ingress.
- If you attach an existing Azure Container Registry, set `acr_pull_enabled = true` and provide `acr_id`.
