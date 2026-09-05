# Security group for the web server. HTTP and HTTPS from anywhere, SSH from
# the admin CIDR only, and outbound limited to what the LAMP build actually
# needs rather than everything.
resource "aws_security_group" "EC2_SG" {
  name        = "Project1-Public-SG"
  description = "Security group for public subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # The description said "admin only" while the CIDR said 0.0.0.0/0. The
  # variable carries a validation block so the wildcard cannot come back
  # through a tfvars file.
  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Outbound is what the provisioning steps in the README use: apt over
  # port 80 (Ubuntu's EC2 mirrors are plain http) and wget of WordPress over
  # 443. DNS to the VPC resolver is not subject to security group rules, so
  # it needs no rule of its own. Anything else that turns out to be needed
  # should be added as a named rule here, not by reopening protocol -1.
  egress {
    description = "HTTP out for apt mirrors"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS out for package and WordPress downloads"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Project1-EC2-SG" }
}
