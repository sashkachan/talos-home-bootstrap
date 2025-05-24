#!/bin/bash
set -e

# Talos Health Check Script
#
# This script checks the health of a Talos Kubernetes cluster by:
# 1. Checking the status of key services on control plane nodes
# 2. Checking the status of etcd and API server components
# 3. Verifying connectivity to the Kubernetes API

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GENERATED_DIR="$SCRIPT_DIR/generated"
source "$GENERATED_DIR/cluster_info.env"

# Configure talosctl
echo "Using talosconfig from $GENERATED_DIR/talosconfig"
export TALOSCONFIG="$GENERATED_DIR/talosconfig"

# Check if we have nodes defined
if [ -z "$NODE_IPS" ]; then
  echo "ERROR: No nodes specified in environment."
  echo "Please ensure NODE_IPS is set in $GENERATED_DIR/cluster_info.env."
  exit 1
fi

echo "==== Talos Cluster Health Check ===="
echo "Control plane nodes: $NODE_IPS"

# Function to check all services on a node
check_services() {
  local node=$1

  echo "  Checking all services:"
  talosctl -n "$node" services

  # Return 0 if successful, 1 if command failed
  return $?
}

# Function to check etcd member status
check_etcd_members() {
  local node=$1

  echo "  Checking etcd members:"
  talosctl -n "$node" etcd members 2>/dev/null

  local result=$?

  if [ $result -ne 0 ]; then
    echo "  ✗ Could not retrieve etcd member list"
    return 1
  fi

  return 0
}

# Function to check etcd status
check_etcd_status() {
  local node=$1

  echo "  Checking etcd status:"
  talosctl -n "$node" etcd status 2>/dev/null

  local result=$?

  if [ $result -ne 0 ]; then
    echo "  ✗ Could not retrieve etcd status"
    return 1
  fi

  return 0
}

# Check each control plane node individually
node_statuses=()
for node in $NODE_IPS; do
  echo ""
  echo "=== Checking node $node ==="

  # Check all services on the node
  echo "Checking services on $node:"
  check_services "$node"
  services_status=$?

  # Check etcd status if possible
  echo "Checking etcd on $node:"
  check_etcd_status "$node"
  etcd_status=$?

  # Check etcd members if etcd status check was successful
  if [ $etcd_status -eq 0 ]; then
    echo "Checking etcd members on $node:"
    check_etcd_members "$node"
    etcd_members_status=$?
  else
    etcd_members_status=1
  fi

  # Determine overall node status
  if [ $services_status -eq 0 ] && [ $etcd_status -eq 0 ] && [ $etcd_members_status -eq 0 ]; then
    node_statuses+=("$node: ✓ Healthy")
  else
    node_statuses+=("$node: ✗ Issues detected")
  fi
done

# Print summary
echo ""
echo "=== Cluster Health Summary ==="
for status in "${node_statuses[@]}"; do
  echo "$status"
done

# Check if Kubernetes config exists and try kubectl if it does
KUBECONFIG_PATH="$GENERATED_DIR/kubeconfig"
if [ -f "$KUBECONFIG_PATH" ]; then
  echo ""
  echo "=== Kubernetes Components ==="
  echo "Checking Kubernetes components with kubectl..."

  export KUBECONFIG="$KUBECONFIG_PATH"
  if kubectl get nodes &>/dev/null; then
    echo "✓ Can access Kubernetes API"
    echo ""
    echo "Kubernetes nodes:"
    kubectl get nodes
  else
    echo "✗ Cannot access Kubernetes API using kubeconfig"
  fi
else
  echo ""
  echo "No kubeconfig found at $KUBECONFIG_PATH"
  echo "Run 'make talos-get-kubeconfig' to retrieve it"
fi
