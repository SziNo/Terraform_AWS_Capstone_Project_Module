output "vpc" {
  description = "VPC summary"
  value       = format("%s (%s)", module.vpc.vpc_id, module.vpc.vpc_cidr)
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

output "bastions" {
  description = "Bastion hosts: name, instance ID, public IP"
  value = [
    for name, ip in module.bastion.public_ips :
    format("%-12s %-22s %s", name, module.bastion.instance_ids[name], ip)
  ]
}

output "ec2_instances" {
  description = "Private EC2 instances: name, instance ID, private IP"
  value = [
    for name, ip in module.ec2.private_ips :
    format("%-12s %-22s %s", name, module.ec2.instance_ids[name], ip)
  ]
}

output "ssh_bastions" {
  description = "SSH commands for the bastion hosts"
  value = {
    for name, ip in module.bastion.public_ips :
    name => "ssh -i ${local.ssh_key_path} ec2-user@${ip}"
  }
}

output "ssh_ec2_instances" {
  description = "SSH commands for the private instances via a bastion (run ssh-add first)"
  value = {
    for name, ip in module.ec2.private_ips :
    name => "ssh -J ec2-user@${local.jump_bastion_ip} ec2-user@${ip}"
  }
}