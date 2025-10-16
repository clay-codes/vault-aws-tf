variable "aws_region" {
  description = "AWS region for Vault deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, staging)"
  type        = string
  default     = "prod"
}

variable "vpc_id" {
  description = "ID of existing VPC to deploy Vault into"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Vault nodes"
  type        = string
  default     = "t3.medium"
}

variable "vault_node_count" {
  description = "Number of Vault nodes (minimum 3 for HA)"
  type        = number
  default     = 3

  validation {
    condition     = var.vault_node_count >= 3
    error_message = "For HA deployment, vault_node_count must be at least 3."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Vault"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vault_license" {
  description = "Vault Enterprise license string"
  type        = string
  sensitive   = true
}

variable "kms_key_id" {
  description = "KMS key ID for Vault auto-unseal (if not provided, a new key will be created)"
  type        = string
  default     = ""
}

variable "kms_endpoint" {
  description = "KMS VPC endpoint URL (optional, for private endpoint access)"
  type        = string
  default     = ""
}
