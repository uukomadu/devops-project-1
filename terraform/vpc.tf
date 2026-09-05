# This Terraform configuration file defines an AWS VPC and a subnet within that VPC.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Project1-VPC"
  }
}

# Public subnet within the VPC
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "Public"
  }
}

# Private subnet within the VPC
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "Private"
  }
}

# Create an Internet Gateway for the VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Project1-IGW"
  }
}

# Create a NAT Gateway in the public subnet
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "Project1-NAT-EIP"
  }
}

# Create a NAT Gateway in the public subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "Project1-NAT-Gateway"
  }

  depends_on = [aws_internet_gateway.main] # <- missing
}

# Create a route table for the public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "Public"
  }
}

# Create a route table for the private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id # <- missing
  }
  tags = {
    Name = "Private"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" { # <- missing
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" { # <- missing

  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
} 