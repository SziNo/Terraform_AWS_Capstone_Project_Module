locals {
  bastions = { for b in var.bastion_config : b.name => b }
}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Security group for bastion hosts"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-bastion-sg"
  }
}

# Rules are separate resources instead of inline blocks, so other modules
# can attach their own rules to this group without conflicting with these.
resource "aws_vpc_security_group_ingress_rule" "ssh_from_allowed_cidr" {
  security_group_id = aws_security_group.this.id
  description       = "SSH from the allowed CIDR"
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# The bastion's only job is forwarding SSH into the VPC, so outbound
# traffic is limited to that instead of allowing everything.
resource "aws_vpc_security_group_egress_rule" "ssh_to_vpc" {
  security_group_id = aws_security_group.this.id
  description       = "SSH into the VPC (private instances)"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# Bastion hosts
resource "aws_instance" "this" {
  for_each = local.bastions

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[each.value.subnet]
  vpc_security_group_ids      = [aws_security_group.this.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.name_prefix}-${each.key}"
  }
}