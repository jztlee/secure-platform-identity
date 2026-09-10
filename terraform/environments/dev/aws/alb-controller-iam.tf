resource "aws_iam_role" "alb_controller" {
  name               = "aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.kyverno_pod_identity_trust.json

  tags = {
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

resource "aws_iam_policy" "alb_controller" {
  name   = "aws-dev-foundation-alb-controller"
  policy = file("${path.module}/alb-controller-iam-policy.json")

  tags = {
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn

  tags = {
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}