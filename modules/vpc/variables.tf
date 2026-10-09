variable "vpc_config" {
  description = "VPC configuration"
  type = object({
    cidr       = string
    name       = optional(string, "capstone")
    nat_subnet = string
  })

  validation {
    condition     = contains([for s in var.subnets : s.name if s.type == "public"], var.vpc_config.nat_subnet)
    error_message = "nat_subnet must be the name of an existing public subnet."
  }
}

variable "subnets" {
  description = "Subnet configurations (name, CIDR, AZ, type)"
  type = list(object({
    name = string
    cidr = string
    az   = string
    type = string
  }))

  validation {
    condition     = alltrue([for s in var.subnets : contains(["public", "private"], s.type)])
    error_message = "Every subnet type must be either \"public\" or \"private\"."
  }
}