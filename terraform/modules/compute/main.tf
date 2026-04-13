data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ---------- Security Groups ----------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg-${var.environment}"
  description = "Allow HTTPS inbound to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
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

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg-${var.environment}"
  description = "Allow traffic from ALB to app servers"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- Application Load Balancer ----------
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  access_logs {
    bucket  = "${var.project_name}-alb-logs-${var.environment}"
    enabled = false
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg-${var.environment}"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ---------- Launch Template ----------
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-${var.environment}-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "DB_HOST=${var.db_endpoint}" >> /etc/app.env
    echo "<h1>TechConsulting DR App - ${var.environment}</h1>" > /var/www/html/index.html
    echo "OK" > /var/www/html/health
  EOF
  )

  monitoring { enabled = true }

  lifecycle { create_before_destroy = true }
}

# ---------- Auto Scaling Group ----------
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg-${var.environment}"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-app-${var.environment}"
    propagate_at_launch = true
  }
}

# Scale-out when CPU > 70%
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-scale-out-${var.environment}"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 2
  cooldown               = 300
}

# Scale-in when CPU < 30%
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-scale-in-${var.environment}"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}
