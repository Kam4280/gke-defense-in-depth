variable "project_id" {
  type        = string
  description = "The target GCP Project ID."
}

variable "namespace" {
  type        = string
  description = "The target Kubernetes namespace for MLOps workloads."
  default     = "mlops-inference"
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
}