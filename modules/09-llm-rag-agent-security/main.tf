# ------------------------------------------------------------------------------
# Phase 2: MLOps SecOps Namespace & Workload Identity Setup
# Architectural Layer: Workload Execution Layer / MLOps Security Sandbox
# ------------------------------------------------------------------------------

variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

# 1. Dedicated Namespace with strict Pod Security Standards (PSS)
resource "kubernetes_namespace_v1" "mlops_secops" {
  metadata {
    name = "mlops-secops"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "istio-injection"                    = "disabled" # Bypassed in favor of Cilium eBPF network isolation
    }
  }
}

# 2. Google Service Account for Workload Identity
resource "google_service_account" "rag_agent_sa" {
  account_id   = "rag-agent-sa"
  display_name = "RAG Agent Workload Identity SA"
  project      = var.project_id
}

# 3. Kubernetes Service Account mapped to GCP SA
resource "kubernetes_service_account_v1" "rag_agent_k8s_sa" {
  metadata {
    name      = "rag-agent-k8s-sa"
    namespace = kubernetes_namespace_v1.mlops_secops.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.rag_agent_sa.email
    }
  }
}

# 4. Workload Identity IAM Binding (Allows K8s SA to impersonate GCP SA)
resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.rag_agent_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[mlops-secops/rag-agent-k8s-sa]"
}

# 5. Additive Least-Privilege IAM Binding (Storage Object Viewer for RAG Bucket Access ONLY)
resource "google_project_iam_member" "rag_agent_storage_reader" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.rag_agent_sa.email}"
}

# Module Outputs
output "mlops_secops_namespace" {
  value       = kubernetes_namespace_v1.mlops_secops.metadata[0].name
  description = "MLOps SecOps Namespace Name"
}

output "rag_agent_sa_email" {
  value       = google_service_account.rag_agent_sa.email
  description = "RAG Agent GCP Service Account Email"
}