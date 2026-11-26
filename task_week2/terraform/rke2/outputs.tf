# Run these on the BASTION: the nodes are reached by PRIVATE IP (same VPC), never from the internet.

output "master_private_ip" {
  description = "Workers join https://<this>:9345; kubectl talks to https://<this>:6443"
  value       = aws_instance.node["master"].private_ip
}

output "worker_private_ip" {
  value = aws_instance.node["worker"].private_ip
}

output "ssh_master" {
  value = "ssh -i ~/.ssh/devops-rke2 ubuntu@${aws_instance.node["master"].private_ip}"
}

output "ssh_worker" {
  value = "ssh -i ~/.ssh/devops-rke2 ubuntu@${aws_instance.node["worker"].private_ip}"
}
