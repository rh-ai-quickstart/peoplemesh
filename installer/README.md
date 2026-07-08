# Peoplemesh Installer Container

This directory contains the installer container image for the Peoplemesh quickstart, designed to be used by Project Navigator for automated deployment.

## Overview

The installer is a self-contained OCI image that bundles:
- Deployment scripts (Bash)
- Helm charts (peoplemesh-umbrella)
- Migration scripts (for upgrades)
- All required tooling (oc, helm, jq)

## Directory Structure

```
installer/
├── Dockerfile                  # Container image definition
├── entrypoint.sh              # Main entrypoint (routes to install/upgrade/uninstall)
├── lib/
│   ├── prerequisites.sh       # Prerequisite validation
│   ├── deploy.sh              # Installation logic
│   ├── upgrade.sh             # Upgrade orchestration
│   ├── verify.sh              # Health checks and endpoint retrieval
│   └── cleanup.sh             # Uninstall logic
├── migrations/
│   └── 0.9.0-to-1.0.0.sh     # Example migration script
└── README.md                  # This file
```

## Building the Image

From the repository root:

```bash
docker build -t ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0 -f installer/Dockerfile .
```

**Note:** The build context is the repository root because it needs to copy the `peoplemesh-umbrella/` chart directory and `quickstart-manifest.yaml`.

## Testing Locally

### Test Prerequisites Check (No Installation)

```bash
docker run --rm \
  -e ACTION=verify \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```

### Test Installation

```bash
docker run --rm \
  -e ACTION=install \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -e INSTALL_MODE=demo \
  -e PARAM_OLLAMA_GPU_ENABLED=false \
  -e PARAM_DOCLING_GPU_ENABLED=false \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```

### Test Upgrade

```bash
docker run --rm \
  -e ACTION=upgrade \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -e SOURCE_VERSION=0.9.0 \
  -e TARGET_VERSION=1.0.0 \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```

### Test Uninstall

```bash
# Keep data
docker run --rm \
  -e ACTION=uninstall-keep-data \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0

# Delete all
docker run --rm \
  -e ACTION=uninstall-delete-all \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```

## Environment Variables

### Required for All Actions

| Variable | Description | Example |
|----------|-------------|---------|
| `ACTION` | Operation to perform | `verify`, `install`, `upgrade`, `uninstall-delete-all`, `uninstall-keep-data` |
| `TARGET_NAMESPACE` | Kubernetes namespace | `peoplemesh-quickstart` |

### Required for Install

| Variable | Description | Default |
|----------|-------------|---------|
| `INSTALL_MODE` | Deployment mode | `demo` or `production` |

### Required for Upgrade

| Variable | Description | Example |
|----------|-------------|---------|
| `SOURCE_VERSION` | Current version | `0.9.0` |
| `TARGET_VERSION` | Target version | `1.0.0` |

### Optional Configuration Parameters

All parameters from the manifest can be passed as `PARAM_*` environment variables:

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `PARAM_OLLAMA_GPU_ENABLED` | Enable GPU for Ollama | boolean | `false` |
| `PARAM_DOCLING_GPU_ENABLED` | Enable GPU for Docling | boolean | `false` |
| `PARAM_PEOPLEMESH_LLM_MODE` | LLM mode | `local` or `external` | `local` |
| `PARAM_PEOPLEMESH_LLM_EXTERNAL_APIKEY` | OpenAI API key | string | - |
| `PARAM_PEOPLEMESH_LLM_EXTERNAL_BASEURL` | OpenAI base URL | string | `https://api.openai.com/v1` |
| `PARAM_PEOPLEMESH_LLM_EXTERNAL_CHATMODEL` | OpenAI model | string | `gpt-4o-mini` |
| `PARAM_PEOPLEMESH_ORGANIZATION_NAME` | Organization name | string | - |
| `PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL` | Contact email | string | - |
| `PARAM_PEOPLEMESH_OIDC_GOOGLE_CLIENTID` | Google OAuth client ID | string | - |
| `PARAM_PEOPLEMESH_OIDC_GOOGLE_CLIENTSECRET` | Google OAuth secret | string | - |
| `PARAM_PEOPLEMESH_OIDC_MICROSOFT_CLIENTID` | Microsoft OAuth client ID | string | - |
| `PARAM_PEOPLEMESH_OIDC_MICROSOFT_CLIENTSECRET` | Microsoft OAuth secret | string | - |

**Note:** Secrets (passwords, API keys) are auto-generated if not provided. You typically don't need to pass them.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General failure (see stderr for details) |
| 2 | Prerequisites not met (see stderr for missing requirements JSON) |

## Output Format

All output is JSON to stdout for easy parsing by Navigator:

```json
{"status":"running","phase":"validating","message":"Checking prerequisites..."}
{"status":"running","phase":"deploying","message":"Installing Helm chart..."}
{"status":"running","phase":"verifying","message":"Waiting for pods..."}
{"status":"success","endpoints":[{"name":"main","url":"https://peoplemesh.apps.example.com"}]}
```

Error output (stderr):
```json
{"status":"error","message":"Helm installation failed"}
{"status":"prerequisites_failed","missing":["OpenShift 4.12+","Keycloak Operator"]}
```

## Publishing

```bash
# Build
docker build -t ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0 -f installer/Dockerfile .

# Test
docker run --rm -e ACTION=install -e TARGET_NAMESPACE=test ...

# Tag
docker tag ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0 \
           ghcr.io/rh-ai-quickstart/peoplemesh-installer:latest

# Push
docker push ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
docker push ghcr.io/rh-ai-quickstart/peoplemesh-installer:latest
```

## How Project Navigator Uses This

Navigator creates a Kubernetes Job with this image, passes parameters via environment variables, and monitors logs for JSON status updates. See `installer-job-example.yaml` for a complete example.

## Troubleshooting

### Prerequisite check fails

```bash
# Check what's missing
docker run --rm \
  -e ACTION=verify \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0 2>&1 | jq .

# Common issues:
# - Keycloak Operator not installed in target namespace
# - OpenShift version < 4.12
# - No storage class available
# - GPU requested but none available
```

### Helm installation fails

```bash
# Check Helm logs (job will preserve logs even after failure)
oc logs -n peoplemesh-test job/quickstart-install-peoplemesh

# Common issues:
# - Namespace doesn't exist (job should create it)
# - Insufficient permissions
# - Resource quotas exceeded
# - Image pull failures
```

### Health checks timeout

```bash
# Check pod status
oc get pods -n peoplemesh-test

# Check events
oc get events -n peoplemesh-test --sort-by='.lastTimestamp'

# Common issues:
# - Pods pending due to resource constraints
# - Image pull backoff
# - CrashLoopBackOff (check pod logs)
```

## Development

When developing the installer locally:

1. Make changes to scripts in `lib/`
2. Test with Docker (no need to rebuild for script changes if you mount the directory)
3. Rebuild the image once changes are tested
4. Push new version to registry

```bash
# Quick test without rebuilding (mount lib directory)
docker run --rm \
  -e ACTION=install \
  -e TARGET_NAMESPACE=test \
  -v $(pwd)/installer/lib:/installer/lib:ro \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```
