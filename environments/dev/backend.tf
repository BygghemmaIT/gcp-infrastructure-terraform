terraform {
  backend "gcs" {
    bucket = "bh-cicd-tfstate"
    prefix = "env/dev"
  }
}
