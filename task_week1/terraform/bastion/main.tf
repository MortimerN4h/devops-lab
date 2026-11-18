# Creates ONE Ubuntu server ("bastion") that can call AWS through an IAM role (no access keys).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ---- Look up the latest Ubuntu 24.04 image (Canonical publishes its ID here) ----
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ---- SSH key: AWS stores the PUBLIC half and puts it on the server ----
resource "aws_key_pair" "bastion" {
  key_name   = "devops-bastion-key"
  public_key = var.ssh_public_key
}

# ---- Firewall: SSH (port 22) only from your IP; the server may call out anywhere ----
resource "aws_security_group" "bastion" {
  name = "devops-bastion-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---- IAM role: "EC2 is allowed to become this identity" + what the identity may do ----
resource "aws_iam_role" "bastion" {
  name = "devops-bastion-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Admin = full access. Acceptable only in a personal learning account.
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# An EC2 server cannot hold a role directly; it holds an "instance profile" wrapping the role.
resource "aws_iam_instance_profile" "bastion" {
  name = "devops-bastion-profile"
  role = aws_iam_role.bastion.name
}

# ---- The server itself ----
resource "aws_instance" "bastion" {
  ami                    = nonsensitive(data.aws_ssm_parameter.ubuntu.value)
  instance_type          = "t3.small"
  key_name               = aws_key_pair.bastion.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # Script that runs once at first boot: installs swap, Docker, Terraform, AWS CLI.
  user_data = file("${path.module}/../../../scripts/bootstrap-bastion.sh")

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "devops-bastion"
  }
}
