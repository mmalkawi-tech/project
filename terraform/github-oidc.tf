# =============================================================================
# GitHub Actions OIDC — Keyless authentication to AWS
# Allows GitHub Actions workflows in mmalkawi-tech/project to assume
# the github-actions-dr-role without any long-lived access keys.
# =============================================================================

# GitHub's OIDC provider (created once per AWS account)
resource "aws_iam_openid_connect_provider" "github" {
  provider = aws.primary
  url      = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (stable — verified against their cert chain)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM Role assumed by GitHub Actions
resource "aws_iam_role" "github_actions" {
  provider = aws.primary
  name     = "github-actions-dr-role"
  description = "Assumed by GitHub Actions in mmalkawi-tech/project via OIDC"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Only workflows from this specific repo can assume this role
            "token.actions.githubusercontent.com:sub" = "repo:mmalkawi-tech/project:*"
          }
        }
      }
    ]
  })
}

# Policy: Terraform state backend access
resource "aws_iam_role_policy" "github_actions_state" {
  provider = aws.primary
  name     = "terraform-state-access"
  role     = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:ListBucket", "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::enhanceit-tfstate-dr",
          "arn:aws:s3:::enhanceit-tfstate-dr/*"
        ]
      },
      {
        Sid    = "DynamoDBStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem",
          "dynamodb:DeleteItem", "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:866934333672:table/terraform-state-lock"
      }
    ]
  })
}

# Policy: DR infrastructure permissions
resource "aws_iam_role_policy" "github_actions_dr" {
  provider = aws.primary
  name     = "dr-infrastructure-access"
  role     = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2AndASG"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "autoscaling:*",
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "RDS"
        Effect = "Allow"
        Action = ["rds:*"]
        Resource = "*"
      },
      {
        Sid    = "S3"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = "*"
      },
      {
        Sid    = "Route53"
        Effect = "Allow"
        Action = ["route53:*", "route53resolver:*"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchAndSNS"
        Effect = "Allow"
        Action = [
          "cloudwatch:*",
          "sns:*",
          "logs:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMScoped"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:PassRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile", "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider", "iam:ListOpenIDConnectProviders",
          "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "Backup"
        Effect = "Allow"
        Action = ["backup:*"]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "ARN to paste into GitHub Actions workflow role-to-assume"
  value       = aws_iam_role.github_actions.arn
}
