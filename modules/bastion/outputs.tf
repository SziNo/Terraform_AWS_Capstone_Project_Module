output "public_ips" {
  description = "Public IPs of the bastion hosts, keyed by bastion name"
  value       = { for k, v in aws_instance.this : k => v.public_ip }
}

output "instance_ids" {
  description = "IDs of the bastion hosts, keyed by bastion name"
  value       = { for k, v in aws_instance.this : k => v.id }
}

output "security_group_id" {
  description = "ID of the bastion security group, used by the EC2 module to allow SSH"
  value       = aws_security_group.this.id
}