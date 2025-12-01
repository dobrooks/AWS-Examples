# Lambda Shutdown Event Tracking

Track AWS Lambda lifecycle events (INVOKE and SHUTDOWN) using the Lambda Extensions API with automatic DynamoDB logging and TTL-based cleanup.

## Overview

This project demonstrates how to capture Lambda SHUTDOWN events using the Lambda Extensions API. The extension runs alongside your Lambda function and logs both INVOKE and SHUTDOWN events to DynamoDB with automatic expiration after 20 minutes.

## Features

- **Lambda Extension** - Captures INVOKE and SHUTDOWN lifecycle events
- **DynamoDB Logging** - Stores events with automatic TTL expiration (20 minutes)
- **API Gateway Integration** - Includes Lambda authorizer example
- **Complete Infrastructure** - IAM roles, Lambda functions, API Gateway, DynamoDB table

## Architecture

```
User Request → API Gateway → Lambda Authorizer
                    ↓
              Target Lambda (with Extension)
                    ↓
              DynamoDB Table
           (lambda-state-events)
```

## Quick Start

```bash
# Deploy all resources
./deploy.sh

# Test the API
curl https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/hello

# View events in DynamoDB
aws dynamodb scan --table-name lambda-state-events --region us-east-1

# Clean up all resources
./cleanup.sh
```

## Project Structure

```
.
├── extensions/
│   └── shutdown-notifier       # Lambda extension (Python)
├── layer/
│   └── extensions/             # Extension packaged as layer
├── authorizer_function.py      # Lambda authorizer
├── target_function.py          # Target Lambda with extension
├── deploy.sh                   # Automated deployment
├── cleanup.sh                  # Resource cleanup
├── trust-policy.json           # IAM trust policy
├── dynamodb-policy.json        # DynamoDB access policy
└── README.md                   # This file
```

## How It Works

### Lambda Extension

The extension registers with the Lambda Runtime Extensions API and listens for lifecycle events:

1. **INVOKE** - Triggered when Lambda function is invoked
2. **SHUTDOWN** - Triggered when Lambda execution environment shuts down

Events are logged to DynamoDB with:
- Event ID (UUID)
- Timestamp
- Event type (INVOKE/SHUTDOWN)
- Function name and version
- Request ID
- TTL (20 minutes from creation)

### DynamoDB TTL

Events automatically expire after 20 minutes (1200 seconds) to minimize storage costs. DynamoDB removes expired items in the background.

### SHUTDOWN Event Triggers

SHUTDOWN events occur when:
- Lambda execution environment is idle for 5-15 minutes
- Function configuration is updated
- AWS scales down capacity

**Note:** SHUTDOWN events are not guaranteed during forced terminations.

## Testing SHUTDOWN Events

See [SHUTDOWN-TESTING.md](SHUTDOWN-TESTING.md) for detailed testing instructions.

The most reliable way to trigger SHUTDOWN:
1. Invoke the function
2. Wait 5-15 minutes (natural timeout)
3. Check DynamoDB for SHUTDOWN event

## Resources Created

- **IAM Role:** `lambda-shutdown-demo-role`
- **Lambda Functions:**
  - `lambda-authorizer-demo` (API Gateway authorizer)
  - `lambda-target-demo` (with extension layer)
- **Lambda Layer:** `lambda-shutdown-extension`
- **DynamoDB Table:** `lambda-state-events` (with TTL enabled)
- **API Gateway:** `lambda-lifecycle-api` (REST API with /hello endpoint)

## Requirements

- AWS CLI configured with appropriate credentials
- Bash shell
- Python 3.12 (for Lambda runtime)

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed architecture documentation
- [SHUTDOWN-TESTING.md](SHUTDOWN-TESTING.md) - Testing guide
- [RESOURCES.md](RESOURCES.md) - Resource details
- [SUMMARY.md](SUMMARY.md) - Project summary

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please open an issue or submit a pull request.
