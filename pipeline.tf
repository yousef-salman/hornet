resource "random_uuid" "S3_suffix" {}

resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "codepipeline-${random_uuid.S3_suffix.result}"
  acl    = "private"
}

resource "aws_codestarconnections_connection" "github_connection" {
  name          = "hornet-connection"
  provider_type = "GitHub"
}


resource "aws_codepipeline" "hornet_codepipeline" {
  name     = "hornet"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_bucket.id
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["hornet-SourceArtifact"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId = "gohornet/hornet"
        BranchName       = "main"
      }
      run_order         = 1
    }
  }

   stage {
    name = "Build-Image"
    action {
        name             = "Build"
        category         = "Build"
        owner            = "AWS"
        provider         = "CodeBuild"
        input_artifacts  = ["hornet-SourceArtifact"]
        version          = "1"

        configuration = {
            ProjectName = aws_codebuild_project.hornet_build.id
        }
        run_order        = 1
        }
  }

   stage {
    name = "Deploy-k8s"
        action {
        name             = "Deploy"
        category         = "Build"
        owner            = "AWS"
        provider         = "CodeBuild"
        input_artifacts  = ["hornet-SourceArtifact"]
        version          = "1"

        configuration = {
            ProjectName = aws_codebuild_project.hornet_deploy.id
        }
        run_order        = 1
        }
    }
}




#############################################################################################
##################################### CodeBuild #############################################
#############################################################################################

resource "aws_iam_role" "codepipeline_role" {
  name = "hornet-pipeline"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_role_policy" {
  role = aws_iam_role.codepipeline_role.name

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObjectAcl",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.artifact_bucket.arn}",
        "${aws_s3_bucket.artifact_bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codestar-connections:UseConnection"
      ],
      "Resource": "${aws_codestarconnections_connection.github_connection.arn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_iam_role" "codebuild_role" {
  name = "hornet"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codebuild_role_policy" {
  role = aws_iam_role.codebuild_role.name

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterfacePermission"
      ],
      "Resource": [
        "arn:aws:ec2:us-east-1:123456789012:network-interface/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "ecr:*"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_codebuild_project" "hornet_build" {
  name          = "hornet-build"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "STAGE"
      value = "BUILD"
    }

    environment_variable {
      name  = "ServiceName"
      value = "hornet"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "hotnet-build-log-group"
      stream_name = "hornet-build-log-stream"
    }

  }

  source {
    type            = "NO_SOURCE"
    buildspec       = file("buildspec")
  }
}


resource "aws_codebuild_project" "hornet_deploy" {
  name          = "hornet-deploy"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "STAGE"
      value = "DEPLOY"
    }

    environment_variable {
      name  = "ServiceName"
      value = "hornet"
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "hotnet-deploy-log-group"
      stream_name = "hornet-deploy-log-stream"
    }

  }

  source {

    type            = "NO_SOURCE"
    buildspec       = file("buildspec")
  }
}