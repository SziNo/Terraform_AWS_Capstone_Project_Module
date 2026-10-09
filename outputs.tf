output "vpc" {
  description = "VPC summary"
  value       = format("%s (%s)", module.vpc.vpc_id, var.vpc_config.cidr)
}

output "public_subnets" {
  description = "Public subnets: name -> ID"
  value       = module.vpc.public_subnet_ids
}

output "private_subnets" {
  description = "Private subnets: name -> ID"
  value       = module.vpc.private_subnet_ids
}

output "nat_public_ip" {
  description = "Public IP of the NAT gateway (outbound IP of the private subnets)"
  value       = module.vpc.nat_public_ip
}