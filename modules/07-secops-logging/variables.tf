variable "project_id" {
  type        = string
  description = "The target GCP Project ID."
}

variable "region" {
  type        = string
  description = "The target GCP Region for log storage."
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster being monitored."
}