# Peoplemesh OpenShift Quickstart - Deployment Guide

This guide walks you through deploying the complete Peoplemesh stack on OpenShift with Keycloak authentication.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Namespace: samouelian-keycloak                              │
│ ┌─────────────────────┐   ┌─────────────────────┐          │
│ │ Keycloak Server     │   │ PostgreSQL          │          │
│ │ (Operator-based)    │──▶│ (Persistent)        │          │
│ └─────────────────────┘   └─────────────────────┘          │
│         │                                                    │
│         │ Provides:                                         │
│         │ - peoplemesh realm                                 │
│         │ - peoplemesh OIDC client                          │
│         │ - Test user: testuser@example.com                 │
└─────────┼────────────────────────────────────────────────────┘
          │ OIDC Authentication
          ▼
┌─────────────────────────────────────────────────────────────┐
│ Namespace: peoplemesh                                        │
│ ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│ │ Peoplemesh App  │  │ PostgreSQL      │  │ Docling      │ │
│ │ (Quarkus)       │─▶│ + pgvector      │  │ (Document    │ │
│ │                 │  │                 │  │ Processing)  │ │
│ └────────┬────────┘  └─────────────────┘  └──────────────┘ │
│          │                                                   │
│          │                                                   │
│          ▼                                                   │
│ ┌─────────────────────┐                                     │
│ │ vLLM Inference      │                                     │
│ │ (KServe)            │                                     │
│ │ Qwen2.5-7B-AWQ      │                                     │
│ └─────────────────────┘                                     │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. OpenShift Cluster

- OpenShift 4.12+ cluster
- Cluster admin access or appropriate permissions
- Sufficient resources:
  - **With GPU (local vLLM)**: 8 CPU, 32GB RAM, 1 GPU
  - **Without GPU (external LLM)**: 4 CPU, 16GB RAM

### 2. Keycloak Operator

The Red Hat build of Keycloak Operator must be installed:

```bash
# Check if operator is installed
oc get csv -n samouelian-keycloak | grep rhbk-operator
```

If not installed:
1. OpenShift Console → Operators → OperatorHub
2. Search for "Red Hat build of Keycloak"
3. Install to `samouelian-keycloak` namespace
4. Select the v24 channel

### 3. Tools Required

- `helm` 3.x
- `oc` CLI (logged into cluster)
- `git` (to clone this repository)

## Deployment Steps

### Step 1: Clone the Repository

```bash
git clone https://github.com/rh-ai-quickstart/peoplemesh.git
cd peoplemesh
```

### Step 2: Deploy Keycloak (Separate Namespace)

```bash
# Create namespace for Keycloak
oc create namespace samouelian-keycloak

# Deploy Keycloak with Helm
helm install keycloak charts/keycloak/ \
  --namespace samouelian-keycloak \
  --set postgres.password=MySecureKeycloakPassword \
  --set realm.testUser.password=TestPassword123
```

**What this deploys:**
- Keycloak server (Operator-managed)
- PostgreSQL database with persistent storage (10Gi)
- `peoplemesh` realm
- Test user: `testuser@example.com` / `TestPassword123`

**Wait for Keycloak to be ready:**

```bash
# Watch pods
oc get pods -n samouelian-keycloak -w

# Check Keycloak status
oc get keycloak keycloak -n samouelian-keycloak
```

Expected output:
```
NAME       READY   ...
keycloak   true    ...
```

### Step 3: Configure Keycloak Client

Get the Keycloak admin credentials:

```bash
# Get admin credentials
echo "Username: $(oc get secret keycloak-initial-admin -n samouelian-keycloak -o jsonpath='{.data.username}' | base64 -d)"
echo "Password: $(oc get secret keycloak-initial-admin -n samouelian-keycloak -o jsonpath='{.data.password}' | base64 -d)"

# Get Keycloak URL
KEYCLOAK_URL="https://$(oc get route keycloak -n samouelian-keycloak -o jsonpath='{.spec.host}')"
echo "Keycloak Admin Console: $KEYCLOAK_URL/admin"
```

**Create OIDC Client in Keycloak:**

1. Open the Keycloak Admin Console in your browser
2. Login with the admin credentials
3. Switch to the **peoplemesh** realm (top-left dropdown)
4. Navigate to **Clients** → **Create client**
5. Configure:
   - Client type: `OpenID Connect`
   - Client ID: `peoplemesh`
   - Click **Next**
6. Capability config:
   - Client authentication: `On`
   - Authorization: `Off`
   - Standard flow: ✓ **Enabled**
   - Direct access grants: **Disabled**
   - Click **Next**
7. Login settings:
   - Root URL: (leave blank for now)
   - Valid redirect URIs: `https://*` (we'll update this after peoplemesh deploys)
   - Web origins: `https://*`
   - Click **Save**
8. Go to the **Credentials** tab
9. **Copy the Client Secret** - you'll need this for the next step

### Step 4: Deploy Peoplemesh (with all dependencies)

Create a custom values file with your Keycloak configuration:

```bash
# Get the Keycloak issuer URL
KEYCLOAK_ISSUER_URL="https://$(oc get route keycloak -n samouelian-keycloak -o jsonpath='{.spec.host}')/realms/peoplemesh"

# Create values file (replace YOUR_CLIENT_SECRET with the secret from step 3)
cat > my-peoplemesh-values.yaml <<EOF
# Peoplemesh with Keycloak authentication

pgvector:
  enabled: true
  postgres:
    password: MySecurePostgresPassword

docling:
  enabled: true

vllm:
  enabled: true  # Set to false if using external LLM

peoplemesh:
  peoplemesh:
    image:
      repository: quay.io/rh-ai-quickstart/peoplemesh
      tag: latest
    route:
      enabled: true

  database:
    host: pgvector-service
    port: 5432
    name: peoplemesh
    user: peoplemesh
    existingSecret: pgvector-database
    passwordKey: DATABASE_PASSWORD

  llm:
    mode: local  # or "external" for external LLM

  security:
    oidc:
      keycloak:
        clientId: "peoplemesh"
        clientSecret: "YOUR_CLIENT_SECRET"  # Replace with actual secret
        issuerUrl: "${KEYCLOAK_ISSUER_URL}"
      google:
        clientId: "none"
        clientSecret: "none"
      microsoft:
        clientId: "none"
        clientSecret: "none"

  organization:
    name: "My Organization"
    contactEmail: "admin@example.com"
EOF
```

Deploy with Helm:

```bash
# Create namespace
oc create namespace peoplemesh

# Deploy the umbrella chart
helm install peoplemesh peoplemesh-umbrella/ \
  --namespace peoplemesh \
  --values my-peoplemesh-values.yaml \
  --timeout 10m
```

**What this deploys:**
- PostgreSQL with pgvector (20Gi persistent storage)
- Docling document processing service
- vLLM inference server with Qwen2.5-7B model (if enabled)
- Peoplemesh application connected to Keycloak

### Step 5: Update Keycloak Redirect URI

Once peoplemesh is deployed, update the Keycloak client with the actual route:

```bash
# Get peoplemesh route
PEOPLEMESH_URL="https://$(oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}')"
echo "Peoplemesh URL: $PEOPLEMESH_URL"
echo "Callback URL: $PEOPLEMESH_URL/api/v1/auth/callback/keycloak"
```

In Keycloak Admin Console:
1. Go to **Clients** → **peoplemesh**
2. Update **Valid redirect URIs**: `https://<your-peoplemesh-route>/api/v1/auth/callback/keycloak`
3. Update **Web origins**: `https://<your-peoplemesh-route>`
4. Click **Save**

### Step 6: Verify Deployment

```bash
# Check all pods are running
oc get pods -n peoplemesh

# Check application health
curl https://$(oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}')/q/health/ready

# Check OIDC providers
curl https://$(oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}')/api/v1/info | jq '.authProviders'
```

Expected output:
```json
{
  "loginProviders": ["keycloak"],
  "profileImportProviders": ["github"]
}
```

### Step 7: Login to Peoplemesh

1. Open your browser to the peoplemesh URL
2. Click **Sign in**
3. Choose **Continue with Keycloak**
4. Login with test credentials:
   - Username: `testuser@example.com`
   - Password: `TestPassword123` (or whatever you set)
5. You should be redirected back to peoplemesh and logged in

## Configuration Options

### Use External LLM Instead of Local vLLM

If you don't have GPU resources, use an external LLM:

```yaml
vllm:
  enabled: false  # Disable local vLLM

peoplemesh:
  llm:
    mode: external
    external:
      baseUrl: "https://api.openai.com/v1"
      apiKey: "sk-your-api-key"
      chatModel: "gpt-4o-mini"
      embeddingModel: "text-embedding-3-small"
      embeddingDimension: 1536
```

### Customize Resource Limits

Adjust based on your cluster capacity:

```yaml
peoplemesh:
  peoplemesh:
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi
      limits:
        cpu: 4000m
        memory: 8Gi
```

### Change Storage Sizes

```yaml
pgvector:
  postgres:
    persistence:
      size: 50Gi  # Increase for larger datasets

postgres:  # Keycloak database
  persistence:
    size: 20Gi
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
oc get pods -n peoplemesh
oc describe pod <pod-name> -n peoplemesh

# Check logs
oc logs -f deployment/peoplemesh -n peoplemesh
```

### Keycloak Login Not Working

```bash
# Verify Keycloak route is accessible
curl -k https://$(oc get route keycloak -n samouelian-keycloak -o jsonpath='{.spec.host}')/realms/peoplemesh/.well-known/openid-configuration

# Check peoplemesh environment variables
oc get deployment peoplemesh -n peoplemesh -o yaml | grep OIDC_KEYCLOAK
```

### Database Connection Issues

```bash
# Test PostgreSQL connection
oc exec -it deployment/peoplemesh -n peoplemesh -- \
  psql -h pgvector-service -U peoplemesh -d peoplemesh -c "SELECT version();"
```

### vLLM Not Ready

```bash
# Check InferenceService status
oc get inferenceservice peoplemesh-llm -n peoplemesh

# Check predictor pod logs
oc logs -l serving.kserve.io/inferenceservice=peoplemesh-llm -n peoplemesh
```

## Cleanup

### Remove Peoplemesh Deployment

```bash
# Uninstall Helm release
helm uninstall peoplemesh -n peoplemesh

# Delete namespace (removes all resources including PVCs)
oc delete namespace peoplemesh
```

### Remove Keycloak Deployment

```bash
# Uninstall Keycloak
helm uninstall keycloak -n samouelian-keycloak

# Delete namespace (WARNING: removes all data)
oc delete namespace samouelian-keycloak
```

## Next Steps

- Configure additional OIDC providers (Google, Microsoft)
- Import user profiles from GitHub
- Customize the peoplemesh realm settings
- Set up backups for PostgreSQL databases
- Configure monitoring and logging

## Support

For issues and questions:
- GitHub Issues: https://github.com/rh-ai-quickstart/peoplemesh/issues
- Documentation: See `/docs` directory in this repository

