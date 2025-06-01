#!/bin/bash
set -e

# Step 4: Apply Talos configurations to all nodes
#
# Usage: 4_apply_configs.sh
#
# This script:
# 1. Loads environment from the previous step
# 2. Applies Talos configurations to each node

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GENERATED_DIR="$SCRIPT_DIR/generated"
source "$GENERATED_DIR/cluster_info.env"

# Configure talosctl
echo "Using talosconfig from $GENERATED_DIR/talosconfig"
export TALOSCONFIG="$GENERATED_DIR/talosconfig"

# First try to load the machine IPs if not already set
if [ -z "$NODE_IPS" ]; then
  echo "NODE_IPS not set, attempting to retrieve from Hetzner Cloud..."
  NODE_IPS=$(hcloud server list -o json | jq -r '.[] | select(.labels["type"] == "controlplane") | .public_net.ipv4.ip' | sort)
  echo "Retrieved NODE_IPS: $NODE_IPS"
fi

# Apply configuration to each node
for NODE_IP in $NODE_IPS; do
  echo "Applying configuration to node $NODE_IP"

  # Check if Talos API is available
  echo "Checking if Talos API is available on $NODE_IP:50000..."
  if ! nc -z -w 5 $NODE_IP 50000; then
    echo "Talos API not available on $NODE_IP:50000, server may need a reboot"
    SERVER_ID=$(hcloud server list -o json | jq -r ".[] | select(.public_net.ipv4.ip == \"$NODE_IP\") | .id")
    if [ -n "$SERVER_ID" ]; then
      echo "Rebooting server ID $SERVER_ID with IP $NODE_IP"
      hcloud server reboot "$SERVER_ID"
      echo "Waiting 30 seconds for server to reboot..."
      sleep 30

      # Check again
      if ! nc -z -w 5 $NODE_IP 50000; then
        echo "ERROR: Talos API still not available on $NODE_IP:50000 after reboot"
        echo "Skipping this node. Please check server status manually."
        continue
      fi
    else
      echo "ERROR: Could not find server ID for IP $NODE_IP"
      echo "Skipping this node"
      continue
    fi
  fi

  # Apply configuration using maintenance service
  echo "Applying Talos configuration to $NODE_IP..."

  # Check if we should use the --insecure flag
  INSECURE_FLAG=${INSECURE:-"yes"}
  INSECURE_OPTION=""
  if [ "$INSECURE_FLAG" = "yes" ]; then
    echo "Using --insecure flag for initial configuration (maintenance service)"
    INSECURE_OPTION="--insecure"
  else
    echo "Not using --insecure flag (connecting to configured Talos API)"
  fi
  
  if talosctl apply-config $INSECURE_OPTION -n $NODE_IP -e $NODE_IP -f "$GENERATED_DIR/controlplane.yaml"; then
    echo "Successfully applied configuration to $NODE_IP"
  else
    echo "ERROR: Failed to apply configuration to $NODE_IP"
    echo "This node may already be configured or having issues."
    continue
  fi

  # Give the node some time to process the configuration
  echo "Waiting 10 seconds for configuration to be processed..."
  sleep 10

  echo "Node $NODE_IP configuration complete"
done

# Update talosctl config to use all control plane nodes
echo "Updating talosctl configuration to include all control plane nodes"
talosctl config endpoint $ENDPOINT
talosctl config node $NODE_IPS

# Display the final talosctl configuration
echo "Final talosctl configuration:"
talosctl config info

# Apply worker configurations to specific nodes
echo "Applying worker configurations..."

# Apply worker-1 config to worker-1 node
echo "Applying worker-1 configuration to $WORKER_1_IP..."
if talosctl apply-config $INSECURE_OPTION --nodes $WORKER_1_IP --file generated/worker-1.yaml; then
  echo "Successfully applied worker-1 configuration to $WORKER_1_IP"
else
  echo "ERROR: Failed to apply worker-1 configuration to $WORKER_1_IP"
fi

# Apply worker-2 config to worker-2 node
echo "Applying worker-2 configuration to $WORKER_2_IP..."
if talosctl apply-config $INSECURE_OPTION --nodes $WORKER_2_IP --file generated/worker-2.yaml; then
  echo "Successfully applied worker-2 configuration to $WORKER_2_IP"
else
  echo "ERROR: Failed to apply worker-2 configuration to $WORKER_2_IP"
fi

echo "Configuration complete. You can now run 5_bootstrap_cluster.sh"

# Apply worker-3 config to worker-3 node
echo "Applying worker-3 configuration to $WORKER_3_IP..."
if talosctl apply-config $INSECURE_OPTION --nodes $WORKER_3_IP --file generated/worker-3.yaml; then
  echo "Successfully applied worker-3 configuration to $WORKER_3_IP"
else
  echo "ERROR: Failed to apply worker-3 configuration to $WORKER_3_IP"
fi

echo "Configuration complete. You can now run 5_bootstrap_cluster.sh"
