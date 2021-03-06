#
# Variable for the EC2 Key 
# Set via CLI or via terraform.tfvars file
#
variable "ec2_key_name" {
  description = "AWS EC2 Key name for SSH access"
  type        = string
  default     = "pcarey-macos"
}

# variable "AccessKeyID" {}

# variable "SecretAccessKey" {}

variable "prefix" {
  description = "Prefix for resources created by this module"
  type        = string
  default     = "terraform-aws-bigip-1nic-pcarey"
}
