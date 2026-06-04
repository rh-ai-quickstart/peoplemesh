# Red Hat build of Keycloak 24.0 Helm Chart

This Helm chart deploys **Red Hat build of Keycloak 24.0** using the Keycloak Operator with a **persistent PostgreSQL database**.

## Overview

This chart is designed for the peoplemesh quickstart and demonstrates deploying Keycloak on OpenShift using:

- **Red Hat build of Keycloak Operator** (must be pre-installed)
- **Persistent PostgreSQL database** (separate from peoplemesh database)
- **OpenShift Route** for TLS termination
- **Peoplemesh realm** pre-configured for OIDC authentication

## Prerequisites

1. **OpenShift cluster** (4.12+)
2. **Keycloak Operator installed** in `samouelian-keycloak` namespace:
   ```bash
   # Verify operator is installed
   oc get csv -n samouelian-keycloak | grep keycloak
   ```
3. **Helm 3.x**
4. **Namespace exists**:
   ```bash
   oc get namespace samouelian-keycloak || oc create namespace samouelian-keycloak
   ```

## Quick Start

### 1. Install Keycloak

```bash
cd /Users/psamouel/Documents/peoplemesh-quickstart

helm install keycloak charts/keycloak/ \
  --namespace samouelian-keycloak \
  --set postgres.password=YOUR_SECURE_PASSWORD
```

### 2. Wait for Keycloak to be Ready

```bash
# Watch the Keycloak CR status
oc get keycloak/keycloak -n samouelian-keycloak -w

# Check all pods
oc get pods -n samouelian-keycloak
```

Expected pods:
- `keycloak-postgres-db-0` - PostgreSQL database
- `keycloak-*` - Keycloak instance(s)

### 3. Get the Keycloak URL

```bash
oc get route keycloak -n samouelian-keycloak -o jsonpath='{.spec.host}'
```

### 4. Get Admin Credentials

```bash
# Username
oc get secret keycloak-initial-admin -n samouelian-keycloak \
  -o jsonpath='{.data.username}' | base64 -d

# Password
oc get secret keycloak-initial-admin -n samouelian-keycloak \
  -o jsonpath='{.data.password}' | base64 -d
```

### 5. Access Keycloak Admin Console

```bash
# Get the URL
KEYCLOAK_URL="https://$(oc get route keycloak -n samouelian-keycloak -o jsonpath='{.spec.host}')"
echo "Keycloak Admin Console: $KEYCLOAK_URL/admin"
```

Login with the admin credentials from step 4.

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `namespace` | Target namespace for deployment | `samouelian-keycloak` |
| `postgres.password` | PostgreSQL password | `changeme-keycloak-db` |
| `postgres.persistence.size` | Database storage size | `10Gi` |
| `keycloak.instances` | Number of Keycloak replicas | `1` |
| `realm.enabled` | Create peoplemesh realm | `true` |
| `realm.name` | Realm name | `peoplemesh` |

### Custom Values

Create a custom `values.yaml`:

```yaml
postgres:
  password: "MySecurePassword123"
  persistence:
    size: 20Gi

keycloak:
  instances: 2
  resources:
    requests:
      memory: 2Gi
```

Install with custom values:

```bash
helm install keycloak charts/keycloak/ \
  --namespace samouelian-keycloak \
  -f my-values.yaml
```

## Architecture

```
┌─────────────────────────────────────────┐
│ OpenShift Route (TLS Termination)      │
│ https://keycloak-samouelian-keycloak...│
└────────────────┬────────────────────────┘
                 │
    ┌────────────▼────────────┐
    │ Keycloak Service        │
    │ (Managed by Operator)   │
    └────────────┬────────────┘
                 │
    ┌────────────▼────────────┐
    │ Keycloak Pod(s)         │
    │ (StatefulSet)           │
    └────────────┬────────────┘
                 │
    ┌────────────▼────────────┐
    │ PostgreSQL StatefulSet  │
    │ + PersistentVolumeClaim │
    │ (10Gi, survives restart)│
    └─────────────────────────┘
```

## Key Features

### Persistent Storage

Unlike the ephemeral example in the RHBK documentation, this chart uses **persistent storage**:

```yaml
volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 10Gi
```

### Peoplemesh Realm

The chart automatically creates a `peoplemesh` realm via `KeycloakRealmImport`:

- **ID**: `peoplemesh`
- **Display Name**: Peoplemesh
- **Registration**: Disabled (admin creates users)
- **Email as Username**: Enabled
- **Remember Me**: Enabled

### OpenShift Integration

- **Route**: Automatically created with TLS reencrypt termination
- **GPU Tolerations**: Pods can schedule on GPU nodes
- **Security**: Runs with OpenShift's restricted SCC

## Verification

### Check Keycloak Status

```bash
# Keycloak CR status
oc get keycloak keycloak -n samouelian-keycloak -o jsonpath='{.status.conditions}'

# Expected output: Ready=true
```

### Check Realm Import

```bash
# Realm import status
oc get keycloakrealmimport peoplemesh-realm -n samouelian-keycloak

# Check status
oc get keycloakrealmimport peoplemesh-realm -n samouelian-keycloak \
  -o jsonpath='{.status.conditions}'
```

### Check Database

```bash
# PostgreSQL pod
oc get pod keycloak-postgres-db-0 -n samouelian-keycloak

# Test database connection
oc exec -it keycloak-postgres-db-0 -n samouelian-keycloak -- \
  psql -U keycloak -d keycloak -c "SELECT version();"
```

### Check Persistent Volume

```bash
# View PVC
oc get pvc -n samouelian-keycloak

# Expected: postgres-data-keycloak-postgres-db-0  Bound
```

## Troubleshooting

### Keycloak Pod Not Starting

```bash
# Check Keycloak logs
oc logs -l app.kubernetes.io/name=keycloak -n samouelian-keycloak

# Check Keycloak CR status
oc describe keycloak keycloak -n samouelian-keycloak
```

### Database Connection Issues

```bash
# Check PostgreSQL logs
oc logs keycloak-postgres-db-0 -n samouelian-keycloak

# Check database secret
oc get secret keycloak-db-secret -n samouelian-keycloak -o yaml
```

### Realm Import Failed

```bash
# Check realm import status
oc describe keycloakrealmimport peoplemesh-realm -n samouelian-keycloak

# Check for errors
oc get keycloakrealmimport peoplemesh-realm -n samouelian-keycloak \
  -o jsonpath='{.status.conditions[?(@.type=="HasErrors")]}'
```

## Uninstall

```bash
# Delete Helm release
helm uninstall keycloak --namespace samouelian-keycloak

# Optional: Delete PVC (this will DELETE all data)
oc delete pvc postgres-data-keycloak-postgres-db-0 -n samouelian-keycloak
```

**Warning**: Deleting the PVC will permanently delete all Keycloak data (users, realms, clients, etc.).

## References

- [Red Hat build of Keycloak 24.0 Operator Guide](https://access.redhat.com/documentation/en-us/red_hat_build_of_keycloak/24.0)
- [Keycloak Operator GitHub](https://github.com/keycloak/keycloak-operator)
- [OpenShift Routes Documentation](https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html)
