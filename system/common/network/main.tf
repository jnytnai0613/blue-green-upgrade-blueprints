locals {
  vpc_name                      = "pod-identity-blue-green-upgrade-vpc"
  dynamodb_name                 = "test-dynamodb"
  dynamodb_iam                  = "read_dynamodb"
  alb_ingress_controller_role   = "alb-ingress-controller-role"
  alb_ingress_controller_policy = "alb-ingress-controller-policy"
  external_dns_role_role        = "external_dns-role"
  external_dns_role_policy      = "external-dns-policy"
  hosted_zone_name              = "jnytnai.click"
  sub_domain_name               = "test"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0.1"

  name               = local.vpc_name
  cidr               = "10.0.0.0/16"
  azs                = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  public_subnets     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnets    = ["10.0.100.0/24", "10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

/*
# コストの面からAWS内外の通信はNAT Gateway経由とする
# AWS内のEKS to DynamoDB間の通信はVPC Endpoint経由でも良い
# 以下の事例にあるようにAWS内通信はNAT Gatetewayでもセキュアを保つことが可能
# https://zenn.dev/simpleform_blog/articles/f048edb9efd2b2
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.ap-northeast-1.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = module.vpc.private_route_table_ids
}
*/

data "aws_route53_zone" "root" {
  name = local.hosted_zone_name
}

resource "aws_route53_zone" "sub" {
  name = "${local.sub_domain_name}.${local.hosted_zone_name}"
}

resource "aws_route53_record" "ns" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "${local.sub_domain_name}.${local.hosted_zone_name}"
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.sub.name_servers
}

module "acm" {
  source      = "terraform-aws-modules/acm/aws"
  version     = "~> 6.0.0"
  domain_name = "${local.sub_domain_name}.${local.hosted_zone_name}"
  zone_id     = aws_route53_zone.sub.zone_id

  subject_alternative_names = [
    "*.${local.sub_domain_name}.${local.hosted_zone_name}"
  ]

  validation_method   = "DNS"
  wait_for_validation = true

  tags = {
    Name = "${local.sub_domain_name}.${local.hosted_zone_name}"
  }
}

resource "aws_dynamodb_table" "test-dynamodb-table" {
  name         = local.dynamodb_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"

  attribute {
    name = "UserId"
    type = "S"
  }
}

########################################
# Dynamo DB
########################################
data "aws_iam_policy_document" "allow_pod_identity" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "read_dynamodb" {
  name               = local.dynamodb_iam
  assume_role_policy = data.aws_iam_policy_document.allow_pod_identity.json
}

resource "aws_iam_role_policy_attachment" "dynamodb_policy_attachment" {
  role       = aws_iam_role.read_dynamodb.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

########################################
# Load Balancer Controller
########################################
resource "aws_iam_policy" "alb_ingress_controller" {
  name   = local.alb_ingress_controller_policy
  policy = file("${path.module}/policy/alb-ingress-controller-policy.json")
}

resource "aws_iam_role" "alb_ingress_controller" {
  name               = local.alb_ingress_controller_role
  assume_role_policy = data.aws_iam_policy_document.allow_pod_identity.json
}

resource "aws_iam_role_policy_attachment" "alb_policy_attachment" {
  role       = aws_iam_role.alb_ingress_controller.name
  policy_arn = aws_iam_policy.alb_ingress_controller.arn
}

########################################
# External DNS
########################################
resource "aws_iam_policy" "external_dns" {
  name   = local.external_dns_role_policy
  policy = file("${path.module}/policy/external-dns-policy.json")
}

resource "aws_iam_role" "external_dns" {
  name               = local.external_dns_role_role
  assume_role_policy = data.aws_iam_policy_document.allow_pod_identity.json
}

resource "aws_iam_role_policy_attachment" "external_dns_policy_attachment" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}
