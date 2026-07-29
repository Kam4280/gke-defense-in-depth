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
# 1. Project Information Lookup
# ------------------------------------------------------------------------------
data "google_project" "project" {
  project_id = var.project_id
}

# ------------------------------------------------------------------------------
# 2. Service Identity Provisioning (Ensures Service Agents Exist)
# ------------------------------------------------------------------------------
resource "google_project_service_identity" "gke_sa" {
  project = var.project_id
  service = "container.googleapis.com"
}

resource "google_project_service_identity" "compute_sa" {
  project = var.project_id
  service = "compute.googleapis.com"
}

# ------------------------------------------------------------------------------
# 3. Cloud KMS KeyRing
# ------------------------------------------------------------------------------
resource "google_kms_key_ring" "keyring" {
  name     = var.keyring_name
  project  = var.project_id
  location = var.region
}

# ------------------------------------------------------------------------------
# 4. CryptoKey for GKE etcd Secret Envelope Encryption
# ------------------------------------------------------------------------------
resource "google_kms_crypto_key" "gke_etcd_key" {
  name            = "gke-etcd-encryption-key"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = var.rotation_period

  purpose = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = false
  }
}

# ------------------------------------------------------------------------------
# 5. CryptoKey for Persistent Node Disks / Stateful Volumes
# ------------------------------------------------------------------------------
resource "google_kms_crypto_key" "gke_disk_key" {
  name            = "gke-disk-encryption-key"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = var.rotation_period

  purpose = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = false
  }
}

# ------------------------------------------------------------------------------
# 6. IAM Grants: GKE Engine Service Agent (for etcd CMEK)
# ------------------------------------------------------------------------------
resource "google_kms_crypto_key_iam_member" "gke_etcd_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.gke_etcd_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.gke_sa.email}"
}

# ------------------------------------------------------------------------------
# 7. IAM Grants: Compute Engine Service Agent (for Node Disk CMEK)
# ------------------------------------------------------------------------------
resource "google_kms_crypto_key_iam_member" "gke_disk_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.gke_disk_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.compute_sa.email}"
}