variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "The name of the Talos cluster"
  type        = string
  default     = "homelab-talos"
}

variable "talos_version" {
  description = "Talos version to install"
  type        = string
  default     = "v1.10.1"
}

variable "hcloud_region" {
  description = "Hetzner Cloud region"
  type        = string
  default     = "fsn1"
}

variable "hcloud_control_plane_type" {
  description = "Hetzner Cloud server type for control plane nodes"
  type        = string
  default     = "cx22"
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 0
}

variable "network_cidr" {
  description = "CIDR for the cluster network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "servers_subnet_cidr" {
  description = "CIDR for Cloud Servers & Load Balancers subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "kubernetes_api_fqdn" {
  description = "Fully qualified domain name for the Kubernetes API endpoint"
  type        = string
  default     = ""
}
