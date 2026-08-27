variable "dev_account_id" {
  description = "AWS account ID of the dev workload account this SCP applies to."
  type        = string
}

module "scp" {
  source = "../../../modules/aws-scp"

  dev_account_id = var.dev_account_id
}