# AWS Region
variable "aws_region" {
  default = "us-east-1"
}

# URL to download vault from
variable "vault_url" {
  default = "https://releases.hashicorp.com/vault/1.0.3/vault_1.0.3_linux_amd64.zip"
}
