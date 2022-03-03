provider "aws" {
  region = var.region
}


resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "tls_private_key" "ec2_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = local.name
  public_key = tls_private_key.ec2_ssh_key.public_key_openssh
}

terraform {
  backend "s3" {}
  required_providers {
    ansible = {
      source = "nbering/ansible"
      version = "1.0.4"
    }
    aws = "~> 3.74" 
  }
}
