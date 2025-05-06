/* NB05022025 -- This is an example of Declarative Infrastructure as Code (IaC) using Terraform. 
   It is designed to be run in a local environment with AWS credentials configured. 
   The script creates a web application architecture on AWS, including VPC, subnets, 
   security groups, an Application Load Balancer (ALB), and an Auto Scaling Group (ASG). 
   The script is modular and can be easily modified to suit different requirements. 
   It is important to ensure that the AWS region and AMI ID are appropriate for your use case. 
   Please review the script carefully before running it in your environment. */

# Configure the AWS provider
provider "aws" {
  region = "us-east-2" # Or your desired region
}

# Create an EC2 instance
resource "aws_instance" "example" {
  ami = "ami-096af71d77183c8f8" # Replace with the appropriate AMI ID
  instance_type = "t2.micro"
  tags = {
    Name = "example-instance"
  }
}

# Create an S3 bucket
resource "aws_s3_bucket" "example" {
  bucket = "sample-terraform-bucket2211223" # Unique bucket name
  tags = {
    Name = "example-bucket"
  }
}