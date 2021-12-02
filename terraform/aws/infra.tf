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
    security_groups       = local.server_security_groups
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
  target_group_arns = [
    aws_lb_target_group.internal-6443.arn
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

  target_group_arns = concat ([
    aws_lb_target_group.agent-80.arn,
    aws_lb_target_group.agent-443.arn,
    aws_lb_target_group.internal-8080.arn,
    aws_lb_target_group.internal-8443.arn,
    aws_lb_target_group.agent-51820.arn
  ], var.use_aws_acm_cert ? [aws_lb_target_group.agent-9443[0].arn] : [])

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
  vpc_security_group_ids          = [aws_security_group.database[0].id]
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