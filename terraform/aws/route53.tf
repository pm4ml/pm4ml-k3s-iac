resource "aws_route53_zone" "private" {
  force_destroy = true
  count = var.create_private_zone == "yes" ? 1 : 0
  name  = "${local.base_domain}.internal."

  vpc {
    vpc_id = module.vpc.vpc_id
  }
}

resource "aws_route53_zone" "public" {
  force_destroy = true
  count = var.create_public_zone == "yes" ? 1 : 0
  name  = "${local.base_domain}."
}

resource "aws_route53_record" "public-ns" {
  count = var.create_public_zone == "yes" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = local.base_domain
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.public[0].name_servers
}
