terraform {
  backend "s3" {
    bucket       = "eks-cluster-state-taniai"
    key          = "blue-cluster/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
