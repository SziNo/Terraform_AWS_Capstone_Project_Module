resource "aws_key_pair" "this" {
  key_name   = var.key_pair.name
  public_key = var.key_pair.public_key
}

module "vpc" {
  source = "./modules/vpc"

  vpc_config = var.vpc_config
  subnets    = var.subnets
}

module "bastion" {
  source = "./modules/bastion"

  bastion_config   = var.bastion_config
  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = module.vpc.vpc_cidr
  allowed_ssh_cidr = var.allowed_ssh_cidr
  subnet_ids       = module.vpc.public_subnet_ids
  ami_id           = data.aws_ami.amazon_linux.id
  instance_type    = var.instance_type
  key_name         = aws_key_pair.this.key_name
  name_prefix      = var.project
}

module "ec2" {
  source = "./modules/ec2-instance"

  ec2_config    = var.ec2_config
  subnet_ids    = module.vpc.private_subnet_ids
  vpc_id        = module.vpc.vpc_id
  ami_id        = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.this.key_name
  name_prefix   = var.project
  user_data     = file("${path.module}/scripts/ec2-userdata.sh")

  bastion_security_group_id = module.bastion.security_group_id
}

module "alb" {
  source = "./modules/alb"

  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.vpc_cidr
  subnet_ids          = module.vpc.public_subnet_ids
  target_instance_ids = module.ec2.instance_ids
  name_prefix         = var.project
}

# Connects two modules: lets the ALB (source) reach the EC2 instances (destination) on port 80.
# Lives in the root so neither module has to know about the other.
resource "aws_vpc_security_group_ingress_rule" "http_from_alb_to_ec2" {
  security_group_id            = module.ec2.security_group_id
  referenced_security_group_id = module.alb.security_group_id
  description                  = "HTTP from the ALB to the EC2 instances"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}