provider "aws" {
    version = "~> 1.57"
}
terraform {
  backend "s3" {
  }
}