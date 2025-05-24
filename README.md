# Talos Home Bootstrap

A comprehensive toolkit for bootstrapping and managing Talos Kubernetes clusters with automated configuration and health monitoring.

## Quick Start

### Prerequisites

- `talosctl` CLI tool installed
- `hcloud` CLI for Hetzner Cloud integration
- `kubectl` for Kubernetes management
- Required environment variables set in `terraform/terraform.tfvars`

### One-Command Bootstrap

```bash
make talos-bootstrap TALOS_VERSION=v1.7.1
```

This command handles the complete cluster setup automatically.

## Step-by-Step Bootstrap Process

For more control over the bootstrap process, use individual steps:

### 1. Prepare Environment

```bash
make talos-prepare TALOS_VERSION=v1.7.1
```

Sets up the environment and downloads necessary Talos assets.

### 2. Install Talos

```bash
make talos-install
```

Installs Talos OS on all designated nodes.

### 3. Generate Configurations

```bash
make talos-generate-configs
```

Generates Talos configuration files for the cluster.

To regenerate secrets:
```bash
make talos-generate-configs REGENERATE_SECRETS=true
```

### 4. Apply Configurations

```bash
make talos-apply-configs
```

Applies the generated configurations to all nodes.

For insecure mode:
```bash
make talos-apply-configs INSECURE=true
```

### 5. Bootstrap Cluster

```bash
make talos-bootstrap-cluster
```

Initializes the Kubernetes cluster on the control plane.

### 6. Get Kubeconfig

```bash
make talos-get-kubeconfig
```

Retrieves the kubeconfig for cluster access.

## ArgoCD Access

### Login to ArgoCD

After the cluster is bootstrapped, you can login to ArgoCD:

```bash
make argocd-login
```

This will:
- Display the ArgoCD web UI endpoint and credentials
- Log you in to the ArgoCD CLI automatically

You can then access ArgoCD via:
- **Web UI**: Visit the displayed endpoint
- **CLI**: Use `make argocd CMD='app list'` or other ArgoCD commands

## Cluster Management

### Health Monitoring

Check overall cluster health:
```bash
make talos-health
```

This command:
- Checks service status on all nodes
- Verifies etcd cluster health
- Tests Kubernetes API connectivity
- Provides a comprehensive health summary

### Configuration Management

Copy Talos config to local machine:
```bash
make talos-config
```

Merge kubeconfig with existing kubectl configuration:
```bash
make talos-merge-kubeconfig
```

### Direct Talos Commands

Execute talosctl commands on the cluster:
```bash
# Check cluster version
make talos CMD='version'

# View cluster dashboard
make talos CMD='dashboard'

# Check logs on specific node
make talos CMD='logs kubelet' TALOS_NODE_IP=10.0.0.1

# Upgrade cluster
make talos CMD='upgrade' TALOS_NODE_IP=10.0.0.1
```

### Node Access

SSH into specific nodes:
```bash
# SSH to control plane node 1
make talos-ssh NODE=1

# SSH to control plane node 2
make talos-ssh NODE=2
```

## Cluster Reset

⚠️ **WARNING**: This will completely reset your cluster!

```bash
make talos-reset-cluster
```

## Troubleshooting

### Common Issues

1. **SSH connections closed during bootstrap**: This is normal during node reboots. Check cluster status with:
   ```bash
   make talos-health
   ```

2. **Missing cluster_info.env**: Run the prepare step first:
   ```bash
   make talos-prepare TALOS_VERSION=v1.7.1
   ```

3. **Configuration not found**: Ensure previous steps completed successfully:
   ```bash
   make talos-generate-configs
   ```

### Health Check Details

The health check script (`talos_health.sh`) performs:
- Service status verification on all nodes
- etcd cluster member and status checks
- Kubernetes API connectivity tests
- Node status summary

### Environment Variables

The following variables are automatically extracted from `terraform/terraform.tfvars`:
- `HCLOUD_TOKEN`: Hetzner Cloud API token
- `CLOUDFLARE_API_TOKEN`: Cloudflare API token
- `CLOUDFLARE_ACCOUNT_ID`: Cloudflare account ID
- `CLOUDFLARE_ZONE_ID`: Cloudflare zone ID

### File Structure

```
├── scripts/talos/
│   ├── 1_prepare_environment.sh
│   ├── 2_install_talos.sh
│   ├── 3_generate_configs.sh
│   ├── 4_apply_configs.sh
│   ├── 5_bootstrap_cluster.sh
│   ├── 6_get_kubeconfig.sh
│   ├── reset_cluster.sh
│   ├── talos_health.sh
│   └── generated/
│       ├── cluster_info.env
│       ├── talosconfig
│       └── kubeconfig
├── patches/
│   └── [various configuration patches]
└── manifests/
    └── [Kubernetes manifests]
```

## Additional Commands

### Hetzner Cloud Management

```bash
# List servers
make hcloud CMD='server list'

# Check server details
make hcloud CMD='server describe <server-name>'
```

### Help

Display all available commands:
```bash
make help
```

This will show a complete list of available Make targets with descriptions.

