# Credentials come from the environment (AWS_PROFILE with IAM Identity Center), never from code.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "davine-week1-aws-iam-security"
      Programme = "Davine Technologies internship"
      ManagedBy = "terraform"
    }
  }
}
