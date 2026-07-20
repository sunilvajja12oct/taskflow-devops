variable "project" { default = "taskflow" }
variable "environment" {}
variable "github_repo" { description = "format: owner/repo" }

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project}-${var.environment}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo}:*",
            "repo:${split("/", var.github_repo)[0]}@*/${split("/", var.github_repo)[1]}@*:*"
          ]
        }
      }
    }]
  })
}

# Scope-cut for time: broad access now (PowerUserAccess + limited IAM),
# tighten to per-resource least-privilege as a Phase 8 follow-up.
resource "aws_iam_role_policy_attachment" "github_actions_power" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "github_actions_iam" {
  name = "github-actions-iam-scoped"
  role = aws_iam_role.github_actions.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:GetRole", "iam:PassRole", "iam:CreateRole", "iam:DeleteRole",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy",
        "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:TagRole",
        "iam:CreateInstanceProfile", "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
        "iam:DeleteInstanceProfile", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies"
      ]
      Resource = "*"
    }]
  })
}

output "role_arn" {
  value = aws_iam_role.github_actions.arn
}
