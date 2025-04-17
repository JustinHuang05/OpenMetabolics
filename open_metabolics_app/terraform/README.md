# OpenMetabolics AWS Infrastructure

This directory contains the Terraform configuration for deploying the AWS infrastructure required for the OpenMetabolics application.

## Prerequisites

1. Install [Terraform](https://www.terraform.io/downloads.html) (version 1.0.0 or later)
2. Configure AWS credentials (either through AWS CLI or environment variables)
3. Install Node.js (for building the Lambda function)

## Directory Structure

```
terraform/
├── main.tf           # Main Terraform configuration
├── variables.tf      # Variable definitions
├── outputs.tf        # Output definitions
├── README.md         # This file
├── scripts/         # Scripts directory
│   └── build_and_push.sh  # Script to build and push Docker image
└── lambda/           # Lambda function code
    ├── index.js      # Lambda function implementation
    └── package.json  # Node.js dependencies
```

## Deployment Steps

1. **Configure AWS Credentials**

   To find this stuff go to IAM and make an access key

   ```bash
   aws configure
   # Enter your AWS Access Key ID
   # Enter your AWS Secret Access Key
   # Enter your default region (e.g., us-east-1)
   ```

2. **Prepare the Lambda Function**

   ```bash
   # Navigate to the terraform directory
   cd terraform

   # Install Lambda function dependencies
   cd lambda
   npm install
   cd ..
   ```

3. **Initialize Terraform**

   ```bash
   terraform init
   ```

4. **Review the Changes**

   ```bash
   terraform plan
   ```

   This will show you:

   - The DynamoDB table that will be created
   - The Lambda function and its configuration
   - The API Gateway setup
   - The ECR repository and Docker image build/push automation
   - IAM roles and policies

5. **Apply the Changes**

   ```bash
   terraform apply
   ```

   When prompted, type `yes` to confirm the deployment.

   The deployment process will:

   - Create all AWS resources
   - Build the Docker image for the energy expenditure service
   - Push the image to ECR
   - Deploy the ECS service with the new image

6. **Update Flutter App**
   After deployment completes, you'll see the API Gateway endpoint URL in the outputs.
   Update your Flutter app's `_uploadCSVToServer` function in `lib/pages/home_page.dart`:

   ```dart
   final String lambdaEndpoint = "https://<your-api-id>.execute-api.us-east-1.amazonaws.com/dev/save-raw-sensor-data";
   ```

7. **Importing Existing Resources**

   If you're using an existing AWS account where some resources were created outside of Terraform, you'll need to import them before running `terraform apply`. For example:

   ```bash
   # Import CloudWatch Log Group
   terraform import aws_cloudwatch_log_group.energy_expenditure /ecs/open-metabolics-energy-expenditure

   # Import Target Group
   terraform import aws_lb_target_group.energy_expenditure arn:aws:elasticloadbalancing:us-east-1:YOUR_ACCOUNT_ID:targetgroup/open-metabolics-ee-tg/YOUR_TARGET_GROUP_ID
   ```

   To find the ARN of an existing resource:

   1. Go to the AWS Console
   2. Navigate to the service (e.g., EC2 > Target Groups)
   3. Select the resource
   4. Look for the ARN in the details or tags section

   Note: In a new AWS account, you won't need to import resources as Terraform will create them from scratch.

8. **Optional, destroy resources if needed**
   ```bash
      terraform destroy
      terraform init -reconfigure
      rm terraform.tfstate*
      terraform apply
   ```

## Deploying from Scratch

If you need to completely redeploy the infrastructure from scratch, follow these steps:

1. **Destroy Existing Resources**

   ```bash
   terraform destroy
   ```

   When prompted, type `yes` to confirm the destruction of all resources.

2. **Clean Up Terraform State**

   ```bash
   rm terraform.tfstate*
   ```

3. **Reinitialize Terraform**

   ```bash
   terraform init -reconfigure
   ```

4. **Apply Infrastructure**

   ```bash
   terraform apply
   ```

   When prompted, type `yes` to confirm the creation of resources.

5. **Build and Push Docker Image**
   After the infrastructure is created, you need to build and push the Docker image:

   ```bash
   cd scripts
   ./build_and_push.sh
   cd ..
   ```

6. **Verify Deployment**

   - Check the ECS service status:
     ```bash
     aws ecs describe-services --cluster open-metabolics-cluster --services open-metabolics-energy-expenditure-service
     ```
   - Check the ALB health:
     ```bash
     aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names open-metabolics-ee-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
     ```

7. **Update Flutter App Configuration**
   After deployment, update the following in your Flutter app:
   - Update `ApiConfig.energyExpenditureServiceUrl` in `lib/config/api_config.dart` with the new ALB DNS name
   - Verify other API endpoints in `ApiConfig` are correct

Note: The Docker image build and push is not automated in the Terraform configuration because it's considered part of the application deployment process rather than infrastructure provisioning.

## Infrastructure Details

The deployment creates:

1. **DynamoDB Table**

   - Name: `RawSensorDataV3`
   - Partition Key: `Timestamp` (String)
   - Billing Mode: Pay-per-request

2. **Lambda Function**

   - Name: `save-raw-sensor-data`
   - Runtime: Node.js 18.x
   - Memory: 256MB
   - Timeout: 30 seconds
   - Environment Variables:
     - `DYNAMODB_TABLE`: Name of the DynamoDB table

3. **API Gateway**

   - Protocol: HTTP
   - Route: POST /save-raw-sensor-data
   - Integration: Lambda proxy integration

4. **IAM Roles and Policies**

   - Lambda execution role with permissions for:
     - DynamoDB PutItem
     - CloudWatch Logs

5. **Authentication**
   - make sure to replace client_id, and pool_id in amplify_config.dart

## Configuration

You can customize the deployment by creating a `terraform.tfvars` file with your desired values:

```hcl
aws_region = "us-east-1"
environment = "dev"
project_name = "open-metabolics"
dynamodb_table_name = "RawSensorDataV3"
```

## Testing the Deployment

1. **Test the API Endpoint**

   ```bash
   curl -X POST https://<your-api-id>.execute-api.us-east-1.amazonaws.com/dev/sensor-data \
     -H "Content-Type: application/json" \
     -d '{"csv_data": "Timestamp,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyroscope_X,Gyroscope_Y,Gyroscope_Z,Gyro_L2_Norm\n1.0,0.1,0.2,0.3,0.4,0.5,0.6,0.7"}'
   ```

2. **Check DynamoDB**

   - Open AWS Console
   - Navigate to DynamoDB
   - Check the `RawSensorDataV3` table for the inserted data

3. **Monitor Lambda**
   - Open AWS Console
   - Navigate to Lambda
   - Check the `save-raw-sensor-data` function's CloudWatch logs

## Updating the Lambda Function

If you need to update the Lambda function code:

1. Make your changes to `lambda/index.js`
2. Run `terraform apply` to deploy the changes

## Cleanup

To destroy all resources:

```bash
terraform destroy
might have to destroy load balancer and target group manually idk why
```

When prompted, type `yes` to confirm the destruction of resources.

## Security Notes

- The Lambda function has minimal IAM permissions, only allowing it to write to the DynamoDB table
- The API Gateway endpoint is public and requires no authentication
- Consider adding API key authentication if needed for production use

## Troubleshooting

1. If you see permission errors, ensure your AWS credentials have sufficient permissions
2. If the Lambda function fails to deploy, check the CloudWatch logs
3. If the DynamoDB table creation fails, ensure the table name is unique in your AWS account
4. If you get "Not Found" errors, verify the API Gateway endpoint URL and route path match exactly

## AWS SES Email Configuration

### Important: SES Production Access Required

Before deploying this application, you need to request production access for Amazon SES (Simple Email Service). This is a one-time setup that cannot be automated through Terraform.

1. Go to AWS Console > SES > Account Dashboard
2. Click "Request Production Access" or "Request Sending Limit Increase"
3. Fill out the form:
   - Select "SES Production Access"
   - Region: us-east-1
   - Limit: SES Sending Limits
   - New limit value: (e.g., 50,000 per day)
   - Use case description: User verification emails with Cognito
   - Mail type: Transactional

**Note:** Until production access is granted, SES will be in "sandbox" mode where:

- Both sender and recipient emails must be verified in SES
- Daily sending limits are restricted
- Only verified email addresses can receive emails

AWS typically responds to production access requests within 24-48 hours.

## Docker Image Automation

The deployment process includes automatic building and pushing of the Docker image:

1. The `scripts/build_and_push.sh` script handles:

   - Building the Docker image from the Dockerfile
   - Logging into ECR
   - Tagging the image
   - Pushing the image to ECR

2. The process is triggered automatically when:

   - The Dockerfile content changes
   - The build script content changes
   - A new deployment is initiated

3. To manually rebuild and push the image:
   ```bash
   ./scripts/build_and_push.sh
   ```
TLDR
1. build and push by running "./build_and_push.sh"
2. terraform apply (and wait for the new task to pop up)
