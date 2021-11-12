
#Customer Gateway
module "cgw" {
  source = "./aws-cgw"
  cgw_ip_address = var.cgw_ip_address
   name          = var.name
   client        = var.client
   domain        = var.domain
   environment   = var.environment

}

#virtual private gateway
module "vgw" {
  source = "./aws-vgw"
  vpc-id         = var.vpc-id
   name          = var.name
   client        = var.client
   domain        = var.domain
   environment   = var.environment
}

#site to site connection
module "vpn-connection" {
  source = "./aws-vpn-connection"
  customer-gateway-id   = module.cgw.customer_gateway
  vpn-gateway-id        = module.vgw.vgw
  vpc-id                = var.vpc-id
  office-private-cidr   = var.vpn_cidr_block
  name                  = var.name
  client                = var.client
  domain                = var.domain
  environment           = var.environment
}


