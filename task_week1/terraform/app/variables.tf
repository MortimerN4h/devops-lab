variable "domain_name" {
  description = "Same domain as in terraform/dns (e.g. example.com). Set it in terraform.tfvars."
  type        = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  # Was t3.small (2 GB): fine for Node + Python + Go, too small once Java (JVM + MySQL ~700 MB) joins.
  # Changing it = Terraform stops the server, changes the type, starts it again (same disk, same Elastic IP).
  description = "m7i-flex.large = 2 vCPU, 8 GB RAM (free-plan eligible; t3.medium is not)"
  type        = string
  default     = "m7i-flex.large"
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
