# Peoplemesh Quickstart - TL;DR

Get Peoplemesh running on OpenShift in 5 minutes.

## Prerequisites

- OpenShift cluster with `oc` CLI configured
- Helm 3.x installed

## Option 1: With External LLM (Fastest)

```bash
cd peoplemesh-umbrella
helm dependency build

helm install peoplemesh . \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=MySecurePass123 \
  --set vllm.enabled=false \
  --set peoplemesh.llm.mode=external \
  --set peoplemesh.llm.external.baseUrl=https://api.openai.com/v1 \
  --set peoplemesh.llm.external.apiKey=sk-YOUR-OPENAI-KEY \
  --set peoplemesh.llm.external.chatModel=gpt-4o-mini \
  --set peoplemesh.llm.external.embeddingModel=text-embedding-3-small \
  --set peoplemesh.llm.external.embeddingDimension=1536
```

## Option 2: With Local LLM (Requires GPU)

```bash
cd peoplemesh-umbrella
helm dependency build

helm install peoplemesh . \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=MySecurePass123
```

## Access the Application

```bash
# Get the URL
oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}'

# Get maintenance API key
oc get secret peoplemesh-secrets -n peoplemesh \
  -o jsonpath='{.data.MAINTENANCE_API_KEY}' | base64 -d
```

## Verify Deployment

```bash
# Run verification script
./scripts/verify-deployment.sh

# Check pod status
oc get pods -n peoplemesh

# View logs
oc logs -f deployment/peoplemesh -n peoplemesh
```

## Uninstall

```bash
helm uninstall peoplemesh -n peoplemesh
oc delete project peoplemesh
```

## Next Steps

- Read [README.md](README.md) for detailed configuration options
- Review [docs/deployment-guide.md](docs/deployment-guide.md) for production setup
- Customize [examples/values-openshift.yaml](examples/values-openshift.yaml)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Database connection fails | Check `oc get pods pgvector-0` is Running |
| vLLM pod pending | Verify GPU nodes: `oc get nodes -l nvidia.com/gpu.present=true` |
| Route not accessible | Check route: `oc get route peoplemesh -n peoplemesh` |
| LLM timeout | Increase `route.timeout` in values or use smaller model |

## Architecture

```
┌─────────────────┐
│   Peoplemesh    │  (Main Application)
│   Web UI + API  │
└────────┬────────┘
         │
    ┌────┴────┬──────────┬──────────┐
    │         │          │          │
┌───▼────┐ ┌─▼──────┐ ┌─▼──────┐ ┌─▼──────┐
│ PostgreSQL │ │ Docling │ │  vLLM  │ │External│
│ +pgvector  │ │ Service │ │ (opt.) │ │LLM(opt)│
└───────────┘ └────────┘ └────────┘ └────────┘
```

## Component Versions

- **PostgreSQL**: 15 with pgvector extension
- **Docling**: Latest CPU-optimized image
- **vLLM**: v0.11.0 with Qwen2.5-7B-AWQ (default)
- **Peoplemesh**: Latest from `frapax/peoplemesh`

## Resources Required

### Minimal (External LLM)
- 2 CPU cores
- 4GB RAM
- 20GB storage

### With Local LLM
- 1 GPU (24GB VRAM)
- 6 CPU cores
- 20GB RAM
- 50GB storage

## Support

- Issues: https://github.com/francescopace/peoplemesh/issues
- Docs: See [docs/](docs/) directory
