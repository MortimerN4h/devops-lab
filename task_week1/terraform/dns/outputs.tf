output "name_servers" {
  description = "Copy these 4 values into your registrar's 'Custom nameservers' setting"
  value       = aws_route53_zone.main.name_servers
}

output "zone_id" {
  value = aws_route53_zone.main.zone_id
}
