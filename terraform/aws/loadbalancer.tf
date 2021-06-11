#
# Internal load balancer
#
resource "aws_lb" "server-lb" { #  server-lb was originally intended to expose the kube api from the k3s server only, however this serves as the internal load balancer for 80/443 traffic too
  internal           = true
  load_balancer_type = "network"
  enable_cross_zone_load_balancing = true
  subnets            = module.vpc.private_subnets
}

resource "aws_lb_listener" "server-port_6443" {
  load_balancer_arn = aws_lb.server-lb.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.server-6443.arn
  }
}

resource "aws_lb_target_group" "server-6443" {
  port     = 6443
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id
}


resource "aws_lb_listener" "internal-port_443" {
  load_balancer_arn = aws_lb.server-lb.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal-443.arn
  }
}

resource "aws_lb_target_group" "internal-443" {
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

  tags = {
    "kubernetes.io/cluster/${local.name}" = ""
  }
}


resource "aws_lb_listener" "internal-port_80" {
  load_balancer_arn = aws_lb.server-lb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal-80.arn
  }
}
resource "aws_lb_target_group" "internal-80" {
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

  tags = {
    "kubernetes.io/cluster/${local.name}" = ""
  }
}

#
# External load balancer
#
resource "aws_lb" "lb" {
  internal           = false
  load_balancer_type = "network"
  subnets            = module.vpc.public_subnets

  tags = {
    "kubernetes.io/cluster/${local.name}" = ""
  }
}

resource "aws_lb_listener" "port_443" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "443"
  protocol          = "TCP"

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

  tags = {
    "kubernetes.io/cluster/${local.name}" = ""
  }
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

  tags = {
    "kubernetes.io/cluster/${local.name}" = ""
  }
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

  tags = {
    "kubernetes.io/cluster/${local.name}" = ""
  }
}
