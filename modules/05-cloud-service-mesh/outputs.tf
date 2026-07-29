output "membership_id" {
  value       = google_gke_hub_membership.membership.membership_id
  description = "The GKE Hub Fleet Membership ID for the cluster."
}

output "servicemesh_feature_state" {
  value       = google_gke_hub_feature.servicemesh.name
  description = "The Fleet Service Mesh feature state."
}