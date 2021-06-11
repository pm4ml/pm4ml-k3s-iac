###
# Required onprem requried values
###

variable "onprem_master_hosts" { # Ansible k3s playbook only currently supports a single master, but allow this to be a list for future compatibility
  description = "IP address or hostname of servers which will act as k3s masters"
  type        = string
}
variable "onprem_agent_hosts" {
  description = "IP Address or hostnames of servers which will act as k3s worker nodes (agents)"
  type        = string
}
variable "onprem_bastion_host" {
  description = "IP Address of bastion host"
  type = string
  default = ""
}

variable "onprem_haproxy_primary" {
  description = "IP Address for haproxy primary load balancer (optional)"
  type = string
  default = ""
}

variable "onprem_haproxy_secondary" {
  description = "IP Address for haproxy secondary load balancer (optional)"
  type = string
  default = ""
}


variable "onprem_ssh_user" {
  description = "Username for SSH user to connect to master and agent servers"
  type        = string
}
variable "onprem_ssh_private_key" {
  description = "Path to PEM format private key to connect to master and agent servers"
  type        = string
}

###
# Required variables without default values
###
variable "client" {
  description = "Client name, lower case and without spaces. This will be used to set the tenant name"
  type        = string
}
variable "environment" {
  description = "environment name, lower case and without spaces. This will be used for tagging"
  type        = string
}
variable "domain" {
  description = "Base domain to attach the tenant to."
  type        = string
}

variable "tags" {
  description = "Contains default tags for this project"
  type        = map(string)
  default     = {}
}

###
# Local copies of variables to allow for parsing
###
locals {
  name = "${replace(var.client, "-", "")}-${var.environment}"
  common_tags = merge(
    { Client      = var.client,
      Environment = var.environment,
      Domain      = var.domain
    },
  var.tags)
}
