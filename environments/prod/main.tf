terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ------------------------------------------------------------------------------
# 1. Tier 1 Network Module Call
# ------------------------------------------------------------------------------
module "vpc" {
  source       = "../../modules/01-vpc-network"
  project_id   = var.project_id
  region       = var.region
  network_name = "prod-gke-did-vpc"
  subnet_name  = "prod-gke-did-subnet"
}

# ------------------------------------------------------------------------------
# 2. Tier 1 Encryption Module Call (CMEK)
# ------------------------------------------------------------------------------
module "kms" {
  source       = "../../modules/02-kms-cmek"
  project_id   = var.project_id
  region       = var.region
  keyring_name = "prod-gke-did-keyring"
}

# ------------------------------------------------------------------------------
# Tier 1 Environment Outputs
# ------------------------------------------------------------------------------
output "network_id" {
  value       = module.vpc.network_id
  description = "The fully qualified URI of the production VPC network."
}

output "subnet_id" {
  value       = module.vpc.subnet_id
  description = "The fully qualified URI of the production subnet."
}

output "pod_ip_range_name" {
  value       = module.vpc.pod_ip_range_name
  description = "Secondary range identifier for Pod alias IPs."
}

output "svc_ip_range_name" {
  value       = module.vpc.svc_ip_range_name
  description = "Secondary range identifier for Service IPs."
}

output "gke_etcd_key_id" {
  value       = module.kms.gke_etcd_key_id
  description = "KMS Key URI for GKE etcd secret envelope encryption."
}

output "gke_disk_key_id" {
  value       = module.kms.gke_disk_key_id
  description = "KMS Key URI for GKE Persistent Disk volume encryption."
}