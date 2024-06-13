output "eip_public_ips" {
  description = "Public IPs of the created Elastic IPs"
  value       = aws_eip.eip_pool[*].public_ip
}

output "aoai_endpoint_service_name" {
  description = "Service Name of the Deployed Azure Open AI Endpoint Service"
  value       = aws_vpc_endpoint_service.aoai.service_name
}