data "aws_vpc" "this" {
  tags = {
    Name = "${var.owner}-${var.env}"
  }
}

data "aws_subnet_ids" "this" {
  vpc_id = "${data.aws_vpc.this.id}"

  tags = {
    Tier = "pub"
  }
}

data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.this.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"]
}