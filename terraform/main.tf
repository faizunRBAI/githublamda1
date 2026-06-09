terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

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

variable "zip_path" {
  description = "Local path to the deployment zip artifact"
  type        = string
  default     = "deployment.zip"
}

variable "app_env" {
  description = "Application environment (development | staging | production)"
  type        = string
  default     = "development"
}

variable "function_url_auth_type" {
  description = "AuthType for the Lambda Function URL (NONE or AWS_IAM)"
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth_type)
    error_message = "function_url_auth_type must be NONE or AWS_IAM."
  }
}

# ---------------------------------------------------------------------------
# IAM — execution role
# ---------------------------------------------------------------------------

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

  tags = {
    Project = var.function_name
  }
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "app" {
  function_name = var.function_name
  description   = "FastAPI application wrapped with Mangum"

  # Runtime — must be python3.11
  runtime = "python3.11"

  # Handler — must be exactly lambda_handler.handler
  handler = "lambda_handler.handler"

  filename         = var.zip_path
  source_code_hash = filebase64sha256(var.zip_path)

  role = aws_iam_role.lambda_exec.arn

  # Give the function enough memory and time for a cold start
  memory_size = 256
  timeout     = 30

  environment {
    variables = {
      APP_ENV = var.app_env
      # PORT and HOST are intentionally omitted — Lambda does not use them
    }
  }

  tags = {
    Project = var.function_name
  }
}

# ---------------------------------------------------------------------------
# Lambda Function URL
# ---------------------------------------------------------------------------

resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = var.function_url_auth_type

  # BUFFERED invoke mode as required by the contract
  invoke_mode = "BUFFERED"
}

# ---------------------------------------------------------------------------
# Resource-based policy — allow public invocation when AuthType is NONE
# ---------------------------------------------------------------------------

resource "aws_lambda_permission" "function_url_invoke" {
  count = var.function_url_auth_type == "NONE" ? 1 : 0

  statement_id           = "AllowFunctionURLPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.app.function_name
}

output "function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.app.arn
}

output "function_url" {
  description = "HTTPS endpoint of the Lambda Function URL"
  value       = aws_lambda_function_url.app.function_url
}