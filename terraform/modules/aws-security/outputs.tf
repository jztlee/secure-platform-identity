output "environment_kms_key_arn" {
    description = "ARN of the environment KMS key, reused by other modules needing encryption at rest."

    value       = aws_kms_key.environment.arn
}