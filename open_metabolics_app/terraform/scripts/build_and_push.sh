#!/bin/bash

# Exit on error
set -e

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

# Get the workspace root directory (parent of terraform directory)
WORKSPACE_ROOT="/Users/justinhuang/Documents/Developer/OpenMetabolics/open_metabolics_app"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build the Docker image with explicit platform
cd $WORKSPACE_ROOT/fargate
docker build --platform linux/amd64 -t open-metabolics-energy-expenditure-service .

# Tag the image for both API and worker services
docker tag open-metabolics-energy-expenditure-service:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/open-metabolics-energy-expenditure-service:latest
docker tag open-metabolics-energy-expenditure-service:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/open-metabolics-energy-expenditure-service:api
docker tag open-metabolics-energy-expenditure-service:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/open-metabolics-energy-expenditure-service:worker

# Push all tags
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/open-metabolics-energy-expenditure-service:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/open-metabolics-energy-expenditure-service:api
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/open-metabolics-energy-expenditure-service:worker

echo "Docker images built and pushed successfully!"
echo "Latest, API, and worker tags are now available in ECR" 