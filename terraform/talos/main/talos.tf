locals {
  # Use the DNS name for the Kubernetes API endpoint
  talos_endpoint = var.kubernetes_api_fqdn
}