###################################################################
#Module Name	:vpn                                                              
#Description	: site-2-site vpn module with VGW                               
#Ver           	:1                                                                                          
#Author       	:Ashok Shelke                  
#Email         	:shelkeashok9@gmail.com, ashok.shelke@modusbox.com                                           
###################################################################
module "vpn" {
  source = "./vpn"
  count      = var.create_p2p_vpn ? 1 : 0
  cgw_ip_address      = var.cgw_ip_address
  vpc-id              = module.vpc.vpc_id
  vpn_cidr_block = local.client_vpn_cidr_block
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
  default     = false
  type        = bool
}

#client vpn cidr
variable "vpn_client_ip_file" {
  default     = ""
  type        = string
  description = "file name to pull client vpn cidr ips from"
} 