# variables.tf (root)

variable "region" {
  description = "AWS region"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to the bastion hosts"
  type        = string
}

variable "project" {
  description = "Project name, used in default tags"
  type        = string
  default     = "capstone"
}

variable "environment" {
  description = "Environment name, used in default tags"
  type        = string
  default     = "dev"
}

variable "vpc_config" {
  description = "VPC configuration"
  type = object({
    cidr       = string
    name       = optional(string, "capstone")
    nat_subnet = string
  })
}

variable "subnets" {
  description = "Subnet configurations (name, CIDR, AZ, type)"
  type = list(object({
    name = string
    cidr = string
    az   = string
    type = string
  }))
}

variable "key_pair" {
  description = "SSH key pair shared by the bastion hosts and the EC2 instances"
  type = object({
    name       = string
    public_key = string
  })
}

variable "instance_type" {
  description = "EC2 instance type for all instances"
  type        = string
  default     = "t2.micro"

  validation {
    condition     = var.instance_type == "t2.micro"
    error_message = "Only t2.micro is allowed, as it is the only free tier eligible type in this account."
  }
}

variable "ec2_config" {
  description = "Number of EC2 instances per private subnet (subnet name => count)"
  type        = map(number)

  validation {
    condition     = alltrue([for n in values(var.ec2_config) : n >= 0 && floor(n) == n])
    error_message = "Instance counts must be non-negative whole numbers."
  }
}