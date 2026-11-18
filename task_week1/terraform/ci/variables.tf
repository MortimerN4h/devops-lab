# Inputs. All have defaults, so no terraform.tfvars is needed; override with -var or a tfvars file.

variable "region" {
  description = "AWS region for ECR"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefix for resource names (ECR repos become <project>/<name>)"
  type        = string
  default     = "devops-lab"
}

variable "repositories" {
  description = "One ECR repository per image. Add the next app's images here (e.g. python-backend)."
  type        = list(string)
  default     = ["node-frontend", "node-backend"]
}

variable "keep_images" {
  description = "How many images to keep per repository (older ones are deleted automatically)"
  type        = number
  default     = 10
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the role, as owner/name"
  type        = string
  default     = "MortimerN4h/devops-lab"
}

variable "github_branch" {
  description = "Only workflows running on this branch may assume the role"
  type        = string
  default     = "main"
}
