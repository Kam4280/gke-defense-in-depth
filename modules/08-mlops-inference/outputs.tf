output "namespace" {
  value       = kubernetes_namespace.mlops.metadata[0].name
  description = "The Kubernetes namespace hosting the sandboxed MLOps inference workload."
}

output "service_account_email" {
  value       = google_service_account.mlops_sa.email
  description = "The GCP Service Account email bound via Workload Identity."
}

output "service_name" {
  value       = kubernetes_service_v1.mlops_service.metadata[0].name
  description = "The ClusterIP service name for the inference endpoint."
}