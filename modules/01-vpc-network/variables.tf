variable "project_id" {
  type        = string
  description = "The GCP Project ID where the network resources will be created."
}

variable "region" {
  type        = string
  description = "The primary GCP region for subnets and Cloud NAT."
  default     = "us-central1"
}

variable "network_name" {
  type        = string
  description = "Name of the custom VPC network."
  default     = "gke-did-vpc"
}

variable "subnet_name" {
  type        = string
  description = "Name of the primary workload subnet."
  default     = "gke-did-subnet-us-central1"
}

variable "subnet_cidr" {
  type        = string
  description = "Primary IP CIDR range for GKE Nodes and host compute."
  default     = "10.10.0.0/20"
}

variable "pod_ip_range_name" {
  type        = string
  description = "Name of the secondary range for GKE Pod alias IPs."
  default     = "gke-pods"
}

variable "pod_cidr" {
  type        = string
  description = "Secondary CIDR range reserved for GKE Pods."
  default     = "10.20.0.0/16"
}

variable "svc_ip_range_name" {
  type        = string
  description = "Name of the secondary range for GKE Service cluster IPs."
  default     = "gke-services"
}

variable "svc_cidr" {
  type        = string
  description = "Secondary CIDR range reserved for GKE Services."
  default     = "10.30.0.0/20"
}