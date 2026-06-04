# Peoplemesh Quickstart for OpenShift

This repository provides Helm charts for deploying [Peoplemesh](https://github.com/francescopace/peoplemesh) to an OpenShift cluster. Peoplemesh is a semantic search platform for finding people, skills, and expertise within organizations.

## Overview

Peoplemesh models organizations as a graph-like mesh where each entity (people, opportunities, groups, communities, projects) is a node. It uses vector embeddings and semantic similarity matching to enable powerful search capabilities.

## Architecture

This deployment includes four main components:

1. **PostgreSQL with pgvector** - Vector database for storing embeddings
2. **Docling** - Document parsing service for CV/PDF import
3. **vLLM** (optional) - Local LLM inference server using KServe
4. **Peoplemesh** - Main application with web UI and REST API

## Prerequisites

- OpenShift cluster (4.12+)
- Helm 3.x
- `kubectl` or `oc` CLI
- For local LLM deployment: OpenShift AI or KServe installed with GPU nodes available

## Quick Start

### 1. Build Helm Dependencies

```bash
cd peoplemesh-umbrella
helm dependency build
```

### 2. Install with Default Configuration

This deploys with local LLM using vLLM:

```bash
helm install peoplemesh . \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=YOUR_SECURE_PASSWORD
```

### 3. Install with External LLM

To use an external LLM service (e.g., OpenAI):

```bash
helm install peoplemesh . \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=YOUR_SECURE_PASSWORD \
  --set vllm.enabled=false \
  --set peoplemesh.llm.mode=external \
  --set peoplemesh.llm.external.baseUrl=https://api.openai.com/v1 \
  --set peoplemesh.llm.external.apiKey=YOUR_API_KEY \
  --set peoplemesh.llm.external.chatModel=gpt-4o-mini \
  --set peoplemesh.llm.external.embeddingModel=text-embedding-3-small \
  --set peoplemesh.llm.external.embeddingDimension=1536
```

### 4. Access the Application

Get the route URL:

```bash
oc get route peoplemesh -n peoplemesh
```

Visit the URL in your browser to access the Peoplemesh UI.

## Configuration Options

### Two Deployment Modes

#### Mode 1: Local LLM (Default)
Deploys vLLM with KServe for on-cluster inference. Requires GPU nodes.

```yaml
vllm:
  enabled: true
peoplemesh:
  llm:
    mode: local
```

#### Mode 2: External LLM
Uses an external vLLM inference server or OpenAI-compatible API.

```yaml
vllm:
  enabled: false
peoplemesh:
  llm:
    mode: external
    external:
      baseUrl: "https://your-vllm-endpoint.com/v1"
      apiKey: "your-api-key"
      chatModel: "model-name"
      embeddingModel: "embedding-model-name"
```

### Customize Values

Create a custom `values.yaml` file (see [examples/values-openshift.yaml](examples/values-openshift.yaml)):

```bash
helm install peoplemesh . \
  --namespace peoplemesh \
  --create-namespace \
  -f examples/values-openshift.yaml
```

## Components

### Individual Charts

You can also deploy components individually:

```bash
# PostgreSQL only
helm install pgvector charts/pgvector \
  --namespace peoplemesh \
  --set postgres.password=secure-password

# Docling only
helm install docling charts/docling \
  --namespace peoplemesh

# vLLM only (requires KServe)
helm install vllm charts/vllm \
  --namespace peoplemesh

# Peoplemesh application only
helm install peoplemesh charts/peoplemesh \
  --namespace peoplemesh \
  --set database.host=pgvector-service
```

## Configuration Reference

### Database Configuration

```yaml
pgvector:
  postgres:
    userId: peoplemesh
    password: changeme-secure-password  # REQUIRED
    databaseName: peoplemesh
    persistence:
      size: 20Gi
```

### LLM Configuration (Local)

```yaml
vllm:
  model:
    storage:
      uri: "hf://Qwen/Qwen2.5-7B-Instruct-AWQ"
    resources:
      limits:
        nvidia.com/gpu: 1
        memory: "12Gi"
```

### Organization Configuration

```yaml
peoplemesh:
  organization:
    name: "My Organization"
    contactEmail: "contact@example.com"
    dpoEmail: "dpo@example.com"
    dataLocation: "US"
    governingLaw: "US Law"
```

## Troubleshooting

### Check Pod Status

```bash
oc get pods -n peoplemesh
```

### View Logs

```bash
# Peoplemesh application
oc logs -f deployment/peoplemesh -n peoplemesh

# PostgreSQL
oc logs -f statefulset/pgvector -n peoplemesh

# Docling
oc logs -f deployment/docling -n peoplemesh

# vLLM (if using local LLM)
oc logs -f -l app=peoplemesh-llm -n peoplemesh
```

### Common Issues

1. **vLLM pod not starting**: Ensure GPU nodes are available and KServe is installed
2. **Database connection failures**: Check pgvector pod is running and password is correct
3. **LLM timeout errors**: Increase timeout values or reduce model size

## Uninstall

```bash
helm uninstall peoplemesh -n peoplemesh
```

To completely remove all resources including PVCs:

```bash
oc delete namespace peoplemesh
```

## Security Notes

- Change default PostgreSQL password in production
- Auto-generated secrets (session, OAuth state, maintenance key) are created on first install
- For production, configure OIDC providers (Google, Microsoft) in values
- Review GDPR compliance settings for your jurisdiction

## Contributing

Issues and pull requests are welcome at the [peoplemesh repository](https://github.com/francescopace/peoplemesh).

## License

See the [Peoplemesh project](https://github.com/francescopace/peoplemesh) for license information.
