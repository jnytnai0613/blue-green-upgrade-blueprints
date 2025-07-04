terraform {
  backend "s3" {
    bucket       = "eks-cluster-state-taniai"
    key          = "common/s3/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
