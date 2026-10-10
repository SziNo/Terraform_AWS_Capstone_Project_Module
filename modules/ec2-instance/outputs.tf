output "instance_ids" {
  description = "IDs of the EC2 instances, keyed by instance name"
  value       = { for k, v in aws_instance.this : k => v.id }
}

output "private_ips" {
  description = "Private IPs of the EC2 instances, keyed by instance name"
  value       = { for k, v in aws_instance.this : k => v.private_ip }
}

output "security_group_id" {
  description = "ID of the EC2 security group, so other modules can attach rules to it"
  value       = aws_security_group.this.id
}