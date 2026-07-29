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
# 1. Enable Required Container Security APIs
# ------------------------------------------------------------------------------
resource "google_project_service" "binauthz_api" {
  project            = var.project_id
  service            = "binaryauthorization.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "containeranalysis_api" {
  project            = var.project_id
  service            = "containeranalysis.googleapis.com"
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 2. Container Analysis Metadata Note (Attestor Anchor)
# ------------------------------------------------------------------------------
resource "google_container_analysis_note" "attestor_note" {
  name    = "${var.attestor_name}-note"
  project = var.project_id

  attestation_authority {
    hint {
      human_readable_name = "Production Release Build Attestor Note"
    }
  }

  depends_on = [
    google_project_service.containeranalysis_api
  ]
}

# ------------------------------------------------------------------------------
# 3. Binary Authorization Attestor
# ------------------------------------------------------------------------------
resource "google_binary_authorization_attestor" "attestor" {
  name    = var.attestor_name
  project = var.project_id

  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor_note.name
  }

  depends_on = [
    google_project_service.binauthz_api
  ]
}

# ------------------------------------------------------------------------------
# 4. Binary Authorization Policy (Supply Chain Gatekeeper)
# ------------------------------------------------------------------------------
resource "google_binary_authorization_policy" "policy" {
  project = var.project_id

  # Automatically allow Google-signed system images (Cilium, DNS, gVisor helper pods)
  global_policy_evaluation_mode = "ENABLE"

  default_admission_rule {
    evaluation_mode  = "ALWAYS_ALLOW" # Swapped to REQUIRE_ATTESTATION in strict enforcement pipelines
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  }

  depends_on = [
    google_project_service.binauthz_api
  ]
}
