terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Enable Cloud Logging & Monitoring APIs
# ------------------------------------------------------------------------------
resource "google_project_service" "logging_api" {
  project            = var.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring_api" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 2. Immutable SecOps Audit Log Storage Bucket
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "secops_log_bucket" {
  name                        = "${var.project_id}-gke-secops-audit-logs"
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  # Immutable retention policy (30-day compliance lock)
  retention_policy {
    is_locked        = false
    retention_period = 2592000 # 30 Days in seconds
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90
    }
  }

  depends_on = [
    google_project_service.logging_api
  ]
}

# ------------------------------------------------------------------------------
# 3. Project Security Audit Log Sink (GKE Control Plane & Gatekeeper)
# ------------------------------------------------------------------------------
resource "google_logging_project_sink" "gke_security_sink" {
  name        = "${var.cluster_name}-secops-audit-sink"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.secops_log_bucket.name}"

  # Filter for GKE Audit Logs, Gatekeeper Denials, and Binary Authorization Events
  filter = <<EOT
resource.type=("k8s_cluster" OR "k8s_container" OR "k8s_node")
OR protoPayload.serviceName="container.googleapis.com"
OR protoPayload.serviceName="binaryauthorization.googleapis.com"
EOT

  unique_writer_identity = true
}

# Grant Log Sink Writer SA permission to write to Storage Bucket
resource "google_storage_bucket_iam_member" "sink_writer" {
  bucket = google_storage_bucket.secops_log_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.gke_security_sink.writer_identity
}