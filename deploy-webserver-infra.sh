
#!/bin/bash
# NB05022025 - This is an example of Impressive Infrastructure as Code (IaC) using AWS CLI
# This script creates a web server infrastructure with an Application Load Balancer (ALB) and Auto Scaling Group (ASG)

# Exit on error
set -e

# Variables
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_1_CIDR="10.0.1.0/24"
PUBLIC_SUBNET_2_CIDR="10.0.2.0/24"
AZ_1="us-east-1a"
AZ_2="us-east-1b"
AMI_ID="ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI

echo "Creating web server infrastructure..."

# Create VPC
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --region $REGION \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames \
  --region $REGION

aws ec2 create-tags \
  --resources $VPC_ID \
  --tags Key=Name,Value=WebAppVPC \
  --region $REGION

echo "VPC created: $VPC_ID"

# Create public subnets
echo "Creating public subnets..."
SUBNET_1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PUBLIC_SUBNET_1_CIDR \
  --availability-zone $AZ_1 \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags \
  --resources $SUBNET_1_ID \
  --tags Key=Name,Value="Public Subnet 1" \
  --region $REGION

SUBNET_2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PUBLIC_SUBNET_2_CIDR \
  --availability-zone $AZ_2 \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags \
  --resources $SUBNET_2_ID \
  --tags Key=Name,Value="Public Subnet 2" \
  --region $REGION

echo "Public subnets created: $SUBNET_1_ID, $SUBNET_2_ID"

# Create and attach internet gateway
echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 create-tags \
  --resources $IGW_ID \
  --tags Key=Name,Value="Web VPC IGW" \
  --region $REGION

aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID \
  --region $REGION

echo "Internet Gateway created and attached: $IGW_ID"

# Create route table for public subnets
echo "Creating route table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-tags \
  --resources $ROUTE_TABLE_ID \
  --tags Key=Name,Value="Public Route Table" \
  --region $REGION

# Add route to internet
aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $REGION

# Associate route table with subnets
aws ec2 associate-route-table \
  --route-table-id $ROUTE_TABLE_ID \
  --subnet-id $SUBNET_1_ID \
  --region $REGION

aws ec2 associate-route-table \
  --route-table-id $ROUTE_TABLE_ID \
  --subnet-id $SUBNET_2_ID \
  --region $REGION

echo "Route table created and associated: $ROUTE_TABLE_ID"

# Create security group for ALB
echo "Creating ALB security group..."
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name alb-sg \
  --description "Security group for application load balancer" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

aws ec2 create-tags \
  --resources $ALB_SG_ID \
  --tags Key=Name,Value="ALB SG" \
  --region $REGION

# Add ingress rule for HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region $REGION

echo "ALB security group created: $ALB_SG_ID"

# Create security group for web servers
echo "Creating web server security group..."
WEB_SG_ID=$(aws ec2 create-security-group \
  --group-name web-server-sg \
  --description "Security group for web servers" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)

aws ec2 create-tags \
  --resources $WEB_SG_ID \
  --tags Key=Name,Value="Web Server SG" \
  --region $REGION

# Add ingress rule for HTTP from ALB only
aws ec2 authorize-security-group-ingress \
  --group-id $WEB_SG_ID \
  --protocol tcp \
  --port 80 \
  --source-group $ALB_SG_ID \
  --region $REGION

# Add egress rule
aws ec2 authorize-security-group-egress \
  --group-id $WEB_SG_ID \
  --protocol all \
  --port -1 \
  --cidr 0.0.0.0/0 \
  --region $REGION

echo "Web server security group created: $WEB_SG_ID"

# Create Application Load Balancer
echo "Creating Application Load Balancer..."
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name web-app-lb \
  --subnets $SUBNET_1_ID $SUBNET_2_ID \
  --security-groups $ALB_SG_ID \
  --region $REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

echo "ALB created: $ALB_ARN"

# Create target group
echo "Creating target group..."
TG_ARN=$(aws elbv2 create-target-group \
  --name web-target-group \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --health-check-path / \
  --health-check-protocol HTTP \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

echo "Target group created: $TG_ARN"

# Create listener
echo "Creating listener..."
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region $REGION \
  --query 'Listeners[0].ListenerArn' \
  --output text)

echo "Listener created: $LISTENER_ARN"

# Create user data script
USER_DATA=$(cat <<EOF
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from Web Server</h1>" > /var/www/html/index.html
EOF
)
USER_DATA_B64=$(echo "$USER_DATA" | base64)

# Create launch template
echo "Creating launch template..."
LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name web-server-template \
  --version-description "Initial version" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t2.micro\",
    \"SecurityGroupIds\": [\"$WEB_SG_ID\"],
    \"UserData\": \"$USER_DATA_B64\",
    \"TagSpecifications\": [{
      \"ResourceType\": \"instance\",
      \"Tags\": [{
        \"Key\": \"Name\",
        \"Value\": \"WebServer\"
      }]
    }]
  }" \
  --region $REGION \
  --query 'LaunchTemplate.LaunchTemplateId' \
  --output text)

echo "Launch template created: $LAUNCH_TEMPLATE_ID"

# Create Auto Scaling Group
echo "Creating Auto Scaling Group..."
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name web-server-asg \
  --launch-template "LaunchTemplateId=$LAUNCH_TEMPLATE_ID,Version=\$Latest" \
  --min-size 2 \
  --max-size 5 \
  --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_1_ID,$SUBNET_2_ID" \
  --target-group-arns $TG_ARN \
  --tags "Key=Name,Value=WebServer-ASG,PropagateAtLaunch=true" \
  --region $REGION

echo "Auto Scaling Group created"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --region $REGION \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "----------------------------"
echo "Deployment completed successfully!"
echo "ALB DNS Name: $ALB_DNS"
echo "Access your web application at: http://$ALB_DNS"
echo "----------------------------"