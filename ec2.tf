# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create a default VPC if one does not exist
resource "aws_default_vpc" "default_vpc" {
  tags = {
    Name = "default vpc"
  }
}

# Use data source to get all availability zones in the region
data "aws_availability_zones" "available_zones" {}

# Create a default subnet if one does not exist
resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.available_zones.names[0]

  tags = {
    Name = "default subnet"
  }
}

# Create a second subnet in a different Availability Zone
resource "aws_default_subnet" "default_az2" {
  availability_zone = data.aws_availability_zones.available_zones.names[1]

  tags = {
    Name = "default subnet 2"
  }
}

# Create a security group for the EC2 instance
resource "aws_security_group" "ec2_security_group" {
  name        = "ec2 security group"
  description = "allow access on ports 8080 and 22"
  vpc_id      = aws_default_vpc.default_vpc.id

  ingress {
    description = "http proxy access"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins server security group"
  }
}

# Use data source to get a registered Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

# Launch the EC2 instances
resource "aws_instance" "ec2_instance" {
  count                  = 2
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.small"
  subnet_id              = aws_default_subnet.default_az1.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  key_name               = "ec2-key"

  tags = {
    Name = "master."
  }
}

# Create an Application Load Balancer (ALB)
resource "aws_lb" "my_alb" {
  name               = "my-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_security_group.id]
  subnets            = [
    aws_default_subnet.default_az1.id,
    aws_default_subnet.default_az2.id,
  ]

  tags = {
    Name = "my-load-balancer"
  }
}

# Create a target group for the ALB
resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 8080  # Assuming your instances listen on port 8080
  protocol = "HTTP"
  vpc_id   = aws_default_vpc.default_vpc.id

  health_check {
    protocol            = "HTTP"
    port                = 8080
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }

  tags = {
    Name = "my-target-group"
  }
}

# Attach EC2 instances to the target group
resource "aws_lb_target_group_attachment" "ec2_target_attachment" {
  for_each         = toset([for instance in aws_instance.ec2_instance : instance.id])
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id        = each.key
  port             = 8080
}
