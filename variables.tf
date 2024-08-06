variable "owner" {
  type = string
  default = "simple-eks"
}

variable "unique_name_prefix" {
  type = string
  default = "simple-eks"
}

variable "unique_name_suffix" {
  type = string
  default = ""
}

variable "eks_ec2_ssh_keypair" {
  description = "An AWS EC2 SSH keypair name to associate with EKS EC2 nodegroup instances."
  type = string
  default = ""
}

variable "admin_ip_cidrs" {
  type = list(string)
  default = []
}

variable "aws_region" {
  type = string
  default = "us-east-1"
}

variable "create_subnets_num" {
  type = number
  default = 3
  validation {
    condition = var.create_subnets_num > 0 && var.create_subnets_num <= 4
    error_message = "You must specify a number of subnets to create between 1 and 4."
  }
}

variable "aws_vpc_id" {
  type = string
  default = ""
}

variable "aws_vpc_cidr" {
  type = string
  default = "10.100.0.0/16"
}

variable "eks_subnets_public" {
  type = list(string)
  default = []
}

variable "eks_subnets_public_tags" {
  type = map(string)
  default = {}
}

variable "eks_subnets_private" {
  type = list(string)
  default = []
}

variable "eks_subnets_private_tags" {
  type = map(string)
  default = {}
}

variable "eks_debug_instance_type" {
  type = string
  default = "t3.small"
}

variable "eks_debug_instance_ami" {
  type = string
  default = ""
}

variable "eks_k8s_version" {
  type = string
  default = "1.30"
}

variable "eks_ec2_nodegroup_size" {
  type = number
  default = 3
}

variable "eks_ec2_nodegroup_instancetype" {
  type = string
  default = "m5.large"
}

variable "eks_nodegroup_public" {
  description = "Whether the node group should be created in public subnets.  If false, it will be created in private subnets."
  type = bool
  default = false
}

variable "eks_service_cidr" {
  description = "Default service CIDR for the EKS cluster.  If you specify creation in an existing VPC, you may need to change this."
  type = string
  default = "10.10.0.0/16"
}

variable "eks_additional_admin_arns" {
  type = list(string)
  default = []
}