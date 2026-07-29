variable "project_id" {
  type        = string
  description = "The target GCP Project ID."
}

variable "attestor_name" {
  type        = string
  description = "The name of the Binary Authorization Attestor."
  default     = "prod-build-attestor"
}