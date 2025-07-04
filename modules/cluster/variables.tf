variable "cluster_name" {
  description = "The name to use for the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "The version for the EKS cluster"
  type        = number
}

variable "node_group_name" {
  description = "The name for the EKS cluster node group"
  type        = string
}

variable "min_size" {
  description = "Minimum number of nodes to have in the EKS cluster"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of nodes to have in the EKS cluster"
  type        = number
  default     = 2
}

variable "desired_size" {
  description = "Desired number of nodes to have in the EKS cluster"
  type        = number
  default     = 3
}

variable "instance_types" {
  description = "The type of EC2 instances to run in the node group"
  type        = list(string)
  default     = ["m3.medium"]
}