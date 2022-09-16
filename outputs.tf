output "public_endpoint" {
  value = aws_alb.vault.dns_name
}

output "custom_public_endpoint" {
  value = local.custom_endpoint
}

output "public_url" {
  value = local.vault_url
}
