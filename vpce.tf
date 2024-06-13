# Define locals to configure deployment
locals {
  vpc_cidr = var.cidr_block
  prefix   = var.prefix
  tags = {
    Service = "${var.service_name}"
    Owner   = "${var.user_name}"
  }

}

# Create IAM Policy for Lambda execution IAM role
resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.prefix}-lambda_asg_policy"
  description = "IAM Policy for Lambda to assign EIPs to proxy servers"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "autoscaling:CompleteLifecycleAction"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress",
          "ec2:DescribeInstances",
          "ec2:DescribeAddresses",
          "ec2:CreateTags"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : "logs:CreateLogGroup",
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      }
    ]
  })
}

# Create Lambda execution IAM role
resource "aws_iam_role" "lambda_role" {
  name = "${local.prefix}-lambda-asg-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "Lambda Execution IAM Role"
    },
    local.tags
  )
}

# Attach IAM Policy to Lambda execution IAM role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Create Lambda Function
resource "aws_lambda_function" "assign_eip" {
  filename         = "${path.module}/scripts/lambda_function.zip"
  function_name    = "${local.prefix}-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("${path.module}/scripts/lambda_function.zip")
  timeout          = 10

  environment {
    variables = {
      EIP_TAG_KEY = "${var.eip_tag_key}"
    }
  }

  tags = merge(
    {
      Name = "Lambda Function for EIP Assignment"
    },
    local.tags
  )
}


# Create networking VPC resources

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${local.prefix}-vpc"
  cidr = local.vpc_cidr
  azs  = data.aws_availability_zones.available.names
  tags = local.tags

  enable_dns_hostnames = true

  enable_nat_gateway = false

  create_igw = true

  public_subnets = [cidrsubnet(local.vpc_cidr, 8, 1),
    cidrsubnet(local.vpc_cidr, 8, 2),
    cidrsubnet(local.vpc_cidr, 8, 3)
  ]

  private_subnets = [cidrsubnet(local.vpc_cidr, 8, 4),
    cidrsubnet(local.vpc_cidr, 8, 5),
    cidrsubnet(local.vpc_cidr, 8, 6)
  ]
}

# Allocate EIPs for the EIP pool
resource "aws_eip" "eip_pool" {
  count  = var.eip_pool_size
  domain = "vpc"

  tags = merge(
    {
      Name = "${local.prefix}-eip"
    },
    {
      "${var.eip_tag_key}" = ""
    },
    local.tags
  )
}


# Create security group for the Launch Template
resource "aws_security_group" "lt_sg" {
  name        = "${local.prefix}-launch-template-sg"
  description = "Dedicated security group for Launch Template that will be attached to each proxy server"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow 443 NLB ingress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    security_groups = [aws_security_group.nlb_sg.id]
  }

/* Optionlly, you can whitelist your VPN IP so that you can SSH into the proxy server from your laptop to configure it

  ingress {
    description = "Allow SSH from your corporate VPN IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    cidr_blocks = ["12.34.56.78/32"]
  }
*/

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = "Launch Template Security Group"
    },
    local.tags
  )
}

# Get the AMI ID for the Launch Template
data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

#Create the Launch Template
resource "aws_launch_template" "aoai_lt" {
  name                   = "${local.prefix}-launch-template"
  image_id               = data.aws_ami.linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.lt_sg.id]

  user_data = filebase64("${path.module}/scripts/haproxy_init.sh")

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      {
        Name = "${local.prefix}-proxy-server"
      },
      local.tags
    )
  }
}

# Create the Auto Scaling Group
resource "aws_autoscaling_group" "aoai_asg" {
  name                      = "${local.prefix}-asg"
  desired_capacity          = 0 # desired capacity set to 0 initially and will be updated to the actual value once lifecycle hook is created
  max_size                  = var.asg_max_size
  min_size                  = 0 # minimum capacity set to 0 initially and will be updated to the actual value once lifecycle hook is created
  health_check_grace_period = 300
  health_check_type         = "EC2"
  vpc_zone_identifier       = module.vpc.public_subnets
  target_group_arns         = ["${aws_lb_target_group.target_group.arn}"]

  launch_template {
    id      = aws_launch_template.aoai_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Owner"
    value               = var.user_name
    propagate_at_launch = true
  }

  depends_on = [
    aws_eip.eip_pool,
    aws_lambda_function.assign_eip
  ]
}

# Create the Auto Scaling Group Lifecycle Hook
resource "aws_autoscaling_lifecycle_hook" "asg_lifecycle_hook" {
  name                   = "${local.prefix}-asg-lifecycle-hook"
  autoscaling_group_name = aws_autoscaling_group.aoai_asg.name
  heartbeat_timeout      = 30
  default_result         = "ABANDON"
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
}

# Update the Auto Scaling Group size to set the proxy EC2 instances to the desired number
resource "null_resource" "update_asg_size" {
  depends_on = [aws_autoscaling_lifecycle_hook.asg_lifecycle_hook]
  provisioner "local-exec" {
    command = <<EOT
      sleep 15
      aws autoscaling update-auto-scaling-group --auto-scaling-group-name ${aws_autoscaling_group.aoai_asg.name} --min-size ${var.asg_min_size} --desired-capacity ${var.asg_desired_size} --profile ${var.aws_profile} --region ${var.region}
    EOT
  }
}

# Create EventBridge Rule for Auto Scaling Group Lifecycle Hook
resource "aws_cloudwatch_event_rule" "asg_lifecycle_rule" {
  name        = "${local.prefix}-lifecycle-rule"
  description = "Rule to capture Auto Scaling lifecycle events"
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-launch Lifecycle Action"]
    detail = {
      "AutoScalingGroupName" = ["${aws_autoscaling_group.aoai_asg.name}"]
    }
  })
}

# Specify EventBridge Target for Lambda
resource "aws_cloudwatch_event_target" "asg_lifecycle_target" {
  rule = aws_cloudwatch_event_rule.asg_lifecycle_rule.name
  arn  = aws_lambda_function.assign_eip.arn
}

# Grant EventBridge permission to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.assign_eip.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg_lifecycle_rule.arn
}

# Create security group for NLB
resource "aws_security_group" "nlb_sg" {
  name   = "${local.prefix}-nlb-sg"
  vpc_id = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = "NLB Security Group"
    },
    local.tags
  )
}


# Create NLB
resource "aws_lb" "nlb" {
  name               = "${local.prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb_sg.id]
  subnets            = module.vpc.private_subnets

  enable_deletion_protection = false

  enable_cross_zone_load_balancing = true

  enforce_security_group_inbound_rules_on_private_link_traffic = "off"

  tags = merge(
    {
      Name = "${local.prefix}-NLB"
    },
    local.tags
  )
}


# Create target group for the NLB listner
resource "aws_lb_target_group" "target_group" {
  name     = "${local.prefix}-tg"
  port     = 443
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  tags = merge(
    {
      Name = "${local.prefix}-target-group"
    },
    local.tags
  )

}


# Create NLB listner
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }

  tags = merge(
    {
      Name = "${local.prefix}-nlb-listener"
    },
    local.tags
  )
}


# Create endpoint service
resource "aws_vpc_endpoint_service" "aoai" {
  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.nlb.arn]
  allowed_principals         = var.allowed_principals

  tags = merge(
    {
      Name = "{local.prefix}-endpoint-service"
    },
    local.tags
  )
}