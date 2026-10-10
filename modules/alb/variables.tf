variable "subnet_ids" {
  description = "A map of public subnet IDs, keyed by subnet name"
  type        = map(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An Application Load Balancer needs at least two subnets (in different AZs)."
  }
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC; the ALB may only send traffic into this range"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for the names and Name tags of the created resources"
  type        = string
}

variable "target_instance_ids" {
  description = "Instance IDs to register in the target group, keyed by instance name"
  type        = map(string)
}

variable "health_check_path" {
  description = "HTTP path the target group uses for health checks"
  type        = string
  default     = "/health"
}