variable "project_id" {
  type        = string
  description = "Target GCP Project ID."
  default     = "kam-dev-test"
}

variable "region" {
  type        = string
  description = "Target GCP Region."
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "Name for the production GKE cluster."
  default     = "prod-gke-did-cluster"
}