# All inputs have defaults: no terraform.tfvars needed.

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "master_instance_type" {
  # RKE2 server needs at least 2 vCPU / 4 GB (etcd + API server + the system pods).
  description = "c7i-flex.large = 2 vCPU, 4 GB RAM (free-plan eligible)"
  type        = string
  default     = "c7i-flex.large"
}

variable "worker_instance_type" {
  description = "Runs the app pods and Longhorn's data. c7i-flex.large = 2 vCPU, 4 GB RAM"
  type        = string
  default     = "c7i-flex.large"
}

variable "worker_disk_gb" {
  description = "Root disk of the worker (OS + images + Longhorn volume data)"
  type        = number
  default     = 40
}

variable "ssh_public_key_path" {
  description = "Public key created on the bastion with: ssh-keygen -t ed25519 -f ~/.ssh/devops-rke2"
  type        = string
  default     = "~/.ssh/devops-rke2.pub"
}
