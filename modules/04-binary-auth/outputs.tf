output "attestor_name" {
  value       = google_binary_authorization_attestor.attestor.name
  description = "The name of the provisioned Binary Authorization attestor."
}

output "attestor_note_id" {
  value       = google_container_analysis_note.attestor_note.id
  description = "The Container Analysis note ID used by the attestor."
}