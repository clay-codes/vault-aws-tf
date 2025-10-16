#!/bin/bash

# Variables passed from Terraform
VAULT_LICENSE="${vault_license}"
VAULT_VERSION="${vault_version}"
REGION="${region}"
NODE_COUNT="${node_count}"
KMS_KEY_ID="${kms_key_id}"
KMS_ENDPOINT="${kms_endpoint}"

# Function to get IMDSv2 token
function get_imds_token {
    curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
}

function install_deps {
    yum install -y yum-utils shadow-utils
    yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    
    # Update system packages first (before installing Vault)
    yum update -y
    
    # Install supporting tools
    yum -y install jq <"/dev/null"
    yum -y install nc <"/dev/null"
    yum install awscli -y
    
    # Install Vault Enterprise - specific version or latest (after updates)
    if [ -n "$VAULT_VERSION" ]; then
        echo "Installing Vault Enterprise version: $VAULT_VERSION"
        yum -y install vault-enterprise-$VAULT_VERSION <"/dev/null"
    else
        echo "Installing latest Vault Enterprise version"
        yum -y install vault-enterprise <"/dev/null"
    fi
    
    # Get IMDSv2 token
    TOKEN=$(get_imds_token)
    
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
    TAG_NAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Name" --region $REGION --output text | cut -f5)
    echo "export PS1='[$TAG_NAME@$PRIVATE_IP \W]\$ '" >> /home/ec2-user/.bash_profile
}

# Create Vault license file from environment variable
function setup_license {
    echo "Setting up Vault license..."
    echo "$VAULT_LICENSE" >/etc/vault.d/vault.hclic
    
    chmod 640 /etc/vault.d/vault.hclic
    chown vault:vault /etc/vault.d/vault.hclic
}

# Get instance index from tags
function get_instance_index {
    TOKEN=$(get_imds_token)
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    INDEX=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Index" --region $REGION --output text | cut -f5)
    echo $INDEX
}

# Get all Vault node IPs from AWS tags
function get_all_vault_ips {
    TOKEN=$(get_imds_token)
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    
    # Get all instances with Role=vault tag in this region
    aws ec2 describe-instances \
        --region $REGION \
        --filters "Name=tag:Role,Values=vault" "Name=instance-state-name,Values=running,pending" \
        --query 'Reservations[*].Instances[*].[PrivateIpAddress]' \
        --output text | tr '\n' ' '
}

# Initializes a single server vault instance raft (for first node only)
function init_vault {
    TOKEN=$(get_imds_token)
    INSTANCE_INDEX=$(get_instance_index)
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
    
    # Get all Vault node IPs for retry_join
    ALL_IPS=$(get_all_vault_ips)
    
    # Build retry_join blocks for all nodes except self
    RETRY_JOIN_CONFIG=""
    for ip in $ALL_IPS; do
        if [ "$ip" != "$PRIVATE_IP" ]; then
            RETRY_JOIN_CONFIG="$RETRY_JOIN_CONFIG
  retry_join {
    leader_api_addr = \"http://$ip:8200\"
  }"
        fi
    done
    
    # Build KMS seal configuration
    KMS_SEAL_CONFIG="seal \"awskms\" {
  region     = \"$REGION\"
  kms_key_id = \"$KMS_KEY_ID\""
    
    # Add endpoint if provided
    if [ -n "$KMS_ENDPOINT" ]; then
        KMS_SEAL_CONFIG="$KMS_SEAL_CONFIG
  endpoint   = \"$KMS_ENDPOINT\""
    fi
    
    KMS_SEAL_CONFIG="$KMS_SEAL_CONFIG
}"
    
    # Create Vault configuration
    cat <<EOF1 >/etc/vault.d/vault.hcl
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "$(hostname)"
$RETRY_JOIN_CONFIG
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  tls_disable     = true
}

$KMS_SEAL_CONFIG

license_path = "/etc/vault.d/vault.hclic"
api_addr = "http://$PRIVATE_IP:8200"
cluster_addr = "http://$PRIVATE_IP:8201"
log_level = "trace"
disable_mlock = true
ui = true
EOF1

    echo 'export VAULT_ADDR=http://127.0.0.1:8200' >>/etc/environment
    echo "export AWS_DEFAULT_REGION=$REGION" >>/etc/environment
    export VAULT_ADDR=http://127.0.0.1:8200
    
    # Start Vault service
    systemctl start vault
    
    # Wait for Vault to start
    sleep 10
    
    # Only initialize on the first node (index 0)
    if [ "$INSTANCE_INDEX" = "0" ]; then
        echo "Initializing Vault on primary node..."
        vault operator init -recovery-shares=5 -recovery-threshold=3 >/home/ec2-user/keys
        
        # Extract recovery keys and root token
        grep 'Recovery Key' /home/ec2-user/keys | awk '{print $NF}' >/home/ec2-user/recovery_keys
        echo $(grep 'Initial Root Token:' /home/ec2-user/keys | awk '{print $NF}') >/home/ec2-user/root_token
        
        # Note: With auto-unseal and retry_join, Vault starts unsealed automatically
        
        # Secure the keys file
        chmod 600 /home/ec2-user/keys
        chmod 600 /home/ec2-user/recovery_keys
        chmod 600 /home/ec2-user/root_token
        chown ec2-user:ec2-user /home/ec2-user/keys
        chown ec2-user:ec2-user /home/ec2-user/recovery_keys
        chown ec2-user:ec2-user /home/ec2-user/root_token
        
        # Add login helper to bash profile
        cat <<EOF2 >>/home/ec2-user/.bash_profile
export VAULT_ADDR=http://127.0.0.1:8200
function vlogin () {
    vault login \$(cat /home/ec2-user/root_token)
}
EOF2
    else
        echo "Secondary node - will automatically join cluster via retry_join"
        echo "With KMS auto-unseal and retry_join configured, this node will:"
        echo "  1. Automatically discover and join the primary node"
        echo "  2. Automatically unseal using KMS"
        echo "Check 'vault status' after a few moments to verify"
    fi
}

# Main execution
install_deps
setup_license
init_vault

echo "Vault setup complete!"
