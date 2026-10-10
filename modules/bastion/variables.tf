variable "bastion_config" {
  description = "Bastion hosts to create (unique name + public subnet name)"
  type = list(object({
    name   = string
    subnet = string
  }))

  validation {
    condition     = length(distinct([for b in var.bastion_config : b.name])) == length(var.bastion_config)
    error_message = "Bastion names must be unique."
  }

  validation {
    condition     = alltrue([for b in var.bastion_config : contains(keys(var.subnet_ids), b.subnet)])
    error_message = "Every bastion subnet must be the name of a subnet passed in subnet_ids."
  }
}

variable "subnet_ids" {
  description = "A map of public subnet IDs, keyed by subnet name"
  type        = map(string)
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC; the bastions may only SSH into this range"
  type        = string
}

variable "ami_id" {
  description = "The ID of the AMI to use for the bastion hosts"
  type        = string
}

variable "instance_type" {
  description = "The EC2 instance type to use"
  type        = string
}

variable "key_name" {
  description = "The name of the SSH key pair to use for the bastion hosts"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to the bastion hosts"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for the Name tags of the created resources"
  type        = string
}