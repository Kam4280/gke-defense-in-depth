variable "project_id" {
  type        = string
  description = "The target GCP Project ID."
}

variable "location" {
  type        = string
  description = "The GCP Region of the cluster."
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
}

variable "cluster_id" {
  type        = string
  description = "The fully qualified resource ID of the GKE cluster."
}