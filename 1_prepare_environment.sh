#!/bin/bash
set -e

# TODO: should use internal node IPs
# TODO: should use encrypted inter node communication
# Step 1: Setup environment for Talos installation
#
# Usage: 1_prepare_environment.sh <talos_version>
#
# Environment variables:
# - HCLOUD_TOKEN: Hetzner Cloud API token
#
# This script:
# 1. Validates requirements
# 2. Sets up working directories
# 3. Retrieves server information from Terraform outputs

TALOS_VERSION="$1"

if [ -z "$HCLOUD_TOKEN" ] || [ -z "$TALOS_VERSION" ]; then
  echo "Usage: HCLOUD_TOKEN=your-token 1_prepare_environment.sh <talos_version>"
  echo "Example: HCLOUD_TOKEN=your-token 1_prepare_environment.sh v1.10.1"
  exit 1
fi

# Set up working directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BASE_DIR="$SCRIPT_DIR"
TERRAFORM_DIR="$BASE_DIR/terraform"
GENERATED_DIR="$SCRIPT_DIR/generated"
mkdir -p "$GENERATED_DIR"

echo "Script directory: $SCRIPT_DIR"
echo "Base directory: $BASE_DIR"
echo "Terraform directory: $TERRAFORM_DIR"
echo "Generated directory: $GENERATED_DIR"

# Get control plane data from Terraform
echo "Getting control plane data from Terraform..."
cd "$TERRAFORM_DIR"
CLUSTER_NAME="homelab-talos"

# Get the control plane IPs from Terraform output
NODE_IPS=$(tofu output -json talos_control_plane_ips | jq -r 'join(" ")')

# Get the DNS-based API endpoint from Terraform output
DNS_ENDPOINT=$(tofu output -json talos_cluster_endpoint 2>/dev/null | jq -r '.' 2>/dev/null | sed 's|^https://||' | sed 's|:6443$||')

# Get the Hetzner Cloud network ID
HCLOUD_NETWORK_ID=$(tofu output -json talos_network_id 2>/dev/null | jq -r '.' 2>/dev/null)

if [ -n "$HCLOUD_NETWORK_ID" ] && [ "$HCLOUD_NETWORK_ID" != "null" ]; then
  echo "Using Hetzner Cloud network ID: $HCLOUD_NETWORK_ID"
else
  HCLOUD_NETWORK_ID=""
  echo "WARNING: Hetzner Cloud network ID not available from Terraform output."
  echo "The hcloud controller manager may not work correctly with load balancers."
fi

# Only set ENDPOINT if we have a valid DNS endpoint
if [ -n "$DNS_ENDPOINT" ] && [ "$DNS_ENDPOINT" != "null" ]; then
  ENDPOINT="$DNS_ENDPOINT"
  echo "Using DNS endpoint ($DNS_ENDPOINT) as the cluster endpoint"
else
  # If the DNS endpoint is not available yet, leave ENDPOINT empty
  ENDPOINT=""
  echo "WARNING: DNS endpoint not available yet."
  echo "No endpoint will be set. You MUST apply Terraform first."
  echo "After applying Terraform changes, rerun this script."
fi

# Get server IDs from Hetzner API
declare -a SERVER_ID_ARRAY
for NODE_IP in $NODE_IPS; do
  SERVER_ID=$(HCLOUD_TOKEN=$HCLOUD_TOKEN hcloud server list -o json | jq -r ".[] | select(.public_net.ipv4.ip == \"$NODE_IP\") | .id")
  if [ -n "$SERVER_ID" ]; then
    SERVER_ID_ARRAY+=("$SERVER_ID")
  fi
done
SERVER_IDS="${SERVER_ID_ARRAY[*]}"

echo "Cluster name: $CLUSTER_NAME"
echo "API endpoint: $ENDPOINT"
echo "Node IPs: $NODE_IPS"
echo "Server IDs: $SERVER_IDS"

# Save information to state file for subsequent scripts
cat > "$GENERATED_DIR/cluster_info.env" << EOF
export CLUSTER_NAME="$CLUSTER_NAME"
export ENDPOINT="$ENDPOINT"
export NODE_IPS="$NODE_IPS"
export SERVER_IDS="$SERVER_IDS"
export TALOS_VERSION="$TALOS_VERSION"
export SCRIPT_DIR="$SCRIPT_DIR"
export BASE_DIR="$BASE_DIR"
export TERRAFORM_DIR="$TERRAFORM_DIR"
export GENERATED_DIR="$GENERATED_DIR"
export HCLOUD_NETWORK_ID="$HCLOUD_NETWORK_ID"
EOF

echo "Environment prepared and saved to $GENERATED_DIR/cluster_info.env"
echo "You can now run 2_install_talos.sh"
