variable "vpc-id" {
  default = ""
}


data "aws_availability_zones" "available" {}

##tags
variable "name" {
  description = "Name to be used on all the resources as identifier"
  default     = ""
}


variable "client" {
  description = "Client name, lower case and without spaces. This will be used to set tags and name resources"
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
