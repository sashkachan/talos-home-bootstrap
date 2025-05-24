# DNS Troubleshooting Guide

This document provides step-by-step troubleshooting commands for DNS issues in the Talos Kubernetes cluster.

## Quick DNS Health Check

```bash
# Check DNS service status
kubectl get svc -n kube-system kube-dns

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution
kubectl run dns-test --image=busybox --restart=Never -- sleep 3600
kubectl wait --for=condition=ready pod/dns-test --timeout=60s
kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local
kubectl exec dns-test -- nslookup google.com
kubectl delete pod dns-test
```

## Detailed Troubleshooting Steps

### 1. Check DNS Service Configuration

```bash
# Get DNS service details
kubectl get svc -n kube-system kube-dns -o wide
kubectl describe svc kube-dns -n kube-system

# Check DNS endpoints
kubectl get endpoints -n kube-system kube-dns
```

### 2. Verify Kubelet DNS Configuration

```bash
# Check kubelet DNS settings on control plane
export TALOSCONFIG="$(pwd)/generated/talosconfig"
FIRST_CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
talosctl get kubeletconfig -n $FIRST_CP_NODE -o yaml | grep -A2 clusterDNS

# Check on all control plane nodes
CP_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
for node in $CP_NODES; do
  echo "=== Node $node ==="
  talosctl get kubeletconfig -n $node -o yaml | grep -A2 clusterDNS
done
```

### 3. Check Pod DNS Resolution Configuration

```bash
# Create test pod and check its DNS config
kubectl run dns-config-test --image=busybox --restart=Never -- sleep 3600
kubectl wait --for=condition=ready pod/dns-config-test --timeout=60s

# Check resolv.conf in pod
kubectl exec dns-config-test -- cat /etc/resolv.conf

# Test specific DNS queries
kubectl exec dns-config-test -- nslookup kubernetes.default.svc.cluster.local
kubectl exec dns-config-test -- nslookup kube-dns.kube-system.svc.cluster.local
kubectl exec dns-config-test -- dig @10.0.8.10 kubernetes.default.svc.cluster.local

kubectl delete pod dns-config-test
```

### 4. Check Network Connectivity

```bash
# Test direct connectivity to DNS service
kubectl run net-test --image=busybox --restart=Never -- sleep 3600
kubectl wait --for=condition=ready pod/net-test --timeout=60s

# Test connectivity to DNS service IP
kubectl exec net-test -- nc -v 10.0.8.10 53

# Test connectivity to CoreDNS pod IPs
COREDNS_IPS=$(kubectl get endpoints -n kube-system kube-dns -o jsonpath='{.subsets[0].addresses[*].ip}')
for ip in $COREDNS_IPS; do
  echo "Testing connectivity to CoreDNS pod $ip"
  kubectl exec net-test -- nc -v $ip 53
done

kubectl delete pod net-test
```

### 5. Check CoreDNS Logs and Configuration

```bash
# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20

# Check CoreDNS configuration
kubectl get configmap coredns -n kube-system -o yaml

# Check for any error events
kubectl get events -n kube-system --field-selector involvedObject.name=coredns
```

### 6. Check CNI (Cilium) Status

```bash
# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium connectivity
kubectl exec -n kube-system ds/cilium -- cilium status

# Check Cilium logs for DNS-related issues
kubectl logs -n kube-system -l k8s-app=cilium --tail=20 | grep -i dns
```

### 7. Check Network Policies

```bash
# Check for network policies that might block DNS
kubectl get networkpolicies -A

# Check Cilium network policies
kubectl get cnp -A
```

## Configuration Files

### Key files to check:
- `patches/cp-patch-network.yml` - Talos network configuration
- `3_generate_configs.sh` - Config generation script

### Restart Services After Config Changes:
```bash
# Regenerate configurations
make talos-generate-configs

# Apply updated configurations (for running clusters, may require reboot)
make talos-apply-configs

# For network changes on running clusters, reboot may be required:
export TALOSCONFIG="$(pwd)/generated/talosconfig"
talosctl reboot --nodes <all-node-ips>
```

## Expected Working State

When DNS is working correctly:
- DNS service at `10.96.0.10` (matches service CIDR `10.96.0.0/12`)
- Kubelet clusterDNS configuration points to `10.96.0.10`
- Pod resolv.conf shows `nameserver 10.96.0.10`
- Both internal and external DNS resolution works
- CoreDNS pods are Running and Ready