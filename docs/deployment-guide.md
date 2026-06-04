# Peoplemesh Deployment Guide

This guide provides detailed instructions for deploying Peoplemesh to OpenShift.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Scenarios](#deployment-scenarios)
- [Step-by-Step Installation](#step-by-step-installation)
- [Post-Installation Configuration](#post-installation-configuration)
- [Validation](#validation)
- [Maintenance](#maintenance)

## Prerequisites

### Required

1. **OpenShift Cluster**: Version 4.12 or later
2. **Helm**: Version 3.x installed locally
3. **CLI Tools**: `oc` or `kubectl` configured for your cluster
4. **Storage**: Default StorageClass configured for PersistentVolumeClaims
5. **Network**: Ability to pull images from Docker Hub and Quay.io

### Optional (for Local LLM)

6. **OpenShift AI**: Installed with KServe/ModelMesh
7. **GPU Nodes**: NVIDIA GPU nodes (A10G, T4, or similar) with at least 24GB VRAM
8. **GPU Operators**: NVIDIA GPU Operator installed

## Deployment Scenarios

### Scenario 1: Quick Evaluation (External LLM)

Best for: Testing, demos, proof-of-concept

- Uses external LLM service (OpenAI)
- No GPU required
- Fastest to deploy

```bash
helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=secure123 \
  --set vllm.enabled=false \
  --set peoplemesh.llm.mode=external \
  --set peoplemesh.llm.external.baseUrl=https://api.openai.com/v1 \
  --set peoplemesh.llm.external.apiKey=sk-your-key \
  --set peoplemesh.llm.external.chatModel=gpt-4o-mini \
  --set peoplemesh.llm.external.embeddingModel=text-embedding-3-small \
  --set peoplemesh.llm.external.embeddingDimension=1536
```

### Scenario 2: Production On-Premise (Local LLM)

Best for: Production deployments, data sovereignty, air-gapped environments

- Uses local vLLM with KServe
- Requires GPU nodes
- Full control over data and models

```bash
helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace peoplemesh \
  -f examples/values-openshift.yaml
```

### Scenario 3: Hybrid (External vLLM Endpoint)

Best for: Shared infrastructure, multi-tenant environments

- Uses centralized vLLM service
- No local GPU required
- Reuses existing LLM infrastructure

```bash
helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace peoplemesh \
  -f examples/values-external-llm.yaml
```

## Step-by-Step Installation

### 1. Prepare Your Environment

```bash
# Clone or navigate to the quickstart repository
cd peoplemesh-quickstart

# Create namespace
oc new-project peoplemesh

# Verify GPU nodes (if using local LLM)
oc get nodes -l nvidia.com/gpu.present=true
```

### 2. Customize Configuration

Create a custom values file:

```bash
cp examples/values-openshift.yaml my-values.yaml
```

Edit `my-values.yaml` to set:

- PostgreSQL password
- LLM mode and credentials
- Organization details
- Route hostname
- Resource limits
- OIDC providers (optional)

### 3. Build Dependencies

```bash
cd peoplemesh-umbrella
helm dependency build
```

This downloads and packages the four subchart dependencies.

### 4. Validate Configuration

```bash
helm template peoplemesh . -f ../my-values.yaml > output.yaml
```

Review `output.yaml` to ensure:
- Secrets are properly templated
- Resource limits are appropriate
- Service names match between components

### 5. Install

```bash
helm install peoplemesh . \
  --namespace peoplemesh \
  -f ../my-values.yaml \
  --timeout 10m
```

The `--timeout 10m` allows time for model downloads if using local LLM.

### 6. Monitor Installation

```bash
# Watch pods start
watch oc get pods -n peoplemesh

# Check deployment status
helm status peoplemesh -n peoplemesh
```

Expected pod startup order:
1. `pgvector-0` (PostgreSQL)
2. `docling-*` (Docling service)
3. `peoplemesh-llm-*` (vLLM, if enabled)
4. `peoplemesh-*` (Application)

## Post-Installation Configuration

### 1. Access the Application

Get the route URL:

```bash
oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}'
```

### 2. First Login

1. Navigate to the route URL
2. Click "Sign in with Google/Microsoft" (if configured)
3. Or use the default admin flow (see maintenance key below)

### 3. Maintenance Access

Retrieve the auto-generated maintenance key:

```bash
oc get secret peoplemesh-secrets -n peoplemesh \
  -o jsonpath='{.data.MAINTENANCE_API_KEY}' | base64 -d
```

Use this key in the `X-Maintenance-Key` header for admin API access.

### 4. Configure OIDC (Optional)

Update the deployment with OIDC credentials:

```bash
helm upgrade peoplemesh . \
  --namespace peoplemesh \
  -f ../my-values.yaml \
  --set peoplemesh.security.google.clientId=YOUR_CLIENT_ID \
  --set peoplemesh.security.google.clientSecret=YOUR_SECRET
```

## Validation

### Health Checks

```bash
# Peoplemesh application health
oc exec -it deployment/peoplemesh -n peoplemesh -- \
  curl http://localhost:8080/q/health

# Database connectivity
oc exec -it statefulset/pgvector -n peoplemesh -- \
  psql -U peoplemesh -d peoplemesh -c "SELECT version();"

# Docling service
oc exec -it deployment/docling -n peoplemesh -- \
  curl http://localhost:5001/health

# vLLM inference (if using local LLM)
oc exec -it deployment/peoplemesh -n peoplemesh -- \
  curl http://peoplemesh-llm-predictor:80/v1/models
```

### Functional Tests

1. **Create a Profile**: Navigate to UI → "Create Profile"
2. **Search**: Try semantic search for skills or names
3. **Import CV**: Upload a test PDF (if Docling is enabled)
4. **Verify Embeddings**: Check that search returns semantically similar results

### Performance Checks

```bash
# Check PostgreSQL performance
oc exec -it statefulset/pgvector -n peoplemesh -- \
  psql -U peoplemesh -d peoplemesh -c "SELECT pg_size_pretty(pg_database_size('peoplemesh'));"

# Check vLLM GPU utilization (if using local LLM)
oc exec -it $(oc get pod -l app=peoplemesh-llm -n peoplemesh -o name | head -1) \
  -n peoplemesh -- nvidia-smi
```

## Maintenance

### Backup Database

```bash
# Backup PostgreSQL data
oc exec -it statefulset/pgvector -n peoplemesh -- \
  pg_dump -U peoplemesh -d peoplemesh > backup.sql
```

### Upgrade

```bash
# Update values
vim my-values.yaml

# Apply upgrade
helm upgrade peoplemesh peoplemesh-umbrella/ \
  --namespace peoplemesh \
  -f my-values.yaml
```

### Scale Components

```bash
# Scale Peoplemesh application
oc scale deployment/peoplemesh -n peoplemesh --replicas=3

# Scale Docling
oc scale deployment/docling -n peoplemesh --replicas=2
```

### View Logs

```bash
# Peoplemesh application logs
oc logs -f deployment/peoplemesh -n peoplemesh

# PostgreSQL logs
oc logs -f statefulset/pgvector -n peoplemesh

# Docling logs
oc logs -f deployment/docling -n peoplemesh

# vLLM logs (if using local LLM)
oc logs -f -l app=peoplemesh-llm -n peoplemesh
```

### Troubleshooting

#### Issue: Peoplemesh pod crashes with database connection error

```bash
# Check pgvector is running
oc get pod pgvector-0 -n peoplemesh

# Verify database credentials
oc get secret pgvector-database -n peoplemesh -o yaml

# Test connection manually
oc exec -it deployment/peoplemesh -n peoplemesh -- \
  env | grep DB_
```

#### Issue: vLLM pod stuck in pending (no GPU)

```bash
# Check GPU node availability
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU operator
oc get pods -n nvidia-gpu-operator

# Verify KServe is installed
oc get crd inferenceservices.serving.kserve.io
```

#### Issue: Slow LLM inference

```bash
# Check vLLM logs for errors
oc logs -f -l app=peoplemesh-llm -n peoplemesh

# Reduce max-model-len in values.yaml
# Increase GPU memory utilization
# Use smaller/quantized model
```

## Uninstall

```bash
# Remove Helm release
helm uninstall peoplemesh -n peoplemesh

# Delete namespace (removes all resources including PVCs)
oc delete project peoplemesh
```

## Additional Resources

- [Peoplemesh GitHub](https://github.com/francescopace/peoplemesh)
- [OpenShift Documentation](https://docs.openshift.com)
- [KServe Documentation](https://kserve.github.io/website/)
- [vLLM Documentation](https://docs.vllm.ai/)
