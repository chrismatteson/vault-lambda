output "Vault URL" {
  value       = "${aws_api_gateway_deployment.vault.invoke_url}"
  description = "The url which VAULT_ADDR can be set to to utilize Vault Lambda server"
}
