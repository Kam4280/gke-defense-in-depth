variable "project_id" {
  type        = string
  description = "The GCP Project ID where KMS resources will be created."
}

variable "region" {
  type        = string
  description = "GCP Region for the KMS KeyRing."
  default     = "us-central1"
}

variable "keyring_name" {
  type        = string
  description = "Name of the KMS KeyRing."
  default     = "gke-did-keyring"
}

variable "rotation_period" {
  type        = string
  description = "Automated rotation period for KMS keys in seconds (default: 90 days)."
  default     = "7776000s" # 90 days in seconds
}