# Lambda Lifecycle Tracking - Functional Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  Lambda Lifecycle Tracking with API Gateway                  │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌──────────────┐
                              │     User     │
                              │   (Browser/  │
                              │     curl)    │
                              └──────┬───────┘
                                     │
                                     │ GET /hello
                                     │ Header: Authorization: any-token
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           API GATEWAY (REST API)                             │
│                         ID: 2x9v8apo48                                       │
│                         Stage: prod                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Endpoint: GET /hello                                                        │
│  Authorization: CUSTOM (Lambda Authorizer)                                   │
│                                                                              │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │
                           │ Step 1: Authorize Request
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    LAMBDA AUTHORIZER (lambda-authorizer-demo)                │
│                    Runtime: Python 3.11 | Memory: 256MB                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  def handler(event, context):                                               │
│      # Extract method ARN                                                    │
│      method_arn = event['methodArn']                                         │
│                                                                              │
│      # Return default ALLOW policy                                           │
│      return {                                                                │
│          'principalId': 'user',                                              │
│          'policyDocument': {                                                 │
│              'Statement': [{                                                 │
│                  'Action': 'execute-api:Invoke',                             │
│                  'Effect': 'Allow',                                          │
│                  'Resource': method_arn                                      │
│              }]                                                              │
│          },                                                                  │
│          'context': {                                                        │
│              'authorizerInfo': 'Default allow policy'                        │
│          }                                                                   │
│      }                                                                       │
│                                                                              │
│  Logs: "Authorizer invoked", "Returning policy"                             │
│                                                                              │
└──────────────────────────┬──────────────────────────────────────────────────┘
                           │
                           │ Returns: ALLOW Policy
                           │
                           │ Step 2: Invoke Target Function
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                  TARGET LAMBDA (lambda-target-demo)                          │
│                  Runtime: Python 3.11 | Memory: 256MB                        │
│                  WITH EXTENSION: shutdown-notifier                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  Main Handler (target_function.py)                                  │    │
│  │  ┌──────────────────────────────────────────────────────────────┐  │    │
│  │  │  def handler(event, context):                                 │  │    │
│  │  │      # Extract headers and context                            │  │    │
│  │  │      headers = event.get('headers', {})                       │  │    │
│  │  │      authorizer = event['requestContext']['authorizer']       │  │    │
│  │  │                                                               │  │    │
│  │  │      # Build HTML response                                    │  │    │
│  │  │      html = f"""                                              │  │    │
│  │  │      <html>                                                   │  │    │
│  │  │        <h1>✅ Success!</h1>                                   │  │    │
│  │  │        <div>Request ID: {context.aws_request_id}</div>       │  │    │
│  │  │        <div>Headers: {headers}</div>                          │  │    │
│  │  │        <div>Authorizer: {authorizer}</div>                    │  │    │
│  │  │      </html>                                                  │  │    │
│  │  │      """                                                      │  │    │
│  │  │                                                               │  │    │
│  │  │      return {                                                 │  │    │
│  │  │          'statusCode': 200,                                   │  │    │
│  │  │          'headers': {'Content-Type': 'text/html'},           │  │    │
│  │  │          'body': html                                         │  │    │
│  │  │      }                                                        │  │    │
│  │  └──────────────────────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ═══════════════════════════════════════════════════════════════════════   │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  Extension: shutdown-notifier (Separate Process)                   │    │
│  │  ┌──────────────────────────────────────────────────────────────┐  │    │
│  │  │  1. Register with Runtime API                                 │  │    │
│  │  │     Events: [INVOKE, SHUTDOWN]                                │  │    │
│  │  │                                                               │  │    │
│  │  │  2. Listen for events (blocking loop)                         │  │    │
│  │  │                                                               │  │    │
│  │  │  3. On INVOKE event:                                          │  │    │
│  │  │     a) Write to DynamoDB (lambda-state-events)                │  │    │
│  │  │     b) Send to upstream webhook                               │  │    │
│  │  │     c) Log: "Event: INVOKE"                                   │  │    │
│  │  │                                                               │  │    │
│  │  │  4. On SHUTDOWN event:                                        │  │    │
│  │  │     a) Write to DynamoDB (lambda-state-events)                │  │    │
│  │  │     b) Send to upstream webhook                               │  │    │
│  │  │     c) Log: "SHUTDOWN! Reason: spindown"                      │  │    │
│  │  │     d) Exit gracefully                                        │  │    │
│  │  └──────────────────────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└──────────────┬───────────────────────────────┬───────────────────────────────┘
               │                               │
               │ Logs                          │ Lifecycle Events
               ▼                               ▼
┌──────────────────────────────┐  ┌──────────────────────────────────────────┐
│  CloudWatch Logs             │  │  DynamoDB Table: lambda-state-events     │
│  /aws/lambda/lambda-target-  │  │  ┌────────────────────────────────────┐ │
│  demo                        │  │  │ eventId (PK): uuid                 │ │
│                              │  │  │ timestamp: ISO 8601                │ │
│  [shutdown-notifier]         │  │  │ eventType: INVOKE | SHUTDOWN       │ │
│  Starting                    │  │  │ functionName: lambda-target-demo   │ │
│  Registered with ID: xxx     │  │  │ requestId: abc-123                 │ │
│  Event: INVOKE               │  │  │ shutdownReason: spindown | N/A     │ │
│  Wrote to DynamoDB: INVOKE   │  │  │ ttl: unix timestamp + 86400        │ │
│  Sending: INVOKE             │  │  └────────────────────────────────────┘ │
│  Target function invoked     │  │                                          │
│  Processing request...       │  │  GSI: timestamp-index                    │
│  Event: SHUTDOWN             │  │  Billing: PAY_PER_REQUEST                │
│  SHUTDOWN! Reason: spindown  │  │  TTL: Auto-delete after 24 hours         │
│  Wrote to DynamoDB: SHUTDOWN │  │                                          │
│                              │  └──────────────────────────────────────────┘
└──────────────────────────────┘
               │
               │ Also sends to
               ▼
┌──────────────────────────────┐
│  Upstream Webhook            │
│  (webhook.site or custom)    │
│                              │
│  POST /endpoint              │
│  {                           │
│    "timestamp": "...",       │
│    "event_type": "INVOKE",   │
│    "function_name": "...",   │
│    "request_id": "..."       │
│  }                           │
└──────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                              REQUEST FLOW TIMELINE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  T=0ms    │ User sends GET /hello                                           │
│           │                                                                  │
│  T=10ms   │ API Gateway receives request                                    │
│           │ Invokes Lambda Authorizer                                       │
│           │                                                                  │
│  T=50ms   │ Authorizer returns ALLOW policy                                 │
│           │ API Gateway proceeds to target                                  │
│           │                                                                  │
│  T=60ms   │ Target Lambda invoked                                           │
│           │ Extension logs INVOKE event                                     │
│           │ Extension writes to DynamoDB                                    │
│           │                                                                  │
│  T=100ms  │ Handler processes request                                       │
│           │ Builds HTML response                                            │
│           │                                                                  │
│  T=150ms  │ Response returned to API Gateway                                │
│           │                                                                  │
│  T=160ms  │ API Gateway returns HTML to user                                │
│           │                                                                  │
│  ...      │ (5-15 minutes of inactivity)                                    │
│           │                                                                  │
│  T=10m    │ Lambda decides to shut down environment                         │
│           │ Extension receives SHUTDOWN event                               │
│           │ Extension writes to DynamoDB                                    │
│           │ Extension exits                                                 │
│           │ Environment terminated                                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                              IAM PERMISSIONS                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Role: lambda-shutdown-demo-role                                            │
│  ├─ AWSLambdaBasicExecutionRole (Managed Policy)                           │
│  │  └─ Permissions:                                                         │
│  │     • logs:CreateLogGroup                                                │
│  │     • logs:CreateLogStream                                               │
│  │     • logs:PutLogEvents                                                  │
│  │                                                                           │
│  └─ DynamoDBAccess (Inline Policy)                                          │
│     └─ Permissions:                                                         │
│        • dynamodb:PutItem                                                    │
│        • dynamodb:GetItem                                                    │
│        • dynamodb:Query                                                      │
│        • dynamodb:Scan                                                       │
│        • Resource: lambda-state-events table and indexes                    │
│                                                                              │
│  Trust Policy: lambda.amazonaws.com                                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA FLOW SUMMARY                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. User Request → API Gateway                                              │
│  2. API Gateway → Lambda Authorizer (returns ALLOW)                         │
│  3. API Gateway → Target Lambda                                             │
│  4. Extension → DynamoDB (INVOKE event)                                     │
│  5. Extension → Upstream Webhook (INVOKE event)                             │
│  6. Handler → HTML Response                                                 │
│  7. API Gateway → User (HTML page)                                          │
│  8. [After idle timeout]                                                    │
│  9. Extension → DynamoDB (SHUTDOWN event)                                   │
│  10. Extension → Upstream Webhook (SHUTDOWN event)                          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Features

✅ **API Gateway Integration**: RESTful endpoint with custom authorizer  
✅ **Lambda Authorizer**: Default allow policy for all requests  
✅ **Lifecycle Tracking**: INVOKE and SHUTDOWN events logged  
✅ **DynamoDB Persistence**: All events stored with 24-hour TTL  
✅ **Dual Notification**: DynamoDB + upstream webhook  
✅ **HTML Response**: Rich response with headers and context  
✅ **CloudWatch Logging**: Full request/response logging  
✅ **Extension Architecture**: Separate process for lifecycle monitoring  

## Testing

```bash
# Test the API
curl https://2x9v8apo48.execute-api.us-east-1.amazonaws.com/prod/hello

# View events in DynamoDB
aws dynamodb scan --table-name lambda-state-events --region us-east-1

# View logs
aws logs tail /aws/lambda/lambda-target-demo --follow --region us-east-1
```
