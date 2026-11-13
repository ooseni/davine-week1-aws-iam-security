locals {
  prefix = "davine-wk1"

  # The policy documents live in ../policies as plain IAM JSON, so they can be read on GitHub
  # and checked by IAM Access Analyzer exactly as AWS receives them.
  policies = "${path.module}/../policies"
}

# Account password rules for every IAM user: CIS AWS Foundations asks for 14+ characters
# and no reuse of the last 24 passwords.
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

# Customer managed policies, attached to the group rather than to people.
resource "aws_iam_policy" "developer_access" {
  name        = "${local.prefix}-developer-access"
  description = "Read EC2 and metrics, start and stop team instances, use project buckets and logs."
  policy      = file("${local.policies}/developer-access.json")
}

resource "aws_iam_policy" "require_mfa" {
  name        = "${local.prefix}-require-mfa"
  description = "Deny everything except setting up MFA and changing password until the user signs in with MFA."
  policy      = file("${local.policies}/require-mfa.json")
}

# MFA is enforced by the attached require-mfa managed policy below. Trivy's AWS-0123 only inspects
# inline group policies, so it is ignored here; the live simulation in scripts/verify_live.sh proves it.
#trivy:ignore:AWS-0123
resource "aws_iam_group" "developers" {
  name = "${local.prefix}-developers"
}

resource "aws_iam_group_policy_attachment" "developers" {
  for_each = {
    developer_access = aws_iam_policy.developer_access.arn
    require_mfa      = aws_iam_policy.require_mfa.arn
  }

  group      = aws_iam_group.developers.name
  policy_arn = each.value
}

# The new employee. No access keys and no console password are created here: the
# administrator sets a one-time password in the console, and the require-MFA policy keeps the
# account locked down until the developer registers an MFA device.
resource "aws_iam_user" "developer" {
  #checkov:skip=CKV_AWS_273:The brief asks for an IAM user. In production people sign in through IAM Identity Center instead (README, Lab vs production).
  for_each = toset(var.developer_user_names)

  name          = "${local.prefix}-${each.key}"
  force_destroy = true # lets terraform destroy remove an MFA device the developer added
}

resource "aws_iam_user_group_membership" "developer" {
  for_each = aws_iam_user.developer

  user   = each.value.name
  groups = [aws_iam_group.developers.name]
}

# A role for an AWS service: an application on EC2 reads its config from S3 and is reached
# through Systems Manager Session Manager, with temporary credentials and no keys on disk.
resource "aws_iam_role" "ec2_app" {
  name                 = "${local.prefix}-ec2-app"
  description          = "EC2 application role: read app config from S3 and allow Systems Manager access."
  assume_role_policy   = file("${local.policies}/ec2-trust.json")
  max_session_duration = 3600
}

resource "aws_iam_policy" "ec2_app_config_read" {
  name        = "${local.prefix}-ec2-app-config-read"
  description = "Read-only access to the application's config bucket."
  policy      = file("${local.policies}/ec2-app-config-read.json")
}

resource "aws_iam_role_policy_attachment" "ec2_app" {
  for_each = {
    app_config_read = aws_iam_policy.ec2_app_config_read.arn
    ssm_core        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  role       = aws_iam_role.ec2_app.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2_app" {
  name = "${local.prefix}-ec2-app"
  role = aws_iam_role.ec2_app.name
}
