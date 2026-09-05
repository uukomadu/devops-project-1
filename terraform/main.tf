# Fetch the latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-*-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create an EC2 instance
resource "aws_instance" "project1_ec2_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = "1PU" # Replace with your actual key pair name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.EC2_SG.id]

  # One-minute CloudWatch metrics. Seven metrics per instance, billed at the
  # per-metric CloudWatch rate; small next to the NAT gateway.
  monitoring = true

  # IMDSv2 only. With http_tokens = "required", a request to the metadata
  # endpoint needs a token obtained by PUT first, which turns an SSRF bug in
  # WordPress or a plugin from "read the instance credentials" into a 401.
  # Hop limit 1 keeps the token from being usable by anything routed through
  # the host, such as a container.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # The root volume holds MySQL and the WordPress tree. Encrypting it is a
  # replacing change: an instance already created without this block is
  # destroyed and recreated when it is applied.
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = {
    Name = "Project1-EC2-Instance"
  }
}

# Create an Elastic IP and associate it with the EC2 instance
resource "aws_eip" "project1_eip" {
  instance = aws_instance.project1_ec2_instance.id
  domain   = "vpc"

  tags = {
    Name = "Project1-EIP"
  }
}
