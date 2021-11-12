resource "aws_vpn_connection" "vpn" {
  vpn_gateway_id      = var.vpn-gateway-id
  customer_gateway_id = var.customer-gateway-id
  type                = "ipsec.1"
  static_routes_only  = true
  tags = {
   Name        = "vpn-${var.name}"
   Client      = var.client
   Domain      = var.domain
   Environment = var.environment
  }
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_vpn_connection_route" "office" {
  count = length(var.office-private-cidr)
  destination_cidr_block = var.office-private-cidr[count.index]
  vpn_connection_id      = aws_vpn_connection.vpn.id
}

