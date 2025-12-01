# Lambda Shutdown Demo - Created Resources

## AWS Resources Created

### 1. IAM Role
- **Name**: `lambda-shutdown-demo-role`
- **ARN**: `arn:aws:iam::211022366230:role/lambda-shutdown-demo-role`
- **Attached Policies**: 
  - `arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole`

### 2. Lambda Function
- **Name**: `lambda-shutdown-demo`
- **ARN**: `arn:aws:lambda:us-east-1:211022366230:function:lambda-shutdown-demo`
- **Runtime**: Python 3.11
- **Memory**: 256 MB
- **Timeout**: 30 seconds

### 3. CloudWatch Log Group (Auto-created)
- **Name**: `/aws/lambda/lambda-shutdown-demo`
- **Region**: us-east-1

## Local Files Created
- `/home/dobrooks/lambda-shutdown-demo/lambda_function.py`
- `/home/dobrooks/lambda-shutdown-demo/extensions/shutdown-notifier`
- `/home/dobrooks/lambda-shutdown-demo/lambda-shutdown-demo.zip`
- `/home/dobrooks/lambda-shutdown-demo/trust-policy.json`
- `/home/dobrooks/lambda-shutdown-demo/package.sh`
- `/home/dobrooks/lambda-shutdown-demo/test-function.sh`

## How to Test

### 1. Test the function (creates warm execution environment):
```bash
cd ~/lambda-shutdown-demo
chmod +x test-function.sh
./test-function.sh
```

### 2. View logs to see extension activity:
```bash
aws logs tail /aws/lambda/lambda-shutdown-demo --follow --region us-east-1
```

### 3. Trigger shutdown (wait 5-15 minutes after last invocation):
The execution environment will automatically shut down after idle timeout.
You'll see the SHUTDOWN event in CloudWatch Logs.

### 4. Force shutdown by updating function:
```bash
aws lambda update-function-configuration \
  --function-name lambda-shutdown-demo \
  --description "Updated to trigger shutdown" \
  --region us-east-1
```

## Cleanup Commands

Run these commands to delete all resources:

```bash
# Delete Lambda function
aws lambda delete-function \
  --function-name lambda-shutdown-demo \
  --region us-east-1

# Wait a moment for logs to finalize
sleep 5

# Delete CloudWatch Log Group
aws logs delete-log-group \
  --log-group-name /aws/lambda/lambda-shutdown-demo \
  --region us-east-1

# Detach policy from role
aws iam detach-role-policy \
  --role-name lambda-shutdown-demo-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Delete IAM role
aws iam delete-role \
  --role-name lambda-shutdown-demo-role

# Delete local files
rm -rf ~/lambda-shutdown-demo
```

## What the Extension Does

1. **Registers** with Lambda Runtime API on cold start
2. **Listens** for INVOKE and SHUTDOWN events
3. **Sends notifications** to upstream URL when:
   - Function is invoked (INVOKE event)
   - Execution environment is shutting down (SHUTDOWN event)
4. **Includes metadata**: timestamp, function name, version, request ID, shutdown reason

## Extension Output in Logs

You'll see lines like:
```
[Extension] Starting shutdown-notifier extension
[Extension] Registered with ID: <extension-id>
[Extension] Received event: INVOKE
[Extension] Sending notification: {...}
[Extension] Notification sent. Status: 200
[Extension] Received event: SHUTDOWN
[Extension] SHUTDOWN detected! Reason: spindown
[Extension] Sending notification: {...}
```

## Notes

- Shutdown notifications have ~2 seconds to complete
- SHUTDOWN events occur after 5-15 minutes of inactivity
- Update the `UPSTREAM_NOTIFICATION_URL` environment variable to your webhook
- Use https://webhook.site to create a free test webhook
