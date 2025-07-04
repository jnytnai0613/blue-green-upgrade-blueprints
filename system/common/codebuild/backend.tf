terraform {
  backend "s3" {
    bucket       = "eks-cluster-state-taniai"
    key          = "common/codebuild/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}