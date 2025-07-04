module "eks" {
  source = "../../modules/cluster"

  cluster_name    = "green"
  cluster_version = 1.33
  node_group_name = "green"
  min_size        = 2
  max_size        = 3
  desired_size    = 2
  instance_types  = ["m3.medium"]
}