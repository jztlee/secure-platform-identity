resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"

  tags = var.tags
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.22.4-eksbuild.3"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  tags = var.tags
}