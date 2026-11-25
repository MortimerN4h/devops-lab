# The APP server: one EC2 that pulls images from ECR and runs every app behind one Nginx ("edge").
#   Internet -> Elastic IP :80/:443 -> edge nginx -> node-frontend -> node-backend -> node-mongo
# Needs first: terraform/dns applied (hosted zone), terraform/ci applied (ECR), images pushed,
# and task_week1/deploy/ pushed to GitHub (user_data clones the public repo).

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ---- Look-ups (data = read something that already exists, create nothing) ----
data "aws_caller_identity" "me" {} # gives the account ID

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_security_group" "bastion" {
  name = "devops-bastion-sg" # created by terraform/bastion
}

data "aws_route53_zone" "main" {
  name = var.domain_name # created by terraform/dns
}

locals {
  # ECR address of THIS account, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com
  registry = "${data.aws_caller_identity.me.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

# ---- SSH key (the key pair lives on the bastion: ~/.ssh/devops-app) ----
resource "aws_key_pair" "app" {
  key_name   = "devops-app-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# ---- Firewall ----
resource "aws_security_group" "app" {
  name        = "devops-app-sg"
  description = "Web from anywhere, SSH only from the bastion"

  ingress {
    description = "HTTP (also used by Lets Encrypt to verify the domain)" # AWS forbids the ' character here
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Source = another SECURITY GROUP instead of an IP: "any machine in the bastion's group".
  # This is what makes the bastion a bastion: the only way in for SSH.
  ingress {
    description     = "SSH from the bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [data.aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---- IAM: the server may only READ from ECR (least privilege, unlike the admin bastion) ----
resource "aws_iam_role" "app" {
  name = "devops-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Lets the SSM agent (pre-installed on Ubuntu AMIs) register the server with AWS Systems Manager.
# GitHub Actions then deploys with "SSM Run Command": no SSH, no open port 22, no private key in GitHub.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "devops-app-profile"
  role = aws_iam_role.app.name
}

# ---- The server ----
resource "aws_instance" "app" {
  ami                    = nonsensitive(data.aws_ssm_parameter.ubuntu.value)
  instance_type          = var.instance_type
  key_name               = aws_key_pair.app.key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  # templatefile() = read the file and replace ${registry}, ${domain}, ${repo_url} with real values
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    registry = local.registry
    domain   = var.domain_name
    repo_url = var.repo_url
  })
  user_data_replace_on_change = true # user_data only runs at first boot -> changing it rebuilds the server

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "devops-app"
  }

  # The SSM parameter above always returns the NEWEST Ubuntu image, and Canonical publishes one every
  # few weeks. Without this, every new image would make `plan` destroy and rebuild the server.
  # Updates on a running server come from apt; a new AMI is used only when the server is rebuilt.
  lifecycle {
    ignore_changes = [ami]
  }
}

# ---- Fixed public IP: DNS points here, so it must not change on stop/start ----
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"
  tags = {
    Name = "devops-app-ip"
  }
}

# ---- DNS: node.<domain> -> Elastic IP ----
resource "aws_route53_record" "node" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "node.${var.domain_name}"
  type    = "A" # A record = name -> IPv4 address
  ttl     = 300 # resolvers may cache the answer for 5 minutes
  records = [aws_eip.app.public_ip]
}

# ---- DNS: python.<domain> -> the same Elastic IP (edge picks the app by server_name) ----
resource "aws_route53_record" "python" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "python.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}

# ---- DNS: go.<domain> -> the same Elastic IP ----
resource "aws_route53_record" "go" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "go.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}

# ---- DNS: java.<domain> -> the same Elastic IP ----
resource "aws_route53_record" "java" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "java.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}
