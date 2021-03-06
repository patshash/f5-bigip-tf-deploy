provider "aws" {
  region = local.region
  # access_key = var.AccessKeyID
  # secret_key = var.SecretAccessKey
}

#
# Create a random id
#
resource "random_id" "id" {
  byte_length = 2
}

#
# Create random password for BIG-IP
#
resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "#%*+,-./:=?@[]^_~"
}

#
# Create Secret Store and Store BIG-IP Password
#
resource "aws_secretsmanager_secret" "bigip" {
  name = format("%s-bigip-secret-%s", var.prefix, random_id.id.hex)
}
resource "aws_secretsmanager_secret_version" "bigip-pwd" {
  secret_id     = aws_secretsmanager_secret.bigip.id
  secret_string = random_password.password.result
}

#
# Create the VPC 
#
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                 = format("%s-vpc-%s", local.prefix, random_id.id.hex)
  cidr                 = local.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  azs = local.azs

  public_subnets = [
    for num in range(length(local.azs)) :
    cidrsubnet(local.cidr, 8, num)
  ]

  tags = {
    Name        = format("%s-vpc-%s", local.prefix, random_id.id.hex)
    Terraform   = "true"
    Environment = "dev"
  }
}

#
# Create a security group for port 80 traffic
#
module "web_server_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = format("%s-web-server-%s", local.prefix, random_id.id.hex)
  description = "Security group for web-server with HTTP ports"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [local.allowed_app_cidr]
}

#
# Create a security group for port 443 traffic
#
module "web_server_secure_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/https-443"

  name        = format("%s-web-server-secure-%s", local.prefix, random_id.id.hex)
  description = "Security group for web-server with HTTPS ports"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [local.allowed_app_cidr]
}

#
# Create a security group for port 8443 traffic
#
module "bigip_mgmt_secure_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/https-8443"

  name        = format("%s-bigip-mgmt-%s", local.prefix, random_id.id.hex)
  description = "Security group for BIG-IP MGMT Interface"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [local.allowed_mgmt_cidr]
}

#
# Create a security group for SSH traffic
#
module "ssh_secure_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/ssh"

  name        = format("%s-ssh-%s", local.prefix, random_id.id.hex)
  description = "Security group for SSH ports open within VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = [local.allowed_mgmt_cidr]
}

#
# Create BIG-IP
#
module bigip {
  source  = "f5devcentral/bigip/aws"
  version = "0.1.4"
  # insert the 2 required variables here
  # Use the latest (11/21) bigip plugins
  AS3_URL = "https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.31.0/f5-appsvcs-3.31.0-6.noarch.rpm"
  DO_URL = "https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.24.0/f5-declarative-onboarding-1.24.0-6.noarch.rpm" 
  TS_URL = "https://github.com/F5Networks/f5-telemetry-streaming/releases/download/v1.23.0/f5-telemetry-1.23.0-4.noarch.rpm"

  #Search the correct AMI.
  f5_ami_search_name = "F5 Networks BIGIP-14.* PAYG - Best 25Mbps*"

  prefix = format(
    "%s-bigip-1-nic_with_new_vpc-%s",
    local.prefix,
    random_id.id.hex
  )
  f5_instance_count           = length(local.azs)
  ec2_key_name                = var.ec2_key_name
  aws_secretmanager_secret_id = aws_secretsmanager_secret.bigip.id
  mgmt_subnet_security_group_ids = [
    module.web_server_sg.security_group_id,
    module.web_server_secure_sg.security_group_id,
    module.ssh_secure_sg.security_group_id,
    module.bigip_mgmt_secure_sg.security_group_id
  ]
  vpc_mgmt_subnet_ids = module.vpc.public_subnets
}

#
# Variables used by this example
#
locals {
  prefix            = "tf-aws-bigip-pcarey"
  region            = "ap-southeast-2"
  #  azs               = ["ap-southeast-2a", "ap-southeast-2b"]
  azs               = ["ap-southeast-2a"]
  cidr              = "10.0.0.0/16"
  allowed_mgmt_cidr = "0.0.0.0/0"
  allowed_app_cidr  = "0.0.0.0/0"
}
