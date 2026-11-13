#!/usr/bin/env bash
# Live checks after `terraform apply`. Asks IAM itself what each identity may do, using the
# policy simulator (iam:SimulatePrincipalPolicy), which evaluates the real attached policies
# without performing any action. Also validates every policy file with IAM Access Analyzer and
# collects account evidence. Account IDs are replaced with <ACCOUNT_ID> in everything printed.
#
# Usage: AWS_PROFILE=<profile> scripts/verify_live.sh [developer-short-name]
# Exit code: 0 when every expectation holds, 1 otherwise.
set -euo pipefail

prefix="davine-wk1"
user="${prefix}-${1:-developer-01}"
role="${prefix}-ec2-app"
here="$(cd "$(dirname "$0")/.." && pwd)"

account=$(aws sts get-caller-identity --query Account --output text)
redact() { sed -u -E "s/[0-9]{12}/<ACCOUNT_ID>/g"; }
exec > >(redact) 2>&1 # AWS error messages can name the account, so stderr is redacted too
user_arn=$(aws iam get-user --user-name "$user" --query User.Arn --output text)
role_arn=$(aws iam get-role --role-name "$role" --query Role.Arn --output text)

passed=0
failed=0

# simulate LABEL EXPECTED PRINCIPAL_ARN ACTION RESOURCE_ARN [extra context entries...]
simulate() {
    local label=$1 expected=$2 principal=$3 action=$4 resource=$5
    shift 5
    local decision
    decision=$(aws iam simulate-principal-policy \
        --policy-source-arn "$principal" \
        --action-names "$action" \
        --resource-arns "$resource" \
        --context-entries "ContextKeyName=aws:username,ContextKeyValues=$user,ContextKeyType=string" "$@" \
        --query 'EvaluationResults[0].EvalDecision' --output text)
    if [[ "$decision" == "$expected" ]]; then
        passed=$((passed + 1)); printf '  PASS  %-58s %s\n' "$label" "$decision"
    else
        failed=$((failed + 1)); printf '  FAIL  %-58s %s (expected %s)\n' "$label" "$decision" "$expected"
    fi
}
mfa() { echo "ContextKeyName=aws:MultiFactorAuthPresent,ContextKeyValues=$1,ContextKeyType=boolean"; }

echo "== Policy simulation: developer $user"
own_user="arn:aws:iam::${account}:user/${user}"
bucket_object="arn:aws:s3:::davine-wk1-dev-assets/report.csv"
team_instance="arn:aws:ec2:us-east-1:${account}:instance/i-0123456789abcdef0"
simulate "describe EC2 instances, signed in with MFA"              allowed      "$user_arn" ec2:DescribeInstances "*" "$(mfa true)"
simulate "describe EC2 instances, no MFA"                          explicitDeny "$user_arn" ec2:DescribeInstances "*" "$(mfa false)"
simulate "read a project bucket object, with MFA"                  allowed      "$user_arn" s3:GetObject "$bucket_object" "$(mfa true)"
simulate "read a project bucket object, no MFA"                    explicitDeny "$user_arn" s3:GetObject "$bucket_object" "$(mfa false)"
simulate "read an object outside the project buckets, with MFA"    implicitDeny "$user_arn" s3:GetObject "arn:aws:s3:::payroll-exports/2026.csv" "$(mfa true)"
simulate "stop an instance tagged Team=developers, with MFA"       allowed      "$user_arn" ec2:StopInstances "$team_instance" "$(mfa true)" \
    "ContextKeyName=aws:ResourceTag/Team,ContextKeyValues=developers,ContextKeyType=string"
simulate "stop an instance tagged Team=finance, with MFA"          implicitDeny "$user_arn" ec2:StopInstances "$team_instance" "$(mfa true)" \
    "ContextKeyName=aws:ResourceTag/Team,ContextKeyValues=finance,ContextKeyType=string"
simulate "terminate an instance, with MFA"                         implicitDeny "$user_arn" ec2:TerminateInstances "$team_instance" "$(mfa true)"
simulate "create an IAM user, with MFA"                            implicitDeny "$user_arn" iam:CreateUser "arn:aws:iam::${account}:user/new-hire" "$(mfa true)"
simulate "attach AdministratorAccess to itself, with MFA"          implicitDeny "$user_arn" iam:AttachUserPolicy "$own_user" "$(mfa true)"
simulate "change own password before MFA (first sign-in)"          allowed      "$user_arn" iam:ChangePassword "$own_user" "$(mfa false)"
simulate "register own MFA device before MFA"                      allowed      "$user_arn" iam:EnableMFADevice "$own_user" "$(mfa false)"
simulate "remove own MFA device, no MFA"                           explicitDeny "$user_arn" iam:DeactivateMFADevice "$own_user" "$(mfa false)"
simulate "change another user's password, with MFA"                implicitDeny "$user_arn" iam:ChangePassword "arn:aws:iam::${account}:user/someone-else" "$(mfa true)"

echo "== Policy simulation: EC2 application role $role"
simulate "read the app config object"                             allowed      "$role_arn" s3:GetObject "arn:aws:s3:::davine-wk1-dev-app-config/app.json"
simulate "overwrite the app config object"                        implicitDeny "$role_arn" s3:PutObject "arn:aws:s3:::davine-wk1-dev-app-config/app.json"
simulate "read another project bucket"                            implicitDeny "$role_arn" s3:GetObject "$bucket_object"
simulate "register with Systems Manager (SSM core policy)"        allowed      "$role_arn" ssm:UpdateInstanceInformation "*"
simulate "create an IAM user"                                      implicitDeny "$role_arn" iam:CreateUser "arn:aws:iam::${account}:user/new-hire"

echo "== IAM Access Analyzer policy validation"
for f in "$here"/policies/*.json; do
    if [[ "$f" == *trust* ]]; then
        args=(--policy-type RESOURCE_POLICY --validate-policy-resource-type AWS::IAM::AssumeRolePolicyDocument)
    else
        args=(--policy-type IDENTITY_POLICY)
    fi
    count=$(aws accessanalyzer validate-policy "${args[@]}" --policy-document "file://$f" --query 'length(findings)' --output text)
    if [[ "$count" == "0" ]]; then
        passed=$((passed + 1)); printf '  PASS  %-58s 0 findings\n' "$(basename "$f")"
    else
        failed=$((failed + 1)); printf '  FAIL  %-58s %s findings\n' "$(basename "$f")" "$count"
        aws accessanalyzer validate-policy "${args[@]}" --policy-document "file://$f" \
            --query 'findings[].[findingType,issueCode]' --output text | sed 's/^/        /'
    fi
done

echo "== Account evidence"
echo "  root user MFA enabled (AccountMFAEnabled): $(aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text)"
echo "  password policy: min length $(aws iam get-account-password-policy --query 'PasswordPolicy.MinimumPasswordLength' --output text), reuse prevention $(aws iam get-account-password-policy --query 'PasswordPolicy.PasswordReusePrevention' --output text)"
echo "  $user groups: $(aws iam list-groups-for-user --user-name "$user" --query 'Groups[].GroupName' --output text)"
echo "  $user access keys: $(aws iam list-access-keys --user-name "$user" --query 'length(AccessKeyMetadata)' --output text)"
echo "  ${prefix}-developers policies: $(aws iam list-attached-group-policies --group-name "${prefix}-developers" --query 'AttachedPolicies[].PolicyName' --output text)"
echo "  $role trusted by: $(aws iam get-role --role-name "$role" --query 'Role.AssumeRolePolicyDocument.Statement[].Principal.Service' --output text)"
echo "  $role policies: $(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyName' --output text)"
echo "  budgets in the account: $(aws budgets describe-budgets --account-id "$account" --query 'length(Budgets)' --output text)"

echo "== Result: $passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
