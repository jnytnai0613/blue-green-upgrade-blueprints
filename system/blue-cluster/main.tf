module "eks" {
  source = "../../modules/cluster"

  cluster_name    = "blue"
  cluster_version = 1.32
  node_group_name = "blue"
  min_size        = 2
  max_size        = 3
  desired_size    = 2
  instance_types  = ["m3.medium"]
}