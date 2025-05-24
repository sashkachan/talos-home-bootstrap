#!/bin/bash
set -e

# Step 5: Bootstrap the Talos cluster
#
# Usage: 5_bootstrap_cluster.sh
#
# This script:
# 1. Loads environment from the previous step
# 2. Bootstraps the etcd cluster on the first control plane node

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GENERATED_DIR="$SCRIPT_DIR/generated"
source "$GENERATED_DIR/cluster_info.env"

# Configure talosctl
echo "Using talosconfig from $GENERATED_DIR/talosconfig"
export TALOSCONFIG="$GENERATED_DIR/talosconfig"

# Select first node as the bootstrap node
BOOTSTRAP_NODE=$(echo $NODE_IPS | awk '{print $1}')
echo "Using control plane node $BOOTSTRAP_NODE as bootstrap target"

# Bootstrap the cluster
echo "Bootstrapping the cluster on node $BOOTSTRAP_NODE"
if talosctl bootstrap --nodes $BOOTSTRAP_NODE -e $BOOTSTRAP_NODE; then
  echo "Successfully bootstrapped the cluster"
else
  echo "ERROR: Failed to bootstrap the cluster"
  echo "This could be due to TLS certificate issues"
  exit 1
fi

echo "Cluster bootstrap completed."
echo "You can now retrieve the kubeconfig using: talosctl kubeconfig ."
