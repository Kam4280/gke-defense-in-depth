terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "kam-dev-test-tfstate-gke-did"
    prefix = "terraform/state/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ------------------------------------------------------------------------------
# Module 01: Tier 1 VPC Network Foundation
# ------------------------------------------------------------------------------
module "vpc_network" {
  source     = "../../modules/01-vpc-network"
  project_id = var.project_id
  region     = var.region
}

# ------------------------------------------------------------------------------
# Module 02: Tier 1 KMS CMEK Keyrings & Keys
# ------------------------------------------------------------------------------
module "kms_cmek" {
  source     = "../../modules/02-kms-cmek"
  project_id = var.project_id
  region     = var.region
}

# ------------------------------------------------------------------------------
# Module 03: Tier 2 Hardened Private GKE Cluster
# ------------------------------------------------------------------------------
module "gke_cluster" {
  source                 = "../../modules/03-gke-cluster"
  project_id             = var.project_id
  region                 = var.region
  cluster_name           = var.cluster_name
  network_id             = module.vpc_network.network_id
  subnet_id              = module.vpc_network.subnet_id
  pod_ip_range_name      = module.vpc_network.pod_ip_range_name
  svc_ip_range_name      = module.vpc_network.svc_ip_range_name
  gke_etcd_key_id        = module.kms_cmek.gke_etcd_key_id
  gke_disk_key_id        = module.kms_cmek.gke_disk_key_id
  master_ipv4_cidr_block = "172.16.0.0/28"

  depends_on = [
    module.vpc_network,
    module.kms_cmek
  ]
}