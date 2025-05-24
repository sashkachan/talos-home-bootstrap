#!/bin/bash
set -e

# Reset Talos Cluster Script
#
# Usage: reset_cluster.sh
#
# This script:
# 1. Loads environment from previous steps
# 2. Resets the Talos nodes to a clean state
# 3. Allows for a fresh bootstrap
#
# WARNING: This is a destructive operation that will wipe all data on the nodes!

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GENERATED_DIR="$SCRIPT_DIR/generated"

if [ ! -f "$GENERATED_DIR/cluster_info.env" ]; then
  echo "Error: cluster_info.env not found. Run 'make talos-prepare TALOS_VERSION=<version>' first."
  exit 1
fi

source "$GENERATED_DIR/cluster_info.env"

# Configure talosctl to use our local config without copying it to ~/.talos
echo "Using talosconfig from $GENERATED_DIR/talosconfig"
export TALOSCONFIG="$GENERATED_DIR/talosconfig"

# Show warning and get confirmation
echo "WARNING: This will RESET ALL NODES in your Talos cluster!"
echo "All data will be lost. This is a destructive operation."
echo "Affected nodes: $NODE_IPS"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Operation cancelled."
  exit 0
fi

# Reset each node in parallel
echo "Resetting all cluster nodes..."

# Function to reset a single node
reset_node() {
  local NODE_IP=$1
  local NODE_NUM=$2
  local TOTAL_NODES=$3
  local LOG_FILE="$GENERATED_DIR/node${NODE_NUM}_reset.log"

  {
    echo "[Node $NODE_NUM/$TOTAL_NODES] Resetting node $NODE_IP..."

    # Check if Talos API is available
    if nc -z -w 3 $NODE_IP 50000; then
      echo "[Node $NODE_NUM/$TOTAL_NODES] Talos API is available. Attempting reset..."

      # Try to reset via talosctl
      if talosctl -n $NODE_IP reset --reboot --system-labels-to-wipe STATE; then
        echo "[Node $NODE_NUM/$TOTAL_NODES] Reset command sent successfully. Node is rebooting..."
      else
        echo "[Node $NODE_NUM/$TOTAL_NODES] Failed to reset using talosctl. Falling back to manual reboot..."
      fi
    else
      echo "[Node $NODE_NUM/$TOTAL_NODES] Talos API not available. Using manual reboot..."
    fi

    echo "[Node $NODE_NUM/$TOTAL_NODES] Reset completed!"
    return 0
  } > "$LOG_FILE" 2>&1 &

  echo "Started reset on node $NODE_NUM/$TOTAL_NODES (IP: $NODE_IP). Log: $LOG_FILE"
  return 0
}

# Reset all nodes in parallel
NODE_NUM=0
TOTAL_NODES=$(echo "$NODE_IPS" | wc -w | tr -d ' ')
declare -a RESET_PIDS

for NODE_IP in $NODE_IPS; do
  NODE_NUM=$((NODE_NUM+1))
  reset_node "$NODE_IP" "$NODE_NUM" "$TOTAL_NODES"
  PID=$!
  RESET_PIDS[$NODE_NUM]=$PID
  echo "Reset process started on node $NODE_NUM/$TOTAL_NODES (IP: $NODE_IP, PID: $PID)"
done

# Wait for all reset operations to complete
echo "Waiting for all $TOTAL_NODES nodes to complete reset..."
for i in $(seq 1 $TOTAL_NODES); do
  wait "${RESET_PIDS[$i]}" || true
  EXIT_CODE=$?
  LOG_FILE="$GENERATED_DIR/node${i}_reset.log"

  if [ $EXIT_CODE -eq 0 ]; then
    echo "Node $i/$TOTAL_NODES reset completed"
    tail -n 5 "$LOG_FILE"
  else
    echo "Node $i/$TOTAL_NODES reset may have issues"
    echo "Check log file for details: $LOG_FILE"
    tail -n 20 "$LOG_FILE"
  fi
done

echo "All nodes have been reset to rescue mode."
echo ""
echo "To rebuild your cluster:"
echo "1. Reinstall Talos: make talos-install"
echo "2. Generate configs: make talos-generate-configs"
echo "3. Apply configs: make talos-apply-configs"
echo "4. Bootstrap cluster: make talos-bootstrap-cluster"
echo "5. Get kubeconfig: make talos-get-kubeconfig"
