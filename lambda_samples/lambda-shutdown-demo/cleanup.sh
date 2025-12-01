#!/bin/bash
set -e

echo "Cleaning up Lambda Lifecycle Demo resources..."
echo ""

echo "1. Deleting API Gateway..."
aws apigateway delete-rest-api --rest-api-id 2x9v8apo48 --region us-east-1 2>/dev/null || echo "   API already deleted"

echo "2. Deleting Lambda functions..."
aws lambda delete-function --function-name lambda-authorizer-demo --region us-east-1 2>/dev/null || echo "   Authorizer already deleted"
aws lambda delete-function --function-name lambda-target-demo --region us-east-1 2>/dev/null || echo "   Target already deleted"
aws lambda delete-function --function-name lambda-shutdown-demo --region us-east-1 2>/dev/null || echo "   Demo already deleted"

echo "3. Deleting Lambda Layer..."
aws lambda delete-layer-version --layer-name lambda-shutdown-extension --version-number 1 --region us-east-1 2>/dev/null || echo "   Layer already deleted"

echo "4. Deleting DynamoDB table..."
aws dynamodb delete-table --table-name lambda-state-events --region us-east-1 2>/dev/null || echo "   Table already deleted"

echo "5. Waiting for logs..."
sleep 5

echo "6. Deleting CloudWatch Log Groups..."
aws logs delete-log-group --log-group-name /aws/lambda/lambda-authorizer-demo --region us-east-1 2>/dev/null || echo "   Authorizer logs deleted"
aws logs delete-log-group --log-group-name /aws/lambda/lambda-target-demo --region us-east-1 2>/dev/null || echo "   Target logs deleted"
aws logs delete-log-group --log-group-name /aws/lambda/lambda-shutdown-demo --region us-east-1 2>/dev/null || echo "   Demo logs deleted"

echo "7. Deleting IAM policies..."
aws iam delete-role-policy --role-name lambda-shutdown-demo-role --policy-name DynamoDBAccess 2>/dev/null || echo "   Policy deleted"
aws iam detach-role-policy --role-name lambda-shutdown-demo-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || echo "   Policy detached"

echo "8. Deleting IAM role..."
aws iam delete-role --role-name lambda-shutdown-demo-role 2>/dev/null || echo "   Role deleted"

echo ""
echo "✅ AWS resources cleaned up!"
echo ""
echo "To delete local files: rm -rf ~/lambda-shutdown-demo"
