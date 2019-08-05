data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

locals {
  myip = "${chomp(data.http.myip.body)}/32"
  userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.this.endpoint}' --b64-cluster-ca '${aws_eks_cluster.this.certificate_authority.0.data}' '${aws_eks_cluster.this.id}'
USERDATA
}

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
    values = ["amazon-eks-node-${var.eks_version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"]
}