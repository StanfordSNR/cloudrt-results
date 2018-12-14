# I am creating the eks cluster following this guide
# https://www.terraform.io/docs/providers/aws/guides/eks-getting-started.html
provider "aws" {
  region                  = "us-west-2"
}

variable "cluster-name" {
  default = "cloudrt-cluster"
  type    = "string"
}

# This data source is included for ease of sample architecture deployment
# and can be swapped out as necessary.
data "aws_availability_zones" "available" {}

resource "aws_vpc" "cloudrt" {
  cidr_block = "10.0.0.0/16"

  tags = "${
    map(
     "Name", "cloudrt-node",
     "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
  }"
}


resource "aws_subnet" "cloudrt" {
  count = 2

  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = "${aws_vpc.cloudrt.id}"

  tags = "${
    map(
     "Name", "cloudrt-node",
     "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
  }"
}


resource "aws_internet_gateway" "cloudrt" {
  vpc_id = "${aws_vpc.cloudrt.id}"

  tags {
    Name = "terraform-eks-cloudrt"
  }
}

resource "aws_route_table" "cloudrt" {
  vpc_id = "${aws_vpc.cloudrt.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.cloudrt.id}"
  }
}

resource "aws_route_table_association" "cloudrt" {
  count = 2

  subnet_id      = "${aws_subnet.cloudrt.*.id[count.index]}"
  route_table_id = "${aws_route_table.cloudrt.id}"
}

resource "aws_iam_role" "cloudrt-cluster" {
  name = "terraform-eks-cloudrt-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "cloudrt-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.cloudrt-cluster.name}"
}

resource "aws_iam_role_policy_attachment" "cloudrt-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.cloudrt-cluster.name}"
}

resource "aws_security_group" "cloudrt-cluster" {
  name        = "terraform-eks-cloudrt-cluster"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.cloudrt.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "terraform-eks-cloudrt"
  }
}

# TODO: outbound security group

# OPTIONAL: Allow inbound traffic from your local workstation external IP
#           to the Kubernetes. You will need to replace A.B.C.D below with
#           your real IP. Services like icanhazip.com can help you find this.
# resource "aws_security_group_rule" "cloudrt-cluster-ingress-workstation-https" {
#   cidr_blocks       = ["128.12.252.4/32"]
#   description       = "Allow workstation to communicate with the cluster API Server"
#   from_port         = 443
#   protocol          = "tcp"
#   security_group_id = "${aws_security_group.cloudrt-cluster.id}"
#   to_port           = 443
#   type              = "ingress"
# }


resource "aws_eks_cluster" "cloudrt" {
  name            = "${var.cluster-name}"
  role_arn        = "${aws_iam_role.cloudrt-cluster.arn}"

  vpc_config {
    security_group_ids = ["${aws_security_group.cloudrt-cluster.id}"]
    subnet_ids         = ["${aws_subnet.cloudrt.*.id}"]
  }

  depends_on = [
    "aws_iam_role_policy_attachment.cloudrt-cluster-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.cloudrt-cluster-AmazonEKSServicePolicy",
  ]
}

resource "aws_iam_role" "cloudrt-node" {
  name = "terraform-eks-cloudrt-node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "cluster-autoscaler" {
  name        = "cloudrtEKSClusterAutoScalerPolicy"
  description = "Allow cluster autoscaler to manage node pool sizes"
  policy      = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup"
            ],
            "Resource": "*"
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "cloudrt-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.cloudrt-node.name}"
}

resource "aws_iam_role_policy_attachment" "cloudrt-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.cloudrt-node.name}"
}

resource "aws_iam_role_policy_attachment" "cloudrt-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.cloudrt-node.name}"
}

resource "aws_iam_role_policy_attachment" "cloudrt-node-cloudrtEKSClusterAutoScalerPolicy" {
  policy_arn = "${aws_iam_policy.cluster-autoscaler.arn}"
  role       = "${aws_iam_role.cloudrt-node.name}"
}

resource "aws_iam_instance_profile" "cloudrt-node" {
  name = "terraform-eks-cloudrt"
  role = "${aws_iam_role.cloudrt-node.name}"
}

resource "aws_security_group" "cloudrt-node" {
  name        = "terraform-eks-cloudrt-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.cloudrt.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "terraform-eks-cloudrt-node",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}

resource "aws_security_group_rule" "cloudrt-node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.cloudrt-node.id}"
  source_security_group_id = "${aws_security_group.cloudrt-node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "cloudrt-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.cloudrt-node.id}"
  source_security_group_id = "${aws_security_group.cloudrt-cluster.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "cloudrt-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.cloudrt-cluster.id}"
  source_security_group_id = "${aws_security_group.cloudrt-node.id}"
  to_port                  = 443
  type                     = "ingress"
}

## Image for worker nodes
data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# This data source is included for ease of sample architecture deployment
# and can be swapped out as necessary.
data "aws_region" "current" {}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We utilize a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html

## TODO: add node labels using https://stackoverflow.com/questions/51432341/eks-node-labels
locals {
  cloudrt-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.cloudrt.endpoint}' --b64-cluster-ca '${aws_eks_cluster.cloudrt.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA
}

resource "aws_launch_configuration" "cloudrt" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.cloudrt-node.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  # TODO: change
  instance_type               = "m4.large"
  name_prefix                 = "terraform-eks-cloudrt"
  security_groups             = ["${aws_security_group.cloudrt-node.id}"]
  user_data_base64            = "${base64encode(local.cloudrt-node-userdata)}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "cloudrt" {
  desired_capacity     = 1
  launch_configuration = "${aws_launch_configuration.cloudrt.id}"
  max_size             = 2
  min_size             = 0
  name                 = "terraform-eks-cloudrt"
  vpc_zone_identifier  = ["${aws_subnet.cloudrt.*.id}"]

  tag {
    key                 = "Name"
    value               = "terraform-eks-cloudrt"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }


  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = true
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster-name}"
    value               = true
    propagate_at_launch = true
  }


  depends_on = ["aws_eks_cluster.cloudrt"]
}

locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH


apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.cloudrt-node.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH
}

data "aws_caller_identity" "current" {}

output "account_id" {
  value = "${data.aws_caller_identity.current.account_id}"
}

output "caller_arn" {
  value = "${data.aws_caller_identity.current.arn}"
}

output "caller_user" {
  value = "${data.aws_caller_identity.current.user_id}"
}

output "cluster_arn" {
  value = "${aws_eks_cluster.cloudrt.arn}"
}

output "config_map_aws_auth" {
  value = "${local.config_map_aws_auth}"
}

