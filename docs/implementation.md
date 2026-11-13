# Implementation | how the account was set up, step by step

## Summary

I secured an AWS account for a new developer: root MFA confirmed, a CIS-strength password policy, a Developers group with two customer managed policies, one IAM user in that group with no access keys, and an IAM role for EC2 that reads one S3 bucket and lets Systems Manager manage the instance. All of it is Terraform (13 resources), applied on 13 November 2026 through an IAM Identity Center session, checked with 19 policy simulations and IAM Access Analyzer, captured in redacted screenshots, and destroyed at 21:52 the same evening.

## Before you start

- An AWS account whose root user has MFA. Root MFA cannot be set through an API; it is a console step for the root user (Security credentials, then Assign MFA device).
- An administrator session from IAM Identity Center: `aws sso login --profile <profile>`, then `export AWS_PROFILE=<profile>`. No long-term access keys are needed anywhere.
- Terraform 1.10 or newer (I used 1.17.1) and AWS CLI v2 (2.39.7).

## Steps

### 1. Confirm the starting state

```bash
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled'   # 1 = root MFA is on
aws iam get-account-password-policy                                   # NoSuchEntity = no policy yet
```

My account returned `1` and `NoSuchEntity`. That matters for step 6: because there was no password policy before, `terraform destroy` returns the account to exactly its previous state.

### 2. Plan

```bash
cd terraform
terraform init
terraform plan -out=wk1.tfplan        # 13 to add, 0 to change, 0 to destroy
```

### 3. Apply

```bash
terraform apply wk1.tfplan
```

| Resource | Console equivalent | Why |
|---|---|---|
| `aws_iam_account_password_policy` | IAM, Account settings, Password policy | 14+ characters, all character types, 90-day rotation, no reuse of the last 24 |
| `aws_iam_policy` x3 | IAM, Policies, Create policy (JSON tab) | `require-mfa`, `developer-access`, `ec2-app-config-read`, loaded from [`policies/`](../policies) |
| `aws_iam_group` + 2 attachments | IAM, User groups, Create group | Permissions live on the group, never on a person |
| `aws_iam_user` + group membership | IAM, Users, Create user, Add to group | The new developer: no access keys, no password from code |
| `aws_iam_role` + 2 attachments | IAM, Roles, Create role, AWS service, EC2 | Trusted only by `ec2.amazonaws.com`; reads the config bucket; `AmazonSSMManagedInstanceCore` |
| `aws_iam_instance_profile` | created with the role in the console | How an EC2 instance carries the role |

A budget (`aws_budgets_budget`, alerts at 80% of actual and 100% of forecast spend) is created only when `budget_alert_email` is set. My account already had a US$1 and a US$40 budget, so I left it unset rather than add a third.

### 4. Give the developer a first password (console, by hand)

IAM, Users, `davine-wk1-developer-01`, Security credentials, Enable console access, with "User must create a new password at next sign-in". This is deliberately not in Terraform, because a password set in code ends up in the state file. Until the developer registers an MFA device, `require-mfa` allows only changing that password and setting up MFA.

In my run I did not issue a password: nobody was going to sign in as the lab user, and the policy simulations in step 5 test exactly this first-sign-in behaviour without creating a credential that could leak.

### 5. Verify

```bash
scripts/verify_live.sh      # 23 checks: 19 policy simulations, 4 Access Analyzer validations
```

On 13 November 2026 at 20:55 WAT: **23 passed, 0 failed**. The transcript is in [`evidence/live-run-2026-11-13.txt`](evidence/live-run-2026-11-13.txt), and the console screenshots are in [`screenshots/`](../screenshots).

### 6. Clean up

```bash
terraform destroy
```

IAM is free, but a lab identity left behind is an unused door. The root MFA setting and the two existing budgets are not managed by this code, so they are untouched.
