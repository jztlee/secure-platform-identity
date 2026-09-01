output "repository_url" {
  description = "The ECR repository URL, used for docker push/pull."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  value = aws_ecr_repository.this.arn
}