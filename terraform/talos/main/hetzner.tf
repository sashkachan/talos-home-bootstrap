# Network setup
resource "hcloud_network" "network" {
  name     = "${var.cluster_name}-network"
  ip_range = var.network_cidr
}

resource "hcloud_network_subnet" "cloud_subnet" {
  network_id   = hcloud_network.network.id
  type         = "server"
  network_zone = "eu-central"
  ip_range     = var.servers_subnet_cidr
}

# Firewall for the cluster
resource "hcloud_firewall" "cluster_firewall" {
  name = "${var.cluster_name}-firewall"

  # Allow internal traffic
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "any"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "any"
    source_ips = [var.network_cidr]
  }

  # Allow SSH from anywhere
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow Kubernetes API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow HTTP for Cilium Gateway
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow HTTPS for Cilium Gateway
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow Kubespan
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow Talos API
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "50000"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow Talos API alternate port
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "50001"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow etcd traffic between nodes
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2379"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2380"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # ICMP
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# SSH key for the servers
resource "hcloud_ssh_key" "default" {
  name = "${var.cluster_name}-key"
  # TODO: make this configurable
  public_key = file("~/.ssh/id_ed25519.pub")
}

# Control plane nodes
resource "hcloud_server" "control_plane" {
  count            = var.control_plane_count
  name             = "${var.cluster_name}-control-plane-${count.index + 1}"
  server_type      = var.hcloud_control_plane_type
  # Start with a basic image - we'll install Talos via rescue mode
  image            = "debian-12"
  location         = var.hcloud_region
  ssh_keys         = [hcloud_ssh_key.default.id]
  firewall_ids     = [hcloud_firewall.cluster_firewall.id]
  delete_protection = true
  rebuild_protection = true

  network {
    network_id = hcloud_network.network.id
    ip         = cidrhost(var.servers_subnet_cidr, count.index + 1)
  }

  # We're using local provisioners in talos.tf to configure the nodes
  # No need for cloud-init user_data

  depends_on = [hcloud_network_subnet.cloud_subnet]
}

# Using DNS-based load balancing instead of a Hetzner load balancer
