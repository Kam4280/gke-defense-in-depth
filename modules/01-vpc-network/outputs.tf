output "network_id" {
  value       = google_compute_network.vpc.id
  description = "The fully qualified URI of the VPC network."
}

output "network_name" {
  value       = google_compute_network.vpc.name
  description = "The name of the VPC network."
}

output "subnet_id" {
  value       = google_compute_subnetwork.subnet.id
  description = "The fully qualified URI of the workload subnet."
}

output "subnet_name" {
  value       = google_compute_subnetwork.subnet.name
  description = "The name of the workload subnet."
}

output "pod_ip_range_name" {
  value       = var.pod_ip_range_name
  description = "The secondary range identifier for GKE Pods."
}

output "svc_ip_range_name" {
  value       = var.svc_ip_range_name
  description = "The secondary range identifier for GKE Services."
}