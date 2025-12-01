# Testing SHUTDOWN Events

## ✅ Extension is Now Working!

The Lambda extension is successfully deployed via Lambda Layer and is tracking lifecycle events.

## Current Status:

**INVOKE Events:** ✅ Logged to DynamoDB by function handler  
**SHUTDOWN Events:** ✅ Extension is ready to capture them

## How to Trigger SHUTDOWN Events:

### Method 1: Wait for Natural Timeout (5-15 minutes)

```bash
# 1. Make a request to warm up the environment
curl -H "Authorization: test" https://2x9v8apo48.execute-api.us-east-1.amazonaws.com/prod/hello

# 2. Wait 10-15 minutes without making any requests

# 3. Check DynamoDB for SHUTDOWN event
aws dynamodb scan --table-name lambda-state-events \
  --filter-expression "eventType = :type" \
  --expression-attribute-values '{":type":{"S":"SHUTDOWN"}}' \
  --region us-east-1
```

### Method 2: Force Shutdown (Immediate)

```bash
# Update function configuration to force environment replacement
aws lambda update-function-configuration \
  --function-name lambda-target-demo \
  --description "Force shutdown - $(date +%s)" \
  --region us-east-1

# Wait a few seconds
sleep 5

# Check DynamoDB for SHUTDOWN event
aws dynamodb scan --table-name lambda-state-events \
  --filter-expression "eventType = :type" \
  --expression-attribute-values '{":type":{"S":"SHUTDOWN"}}' \
  --region us-east-1
```

### Method 3: Delete and Recreate (Guaranteed)

```bash
# This will definitely trigger shutdown
aws lambda delete-function --function-name lambda-target-demo --region us-east-1

# Check DynamoDB immediately
aws dynamodb scan --table-name lambda-state-events \
  --filter-expression "eventType = :type" \
  --expression-attribute-values '{":type":{"S":"SHUTDOWN"}}' \
  --region us-east-1
```

## Expected SHUTDOWN Event in DynamoDB:

```json
{
  "eventId": "uuid-here",
  "timestamp": "2025-12-01T14:50:00.000Z",
  "eventType": "SHUTDOWN",
  "functionName": "lambda-target-demo",
  "functionVersion": "$LATEST",
  "requestId": "N/A",
  "shutdownReason": "spindown",
  "ttl": 1764686400
}
```

## Monitoring Extension Activity:

```bash
# Watch logs in real-time
aws logs tail /aws/lambda/lambda-target-demo --follow --region us-east-1

# Filter for extension logs only
aws logs tail /aws/lambda/lambda-target-demo --since 10m --region us-east-1 | grep shutdown-notifier

# Look for SHUTDOWN event
aws logs tail /aws/lambda/lambda-target-demo --since 10m --region us-east-1 | grep SHUTDOWN
```

## Extension Lifecycle:

1. **Cold Start** - Extension starts with Lambda environment
2. **Registration** - Extension registers for INVOKE and SHUTDOWN events
3. **INVOKE Events** - Extension logs each invocation (handler writes to DynamoDB)
4. **Idle Period** - Environment stays warm for 5-15 minutes
5. **SHUTDOWN Event** - Lambda sends SHUTDOWN signal
6. **Extension Writes** - Extension writes SHUTDOWN event to DynamoDB
7. **Graceful Exit** - Extension exits within 2 seconds
8. **Environment Terminated** - Lambda terminates the execution environment

## Troubleshooting:

If SHUTDOWN events aren't appearing:

1. Check extension is loaded:
   ```bash
   aws logs tail /aws/lambda/lambda-target-demo --since 5m --region us-east-1 | grep "shutdown-notifier"
   ```

2. Verify boto3 is available:
   ```bash
   aws logs tail /aws/lambda/lambda-target-demo --since 5m --region us-east-1 | grep "boto3: available"
   ```

3. Check for errors:
   ```bash
   aws logs tail /aws/lambda/lambda-target-demo --since 5m --region us-east-1 | grep -i error
   ```

## Quick Test Command:

```bash
# Force shutdown and check immediately
aws lambda update-function-configuration \
  --function-name lambda-target-demo \
  --description "Test shutdown $(date +%s)" \
  --region us-east-1&& sleep 10 && \
aws dynamodb scan --table-name lambda-state-events \
  --filter-expression "eventType = :type" \
  --expression-attribute-values '{":type":{"S":"SHUTDOWN"}}' \
  --region us-east-1 --output table
```
