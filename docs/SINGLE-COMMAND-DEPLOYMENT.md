# Peoplemesh Single-Command Deployment

Deploy the complete Peoplemesh stack with Keycloak authentication using **one Helm command**. No manual configuration steps required!

## What Gets Deployed

All in a **single namespace**:
- ✅ Keycloak server (with Operator)
- ✅ Keycloak PostgreSQL database (persistent)
- ✅ Peoplemesh realm (pre-configured)
- ✅ Peoplemesh OIDC client (auto-configured)
- ✅ Test user (ready to login)
- ✅ PostgreSQL with pgvector (for peoplemesh data)
- ✅ Docling (document processing)
- ✅ vLLM inference server (optional)
- ✅ Peoplemesh application

## Prerequisites

### 1. OpenShift Cluster
- OpenShift 4.12+
- Cluster admin or appropriate permissions
- Resources: 8 CPU, 32GB RAM minimum (with GPU)

### 2. Keycloak Operator Installed

The Red Hat build of Keycloak Operator must be available on the cluster. It can be installed in **any namespace** (doesn't have to be the same as peoplemesh).

Check if installed:
```bash
oc get csv -A | grep rhbk-operator
```

If not installed:
1. OpenShift Console → Operators → OperatorHub
2. Search "Red Hat build of Keycloak"
3. Install (all namespaces or specific namespace)
4. Select v24 channel

### 3. Tools
- `helm` 3.x
- `oc` CLI (logged into cluster)

## One-Command Deployment

```bash
# Clone the repository
git clone https://github.com/rh-ai-quickstart/peoplemesh.git
cd peoplemesh

# Build Helm dependencies
cd peoplemesh-umbrella
helm dependency build
cd ..

# Deploy everything with one command
helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=SecurePostgresPassword \
  --set keycloak.postgres.password=SecureKeycloakPassword \
  --set keycloak.realm.testUser.password=TestUserPassword123 \
  --timeout 15m \
  --wait
```

**That's it!** Everything is deployed and configured.

## What Happens Automatically

### 1. Keycloak Configuration
- ✅ Keycloak server deployed via Operator
- ✅ PostgreSQL database created (10Gi persistent storage)
- ✅ `peoplemesh` realm imported
- ✅ OIDC client created with:
  - Client ID: `peoplemesh`
  - Client secret: **Auto-generated** and shared
  - Redirect URIs: **Auto-detected** from cluster domain
  - Web origins: **Auto-configured**

### 2. Test User
- ✅ Username: `testuser@example.com`
- ✅ Password: `TestUserPassword123` (or whatever you set)
- ✅ Email verified: Yes
- ✅ Ready to login immediately

### 3. Peoplemesh Application
- ✅ Connected to Keycloak automatically
- ✅ Client secret shared from Keycloak
- ✅ Issuer URL auto-detected
- ✅ Redirect URIs pre-configured
- ✅ Database seeded with test data

### 4. No Manual Steps
- ❌ No Keycloak admin console login required
- ❌ No client creation in Keycloak UI
- ❌ No secret copying between systems
- ❌ No URL configuration
- ❌ No redirect URI updates

## Verify Deployment

```bash
# Check all pods are running
oc get pods -n peoplemesh

# Should see:
# - keycloak-postgres-db-0 (Running)
# - keycloak-0 (Running)
# - pgvector-0 (Running)
# - docling-* (Running)
# - peoplemesh-llm-* (Running, if vllm enabled)
# - peoplemesh-* (Running)
```

Wait for all pods to be `Running` and `Ready`.

## Access Peoplemesh

```bash
# Get the application URL
PEOPLEMESH_URL="https://$(oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}')"
echo "Peoplemesh: $PEOPLEMESH_URL"

# Open in browser and login with:
# Username: testuser@example.com
# Password: TestUserPassword123 (or whatever you set)
```

## Configuration Options

### Use External LLM (No GPU Required)

```bash
helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=SecurePostgresPassword \
  --set keycloak.postgres.password=SecureKeycloakPassword \
  --set vllm.enabled=false \
  --set peoplemesh.llm.mode=external \
  --set peoplemesh.llm.external.baseUrl="https://api.openai.com/v1" \
  --set peoplemesh.llm.external.apiKey="sk-your-api-key" \
  --set peoplemesh.llm.external.chatModel="gpt-4o-mini" \
  --set peoplemesh.llm.external.embeddingModel="text-embedding-3-small" \
  --set peoplemesh.llm.external.embeddingDimension=1536 \
  --timeout 15m \
  --wait
```

### Custom Organization Details

```bash
helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=SecurePostgresPassword \
  --set keycloak.postgres.password=SecureKeycloakPassword \
  --set peoplemesh.organization.name="Acme Corporation" \
  --set peoplemesh.organization.contactEmail="admin@acme.com" \
  --set peoplemesh.organization.dpoEmail="privacy@acme.com" \
  --timeout 15m \
  --wait
```

### Create Multiple Test Users

Create a custom values file:

```yaml
# my-values.yaml
keycloak:
  realm:
    testUser:
      enabled: true
      username: admin-user
      email: admin@example.com
      password: AdminPassword123

pgvector:
  postgres:
    password: SecurePostgresPassword

keycloak:
  postgres:
    password: SecureKeycloakPassword
```

Deploy:
```bash
helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace peoplemesh \
  -f my-values.yaml \
  --timeout 15m \
  --wait
```

## How It Works

### Auto-Generated Client Secret

1. Umbrella chart creates `keycloak-client-secret` Secret on first install
2. Secret contains randomly generated 32-character client secret
3. Keycloak realm import references this secret for OIDC client
4. Peoplemesh application references the same secret
5. Both components share the same secret automatically

### Auto-Detected Cluster Domain

The deployment automatically detects your cluster domain by looking up the OpenShift console route:

```yaml
# In _helpers.tpl
Get console route: console-openshift-console.apps.cluster.example.com
Extract domain: apps.cluster.example.com
Use for routes: https://keycloak-peoplemesh.apps.cluster.example.com
                https://peoplemesh-peoplemesh.apps.cluster.example.com
```

### Auto-Configured Redirect URIs

Keycloak OIDC client is created with wildcard redirect URIs that match any namespace on the cluster:

```yaml
redirectUris:
  - "https://peoplemesh-*.apps.*/api/v1/auth/callback/keycloak"
  - "http://localhost:8080/api/v1/auth/callback/keycloak"
```

This works for:
- Any namespace name
- Any cluster domain
- Local development

## Architecture

```
Namespace: peoplemesh
┌────────────────────────────────────────────────────────────────┐
│                                                                 │
│  ┌──────────────────┐     ┌──────────────────┐                │
│  │ Keycloak Server  │────▶│ Keycloak         │                │
│  │ (Operator)       │     │ PostgreSQL       │                │
│  └────────┬─────────┘     └──────────────────┘                │
│           │                                                     │
│           │ OIDC (shared secret)                               │
│           ▼                                                     │
│  ┌──────────────────┐     ┌──────────────────┐  ┌──────────┐ │
│  │ Peoplemesh App   │────▶│ Peoplemesh       │  │ Docling  │ │
│  └────────┬─────────┘     │ PostgreSQL       │  └──────────┘ │
│           │               │ + pgvector       │                 │
│           ▼               └──────────────────┘                 │
│  ┌──────────────────┐                                          │
│  │ vLLM Inference   │                                          │
│  │ (Optional)       │                                          │
│  └──────────────────┘                                          │
│                                                                 │
│  Shared Resources:                                             │
│  • Secret: keycloak-client-secret (auto-generated)            │
│  • Secret: pgvector-database (postgres password)              │
│  • Secret: keycloak-db-secret (keycloak postgres password)    │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

## Post-Install Information

After deployment, Helm prints:

```
========================================
Peoplemesh Quickstart Deployed!
========================================

Application URL:
  https://peoplemesh-peoplemesh.apps.cluster.example.com

Keycloak Admin Console:
  https://keycloak-peoplemesh.apps.cluster.example.com/admin
  
Test User:
  Username: testuser@example.com
  Password: TestUserPassword123

Next Steps:
  1. Wait for all pods to be ready
  2. Navigate to application URL
  3. Click "Sign in"
  4. Choose "Continue with Keycloak"
  5. Login with test credentials above
```

## Upgrade Deployment

To update configuration:

```bash
# Modify values
helm upgrade peoplemesh peoplemesh-umbrella/ \
  --namespace peoplemesh \
  --set pgvector.postgres.password=SecurePostgresPassword \
  --set keycloak.postgres.password=SecureKeycloakPassword \
  --set peoplemesh.peoplemesh.replicas=2 \
  --reuse-values
```

## Cleanup

```bash
# Uninstall everything
helm uninstall peoplemesh -n peoplemesh

# Delete namespace (removes PVCs and all data)
oc delete namespace peoplemesh
```

**Warning**: This deletes all data including:
- Keycloak users and realm configuration
- Peoplemesh application data
- All persistent volumes

## Troubleshooting

### Keycloak Not Ready

```bash
# Check Keycloak CR status
oc get keycloak keycloak -n peoplemesh

# Check operator logs
oc logs -l name=rhbk-operator -n <operator-namespace>
```

### Peoplemesh Can't Connect to Keycloak

```bash
# Verify shared secret exists
oc get secret keycloak-client-secret -n peoplemesh

# Check peoplemesh environment
oc set env deployment/peoplemesh --list -n peoplemesh | grep KEYCLOAK
```

### Test User Can't Login

```bash
# Check realm import status
oc get keycloakrealmimport peoplemesh-realm -n peoplemesh

# Verify test user in Keycloak
# Login to Keycloak admin console
# Navigate to peoplemesh realm → Users
# Search for testuser@example.com
```

### Pods Stuck in Pending

```bash
# Check resource availability
oc describe pod <pod-name> -n peoplemesh

# Check PVC status
oc get pvc -n peoplemesh
```

## Automated Deployment Script

For fully automated deployments in CI/CD:

```bash
#!/bin/bash
set -e

NAMESPACE="peoplemesh"
POSTGRES_PASSWORD="$(openssl rand -base64 32)"
KEYCLOAK_PASSWORD="$(openssl rand -base64 32)"
TEST_USER_PASSWORD="TestUser$(openssl rand -base64 12)"

helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace "$NAMESPACE" \
  --set pgvector.postgres.password="$POSTGRES_PASSWORD" \
  --set keycloak.postgres.password="$KEYCLOAK_PASSWORD" \
  --set keycloak.realm.testUser.password="$TEST_USER_PASSWORD" \
  --timeout 15m \
  --wait

# Save credentials
echo "Namespace: $NAMESPACE" > deployment-info.txt
echo "Test User: testuser@example.com" >> deployment-info.txt
echo "Test Password: $TEST_USER_PASSWORD" >> deployment-info.txt
echo "App URL: https://$(oc get route peoplemesh -n $NAMESPACE -o jsonpath='{.spec.host}')" >> deployment-info.txt

cat deployment-info.txt
```

## Next Steps

- Access Keycloak admin console to create additional users
- Configure additional OIDC scopes or claims
- Import user profiles from GitHub
- Set up monitoring and logging
- Configure backups for PostgreSQL databases

## Support

For issues:
- GitHub Issues: https://github.com/rh-ai-quickstart/peoplemesh/issues
- Documentation: See `/docs` directory

