#ASHOK
# TODO: VPN MODULE
module "vpn" {
  source = "./vpn"
  count      = var.create_p2p_vpn ? 1 : 0
  cgw_ip_address      = var.cgw_ip_address
  vpc-id              = module.vpc.vpc_id
  vpn_cidr_block = var.vpn_cidr_block
  name        = local.name
  environment = var.environment
      client = var.client
      domain = var.domain
}

variable "cgw_ip_address" {
  description = "IP address of the client VPN endpoint"
  type        = string
}


variable "vpn_cidr_block" {
  description = "List of CIDRs to be routed into the VPN tunnel."
  type        = list
  default     = []
}


##vpn switch enable/disable 
variable "create_p2p_vpn" {
  description = "set up p2p vpn"
#  type        = string
#  default     = "no"
  default     = false
  type        = bool
}

