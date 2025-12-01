import json
import os
import urllib3

http = urllib3.PoolManager()

def handler(event, context):
    """Main Lambda handler - processes requests"""
    
    # Simulate some work
    print(f"Processing request: {json.dumps(event)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Function executed successfully',
            'requestId': context.aws_request_id
        })
    }
