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

# Setup OpenID Connect for GitHub
OPEN_ID_PROVIDER_ARN="arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"

# Check if OpenID Connect provider already exists
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn $OPEN_ID_PROVIDER_ARN --region $REGION >/dev/null 2>&1; then
    echo "OpenID Connect provider '$OPEN_ID_PROVIDER_ARN' already exists"
else
    if aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com --thumbprint-list 6938FD4D98BAB03FAADB97B34396831E3780AEA1 --region $REGION >/dev/null 2>&1; then
        echo "OpenID Connect provider created successfully"
    else
        echo "Failed to create OpenID Connect provider"
        exit 1
    fi
fi

# Create the Role for OIDC
ROLE_NAME="OIDC"
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# Prompt for variables for OIDC Role
read -p "Enter the repository owner/organization [MisterCWalker]: " REPO_OWNER
REPO_OWNER=${REPO_OWNER:-"MisterCWalker"}

read -p "Enter the repository name [TerraformSnykTest]: " REPO
REPO=${REPO:-"TerraformSnykTest"}

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": {
              "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
              "StringLike": {
                "token.actions.githubusercontent.com:sub": "repo:$REPO_OWNER/$REPO:*"
              },
              "StringEquals": {
                  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
              }
          }
      }
  ]
}
EOF
)

# Check if the role already exists
if aws iam get-role --role-name $ROLE_NAME --region $REGION >/dev/null 2>&1; then
    echo "Role '$ROLE_NAME' already exists"
else
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document "$TRUST_POLICY" --region $REGION
    echo "Role '$ROLE_NAME' created successfully"
fi

# Check if the policy is already attached to the role
if aws iam list-attached-role-policies --role-name $ROLE_NAME --region $REGION --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN']" | grep $POLICY_ARN >/dev/null 2>&1; then
    echo "Policy '$POLICY_ARN' is already attached to '$ROLE_NAME'"
else
    # Attach the policy to the role
    if aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN --region $REGION >/dev/null 2>&1; then
        echo "Policy '$POLICY_ARN' attached successfully to '$ROLE_NAME'"
    else
        echo "Failed to attach policy '$POLICY_ARN' to '$ROLE_NAME'"
        exit 1
    fi
fi

# Get OIDC Role Arn
ROLE_ARN=$(aws iam get-role --role-name OIDC --query 'Role.Arn' --output text)

# Display bucket and role outputs for GitHub Variables
echo "Bucket = '$BUCKET_NAME'"
echo "Role Arn = '$ROLE_ARN'"

# Question for setting the GitHub secret BUCKET_TF_STATE
echo "Do you want to set the secret BUCKET_TF_STATE to the value of $BUCKET_NAME in the repository $REPO_OWNER/$REPO? [Y/n]"
read response

if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
then
    echo -n "$BUCKET_NAME" | gh secret set BUCKET_TF_STATE -R "$REPO_OWNER/$REPO"
    echo "Secret has been set."
else
    echo "Operation cancelled."
fi

# Question for setting the GitHub variable AWS_ROLE
echo "Do you want to set the variable AWS_ROLE to the value of $ROLE_ARN in the repository $REPO_OWNER/$REPO? [Y/n]"
read response

if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
then
    echo -n "$ROLE_ARN" | gh variable set AWS_ROLE -R "$REPO_OWNER/$REPO"
    echo "Variable has been set."
else
    echo "Operation cancelled."
fi
