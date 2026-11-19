variable "domain_name" {
  description = "Same domain as in terraform/dns (e.g. example.com). Set it in terraform.tfvars."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  description = "t3.small = 2 vCPU, 2GB RAM (enough for edge nginx + a few apps, with swap)"
  type        = string
  default     = "t3.small"
}

variable "ssh_public_key_path" {
  description = "Public key created on the bastion with: ssh-keygen -t ed25519 -f ~/.ssh/devops-app"
  type        = string
  default     = "~/.ssh/devops-app.pub"
}

variable "repo_url" {
  description = "Public Git repo cloned by the server (contains task_week1/deploy)"
  type        = string
  default     = "https://github.com/MortimerN4h/devops-lab.git"
}
