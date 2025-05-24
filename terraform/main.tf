# Main Terraform configuration file that imports modules
# Import the Talos module first to create the Kubernetes cluster
module "talos" {
  source = "./talos/main"

  # Hetzner Cloud configuration
  hcloud_token              = var.hcloud_token
  hcloud_region             = var.hcloud_region
  hcloud_control_plane_type = var.hcloud_control_plane_type

  # Talos configuration
  cluster_name        = var.cluster_name
  talos_version       = var.talos_version
  control_plane_count = var.control_plane_count
  worker_count        = var.worker_count

  # Network configuration
  network_cidr = var.network_cidr

  # Use the Cloudflare DNS name for the Kubernetes API
  kubernetes_api_fqdn = "${var.kubernetes_api_domain}.${var.root_domain}"
}
# Talos outputs for use with the Makefile talos-ssh command
output "talos_control_plane_ips" {
  description = "IP addresses of the Talos control plane nodes"
  value       = module.talos.control_plane_ips
}

# Kubernetes API endpoint URL
output "talos_cluster_endpoint" {
  description = "Kubernetes API endpoint URL"
  value       = module.talos.cluster_endpoint
}

# Talos network ID for Hetzner Cloud Controller Manager
output "talos_network_id" {
  description = "Hetzner Cloud network ID for the cluster"
  value       = module.talos.talos_network_id
}
