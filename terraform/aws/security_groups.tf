#############################
### Access Control
#############################

resource "aws_security_group" "ingress" {
  name   = "${local.name}-ingress"
  vpc_id = module.vpc.vpc_id
  tags = merge({ Name = "${local.name}-ingress" }, local.common_tags)
}

resource "aws_security_group_rule" "ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "TCP"
  cidr_blocks       = local.external_http_cidr_blocks
  security_group_id = aws_security_group.ingress.id
}

resource "aws_security_group_rule" "ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "TCP"
  cidr_blocks       = local.external_http_cidr_blocks
  security_group_id = aws_security_group.ingress.id
}

resource "aws_security_group_rule" "ingress_http_internal" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ingress.id
}

resource "aws_security_group_rule" "ingress_https_internal" {
  type              = "ingress"
  from_port         = 8443
  to_port           = 8443
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ingress.id
}

resource "aws_security_group_rule" "ingress_vpn" {
  type              = "ingress"
  from_port         = 51820
  to_port           = 51820
  protocol          = "UDP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ingress.id
}

resource "aws_security_group_rule" "ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.ingress.id
}

resource "aws_security_group_rule" "ingress_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ingress.id
}

resource "aws_security_group" "self" {
  name   = "${local.name}-self"
  vpc_id = module.vpc.vpc_id
  tags = merge({ Name = "${local.name}-self" }, local.common_tags)
}

resource "aws_security_group_rule" "self_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.self.id
}

resource "aws_security_group_rule" "self_k3s_server" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "TCP"
  cidr_blocks       = module.vpc.private_subnets_cidr_blocks
  security_group_id = aws_security_group.self.id
}

resource "aws_security_group_rule" "self_https_external" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "TCP"
  cidr_blocks       = module.vpc.private_subnets_cidr_blocks
  security_group_id = aws_security_group.self.id
}

resource "aws_security_group_rule" "self_http_external" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "TCP"
  cidr_blocks       = module.vpc.private_subnets_cidr_blocks
  security_group_id = aws_security_group.self.id
}

resource "aws_security_group_rule" "self_https_internal" {
  type              = "ingress"
  from_port         = 8443
  to_port           = 8443
  protocol          = "TCP"
  cidr_blocks       = module.vpc.private_subnets_cidr_blocks
  security_group_id = aws_security_group.self.id
}

resource "aws_security_group_rule" "self_http_internal" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "TCP"
  cidr_blocks       = module.vpc.private_subnets_cidr_blocks
  security_group_id = aws_security_group.self.id
}

resource "aws_security_group_rule" "self_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.self.id
}

#should change this to create only if managed db being used, need to address the ref to db sec group in ec2 server aws_launch_template


resource "aws_security_group" "database" {
  count  = local.deploy_rds
  name   = "${local.name}-database"
  vpc_id = module.vpc.vpc_id
  tags = merge({ Name = "${local.name}-database" }, local.common_tags)
}

resource "aws_security_group_rule" "database_self" {
  count             = local.deploy_rds
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "TCP"
  self              = true
  security_group_id = aws_security_group.database[0].id
}

resource "aws_security_group_rule" "database_egress_all" {
  count             = local.deploy_rds
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.database[0].id
}