#!/bin/bash
set -e

# Step 3: Generate Talos configurations
#
# Usage: 3_generate_configs.sh [REGENERATE_SECRETS=yes|no]
#
# This script:
# 1. Loads environment from the previous step
# 2. Generates Talos configurations for the cluster
# 3. Creates talosconfig with all control plane nodes as endpoints
# 4. Optionally regenerates secrets

# Load environment from previous step
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GENERATED_DIR="$SCRIPT_DIR/generated"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"
source "$GENERATED_DIR/cluster_info.env"

echo "Generating Talos configurations..."

# Create manifests directory if it doesn't exist
mkdir -p "$MANIFESTS_DIR"

# Clean up existing configuration files to avoid the "file already exists" error
echo "Removing any existing Talos configuration files..."
rm -f "$GENERATED_DIR/controlplane.yaml" "$GENERATED_DIR/worker.yaml" "$GENERATED_DIR/talosconfig"

# Make sure we have a valid endpoint
if [ -z "$ENDPOINT" ]; then
  echo "ERROR: No endpoint specified."
  echo "Please set the ENDPOINT variable in $GENERATED_DIR/cluster_info.env."
  exit 1
fi

echo "Generating Talos configurations with endpoint: $ENDPOINT"

# Add all node IPs and the load balancer IP as additional SANs to the certificate
ADDITIONAL_SANS="$ENDPOINT,$(echo $NODE_IPS | tr ' ' ',')"
echo "Adding endpoint and node IPs as additional SANs: $ADDITIONAL_SANS"

# Check if we should regenerate secrets
if [ "${REGENERATE_SECRETS}" == "yes" ]; then
  echo "Regenerating Talos secrets..."
  talosctl gen secrets --output-file "$MANIFESTS_DIR/secrets.yaml" --force
elif [ ! -f "$MANIFESTS_DIR/secrets.yaml" ]; then
  echo "No existing secrets found. Generating new secrets..."
  talosctl gen secrets --output-file "$MANIFESTS_DIR/secrets.yaml" --force
else
  echo "Using existing secrets from $MANIFESTS_DIR/secrets.yaml"
fi

talosctl gen config \
  "$CLUSTER_NAME" \
  "https://$ENDPOINT:6443" \
  --force \
  --with-docs=false \
  --with-kubespan=true \
  --with-examples=false \
  --additional-sans="$ADDITIONAL_SANS" \
  --config-patch-control-plane @patches/cp-patch-kube-prism.yml \
  --config-patch-control-plane @patches/cp-patch-network.yml \
  --config-patch @patches/cf-patch-cni.yml \
  --config-patch @patches/cf-patch-cilium.yml \
  --config-patch @patches/cf-patch-argocd.yml \
  --config-patch @patches/machine-patch-kubespan-filters.yml \
  --with-secrets="$MANIFESTS_DIR/secrets.yaml" \
  --output-dir "$GENERATED_DIR"

# Generate individual worker configurations
echo "Generating individual worker configurations..."

for worker_num in $WORKER_NODES; do
  # Get the patch file path for this worker
  patch_var="WORKER_${worker_num}_PATCH"
  patch_file=${!patch_var}
  
  if [ ! -f "$patch_file" ]; then
    echo "ERROR: Patch file not found: $patch_file"
    exit 1
  fi
  
  echo "Generating config for worker-$worker_num using $patch_file"
  
  # Generate node-specific config file
  talosctl machineconfig patch \
    "$GENERATED_DIR/worker.yaml" \
    --patch @"$patch_file" \
    --output "$GENERATED_DIR/worker-$worker_num.yaml"
    
  echo "✓ Generated config file: $GENERATED_DIR/worker-$worker_num.yaml"
done

echo "All worker configurations generated successfully."
  
# Note: External cloud provider is disabled

# Set up the talosconfig location
export TALOSCONFIG="$GENERATED_DIR/talosconfig"

echo "Configuring talosconfig with all endpoints and nodes..."
echo "Talos configurations generated successfully. You can now run 'make talos-apply-configs'."
