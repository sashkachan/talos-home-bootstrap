# Output the control plane IPs for easier access
output "control_plane_ips" {
  description = "IPs of the control plane nodes"
  value       = [for i in range(var.control_plane_count) : hcloud_server.control_plane[i].ipv4_address]
}

# Output the cluster endpoint URL
output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://${local.talos_endpoint}:6443"
}

# Output Hetzner network name for the hcloud-controller-manager
output "talos_network_name" {
  description = "Hetzner Cloud network name for the cluster"
  value       = hcloud_network.network.name
}

# Output Hetzner network ID for the hcloud-controller-manager
output "talos_network_id" {
  description = "Hetzner Cloud network ID for the cluster"
  value       = hcloud_network.network.id
}

# Output information that will be needed for the bootstrap scripts
output "control_plane_data" {
  value = {
    cluster_name = var.cluster_name
    endpoint     = local.talos_endpoint
    node_ips     = [for i in range(var.control_plane_count) : hcloud_server.control_plane[i].ipv4_address]
    server_ids   = hcloud_server.control_plane[*].id
  }
}
