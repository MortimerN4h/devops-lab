# Container registry (ECR) + a way for GitHub Actions to log in to AWS WITHOUT stored keys (OIDC).
#
# How OIDC works:
#   1. A GitHub Actions job asks GitHub for a short-lived signed token (a JWT) that says
#      "I am repo X, branch Y".
#   2. The job hands that token to AWS STS (AssumeRoleWithWebIdentity).
#   3. AWS checks the signature against the OIDC provider registered below, checks the trust
#      policy conditions (right repo + branch), then returns credentials valid for ~1 hour.
# Result: no AWS access key is ever stored in GitHub.

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

# ---------------------------------------------------------------------------
# ECR: one repository per image, e.g. devops-lab/node-frontend
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  for_each = toset(var.repositories) # creates one resource per name in the list

  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "MUTABLE" # "latest" is moved to the newest image on every push
  force_delete         = true      # allow `terraform destroy` even when images exist (learning account)

  image_scanning_configuration {
    scan_on_push = true # free basic scan for known vulnerabilities (CVE)
  }
}

# Keep only the newest images so storage (= cost) stays small.
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last ${var.keep_images} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_images
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# OIDC: tell AWS to trust tokens signed by GitHub Actions
# (only ONE such provider can exist per AWS account)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"] # the "audience" GitHub puts in the token for AWS
  # AWS now verifies GitHub's certificate itself; these well-known values are still required by the API.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# ---------------------------------------------------------------------------
# IAM role that GitHub Actions becomes
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_actions" {
  name = "${var.project}-github-actions"

  # TRUST policy = WHO may become this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # sub = "repo:<owner>/<repo>:ref:refs/heads/<branch>" -> only OUR repo, only branch main.
        # Without this condition ANY GitHub repo in the world could assume the role!
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
        }
      }
    }]
  })
}

# PERMISSION policy = WHAT the role may do: log in to ECR and push/pull only OUR repositories.
resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken" # account-wide action, cannot be limited to a repo
        Resource = "*"
      },
      {
        Sid    = "PushPullOwnRepos"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = [for r in aws_ecr_repository.app : r.arn]
      },
    ]
  })
}
