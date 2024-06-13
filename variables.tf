variable "region" {
  type        = string
  description = "Region of all your AWS resources"
}

variable "cidr_block" {
  type        = string
  description = "Databricks Workspace VPC CIDR"
}

variable "prefix" {
  type        = string
  description = "Prefix of related AWS resources for Azure Open AI endpoint service"
}

variable "user_name" {
  type        = string
  description = "your firstname.lastname"
}

variable "service_name" {
  type        = string
  description = "Databricks service name"
}

variable "eip_pool_size" {
  type        = number
  description = "Size of Elastic IP pool"
}

variable "eip_tag_key" {
  type        = string
  description = "Tag key of the EIPs in the pool"
}

variable "asg_min_size" {
  type        = number
  description = "Minimum capacity of Auto Scaling Group"
}

variable "asg_max_size" {
  type        = number
  description = "Maximum capacity of Auto Scaling Group"
}

variable "asg_desired_size" {
  type        = number
  description = "Desired capacity of Auto Scaling Group"
}

variable "instance_type" {
  type        = string
  description = "Instance type of your proxy server"
}

variable "key_name" {
  type        = string
  description = "Key pairs name of your proxy server"
}

variable "allowed_principals" {
  type        = list(string)
  description = "List of IAM principals that are allowed to create VPC endpoint against the endpoint service"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile name"
}