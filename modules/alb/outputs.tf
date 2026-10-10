output "dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.this.dns_name
}

output "security_group_id" {
  description = "ID of the ALB security group, used to allow traffic from the ALB to the targets"
  value       = aws_security_group.this.id
}