# Inputs of this configuration. Values are supplied in terraform.tfvars.

variable "my_ip_cidr" {
  description = "Your public IP in CIDR form, e.g. 203.0.113.5/32. Only this IP may SSH in."
  type        = string
}

variable "ssh_public_key" {
  description = "Content of your SSH PUBLIC key (~/.ssh/devops-bastion.pub)"
  type        = string
}
