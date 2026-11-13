# Testing

Two layers: checks that run on every push with no AWS account, and a live run against a real account.

## On every push (GitHub Actions, no AWS credentials)

| Check | Tool and version | Result on 13 November 2026 |
|---|---|---|
| Policy files are valid JSON | `jq` | 4 of 4 valid |
| No access keys or console passwords in code | `grep` guard | none found |
| Format, validate and unit tests | Terraform 1.17.1, AWS provider 6.73.0, `terraform test` with a mocked provider | 10 of 10 tests pass |
| Lint | TFLint 0.66.0, recommended preset | 0 issues |
| Security scan | Checkov 3.4.3 | 25 passed, 0 failed, 1 skipped with a reason |
| Security scan | Trivy 0.76.2 | 0 findings, 1 ignored with a reason |
| Secret scan of the whole history | gitleaks 8.30.1 | 0 leaks |

### The 10 Terraform tests

Each one plans the configuration against a mocked AWS provider and asserts one security property: the group carries exactly the two customer policies; every developer joins the group; `require-mfa` has one Deny on `*` conditioned on `aws:MultiFactorAuthPresent` being false, exempting only IAM self-service and `sts:GetSessionToken`; `developer-access` grants no `iam:`, `sts:`, `*` or `service:*` action and holds only Allow statements; the role is trusted by EC2 only and carries exactly two policies; the password policy meets the CIS benchmark; no budget exists without an email; the budget alerts at 80% actual and 100% forecast; an invalid email and an invalid user name are rejected.

### Do the tests catch real mistakes?

A test that never fails proves nothing, so I broke a copy of the configuration three ways and ran the suite each time:

| Deliberate mistake | Result |
|---|---|
| MFA deny condition flipped from `"false"` to `"true"` | caught, 9 passed 1 failed |
| Role trust given to `lambda.amazonaws.com` instead of EC2 | caught, 9 passed 1 failed |
| `iam:CreateUser` added to the developer policy | caught, 9 passed 1 failed |

### Skipped and ignored findings

- **Checkov CKV_AWS_273** ("access through SSO, not IAM users"): the brief requires an IAM user. The skip is written on the resource, and production would use IAM Identity Center (README, Lab vs production).
- **Trivy AWS-0123** ("MFA not enforced for group"): MFA is enforced by the attached `require-mfa` managed policy. Trivy only inspects inline group policies. The live simulation below proves the enforcement.

## Live run on AWS (13 November 2026, 20:55 WAT)

`terraform apply` created 13 resources through an IAM Identity Center administrator session. [`scripts/verify_live.sh`](../scripts/verify_live.sh) then asked IAM itself, through `iam:SimulatePrincipalPolicy`, what each identity may do, and validated each policy file with IAM Access Analyzer.

**23 passed, 0 failed:**

- 14 simulations for the developer, for example: `ec2:DescribeInstances` is allowed with MFA and explicitly denied without it; stopping an instance tagged `Team=developers` is allowed, but one tagged `Team=finance` is not; creating IAM users and attaching policies to itself are implicitly denied; before MFA, the developer may change their own password and register an MFA device, but not remove one.
- 5 simulations for the EC2 role: it may read the app config object but not overwrite it, may not read other project buckets, may register with Systems Manager, and may not create IAM users.
- 4 IAM Access Analyzer validations: 0 findings on each policy file.

Account evidence from the same run: root MFA enabled, password policy 14 characters with reuse prevention 24, the user's only group is `davine-wk1-developers`, 0 access keys, the role trusted by `ec2.amazonaws.com` only.

The full transcript, with account IDs redacted by the script, is [`evidence/live-run-2026-11-13.txt`](evidence/live-run-2026-11-13.txt).

## Teardown (13 November 2026, 21:52 WAT)

After the console screenshots were taken, `terraform destroy` removed all 13 resources. Checked straight afterwards: the group, user, role, the three `davine-wk1-*` policies and the password policy no longer exist; root MFA is still enabled; the account's two existing budgets are untouched. The account is back in exactly the state it was in before the run.

## Running the checks yourself

```bash
cd terraform && terraform init -backend=false && terraform test     # offline, no AWS needed
tflint --chdir=terraform && checkov -d terraform --quiet && trivy config terraform
AWS_PROFILE=<profile> scripts/verify_live.sh                          # after terraform apply
```
