output "github_actions_role_arn" {
  description = "Put this in GitHub: Settings -> Secrets and variables -> Actions -> Variables -> AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "registry" {
  description = "ECR registry host (docker login target)"
  value       = split("/", values(aws_ecr_repository.app)[0].repository_url)[0]
}

output "repository_urls" {
  description = "Full image names to push/pull"
  value       = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}
