terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Owner = var.owner
    }
  }
}

data "aws_region" "current" {}

# Filter out local zones, which are not currently supported 
# with managed node groups, and zone IDs which for some 
# unspecified-by-AWS reason are NOT ALLOWED to be part of 
# your EKS cluster.
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  state = "available"
  exclude_zone_ids = ["use1-az3", "usw1-az2", "cac1-az3"]
}

data "aws_caller_identity" "eks_creator" {}

data "aws_vpc" "simple_eks" {
  id = local.vpc_id
}

data "http" "admin_ip" {
  url = "https://whatismyip.akamai.com/"
}

data "aws_ssm_parameter" "al2023_eks" {
  name = "/aws/service/eks/optimized-ami/${var.eks_k8s_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}


resource "random_string" "unique_name_prefix" {
  length = 8
  upper = false
  special = false
}

resource "random_string" "unique_name_suffix" {
  length = 8
  upper = false
  special = false
}

locals {
  owner = coalesce(var.owner, data.aws_caller_identity.eks_creator.user_id)
  unique_name_prefix = coalesce(var.unique_name_prefix, random_string.unique_name_prefix.result)
  unique_name_suffix = coalesce(var.unique_name_suffix, random_string.unique_name_suffix.result)
  unique_name = "${var.unique_name_prefix}-eks-${local.unique_name_suffix}"
  eks_nodegroup_ami = data.aws_ssm_parameter.al2023_eks.value
  public_subnet_cidr = cidrsubnet(var.aws_vpc_cidr,2,0)
  private_subnet_cidr = cidrsubnet(var.aws_vpc_cidr,2,2)
  admin_ip_cidr = coalesce(var.admin_ip_cidr, "${data.http.admin_ip.response_body}/32")
  create_vpc = var.aws_vpc_id == "" ? true : false
  create_subnets_public = flatten(var.eks_subnets_public) == [] ? true : false
  create_subnets_private = flatten(var.eks_subnets_private) == [] ? true : false
  vpc_id = length(aws_vpc.simple_eks) > 0 ? aws_vpc.simple_eks[0].id : var.aws_vpc_id
  vpc_cidr = data.aws_vpc.simple_eks.cidr_block
  subnets_public = local.create_subnets_public ? aws_subnet.eks_public[*].id : var.eks_subnets_public
  subnets_private = local.create_subnets_private ? aws_subnet.eks_private[*].id : var.eks_subnets_private
  create_eks_admin_sg = var.eks_admin_sg == "" ? true : false
  eks_admin_sg = local.create_eks_admin_sg ? aws_security_group.eks_access[0].id : var.eks_admin_sg
  create_eks_ssh_keypair = var.eks_ec2_ssh_keypair == "" ? true : false
  eks_ec2_ssh_keypair = coalesce(var.eks_ec2_ssh_keypair,aws_key_pair.eks_instance[0].key_name)
}

resource "tls_private_key" "eks_instance" {
  count = local.create_eks_ssh_keypair == true ? 1 : 0
  algorithm = "ED25519"
}

resource "aws_key_pair" "eks_instance" {
  count = local.create_eks_ssh_keypair == true ? 1 : 0
  key_name = "eks-ssh-key-${local.unique_name_suffix}"
  public_key = tls_private_key.eks_instance[0].public_key_openssh
}

resource "local_sensitive_file" "ssh_private_key" {
  count = local.create_eks_ssh_keypair == true ? 1 : 0
  content = tls_private_key.eks_instance[0].private_key_openssh
  filename = "${path.root}/files/eks_node_ssh_privkey_${local.unique_name_suffix}"
  directory_permission = "0700"
  file_permission = "0600"
}

resource "aws_vpc" "simple_eks" {
  count = local.create_vpc ? 1 : 0
  cidr_block = var.aws_vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = local.unique_name
  }
}

resource "aws_internet_gateway" "eks_public" {
  count = local.create_subnets_public ? 1 : 0
  tags = {
    Name = "${local.unique_name}"
  }
}

resource "aws_internet_gateway_attachment" "eks_public" {
  count = local.create_subnets_public ? 1 : 0
  internet_gateway_id = aws_internet_gateway.eks_public[0].id
  vpc_id = local.vpc_id
}

resource "aws_subnet" "eks_public" {
  count = local.create_subnets_public ? var.create_subnets_num : 0
  vpc_id = local.vpc_id
  map_public_ip_on_launch = true
  cidr_block = cidrsubnet(local.public_subnet_cidr,3,count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge(var.eks_subnets_public_tags,
    {
      "Name" = "${local.unique_name}-public-${count.index}"
      "kubernetes.io/role/elb" = 1
    }
  )
}

resource "aws_route_table" "eks_public" {
  count = local.create_subnets_public ? 1 : 0
  vpc_id = local.vpc_id

  tags = {
    Name = "${local.unique_name}-public"
  }
}

resource "aws_route" "eks_public_ipv4_default" {
  count = local.create_subnets_public ? 1 : 0
  route_table_id = aws_route_table.eks_public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.eks_public[0].id
}

resource "aws_route_table_association" "eks_public" {
  count = local.create_subnets_public ? length(local.subnets_public) : 0
  subnet_id = local.subnets_public[count.index]
  route_table_id = aws_route_table.eks_public[0].id
}

resource "aws_subnet" "eks_private" {
  count = local.create_subnets_private ? var.create_subnets_num : 0
  vpc_id = local.vpc_id
  cidr_block = cidrsubnet(local.private_subnet_cidr,3,count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge(var.eks_subnets_private_tags,
    {
      "Name" = "${local.unique_name}-private-${count.index}"
      "kubernetes.io/role/internal-elb" = 1
    }
  )
}

resource "aws_eip" "eks_private_nat" {
  count = local.create_subnets_private ? 1 : 0
}

resource "aws_nat_gateway" "eks_private" {
  count = local.create_subnets_private ? 1 : 0
  subnet_id = local.subnets_public[0]
  allocation_id = aws_eip.eks_private_nat[0].id
  tags = {
    Name = "${local.unique_name}-private"
  }
}

data "aws_nat_gateway" "eks_private" {
  tags = {
    Name = "${local.unique_name}-private"
  }
}

resource "aws_route_table" "eks_private_nat" {
  count = local.create_subnets_private ? 1 : 0
  vpc_id = local.vpc_id
  
  tags = {
    Name = "${local.unique_name}-nat"
  }
}

resource "aws_route" "eks_private_ipv4_default" {
  count = local.create_subnets_private ? 1 : 0
  route_table_id = aws_route_table.eks_private_nat[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.eks_private[0].id
}

resource "aws_route_table_association" "eks_private_nat" {
  count = local.create_subnets_private ? length(local.subnets_private) : 0
  subnet_id = local.subnets_private[count.index]
  route_table_id = aws_route_table.eks_private_nat[0].id
}

resource "aws_security_group" "eks_access" {
  count = local.create_eks_admin_sg ? 1 : 0
  name = "${local.unique_name}-admin"
  vpc_id = local.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  count = local.create_eks_admin_sg ? 1 : 0
  security_group_id = local.eks_admin_sg
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "admin_ssh_inbound" {
  count = local.create_eks_admin_sg ? 1 : 0
  security_group_id = local.eks_admin_sg
  cidr_ipv4 = local.admin_ip_cidr
  from_port = 22
  to_port = 22
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "eks_inbound" {
  for_each = local.create_eks_admin_sg ? toset([for port in var.eks_ingress_ports: tostring(port)]) : toset([])
  security_group_id = local.eks_admin_sg
  cidr_ipv4 = local.admin_ip_cidr
  from_port = each.key
  to_port = each.key
  ip_protocol = "tcp"
}

data "aws_iam_policy_document" "eks_controlplane_assumerole" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "eks_ec2_assumerole" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster" {
  name = local.unique_name
  assume_role_policy = data.aws_iam_policy_document.eks_controlplane_assumerole.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "simple_eks" {
  name     = local.unique_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = local.subnets_public
    public_access_cidrs = flatten([ local.admin_ip_cidr, formatlist("%s/32", data.aws_nat_gateway.eks_private[*].public_ip)])
  }

  version = var.eks_k8s_version == "" ? null : var.eks_k8s_version

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.eks_service_cidr
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

resource "aws_eks_access_entry" "additional_admins" {
  count = length(var.eks_additional_admin_arns)
  cluster_name = aws_eks_cluster.simple_eks.name
  principal_arn = var.eks_additional_admin_arns[count.index]
}

resource "aws_eks_access_policy_association" "additional_admins" {
  count = length(var.eks_additional_admin_arns)
  cluster_name = aws_eks_cluster.simple_eks.name
  principal_arn = var.eks_additional_admin_arns[count.index]
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_iam_role" "eks_ec2_nodegroup" {
  name = "${local.unique_name}-nodegroup"
  assume_role_policy = data.aws_iam_policy_document.eks_ec2_assumerole.json
}

resource "aws_iam_role_policy_attachment" "eks_ec2_nodegroup_policy" {
  for_each = toset(["AmazonEKSWorkerNodePolicy", "AmazonEKS_CNI_Policy", "AmazonEC2ContainerRegistryReadOnly"])
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
  role = aws_iam_role.eks_ec2_nodegroup.name
}

resource "aws_eks_node_group" "ec2" {
  cluster_name = aws_eks_cluster.simple_eks.name
  node_group_name = "${local.unique_name}-nodegroup"
  version = aws_eks_cluster.simple_eks.version
  ami_type = "AL2023_x86_64_STANDARD"
  instance_types = [var.eks_ec2_nodegroup_instancetype]
  scaling_config {
    desired_size = var.eks_ec2_nodegroup_size
    min_size = 1
    max_size = var.eks_ec2_nodegroup_size
  }
  remote_access {
    ec2_ssh_key = local.eks_ec2_ssh_keypair
  }
  node_role_arn = aws_iam_role.eks_ec2_nodegroup.arn
  subnet_ids = var.eks_nodegroup_public ? local.subnets_public : local.subnets_private
}

# It should not be necessary to uncomment the following except to debug EKS worker nodes in a private subnet.
/*
data "aws_ami" "al2023" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  owners = ["amazon"]
}

resource "aws_instance" "eks_debug" {
  ami = coalesce(var.eks_debug_instance_ami,data.aws_ami.al2023.id)
  instance_type = var.eks_debug_instance_type
  subnet_id = local.subnets_public[0]
  key_name = local.eks_ec2_ssh_keypair
  security_groups = [ local.eks_admin_sg ]
  tags = {
    Name = "${local.unique_name}-debug"
  }
}
*/