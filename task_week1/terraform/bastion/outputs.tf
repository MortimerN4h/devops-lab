# Values printed at the end of `terraform apply` (and by `terraform output`).

output "public_ip" {
  description = "Public IP of the bastion"
  value       = aws_instance.bastion.public_ip
}

output "ssh_command" {
  description = "Command to log in (adjust the key path if yours differs)"
  value       = "ssh -i ~/.ssh/devops-bastion ubuntu@${aws_instance.bastion.public_ip}"
}
