resource "aws_key_pair" "this" {
  key_name   = var.key_pair.name
  public_key = var.key_pair.public_key
}

module "vpc" {
  source = "./modules/vpc"

  vpc_config = var.vpc_config
  subnets    = var.subnets
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