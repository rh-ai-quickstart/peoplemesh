# Peoplemesh OpenShift Quickstart - Summary

## What This Project Provides

A production-ready Helm-based deployment of Peoplemesh on OpenShift with:

✅ **Keycloak Authentication** - No need for Google/Microsoft OAuth credentials  
✅ **Complete Stack** - Database, LLM, document processing, all included  
✅ **Single Command Deployment** - Deploy everything with one Helm command  
✅ **Persistent Storage** - Data survives pod restarts  
✅ **GPU Support** - Optional local vLLM deployment or external LLM  
✅ **Test User Included** - Login immediately after deployment  

## Quick Start (TL;DR)

```bash
# 1. Deploy Keycloak (separate namespace)
helm install keycloak charts/keycloak/ \
  --namespace samouelian-keycloak \
  --create-namespace \
  --set postgres.password=SecurePassword123 \
  --set realm.testUser.password=TestPassword123

# 2. Get Keycloak client secret
# - Login to Keycloak admin console
# - Create "peoplemesh" OIDC client in peoplemesh realm
# - Copy client secret

# 3. Deploy Peoplemesh (all components)
helm install peoplemesh peoplemesh-umbrella/ \
  --namespace peoplemesh \
  --create-namespace \
  --set pgvector.postgres.password=PostgresPassword123 \
  --set peoplemesh.security.oidc.keycloak.clientSecret="YOUR_CLIENT_SECRET" \
  --set peoplemesh.security.oidc.keycloak.issuerUrl="https://keycloak-samouelian-keycloak.apps.YOUR_CLUSTER/realms/peoplemesh"

# 4. Update Keycloak redirect URI with actual peoplemesh route
# 5. Login with testuser@example.com / TestPassword123
```

## Architecture Decision: Two Helm Charts

### Why Not One Chart?

**Keycloak** (separate chart in `samouelian-keycloak` namespace):
- Survives peoplemesh reinstalls
- Can be shared across multiple applications
- Operator-based deployment (CRDs in separate namespace)
- Persistent user data and realm configuration

**Peoplemesh Umbrella** (in `peoplemesh` namespace):
- Bundles: pgvector, docling, vllm, peoplemesh app
- Can be reinstalled without losing Keycloak users
- Clean separation of concerns

## Key Features

### 1. Declarative Keycloak Setup

The Keycloak chart uses `KeycloakRealmImport` to declaratively create:
- `peoplemesh` realm
- Test user: `testuser@example.com`
- Security policies (brute force protection, session timeouts)

No shell scripts needed - everything is Helm-managed.

### 2. Updated Peoplemesh Image

Uses `quay.io/rh-ai-quickstart/peoplemesh:latest` which includes:
- Keycloak OIDC support
- OIDC discovery (standards-compliant)
- Works with any OIDC provider

Source: `/Users/psamouel/Documents/peoplemesh/KEYCLOAK-IMPLEMENTATION.md`

### 3. Flexible LLM Deployment

**Option A: Local vLLM (GPU required)**
```yaml
vllm:
  enabled: true  # KServe InferenceService
peoplemesh:
  llm:
    mode: local
```

**Option B: External LLM (no GPU needed)**
```yaml
vllm:
  enabled: false
peoplemesh:
  llm:
    mode: external
    external:
      baseUrl: "https://api.openai.com/v1"
      apiKey: "sk-..."
      chatModel: "gpt-4o-mini"
```

### 4. Persistent Storage Everywhere

- PostgreSQL (pgvector): 20Gi PVC for peoplemesh data
- Keycloak PostgreSQL: 10Gi PVC for users/realms
- StatefulSets ensure data survives restarts

### 5. Post-Install Notes

Helm automatically prints:
- Application URL
- Admin credentials
- Test user credentials
- Next steps

## File Structure

```
peoplemesh-quickstart/
├── charts/
│   ├── keycloak/              # Separate Keycloak deployment
│   │   ├── templates/
│   │   │   ├── keycloak-cr.yaml           # Keycloak Operator CR
│   │   │   ├── postgres-statefulset.yaml  # Persistent DB
│   │   │   ├── realm-import.yaml          # Declarative realm + test user
│   │   │   ├── keycloak-route.yaml        # OpenShift Route
│   │   │   └── NOTES.txt                  # Post-install info
│   │   └── values.yaml
│   ├── pgvector/              # PostgreSQL with pgvector
│   ├── docling/               # Document processing
│   ├── vllm/                  # KServe vLLM inference
│   └── peoplemesh/            # Main application
│       ├── templates/
│       │   ├── deployment.yaml
│       │   ├── secrets.yaml   # Keycloak client secret
│       │   └── route.yaml
│       └── values.yaml        # Keycloak OIDC config
├── peoplemesh-umbrella/       # Umbrella chart
│   ├── Chart.yaml             # Dependencies
│   ├── values.yaml            # Complete config
│   └── templates/
│       └── NOTES.txt          # Deployment summary
├── examples/
│   ├── values-openshift.yaml  # Example: full OpenShift
│   └── values-external-llm.yaml  # Example: no GPU
├── DEPLOYMENT.md              # Complete deployment guide
└── QUICKSTART-SUMMARY.md      # This file
```

## Helm Chart Dependencies

The umbrella chart (`peoplemesh-umbrella`) references subchart via `file://` dependencies:

```yaml
dependencies:
  - name: pgvector
    version: 0.1.0
    repository: file://../charts/pgvector
  - name: docling
    version: 0.1.0
    repository: file://../charts/docling
  - name: vllm
    version: 0.1.0
    repository: file://../charts/vllm
    condition: vllm.enabled
  - name: peoplemesh
    version: 0.1.0
    repository: file://../charts/peoplemesh
```

Update dependencies:
```bash
cd peoplemesh-umbrella
helm dependency update
```

## Comparison with Peoplemesh Source Chart

The peoplemesh source repo (`/Users/psamouel/Documents/peoplemesh/tools/helm`) has its own chart, but:

| Feature | Source Chart | Quickstart Charts |
|---------|-------------|-------------------|
| Target | Developer deployment | Production reference |
| Keycloak | Not included | Full operator-based deployment |
| Namespace | Single namespace | Multi-namespace (Keycloak separate) |
| LLM | Ollama | vLLM with KServe |
| Storage | Optional | Persistent by default |
| OIDC | Manual setup | Pre-configured realm + test user |
| Documentation | Basic | Complete guides |

**Recommendation**: Use this quickstart for production-ready deployments.

## Environment Variables

The peoplemesh chart now supports:

```bash
# Keycloak OIDC
OIDC_KEYCLOAK_CLIENT_ID=peoplemesh
OIDC_KEYCLOAK_CLIENT_SECRET=<from-helm-values>
OIDC_KEYCLOAK_ISSUER_URL=https://keycloak.../realms/peoplemesh

# Disable other providers
OIDC_GOOGLE_CLIENT_ID=none
OIDC_GOOGLE_CLIENT_SECRET=none
OIDC_MICROSOFT_CLIENT_ID=none
OIDC_MICROSOFT_CLIENT_SECRET=none
```

## Deployment Workflow

```
1. Deploy Keycloak
   └─> Creates: Keycloak server + PostgreSQL + peoplemesh realm + test user
   └─> Returns: Admin credentials, test user credentials

2. Create OIDC Client
   └─> Keycloak admin console: Create peoplemesh client
   └─> Copy: Client secret

3. Deploy Peoplemesh
   └─> Creates: pgvector + docling + vllm + peoplemesh app
   └─> Uses: Keycloak for authentication
   └─> Returns: Application URL

4. Update Redirect URI
   └─> Keycloak admin console: Add actual peoplemesh route
   └─> Enables: OAuth callback

5. Login & Use
   └─> Browser: Navigate to peoplemesh URL
   └─> Login: testuser@example.com / TestPassword123
   └─> Success: Full access to peoplemesh
```

## Test User Details

Created automatically by Keycloak realm import:

- **Username**: `testuser@example.com`
- **Email**: `testuser@example.com`
- **Password**: Configurable via `realm.testUser.password` (default: `changeme123`)
- **Email Verified**: Yes
- **Enabled**: Yes

This user is created declaratively - no API calls or shell scripts needed.

## Security Notes

### Secrets Management

All secrets are parameterized via Helm values:

```yaml
# Keycloak chart
postgres.password: "..."           # Keycloak DB password
realm.testUser.password: "..."     # Test user password

# Peoplemesh umbrella
pgvector.postgres.password: "..."  # Peoplemesh DB password
peoplemesh.security.oidc.keycloak.clientSecret: "..."  # OIDC client secret
```

### Production Checklist

Before production deployment:

- [ ] Change all passwords from defaults
- [ ] Set `corsOrigins` to specific domains (not `*`)
- [ ] Disable test user creation (`realm.testUser.enabled: false`)
- [ ] Configure proper TLS certificates
- [ ] Set resource limits based on load testing
- [ ] Configure backup strategy for PostgreSQL PVCs
- [ ] Review Keycloak security policies
- [ ] Enable Keycloak authentication on vLLM endpoint

## Troubleshooting

See [DEPLOYMENT.md](DEPLOYMENT.md#troubleshooting) for common issues.

Quick checks:

```bash
# All pods running?
oc get pods -n peoplemesh
oc get pods -n samouelian-keycloak

# Keycloak ready?
oc get keycloak keycloak -n samouelian-keycloak

# Peoplemesh healthy?
curl https://$(oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}')/q/health

# OIDC configured?
curl https://$(oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}')/api/v1/info | jq '.authProviders'
```

## Related Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Complete step-by-step deployment guide
- **[KEYCLOAK-DEPLOYMENT-SUMMARY.md](KEYCLOAK-DEPLOYMENT-SUMMARY.md)** - Keycloak chart details
- **[docs/keycloak-setup.md](docs/keycloak-setup.md)** - Keycloak configuration guide
- **[charts/keycloak/README.md](charts/keycloak/README.md)** - Keycloak chart reference
- **[examples/](examples/)** - Example values files

## Credits

- **Peoplemesh**: https://github.com/frapax/peoplemesh
- **Keycloak**: https://www.keycloak.org
- **Red Hat build of Keycloak Operator**: https://access.redhat.com/products/red-hat-build-of-keycloak
- **OpenShift AI / KServe**: https://ai-on-openshift.io

## License

This quickstart inherits the license from the Peoplemesh project.

