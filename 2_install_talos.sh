#!/bin/bash
set -e

# Step 2: Install Talos on all nodes
#
# Usage: 2_install_talos.sh
#
# This script:
# 1. Loads environment from the previous step
# 2. Puts servers into rescue mode
# 3. Installs Talos on each server in parallel

# Load environment from previous step
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GENERATED_DIR="$SCRIPT_DIR/generated"
source "$GENERATED_DIR/cluster_info.env"

# Function to install Talos on a single node
install_talos_on_node() {
  local SERVER_ID=$1
  local NODE_NUM=$2
  local TOTAL_NODES=$3
  local LOG_FILE="$GENERATED_DIR/node${NODE_NUM}_install.log"

  {
    echo "[Node $NODE_NUM/$TOTAL_NODES] Installing Talos on server ID: $SERVER_ID"
    SERVER_IP=$(hcloud server describe "$SERVER_ID" -o json | jq -r '.public_net.ipv4.ip')
    echo "[Node $NODE_NUM/$TOTAL_NODES] Server IP: $SERVER_IP"

    # Enable rescue mode
    echo "[Node $NODE_NUM/$TOTAL_NODES] Enabling rescue mode for server $SERVER_ID..."
    hcloud server enable-rescue --ssh-key "$CLUSTER_NAME-key" "$SERVER_ID"

    # Verify rescue mode was enabled
    RESCUE_STATUS=$(hcloud server describe "$SERVER_ID" -o json | jq -r '.rescue_enabled')
    echo "[Node $NODE_NUM/$TOTAL_NODES] Rescue mode status: $RESCUE_STATUS"

    # Reboot into rescue mode
    echo "[Node $NODE_NUM/$TOTAL_NODES] Rebooting server $SERVER_ID into rescue mode..."
    hcloud server reboot "$SERVER_ID"

    # Remove old host key if it exists
    ssh-keygen -R "$SERVER_IP" 2>/dev/null || true

    # Wait for SSH to become available - give it enough time to boot
    echo "[Node $NODE_NUM/$TOTAL_NODES] Waiting for SSH to become available..."
    sleep 20

    # More reliable SSH connection handling
    for attempt in {1..30}; do
      if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$SERVER_IP echo "SSH is up"; then
        echo "[Node $NODE_NUM/$TOTAL_NODES] SSH connection established!"
        break
      fi

      echo "[Node $NODE_NUM/$TOTAL_NODES] Waiting for SSH on $SERVER_IP... attempt $attempt/30"
      sleep 10

      # Try rebooting if we can't connect after 15 attempts
      if [ $attempt -eq 15 ]; then
        echo "[Node $NODE_NUM/$TOTAL_NODES] Still waiting for SSH after 15 attempts. Rebooting server..."
        hcloud server reboot "$SERVER_ID"
        sleep 20
      fi

      if [ $attempt -eq 30 ]; then
        echo "[Node $NODE_NUM/$TOTAL_NODES] ERROR: Failed to connect via SSH after 30 attempts"
        return 1
      fi
    done

    # Install Talos with fixed /dev/sda device
    echo "[Node $NODE_NUM/$TOTAL_NODES] Installing Talos $TALOS_VERSION on server $SERVER_IP..."

    # Use || true to prevent the script from exiting when SSH connection closes during reboot
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$SERVER_IP <<EOF || true
      set -ex
      apt-get update && apt-get install -y wget pv

      # Verify rescue system
      echo "Rescue system details:"
      uname -a

      # Use fixed Talos version
      export TALOS_VERSION=$TALOS_VERSION
      echo "Using Talos version: \$TALOS_VERSION"

      # Download Talos image with proper error handling
      echo "Downloading Talos image v\$TALOS_VERSION..."
      DOWNLOAD_URL="https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/\${TALOS_VERSION}/hcloud-amd64.raw.xz"
      echo "Download URL: \$DOWNLOAD_URL"

      wget --progress=bar:force "\$DOWNLOAD_URL" -O /root/hcloud-amd64.raw.xz

      # Verify download
      if [ ! -f /root/hcloud-amd64.raw.xz ] || [ ! -s /root/hcloud-amd64.raw.xz ]; then
        echo "ERROR: Downloaded file is missing or empty!"
        exit 1
      fi

      echo "Download complete. File size: \$(du -h /root/hcloud-amd64.raw.xz | awk '{print \$1}')"

      # Extract image
      echo "Extracting Talos image..."
      pv /root/hcloud-amd64.raw.xz | xz -d > /root/hcloud-amd64.raw

      # Always use /dev/sda for Hetzner
      BOOT_DEVICE="/dev/sda"

      # Show disk info for verification
      echo "Disk layout before installation:"
      lsblk -p

      echo "Installing Talos to boot device: \$BOOT_DEVICE"

      # Write Talos image to the boot device
      dd if=/root/hcloud-amd64.raw of=\$BOOT_DEVICE bs=4M status=progress
      sync

      echo "Talos has been written to disk. Disk layout after installation:"
      lsblk -p

      echo "Rebooting into Talos..."
      sleep 3
      reboot
EOF

    echo "[Node $NODE_NUM/$TOTAL_NODES] Server is rebooting into Talos..."

    # Wait for SSH to go down (confirming reboot)
    for i in {1..20}; do
      if ! nc -z "$SERVER_IP" 22 -w 1 2>/dev/null; then
        echo "[Node $NODE_NUM/$TOTAL_NODES] SSH is down, server is rebooting"
        break
      fi
      sleep 2
    done

    # Wait for Talos API to come up with longer timeout
    echo "[Node $NODE_NUM/$TOTAL_NODES] Waiting for Talos API to come up on $SERVER_IP:50000..."
    # Give Talos more time to boot before checking
    sleep 60

    for i in {1..60}; do
      if nc -z "$SERVER_IP" 50000 -w 5 2>/dev/null; then
        echo "[Node $NODE_NUM/$TOTAL_NODES] Talos API is available on $SERVER_IP:50000, installation successful!"
        return 0
      fi

      if [ $((i % 5)) -eq 0 ]; then
        echo "[Node $NODE_NUM/$TOTAL_NODES] Waiting for Talos API... attempt $i/60"
      fi

      # Try a reboot at certain intervals if API not available
      if [ $i -eq 30 ]; then
        echo "[Node $NODE_NUM/$TOTAL_NODES] Talos API still not available. Rebooting server..."
        hcloud server reboot "$SERVER_ID"
        sleep 30
      fi

      sleep 5
    done

    echo "[Node $NODE_NUM/$TOTAL_NODES] WARNING: Talos API not detected within timeout period"
    echo "[Node $NODE_NUM/$TOTAL_NODES] Performing final reboot before continuing..."
    hcloud server reboot "$SERVER_ID"
    sleep 30

    # Final check for Talos API
    if nc -z "$SERVER_IP" 50000 -w 5 2>/dev/null; then
      echo "[Node $NODE_NUM/$TOTAL_NODES] Talos API is now available after final reboot!"
      return 0
    else
      echo "[Node $NODE_NUM/$TOTAL_NODES] Talos API still not available. May need manual intervention."
      echo "[Node $NODE_NUM/$TOTAL_NODES] To manually check: nc -zv $SERVER_IP 50000"
      return 1
    fi
  } > "$LOG_FILE" 2>&1 &

  echo "Started installation on node $NODE_NUM (server ID: $SERVER_ID, IP: $(hcloud server describe "$SERVER_ID" -o json | jq -r '.public_net.ipv4.ip')). Log: $LOG_FILE"
  return 0
}

# Install Talos on all nodes in parallel
echo "Installing Talos on all nodes in parallel..."

# Start the installations in parallel
NODE_NUM=0
TOTAL_NODES=$(echo "$SERVER_IDS" | wc -w | tr -d ' ')
declare -a PIDS

for SERVER_ID in $SERVER_IDS; do
  NODE_NUM=$((NODE_NUM+1))
  SERVER_IP=$(hcloud server describe "$SERVER_ID" -o json | jq -r '.public_net.ipv4.ip')
  install_talos_on_node "$SERVER_ID" "$NODE_NUM" "$TOTAL_NODES"
  PID=$!
  PIDS[$NODE_NUM]=$PID
  echo "Installation started on node $NODE_NUM/$TOTAL_NODES (Server ID: $SERVER_ID, IP: $SERVER_IP, PID: $PID)"

  # Stagger the installations to avoid overwhelming the Hetzner API
  sleep 5
done

# Wait for all installations to complete
echo "Waiting for all $TOTAL_NODES nodes to complete installation..."

for i in $(seq 1 $TOTAL_NODES); do
  SERVER_ID=$(echo $SERVER_IDS | cut -d ' ' -f $i)
  NODE_IP=$(hcloud server describe "$SERVER_ID" -o json | jq -r '.public_net.ipv4.ip')
  LOG_FILE="$GENERATED_DIR/node${i}_install.log"
  PID="${PIDS[$i]}"

  echo "Waiting for node $i/$TOTAL_NODES (IP: $NODE_IP, PID: $PID) installation to complete..."

  # Wait for process to complete
  wait "$PID" || {
    echo "Node $i/$TOTAL_NODES installation failed or timed out."
    echo "Last 20 log entries:"
    tail -n 20 "$LOG_FILE"

    # Check if Talos API is available despite the error
    if nc -z "$NODE_IP" 50000 -w 5 2>/dev/null; then
      echo "GOOD NEWS: Talos API IS available on $NODE_IP:50000 despite log issues!"
    else
      echo "WARNING: Talos API is NOT available on $NODE_IP:50000"
      echo "You may need to manually check or reinstall this node."
    fi
  }
done

echo "All node installations completed. The next step is to run 3_generate_configs.sh"
echo "To verify Talos API availability on all nodes, you can run:"
for SERVER_ID in $SERVER_IDS; do
  SERVER_IP=$(hcloud server describe "$SERVER_ID" -o json | jq -r '.public_net.ipv4.ip')
  echo "  nc -zv $SERVER_IP 50000"
done
