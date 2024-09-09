output "aws_vpc_id" {
  value = local.vpc_id
}

output "aws_subnets_public" {
  value = local.subnets_public
}

output "aws_subnets_private" {
  value = local.subnets_private
}

output "aws_eks_ec2_ssh_keypair" {
  value = local.eks_ec2_ssh_keypair
}

output "aws_eks_ec2_ssh_privkey_file" {
  value = local.create_eks_ssh_keypair == true ? local_sensitive_file.ssh_private_key[0].filename : "No local SSH key was created."
}

output "aws_eks_region" {
  value = regex(".*\\.([a-z0-9-]*)\\Q.eks.amazonaws.com\\E", aws_eks_cluster.simple_eks.endpoint)[0]
}

output "awk_eks_cluster_security_group" {
  value = aws_eks_cluster.simple_eks.cluster_security_group_id
}

output "kubeconfig_certificate_authority_data" {
  value = aws_eks_cluster.simple_eks.certificate_authority[0].data
}

output "kubeconfig_eks_cluster_name" {
  value = aws_eks_cluster.simple_eks.name
}

output "kubeconfig_eks_cluster_endpoint" {
  value = aws_eks_cluster.simple_eks.endpoint
}