variable "ec2_config" {
  description = "A map of EC2 instance counts per subnet (subnet name => count)"
  type        = map(number)

  validation {
    condition     = alltrue([for subnet in keys(var.ec2_config) : contains(keys(var.subnet_ids), subnet)])
    error_message = "Every key in ec2_config must be the name of a subnet passed in subnet_ids."
  }
}

variable "subnet_ids" {
  description = "A map of subnet IDs, keyed by subnet name"
  type        = map(string)
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "ami_id" {
  description = "The ID of the AMI to use for the EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "The EC2 instance type to use"
  type        = string
}

variable "key_name" {
  description = "The name of the SSH key pair to use for the EC2 instances"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for the Name tags of the created resources"
  type        = string
}

variable "user_data" {
  description = "Optional user data script for the instances"
  type        = string
  default     = null
}

variable "bastion_security_group_id" {
  description = "Security group ID of the bastion hosts, allowed to SSH into the instances"
  type        = string
}