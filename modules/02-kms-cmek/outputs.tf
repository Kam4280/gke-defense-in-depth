output "keyring_id" {
  value       = google_kms_key_ring.keyring.id
  description = "The fully qualified resource ID of the KMS KeyRing."
}

output "gke_etcd_key_id" {
  value       = google_kms_crypto_key.gke_etcd_key.id
  description = "The fully qualified resource ID of the GKE etcd database encryption key."
}

output "gke_disk_key_id" {
  value       = google_kms_crypto_key.gke_disk_key.id
  description = "The fully qualified resource ID of the Persistent Disk encryption key."
}
