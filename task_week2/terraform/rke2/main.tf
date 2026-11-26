# A small Kubernetes cluster with RKE2 (Rancher's Kubernetes distribution): 1 master + 1 worker, on EC2.
#   master = RKE2 "server": control plane (API server, etcd, scheduler, controller-manager) + can run pods
#   worker = RKE2 "agent" : only runs pods (kubelet + container runtime), joins the master with a token
# Terraform only creates the machines and the network rules. RKE2 and Longhorn are installed BY HAND
# (see ../../README.md) so every step is visible; user_data only sets the hostname.

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

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_security_group" "bastion" {
  name = "devops-bastion-sg" # created by task_week1/terraform/bastion
}

resource "aws_key_pair" "rke2" {
  key_name   = "devops-rke2-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# ---- Firewall: one group for BOTH nodes ----
resource "aws_security_group" "rke2" {
  name        = "devops-rke2-sg"
  description = "RKE2 nodes: everything between nodes, SSH and kube API from the bastion"

  # self = true: "any machine in THIS group". The nodes need many ports between them
  # (9345 join, 6443 API, 10250 kubelet, 2379-2380 etcd, 8472/udp VXLAN pod network, Longhorn 9500+...).
  # Listing them one by one is the strict way; inside a private 2-node lab, trusting the group is enough.
  ingress {
    description = "All traffic between cluster nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "SSH from the bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [data.aws_security_group.bastion.id]
  }

  ingress {
    description     = "Kubernetes API from the bastion (kubectl, helm)"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [data.aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # download RKE2, container images, Helm charts
  }
}

# ---- The two nodes: same shape, different name / size / disk ----
locals {
  nodes = {
    master = { instance_type = var.master_instance_type, disk_gb = 30 }
    worker = { instance_type = var.worker_instance_type, disk_gb = var.worker_disk_gb }
  }
}

resource "aws_instance" "node" {
  for_each = local.nodes # one instance per map entry: aws_instance.node["master"], aws_instance.node["worker"]

  ami                    = nonsensitive(data.aws_ssm_parameter.ubuntu.value)
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.rke2.key_name
  vpc_security_group_ids = [aws_security_group.rke2.id]

  # Kubernetes names each node after the machine's hostname -> readable names instead of ip-172-31-x-y
  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname rke2-${each.key}
  EOF

  root_block_device {
    volume_size = each.value.disk_gb # Longhorn stores volume data in /var/lib/longhorn on this disk
    volume_type = "gp3"
  }

  tags = {
    Name = "devops-rke2-${each.key}"
  }

  lifecycle {
    ignore_changes = [ami] # same reason as task_week1/terraform/app: a newer Ubuntu image must not rebuild the node
  }
}
