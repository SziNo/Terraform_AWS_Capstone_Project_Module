locals {
  # Flatten the per-subnet counts into one entry per instance:
  # { "private-a" = 2, "private-b" = 1 }
  #   => { "private-a-1" = "private-a", "private-a-2" = "private-a", "private-b-1" = "private-b" }
  instances = merge([
    for subnet, n in var.ec2_config : {
      for i in range(1, n + 1) : "${subnet}-${i}" => subnet
    }
  ]...)
}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "Security group for the private EC2 instances"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-ec2-sg"
  }
}

# Rules are separate resources instead of inline blocks, so other modules
# can attach their own rules to this group without conflicting with these.
resource "aws_vpc_security_group_ingress_rule" "ssh_from_bastion" {
  security_group_id            = aws_security_group.this.id
  description                  = "SSH from the bastion hosts"
  referenced_security_group_id = var.bastion_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "this" {
  for_each = local.instances

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[each.value]
  vpc_security_group_ids      = [aws_security_group.this.id]
  key_name                    = var.key_name
  associate_public_ip_address = false

  user_data                   = var.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.name_prefix}-${each.key}"
  }
}