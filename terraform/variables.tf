variable "region" {
  description = "Region for the provider. IAM is global, but AWS Budgets and the provider still need one."
  type        = string
  default     = "us-east-1"
}

variable "developer_user_names" {
  description = "Short names of the developers to onboard. Each becomes IAM user davine-wk1-<name> in the Developers group."
  type        = list(string)
  default     = ["developer-01"]

  validation {
    condition     = length(var.developer_user_names) > 0 && alltrue([for n in var.developer_user_names : can(regex("^[a-z0-9][a-z0-9-]{1,30}$", n))])
    error_message = "Give at least one name, each 2 to 31 lowercase letters, digits or hyphens."
  }
}

variable "budget_alert_email" {
  description = "Email that receives budget alerts. Leave null to skip the budget, for example when the account already has one."
  type        = string
  default     = null

  validation {
    condition     = var.budget_alert_email == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be an email address or null."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in US dollars. Alerts go out at 80% of actual spend and 100% of forecast spend."
  type        = number
  default     = 1

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than zero."
  }
}
