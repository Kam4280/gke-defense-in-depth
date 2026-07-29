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
# 1. Custom Least-Privilege Node Service Account
# ------------------------------------------------------------------------------
resource "google_service_account" "gke_nodes_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "Hardened GKE Node Pool Service Account"
  project      = var.project_id
}

# Additive IAM Grants for Node SA
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

# Grant Node SA permission to decrypt boot disks using CMEK
resource "google_kms_crypto_key_iam_member" "node_disk_decrypter" {
  crypto_key_id = var.gke_disk_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.gke_nodes_sa.email}"
}

# ------------------------------------------------------------------------------
# 2. Hardened Private GKE Control Plane
# ------------------------------------------------------------------------------
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  network    = var.network_id
  subnetwork = var.subnet_id

  # Deletes the default unhardened node pool upon creation
  remove_default_node_pool = true
  initial_node_count       = 1

  # Layer 4: Dataplane V2 (Cilium eBPF)
  datapath_provider = "ADVANCED_DATAPATH"

  # IP Allocation Policy for Secondary Ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pod_ip_range_name
    services_secondary_range_name = var.svc_ip_range_name
  }

  # Private Cluster Configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Control plane endpoint accessible for kubectl
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Layer 6: CMEK Envelope Encryption for etcd Secrets
  database_encryption {
    state    = "ENCRYPTED"
    key_name = var.gke_etcd_key_id
  }

  # Layer 5: Workload Identity Federation Activation
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Hardened Control Plane Maintenance Policy
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Security & Compliance Features
  release_channel {
    channel = "REGULAR"
  }

  lifecycle {
    ignore_changes = [
      initial_node_count
    ]
  }
}

# ------------------------------------------------------------------------------
# 3. Node Pool 1: Standard System Workloads (Shielded Nodes)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "system_nodes" {
  name       = "system-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
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
    machine_type    = "e2-standard-4"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_nodes_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Layer 6: CMEK Encrypted Boot Disks
    boot_disk_kms_key = var.gke_disk_key_id
    disk_size_gb      = 50
    disk_type         = "pd-standard"

    # Layer 3: Shielded Node Hardening
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Security Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      "workload-tier" = "system"
    }
  }
}

# ------------------------------------------------------------------------------
# 4. Node Pool 2: gVisor Sandboxed Workloads (Kernel Isolation)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "gvisor_nodes" {
  provider   = google-beta
  name       = "gvisor-sandbox-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
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
    machine_type    = "e2-standard-4"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_nodes_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Layer 3: gVisor User-Space Sandbox Runtime
    sandbox_config {
      sandbox_type = "gvisor"
    }

    # Layer 6: CMEK Encrypted Boot Disks
    boot_disk_kms_key = var.gke_disk_key_id
    disk_size_gb      = 50
    disk_type         = "pd-standard"

    # Layer 3: Shielded Node Hardening
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Taint to force untrusted/isolated workloads to explicitly tolerate gVisor
    taint {
      key    = "sandbox.gke.io/runtime"
      value  = "gvisor"
      effect = "NO_SCHEDULE"
    }

    labels = {
      "sandbox.gke.io/runtime" = "gvisor"
      "workload-tier"          = "untrusted-unisolated"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}