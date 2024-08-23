terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create Public Subnet
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
}

# Create Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associate Route Table with Public Subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create Public SubnetTwo
resource "aws_subnet" "publicTwo" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1b"
}

# Associate Route Table with Public Subnet2
resource "aws_route_table_association" "publicTwo" {
  subnet_id      = aws_subnet.publicTwo.id
  route_table_id = aws_route_table.public.id
}


# Create Security Group
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
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
}

# Launch EC2 Instance with Node.js Application
resource "aws_instance" "web" {
  ami           = "ami-066784287e358dad1" 
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.web_sg.id]

  tags = {
    Name = "Expatswap-NodeJSApp"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              curl -sL https://rpm.nodesource.com/setup_14.x | bash -
              yum install -y nodejs git
              mkdir -p /var/www/nodeapp
              cd /var/www/nodeapp
              git clone https://github.com/emmaxyz90/expatswap.git .
              npm install
              npm start
            EOF
}

# Create Application Load Balancer
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public.id, aws_subnet.publicTwo.id]

  enable_deletion_protection = false
}

# Create Target Group
resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    port = "3000"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Attach EC2 Instance to Target Group
resource "aws_lb_target_group_attachment" "web_tg_attachment" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web.id
  port             = 3000
}

# Create Listener for ALB
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}



output "alb_dns_name" {
  value = aws_lb.web_alb.dns_name
}
