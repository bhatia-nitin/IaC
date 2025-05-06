/* NB05022025 -- This is an example of Declarative Infrastructure as Code (IaC) using Terraform. 
   It is designed to be run in a local environment with AWS credentials configured. 
   The script creates a web application architecture on AWS, including VPC, subnets, 
   security groups, an Application Load Balancer (ALB), and an Auto Scaling Group (ASG). 
   The script is modular and can be easily modified to suit different requirements. 
   It is important to ensure that the AWS region and AMI ID are appropriate for your use case. 
   Please review the script carefully before running it in your environment. */

provider "aws" {
  region = "us-east-2"
}

# VPC and networking
resource "aws_vpc" "web_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  
  tags = {
    Name = "WebAppVPC"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.web_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"
  
  tags = {
    Name = "Public Subnet 1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.web_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-2b"
  
  tags = {
    Name = "Public Subnet 2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.web_vpc.id
  
  tags = {
    Name = "Web VPC IGW"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.web_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# Security group for web servers
resource "aws_security_group" "web_sg" {
  name        = "web-server-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.web_vpc.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "Web Server SG"
  }
}

# Security group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for application load balancer"
  vpc_id      = aws_vpc.web_vpc.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "ALB SG"
  }
}

# Application Load Balancer
resource "aws_lb" "web_alb" {
  name               = "web-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  
  tags = {
    Name = "Web App ALB"
  }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.web_vpc.id
  
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Launch Template and Auto Scaling Group
resource "aws_launch_template" "web_template" {
  name_prefix   = "web-server-"
  image_id      = "ami-096af71d77183c8f8"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from Web Server</h1>" > /var/www/html/index.html
    EOF
  )
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "WebServer"
    }
  }
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity    = 2
  max_size            = 5
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  target_group_arns   = [aws_lb_target_group.web_tg.arn]
  
  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }
  
  tag {
    key                 = "Name"
    value               = "WebServer-ASG"
    propagate_at_launch = true
  }
}

# Output the ALB DNS name
output "alb_dns_name" {
  value = aws_lb.web_alb.dns_name
  description = "The DNS name of the load balancer"
}