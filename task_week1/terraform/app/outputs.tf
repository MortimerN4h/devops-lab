output "public_ip" {
  description = "Elastic IP (fixed). DNS node.<domain> points here."
  value       = aws_eip.app.public_ip
}

output "node_url" {
  value = "http://${aws_route53_record.node.name}"
}

output "ssh_command" {
  description = "Run on the BASTION (private IP: both machines are in the same VPC)"
  value       = "ssh -i ~/.ssh/devops-app ubuntu@${aws_instance.app.private_ip}"
}

output "python_url" {
  value = "http://${aws_route53_record.python.name}"
}

output "go_url" {
  value = "http://${aws_route53_record.go.name}"
}

output "java_url" {
  value = "http://${aws_route53_record.java.name}"
}

output "dotnet_table" {
  description = "Real DynamoDB table of the .NET app (TABLE_NAME in the server compose)"
  value       = aws_dynamodb_table.dotnet_notes.name
}

output "dotnet_url" {
  value = "http://${aws_route53_record.dotnet.name}"
}
