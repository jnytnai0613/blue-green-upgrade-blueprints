locals {
  s3_name                = "codebuild-cache-taniai"
  ecr_name               = "blue-green-ecr"
  codebuild_project_name = "codebuild-project-practice"
  connection_name        = "github-connection"
}

resource "aws_s3_bucket" "codebuild" {
  bucket = local.s3_name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "codebuild"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    effect = "Allow"
    sid    = "ECRAccess"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:InitiateLayerUpload",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:BatchGetImage"
    ]

    resources = [aws_ecr_repository.ecr.arn]
  }

  statement {
    effect = "Allow"
    sid    = "ECRAuth"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"
    sid    = "CloudWatchLogsAccess"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"
    sid    = "CodeConnectionAccess"

    actions = [
      "codeconnections:GetConnectionToken",
      "codeconnections:GetConnection"
    ]

    resources = [aws_codeconnections_connection.github.arn]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  role   = aws_iam_role.codebuild.name
  policy = data.aws_iam_policy_document.codebuild.json
}

resource "aws_codeconnections_connection" "github" {
  name          = local.connection_name
  provider_type = "GitHub"
}

resource "aws_codebuild_project" "codebuild" {
  name          = local.codebuild_project_name
  description   = "practice for CI from GitHub"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 5

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type     = "S3"
    location = aws_s3_bucket.codebuild.bucket
  }

  environment {
    # https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-compute-types.html#environment.types
    compute_type = "BUILD_GENERAL1_SMALL"
    type         = "LINUX_CONTAINER"

    # https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-available.html
    # EC2インスタンスは"aws/codebuild/ami/amazonlinux-x86_64-base:latest"や
    # "aws/codebuild/ami/amazonlinux-arm-base:latest"のみ。基本的には自前でビルドが必要。
    image                       = "aws/codebuild/standard:6.0" # Ubuntu 22.04
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type = "GITHUB"
    # 適宜変更する
    location            = "https://github.com/jnytnai0613/blue-green-upgrade-blueprints"
    report_build_status = true
    buildspec           = "system/assets/sample-app/container/buildspec.yml"

    auth {
      type     = "CODECONNECTIONS"
      resource = aws_codeconnections_connection.github.arn
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "buildlog"
      stream_name = "log-stream"
    }
  }
}

/*
# GitHubのSettings/Webhooksに反映される
# 初回apply時はこのresourceはコメントアウトしておく
# CodeConnectionを承認しないと、ARNの無効エラーが出る
resource "aws_codebuild_webhook" "github" {
  project_name = aws_codebuild_project.codebuild.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_MERGED"
    }

    filter {
      type    = "FILE_PATH"
      pattern = "system/assets/sample-app/container/.*"
    }
  }
}
*/

resource "aws_ecr_repository" "ecr" {
  name = local.ecr_name

  image_scanning_configuration {
    scan_on_push = true
  }
}
