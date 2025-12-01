#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Deploying Lambda Shutdown Tracking Demo to account $ACCOUNT_ID in $REGION"

# Create IAM role
echo "Creating IAM role..."
aws iam create-role \
  --role-name lambda-shutdown-demo-role \
  --assume-role-policy-document file://trust-policy.json \
  --region $REGION 2>/dev/null || echo "Role already exists"

aws iam attach-role-policy \
  --role-name lambda-shutdown-demo-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  --region $REGION

aws iam put-role-policy \
  --role-name lambda-shutdown-demo-role \
  --policy-name DynamoDBAccess \
  --policy-document file://dynamodb-policy.json \
  --region $REGION

echo "Waiting for IAM role to propagate..."
sleep 10

# Create DynamoDB table
echo "Creating DynamoDB table..."
aws dynamodb create-table \
  --table-name lambda-state-events \
  --attribute-definitions AttributeName=eventId,AttributeType=S AttributeName=timestamp,AttributeType=N \
  --key-schema AttributeName=eventId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes "IndexName=timestamp-index,KeySchema=[{AttributeName=timestamp,KeyType=HASH}],Projection={ProjectionType=ALL}" \
  --region $REGION 2>/dev/null || echo "Table already exists"

aws dynamodb update-time-to-live \
  --table-name lambda-state-events \
  --time-to-live-specification "Enabled=true,AttributeName=ttl" \
  --region $REGION

# Package and deploy extension layer
echo "Creating Lambda extension layer..."
./package.sh
aws lambda publish-layer-version \
  --layer-name lambda-shutdown-extension \
  --zip-file fileb://extension-layer.zip \
  --compatible-runtimes python3.9 python3.10 python3.11 python3.12 \
  --region $REGION

LAYER_ARN=$(aws lambda list-layer-versions \
  --layer-name lambda-shutdown-extension \
  --query 'LayerVersions[0].LayerVersionArn' \
  --output text \
  --region $REGION)

# Deploy Lambda functions
echo "Deploying Lambda functions..."
zip -q authorizer.zip authorizer_function.py
zip -q target.zip target_function.py

aws lambda create-function \
  --function-name lambda-authorizer-demo \
  --runtime python3.12 \
  --role arn:aws:iam::$ACCOUNT_ID:role/lambda-shutdown-demo-role \
  --handler authorizer_function.lambda_handler \
  --zip-file fileb://authorizer.zip \
  --region $REGION 2>/dev/null || \
aws lambda update-function-code \
  --function-name lambda-authorizer-demo \
  --zip-file fileb://authorizer.zip \
  --region $REGION

aws lambda create-function \
  --function-name lambda-target-demo \
  --runtime python3.12 \
  --role arn:aws:iam::$ACCOUNT_ID:role/lambda-shutdown-demo-role \
  --handler target_function.lambda_handler \
  --zip-file fileb://target.zip \
  --layers $LAYER_ARN \
  --region $REGION 2>/dev/null || \
aws lambda update-function-code \
  --function-name lambda-target-demo \
  --zip-file fileb://target.zip \
  --region $REGION

# Create API Gateway
echo "Creating API Gateway..."
API_ID=$(aws apigateway create-rest-api \
  --name lambda-lifecycle-api \
  --query 'id' \
  --output text \
  --region $REGION 2>/dev/null || cat api-id.txt)

echo $API_ID > api-id.txt

ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[0].id' \
  --output text \
  --region $REGION)

AUTHORIZER_ID=$(aws apigateway create-authorizer \
  --rest-api-id $API_ID \
  --name lambda-authorizer \
  --type REQUEST \
  --authorizer-uri arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$REGION:$ACCOUNT_ID:function:lambda-authorizer-demo/invocations \
  --identity-source method.request.header.Authorization \
  --query 'id' \
  --output text \
  --region $REGION 2>/dev/null || echo "Authorizer exists")

RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part hello \
  --query 'id' \
  --output text \
  --region $REGION 2>/dev/null || \
aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?path==`/hello`].id' \
  --output text \
  --region $REGION)

aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --authorization-type CUSTOM \
  --authorizer-id $AUTHORIZER_ID \
  --region $REGION 2>/dev/null || echo "Method exists"

aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$REGION:$ACCOUNT_ID:function:lambda-target-demo/invocations \
  --region $REGION 2>/dev/null || echo "Integration exists"

aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod \
  --region $REGION

# Add Lambda permissions
aws lambda add-permission \
  --function-name lambda-authorizer-demo \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*" \
  --region $REGION 2>/dev/null || echo "Permission exists"

aws lambda add-permission \
  --function-name lambda-target-demo \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*" \
  --region $REGION 2>/dev/null || echo "Permission exists"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "API Endpoint: https://$API_ID.execute-api.$REGION.amazonaws.com/prod/hello"
echo ""
echo "Test with: curl https://$API_ID.execute-api.$REGION.amazonaws.com/prod/hello"
