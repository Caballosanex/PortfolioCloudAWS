# --- GitHub Actions OIDC Federation ---
# Allows GitHub Actions to assume an IAM role without stored credentials.
# Trust is scoped to pushes on main branch only.

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]

  tags = { Name = "${var.project_name}-github-oidc" }
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:Caballosanex/PortfolioCloudAWS:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = { Name = "${var.project_name}-github-actions" }
}

resource "aws_iam_role_policy" "github_actions" {
  name = "${var.project_name}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories"
        ]
        Resource = "arn:aws:ecr:eu-west-1:649966626787:repository/asanchezbl-portfolio/*"
      },
      {
        Sid    = "S3"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::asanchezbl-static",
          "arn:aws:s3:::asanchezbl-static/*"
        ]
      },
      {
        Sid    = "ECS"
        Effect = "Allow"
        Action = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = "arn:aws:ecs:eu-west-1:649966626787:service/asanchezbl-portfolio/*"
      },
      {
        Sid    = "CloudFront"
        Effect = "Allow"
        Action = ["cloudfront:CreateInvalidation"]
        Resource = "arn:aws:cloudfront::649966626787:distribution/E3P27TI3D0ZV00"
      },
      {
        Sid    = "LambdaUpdate"
        Effect = "Allow"
        Action = ["lambda:UpdateFunctionCode"]
        Resource = "arn:aws:lambda:eu-west-1:649966626787:function:asanchezbl-portfolio-*"
      }
    ]
  })
}
