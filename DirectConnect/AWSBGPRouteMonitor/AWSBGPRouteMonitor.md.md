# ############### DRAFT - Subject to change ################

# Monitoring BGP Route Health in AWS Direct Connect with Lambda and CloudWatch
## by Don Brooks 

## Introduction
AWS Direct Connect is a dedicated network connection service that establishes a private, high-bandwidth link between your on-premises data center and AWS. Instead of using the public internet, Direct Connect provides a more reliable, secure, and consistent network experience with reduced latency and higher throughput. It supports connection speeds from 1 Gbps to 100 Gbps and can be used to access AWS services across multiple regions. Direct Connect is particularly valuable for organizations that need to transfer large amounts of data, require consistent network performance, or must meet specific compliance requirements for data transmission. Users can establish either dedicated connections (physical ethernet ports dedicated to a customer) or hosted connections (obtained through AWS Direct Connect Partners).

In AWS Direct Connect environments, private Virtual Interfaces (VIFs) connected through a Direct Connect Gateway (DXGW) to Virtual Private Gateways (VGWs) enable secure, low-latency connectivity between on-premises networks and AWS VPCs. These setups rely on Border Gateway Protocol (BGP) sessions to exchange routing information. While AWS provides CloudWatch metrics like `VirtualInterfaceBgpPeerState` to monitor BGP session status (up or down), there’s no native metric to track the actual number of routes exchanged. This gap can be problematic: a BGP session may be "up," but if no routes are being propagated, your connectivity could be silently broken.  Another scenario if if the Direct Connect VIF are connect to a AWS transit Gateway through a DXGW.  This scenario will be addressed in a future article.

In this post, we’ll address this issue by building a solution to monitor the health of BGP route propagation in AWS Direct Connect. We’ll create an AWS Lambda function to check subnet route tables for VGW-propagated routes, publish the count to a custom CloudWatch metric, and set up an alarm to alert when no routes are exchanged. This ensures you’re notified if your BGP session is up but not exchanging routes, helping maintain robust connectivity.

## The Problem: No Native Metric for BGP Route Health
AWS Direct Connect supports metrics like `VirtualInterfaceBgpPeerState`, which indicates whether a BGP session is up (1) or down (0). However, this metric doesn’t tell you if routes are actually being exchanged. For example, your on-premises router might establish a BGP session with a private VIF, but misconfigurations or network issues could prevent route advertisements, resulting in no propagated routes in your VPC subnets’ route tables. Without a way to monitor this, you might assume connectivity is fine when it’s not.

To solve this, we need to:
1. Identify subnets in VPCs with VGW route propagation enabled.
2. Count the number of routes in each subnet’s route table propagated by the VGW (where `Origin` is `EnableVgwRoutePropagation`).
3. Publish the count as a custom CloudWatch metric.
4. Set an alarm to alert if the count is 0, indicating no routes are being exchanged.
5. Send a notification to a SNS Topic to notify of alarm via email or text.
6. Run this check every 3 minutes to ensure timely detection.

## Solution: AWS Lambda and CloudWatch
This solution uses an AWS Lambda function to query route tables, count VGW-propagated routes, and publish a custom metric to CloudWatch. We’ll also configure a CloudWatch alarm to notify us via Amazon SNS if the route count drops to 0. Finally, we’ll schedule the Lambda function to run every 3 minutes using a CloudWatch Events Rule.

<img width="929" height="561" alt="image" src="https://4453gh-werwer-1384-artifacts.s3.us-east-2.amazonaws.com/AWSBGPRouteMonitor+(1).jpg" />



### Step 1: AWS Lambda Function
The Lambda function iterates through all VPCs, identifies subnets with VGW route propagation enabled, counts propagated routes, and publishes the count to a custom CloudWatch metric (`Custom/DirectConnect/VgwPropagatedRouteCount`).

Here’s the Python code for the Lambda function:

    import json
    import boto3
    from botocore.exceptions import ClientError
    from datetime import datetime
    
    def lambda_handler(event, context):
        # Initialize EC2 and CloudWatch clients
        ec2_client = boto3.client('ec2')
        cw_client = boto3.client('cloudwatch')
       
        try:
            # Get all VPCs in the region
            vpc_response = ec2_client.describe_vpcs()
            #print("Getting the vpcs - ", vpc_response)
            vpcs = vpc_response.get('Vpcs', [])
           
            if not vpcs:
                return {
                    'statusCode': 200,
                    'body': json.dumps({'message': 'No VPCs found in the region'})
                }
           
            results = []
           
            # Iterate through each VPC
            for vpc in vpcs:
                vpc_id = vpc['VpcId']
               
                # Get the VGW attached to the VPC
                vgw_response = ec2_client.describe_vpn_gateways(
                    Filters=[
                        {'Name': 'attachment.vpc-id', 'Values': [vpc_id]},
                        {'Name': 'attachment.state', 'Values': ['attached']}
                    ]
                )
                
                vgws = vgw_response.get('VpnGateways', [])
                if not vgws:
                    print(f"No VGW attached to VPC {vpc_id}")
                    continue  # Skip VPCs with no attached VGW
               
                vgw_id = vgws[0]['VpnGatewayId']
                #print(Processing routes for VGW : ",vgw_id)
               
                # Get all subnets in the VPC
                subnet_response = ec2_client.describe_subnets(
                    Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}]
                )
                subnets = subnet_response.get('Subnets', [])
               
                # Iterate through each subnet
                for subnet in subnets:
                    subnet_id = subnet['SubnetId']
                    #print(vpc_id, subnet_id)
                   
                    # Get the route table associated with the subnet
                    rt_response = ec2_client.describe_route_tables(
                        Filters=[
                            {'Name': 'association.subnet-id', 'Values': [subnet_id]}
                        ]
                    )
                   
                    # If no explicit association, check for main route table
                    if not rt_response.get('RouteTables'):
                        rt_response = ec2_client.describe_route_tables(
                            Filters=[
                                {'Name': 'association.main', 'Values': ['true']},
                                {'Name': 'vpc-id', 'Values': [vpc_id]}
                            ]
                        )
                   
                    if not rt_response.get('RouteTables'):
                        continue  # Skip if no route table found
                   
                    route_table = rt_response['RouteTables'][0]
                    route_table_id = route_table['RouteTableId']
                   
                    # Check if VGW propagation is enabled
                    propagation_enabled = any(
                        prop['GatewayId'] == vgw_id
                        for prop in route_table.get('PropagatingVgws', [])
                    )
                   
                    if not propagation_enabled:
                        continue  # Skip if VGW propagation is not enabled
                   
                    # Count VGW-propagated routes
                    routes = route_table.get('Routes', [])
                    vgw_propagated_count = sum(
                        1 for route in routes
                        if route.get('Origin') == 'EnableVgwRoutePropagation'
                    )
                   
                    # Publish to CloudWatch custom metric
                    cw_client.put_metric_data(
                        Namespace='Custom/DirectConnect',
                        MetricData=[
                            {
                                'MetricName': 'VgwPropagatedRouteCount',
                                'Dimensions': [
                                    {'Name': 'SubnetId', 'Value': subnet_id},
                                    {'Name': 'RouteTableId', 'Value': route_table_id},
                                    {'Name': 'VgwId', 'Value': vgw_id}
                                ],
                                'Value': vgw_propagated_count,
                                'Unit': 'Count',
                                'Timestamp': datetime.utcnow()
                            }
                        ]
                    )
                   
                    # Collect result for response
                    results.append({
                        'SubnetId': subnet_id,
                        'RouteTableId': route_table_id,
                        'VgwId': vgw_id,
                        'VgwPropagatedRouteCount': vgw_propagated_count
                    })
           
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Successfully published VGW propagated route counts',
                    'results': results
                }, indent=2)
            }
       
        except ClientError as e:
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'Failed to process request',
                    'details': str(e)
                })
            }
        except Exception as e:
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'Unexpected error',
                    'details': str(e)
                })
            }

### Step 2: Deploy the Lambda Function and corresponding permissions
1. **Configure IAM Policy and Role**:
   - Create a IAM $${\color{red}POLICY}$$ called **dx_route_monitor_policy** and add these permissions (Swicth to JSON edit)
     ```json
     {
         "Version": "2012-10-17",
         "Statement": [
             {
                 "Effect": "Allow",
                 "Action": [
                     "ec2:DescribeVpcs",
                     "ec2:DescribeSubnets",
                     "ec2:DescribeRouteTables",
                     "ec2:DescribeVpnGateways",
                     "cloudwatch:PutMetricData",
                     "logs:CreateLogGroup",
                     "logs:CreateLogStream",
                     "logs:PutLogEvents"
                 ],
                 "Resource": "*"
             }
         ]
     }
     ```

   - Create an IAM $${\color{red}ROLE}$$ to be used by the Lambda function for execution called **dx_route_monitor_role**.
     
     Select AWS Service -> lambda.
     Choose the policy created above "dx_route_monitor_policy"


   - 
2. **Create the Function**:
   - In the AWS Lambda Console (https://console.aws.amazon.com/lambda/), create a new function named `MonitorVgwPropagatedRoutes`.
   - Set the runtime to Python 3.13 (or later) and architecture to x86_64.
   - Paste the code above into `lambda_function.py` and deploy.
   - Under *Configuration -> Permission* edit the **Execution Role** and choose the Role created above **dx_route_monitor_role**
     
4. **Set Timeout and Memory**:
   - Set a timeout of 60 seconds and memory of 256 MB to handle multiple VPCs and subnets.
   - Under *Configuration -> General configuration* Edit these timeout values.
     Note: You may have to adjust this timer up depending on your environment.  If you experience timeout error in the lambda log then increase the execution timeout.

### Step 3: Schedule the Lambda Function
To run the function every 3 minutes:
1. **Create a Amazon Eventbridge schedule**:
   - In the Amazon EventBridge Console , go to **Schedular > Schedule > Create Schedule**.
   - Enter a name for the schedule i.e. **dx_monitor_Lambda_schedule**
   - Enter a <optional> description.
   - In the Schedule Pattern Section
   -     Select Recurring
   -     Select "Rate Base" for Schedule Type
   -     Set "Rate Expression" to 3 <minutes>
   -     Select "Next"
   -     Select "AWS Lambda Invoke"
   -     Select your lambda function "MonitorVgwPropagatedRoutes" from the drop down.
   -     Click Next
   -     Make sure the Schedule State is Enable
   -     Under Permission select "Create new role for this schedule"
   -         Name the Role "Amazon_EventBridge_dx_monitor"
   -     Click "Next"
   -     Review the information and click "Create Schedule"


# ################ Stll working on this section

### Step 4: Set Up a CloudWatch Alarm
To alert when no routes are propagated (count = 0) for a specific subnet:
1. **Create an SNS Topic**:
   In the SNS Console (https://console.aws.amazon.com/sns/), create a topic (e.g., `VgwRouteAlarmTopic`).
   
        Select "Standard" topic as order is not important and volume is low.
        Provide a name for your topic aka "dx_monitor-Topic
        Hit <Create>
   - On the SNS Main Page click on Subscriptions-> Create Subscriptioln
   -     Enter the arn of the topic you just created
   -     Select the delivery method (Usually SMS or EMail)
   -     Enter Email Address under endpoint
   -     <Click on "Create Subscription"
   -     Note:  You will receive an email at the address you entered to confirm your enrollment to the subscription
   - 
   - OR if you prefer to configure via the AWS CLI to Subscribe an email or SMS endpoin:
 
     ```bash
     aws sns create-topic --name VgwRouteAlarmTopic --region us-east-1
     aws sns subscribe \
       --topic-arn arn:aws:sns:us-east-1:123456789012:VgwRouteAlarmTopic \
       --protocol email \
       --notification-endpoint <*your-email@example.com*> \
       --region us-east-1
     ```
3. **Create the Alarm**:
   - Use the AWS CLI to create an alarm for a specific subnet:
     ```bash
     aws cloudwatch put-metric-alarm \
       --alarm-name "VgwRouteCountZero-subnet-xxxxxxxx" \
       --alarm-description "Alerts when VGW-propagated route count is 0 for subnet-xxxxxxxx" \
       --metric-name VgwPropagatedRouteCount \
       --namespace Custom/DirectConnect \
       --statistic Average \
       --period 180 \
       --threshold 0 \
       --comparison-operator EqualToThreshold \
       --evaluation-periods 1 \
       --datapoints-to-alarm 1 \
       --treat-missing-data breaching \
       --dimensions Name=SubnetId,Value=subnet-xxxxxxxx Name=RouteTableId,Value=rtb-xxxxxxxx Name=VgwId,Value=vgw-xxxxxxxx \
       --alarm-actions arn:aws:sns:us-east-1:123456789012:VgwRouteAlarmTopic \
       --region us-east-1
     ```
   - Replace `subnet-xxxxxxxx`, `rtb-xxxxxxxx`, `vgw-xxxxxxxx`, and the SNS topic ARN with your values.
   - 
4. **Automate for Multiple Subnets**:
   - Since you have multiple subnets, use a script to create alarms for each subnet based on the Lambda function’s output. Here’s a Python script to automate this:

     ```python
     import boto3
     import json

     def create_alarms_for_subnets(region, sns_topic_arn, subnets):
         cw_client = boto3.client('cloudwatch', region_name=region)
         
         for subnet in subnets:
             subnet_id = subnet['SubnetId']
             route_table_id = subnet['RouteTableId']
             vgw_id = subnet['VgwId']
             
             alarm_name = f"VgwRouteCountZero-{subnet_id}"
             alarm_description = f"Alerts when VGW-propagated route count is 0 for {subnet_id}"
             
             try:
                 cw_client.put_metric_alarm(
                     AlarmName=alarm_name,
                     AlarmDescription=alarm_description,
                     MetricName='VgwPropagatedRouteCount',
                     Namespace='Custom/DirectConnect',
                     Statistic='Average',
                     Period=180,
                     Threshold=0,
                     ComparisonOperator='EqualToThreshold',
                     EvaluationPeriods=1,
                     DatapointsToAlarm=1,
                     TreatMissingData='breaching',
                     Dimensions=[
                         {'Name': 'SubnetId', 'Value': subnet_id},
                         {'Name': 'RouteTableId', 'Value': route_table_id},
                         {'Name': 'VgwId', 'Value': vgw_id}
                     ],
                     AlarmActions=[sns_topic_arn]
                 )
                 print(f"Created alarm {alarm_name}")
             except Exception as e:
                 print(f"Failed to create alarm for {subnet_id}: {str(e)}")

     def main():
         region = 'us-east-1'  # Replace with your region
         sns_topic_arn = 'arn:aws:sns:us-east-1:123456789012:VgwRouteAlarmTopic'  # Replace with your SNS topic ARN
         
         # Use Lambda output or fetch subnets dynamically
         lambda_output = {
             "results": [
                 {
                     "SubnetId": "subnet-xxxxxxxx",
                     "RouteTableId": "rtb-xxxxxxxx",
                     "VgwId": "vgw-xxxxxxxx",
                     "VgwPropagatedRouteCount": 0
                 }
                 # Add more subnets from Lambda output
             ]
         }
         
         subnets = lambda_output['results']
         create_alarms_for_subnets(region, sns_topic_arn, subnets)

     if __name__ == "__main__":
         main()
     ```

   - Save as `create_alarms.py`, update the `region`, `sns_topic_arn`, and `subnets` list with your Lambda output, and run:
     ```bash
     python3 create_alarms.py
     ```

### Step 5: Test and Validate
1. **Test the Lambda Function**:
   - Invoke the Lambda function in the AWS Console with an empty event (`{}`).
   - Check CloudWatch Logs (`/aws/lambda/MonitorVgwPropagatedRoutes`) for the output, which lists subnets, route tables, VGWs, and route counts.
   - Verify metrics in CloudWatch under **Metrics > Custom/DirectConnect > VgwPropagatedRouteCount**.
2. **Test the Alarm**:
   - Temporarily stop BGP route advertisements on your on-premises router or private VIF to simulate 0 propagated routes.
   - Wait for the Lambda function to run (within 3 minutes) and check if the alarm transitions to `ALARM` state.
   - Confirm notifications are sent via the SNS topic (e.g., check your email).
3. **Verify BGP Status**:
   - Ensure BGP sessions are active:
     ```bash
     aws directconnect describe-virtual-interfaces --region us-east-1
     ```
   - Check `bgpPeerState` is `available`. If no routes are propagated, investigate your on-premises router or DXGW configuration.

### Considerations
- **Multiple Subnets**: You’ll need an alarm per subnet due to unique `SubnetId` dimensions. The `create_alarms.py` script automates this.
- **False Positives**: Use `EvaluationPeriods=3` (9 minutes) instead of 1 for alarms to reduce false positives from temporary BGP drops.
- **Cost**:
  - **Lambda**: ~480 invocations/day at 3-minute intervals, costing ~$0.10-$0.20/month (256 MB, 5-second duration).
  - **CloudWatch Metrics**: $0.30 per metric-month per subnet (first 10,000 metrics free).
  - **CloudWatch Alarms**: $0.10 per alarm-month per subnet.
  - **SNS**: ~$0.50 per million email notifications.
  - Monitor costs with AWS Cost Explorer.
- **Cross-Account Setup**: If VGWs or subnets are in different accounts, configure cross-account CloudWatch access.
- **Troubleshooting**:
  - **No Metrics**: Verify the Lambda function is publishing metrics (check logs).
  - **No Routes**: Confirm BGP advertisements from your on-premises router and VIF/DXGW associations.
  - **Permission Errors**: Ensure the Lambda IAM role includes `ec2:Describe*` and `cloudwatch:PutMetricData`.

### Conclusion
By deploying this AWS Lambda function and CloudWatch alarms, you can effectively monitor BGP route health in your AWS Direct Connect setup. The solution fills the gap left by the absence of a native CloudWatch metric for BGP route counts, ensuring you’re alerted when no routes are propagated despite an active BGP session. This proactive monitoring helps maintain reliable connectivity between your on-premises network and AWS VPCs.

For further enhancements, consider:
- Creating a CloudWatch Dashboard to visualize `VgwPropagatedRouteCount` across subnets.
- Adding remediation logic (e.g., a Lambda function triggered by the alarm to restart BGP sessions).
- Filtering specific VPCs to reduce Lambda execution time in large environments.

If you need help with these enhancements or have specific subnet IDs to monitor, feel free to reach out!
