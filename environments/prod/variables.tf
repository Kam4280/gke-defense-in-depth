variable "project_id" {
  type        = string
  description = "The target GCP Project ID for production infrastructure."
}

variable "region" {
  type        = string
  description = "The primary GCP region for resources."
  default     = "us-central1"
}