data "aws_iam_policy_document" "kyverno_pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kyverno_ecr_read" {
  name               = "kyverno-ecr-read"
  assume_role_policy = data.aws_iam_policy_document.kyverno_pod_identity_trust.json

  tags = {
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}

data "aws_iam_policy_document" "kyverno_ecr_read" {
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrReadImage"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [module.ecr.repository_arn]
  }
}

resource "aws_iam_role_policy" "kyverno_ecr_read" {
  name   = "ecr-read"
  role   = aws_iam_role.kyverno_ecr_read.id
  policy = data.aws_iam_policy_document.kyverno_ecr_read.json
}

resource "aws_eks_pod_identity_association" "kyverno_admission_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kyverno"
  service_account = "kyverno-admission-controller"
  role_arn        = aws_iam_role.kyverno_ecr_read.arn

  tags = {
    Owner          = "platform-team"
    Environment    = "dev"
    CostCenter     = "platform-eng"
    Classification = "internal"
    ManagedBy      = "terraform"
  }
}