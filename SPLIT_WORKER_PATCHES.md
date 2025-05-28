# Split Worker Patches Implementation

## Problem
The current `3_generate_configs.sh` script only applies one worker patch (`worker-patch-2.yml`) to all workers, but we have two different worker configurations that need different patches applied to each specific worker node.

Current issue on line 63:
```bash
--config-patch-worker @patches/worker-patch-2.yml \
```

## Implementation Steps

### Step 1: Update `1_prepare_environment.sh`

Add worker node definitions to the generated environment file. Insert after line 98, before the `EOF`:

```bash
# Worker node configurations (physical machines)
export WORKER_NODES="1 2"
export WORKER_1_PATCH="patches/worker-patch-1.yml"
export WORKER_2_PATCH="patches/worker-patch-2.yml"
export WORKER_1_IP="10.200.0.8"
export WORKER_2_IP="10.200.0.6"
```

### Step 2: Update `3_generate_configs.sh`

#### 2.1 Remove Worker Patch from Main Generation
Remove line 63:
```bash
# REMOVE THIS LINE:
--config-patch-worker @patches/worker-patch-2.yml \
```

#### 2.2 Add Worker-Specific Generation Loop
Add after the main `talosctl gen config` command (around line 69):

```bash
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
```

### Step 3: Update `4_apply_configs.sh`

Replace generic worker config application with node-specific configs:

```bash
# Apply worker-1 config to worker-1 node
talosctl apply-config --insecure --nodes $WORKER_1_IP --file generated/worker-1.yaml

# Apply worker-2 config to worker-2 node  
talosctl apply-config --insecure --nodes $WORKER_2_IP --file generated/worker-2.yaml
```

### Step 4: File Structure After Generation

```
generated/
├── controlplane.yaml     # Control plane config
├── worker.yaml          # Base worker config (generic)
├── worker-1.yaml        # Worker 1 specific config
├── worker-2.yaml        # Worker 2 specific config
└── talosconfig          # Talos client config
```

## Validation

After generation, validate each config:
```bash
talosctl validate --config generated/worker-1.yaml --mode metal
talosctl validate --config generated/worker-2.yaml --mode metal
```