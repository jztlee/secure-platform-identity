resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name           = "dev-guardduty-detector"
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}