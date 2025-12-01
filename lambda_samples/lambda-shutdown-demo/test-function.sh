#!/bin/bash

echo "Testing Lambda function..."
echo ""

# Invoke the function
aws lambda invoke \
  --function-name lambda-shutdown-demo \
  --payload '{"test": "data"}' \
  --region us-east-1 \
  response.json

echo ""
echo "Response:"
cat response.json
echo ""
echo ""
echo "Check CloudWatch Logs for extension output:"
echo "aws logs tail /aws/lambda/lambda-shutdown-demo --follow --region us-east-1"
