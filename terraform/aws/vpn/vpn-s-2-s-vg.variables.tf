
variable "cgw_ip_address" {
  description = "IP address of the client VPN endpoint"
  type        = string
}

variable "vpc-id" {
  description = "vpc id"
  type        = string
}

variable "vpn_cidr_block" {
  description = "List of CIDRs to be routed into the VPN tunnel."
  type        = list
  default     = []
}

#tags
variable "name" {
  description = "Name to be used on all the resources as identifier"
  default     = ""
}

variable "client" {
  description = "Client name, lower case and without spaces. This will be used to set tags and name resources"
  type        = string
}

variable "environment" {
  description = "environment name, lower case and without spaces. This will be used for tagging"
  type        = string
}

variable "domain" {
  description = "Base domain to attach the tenant to."
  type        = string
}
