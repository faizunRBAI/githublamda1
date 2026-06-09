terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ──────────────────────────────────────────────
# Variables
# ──────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "githublamda1"
}

variable "app_env" {
  description = "Application environment (development | staging | production)"
  type        = string
  default     = "development"
}

variable "zip_path" {
  description = "Local path to the deployment zip archive produced by CI"
  type        = string
  default     = "function.zip"
}

# ──────────────────────────────────────────────
# IAM role for Lambda
# ──────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.function_name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ──────────────────────────────────────────────
# Lambda function
# ──────────────────────────────────────────────
resource "aws_lambda_function" "app" {
  function_name = var.function_name
  description   = "FastAPI application deployed via Mangum"

  filename         = var.zip_path
  source_code_hash = filebase64sha256(var.zip_path)

  runtime = "python3.12"
  handler = "lambda_handler.handler"

  role = aws_iam_role.lambda_exec.arn

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      APP_ENV = var.app_env
    }
  }
}

# ──────────────────────────────────────────────
# Lambda Function URL (public, no auth)
# ──────────────────────────────────────────────
resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    expose_headers    = ["*"]
    max_age           = 86400
  }
}

# ──────────────────────────────────────────────
# CloudWatch log group with retention
# ──────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 14
}

# ──────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────
output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.app.arn
}

output "function_url" {
  description = "Lambda Function URL (public endpoint)"
  value       = aws_lambda_function_url.app.function_url
}