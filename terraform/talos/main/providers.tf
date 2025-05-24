terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.50.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.8.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "talos" {
  config_path    = "${path.module}/../generated/talosconfig"
  endpoint       = try(hcloud_server.control_plane[0].ipv4_address, "")
  client_cert    = ""
  client_key     = ""
  ca_certificate = ""
}