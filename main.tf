terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data source for existing VPC
data "aws_vpc" "existing" {
  id = var.vpc_id
}

# Get first available AZ in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for default subnet in first available AZ
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  # Use first default subnet found
  default_subnet_id = data.aws_subnets.default.ids[0]
}

# Create SSH key pair
resource "tls_private_key" "vault_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vault" {
  key_name   = "${var.environment}-vault-key"
  public_key = tls_private_key.vault_ssh.public_key_openssh

  tags = {
    Name = "${var.environment}-vault-key"
  }
}

# Save private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.vault_ssh.private_key_pem
  filename        = "${path.module}/${var.environment}-vault-key.pem"
  file_permission = "0400"
}

# Security Group
resource "aws_security_group" "vault_sg" {
  name        = "${var.environment}-vault-sg"
  description = "Security group for Vault Enterprise cluster"
  vpc_id      = var.vpc_id

  # Vault API
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Vault cluster communication
  ingress {
    from_port = 8201
    to_port   = 8201
    protocol  = "tcp"
    self      = true
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-vault-sg"
  }
}

# IAM Role and Instance Profile
resource "aws_iam_role" "vault_role" {
  name = "${var.environment}-vault-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-vault-role"
  }
}

resource "aws_iam_role_policy" "vault_policy" {
  name = "${var.environment}-vault-policy"
  role = aws_iam_role.vault_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = local.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "vault_profile" {
  name = "${var.environment}-vault-profile"
  role = aws_iam_role.vault_role.name
}

# EC2 Instances
resource "aws_instance" "vault" {
  count = var.vault_node_count

  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.vault.key_name
  subnet_id     = local.default_subnet_id

  vpc_security_group_ids = [aws_security_group.vault_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.vault_profile.name

  user_data = templatefile("${path.module}/user-data.sh", {
    vault_license = var.vault_license
    region        = var.aws_region
    node_count    = var.vault_node_count
    kms_key_id    = local.kms_key_id
    kms_endpoint  = var.kms_endpoint
  })

  tags = {
    Name  = "${var.environment}-vault-node-${count.index + 1}"
    Role  = "vault"
    Index = count.index
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
