# Copy to terraform.tfvars (gitignored) and set your own values.
#
# admin_cidr is the only address allowed to reach port 22. Use your current
# public IP as a /32; the variable rejects 0.0.0.0/0. 203.0.113.10 is a
# documentation address and will not route anywhere.
admin_cidr = "203.0.113.10/32"
aws_region = "us-east-2"
