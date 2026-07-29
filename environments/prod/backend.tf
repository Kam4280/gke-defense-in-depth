terraform {
  backend "gcs" {
    bucket = "kam-dev-test-tfstate-gke-did"
    prefix = "terraform/state/prod"
  }
}