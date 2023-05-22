#!/bin/bash

# Prompt for variables
read -p "Enter the bucket name [terraform-state]: " BUCKET_NAME
BUCKET_NAME=${BUCKET_NAME:-"terraform-state"}

read -p "Enter the DynamoDB table name [terraform-state-lock]: " DYNAMODB_TABLE
DYNAMODB_TABLE=${DYNAMODB_TABLE:-"terraform-state-lock"}

read -p "Enter the AWS region [$(aws configure get region)]: " REGION
REGION=${REGION:-$(aws configure get region)}

# Prepend the account ID to the bucket name
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $REGION)
BUCKET_NAME="$ACCOUNT_ID-$BUCKET_NAME"

# Check if S3 bucket already exists
if aws s3api head-bucket --bucket $BUCKET_NAME --region $REGION >/dev/null 2>&1; then
    echo "Bucket '$BUCKET_NAME' already exists"

    # Check if versioning is enabled
    VERSIONING_STATUS=$(aws s3api get-bucket-versioning --bucket $BUCKET_NAME --query 'Status' --output text --region $REGION)
    if [ "$VERSIONING_STATUS" != "Enabled" ]; then
        aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled --region $REGION >/dev/null 2>&1
        echo "Versioning enabled on the existing bucket '$BUCKET_NAME'"
    else
        echo "Versioning already enabled on the existing bucket '$BUCKET_NAME'"
    fi
else
    if aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION >/dev/null 2>&1; then
        echo "Bucket $BUCKET_NAME created successfully"
        aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled --region $REGION >/dev/null 2>&1
        echo "Versioning enabled on the new bucket '$BUCKET_NAME'"
    else
        echo "Failed to create bucket '$BUCKET_NAME'"
        exit 1
    fi
fi

# Check if DynamoDB table already exists
if aws dynamodb describe-table --table-name $DYNAMODB_TABLE --region $REGION >/dev/null 2>&1; then
    echo "DynamoDB table $DYNAMODB_TABLE already exists"
else
    if aws dynamodb create-table --table-name $DYNAMODB_TABLE --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 --region $REGION >/dev/null 2>&1; then
        echo "DynamoDB table $DYNAMODB_TABLE created successfully"
    else
        echo "Failed to create DynamoDB table $DYNAMODB_TABLE"
        exit 1
    fi
fi
