# Simplified GPU Configuration

## Overview

GPU support is now controlled by **just 2 simple flags**:
- `ollama.gpu.enabled` (default: `false`)
- `docling.gpu.enabled` (default: `false`)

**No toleration configuration needed!** GPU node tolerations are pre-configured.

## Quick Start

### CPU-Only (Default)
```bash
helm install peoplemesh peoplemesh-umbrella \
  --namespace peoplemesh \
  --set keycloak.postgres.password="..." \
  # ... other secrets (no GPU flags needed)
```

### With GPU (Ollama only - most common)
```bash
helm install peoplemesh peoplemesh-umbrella \
  --namespace peoplemesh \
  --set ollama.gpu.enabled=true \
  --set keycloak.postgres.password="..." \
  # ... other secrets
```

### With GPU (Both Ollama and Docling)
```bash
helm install peoplemesh peoplemesh-umbrella \
  --namespace peoplemesh \
  --set ollama.gpu.enabled=true \
  --set docling.gpu.enabled=true \
  --set keycloak.postgres.password="..." \
  # ... other secrets
```

## What Happens When GPU is Enabled

### Ollama (`ollama.gpu.enabled=true`)
1. ✅ Requests `nvidia.com/gpu: 1` (hard requirement)
2. ✅ Tolerates GPU node taints (`g5-gpu`, `nvidia.com/gpu`)
3. ✅ Schedules to GPU node (A10G, 23GB VRAM)
4. ✅ **10-20x faster** LLM inference
   - Search query parsing: 5-10s → 1-2s
   - CV structuring: 120-240s → 10-20s

### Docling (`docling.gpu.enabled=true`)
1. ✅ Requests `nvidia.com/gpu: 1` (hard requirement)
2. ✅ Tolerates GPU node taints (`g5-gpu`, `nvidia.com/gpu`)
3. ✅ Changes image to GPU version: `docling-serve:latest` (not `-cpu`)
4. ✅ Schedules to GPU node
5. ✅ **Faster** document parsing

## Pre-Configured Tolerations

**No user configuration needed!** Both charts include these tolerations by default:

```yaml
tolerations:
  - key: g5-gpu
    operator: Exists
    effect: NoSchedule
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

**Why this works:**
- Tolerations are **harmless** when `gpu.enabled=false`
- Pod only requests GPU when flag is `true`
- Without GPU request, pod ignores GPU nodes naturally
- With GPU request, tolerations allow scheduling on tainted GPU nodes

## Your Cluster GPU Status

**8 GPU nodes available:**
- GPU Type: NVIDIA A10G (Ampere)
- GPU Memory: 23 GB per GPU
- Instance: AWS g5.2xlarge
- Taint: `g5-gpu=true:NoSchedule`
- Status: All GPUs currently **available** (allocatable)

## Verification After Install

```bash
# Check if Ollama got GPU
oc describe pod ollama-0 -n <namespace> | grep nvidia.com/gpu
# Should show: nvidia.com/gpu: 1 (in both Requests and Limits)

# Check if Docling got GPU
oc describe pod <docling-pod> -n <namespace> | grep nvidia.com/gpu
# Should show: nvidia.com/gpu: 1 (in both Requests and Limits)

# Check which nodes they're running on
oc get pods -n <namespace> -o wide | grep -E "ollama|docling"

# Verify GPU nodes
oc describe node <node-name> | grep nvidia.com/gpu
```

## Common Scenarios

### Scenario 1: No GPU Available
**Flags:** `ollama.gpu.enabled=false`, `docling.gpu.enabled=false` (default)
- ✅ Works on any cluster
- ⏱️ Slower inference (CPU-based)

### Scenario 2: 1 GPU Available - Prioritize Ollama
**Flags:** `ollama.gpu.enabled=true`, `docling.gpu.enabled=false`
- ✅ Ollama gets GPU (biggest performance impact)
- ✅ Docling uses CPU (still functional)
- ⚡ Fast LLM inference, standard document parsing

### Scenario 3: 2+ GPUs Available
**Flags:** `ollama.gpu.enabled=true`, `docling.gpu.enabled=true`
- ✅ Both get GPUs
- ⚡ Maximum performance

### Scenario 4: GPU Enabled but None Available
**Flags:** `ollama.gpu.enabled=true` but no GPU nodes
- ❌ Ollama pod stays **Pending** forever
- ⚠️ Deployment fails
- **Solution:** Set flag to `false` or add GPU nodes

## Troubleshooting

### Pod Stuck in Pending
```bash
oc describe pod ollama-0 -n <namespace>
```
Look for: `FailedScheduling: 0/X nodes are available: X Insufficient nvidia.com/gpu`

**Fix:** Either:
1. Add GPU nodes to cluster, OR
2. Disable GPU: `--set ollama.gpu.enabled=false`

### Pod Running but No Performance Improvement
```bash
# Check if GPU was actually allocated
oc describe pod ollama-0 -n <namespace> | grep -A 5 "Limits:"
```
Should show `nvidia.com/gpu: 1`

If not present:
1. Check helm values: `helm get values peoplemesh -n <namespace> | grep gpu`
2. Rebuild dependencies: `helm dependency update`
3. Reinstall with flag

## Summary

**Before (Complex):**
- Multiple flags needed
- Manual toleration configuration
- Confusing for users

**After (Simple):**
- ✅ Just 2 boolean flags
- ✅ Tolerations pre-configured
- ✅ Works out-of-box on tainted GPU nodes
- ✅ Gracefully falls back to CPU when GPU disabled
