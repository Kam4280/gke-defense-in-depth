# ------------------------------------------------------------------------------
# Tier 1 Network Outputs
# ------------------------------------------------------------------------------
output "network_id" {
  value       = module.vpc_network.network_id
  description = "The fully qualified URI of the production VPC network."
}

output "subnet_id" {
  value       = module.vpc_network.subnet_id
  description = "The fully qualified URI of the production subnet."
}

output "pod_ip_range_name" {
  value       = module.vpc_network.pod_ip_range_name
  description = "Secondary range identifier for Pod alias IPs."
}

output "svc_ip_range_name" {
  value       = module.vpc_network.svc_ip_range_name
  description = "Secondary range identifier for Service IPs."
}

# ------------------------------------------------------------------------------
# Tier 1 KMS Outputs
# ------------------------------------------------------------------------------
output "gke_etcd_key_id" {
  value       = module.kms_cmek.gke_etcd_key_id
  description = "KMS Key URI for GKE etcd secret envelope encryption."
}

output "gke_disk_key_id" {
  value       = module.kms_cmek.gke_disk_key_id
  description = "KMS Key URI for GKE Persistent Disk volume encryption."
}

# ------------------------------------------------------------------------------
# Tier 2 GKE Cluster Outputs
# ------------------------------------------------------------------------------
output "cluster_name" {
  value       = module.gke_cluster.cluster_name
  description = "GKE Cluster Name."
}

output "cluster_endpoint" {
  value       = module.gke_cluster.cluster_endpoint
  description = "GKE Master Control Plane Endpoint IP."
}

output "node_service_account" {
  value       = module.gke_cluster.node_service_account_email
  description = "Dedicated Least-Privilege Node Service Account."
}