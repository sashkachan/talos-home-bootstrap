#!/bin/bash
set -e

# Step 6: Retrieve kubeconfig from the Talos cluster
#
# Usage: 6_get_kubeconfig.sh
#
# This script:
# 1. Loads environment from the previous step
# 2. Retrieves the kubeconfig file from the Talos cluster
# 3. Ensures the kubeconfig uses the load balancer endpoint

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GENERATED_DIR="$SCRIPT_DIR/generated"
source "$GENERATED_DIR/cluster_info.env"

# Configure talosctl
echo "Using talosconfig from $GENERATED_DIR/talosconfig"
export TALOSCONFIG="$GENERATED_DIR/talosconfig"

# Make sure we have nodes and endpoint defined
if [ -z "$NODE_IPS" ]; then
  echo "ERROR: No nodes specified in environment."
  echo "Please ensure NODE_IPS is set in $GENERATED_DIR/cluster_info.env."
  exit 1
fi

if [ -z "$ENDPOINT" ]; then
  echo "ERROR: No endpoint (load balancer) specified."
  echo "Please ensure ENDPOINT is set in $GENERATED_DIR/cluster_info.env."
  exit 1
fi

# Select a control plane node to retrieve kubeconfig from
CONTROL_PLANE_NODE=$(echo $NODE_IPS | awk '{print $1}')
echo "Using control plane node $CONTROL_PLANE_NODE to retrieve kubeconfig"
echo "Load balancer endpoint: $ENDPOINT"

# Set up output path
KUBECONFIG_PATH="$GENERATED_DIR/kubeconfig"
echo "Will save kubeconfig to $KUBECONFIG_PATH"

# Wait for Kubernetes API to be available
echo "Checking if Kubernetes API is available..."
echo "This may take a few minutes as the cluster bootstraps..."

echo "Retrieving kubeconfig from the cluster..."
if talosctl kubeconfig -e $CONTROL_PLANE_NODE --nodes $CONTROL_PLANE_NODE "$KUBECONFIG_PATH"; then
  echo "Successfully retrieved kubeconfig to $KUBECONFIG_PATH"

  # Now modify the kubeconfig to use the load balancer instead of direct node access
  echo "Modifying kubeconfig to use load balancer endpoint..."
  TEMP_CONFIG=$(mktemp)

  # Replace the server with the load balancer endpoint
  sed "s|server: https://[^:]*:6443|server: https://$ENDPOINT:6443|g" "$KUBECONFIG_PATH" > "$TEMP_CONFIG"
  mv "$TEMP_CONFIG" "$KUBECONFIG_PATH"

else
  echo "ERROR: Failed to retrieve kubeconfig"
  exit 1
fi

# Verify the kubeconfig is using the load balancer endpoint
if grep -q "$ENDPOINT" "$KUBECONFIG_PATH"; then
  echo "Verified kubeconfig is using the load balancer endpoint ($ENDPOINT)"
else
  echo "WARNING: Kubeconfig may not be using the load balancer endpoint"
  echo "You might need to manually edit the server URL in $KUBECONFIG_PATH"
fi

echo "Kubeconfig retrieval completed."
echo "You can now use kubectl to interact with your cluster:"
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
echo "  kubectl get nodes"
