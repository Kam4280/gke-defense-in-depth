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

# ------------------------------------------------------------------------------
# 1. Dedicated Least-Privilege Node Service Account
# ------------------------------------------------------------------------------
resource "google_service_account" "gke_nodes_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "Hardened GKE Node Pool Service Account"
  project      = var.project_id
}

# IAM Role Bindings for Node SA
resource "google_project_iam_member" "node_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes_sa.email}"
}

resource "google_project_iam_member" "node_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes_sa.email}"
}

resource "google_project_iam_member" "node_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes_sa.email}"
}

resource "google_kms_crypto_key_iam_member" "node_disk_decrypter" {
  crypto_key_id = var.gke_disk_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.gke_nodes_sa.email}"
}

# ------------------------------------------------------------------------------
# 2. Hardened Private GKE Control Plane
# ------------------------------------------------------------------------------
resource "google_container_cluster" "primary" {
  provider = google-beta

  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  # Attach to Tier 1 VPC Network & Subnet
  network    = var.network_id
  subnetwork = var.subnet_id

  # Delete the default node pool to replace with hardened pools
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network & Pod IP Allocation
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pod_ip_range_name
    services_secondary_range_name = var.svc_ip_range_name
  }

  # Datapath & Network Policies (eBPF / Dataplane V2)
  datapath_provider = "ADVANCED_DATAPATH"

  # Private Cluster Network Security Profile
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Workload Identity Federation
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # CMEK Envelope Encryption for Kubernetes Secrets (etcd)
  database_encryption {
    state    = "ENCRYPTED"
    key_name = var.gke_etcd_key_id
  }

  # Shielded Nodes
  enable_shielded_nodes = true

  # Release Channel & Maintenance
  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  deletion_protection = true
}

# ------------------------------------------------------------------------------
# 3. System Node Pool (Internal System Workloads)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "system_nodes" {
  name       = "system-node-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-standard-4"
    image_type   = "COS_CONTAINERD"
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # KMS CMEK Boot Disk Encryption
    boot_disk_kms_key = var.gke_disk_key_id

    # Dedicated Least-Privilege SA
    service_account = google_service_account.gke_nodes_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Shielded VM Hardening
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      "workload-tier" = "system"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

# ------------------------------------------------------------------------------
# 4. Sandbox Node Pool (gVisor MicroVM Workload Isolation)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "gvisor_nodes" {
  provider = google-beta

  name       = "gvisor-sandbox-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-standard-4"
    image_type   = "COS_CONTAINERD"
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Enable gVisor Sandbox Runtime (GKE manages sandbox.gke.io/runtime label and taint)
    sandbox_config {
      sandbox_type = "gvisor"
    }

    # KMS CMEK Boot Disk Encryption
    boot_disk_kms_key = var.gke_disk_key_id

    # Dedicated Least-Privilege SA
    service_account = google_service_account.gke_nodes_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Shielded VM Hardening
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      "workload-tier" = "untrusted-unisolated"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}