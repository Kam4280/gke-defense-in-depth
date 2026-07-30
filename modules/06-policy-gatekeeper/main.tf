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
# 1. Enable Policy Controller API
# ------------------------------------------------------------------------------
resource "google_project_service" "policycontroller_api" {
  project            = var.project_id
  service            = "anthospolicycontroller.googleapis.com"
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 2. Enable Fleet Policy Controller Feature
# ------------------------------------------------------------------------------
resource "google_gke_hub_feature" "policycontroller" {
  project  = var.project_id
  name     = "policycontroller"
  location = "global"

  depends_on = [
    google_project_service.policycontroller_api
  ]
}

# ------------------------------------------------------------------------------
# 3. Configure Policy Controller Membership (Managed OPA Gatekeeper)
# ------------------------------------------------------------------------------
resource "google_gke_hub_feature_membership" "policycontroller_membership" {
  project    = var.project_id
  location   = "global"
  feature    = google_gke_hub_feature.policycontroller.name
  membership = var.membership_id

  policycontroller {
    policy_controller_hub_config {
      install_spec               = "INSTALL_SPEC_ENABLED"
      log_denies_enabled         = true
      referential_rules_enabled  = true
      constraint_violation_limit = 50

      policy_content {
        template_library {
          installation = "ALL"
        }
      }
    }
  }

  depends_on = [
    google_gke_hub_feature.policycontroller
  ]
}