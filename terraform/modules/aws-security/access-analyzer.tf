resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "dev-account-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name           = "dev-account-analyzer"
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}