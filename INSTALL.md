# Peoplemesh Quickstart Installation Guide

## Prerequisites

- OpenShift cluster access with cluster-admin or namespace-admin permissions
- `oc` CLI tool installed and authenticated
- `helm` CLI tool installed (version 3.x)
- **Red Hat build of Keycloak Operator** installed in target namespace (see Quick Start in README.md)

## Secrets Management

**All secrets must be provided** for security. Generate them with `openssl rand -base64 24`.

The following secrets are required during installation:
- Keycloak database password
- PgVector database password
- Keycloak client secret
- Session encryption secret
- OAuth state secret
- Maintenance API key
- Test user password

The Keycloak issuer URL is auto-detected from your cluster - you don't need to provide it.

## Installation

### Create Namespace and Install Operator

**IMPORTANT:** The Keycloak Operator must be installed in the target namespace before deploying:

```bash
# Create the namespace
oc new-project peoplemesh-quickstart

# Install the Red Hat build of Keycloak Operator from OperatorHub
# 1. OpenShift Console → OperatorHub
# 2. Search for "Red Hat build of Keycloak"
# 3. Click "Install"
# 4. Installation Mode: "A specific namespace on the cluster"
# 5. Installed Namespace: Select "peoplemesh-quickstart"
# 6. Wait for "Succeeded" status
```

### Basic Installation (Recommended: Using install.sh)

The easiest way to install is using the provided script, which automatically generates all secrets:

```bash
./install.sh \
  --namespace peoplemesh-quickstart \
  --test-password YourSecurePassword
```

**Options:**
- `--namespace <name>` - Target namespace (required)
- `--test-password <password>` - Test user password (required)
- `--ollama-gpu <true|false>` - Enable GPU for Ollama (default: false)
- `--docling-gpu <true|false>` - Enable GPU for Docling (default: false)

**Example with GPU:**
```bash
./install.sh \
  --namespace peoplemesh-quickstart \
  --test-password YourSecurePassword \
  --ollama-gpu true \
  --docling-gpu true
```

### Manual Helm Installation

If you prefer to use Helm directly without the script:

```bash
# Generate secure secrets
KC_DB_PASSWORD=$(openssl rand -base64 24)
PG_DB_PASSWORD=$(openssl rand -base64 24)
CLIENT_SECRET=$(openssl rand -base64 24)
SESSION_SECRET=$(openssl rand -base64 24)
OAUTH_SECRET=$(openssl rand -base64 24)
MAINT_KEY=$(openssl rand -base64 24)

# Deploy
helm install peoplemesh . \
  --namespace peoplemesh-quickstart \
  --timeout 15m \
  --wait \
  --set keycloak.postgres.password="$KC_DB_PASSWORD" \
  --set pgvector.postgres.password="$PG_DB_PASSWORD" \
  --set keycloak.realm.client.clientSecret="$CLIENT_SECRET" \
  --set peoplemesh.security.sessionSecret="$SESSION_SECRET" \
  --set peoplemesh.security.oauthStateSecret="$OAUTH_SECRET" \
  --set peoplemesh.security.maintenanceApiKey="$MAINT_KEY" \
  --set keycloak.realm.testUser.password="YourSecurePassword"

# Clear secrets from memory
KC_DB_PASSWORD=""
PG_DB_PASSWORD=""
CLIENT_SECRET=""
SESSION_SECRET=""
OAUTH_SECRET=""
MAINT_KEY=""
```

**Note:** Secrets are generated locally (not exported to environment) for security. The Keycloak client secret is automatically synchronized to Peoplemesh via a post-install job. The Keycloak issuer URL is auto-detected from your cluster.


### What Each Secret Does

| Secret | Purpose | Used By |
|--------|---------|---------|
| **keycloak.postgres.password** | Keycloak's PostgreSQL database password | Keycloak → Postgres |
| **pgvector.postgres.password** | Peoplemesh's PostgreSQL database password | Peoplemesh → Postgres |
| **keycloak.realm.client.clientSecret** | OIDC client secret shared between Keycloak and Peoplemesh | Keycloak ↔ Peoplemesh |
| **peoplemesh.security.sessionSecret** | Encrypts browser session cookies | Peoplemesh |
| **peoplemesh.security.oauthStateSecret** | OAuth CSRF protection during login flow | Peoplemesh |
| **peoplemesh.security.maintenanceApiKey** | API key for maintenance endpoints | Peoplemesh |
| **keycloak.realm.testUser.password** | Password for demo test user | Keycloak Test User |

## Uninstallation

### Using uninstall.sh (Recommended)

The easiest way to uninstall:

```bash
./uninstall.sh --namespace peoplemesh-quickstart
```

This will:
- ✅ Remove the Helm release
- ✅ Remove all deployments, services, routes
- ✅ Remove all secrets
- ✅ Remove all PVCs (database data is deleted)
- ℹ️  Namespace remains (see script output for delete command)

### Manual Helm Uninstall

```bash
helm uninstall peoplemesh --namespace peoplemesh-quickstart
```

**Complete cleanup** - ready for a fresh install!

## Reinstallation

If you need to preserve secrets across reinstalls, save them before uninstalling and reuse them:

```bash
# Save your current secret values
export KC_DB_PASSWORD="..." 
export PG_DB_PASSWORD="..."
export CLIENT_SECRET="..."
export SESSION_SECRET="..."
export OAUTH_SECRET="..."
export MAINT_KEY="..."

# Reuse the same secret values
helm install peoplemesh . \
  --namespace peoplemesh-quickstart \
  --timeout 15m \
  --wait \
  --set keycloak.postgres.password="$KC_DB_PASSWORD" \
  --set pgvector.postgres.password="$PG_DB_PASSWORD" \
  --set keycloak.realm.client.clientSecret="$CLIENT_SECRET" \
  --set peoplemesh.security.sessionSecret="$SESSION_SECRET" \
  --set peoplemesh.security.oauthStateSecret="$OAUTH_SECRET" \
  --set peoplemesh.security.maintenanceApiKey="$MAINT_KEY" \
  --set keycloak.realm.testUser.password="YourSecurePassword"
```

**Why reuse the same secrets?**
- ✅ Browser sessions remain valid (no cookie clearing needed!)
- ✅ Consistent authentication experience

**Note:** Database data is still lost because PVCs are deleted on uninstall. This is intentional for the quickstart to ensure clean state.

## GPU Acceleration (Optional)

Enable GPU for **10-20x faster** LLM inference and document processing:

```bash
helm install peoplemesh . \
  --namespace peoplemesh-quickstart \
  --set ollama.gpu.enabled=true \
  --set docling.gpu.enabled=true \
  --set keycloak.postgres.password="..." \
  # ... other required secrets
```

**GPU Flags (both default to `false`):**
- `ollama.gpu.enabled=true` - GPU for LLM inference (search, CV structuring)
- `docling.gpu.enabled=true` - GPU for document parsing

**Requirements:**
- GPU-enabled cluster nodes (NVIDIA)
- NVIDIA GPU Operator installed
- At least 1 GPU available (both can share same GPU)

**Note:** Tolerations for GPU node taints (`g5-gpu`, `nvidia.com/gpu`) are pre-configured - no additional flags needed!

See [GPU-SETUP.md](GPU-SETUP.md) for detailed configuration and troubleshooting.

## Alternative: Use a Values File

Instead of long `--set` commands, create a `secrets.yaml` file:

```yaml
# secrets.yaml - DO NOT COMMIT THIS FILE!
keycloak:
  postgres:
    password: "your-keycloak-db-password-here"
  realm:
    client:
      clientSecret: "your-client-secret-here"

pgvector:
  postgres:
    password: "your-pgvector-db-password-here"

peoplemesh:
  security:
    sessionSecret: "your-session-secret-here-min-32-chars"
    oauthStateSecret: "your-oauth-secret-here-min-32-chars"
    maintenanceApiKey: "your-maintenance-key-here-min-32-chars"
```

Then install with:

```bash
helm install peoplemesh . \
  --namespace peoplemesh-quickstart \
  --timeout 15m \
  --wait \
  --values secrets.yaml
```

**Security Warning:** Add `secrets.yaml` to `.gitignore` to prevent committing secrets!

## Verification

After installation completes:

```bash
# Check all pods are running
oc get pods -n peoplemesh-quickstart

# Get the application URL
oc get route peoplemesh -n peoplemesh-quickstart -o jsonpath='{.spec.host}'

# Get Keycloak admin URL
oc get route keycloak -n peoplemesh-quickstart -o jsonpath='{.spec.host}'
```

### Test Login

1. Navigate to the Peoplemesh URL
2. Click "Sign in"
3. Choose "Continue with Keycloak"
4. Login with test user:
   - Username: `testuser`
   - Password: `changeme123`

### No Cookie Issues!

Because you're using the same `sessionSecret` across reinstalls:
- ✅ Sessions persist
- ✅ No need to clear cookies
- ✅ No "No OIDC provider configured" errors

## Troubleshooting

### "Required value" errors during install

**Cause:** One or more required secrets was not provided.

**Solution:** Ensure you provide all required secrets with `openssl rand -base64 24`. See the installation commands above for the complete list.

### Pods not starting

```bash
# Check pod status
oc get pods -n peoplemesh-quickstart

# Check specific pod logs
oc logs <pod-name> -n peoplemesh-quickstart

# Check events
oc get events -n peoplemesh-quickstart --sort-by='.lastTimestamp'
```

### Clean reinstall

```bash
# Uninstall everything
helm uninstall peoplemesh -n peoplemesh-quickstart

# PVCs are automatically deleted by the pre-install cleanup job
# But you can manually verify:
oc get pvc -n peoplemesh-quickstart

# Reinstall with same secrets
helm install peoplemesh . --namespace peoplemesh-quickstart ...
```

## Production Considerations

This quickstart is designed for demos and development. For production:

1. **Use a secrets manager** (HashiCorp Vault, External Secrets Operator)
2. **Disable PVC cleanup** - remove `peoplemesh-umbrella/templates/cleanup-*` files
3. **Use persistent storage** with backup/snapshot capabilities
4. **Change default test user password** or disable test user
5. **Configure proper CORS origins** (not `*`)
6. **Use production-grade OAuth provider**
7. **Enable TLS/mTLS** between services
8. **Set resource limits** appropriate for your workload
