# Example terraform.tfvars file
# Copy this to terraform.tfvars and fill in your values

# set region
aws_region = "us-west-2"

# arbitrary name for cluster
environment = "cluster-A"

# Existing VPC Configuration
vpc_id = "vpc-0123456789"  

# run 'yum list available vault-enterprise --showduplicates' on the instance to see available
# format should mirror above output, like so:  "1.19.1+ent-1"
# leave blank for latest
vault_version = "1.19.1+ent-1"

# Instance Configuration
instance_type = "t3.medium"
vault_node_count = 3

# Security - restrict this to your IP or corporate CIDR
allowed_cidr_blocks = ["0.0.0.0/0"]  

# KMS Configuration for Auto-Unseal
# Leave kms_key_id empty to create a new KMS key, or provide an existing key ID
kms_key_id = ""  # e.g., "19ec80b0-dfdd-4d97-8164-c6examplekey"

# Optional: KMS VPC Endpoint (if using private endpoint)
kms_endpoint = ""  # e.g., "https://vpce-0e1bb1852241f8cc6-pzi0do8n.kms.us-east-1.vpce.amazonaws.com"

# Vault License - paste your full license string here
vault_license = ""
