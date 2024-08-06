# simple-eks
A simple Terraform config to create a small EKS cluster suitable for demos and other non-prod uses.

> [!WARNING]
> Do not use this code for a production EKS cluster.  It is provided for educational purposes only, primarily for use preparing EKS clusters suitable for running demos.

If you already have subnets created with appropriate networking, you can supply their IDs as a list in the variables `aws_vpc_id`, `eks_subnets_public` and (optionally) `eks_subnets_private`.  In that case routing tables, security group rules and gateways, along with the associations between them, will *not* be created in the supplied subnets.