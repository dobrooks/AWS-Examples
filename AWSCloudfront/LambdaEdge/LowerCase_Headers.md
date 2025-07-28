# Implementing High-Performance Header Normalization with AWS CloudFront Lambda@Edge
## by Don Brooks 

## Introduction

Amazon CloudFront is a fast content delivery network (CDN) service that securely delivers data, videos, applications, and APIs to customers globally with low latency and high transfer speeds. When combined with Lambda@Edge, it provides powerful capabilities to modify content and headers at the edge, closer to your users.

## The Challenge: Header Case Normalization at Scale

When dealing with HTTP headers in web applications, inconsistent header casing can cause issues with downstream services or client applications. Today, we'll explore how to implement a scalable Lambda@Edge function that normalizes response headers to lowercase while handling high traffic volumes.

## Solution Overview

Our solution will:
1. Intercept CloudFront responses
2. Convert all header names to lowercase
3. Maintain the original header values
4. Handle high transaction volumes
5. Include proper monitoring and error handling

## Implementation

### Core Function Code

```python
import json

def lambda_handler(event, context):
    try:
        # Get the response from the CloudFront event
        response = event['Records'][0]['cf']['response']
        headers = response['headers']

        # Create a new headers dictionary with lowercase names
        lowercase_headers = {}
        for header_name, header_value in headers.items():
            lowercase_name = header_name.lower()
            
            # Keep the original array of objects structure
            lowercase_headers[lowercase_name] = header_value
            
            # Update the 'key' property within each header value object
            for item in lowercase_headers[lowercase_name]:
                item['key'] = lowercase_name
                
            print(f"Processed {header_name} -> {lowercase_name}")
        
        # Example to Add an additional header
        lowercase_headers['x-extra-header'] = [{
            'key': 'x-extra-header',
            'value': 'extra-value'
        }]

        # Update the response headers
        response['headers'] = lowercase_headers
        response["status"] = str(response.get('status', '200'))
        response["statusDescription"] = response.get('statusDescription', "OK")

        print(f"Final headers : {json.dumps(response)}")            
        return response
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        return {
            'status': '500',
            'statusDescription': 'Internal Server Error',
            'headers': {
                'content-type': [{
                    'key': 'Content-Type',
                    'value': 'text/plain'
                }]
            },
            'body': 'An error occurred processing your request'
        }
```

## Setting Up the Infrastructure

### Lambda Execution Role

Create the following IAM role for your Lambda function:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  LambdaEdgeExecutionRole:
    Type: 'AWS::IAM::Role'
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - lambda.amazonaws.com
                - edgelambda.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Policies:
        - PolicyName: EdgeFunctionPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - 'logs:CreateLogGroup'
                  - 'logs:CreateLogStream'
                  - 'logs:PutLogEvents'
                Resource: 'arn:aws:logs:*:*:*'
```

## Deployment Steps

1. Create a new Lambda function in the US-East-1 region
2. Copy the code above into the function
3. Attach the created IAM role to the function
4. Publish a version of the Lambda function
5. Associate the function with your CloudFront distribution as a "Response Header" trigger

## Scaling and Performance Considerations

### Understanding Lambda@Edge Limits

- Viewer request/response: 10,000 RPS (Calculated at 10x Concurrency Limit)
- Origin request/response: 30 RPS
- Default regional concurrent execution limit: 1,000

### Increasing Concurrency Limits

To handle higher TPS:

1. Request a Service Quota increase through AWS Service Quotas console (Keep in mind that the limit is for ALL your lambda usage and not just the lambda@edge discussed here)
2. Configure Reserved Concurrency:
```bash
aws lambda put-function-concurrency \
    --function-name your-function-name \
    --reserved-concurrent-executions 100
```

3. Set up Provisioned Concurrency:
```bash
aws lambda put-provisioned-concurrency-config \
    --function-name your-function-name \
    --qualifier your-version \
    --provisioned-concurrent-executions 50
```

## Monitoring and Alerting

### CloudWatch Dashboard

Deploy this dashboard to monitor your function:

```yaml
Resources:
  LambdaDashboard:
    Type: 'AWS::CloudWatch::Dashboard'
    Properties:
      DashboardName: LambdaEdgeMetrics
      DashboardBody: !Sub |
        {
          "widgets": [
            {
              "type": "metric",
              "properties": {
                "metrics": [
                  ["AWS/Lambda", "Concurrent Executions"],
                  ["AWS/Lambda", "Errors"],
                  ["AWS/Lambda", "Duration"],
                  ["AWS/Lambda", "Throttles"]
                ],
                "period": 60,
                "stat": "Maximum",
                "region": "us-east-1",
                "title": "Lambda Performance Metrics"
              }
            }
          ]
        }
```

### Concurrency Alarms

Set up alerts for high concurrency:

```yaml
Resources:
  ConcurrencyAlarm:
    Type: 'AWS::CloudWatch::Alarm'
    Properties:
      AlarmName: LambdaConcurrencyAlarm
      MetricName: ConcurrentExecutions
      Namespace: AWS/Lambda
      Statistic: Maximum
      Period: 60
      EvaluationPeriods: 1
      Threshold: 800
      ComparisonOperator: GreaterThanThreshold
```

## Best Practices

1. **Monitor Performance**:
   - Watch concurrent executions
   - Track error rates
   - Monitor function duration
   - Set up alerts for throttling

2. **Cost Optimization**:
   - Use provisioned concurrency for predictable loads
   - Monitor CloudWatch Logs usage
   - Regular review of function performance

3. **Error Handling**:
   - Implement comprehensive error catching
   - Log errors appropriately
   - Return meaningful error responses

## Cost Considerations

When implementing this solution, consider:
- Lambda pricing per invocation and duration
- Provisioned concurrency costs
- CloudWatch Logs costs
- Data transfer costs across regions

## Conclusion

This solution provides a robust, scalable approach to header normalization using Lambda@Edge. By following the deployment steps and implementing the monitoring suggestions, you can ensure consistent header formatting across your content delivery network while maintaining high performance and reliability.

Remember to:
- Start with a lower concurrency limit and scale up as needed
- Monitor your function's performance closely
- Implement proper error handling
- Review costs regularly
- Test thoroughly in a staging environment before production deployment

This implementation will help you maintain consistent header casing while handling high traffic volumes efficiently through your CloudFront distribution.
