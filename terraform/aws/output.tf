output "bastion_hostname" {
  description = "Bastion Instance Hostname"
  value       = aws_instance.bastion.public_ip
}

output "external_dns_iam_access_key" {
  description = "Access Key ID for IAM user to be used by external-dns"
  value       = aws_iam_access_key.route53-external-dns.id
}

output "external_dns_iam_secret_key" {
  description = "Secret Key for IAM user to be used by external-dns"
  value       = aws_iam_access_key.route53-external-dns.secret
  sensitive   = true
}

output "db_password" {
  description = "Password for RDS user"
  value       = var.db_password != null ? var.db_password : random_password.db_password.result
  sensitive   = true
}

output "ssh_private_key" {
  description = "Private key in PEM format"
  value       = tls_private_key.ec2_ssh_key.private_key_pem
  sensitive   = true
}

output "nat_public_ips" {
  description = "nat gateway public ips"
  value       = module.vpc.nat_public_ips
}