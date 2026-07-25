variable "project_id" {
  type        = string
  description = "Target GCP Project ID where infrastructure will be deployed."
}

variable "region" {
  type        = string
  description = "Default GCP Region for bootstrap resources."
  default     = "us-central1"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique name for the Terraform remote state GCS bucket."
}

variable "github_org" {
  type        = string
  description = "GitHub Organization or individual Username owning the repository."
}

variable "github_repo" {
  type        = string
  description = "GitHub Repository name."
}