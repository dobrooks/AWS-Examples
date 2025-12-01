import json
import os
import boto3
from datetime import datetime
import uuid

dynamodb = boto3.resource('dynamodb', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE', 'lambda-state-events'))

def write_event(event_type, context, extra_data=None):
    """Write lifecycle event to DynamoDB with 20-minute TTL"""
    try:
        item = {
            'eventId': str(uuid.uuid4()),
            'timestamp': datetime.utcnow().isoformat(),
            'eventType': event_type,
            'functionName': context.function_name,
            'functionVersion': context.function_version,
            'requestId': context.aws_request_id,
            'memoryLimit': context.memory_limit_in_mb,
            'ttl': int(datetime.utcnow().timestamp()) + 1200  # 20 minutes
        }
        if extra_data:
            item.update(extra_data)
        
        table.put_item(Item=item)
        print(f"✅ Wrote {event_type} event to DynamoDB: {item['eventId']} (TTL: 20 min)")
    except Exception as e:
        print(f"❌ Failed to write to DynamoDB: {e}")

def handler(event, context):
    """Lambda authorizer - returns default ALLOW policy"""
    
    # Write INVOKE event to DynamoDB
    write_event('AUTHORIZER_INVOKE', context, {
        'methodArn': event.get('methodArn', 'N/A'),
        'authorizationType': event.get('type', 'REQUEST')
    })
    
    print(f"Authorizer invoked: {json.dumps(event)}")
    
    # Extract the method ARN
    method_arn = event['methodArn']
    
    # Generate allow policy
    policy = {
        'principalId': 'user',
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': 'Allow',
                    'Resource': method_arn
                }
            ]
        },
        'context': {
            'authorizerInfo': 'Default allow policy',
            'timestamp': context.aws_request_id
        }
    }
    
    print(f"Returning policy: {json.dumps(policy)}")
    return policy
