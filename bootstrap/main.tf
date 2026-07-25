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
# 1. GCS Bucket for Remote Terraform State
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "tf_state" {
  name                        = var.state_bucket_name
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 5
    }
  }
}

# ------------------------------------------------------------------------------
# 2. CI/CD Service Account for GitHub Actions
# ------------------------------------------------------------------------------
resource "google_service_account" "github_actions_sa" {
  account_id   = "gh-actions-gke-did"
  display_name = "GitHub Actions CI/CD SA for GKE Defense-in-Depth"
  description  = "Keyless automation service account triggered via WIF"
}

# Additive (Non-destructive) IAM Bindings
resource "google_project_iam_member" "sa_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

resource "google_project_iam_member" "sa_security_admin" {
  project = var.project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

resource "google_project_iam_member" "sa_container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

# ------------------------------------------------------------------------------
# 3. Workload Identity Federation (WIF) Pool & OIDC Provider
# ------------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions WIF Pool"
  description               = "Identity pool for keyless GitHub Actions deployment"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC Provider"

  # Enforce attribute condition to satisfy GCP IAM security policy
  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Bind Service Account Token Creator specifically to our GitHub Repository
resource "google_service_account_iam_member" "wif_sa_binding" {
  service_account_id = google_service_account.github_actions_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# ------------------------------------------------------------------------------
# Outputs (Required for GitHub Secrets)
# ------------------------------------------------------------------------------
output "tf_state_bucket" {
  value       = google_storage_bucket.tf_state.name
  description = "Name of the remote state GCS bucket"
}

output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github_provider.name
  description = "Full resource name of the WIF Provider for GitHub Actions"
}

output "service_account_email" {
  value       = google_service_account.github_actions_sa.email
  description = "Service account email assumed by GitHub Actions"
}