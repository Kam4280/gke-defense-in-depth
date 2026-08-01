terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Dedicated MLOps Workload GCP Service Account
# ------------------------------------------------------------------------------
resource "google_service_account" "mlops_sa" {
  account_id   = "mlops-inference-sa"
  display_name = "Hardened MLOps Workload Service Account"
  project      = var.project_id
}

# ------------------------------------------------------------------------------
# 2. Hardened Kubernetes Namespace
# ------------------------------------------------------------------------------
resource "kubernetes_namespace" "mlops" {
  metadata {
    name = var.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "istio-injection"                    = "disabled"
    }
  }
}

# ------------------------------------------------------------------------------
# 3. Workload Identity Binding (KSA ◄──► GSA)
# ------------------------------------------------------------------------------
resource "kubernetes_service_account" "mlops_ksa" {
  metadata {
    name      = "mlops-inference-ksa"
    namespace = kubernetes_namespace.mlops.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.mlops_sa.email
    }
  }
}

resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.mlops_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace.mlops.metadata[0].name}/${kubernetes_service_account.mlops_ksa.metadata[0].name}]"
}

# ------------------------------------------------------------------------------
# 4. Hardened gVisor Sandboxed MLOps Model Server Deployment
# ------------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "mlops_inference" {
  metadata {
    name      = "mlops-model-server"
    namespace = kubernetes_namespace.mlops.metadata[0].name
    labels = {
      app  = "mlops-model-server"
      tier = "inference"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "mlops-model-server"
      }
    }

    template {
      metadata {
        labels = {
          app  = "mlops-model-server"
          tier = "inference"
        }
        annotations = {
          "sidecar.istio.io/inject" = "false"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.mlops_ksa.metadata[0].name

        # Enforce gVisor MicroVM Sandbox Runtime
        runtime_class_name = "gvisor"

        # Direct placement onto gVisor Node Pool
        node_selector = {
          "sandbox.gke.io/runtime" = "gvisor"
        }

        toleration {
          key      = "sandbox.gke.io/runtime"
          operator = "Equal"
          value    = "gvisor"
          effect   = "NoSchedule"
        }

        # Pod-level Security Context
        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          fs_group        = 10001

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "model-server"
          image = "us-docker.pkg.dev/google-samples/containers/gke/hello-app:2.0"

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          # Container-level Security Context
          security_context {
            run_as_non_root            = true
            run_as_user                = 10001
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }

            seccomp_profile {
              type = "RuntimeDefault"
            }
          }

          port {
            container_port = 8080
            name           = "http"
          }
        }
      }
    }
  }

  depends_on = [
    google_service_account_iam_member.workload_identity_user
  ]
}

# ------------------------------------------------------------------------------
# 5. Internal ClusterIP Service
# ------------------------------------------------------------------------------
resource "kubernetes_service_v1" "mlops_service" {
  metadata {
    name      = "mlops-model-server-svc"
    namespace = kubernetes_namespace.mlops.metadata[0].name
  }

  spec {
    selector = {
      app = "mlops-model-server"
    }

    port {
      port        = 80
      target_port = 8080
      name        = "http"
    }

    type = "ClusterIP"
  }
}