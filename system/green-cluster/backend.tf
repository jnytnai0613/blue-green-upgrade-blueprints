terraform {
  backend "s3" {
    bucket       = "eks-cluster-state-taniai"
    key          = "green-cluster/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}