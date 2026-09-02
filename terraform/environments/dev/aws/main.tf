module "networking" {
  source = "../../../modules/aws-networking"

  environment        = "dev"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs       = ["10.0.0.0/24", "10.0.1.0/24"]
  private_app_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
  private_data_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]

  tags = {
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

module "security" {
  source = "../../../modules/aws-security"
}

module "eks" {
  source = "../../../modules/aws-eks"

  vpc_id                  = module.networking.vpc_id
  private_app_subnet_ids  = module.networking.private_app_subnet_ids
  allowed_cidrs           = ["99.142.44.124/32"]

  tags = {
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
    cluster_admin_principal_arns = ["arn:aws:iam::133857166442:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_platform-admin_1a1ea017b1e815a6"]
}

module "ecr" {
  source = "../../../modules/aws-ecr"

  repository_name = "platform-api"
  kms_key_arn     = module.security.environment_kms_key_arn

  tags = {
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}