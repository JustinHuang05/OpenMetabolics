# OpenMetabolics AWS Infrastructure - Terraform Documentation

This directory contains the Terraform configuration for deploying the complete AWS infrastructure required for the OpenMetabolics application. The infrastructure includes data storage, serverless functions, containerized services, authentication, networking, and more.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Infrastructure Components](#infrastructure-components)
- [Prerequisites](#prerequisites)
- [Setup Instructions](#setup-instructions)
- [Deployment Guide](#deployment-guide)
- [Configuration](#configuration)
- [File Structure](#file-structure)
- [Troubleshooting](#troubleshooting)
- [Maintenance & Updates](#maintenance--updates)

## Overview

The Terraform configuration provisions a complete serverless and containerized backend infrastructure for OpenMetabolics, including:

- **Data Storage**: Multiple DynamoDB tables for sensor data, user profiles, and processing status
- **Serverless Functions**: Lambda functions for API endpoints and data processing
- **Container Services**: ECS Fargate services for compute-intensive energy expenditure calculations
- **Authentication**: AWS Cognito user pool for user authentication and management
- **API Gateway**: HTTP API for exposing Lambda functions
- **Networking**: VPC, subnets, load balancers, and security groups
- **Message Queuing**: SQS queues for asynchronous job processing
- **Monitoring**: CloudWatch logs for application monitoring

## Architecture

```
┌─────────────────┐
│  Flutter App    │
└────────┬────────┘
         │
         ├───► API Gateway ────► Lambda Functions ────► DynamoDB
         │
         ├───► Cognito (Auth)
         │
         └───► Application Load Balancer ────► ECS Fargate (API Service)
                                              │
                                              └───► SQS Queue ────► ECS Fargate (Worker)
```

### Data Flow

1. **Sensor Data Collection**: Flutter app sends sensor data → API Gateway → Lambda → DynamoDB
2. **Energy Expenditure Processing**: API service receives processing request → SQS Queue → Worker service processes → Results stored in DynamoDB
3. **User Management**: Cognito handles authentication, user profiles stored in DynamoDB
4. **Query Operations**: Lambda functions query DynamoDB tables and return results via API Gateway

## Infrastructure Components

### 1. DynamoDB Tables

#### `RawSensorDataTable` (Raw Sensor Data)

- **Purpose**: Stores raw accelerometer and gyroscope sensor data from mobile devices
- **Key Schema**:
  - Partition Key: `SessionId` (String)
  - Sort Key: `Timestamp` (String)
  - Global Secondary Index: `UserEmailIndex` (UserEmail + Timestamp)
- **Billing**: Pay-per-request (on-demand)
- **Usage**: Primary storage for sensor readings before processing

#### `open-metabolics-energy-results` (Energy Expenditure Results)

- **Purpose**: Stores processed energy expenditure calculations
- **Key Schema**:
  - Partition Key: `SessionId` (String)
  - Sort Key: `Timestamp` (String)
  - Global Secondary Index: `UserEmailIndex` (UserEmail + Timestamp)
- **Billing**: Pay-per-request (on-demand)
- **Usage**: Final results after energy expenditure processing

#### `open-metabolics-user-profiles` (User Profiles)

- **Purpose**: Stores user profile information (age, weight, height, etc.)
- **Key Schema**:
  - Partition Key: `UserEmail` (String)
- **Billing**: Pay-per-request (on-demand)
- **Usage**: User demographic and physical data needed for calculations

#### `user_survey_responses` (Survey Responses)

- **Purpose**: Stores user survey/questionnaire responses
- **Key Schema**:
  - Partition Key: `SessionId` (String)
  - Sort Key: `Timestamp` (String)
  - Global Secondary Index: `UserEmailIndex` (UserEmail + Timestamp)
- **Billing**: Pay-per-request (on-demand)
- **Usage**: User feedback and survey data collection

#### `energy-expenditure-processing-status` (Processing Status)

- **Purpose**: Tracks the status of energy expenditure processing jobs
- **Key Schema**:
  - Partition Key: `SessionId` (String)
- **Billing**: Pay-per-request (on-demand)
- **Usage**: Job status tracking (pending, processing, completed, failed)

### 2. Lambda Functions

All Lambda functions use Node.js 18.x runtime and are exposed via API Gateway HTTP API.

#### `save-raw-sensor-data`

- **Purpose**: Receives and stores raw sensor CSV data from the Flutter app
- **Endpoint**: `POST /save-raw-sensor-data`
- **Memory**: 512MB
- **Timeout**: 60 seconds
- **Environment Variables**:
  - `DYNAMODB_TABLE`: Raw sensor data table name
- **Input**: JSON with `csv_data`, `user_email`, `session_id`
- **Output**: Success/error status

#### `process-energy-expenditure`

- **Purpose**: Triggers energy expenditure processing (sends job to SQS queue)
- **Endpoint**: `POST /process-energy-expenditure`
- **Memory**: 1024MB
- **Timeout**: 300 seconds (5 minutes)
- **Environment Variables**:
  - `RAW_SENSOR_TABLE`: Raw sensor data table name
  - `RESULTS_TABLE`: Energy results table name
- **Usage**: Initiates async processing workflow

#### `manage-user-profile`

- **Purpose**: Creates or updates user profile information
- **Endpoint**: `POST /manage-user-profile`
- **Memory**: 256MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `USER_PROFILES_TABLE`: User profiles table name
- **Input**: User email, age, weight, height, etc.

#### `get-user-profile`

- **Purpose**: Retrieves user profile information
- **Endpoint**: `POST /get-user-profile`
- **Memory**: 256MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `USER_PROFILES_TABLE`: User profiles table name

#### `get-past-sessions`

- **Purpose**: Retrieves list of past recording sessions for a user
- **Endpoint**: `POST /get-past-sessions`
- **Memory**: 256MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `RESULTS_TABLE`: Energy results table name

#### `get-past-sessions-summary`

- **Purpose**: Retrieves summary of past sessions (aggregated data)
- **Endpoint**: `POST /get-past-sessions-summary`
- **Memory**: 256MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `RESULTS_TABLE`: Energy results table name

#### `get-session-details`

- **Purpose**: Retrieves detailed information for a specific session
- **Endpoint**: `POST /get-session-details`
- **Memory**: 256MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `RESULTS_TABLE`: Energy results table name

#### `get-all-session-summaries`

- **Purpose**: Retrieves all session summaries with survey data
- **Endpoint**: `POST /get-all-session-summaries`
- **Memory**: 512MB
- **Timeout**: 60 seconds
- **Environment Variables**:
  - `RESULTS_TABLE`: Energy results table name
  - `SURVEY_TABLE`: Survey responses table name

#### `save-survey-response`

- **Purpose**: Saves user survey/questionnaire responses
- **Endpoint**: `POST /save-survey-response`
- **Memory**: 256MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `SURVEY_TABLE`: Survey responses table name

#### `get-survey-response`

- **Purpose**: Retrieves survey responses for a session
- **Endpoint**: `POST /get-survey-response`
- **Memory**: 256MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `SURVEY_TABLE`: Survey responses table name

#### `check-survey-responses`

- **Purpose**: Checks if survey responses exist for a user/session
- **Endpoint**: `POST /check-survey-responses`
- **Memory**: 256MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `SURVEY_TABLE`: Survey responses table name

### 3. API Gateway

- **Type**: HTTP API (API Gateway v2)
- **Protocol**: HTTP
- **Stage**: `dev` (configurable via `environment` variable)
- **Auto-deploy**: Enabled (deploys automatically on changes)
- **Routes**: All Lambda functions are exposed as POST endpoints
- **Base URL Format**: `https://<api-id>.execute-api.<region>.amazonaws.com/<stage>`

### 4. AWS Cognito (Authentication)

#### User Pool: `openmetabolics-users`

- **Purpose**: User authentication and management
- **Features**:
  - Email/password authentication
  - Email verification required
  - Password policy: minimum 8 characters, requires uppercase, lowercase, numbers, and symbols
- **Attributes**:
  - `email` (required, verified)
  - `given_name` (required, first name)
  - `family_name` (required, last name)
- **Email Configuration**:
  - Sender: `justinhuang@seas.harvard.edu` (via SES)
  - Account type: Developer (uses SES for sending)
- **Client**: `openmetabolics-app` with multiple auth flows enabled

**Important**: Update `amplify_config.dart` with the pool ID and client ID after deployment.

### 5. Amazon SES (Email Service)

- **Purpose**: Sends verification emails for Cognito
- **Verified Email**: `justinhuang@seas.harvard.edu`
- **Status**: Must request production access for production use
- **Sandbox Mode**: In sandbox mode, only verified email addresses can receive emails

### 6. ECS Fargate Services

#### API Service: `open-metabolics-energy-expenditure-service`

- **Purpose**: REST API for energy expenditure processing requests
- **Container**: Docker image from ECR
- **CPU**: 1024 (1 vCPU)
- **Memory**: 2048 MB (2 GB)
- **Network**: Public subnets with public IPs
- **Load Balancer**: Application Load Balancer (ALB)
- **Environment Variables**:
  - `SERVICE_TYPE=api`
  - DynamoDB table names
  - SQS queue URL
- **Health Check**: `/health` endpoint on port 80

#### Worker Service: `energy-expenditure-worker`

- **Purpose**: Processes energy expenditure jobs from SQS queue
- **Container**: Same Docker image as API service (different `SERVICE_TYPE`)
- **CPU**: 256 (0.25 vCPU)
- **Memory**: 512 MB
- **Network**: Private subnets (no public IP)
- **Environment Variables**:
  - `SERVICE_TYPE=worker`
  - DynamoDB table names
  - SQS queue URL
- **Scaling**: 1 task (can be scaled via `desired_count`)

### 7. Amazon ECR (Container Registry)

- **Repository**: `open-metabolics-energy-expenditure-service`
- **Purpose**: Stores Docker images for ECS services
- **Lifecycle Policy**: Keeps last 30 images, deletes older ones
- **Tags**: `latest`, `api`, `worker`
- **Build**: Automated via `null_resource` when Dockerfile or source files change

### 8. SQS Queues

#### Processing Queue: `energy-expenditure-processing-queue`

- **Purpose**: Queue for energy expenditure processing jobs
- **Visibility Timeout**: 26,400 seconds (7 hours 20 minutes) - allows long-running jobs
- **Message Retention**: 24 hours
- **Long Polling**: 20 seconds
- **Dead Letter Queue**: Failed messages (after 3 retries) go to DLQ

#### Dead Letter Queue: `energy-expenditure-processing-dlq`

- **Purpose**: Stores failed processing jobs for investigation
- **Message Retention**: 14 days
- **Usage**: Manual review and reprocessing of failed jobs

### 9. Networking (VPC)

#### VPC: `10.0.0.0/16`

- **DNS**: Enabled for hostnames and resolution
- **Purpose**: Isolated network for AWS resources

#### Public Subnets

- **Subnet 1**: `10.0.1.0/24` (Availability Zone A)
- **Subnet 2**: `10.0.4.0/24` (Availability Zone B)
- **Usage**: Application Load Balancer, API service (ECS tasks with public IPs)
- **Internet Gateway**: Direct internet access

#### Private Subnets

- **Subnet 1**: `10.0.2.0/24` (Availability Zone A)
- **Subnet 2**: `10.0.3.0/24` (Availability Zone B)
- **Usage**: Worker service (ECS tasks without public IPs)
- **NAT Gateway**: Outbound internet access for pulling Docker images

#### Security Groups

- **ALB Security Group**: Allows HTTP (port 80) from internet
- **ECS Tasks Security Group**: Allows HTTP (port 80) from ALB, allows all outbound traffic

### 10. Application Load Balancer (ALB)

- **Name**: `open-metabolics-ee-lb`
- **Type**: Application Load Balancer (Layer 7)
- **Scheme**: Internet-facing
- **Listener**: HTTP on port 80
- **Target Group**: Health checks on `/health` endpoint
- **Health Check**:
  - Path: `/health`
  - Interval: 60 seconds
  - Timeout: 30 seconds
  - Healthy threshold: 2 consecutive successes
  - Unhealthy threshold: 10 consecutive failures

### 11. IAM Roles & Policies

#### Lambda Execution Role

- **Permissions**: DynamoDB (all tables), CloudWatch Logs
- **Used By**: All Lambda functions

#### ECS Task Execution Role

- **Permissions**: ECR (pull images), CloudWatch Logs
- **Used By**: ECS tasks for pulling images and logging

#### ECS Task Role

- **Permissions**: DynamoDB (read/write), SQS (send/receive/delete messages)
- **Used By**: ECS tasks for application operations

### 12. CloudWatch Logs

- **API Service Logs**: `/ecs/open-metabolics-energy-expenditure`
- **Worker Service Logs**: `/ecs/energy-expenditure-worker`
- **Retention**: 30 days
- **Purpose**: Application logs, debugging, monitoring

## Prerequisites

Before deploying, ensure you have:

1. **Terraform** (version 1.0.0 or later)

   ```bash
   terraform --version
   ```

2. **AWS CLI** configured with credentials

   ```bash
   aws configure
   ```

3. **Docker** (for building container images)

   ```bash
   docker --version
   ```

4. **Node.js** (for Lambda function dependencies)

   ```bash
   node --version
   ```

5. **AWS Account** with appropriate permissions (see IAM setup below)

## Setup Instructions

### Step 1: Configure IAM Permissions

Before deploying, you need to create an IAM user with the required permissions.

1. **Create IAM User**:

   - Go to AWS Console → IAM → Users
   - Click "Create user"
   - Enter username (e.g., `terraform-deployer`)
   - Select "Access key - Programmatic access"
   - **Save the Access Key ID and Secret Access Key** (you'll only see the secret once!)

2. **Create IAM Policy**:

   - Go to AWS Console → IAM → Policies
   - Click "Create policy"
   - Choose "JSON" tab
   - Copy and paste contents from `terraform_user_policy.json`
   - Click "Next"
   - Name: `OpenMetabolicsTerraformDeployment`
   - Click "Create policy"

3. **Attach Policy to User**:

   - Go to IAM → Users → Select your user
   - Click "Add permissions" → "Attach policies directly"
   - Search for `OpenMetabolicsTerraformDeployment`
   - Select and click "Add permissions"

4. **Configure AWS Credentials**:
   ```bash
   aws configure
   # Enter Access Key ID
   # Enter Secret Access Key
   # Enter region (e.g., us-east-1)
   # Enter output format (json or leave blank)
   ```

### Step 2: Request SES Production Access

**Important**: AWS SES starts in sandbox mode. For production use:

1. Go to AWS Console → SES → Account Dashboard
2. Click "Request Production Access" or "Request Sending Limit Increase"
3. Fill out the form:
   - **Type**: SES Production Access
   - **Region**: us-east-1 (or your region)
   - **Use case**: "User verification emails with Cognito"
   - **Mail type**: Transactional
   - **Daily sending limit**: Request appropriate limit (e.g., 50,000)
4. Submit and wait for approval (typically 24-48 hours)

**Sandbox Mode Limitations**:

- Only verified email addresses can receive emails
- Limited daily sending quota
- Both sender and recipient must be verified

### Step 3: Prepare Lambda Functions

The Lambda functions are automatically packaged by Terraform, but you may need to install dependencies:

```bash
cd terraform/lambda
npm install
cd ..
```

## Deployment Guide

### Initial Deployment

1. **Navigate to Terraform Directory**:

   ```bash
   cd terraform
   ```

2. **Initialize Terraform**:

   ```bash
   terraform init
   ```

   This downloads required providers and modules.

3. **Review Planned Changes**:

   ```bash
   terraform plan
   ```

   Review the output to see what resources will be created.

4. **Apply Configuration**:

   ```bash
   terraform apply
   ```

   Type `yes` when prompted to confirm.

   **Note**: The first deployment will:

   - Create all AWS resources
   - Build and push Docker image to ECR (this may take several minutes)
   - Deploy ECS services
   - Take approximately 10-15 minutes

5. **Save Outputs**:
   After deployment completes, Terraform will output:

   - API Gateway endpoint URL
   - Cognito Pool ID
   - Cognito Client ID
   - ALB DNS name

6. **Update Flutter App Configuration**:
   - Update `lib/config/api_config.dart` with the ALB DNS name
   - Update `lib/auth/amplify_config.dart` with Cognito Pool ID and Client ID

### Configuration Variables

You can customize the deployment by creating a `terraform.tfvars` file:

```hcl
aws_region = "us-east-1"
environment = "dev"
project_name = "open-metabolics"
dynamodb_table_name = "RawSensorDataTable"
```

Or pass variables via command line:

```bash
terraform apply -var="aws_region=us-west-2" -var="environment=prod"
```

### Updating Infrastructure

To update resources:

1. **Modify Terraform files** as needed
2. **Review changes**:
   ```bash
   terraform plan
   ```
3. **Apply changes**:
   ```bash
   terraform apply
   ```

**Note**: Changes to Lambda functions or Docker images will trigger automatic updates.

### Updating Lambda Functions

1. Edit the Lambda function code in `terraform/lambda/`
2. Run `terraform apply`
3. Terraform automatically packages and deploys the updated code

### Updating Docker Images

The Docker image is automatically rebuilt and pushed when:

- The Dockerfile changes (`fargate/Dockerfile`)
- The build script changes (`scripts/build_and_push.sh`)
- Source files change (worker or API Python files)

To manually rebuild and push:

```bash
cd terraform/scripts
./build_and_push.sh
```

Then force a new ECS deployment:

```bash
aws ecs update-service \
  --cluster open-metabolics-cluster \
  --service open-metabolics-energy-expenditure-service \
  --force-new-deployment
```

### Destroying Infrastructure

**Warning**: This will delete all resources!

```bash
terraform destroy
```

Type `yes` when prompted.

**Note**: Some resources (like load balancers) may need to be deleted manually if Terraform encounters issues.

### Complete Redeployment

If you need to start from scratch:

```bash
# 1. Destroy existing resources
terraform destroy

# 2. Remove state files
rm terraform.tfstate*

# 3. Reinitialize
terraform init -reconfigure

# 4. Apply
terraform apply
```

## Configuration

### Variables (variables.tf)

- **`aws_region`** (default: `"us-east-1"`): AWS region for all resources
- **`environment`** (default: `"dev"`): Environment name (affects naming and tags)
- **`project_name`** (default: `"open-metabolics"`): Project identifier for resource names
- **`dynamodb_table_name`** (default: `"RawSensorDataTable"`): Name of the main sensor data table

### Outputs (outputs.tf)

After deployment, Terraform outputs:

- **`api_endpoint`**: API Gateway base URL
- **`dynamodb_table_name`**: Raw sensor data table name
- **`lambda_function_name`**: Main Lambda function name
- **`cognito_pool_id`**: Cognito User Pool ID
- **`cognito_client_id`**: Cognito App Client ID
- **`energy_expenditure_service_url`**: ALB DNS name

View outputs:

```bash
terraform output
```

## File Structure

```
terraform/
├── main.tf                    # Main Terraform configuration (all resources)
├── variables.tf                # Variable definitions
├── outputs.tf                 # Output values
├── README.md                  # This file
├── terraform_user_policy.json # IAM policy for Terraform user
├── terraform.tfstate          # Terraform state (auto-generated)
├── terraform.tfstate.backup   # State backup (auto-generated)
├── .terraform/                # Terraform cache (auto-generated)
├── .terraform.lock.hcl        # Provider lock file
├── lambda/                    # Lambda function source code
│   ├── index.js               # Main sensor data handler
│   ├── process_energy_expenditure.js
│   ├── user_profile.js
│   ├── get_user_profile.js
│   ├── get_past_sessions.js
│   ├── get_past_sessions_summary.js
│   ├── get_session_details.js
│   ├── get_all_session_summaries.js
│   ├── save_survey_response.js
│   ├── get_survey_response.js
│   ├── check_survey_responses.js
│   ├── package.json           # Node.js dependencies
│   └── *.zip                  # Packaged Lambda functions (auto-generated)
└── scripts/
    └── build_and_push.sh      # Docker build and push script
```

## Troubleshooting

### Common Issues

1. **Permission Errors**

   - **Error**: "AccessDenied" or "UnauthorizedOperation"
   - **Solution**: Verify IAM user has the policy attached, check AWS credentials

2. **Lambda Function Fails to Deploy**

   - **Error**: "Error creating Lambda function"
   - **Solution**: Check CloudWatch logs, verify Lambda code syntax, ensure IAM role exists

3. **ECS Service Won't Start**

   - **Error**: Tasks stuck in "PENDING" or "STOPPED"
   - **Solution**:
     - Check CloudWatch logs for container errors
     - Verify Docker image exists in ECR
     - Check security group allows traffic
     - Verify task execution role has ECR permissions

4. **ALB Health Checks Failing**

   - **Error**: Targets unhealthy
   - **Solution**:
     - Verify `/health` endpoint exists and returns 200
     - Check security groups allow traffic from ALB to tasks
     - Review ECS task logs

5. **Docker Build Fails**

   - **Error**: "Cannot connect to Docker daemon" or build errors
   - **Solution**:
     - Ensure Docker is running
     - Check Dockerfile syntax
     - Verify build script has execute permissions: `chmod +x scripts/build_and_push.sh`

6. **Cognito Email Not Sending**

   - **Error**: Verification emails not received
   - **Solution**:
     - Check SES is in production mode (not sandbox)
     - Verify sender email is verified in SES
     - Check Cognito email configuration

7. **API Gateway Returns 502/503**

   - **Error**: Bad Gateway or Service Unavailable
   - **Solution**:
     - Check Lambda function logs
     - Verify Lambda function is deployed and not errored
     - Check API Gateway integration configuration

8. **DynamoDB Table Creation Fails**
   - **Error**: "Table already exists" or "Invalid table name"
   - **Solution**:
     - Table name must be unique in region
     - Check table name doesn't contain invalid characters
     - If importing existing table, use `terraform import`

### Debugging Commands

**Check ECS Service Status**:

```bash
aws ecs describe-services \
  --cluster open-metabolics-cluster \
  --services open-metabolics-energy-expenditure-service
```

**Check ALB Target Health**:

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names open-metabolics-ee-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)
```

**View Lambda Logs**:

```bash
aws logs tail /aws/lambda/save-raw-sensor-data --follow
```

**View ECS Logs**:

```bash
aws logs tail /ecs/open-metabolics-energy-expenditure --follow
```

**Test API Endpoint**:

```bash
curl -X POST https://<api-id>.execute-api.us-east-1.amazonaws.com/dev/save-raw-sensor-data \
  -H "Content-Type: application/json" \
  -d '{"csv_data": "Timestamp,Accelerometer_X\n1.0,0.1", "user_email": "test@example.com", "session_id": "test-session"}'
```

## Maintenance & Updates

### Regular Maintenance Tasks

1. **Monitor CloudWatch Logs**: Check for errors regularly
2. **Review Costs**: Monitor AWS billing dashboard
3. **Update Docker Images**: Rebuild when code changes
4. **Rotate Credentials**: Periodically rotate AWS access keys
5. **Backup Important Data**: Consider DynamoDB backups for production

### Scaling Considerations

**Lambda Functions**:

- Automatically scale based on request volume
- No manual scaling needed

**ECS Services**:

- **API Service**: Currently 1 task. Increase `desired_count` for higher traffic
- **Worker Service**: Currently 1 task. Increase for parallel processing

**DynamoDB**:

- Uses on-demand billing (auto-scaling)
- No manual scaling needed

**ALB**:

- Automatically handles traffic distribution
- No manual scaling needed

### Cost Optimization

- **DynamoDB**: On-demand billing (pay only for what you use)
- **Lambda**: Pay per request and compute time
- **ECS Fargate**: Pay per vCPU and memory allocated
- **ALB**: Fixed hourly cost + data transfer
- **NAT Gateway**: Fixed hourly cost (consider removing if not needed)

**Tip**: Consider using AWS Cost Explorer to monitor spending.

### Security Best Practices

1. **Never commit credentials**: Use AWS Secrets Manager or environment variables
2. **Limit IAM permissions**: Follow principle of least privilege
3. **Enable CloudWatch alarms**: Monitor for unusual activity
4. **Use HTTPS**: Consider adding SSL certificate to ALB for production
5. **Regular updates**: Keep Terraform and providers updated
6. **Network security**: Review security group rules regularly

## Additional Resources

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS DynamoDB Documentation](https://docs.aws.amazon.com/dynamodb/)
- [AWS Cognito Documentation](https://docs.aws.amazon.com/cognito/)

---

**Last Updated**: See git history for latest changes.

**Questions or Issues?**: Check the troubleshooting section or review Terraform documentation.
