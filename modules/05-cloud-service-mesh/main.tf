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
# 1. Enable Service Mesh & GKE Hub Fleet APIs
# ------------------------------------------------------------------------------
resource "google_project_service" "gkehub_api" {
  project            = var.project_id
  service            = "gkehub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "mesh_api" {
  project            = var.project_id
  service            = "mesh.googleapis.com"
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 2. Register GKE Cluster to Google Cloud Fleet (GKE Hub)
# ------------------------------------------------------------------------------
resource "google_gke_hub_membership" "membership" {
  project       = var.project_id
  membership_id = "${var.cluster_name}-fleet-member"

  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${var.cluster_id}"
    }
  }

  depends_on = [
    google_project_service.gkehub_api
  ]
}

# ------------------------------------------------------------------------------
# 3. Enable Service Mesh Fleet Feature
# ------------------------------------------------------------------------------
resource "google_gke_hub_feature" "servicemesh" {
  project  = var.project_id
  name     = "servicemesh"
  location = "global"

  depends_on = [
    google_project_service.mesh_api
  ]
}

# ------------------------------------------------------------------------------
# 4. Activate Automatic Managed Service Mesh Management
# ------------------------------------------------------------------------------
resource "google_gke_hub_feature_membership" "servicemesh_membership" {
  project    = var.project_id
  location   = "global"
  feature    = google_gke_hub_feature.servicemesh.name
  membership = google_gke_hub_membership.membership.membership_id

  mesh {
    management = "MANAGEMENT_AUTOMATIC"
  }
}