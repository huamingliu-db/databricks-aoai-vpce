# db-aoai-vpce
This script can help you quickly deploy a VPC endpoint service for serverless model serving to securely connect to Azure Open AI service.

# Disclaimer
The Terraform code is provided as a sample for reference and testing purposes only. Please review, modify the code according to your needs, and fully test it before using it in your production environment. The code is offered without warranties, and the user assumes full responsibility for its use.

# Repository structure and content
Code in the repository is organized into the following folders:

scripts - EC2 user data shell script and zipped Lambda function python code
myvars.auto.tfvars - All the input variables. Please adjust these variables before running the script
output.tf - Declare the output values
providers.tf - Configure AWS provider
variables.tf - Declare all the input variables.
versions.tf - Specify the versions of Terraform and AWS providers
vpce.tf - Deploy all the AWS resources
