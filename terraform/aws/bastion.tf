resource "aws_security_group" "bastion" {
  name   = "${local.name}-bastion"
  vpc_id = module.vpc.vpc_id
  tags   = merge({}, local.common_tags)
}

resource "aws_security_group_rule" "bastion_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "bastion_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id     = element(module.vpc.public_subnets, 0)
  user_data     = templatefile("${path.module}/templates/bastion.user_data.tmpl", { ssh_keys = local.ssh_keys })
  key_name      = local.name

  vpc_security_group_ids = [aws_security_group.bastion.id, module.vpc.default_security_group_id]

  tags = merge({ Name = "${local.name}-bastion" }, local.common_tags)

  lifecycle {
    ignore_changes = [
      ami
    ]
  }
}