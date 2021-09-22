#############################
### VPC
#############################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.17.0"

  name = local.name
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  create_database_subnet_group = false

  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway   = true

  tags = merge({}, local.common_tags)
}
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
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ingress.id
}

resource "aws_security_group_rule" "ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
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
  #count  = local.deploy_rds
  name   = "${local.name}-database"
  vpc_id = module.vpc.vpc_id
  tags = merge({ Name = "${local.name}-database" }, local.common_tags)
}

resource "aws_security_group_rule" "database_self" {
  #count             = local.deploy_rds
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "TCP"
  self              = true
  security_group_id = aws_security_group.database.id
}

resource "aws_security_group_rule" "database_egress_all" {
  #count             = local.deploy_rds
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.database.id
}

#############################
### Create Nodes
#############################
resource "aws_launch_template" "k3s_server" {
  name_prefix   = "${local.name}-server"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.master_instance_type
  user_data     = data.template_cloudinit_config.k3s_server.rendered
  key_name      = local.name

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      encrypted   = true
      volume_type = "gp2"
      volume_size = var.master_volume_size
    }
  }

  network_interfaces {
    delete_on_termination = true
    security_groups       = [aws_security_group.self.id, aws_security_group.database.id, module.vpc.default_security_group_id]
  }


  tags = merge(
    { Name = "${local.name}-server" },
    local.common_tags
  )


  tag_specifications {
    resource_type = "instance"

    tags = merge(
      { Name = "${local.name}-server" },
      local.common_tags
    )
  }
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      { Name = "${local.name}-server" },
      local.common_tags
    )
  }
  tag_specifications {
    resource_type = "network-interface"

    tags = merge(
      { Name = "${local.name}-server" },
      local.common_tags
    )
  }
  lifecycle {
    ignore_changes = [
      image_id
    ]
  }
}

resource "aws_launch_template" "k3s_agent" {
  name_prefix   = "${local.name}-agent"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.agent_instance_type
  user_data     = data.template_cloudinit_config.k3s_agent.rendered
  key_name      = local.name

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      encrypted   = true
      volume_type = "gp2"
      volume_size = var.agent_volume_size
    }
  }

  network_interfaces {
    delete_on_termination = true
    security_groups       = [aws_security_group.ingress.id, aws_security_group.self.id, module.vpc.default_security_group_id]
  }

  tags = merge(
    { Name = "${local.name}-agent" },
    local.common_tags
  )

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      { Name = "${local.name}-agent" },
      local.common_tags
    )
  }
  tag_specifications {
    resource_type = "volume"

    tags = merge(
      { Name = "${local.name}-agent" },
      local.common_tags
    )
  }
  tag_specifications {
    resource_type = "network-interface"

    tags = merge(
      { Name = "${local.name}-agent" },
      local.common_tags
    )
  }
  lifecycle {
    ignore_changes = [
      image_id
    ]
  }
}

resource "aws_autoscaling_group" "k3s_server" {
  name_prefix         = "${local.name}-server"
  desired_capacity    = var.master_node_count
  max_size            = var.master_node_count
  min_size            = var.master_node_count
  vpc_zone_identifier = module.vpc.private_subnets

  # Join the server/master to the internal load balancer for the kube api on 6443
  # and to the external load balancer for servicelb listening on 80 and 443
  target_group_arns = [
    aws_lb_target_group.server-6443.arn
  ]

  launch_template {
    id      = aws_launch_template.k3s_server.id
    version = "$Latest"
  }
  tags = concat(
    [
      {
        "key"                 = "Name"
        "value"               = "${local.name}-k3s_server"
        "propagate_at_launch" = false
      },
      {
        "key"                 = "Client"
        "value"               = var.client
        "propagate_at_launch" = false
      },
      {
        "key"                 = "Environment"
        "value"               = var.environment
        "propagate_at_launch" = false
      },
      {
        "key"                 = "Domain"
        "value"               = local.base_domain
        "propagate_at_launch" = false
      }
    ]
  )
  depends_on = [aws_rds_cluster_instance.k3s]
}

resource "aws_autoscaling_group" "k3s_agent" {
  name_prefix         = "${local.name}-agent"
  desired_capacity    = var.agent_node_count
  max_size            = var.agent_node_count
  min_size            = var.agent_node_count
  vpc_zone_identifier = module.vpc.private_subnets

  target_group_arns = [
    aws_lb_target_group.agent-80.arn,
    aws_lb_target_group.agent-443.arn,
    aws_lb_target_group.internal-8080.arn,
    aws_lb_target_group.internal-8443.arn,
    aws_lb_target_group.agent-51820.arn
  ]

  launch_template {
    id      = aws_launch_template.k3s_agent.id
    version = "$Latest"
  }
  tags = concat(
    [
      {
        "key"                 = "Name"
        "value"               = "${local.name}-k3s_agent"
        "propagate_at_launch" = false
      },
      {
        "key"                 = "Client"
        "value"               = var.client
        "propagate_at_launch" = false
      },
      {
        "key"                 = "Environment"
        "value"               = var.environment
        "propagate_at_launch" = false
      },
      {
        "key"                 = "Domain"
        "value"               = local.base_domain
        "propagate_at_launch" = false
      }
    ]
  )

}

#############################
### Create Database
#############################
resource "aws_db_subnet_group" "private" {
  count       = local.deploy_rds
  name_prefix = "${local.name}-private"
  subnet_ids  = local.private_subnets
}

resource "aws_rds_cluster_parameter_group" "k3s" {
  count       = local.deploy_rds
  name_prefix = "${local.name}-"
  description = "Force SSL for aurora-postgresql10.7"
  family      = "aurora-postgresql10"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}
#WHEREWASI: Here, about to sort out local vars for db auth
resource "aws_rds_cluster" "k3s" {
  count                           = local.deploy_rds
  cluster_identifier_prefix       = "${local.name}-"
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned"
  engine_version                  = "10.7"
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.k3s.0.name
  availability_zones              = data.aws_availability_zones.available.names
  database_name                   = local.db_name
  master_username                 = local.db_user
  master_password                 = local.db_password
  preferred_maintenance_window    = "fri:03:21-fri:03:51"
  db_subnet_group_name            = aws_db_subnet_group.private.0.id
  vpc_security_group_ids          = [aws_security_group.database.id]
  storage_encrypted               = true

  preferred_backup_window   = "03:52-05:52"
  backup_retention_period   = 30
  copy_tags_to_snapshot     = true
  deletion_protection       = false
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name}-final-snapshot"
}

resource "aws_rds_cluster_instance" "k3s" {
  count                = local.db_node_count
  identifier_prefix    = "${local.name}-${count.index}"
  cluster_identifier   = aws_rds_cluster.k3s.0.id
  engine               = "aurora-postgresql"
  instance_class       = var.db_instance_type
  db_subnet_group_name = aws_db_subnet_group.private.0.id
}
