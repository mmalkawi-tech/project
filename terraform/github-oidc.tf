# =============================================================================
# GitHub Actions OIDC — Keyless authentication to AWS
# Allows GitHub Actions workflows in mmalkawi-tech/project to assume
# the github-actions-dr-role without any long-lived access keys.
# =============================================================================

# GitHub's OIDC provider — already created by bootstrap.sh, read-only here
data "aws_iam_openid_connect_provider" "github" {
  provider = aws.primary
  url      = "https://token.actions.githubusercontent.com"
}

# IAM Role — already created by bootstrap.sh, read-only here
data "aws_iam_role" "github_actions" {
  provider = aws.primary
  name     = "github-actions-dr-role"
}

# Policy: Terraform state backend access
resource "aws_iam_role_policy" "github_actions_state" {
  provider = aws.primary
  name     = "terraform-state-access"
  role     = data.aws_iam_role.github_actions.role_name

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
  role     = data.aws_iam_role.github_actions.role_name

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
  description = "ARN of the GitHub Actions IAM role"
  value       = data.aws_iam_role.github_actions.arn
}
