# vault-lambda
This repository provides a python 2.7 lambda function for  
running HashiCorp Vault in a serverless fashion. There is  
also Terraform code to stand up this solution as simple as:  
  
git clone https://github.com/chrismatteson/vault-lambda  
cd vault-lambda/terraform  
terraform init  
terraform plan  
terraform apply  
export VAULT_ADDR=`terraform output "Vault URL"`  
  
Vault is now up and running in AWS with KMS autounseal.  
It can be initalized and used as Vault would typically be  
used.  
  
The Terraform code stands up a public API gateway without  
any authentication to proxy the Vault API calls to the  
Lambda. The Vault binary and Vault data is stored on an  
s3 bucket, and cloudwatch is enabled for logging.  
  
## This is NOT Production ready.  
It's a proof of concept please don't do this with your  
real data  
