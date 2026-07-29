output "cluster_name" {
  value       = google_container_cluster.primary.name
  description = "The name of the provisioned GKE cluster."
}

output "cluster_endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "The IP address of the GKE Kubernetes API master control plane."
}

output "ca_certificate" {
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  description = "Base64 encoded public certificate for cluster authentication."
  sensitive   = true
}

output "node_service_account_email" {
  value       = google_service_account.gke_nodes_sa.email
  description = "Email of the dynamic least-privilege node service account."
}