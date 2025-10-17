## Intro
Terraform repro to quickly deploy any number of nodes onto AWS in an HA Vault setup running on any version.  Auto join and KMS auto unseal enabled.

### Prerequisites
- Authentication to AWS CLI configured (via doormat for Hashi).
- Pre-existing VPC ID of your default region.
- Vault enterprise license.

### Procedure
- Clone repo and cd into it.
- Set terraform.tfvars:
  - Vault ebterprise license.
  - AWS Region
  - Existing AWS VPC ID for that region 
  - Vault version, or set to "" for latest.
- Run terraform plan.
- If no errors, run terraform apply.
- SSH commands will be output when finished.
- after some time, HA cluster should be operational.
- `ls` in home directoroy to see unseal keys and root token.
