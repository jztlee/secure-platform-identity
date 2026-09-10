resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/dev/cluster"
  retention_in_days = 30

  tags = merge(var.tags, { Name = "eks-dev-cluster-logs" })
}