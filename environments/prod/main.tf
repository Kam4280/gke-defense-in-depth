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
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke_cluster.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke_cluster.cluster_ca_certificate)
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
# ------------------------------------------------------------------------------
# 3. Tier 2 Binary Authorization Module Call (Supply Chain Security)
# ------------------------------------------------------------------------------
module "binary_auth" {
  source     = "../../modules/04-binary-auth"
  project_id = var.project_id

  depends_on = [
    module.gke_cluster
  ]
}

# Output Binary Authorization Attestor Name
output "binauthz_attestor_name" {
  value       = module.binary_auth.attestor_name
  description = "The Binary Authorization attestor name."
}
# ------------------------------------------------------------------------------
# Module 05: Tier 3 Cloud Service Mesh & Fleet Registration
# ------------------------------------------------------------------------------
module "cloud_service_mesh" {
  source       = "../../modules/05-cloud-service-mesh"
  project_id   = var.project_id
  location     = var.region
  cluster_name = var.cluster_name
  cluster_id   = module.gke_cluster.cluster_id

  depends_on = [
    module.gke_cluster
  ]
}
# ------------------------------------------------------------------------------
# Module 06: Tier 4 Governance & OPA Gatekeeper (Policy Controller)
# ------------------------------------------------------------------------------
module "policy_gatekeeper" {
  source        = "../../modules/06-policy-gatekeeper"
  project_id    = var.project_id
  membership_id = module.cloud_service_mesh.membership_id

  depends_on = [
    module.cloud_service_mesh
  ]
}
# ------------------------------------------------------------------------------
# Module 07: Tier 5 SecOps Audit Logging & Log Sinks
# ------------------------------------------------------------------------------
module "secops_logging" {
  source       = "../../modules/07-secops-logging"
  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name

  depends_on = [
    module.gke_cluster
  ]
}
# ------------------------------------------------------------------------------
# Module 08: Tier 6 Sandboxed MLOps Workload Deployment
# ------------------------------------------------------------------------------
module "mlops_inference" {
  source       = "../../modules/08-mlops-inference"
  project_id   = var.project_id
  cluster_name = var.cluster_name

  depends_on = [
    module.gke_cluster
  ]
}

output "mlops_namespace" {
  value       = module.mlops_inference.namespace
  description = "The namespace of the deployed sandboxed MLOps workload."
}