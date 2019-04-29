resource "aws_iam_role" "worker" {
  name = "${var.owner}-${var.env}-${var.project}-worker"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  tags = {
      owner   = "${var.owner}"
      project = "${var.project}"
      env     = "${var.env}"
  }
}

resource "aws_iam_role_policy_attachment" "worker_00" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.worker.name}"
}

resource "aws_iam_role_policy_attachment" "worker_01" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.worker.name}"
}

resource "aws_iam_role_policy_attachment" "worker_02" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.worker.name}"
}

resource "aws_iam_role_policy_attachment" "worker_03" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  role       = "${aws_iam_role.worker.name}"
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.owner}-${var.env}-${var.project}-worker"
  role = "${aws_iam_role.worker.name}"
}

resource "aws_security_group" "worker" {
  name        = "${var.owner}-${var.env}-${var.project}-worker"
  description = "Allow inbound traffic for worker"
  vpc_id      = "${data.aws_vpc.this.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.this.endpoint}' --b64-cluster-ca '${aws_eks_cluster.this.certificate_authority.0.data}' '${var.owner}-${var.env}'
USERDATA
}

resource "aws_launch_configuration" "this" {
  image_id             = "${data.aws_ami.eks-worker.id}"
  name_prefix          = "${var.owner}-${var.env}-${var.project}-"
  instance_type        = "${var.instance_type}"
  spot_price           = "${var.spot_price}"
  iam_instance_profile = "${aws_iam_instance_profile.worker.arn}"
  enable_monitoring    = true
  ebs_optimized        = false
  security_groups      = ["${aws_security_group.worker.id}"]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 30
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }

  user_data_base64        = "${base64encode(local.userdata)}"
}

resource "aws_autoscaling_group" "this" {
  name_prefix               = "${var.owner}-${var.env}-${var.project}-"
  launch_configuration      = "${aws_launch_configuration.this.name}"
  max_size                  = "${var.desired_capacity}"
  min_size                  = "${var.desired_capacity}"
  desired_capacity          = "${var.desired_capacity}"
  vpc_zone_identifier       = ["${data.aws_subnet_ids.this.ids}"]
  metrics_granularity       = "1Minute"
  enabled_metrics           = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]

  tag {
    key                 = "Name"
    value               = "${var.owner}-${var.env}-${var.project}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Owner"
    value               = "${var.owner}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = "${var.project}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Env"
    value               = "${var.env}"
    propagate_at_launch = true
  }
  tag {
    key                 = "kubernetes.io/cluster/${var.owner}-${var.env}"
    value               = "owned"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# politicas de escalamiento
resource "aws_autoscaling_policy" "up" {
  name                   = "${var.owner}-${var.env}-${var.project}-cpu-up"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.this.name}"
  policy_type            = "StepScaling"

  step_adjustment {
    scaling_adjustment = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 10
  }
  step_adjustment {
    scaling_adjustment = 2
    metric_interval_lower_bound = 10
  }
}
resource "aws_cloudwatch_metric_alarm" "up" {
  alarm_name          = "${var.owner}-${var.env}-${var.project}-cpu-up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 75

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.this.name}"
  }

  alarm_description = "Auto Scaling Increase CPU"
  alarm_actions     = ["${aws_autoscaling_policy.up.arn}"]
}

resource "aws_autoscaling_policy" "down" {
  name                   = "${var.owner}-${var.env}-${var.project}-cpu-down"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.this.name}"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "down" {
  alarm_name          = "${var.owner}-${var.env}-${var.project}-cpu-down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 35

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.this.name}"
  }

  alarm_description = "Auto Scaling Decrease CPU"
  alarm_actions     = ["${aws_autoscaling_policy.down.arn}"]
}