variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-2"
}

variable "admin_cidr" {
  description = "The only CIDR allowed to reach port 22. No default on purpose: the value has to be chosen, and 0.0.0.0/0 is rejected."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid IPv4 CIDR and must not be 0.0.0.0/0. Use your own address as a /32."
  }
}
