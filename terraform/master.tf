resource "aws_iam_role" "master" {
  name = "${var.owner}-${var.env}-${var.project}-master"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "eks.amazonaws.com"
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

resource "aws_iam_role_policy_attachment" "master_00" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.master.name}"
}

resource "aws_iam_role_policy_attachment" "master_01" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.master.name}"
}

resource "aws_iam_role_policy_attachment" "master_02" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  role       = "${aws_iam_role.master.name}"
}

resource "aws_security_group" "master" {
  name        = "${var.owner}-${var.env}-${var.project}-master"
  description = "Allow inbound traffic for master"
  vpc_id      = "${data.aws_vpc.this.id}"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = ["${aws_security_group.worker.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eks_cluster" "this" {
  name     = "${var.owner}-${var.env}"
  role_arn = "${aws_iam_role.master.arn}"
  version  = 1.12

  vpc_config {
    security_group_ids     = ["${aws_security_group.master.id}"]
    subnet_ids             = ["${data.aws_subnet_ids.this.ids}"]
  }
  depends_on = [
    "aws_iam_role_policy_attachment.master_00",
    "aws_iam_role_policy_attachment.master_01",
    "aws_iam_role_policy_attachment.master_02"
  ]
}