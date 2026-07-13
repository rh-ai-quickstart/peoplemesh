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
├── entrypoint.sh              # Main entrypoint (routes to validate/install/upgrade/uninstall)
├── lib/
│   ├── prerequisites.sh       # Prerequisite validation (used by validate action)
│   ├── deploy.sh              # Installation logic
│   ├── upgrade.sh             # Upgrade orchestration
│   ├── status.sh              # Deployment status checks and endpoint retrieval
│   └── cleanup.sh             # Uninstall logic
├── migrations/
│   └── 0.9.0-to-1.0.0.sh     # Example migration script
└── README.md                  # This file
```

## Building the Image

From the repository root:

```bash
podman build -t quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0 -f installer/Dockerfile .
```

**Note:** The build context is the repository root because it needs to copy the `peoplemesh-umbrella/` chart directory and `quickstart-manifest.yaml`.

## Testing

The installer can be tested in two ways:

1. **Local testing** - Run the installer container locally via podman (uses QEMU emulation on Apple Silicon)
2. **Cluster testing** - Deploy the installer as a Kubernetes Job on the target cluster (native execution)

### Local Testing (via podman)

#### Validate Prerequisites

```bash
podman run --rm \
  -e ACTION=CHECK_PRE_REQS \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```

#### Check Deployment Status

```bash
podman run --rm \
  -e ACTION=STATUS \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```

#### Installation

```bash
# Minimal installation - secrets auto-generated
podman run --rm \
  -e ACTION=INSTALL \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -e INSTALL_MODE=demo \
  -e PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD="YourSecurePassword" \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0

# With GPU acceleration
podman run --rm \
  -e ACTION=INSTALL \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -e INSTALL_MODE=demo \
  -e PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD="YourSecurePassword" \
  -e PARAM_OLLAMA_GPU_ENABLED=true \
  -e PARAM_DOCLING_GPU_ENABLED=true \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0

# With organization customization
podman run --rm \
  -e ACTION=INSTALL \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -e INSTALL_MODE=demo \
  -e PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD="YourSecurePassword" \
  -e PARAM_PEOPLEMESH_ORGANIZATION_NAME="My Company" \
  -e PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL="contact@mycompany.com" \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```

#### Uninstall

```bash
# Keep data (preserves PVCs for reinstall)
podman run --rm \
  -e ACTION=UNINSTALL_KEEP_DATA \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0

# Delete all (complete cleanup)
podman run --rm \
  -e ACTION=UNINSTALL_DELETE_ALL \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```

### Cluster Testing (via Kubernetes Job)

For testing in the actual cluster environment where Navigator will run the installer, use the `deploy_job` modifier:

```bash
# Check prerequisites on cluster
./installer/build.sh deploy_job check_pre_reqs <namespace>

# Check deployment status on cluster
./installer/build.sh deploy_job status <namespace>

# Deploy installation on cluster
./installer/build.sh deploy_job install <namespace>

# Uninstall (keep data) on cluster
./installer/build.sh deploy_job uninstall_keep_data <namespace>

# Uninstall (delete all) on cluster
./installer/build.sh deploy_job uninstall_delete_all <namespace>
```

**How it works:**
1. Builds the installer image and pushes to `quay.io/rh-ai-quickstart`
2. Creates a Kubernetes Job in the target namespace
3. Job pulls the image from quay.io (`imagePullPolicy: Always`)
4. Streams the logs from the Job
5. Tests in native cluster execution (no emulation)

**When to use cluster testing:**
- Testing on non-x86_64 development machines (validates native execution)
- Verifying RBAC permissions work correctly
- Testing the exact environment Navigator uses
- Debugging cluster-specific issues
- Testing all installer actions (not just install)

**Note:** The Job uses `imagePullPolicy: Always` to pull from quay.io, so you must run `./installer/build.sh push` first to make the image available to the cluster.

## Actions

The installer supports the following actions (set via `ACTION` environment variable):

| Action | Description | When to Use |
|--------|-------------|-------------|
| `CHECK_PRE_REQS` | Checks prerequisites without installing | Before installation to verify cluster readiness |
| `STATUS` | Checks deployment condition (installed/uninstalled state) | Monitor deployment health or verify clean uninstall |
| `INSTALL` | Installs the quickstart (includes CHECK_PRE_REQS step) | Deploy Peoplemesh to cluster |
| `UNINSTALL_DELETE_ALL` | Removes all components and data (includes STATUS step) | Complete cleanup - deletes databases, secrets, PVCs |
| `UNINSTALL_KEEP_DATA` | Removes runtime but keeps data volumes (includes STATUS step) | Preserve data for reinstall |
| `UPGRADE` | Upgrades the quickstart to a newer version | Migrate from one version to another |

**Key Differences:**

- **CHECK_PRE_REQS vs STATUS**: 
  - `CHECK_PRE_REQS` checks if prerequisites are met before installation
  - `STATUS` checks the current deployment state (works for both installed and uninstalled)

- **STATUS use cases**:
  - Monitor deployment health when status HTTP endpoint is unavailable
  - Verify orphaned resources after uninstall
  - Quick deployment state check without waiting/retrying

- **Uninstall actions**:
  - Both automatically run `STATUS` after cleanup to confirm state
  - `UNINSTALL_DELETE_ALL`: Complete cleanup (ready for fresh install)
  - `UNINSTALL_KEEP_DATA`: Preserves databases for reinstall (same secrets needed)

## Environment Variables

### Required for All Actions

| Variable | Description | Example |
|----------|-------------|---------|
| `ACTION` | Operation to perform | `CHECK_PRE_REQS`, `STATUS`, `INSTALL`, `UNINSTALL_DELETE_ALL`, `UNINSTALL_KEEP_DATA`, `UPGRADE` |
| `TARGET_NAMESPACE` | Kubernetes namespace | `peoplemesh-quickstart` |

### Required for Install

| Variable | Description | Default |
|----------|-------------|---------|
| `INSTALL_MODE` | Deployment mode | `demo` or `production` |
| `PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD` | Test user password | Required - secure password for test user login |

**Note:** All other secrets (database passwords, client secrets, encryption keys) are automatically generated by the installer. You only need to provide the test user password.

### Required for Upgrade

| Variable | Description | Example |
|----------|-------------|---------|
| `SOURCE_VERSION` | Current version | `0.9.0` |
| `TARGET_VERSION` | Target version | `1.0.0` |

### Optional Configuration Parameters

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `PARAM_OLLAMA_GPU_ENABLED` | Enable GPU for Ollama | boolean | `false` |
| `PARAM_DOCLING_GPU_ENABLED` | Enable GPU for Docling | boolean | `false` |
| `PARAM_PEOPLEMESH_ORGANIZATION_NAME` | Organization name | string | - |
| `PARAM_PEOPLEMESH_ORGANIZATION_CONTACTEMAIL` | Contact email | string | - |

**Note:** All database passwords, encryption keys, and client secrets are automatically generated by the installer. Only the test user password and optional configuration above need to be provided.

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
podman build -t quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0 -f installer/Dockerfile .

# Test
podman run --rm -e ACTION=install -e TARGET_NAMESPACE=test ...

# Tag
podman tag quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0 \
           quay.io/rh-ai-quickstart/peoplemesh-installer:latest

# Push
podman push quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
podman push quay.io/rh-ai-quickstart/peoplemesh-installer:latest
```

## How Project Navigator Uses This

Navigator creates a Kubernetes Job with this image, passes parameters via environment variables, and monitors logs for JSON status updates. See `installer-job-example.yaml` for a complete example.

## Troubleshooting

### Prerequisite validation fails

```bash
# Check what's missing
podman run --rm \
  -e ACTION=validate \
  -e TARGET_NAMESPACE=peoplemesh-test \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0 2>&1 | jq .

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
podman run --rm \
  -e ACTION=install \
  -e TARGET_NAMESPACE=test \
  -v $(pwd)/installer/lib:/installer/lib:ro \
  -v $HOME/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  quay.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
```
