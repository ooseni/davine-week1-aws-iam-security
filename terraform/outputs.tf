output "developers_group" {
  description = "The IAM group every developer joins."
  value       = aws_iam_group.developers.name
}

output "developer_users" {
  description = "IAM user names created for the developers."
  value       = [for u in aws_iam_user.developer : u.name]
}

output "ec2_app_role" {
  description = "Name of the EC2 application role."
  value       = aws_iam_role.ec2_app.name
}

output "ec2_instance_profile" {
  description = "Instance profile to attach to the application's EC2 instance."
  value       = aws_iam_instance_profile.ec2_app.name
}

output "budget" {
  description = "Name of the monthly budget, or null when none was created."
  value       = one(aws_budgets_budget.monthly[*].name)
}
