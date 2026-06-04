# Keycloak Setup for Peoplemesh

This guide explains how to deploy and configure Red Hat build of Keycloak 24.0 as an OIDC provider for Peoplemesh.

## Overview

Keycloak will serve as the identity provider (IDP) for Peoplemesh, providing:
- User authentication via OIDC
- User management
- Realm for peoplemesh application
- Client configuration for peoplemesh

## Deployment Architecture

```
Peoplemesh Namespace (peoplemesh)          Keycloak Namespace (samouelian-keycloak)
┌─────────────────────────────┐           ┌──────────────────────────────────┐
│ Peoplemesh Application      │           │ Keycloak Server                  │
│  ├─ OIDC Client Config      │◄──────────┤  ├─ Realm: peoplemesh           │
│  └─ Endpoints:              │   HTTPS   │  ├─ Clients                      │
│     - .../auth/login/...    │           │  └─ Users                        │
└─────────────────────────────┘           └────────────┬─────────────────────┘
                                                        │
                                          ┌─────────────▼─────────────────────┐
                                          │ PostgreSQL Database (Persistent)  │
                                          │  - 10Gi PVC                       │
                                          │  - Survives pod restarts          │
                                          └───────────────────────────────────┘
```

## Prerequisites

### 1. Install Keycloak Operator

The Keycloak Operator must be installed in the `samouelian-keycloak` namespace:

```bash
# Verify the operator is installed
oc get csv -n samouelian-keycloak | grep rhbk-operator

# Check CRDs are available
oc get crd keycloaks.k8s.keycloak.org
oc get crd keycloakrealmimports.k8s.keycloak.org
```

If not installed, install via OperatorHub:
1. OpenShift Console → Operators → OperatorHub
2. Search for "Red Hat build of Keycloak"
3. Install to `samouelian-keycloak` namespace
4. Select the v24 channel

### 2. Create Namespace

```bash
oc get namespace samouelian-keycloak || oc create namespace samouelian-keycloak
```

## Installation Steps

### Step 1: Deploy Keycloak with Helm

```bash
cd /Users/psamouel/Documents/peoplemesh-quickstart

helm install keycloak charts/keycloak/ \
  --namespace samouelian-keycloak \
  --set postgres.password=MySecureKeycloakPassword
```

### Step 2: Monitor Deployment

```bash
# Watch Keycloak CR status
oc get keycloak keycloak -n samouelian-keycloak -w

# Watch pods
oc get pods -n samouelian-keycloak -w
```

Wait for:
- `keycloak-postgres-db-0` → Running
- `keycloak-*` → Running
- Keycloak CR status → Ready=true

This typically takes 2-5 minutes.

### Step 3: Verify Deployment

```bash
# Check Keycloak is ready
oc get keycloak keycloak -n samouelian-keycloak \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Should output: true

# Check realm was imported
oc get keycloakrealmimport peoplemesh-realm -n samouelian-keycloak \
  -o jsonpath='{.status.conditions[?(@.type=="Done")].status}'
# Should output: true
```

### Step 4: Access Keycloak Admin Console

```bash
# Get the route URL
KEYCLOAK_URL="https://$(oc get route keycloak -n samouelian-keycloak -o jsonpath='{.spec.host}')"
echo "Admin Console: $KEYCLOAK_URL/admin"

# Get admin credentials
echo "Username: $(oc get secret keycloak-initial-admin -n samouelian-keycloak -o jsonpath='{.data.username}' | base64 -d)"
echo "Password: $(oc get secret keycloak-initial-admin -n samouelian-keycloak -o jsonpath='{.data.password}' | base64 -d)"
```

Open the Admin Console URL in your browser and log in with these credentials.

## Configuring Peoplemesh Client

Once Keycloak is running, you need to create an OIDC client for Peoplemesh.

### Step 1: Get Peoplemesh Route

First, determine your Peoplemesh redirect URI:

```bash
# If peoplemesh is deployed, get its route
PEOPLEMESH_URL="https://$(oc get route peoplemesh -n peoplemesh -o jsonpath='{.spec.host}')"
echo "Peoplemesh callback: $PEOPLEMESH_URL/api/v1/auth/callback/keycloak"
```

### Step 2: Create Client via Admin Console

1. Log into Keycloak Admin Console
2. Select the **peoplemesh** realm (top-left dropdown)
3. Navigate to **Clients** → **Create client**
4. **General Settings**:
   - Client type: `OpenID Connect`
   - Client ID: `peoplemesh`
   - Click **Next**
5. **Capability config**:
   - Client authentication: `On`
   - Authorization: `Off`
   - Standard flow: `Enabled` ✓
   - Direct access grants: `Enabled` ✓
   - Click **Next**
6. **Login settings**:
   - Valid redirect URIs: `https://<peoplemesh-route>/api/v1/auth/callback/keycloak`
   - Web origins: `https://<peoplemesh-route>`
   - Click **Save**

### Step 3: Get Client Secret

1. Go to **Clients** → **peoplemesh**
2. Click the **Credentials** tab
3. Copy the **Client secret** value

You'll need this for configuring Peoplemesh.

### Step 4: Create Test User

1. Navigate to **Users** → **Add user**
2. Fill in:
   - Username: `testuser`
   - Email: `testuser@example.com`
   - First name: `Test`
   - Last name: `User`
   - Email verified: `On`
   - Click **Create**
3. Go to **Credentials** tab
4. Click **Set password**
5. Set a password, turn off **Temporary**
6. Click **Save**

## Keycloak Endpoints

Once deployed, note these endpoints for Peoplemesh configuration:

```bash
KEYCLOAK_URL="https://$(oc get route keycloak -n samouelian-keycloak -o jsonpath='{.spec.host}')"

echo "Issuer URL: $KEYCLOAK_URL/realms/peoplemesh"
echo "Authorization: $KEYCLOAK_URL/realms/peoplemesh/protocol/openid-connect/auth"
echo "Token: $KEYCLOAK_URL/realms/peoplemesh/protocol/openid-connect/token"
echo "UserInfo: $KEYCLOAK_URL/realms/peoplemesh/protocol/openid-connect/userinfo"
echo "JWKS: $KEYCLOAK_URL/realms/peoplemesh/protocol/openid-connect/certs"
```

## Testing OIDC Flow

### Test Discovery Endpoint

```bash
KEYCLOAK_URL="https://$(oc get route keycloak -n samouelian-keycloak -o jsonpath='{.spec.host}')"

curl -k "$KEYCLOAK_URL/realms/peoplemesh/.well-known/openid-configuration" | jq .
```

This should return the OIDC configuration JSON.

## Maintenance

### Restart Keycloak

```bash
# Delete Keycloak pod (Operator will recreate it)
oc delete pod -l app.kubernetes.io/name=keycloak -n samouelian-keycloak
```

### Restart PostgreSQL

```bash
# Delete PostgreSQL pod (StatefulSet will recreate it with same PVC)
oc delete pod keycloak-postgres-db-0 -n samouelian-keycloak
```

**Data is preserved** because of the persistent volume.

### View Logs

```bash
# Keycloak logs
oc logs -f -l app.kubernetes.io/name=keycloak -n samouelian-keycloak

# PostgreSQL logs
oc logs -f keycloak-postgres-db-0 -n samouelian-keycloak
```

### Backup Database

```bash
# Backup Keycloak database
oc exec keycloak-postgres-db-0 -n samouelian-keycloak -- \
  pg_dump -U keycloak keycloak > keycloak-backup-$(date +%Y%m%d).sql
```

## Uninstall

```bash
# Remove Helm release
helm uninstall keycloak --namespace samouelian-keycloak

# Optional: Delete persistent data (WARNING: irreversible!)
oc delete pvc postgres-data-keycloak-postgres-db-0 -n samouelian-keycloak
```

## Next Steps

Once Keycloak is configured:

1. **Update Peoplemesh** to use Keycloak as OIDC provider (see [GOOGLE-IDP-INTEGRATION.md](../GOOGLE-IDP-INTEGRATION.md))
2. **Modify Peoplemesh code** to add Keycloak support (see instructions for new Claude conversation)
3. **Test authentication flow** with the test user

## References

- [Red Hat build of Keycloak 24.0 Documentation](https://access.redhat.com/documentation/en-us/red_hat_build_of_keycloak/24.0)
- [Keycloak OIDC Documentation](https://www.keycloak.org/docs/latest/server_admin/#_oidc)
- [OpenID Connect Core Specification](https://openid.net/specs/openid-connect-core-1_0.html)
