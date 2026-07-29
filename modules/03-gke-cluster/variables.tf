variable "project_id" {
  type        = string
  description = "The target GCP Project ID."
}

variable "region" {
  type        = string
  description = "The GCP Region for the cluster."
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
  default     = "prod-gke-did-cluster"
}

variable "network_id" {
  type        = string
  description = "VPC network ID created by Tier 1."
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID created by Tier 1."
}

variable "pod_ip_range_name" {
  type        = string
  description = "Secondary subnet range name for Pod alias IPs."
}

variable "svc_ip_range_name" {
  type        = string
  description = "Secondary subnet range name for Service IPs."
}

variable "gke_etcd_key_id" {
  type        = string
  description = "KMS Key URI for etcd secret envelope encryption."
}

variable "gke_disk_key_id" {
  type        = string
  description = "KMS Key URI for Persistent Disk volume encryption."
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "The /28 CIDR block reserved for the managed GKE Control Plane private endpoint."
  default     = "172.16.0.0/28"
}