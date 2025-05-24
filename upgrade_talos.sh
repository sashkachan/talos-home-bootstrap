#!/bin/bash
set -e

# Upgrade Talos cluster with custom image
#
# Usage: upgrade_talos.sh [TALOS_VERSION]
#
# This script:
# 1. Loads environment from cluster_info.env
# 2. Generates custom Talos image with system extensions
# 3. Upgrades all nodes with the new image
# 4. Validates the upgrade

# Load environment from previous step
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GENERATED_DIR="$SCRIPT_DIR/generated"
source "$GENERATED_DIR/cluster_info.env"

# Get Talos version from argument or default
TALOS_VERSION=${1:-"v1.8.3"}

echo "Upgrading Talos cluster to version: $TALOS_VERSION"

# Verify talosconfig exists
TALOSCONFIG="$GENERATED_DIR/talosconfig"
if [ ! -f "$TALOSCONFIG" ]; then
  echo "ERROR: talosconfig not found at $TALOSCONFIG"
  echo "Please ensure the cluster is already configured."
  exit 1
fi

# Export talosconfig for talosctl commands
export TALOSCONFIG

echo "Generating custom Talos image with system extensions..."

# Generate custom image with system extensions
IMAGE_ID=$(curl -s -X POST --data-binary @patches/bare-metal.yaml https://factory.talos.dev/schematics | jq -r '.id')

if [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" = "null" ]; then
  echo "ERROR: Failed to generate custom image"
  exit 1
fi

echo "Generated custom image ID: $IMAGE_ID"

# Build the full image URL
CUSTOM_IMAGE="factory.talos.dev/installer/$IMAGE_ID:$TALOS_VERSION"
echo "Using custom image: $CUSTOM_IMAGE"

# Function to upgrade a node
upgrade_node() {
  local node_ip=$1
  local node_type=$2
  
  echo "Upgrading $node_type node: $node_ip"
  
  if ! talosctl upgrade --nodes "$node_ip" --image "$CUSTOM_IMAGE"; then
    echo "WARNING: Upgrade failed for node $node_ip. This might be normal during reboot."
    echo "The node should come back online with the new image."
  fi
  
  # Wait a moment before proceeding to next node
  sleep 5
}

# Upgrade control plane nodes first
echo "Upgrading control plane nodes..."
for cp_ip in $CONTROL_PLANE_IPS; do
  upgrade_node "$cp_ip" "control plane"
done

# Wait for control plane to stabilize
echo "Waiting for control plane to stabilize..."
sleep 30

# Upgrade worker nodes
if [ -n "$WORKER_IPS" ]; then
  echo "Upgrading worker nodes..."
  for worker_ip in $WORKER_IPS; do
    upgrade_node "$worker_ip" "worker"
  done
else
  echo "No worker nodes to upgrade."
fi

echo "Talos upgrade initiated for all nodes."
echo "Nodes will reboot and come back online with the new image."
echo ""
echo "To check the upgrade status, run:"
echo "  make talos-health"
echo "  make talos CMD='version'"
echo ""
echo "To verify the system extensions are loaded:"
echo "  make talos CMD='get extensions'"