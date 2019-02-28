output "Vault URL" {
  value       = "${aws_api_gateway_deployment.vault.invoke_url}${aws_api_gateway_stage.stage.stage_name}/${aws_api_gateway_resource.vault.path_part}"
  description = "The url which VAULT_ADDR can be set to to utilize Vault Lambda server"
}
