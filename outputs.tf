output "vault_node_private_ips" {
  description = "Private IP addresses of Vault nodes"
  value       = aws_instance.vault[*].private_ip
}

output "vault_node_public_ips" {
  description = "Public IP addresses of Vault nodes"
  value       = aws_instance.vault[*].public_ip
}

output "vault_security_group_id" {
  description = "ID of the Vault security group"
  value       = aws_security_group.vault_sg.id
}

output "vault_node_ids" {
  description = "Instance IDs of Vault nodes"
  value       = aws_instance.vault[*].id
}

output "primary_vault_url" {
  description = "URL to access primary Vault node"
  value       = "http://${aws_instance.vault[0].public_ip}:8200"
}

output "kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal"
  value       = local.kms_key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used for Vault auto-unseal"
  value       = local.kms_key_arn
}

output "ssh_private_key_path" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}

output "ssh_commands" {
  description = "SSH commands to connect to each Vault node"
  value = {
    for idx, ip in aws_instance.vault[*].public_ip :
    "vault-node-${idx + 1}" => "ssh -i ${local_file.private_key.filename} ec2-user@${ip}"
  }
}

output "all_ssh_commands" {
  description = "All SSH commands in a single output"
  value       = join("\n", [for idx, ip in aws_instance.vault[*].public_ip : "# Node ${idx + 1}\nssh -i ${local_file.private_key.filename} ec2-user@${ip}"])
}
