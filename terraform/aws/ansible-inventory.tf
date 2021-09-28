# Output variables to the ansible inventory 'all' group
resource "ansible_group" "all" {
  inventory_group_name = "all"
  vars = {
    tf_cloud_provider               = "aws"
    external_dns_iam_access_key     = aws_iam_access_key.route53-external-dns.id
    external_dns_iam_secret_key     = aws_iam_access_key.route53-external-dns.secret
    longhorn_backups_bucket_name    = "${local.base_domain}-lhbck"
    longhorn_backups_iam_access_key = aws_iam_access_key.longhorn_backups.id
    longhorn_backups_iam_secret_key = aws_iam_access_key.longhorn_backups.secret
    external_lb_hostname            = aws_lb.lb.dns_name
    internal_lb_hostname            = aws_lb.internal-lb.dns_name
    ansible_ssh_user                = "ubuntu"
  }
}

# Create data sources to load the IPs of the servers created by the autoscaling group
data "aws_instances" "k3s_server" {
  instance_tags = merge({ Name = "${local.name}-server" }, local.identifying_tags)
  depends_on    = [aws_autoscaling_group.k3s_server]
}

data "aws_instances" "k3s_agent" {
  count         = var.agent_node_count > 0 ? 1 : 0
  instance_tags = merge({ Name = "${local.name}-agent" }, local.identifying_tags)
  depends_on    = [aws_autoscaling_group.k3s_agent]
}

# Output hosts for ansible inventory
resource "ansible_host" "k3s_server" {
  count              = var.master_node_count
  inventory_hostname = data.aws_instances.k3s_server.private_ips[count.index]
  groups             = ["k3s_master"]
  depends_on         = [data.aws_instances.k3s_server]
}
resource "ansible_host" "k3s_agent" {
  count              = var.agent_node_count
  inventory_hostname = data.aws_instances.k3s_agent[0].private_ips[count.index]
  groups             = ["k3s_node"]
  depends_on         = [data.aws_instances.k3s_agent]
}
resource "ansible_host" "bastion" {
  inventory_hostname = aws_instance.bastion.public_ip
  groups             = ["bastion"]
}
