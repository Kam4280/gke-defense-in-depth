output "policycontroller_feature_state" {
  value       = google_gke_hub_feature.policycontroller.name
  description = "The Fleet Policy Controller feature name."
}