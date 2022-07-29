resource "aws_vpc_peering_connection" "iac_pc" {
  count = var.create_vpc_peering == true ? 1 : 0
  peer_vpc_id = var.peer_vpc_id
  vpc_id = module.vpc.vpc_id
  auto_accept = true

  accepter {
    allow_remote_vpc_dns_resolution = false
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }
  tags = merge({ Name = "${local.name}-vpc-peer-conn-iac_pc" }, local.common_tags)
}

data "aws_route_tables" "k3s_private_rts" {
  count = var.create_vpc_peering == true ? 1 : 0
  vpc_id = module.vpc.vpc_id
  
  filter {
    name   = "tag:subnet-type"
    values = ["private-k3s"]
  }
  filter {
    name   = "tag:Client"
    values = [var.client]
  }
  depends_on = [module.vpc]
}

data "aws_route_table" "switch_management_rt" {
  count = var.create_vpc_peering == true ? 1 : 0
  vpc_id = var.peer_vpc_id

  filter {
    name   = "tag:Name"
    values = ["*-public-management"]
  }
}

resource "aws_route" "vpc-peering-route-to-k3s" {
    count = var.create_vpc_peering == true ? 1 : 0
    route_table_id = data.aws_route_table.switch_management_rt[0].id
    destination_cidr_block = var.vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.iac_pc[0].id
}

resource "aws_route" "vpc-peering-route-to-cirunner" {
    count = var.create_vpc_peering == true ? var.az_count : 0
    route_table_id = tolist(data.aws_route_tables.k3s_private_rts[0].ids)[count.index]
    destination_cidr_block = "10.25.0.0/16"    
    vpc_peering_connection_id = aws_vpc_peering_connection.iac_pc[0].id
}
