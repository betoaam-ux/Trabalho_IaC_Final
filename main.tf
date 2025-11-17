provider "aws" {
  region = "us-east-1"
}

# -----------------------------
# VPC
# -----------------------------
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "iac-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# -----------------------------
# Subnets (Zone A e B)
# -----------------------------
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# -----------------------------
# Route table
# -----------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------
# Security Group
# -----------------------------
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

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

# -----------------------------
# Launch Template
# -----------------------------
resource "aws_launch_template" "web_template" {
  name_prefix = "web-template"

  image_id      = "ami-0c02fb55956c7d316" # Amazon Linux 2
  instance_type = "t2.micro"

  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
  }

  user_data = base64encode(<<EOF
#!/bin/bash
sudo yum update -y
sudo yum install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
EOF
  )
}

# -----------------------------
# Target Group
# -----------------------------
resource "aws_lb_target_group" "tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# -----------------------------
# Application Load Balancer
# -----------------------------
resource "aws_lb" "alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -----------------------------
# Auto Scaling Group
# -----------------------------
resource "aws_autoscaling_group" "asg" {
  name                      = "web-asg"
  max_size                  = 4
  min_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 30
  health_check_type         = "EC2"

  vpc_zone_identifier = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg.arn]
}

# Auto Scaling Policy (CPU > 80%)
resource "aws_cloudwatch_metric_alarm" "cpu_alarm_high" {
  alarm_name          = "HighCPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
}
