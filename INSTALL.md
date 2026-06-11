# Peoplemesh Quickstart Installation Guide

## Prerequisites

- OpenShift cluster access with cluster-admin or namespace-admin permissions
- `oc` CLI tool installed and authenticated
- `helm` CLI tool installed (version 3.x)

## Required Secrets

This installation requires **7 secrets** to be provided explicitly. No secrets are auto-generated or hardcoded.

### Generate All Secrets at Once

```bash
# Generate all required secrets
export KC_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
export PG_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
export CLIENT_SECRET=$(openssl rand -hex 32)
export SESSION_SECRET=$(openssl rand -hex 32)
export OAUTH_SECRET=$(openssl rand -hex 32)
export MAINT_KEY=$(openssl rand -hex 32)
export TEST_USER_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

# Display for reference (save these if you need to reinstall!)
cat <<EOF

================================
Generated Secrets (save these!)
================================
Keycloak DB Password:    $KC_DB_PASSWORD
Pgvector DB Password:    $PG_DB_PASSWORD
Keycloak Client Secret:  $CLIENT_SECRET
Session Secret:          $SESSION_SECRET
OAuth State Secret:      $OAUTH_SECRET
Maintenance API Key:     $MAINT_KEY
Test User Password:      $TEST_USER_PASSWORD
================================

EOF
```

## Installation

### Create Namespace

```bash
oc new-project peoplemesh-quickstart
```

### Install with Helm

```bash
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
  --set keycloak.realm.testUser.password="$TEST_USER_PASSWORD"
```

### What Each Secret Does

| Secret | Purpose | Used By |
|--------|---------|---------|
| **keycloak.postgres.password** | Keycloak's PostgreSQL database password | Keycloak → Postgres |
| **pgvector.postgres.password** | Peoplemesh's PostgreSQL database password | Peoplemesh → Postgres |
| **keycloak.realm.client.clientSecret** | OIDC client secret shared between Keycloak and Peoplemesh | Keycloak ↔ Peoplemesh |
| **peoplemesh.security.sessionSecret** | Encrypts browser session cookies (prevents cookie issue!) | Peoplemesh |
| **peoplemesh.security.oauthStateSecret** | OAuth CSRF protection during login flow | Peoplemesh |
| **peoplemesh.security.maintenanceApiKey** | API key for maintenance endpoints | Peoplemesh |
| **keycloak.realm.testUser.password** | Password for demo test user (username: testuser) | Keycloak Test User |

## Uninstallation

The quickstart includes automatic cleanup of PVCs (database volumes):

```bash
helm uninstall peoplemesh --namespace peoplemesh-quickstart
```

This will:
- ✅ Remove all deployments, services, routes
- ✅ Remove all secrets
- ✅ Remove all PVCs (database data is deleted)

**Complete cleanup** - ready for a fresh install!

## Reinstallation

To reinstall, use **the exact same secrets** as the original installation:

```bash
# Reuse the same secret values you generated earlier
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
  --set keycloak.realm.testUser.password="$TEST_USER_PASSWORD"
```

**Why reuse the same secrets?**
- ✅ Browser sessions remain valid (no cookie clearing needed!)
- ✅ No "No OIDC provider configured" errors
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

**Cause:** One or more secrets not provided.

**Solution:** Ensure all 6 secrets are provided via `--set` or values file.

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
