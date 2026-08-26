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
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = "1PU" # Replace with your actual key pair name
  subnet_id              = aws_subnet.public.id        # <- missing
  vpc_security_group_ids = [aws_security_group.EC2_SG.id] # <- missing

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