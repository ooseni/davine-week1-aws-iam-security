# Offline tests: a mocked AWS provider, so they run in CI with no account and no credentials.
# Each run plans the configuration and checks a security property of what would be created.

mock_provider "aws" {}

run "developers_group_gets_exactly_the_two_customer_policies" {
  command = plan

  assert {
    condition     = toset(keys(aws_iam_group_policy_attachment.developers)) == toset(["developer_access", "require_mfa"])
    error_message = "The Developers group must carry the developer-access and require-MFA policies, and nothing else."
  }
}

run "every_developer_joins_the_developers_group" {
  command = plan

  variables {
    developer_user_names = ["developer-01", "developer-02"]
  }

  assert {
    condition     = length(aws_iam_user_group_membership.developer) == 2 && alltrue([for m in aws_iam_user_group_membership.developer : m.groups == toset(["davine-wk1-developers"])])
    error_message = "Each developer must be a member of davine-wk1-developers."
  }

  assert {
    condition     = sort([for u in aws_iam_user.developer : u.name]) == tolist(["davine-wk1-developer-01", "davine-wk1-developer-02"])
    error_message = "User names must be davine-wk1-<name>."
  }
}

run "require_mfa_denies_everything_but_mfa_setup_without_mfa" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(aws_iam_policy.require_mfa.policy).Statement : s
      if s.Effect == "Deny"
      && try(s.Resource, "") == "*"
      && try(s.Condition.BoolIfExists["aws:MultiFactorAuthPresent"], "") == "false"
      && length(try(s.NotAction, [])) > 0
    ]) == 1
    error_message = "require-mfa must have one Deny on all resources, conditioned on aws:MultiFactorAuthPresent being false."
  }

  assert {
    condition = alltrue([
      for a in flatten([for s in jsondecode(aws_iam_policy.require_mfa.policy).Statement : try(s.NotAction, []) if s.Effect == "Deny"]) :
      startswith(a, "iam:") || a == "sts:GetSessionToken"
    ])
    error_message = "Only IAM self-service and sts:GetSessionToken may be exempt from the MFA deny."
  }
}

run "developer_policy_never_grants_iam_or_wildcard_actions" {
  command = plan

  assert {
    condition = alltrue([
      for a in flatten([for s in jsondecode(aws_iam_policy.developer_access.policy).Statement : try(flatten([s.Action]), [])]) :
      !startswith(a, "iam:") && !startswith(a, "sts:") && a != "*" && !endswith(a, ":*")
    ])
    error_message = "developer-access must not grant IAM, STS, * or service:* actions."
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_policy.developer_access.policy).Statement : s.Effect == "Allow"])
    error_message = "developer-access holds only Allow statements; the deny lives in require-mfa."
  }
}

run "ec2_role_is_trusted_by_ec2_only" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role.ec2_app.assume_role_policy).Statement) == 1
    error_message = "The role trust policy must have exactly one statement."
  }

  assert {
    condition     = jsondecode(aws_iam_role.ec2_app.assume_role_policy).Statement[0].Principal == { Service = "ec2.amazonaws.com" }
    error_message = "Only the EC2 service may assume the application role."
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.ec2_app)) == toset(["app_config_read", "ssm_core"])
    error_message = "The role gets read access to its config bucket and the SSM core policy, nothing more."
  }

  assert {
    condition     = aws_iam_instance_profile.ec2_app.role == "davine-wk1-ec2-app"
    error_message = "The instance profile must wrap the application role."
  }
}

run "password_policy_meets_cis_benchmark" {
  command = plan

  assert {
    condition     = aws_iam_account_password_policy.this.minimum_password_length >= 14 && aws_iam_account_password_policy.this.password_reuse_prevention >= 24
    error_message = "Passwords need 14+ characters and no reuse of the last 24 (CIS AWS Foundations)."
  }
}

run "no_budget_without_an_alert_email" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.monthly) == 0
    error_message = "No budget may be created when budget_alert_email is null."
  }
}

run "budget_alerts_at_80_percent_actual_and_100_percent_forecast" {
  command = plan

  variables {
    budget_alert_email = "alerts@example.com"
    monthly_budget_usd = 5
  }

  assert {
    condition     = length(aws_budgets_budget.monthly) == 1 && aws_budgets_budget.monthly[0].limit_amount == "5"
    error_message = "One 5 USD budget must be created when an email is given."
  }

  assert {
    condition     = toset([for n in aws_budgets_budget.monthly[0].notification : "${n.notification_type}:${n.threshold}"]) == toset(["ACTUAL:80", "FORECASTED:100"])
    error_message = "Alerts must fire at 80% of actual and 100% of forecast spend."
  }
}

run "rejects_an_invalid_alert_email" {
  command = plan

  variables {
    budget_alert_email = "not-an-email"
  }

  expect_failures = [var.budget_alert_email]
}

run "rejects_an_invalid_user_name" {
  command = plan

  variables {
    developer_user_names = ["Bad Name!"]
  }

  expect_failures = [var.developer_user_names]
}
