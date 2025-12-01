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
    """Target Lambda - returns 200 OK with headers and success message"""
    
    # Write INVOKE event to DynamoDB
    write_event('INVOKE', context, {
        'httpMethod': event.get('httpMethod', 'N/A'),
        'path': event.get('path', 'N/A'),
        'sourceIp': event.get('requestContext', {}).get('identity', {}).get('sourceIp', 'N/A')
    })
    
    print(f"Target function invoked: {json.dumps(event)}")
    
    # Extract headers from the event
    headers = event.get('headers', {})
    request_context = event.get('requestContext', {})
    authorizer_context = request_context.get('authorizer', {})
    
    # Build HTML response
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Lambda Success</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; background: #f0f0f0; }}
            .container {{ background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
            h1 {{ color: #28a745; }}
            .section {{ margin: 20px 0; padding: 15px; background: #f8f9fa; border-left: 4px solid #28a745; }}
            .header-item {{ margin: 5px 0; font-family: monospace; }}
            .label {{ font-weight: bold; color: #495057; }}
            .success {{ color: #28a745; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>✅ Success!</h1>
            <p>Your request was successfully processed by the Lambda function.</p>
            <p class="success">Event logged to DynamoDB: lambda-state-events (TTL: 20 minutes)</p>
            
            <div class="section">
                <h3>Request Information</h3>
                <div class="header-item"><span class="label">Request ID:</span> {context.aws_request_id}</div>
                <div class="header-item"><span class="label">Function Name:</span> {context.function_name}</div>
                <div class="header-item"><span class="label">HTTP Method:</span> {event.get('httpMethod', 'N/A')}</div>
                <div class="header-item"><span class="label">Path:</span> {event.get('path', 'N/A')}</div>
            </div>
            
            <div class="section">
                <h3>Authorizer Context</h3>
                <div class="header-item"><span class="label">Principal ID:</span> {authorizer_context.get('principalId', 'N/A')}</div>
                <div class="header-item"><span class="label">Authorizer Info:</span> {authorizer_context.get('authorizerInfo', 'N/A')}</div>
            </div>
            
            <div class="section">
                <h3>Request Headers</h3>
                {''.join([f'<div class="header-item"><span class="label">{k}:</span> {v}</div>' for k, v in headers.items()])}
            </div>
        </div>
    </body>
    </html>
    """
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'text/html',
            'X-Request-Id': context.aws_request_id
        },
        'body': html
    }
