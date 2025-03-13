terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# DynamoDB Table
resource "aws_dynamodb_table" "raw_sensor_data" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "Timestamp"
  stream_enabled = false

  attribute {
    name = "Timestamp"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda IAM Policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.raw_sensor_data.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "sensor_data_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "save-raw-sensor-data"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 256
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.raw_sensor_data.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "lambda_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda_stage" {
  api_id = aws_apigatewayv2_api.lambda_api.id
  name   = var.environment
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.lambda_api.id
  integration_type = "AWS_PROXY"

  connection_type    = "INTERNET"
  description       = "Lambda integration"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.sensor_data_handler.invoke_arn
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "POST /save-raw-sensor-data"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sensor_data_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.js"
  output_path = "${path.module}/lambda/function.zip"
}

# User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "openmetabolics-users"

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  # Required attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    required           = true
    mutable            = true

    string_attribute_constraints {
      min_length = 3
      max_length = 100
    }
  }

  schema {
    name                = "given_name"  # First name
    attribute_data_type = "String"
    required           = true
    mutable            = true

    string_attribute_constraints {
      min_length = 1
      max_length = 50
    }
  }

  schema {
    name                = "family_name"  # Last name
    attribute_data_type = "String"
    required           = true
    mutable            = true

    string_attribute_constraints {
      min_length = 1
      max_length = 50
    }
  }

  # Enable email verification
  auto_verified_attributes = ["email"]
  
  verification_message_template {
    email_subject = "Your OpenMetabolics Verification Code"
    email_message = "Thank you for signing up! Your verification code is {####}"
    default_email_option = "CONFIRM_WITH_CODE"
  }

  # Make sure email sending is enabled
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Update the client to allow user signup
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
}

# User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name         = "openmetabolics-app"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_CUSTOM_AUTH"
  ]
}

# Output the important values
output "cognito_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.client.id
} 