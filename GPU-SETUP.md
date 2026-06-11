# GPU Acceleration for Ollama

Ollama can use NVIDIA GPUs to dramatically speed up LLM inference. On GPU, operations that take 2-3 minutes on CPU complete in seconds.

## Performance Improvement

| Operation | CPU (4 cores) | GPU (1x T4) |
|-----------|---------------|-------------|
| Search query parsing | ~5-10s | ~1-2s |
| CV profile structuring | ~120-240s | ~10-20s |
| Embedding generation | ~2-3s | <1s |

## Prerequisites

1. **GPU-enabled nodes** in your OpenShift/Kubernetes cluster
2. **NVIDIA GPU Operator** installed (provides device plugin and drivers)
3. **GPU resources available** - this deployment uses the standard NVIDIA resource identifier `nvidia.com/gpu`

### Check GPU Availability

```bash
# List nodes with GPU
oc get nodes -o json | jq '.items[] | select(.status.capacity."nvidia.com/gpu" != null) | .metadata.name'

# Check GPU details on a node
oc describe node <node-name> | grep -A 5 nvidia.com/gpu

# Or check all nodes
oc get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu
```

## Enable GPU for Ollama and Docling

**Default configuration:** GPU disabled for maximum compatibility.

**Important:** GPU is a **hard requirement** when enabled. If no GPU is available, pods will remain in `Pending` state.

**GPU Tolerations:** Pre-configured for common GPU node taints (`g5-gpu`, `nvidia.com/gpu`) - no additional configuration needed!

### Simplified GPU Configuration

Just **two flags** control GPU usage:

**New installation:**
```bash
helm install peoplemesh peoplemesh-umbrella \
  --namespace peoplemesh \
  --set ollama.gpu.enabled=true \
  --set docling.gpu.enabled=true \
  --set keycloak.postgres.password=<password> \
  # ... other required secrets
```

**Existing deployment:**
```bash
helm upgrade peoplemesh peoplemesh-umbrella \
  --namespace samouelian-peoplemesh \
  --reuse-values \
  --set ollama.gpu.enabled=true \
  --set docling.gpu.enabled=true
```

**GPU Flag Options:**
- `ollama.gpu.enabled=true` - Enables GPU for LLM inference (search, CV parsing)
- `docling.gpu.enabled=true` - Enables GPU for document processing
- Both default to `false` (CPU-only mode)
- Both can share the same GPU or use separate GPUs

## Deploy with GPU

After enabling GPU in values.yaml:

```bash
# Update dependencies
cd peoplemesh-umbrella
helm dependency update

# Upgrade deployment
helm upgrade peoplemesh . \
  --namespace samouelian-peoplemesh \
  --reuse-values
```

The Ollama pod will be rescheduled to a GPU node. The StatefulSet will:
1. Delete the old CPU-based pod
2. Create a new pod on a GPU node
3. Re-pull models (they're stored in PVC, so this is fast)
4. Start serving with GPU acceleration

## Verify GPU Usage

### Check Pod Placement

```bash
# Get the node where Ollama is running
oc get pod -l app.kubernetes.io/name=ollama -n samouelian-peoplemesh -o wide

# Verify that node has GPU
oc describe node <node-name> | grep nvidia.com/gpu
```

### Check GPU Allocation

```bash
# Check if pod has GPU assigned
oc describe pod ollama-0 -n samouelian-peoplemesh | grep nvidia.com/gpu

# Should show:
# Requests:
#   nvidia.com/gpu: 1
# Limits:
#   nvidia.com/gpu: 1
```

### Monitor GPU Usage

```bash
# Exec into Ollama pod
oc exec -it <ollama-pod-name> -n samouelian-peoplemesh -- /bin/bash

# Check GPU visibility (if nvidia-smi is available)
nvidia-smi

# Or check CUDA devices
ls -la /dev/nvidia*
```

### Test Performance

Upload a resume and observe the CV import logs:

```bash
oc logs -f <peoplemesh-pod-name> -n samouelian-peoplemesh | grep "Profile structuring"
```

**Before (CPU):** `Profile structuring LLM started` → 120-240s delay → `completed`  
**After (GPU):** `Profile structuring LLM started` → 10-20s delay → `completed`

## Troubleshooting

### Pod Stuck in Pending

```bash
# Check events
oc describe pod <ollama-pod-name> -n samouelian-peoplemesh
```

**Common causes:**
- No GPU nodes available → Add GPU nodes to cluster
- GPU already allocated → Scale down other GPU workloads or add more GPUs
- Missing GPU operator → Install NVIDIA GPU Operator

### Pod Running but Not Using GPU

```bash
# Check device plugin
oc get daemonset -n nvidia-gpu-operator nvidia-device-plugin-daemonset

# Check if GPU is visible in container
oc exec <ollama-pod-name> -n samouelian-peoplemesh -- ls -la /dev/nvidia0
```

If `/dev/nvidia0` doesn't exist, the GPU device plugin isn't working correctly.

### Performance Not Improved

Check Ollama is actually using GPU:

```bash
# View Ollama logs during inference
oc logs -f <ollama-pod-name> -n samouelian-peoplemesh
```

Look for GPU-related messages in Ollama startup logs. Ollama automatically detects and uses GPUs when available.

## GPU Models and Sizing

### Recommended GPU for Peoplemesh

| GPU | VRAM | Models Supported | Performance |
|-----|------|------------------|-------------|
| Tesla T4 | 16GB | granite4:3b + embedding | Good (10-20s) |
| Tesla V100 | 16/32GB | granite4:3b + embedding | Excellent (5-10s) |
| A10/A100 | 24/80GB | Larger models (7b, 13b) | Excellent (<5s) |

### Model Size Considerations

Current models:
- `granite4:3b` - Chat model (~2GB VRAM)
- `granite-embedding:30m` - Embedding model (~100MB VRAM)

**Total:** ~3GB VRAM required, so any GPU with 8GB+ VRAM works well.

For larger models (granite-8b, llama-13b), you'll need 16GB+ VRAM.

## Cost Considerations

**Cloud GPU pricing (approximate):**
- AWS p3.2xlarge (1x V100): $3.06/hour
- GCP n1-standard-4 + T4: $0.95/hour
- Azure NC6s_v3 (1x V100): $3.06/hour

**CPU vs GPU cost:**
- CPU: Slower but cheaper (~$0.10-0.20/hour for 4 vCPU)
- GPU: 10-20x faster but 5-15x more expensive

**Recommendation:** Use GPU if:
- High CV upload volume (>10/day)
- User-facing latency matters (waiting 2 minutes is bad UX)
- Budget allows ($50-100/month extra for T4)

For demo/testing with low usage, CPU is fine with the 240s timeout.

## Rollback to CPU

To disable GPU and return to CPU:

```bash
# Comment out GPU requests in values.yaml, then:
helm upgrade peoplemesh peoplemesh-umbrella \
  --namespace samouelian-peoplemesh \
  --reuse-values
```

The pod will reschedule to a CPU node.

## References

- [NVIDIA GPU Operator Docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html)
- [OpenShift GPU Documentation](https://docs.openshift.com/container-platform/latest/architecture/nvidia-gpu-architecture-overview.html)
- [Ollama GPU Support](https://github.com/ollama/ollama/blob/main/docs/gpu.md)
