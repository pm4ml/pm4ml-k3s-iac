# Output variables to the ansible inventory 'all' group
resource "ansible_group" "all" {
  inventory_group_name = "all"
  vars = {
    tf_cloud_provider = "onprem"
    ansible_ssh_user  = var.onprem_ssh_user
  }
}

# Output hosts for ansible inventory
resource "ansible_host" "k3s_server" {
  for_each           = toset(split(",", var.onprem_master_hosts))
  inventory_hostname = each.value
  groups             = ["k3s_master"]
}
resource "ansible_host" "k3s_agent" {
  for_each           = toset(split(",", var.onprem_agent_hosts))
  inventory_hostname = each.value
  groups             = ["k3s_node"]
}

terraform {
  backend "s3" {}
  required_providers {
    ansible = {
      source = "nbering/ansible"
      version = "1.0.4"
    }
  }
}

resource "ansible_host" "bastion" {
  inventory_hostname = var.onprem_bastion_host
  groups             = ["bastion"]
}

resource "ansible_host" "haproxy_primary" {
  inventory_hostname = var.onprem_haproxy_primary
  groups             = ["haproxy_primary"]
}
resource "ansible_host" "haproxy_secondary" {
  inventory_hostname = var.onprem_haproxy_secondary
  groups             = ["haproxy_secondary"]
}

# Output ssh private key so that ansible/make can read it from the state
output "ssh_private_key" {
  description = "Private key in PEM format"
  value       = file(var.onprem_ssh_private_key)
  sensitive   = true
}

output "bastion_hostname" {
  description = "Bastion Instance Hostname"
  value       = var.onprem_bastion_host
}
