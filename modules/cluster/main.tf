locals {
  app_namespace               = "app"
  app_serviceaccount          = "app-sa"
  lb-namespace                = "kube-system"
  lb_serviceaccount           = "aws-load-balancer-controller"
  external_dns_namespace      = "external-dns"
  external_dns_serviceaccount = "external-dns"
}

data "terraform_remote_state" "common" {
  backend = "s3"

  config = {
    bucket = "eks-cluster-state-taniai"
    key    = "common/network/terraform.tfstate"
    region = "ap-northeast-1"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37.1"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  cluster_addons = {
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-efs-csi-driver = {
      most_recent = true
    }
  }

  vpc_id     = data.terraform_remote_state.common.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.common.outputs.private_subnet_ids

  eks_managed_node_groups = {
    initial = {
      node_group_name = var.node_group_name
      instance_type   = var.instance_types

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size
      subnet_ids   = data.terraform_remote_state.common.outputs.private_subnet_ids
    }
  }

  enable_cluster_creator_admin_permissions = true
}

####################
# Pod Identity設定
# RoleとServiceAccountを紐づける
# AWS公式のModule terraform-aws-eks-pod-identityでも可能だが、Roleの新規作成が前提となっている
# 今回はBlueとGreenでRoleを同じものを使用するため、aws_eks_pod_identity_associationリソースを使用する
# https://github.com/terraform-aws-modules/terraform-aws-eks-pod-identity/blob/6d4aa31990e4179640c869505169ebc78f200e10/main.tf#L193
####################
resource "aws_eks_pod_identity_association" "dynamo_read" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.app_namespace
  service_account = local.app_serviceaccount
  role_arn        = data.terraform_remote_state.common.outputs.pod_dynamodb_role_arn
}

resource "aws_eks_pod_identity_association" "lb-identity" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.lb-namespace
  service_account = local.lb_serviceaccount
  role_arn        = data.terraform_remote_state.common.outputs.pod_lb_role_arn
}

resource "aws_eks_pod_identity_association" "external-dns-identity" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.external_dns_namespace
  service_account = local.external_dns_serviceaccount
  role_arn        = data.terraform_remote_state.common.outputs.pod_external_dns_role_arn
}
