terraform {
  required_version = "~> 1.4.6"
  required_providers {
    aws = "~> 4.67.0"
  }
  backend "s3" {
    bucket         = "521776594233-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
