#
# Internal load balancer
#
resource "aws_lb" "internal-lb" { #  for internal traffic, including kube traffic
  internal           = true
  load_balancer_type = "network"
  enable_cross_zone_load_balancing = true
  subnets            = module.vpc.private_subnets
  tags = merge({ Name = "${local.name}-internal" }, local.common_tags)
}

resource "aws_lb_listener" "internal-port_6443" {
  load_balancer_arn = aws_lb.internal-lb.arn
  port              = "6443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal-6443.arn
  }
}

resource "aws_lb_target_group" "internal-6443" {
  port     = 6443
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id
  tags = merge({ Name = "${local.name}-internal-6443" }, local.common_tags)
}

resource "aws_lb_listener" "internal-port_443" {
  load_balancer_arn = aws_lb.internal-lb.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal-8443.arn
  }
}

resource "aws_lb_target_group" "internal-8443" {
  port     = 8443
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 10
    timeout             = 6
    path                = "/healthz"
    port                = 8080
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  tags = merge({ Name = "${local.name}-internal-8443" }, local.common_tags)
}


resource "aws_lb_listener" "internal-port_80" {
  load_balancer_arn = aws_lb.internal-lb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal-8080.arn
  }
}
resource "aws_lb_target_group" "internal-8080" {
  port     = 8080
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 10
    timeout             = 6
    path                = "/healthz"
    port                = 8080
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  tags = merge({ Name = "${local.name}-internal-8080" }, local.common_tags)
}

#
# External load balancer
#

resource "aws_acm_certificate" "wildcard-cert" {
  count      = var.use_aws_acm_cert ? 1 : 0
  domain_name       = aws_route53_record.public-ns[0].fqdn
  validation_method = "DNS"
  subject_alternative_names = ["*.${var.aws_acm_wildcard_entry}.${aws_route53_record.public-ns[0].fqdn}", "vpn.${aws_route53_record.public-ns[0].fqdn}","vault.${aws_route53_record.public-ns[0].fqdn}","grafana.${aws_route53_record.public-ns[0].fqdn}"]
  tags = merge({ Name = "${local.name}-wildcard-cert" }, local.common_tags)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  count = 5 * (var.use_aws_acm_cert ? 1 : 0)
  name            = aws_acm_certificate.wildcard-cert[0].domain_validation_options.*.resource_record_name[count.index]
  records         = [aws_acm_certificate.wildcard-cert[0].domain_validation_options.*.resource_record_value[count.index]]
  type            = aws_acm_certificate.wildcard-cert[0].domain_validation_options.*.resource_record_type[count.index]
  ttl             = 60
  allow_overwrite = true
  zone_id  = aws_route53_zone.public[0].id
}
resource "aws_acm_certificate_validation" "cert" {
  count      = var.use_aws_acm_cert ? 1 : 0
  certificate_arn         = aws_acm_certificate.wildcard-cert[0].arn
  validation_record_fqdns = aws_route53_record.cert_validation[*].fqdn
}

resource "aws_lb" "lb" {
  internal           = false
  load_balancer_type = "network"
  subnets            = module.vpc.public_subnets
  tags = merge({ Name = "${local.name}-public" }, local.common_tags)
}

resource "aws_lb_listener" "port_9443" {
  count      = var.use_aws_acm_cert ? 1 : 0
  load_balancer_arn = aws_lb.lb.arn
  port              = "9443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent-9443[0].arn
  }
}

resource "aws_lb_target_group" "agent-9443" {
  count      = var.use_aws_acm_cert ? 1 : 0
  port     = 443
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 10
    timeout             = 6
    path                = "/healthz"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  tags = merge({ Name = "${local.name}-agent-9443" }, local.common_tags)
}


resource "aws_lb_listener" "port_443" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "443"
  protocol          = var.use_aws_acm_cert ? "TLS" : "TCP"
  ssl_policy        = var.use_aws_acm_cert ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = var.use_aws_acm_cert ? aws_acm_certificate.wildcard-cert[0].arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent-443.arn
  }
}

resource "aws_lb_listener" "port_80" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent-80.arn
  }
}

resource "aws_lb_listener" "port_51820" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "51820"
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent-51820.arn
  }
}

resource "aws_lb_target_group" "agent-443" {
  port     = 443
  protocol = var.use_aws_acm_cert ? "TLS" : "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 10
    timeout             = 6
    path                = "/healthz"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  tags = merge({ Name = "${local.name}-agent-443" }, local.common_tags)
}

resource "aws_lb_target_group" "agent-80" {
  port     = 80
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 10
    timeout             = 6
    path                = "/healthz"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  tags = merge({ Name = "${local.name}-agent-80" }, local.common_tags)
}


resource "aws_lb_target_group" "agent-51820" {
  port     = 51820
  protocol = "UDP"
  vpc_id   = module.vpc.vpc_id

  # TODO: can't health check against a UDP port, but need to have a health check when backend is an instance. 
  # check tcp port 80 (ingress) for now, but probably need to add a http sidecar or something to act as a health check for wireguard
  health_check {
    protocol = "TCP"
    port     = 80
  }

  tags = merge({ Name = "${local.name}-agent-51820" }, local.common_tags)
}
