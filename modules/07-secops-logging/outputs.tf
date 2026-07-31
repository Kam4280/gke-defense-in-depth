output "secops_bucket_name" {
  value       = google_storage_bucket.secops_log_bucket.name
  description = "The name of the SecOps compliance log storage bucket."
}

output "log_sink_writer_identity" {
  value       = google_logging_project_sink.gke_security_sink.writer_identity
  description = "The Service Account identity used by the log sink."
}