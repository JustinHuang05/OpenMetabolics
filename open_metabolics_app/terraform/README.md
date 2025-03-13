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
   - IAM roles and policies

5. **Apply the Changes**

   ```bash
   terraform apply
   ```

   When prompted, type `yes` to confirm the deployment.

6. **Update Flutter App**
   After deployment completes, you'll see the API Gateway endpoint URL in the outputs.
   Update your Flutter app's `_uploadCSVToServer` function in `lib/pages/home_page.dart`:

   ```dart
   final String lambdaEndpoint = "https://<your-api-id>.execute-api.us-east-1.amazonaws.com/dev/save-raw-sensor-data";
   ```

7. **Optional, destroy resources if needed**
   ```bash
      terraform destroy
      terraform init -reconfigure
      rm terraform.tfstate*
      terraform apply
   ```

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
