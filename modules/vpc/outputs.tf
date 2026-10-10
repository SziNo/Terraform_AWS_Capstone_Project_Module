output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, keyed by subnet name"
  value       = { for k, v in aws_subnet.public : k => v.id }

  depends_on = [aws_route_table_association.public]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, keyed by subnet name"
  value       = { for k, v in aws_subnet.private : k => v.id }

  # Consumers wait until the NAT route is in place, so instances launched
  # into these subnets have outbound internet access at boot.
  depends_on = [aws_route_table_association.private]
}

output "nat_public_ip" {
  description = "Public IP of the NAT gateway"
  value       = aws_eip.this.public_ip
}