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

# DynamoDB Table for raw sensor data
resource "aws_dynamodb_table" "raw_sensor_data" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "SessionId"
  range_key      = "Timestamp"
  stream_enabled = false

  attribute {
    name = "SessionId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  attribute {
    name = "UserEmail"
    type = "S"
  }

  global_secondary_index {
    name               = "UserEmailIndex"
    hash_key           = "UserEmail"
    range_key          = "Timestamp"
    projection_type    = "ALL"
    write_capacity     = 5
    read_capacity      = 5
  }

  tags = {
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# DynamoDB Table for energy expenditure results
resource "aws_dynamodb_table" "energy_expenditure_results" {
  name           = "${var.project_name}-energy-results"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "SessionId"
  range_key      = "Timestamp"
  stream_enabled = false

  attribute {
    name = "SessionId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  attribute {
    name = "UserEmail"
    type = "S"
  }

  global_secondary_index {
    name               = "UserEmailIndex"
    hash_key           = "UserEmail"
    range_key          = "Timestamp"
    projection_type    = "ALL"
    write_capacity     = 5
    read_capacity      = 5
  }

  tags = {
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# DynamoDB Table for user profiles
resource "aws_dynamodb_table" "user_profiles" {
  name           = "${var.project_name}-user-profiles"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "UserEmail"
  stream_enabled = false

  attribute {
    name = "UserEmail"
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
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.raw_sensor_data.arn,
          "${aws_dynamodb_table.raw_sensor_data.arn}/index/UserEmailIndex",
          aws_dynamodb_table.energy_expenditure_results.arn,
          "${aws_dynamodb_table.energy_expenditure_results.arn}/index/UserEmailIndex",
          aws_dynamodb_table.user_profiles.arn
        ]
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

# Archive Lambda function code for energy expenditure processing
data "archive_file" "energy_expenditure_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/process_energy_expenditure.js"
  output_path = "${path.module}/lambda/energy_expenditure_function.zip"
}

# Lambda Function for energy expenditure processing
resource "aws_lambda_function" "energy_expenditure_handler" {
  filename         = data.archive_file.energy_expenditure_zip.output_path
  function_name    = "process-energy-expenditure"
  role            = aws_iam_role.lambda_role.arn
  handler         = "process_energy_expenditure.handler"
  runtime         = "nodejs18.x"
  timeout         = 300  # 5 minutes
  memory_size     = 1024
  source_code_hash = data.archive_file.energy_expenditure_zip.output_base64sha256

  environment {
    variables = {
      RAW_SENSOR_TABLE = aws_dynamodb_table.raw_sensor_data.name
      RESULTS_TABLE    = aws_dynamodb_table.energy_expenditure_results.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# API Gateway integration for energy expenditure processing
resource "aws_apigatewayv2_integration" "energy_expenditure_integration" {
  api_id           = aws_apigatewayv2_api.lambda_api.id
  integration_type = "AWS_PROXY"

  connection_type    = "INTERNET"
  description       = "Energy expenditure processing Lambda integration"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.energy_expenditure_handler.invoke_arn
}

resource "aws_apigatewayv2_route" "energy_expenditure_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "POST /process-energy-expenditure"
  target    = "integrations/${aws_apigatewayv2_integration.energy_expenditure_integration.id}"
}

resource "aws_lambda_permission" "energy_expenditure_api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.energy_expenditure_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}

# First, add SES configuration (add this before the user pool)
resource "aws_ses_email_identity" "sender" {
  email = "justin.sy.huang@gmail.com"
}

# Then update the user pool email configuration
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
    email_sending_account = "DEVELOPER"
    from_email_address    = "justin.sy.huang@gmail.com"
    source_arn           = aws_ses_email_identity.sender.arn
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

# Lambda Function for user profile management
resource "aws_lambda_function" "user_profile_handler" {
  filename         = data.archive_file.user_profile_zip.output_path
  function_name    = "manage-user-profile"
  role            = aws_iam_role.lambda_role.arn
  handler         = "user_profile.handler"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 256
  source_code_hash = data.archive_file.user_profile_zip.output_base64sha256

  environment {
    variables = {
      USER_PROFILES_TABLE = aws_dynamodb_table.user_profiles.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Archive Lambda function code for user profile management
data "archive_file" "user_profile_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/user_profile.js"
  output_path = "${path.module}/lambda/user_profile_function.zip"
}

# API Gateway integration for user profile management
resource "aws_apigatewayv2_integration" "user_profile_integration" {
  api_id           = aws_apigatewayv2_api.lambda_api.id
  integration_type = "AWS_PROXY"

  connection_type    = "INTERNET"
  description       = "User profile management Lambda integration"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.user_profile_handler.invoke_arn
}

resource "aws_apigatewayv2_route" "user_profile_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "POST /manage-user-profile"
  target    = "integrations/${aws_apigatewayv2_integration.user_profile_integration.id}"
}

resource "aws_lambda_permission" "user_profile_api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.user_profile_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}

# Archive Lambda function code for getting user profile
data "archive_file" "get_user_profile_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_user_profile.js"
  output_path = "${path.module}/lambda/get_user_profile_function.zip"
}

# Lambda Function for getting user profile
resource "aws_lambda_function" "get_user_profile_handler" {
  filename         = data.archive_file.get_user_profile_zip.output_path
  function_name    = "get-user-profile"
  role            = aws_iam_role.lambda_role.arn
  handler         = "get_user_profile.handler"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 256
  source_code_hash = data.archive_file.get_user_profile_zip.output_base64sha256

  environment {
    variables = {
      USER_PROFILES_TABLE = aws_dynamodb_table.user_profiles.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# API Gateway integration for getting user profile
resource "aws_apigatewayv2_integration" "get_user_profile_integration" {
  api_id           = aws_apigatewayv2_api.lambda_api.id
  integration_type = "AWS_PROXY"

  connection_type    = "INTERNET"
  description       = "Get user profile Lambda integration"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.get_user_profile_handler.invoke_arn
}

resource "aws_apigatewayv2_route" "get_user_profile_route" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "POST /get-user-profile"
  target    = "integrations/${aws_apigatewayv2_integration.get_user_profile_integration.id}"
}

resource "aws_lambda_permission" "get_user_profile_api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_user_profile_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}

# ECR Repository for Fargate service
resource "aws_ecr_repository" "energy_expenditure_service" {
  name = "${var.project_name}-energy-expenditure-service"
  force_delete = true
}

# Null resource to build and push Docker image
resource "null_resource" "docker_build_push" {
  depends_on = [aws_ecr_repository.energy_expenditure_service]

  triggers = {
    script_hash = filesha256("${path.module}/scripts/build_and_push.sh")
    dockerfile_hash = filesha256("${path.module}/../fargate/Dockerfile")
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/build_and_push.sh"
    working_dir = path.root
  }
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "energy_expenditure_service" {
  repository = aws_ecr_repository.energy_expenditure_service.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "energy_expenditure" {
  family                   = "${var.project_name}-energy-expenditure"
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                     = "1024"
  memory                  = "2048"
  execution_role_arn      = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "energy-expenditure"
      image     = "${aws_ecr_repository.energy_expenditure_service.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "RAW_SENSOR_TABLE"
          value = aws_dynamodb_table.raw_sensor_data.name
        },
        {
          name  = "RESULTS_TABLE"
          value = aws_dynamodb_table.energy_expenditure_results.name
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.energy_expenditure.name
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "energy_expenditure" {
  name              = "/ecs/${var.project_name}-energy-expenditure"
  retention_in_days = 30
}

# ECS Service
resource "aws_ecs_service" "energy_expenditure" {
  name            = "${var.project_name}-energy-expenditure-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.energy_expenditure.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.energy_expenditure.arn
    container_name   = "energy-expenditure"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.energy_expenditure]
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Role Policy for ECS Task Execution
resource "aws_iam_role_policy" "ecs_task_execution_role_policy" {
  name = "${var.project_name}-ecs-task-execution-role-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Role Policy for ECS Task
resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "${var.project_name}-ecs-task-role-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:PutItem"
        ]
        Resource = [
          aws_dynamodb_table.raw_sensor_data.arn,
          aws_dynamodb_table.energy_expenditure_results.arn
        ]
      }
    ]
  })
}

# Application Load Balancer
resource "aws_lb" "energy_expenditure" {
  name               = "open-metabolics-ee-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.alb.id]
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB Target Group
resource "aws_lb_target_group" "energy_expenditure" {
  name        = "open-metabolics-ee-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    interval            = 60
    matcher            = "200"
  }
}

# ALB Listener
resource "aws_lb_listener" "energy_expenditure" {
  load_balancer_arn = aws_lb.energy_expenditure.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.energy_expenditure.arn
  }
}

# Output the ALB DNS name
output "energy_expenditure_service_url" {
  value = aws_lb.energy_expenditure.dns_name
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Public Subnet 2
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}b"

  tags = {
    Name        = "${var.project_name}-public-subnet-2"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Private Subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project_name}-private-subnet"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Add a second private subnet in a different AZ
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "${var.project_name}-private-subnet-2"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Route Table Association for Public Subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Route Table Association for Public Subnet 2
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-nat-eip"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name        = "${var.project_name}-nat-gw"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Table for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.environment
    Project     = "OpenMetabolics"
  }
}

# Route Table Association for Private Subnet
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Add route table association for the second private subnet
resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
} 