#customer gateway
resource "aws_customer_gateway" "customer_gateway" {
  bgp_asn    = "65000"
  ip_address = var.cgw_ip_address
  type       = "ipsec.1"
  tags = {
      Name        = "cgw-${var.name}"
      Client      = var.client
      Domain      = var.domain
      Environment = var.environment
  }

}

