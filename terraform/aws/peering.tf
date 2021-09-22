resource "aws_vpc_peering_connection" "iac_pc" {
  count = var.create_vpc_peering == true ? 1 : 0
  peer_vpc_id = var.peer_vpc_id
  vpc_id = module.vpc.vpc_id
  auto_accept = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }
  tags = merge({ Name = "${local.name}-vpc-peer-conn-iac_pc" }, local.common_tags)
}

data "aws_route_table" "k3s_private_rta" {
  count = var.create_vpc_peering == true ? 1 : 0
  vpc_id = module.vpc.vpc_id

  filter {
    name   = "tag:Name"
    values = ["${local.name}-private-${var.region}a"]
  }
  depends_on = [module.vpc]
}

data "aws_route_table" "k3s_private_rtb" {
  count = var.create_vpc_peering == true ? 1 : 0
  vpc_id = module.vpc.vpc_id

  filter {
    name   = "tag:Name"
    values = ["${local.name}-private-${var.region}b"]
  }
  depends_on = [module.vpc]
}

data "aws_route_table" "k3s_private_rtc" {
  count = var.create_vpc_peering == true ? 1 : 0
  vpc_id = module.vpc.vpc_id

  filter {
    name   = "tag:Name"
    values = ["${local.name}-private-${var.region}c"]
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
    for_each = local.switch_rtid_map
    route_table_id = each.value
    destination_cidr_block = var.vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.iac_pc[0].id
}

resource "aws_route" "vpc-peering-route-to-cirunner" {
    for_each = local.k3s_rtid_map
    route_table_id = each.value
    destination_cidr_block = "10.25.0.0/16"    
    vpc_peering_connection_id = aws_vpc_peering_connection.iac_pc[0].id
}

locals {
  switch_rtid_map = var.create_vpc_peering == true ? {public-management = data.aws_route_table.switch_management_rt[0].id} : {}
  k3s_rtid_map = var.create_vpc_peering == true ? {private-a = data.aws_route_table.k3s_private_rta[0].id, private-b = data.aws_route_table.k3s_private_rtb[0].id,private-c = data.aws_route_table.k3s_private_rtc[0].id} : {}
}