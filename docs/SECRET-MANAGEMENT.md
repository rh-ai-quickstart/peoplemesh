# Secret Management - Design Decision

## Philosophy

**Explicit over implicit.** All secrets must be provided by the user at install time.

## What Changed

### Before
- Secrets auto-generated with `randAlphaNum`
- Used `lookup` patterns to preserve secrets on upgrade
- Added `helm.sh/resource-policy: keep` to prevent deletion on uninstall
- **Problem:** Cookie/session issues after reinstall, secrets persisted after uninstall

### After
- **All 6 secrets required** - no defaults, no auto-generation
- **No lookup patterns** - user provides values explicitly
- **No resource-policy: keep** - `helm uninstall` removes everything
- **User controls persistence** - same secrets = persistent sessions

## Required Secrets

| Secret | Chart Value | Purpose |
|--------|-------------|---------|
| Keycloak DB Password | `keycloak.postgres.password` | Keycloak's PostgreSQL authentication |
| Pgvector DB Password | `pgvector.postgres.password` | Peoplemesh's PostgreSQL authentication |
| Keycloak Client Secret | `keycloak.realm.client.clientSecret` | OIDC authentication between Keycloak ↔ Peoplemesh |
| Session Secret | `peoplemesh.security.sessionSecret` | Browser session cookie encryption |
| OAuth State Secret | `peoplemesh.security.oauthStateSecret` | OAuth CSRF protection |
| Maintenance API Key | `peoplemesh.security.maintenanceApiKey` | Maintenance endpoint authentication |

## Benefits

### 1. Predictable Uninstall
```bash
helm uninstall peoplemesh -n namespace
```
- ✅ Removes ALL resources
- ✅ Removes ALL secrets
- ✅ PVC cleanup job removes databases
- ✅ No orphaned resources

### 2. Session Persistence Control
**Same secrets = sessions persist:**
```bash
# Install
helm install ... --set peoplemesh.security.sessionSecret="abc123..."

# Uninstall
helm uninstall ...

# Reinstall with SAME secret
helm install ... --set peoplemesh.security.sessionSecret="abc123..."
# → Browser cookies still valid!
```

**Different secrets = fresh start:**
```bash
# Reinstall with DIFFERENT secret
helm install ... --set peoplemesh.security.sessionSecret="xyz789..."
# → Old cookies invalid, must login again
```

### 3. Security Transparency
- No hidden auto-generated secrets
- User controls all authentication credentials
- Clear documentation of what each secret does
- Explicit in Helm commands or values files

### 4. Testing & CI/CD Friendly
- Use fixed secrets for test environments
- Consistent state across test runs
- Easy to parameterize in CI/CD pipelines
- No surprises from random generation

## Implementation Details

### Helper Template Pattern
```yaml
{{- define "keycloak.postgresPassword" -}}
{{- required "keycloak.postgres.password is required" .Values.postgres.password }}
{{- end }}
```

### Secret Template Pattern
```yaml
stringData:
  password: {{ include "keycloak.postgresPassword" . | quote }}
```

### Helm Install Fails Fast
If any required secret is missing:
```
Error: execution error at (chart/templates/secrets.yaml:17:24): 
  keycloak.postgres.password is required
```

## Migration from Previous Version

If you have an existing deployment with auto-generated secrets:

### Step 1: Extract Current Secrets
```bash
# Get current secrets
KC_DB_PASS=$(oc get secret keycloak-db-secret -n namespace -o jsonpath='{.data.password}' | base64 -d)
PG_DB_PASS=$(oc get secret pgvector-database -n namespace -o jsonpath='{.data.DATABASE_PASSWORD}' | base64 -d)
CLIENT_SECRET=$(oc get secret keycloak-client-secret -n namespace -o jsonpath='{.data.clientSecret}' | base64 -d)
SESSION_SECRET=$(oc get secret peoplemesh-secrets -n namespace -o jsonpath='{.data.SESSION_SECRET}' | base64 -d)
OAUTH_SECRET=$(oc get secret peoplemesh-secrets -n namespace -o jsonpath='{.data.OAUTH_STATE_SECRET}' | base64 -d)
MAINT_KEY=$(oc get secret peoplemesh-secrets -n namespace -o jsonpath='{.data.MAINTENANCE_API_KEY}' | base64 -d)
```

### Step 2: Uninstall Old Version
```bash
helm uninstall peoplemesh -n namespace
```

### Step 3: Reinstall with Extracted Secrets
```bash
helm install peoplemesh peoplemesh-umbrella \
  --namespace namespace \
  --set keycloak.postgres.password="$KC_DB_PASS" \
  --set pgvector.postgres.password="$PG_DB_PASS" \
  --set keycloak.realm.client.clientSecret="$CLIENT_SECRET" \
  --set peoplemesh.security.sessionSecret="$SESSION_SECRET" \
  --set peoplemesh.security.oauthStateSecret="$OAUTH_SECRET" \
  --set peoplemesh.security.maintenanceApiKey="$MAINT_KEY"
```

**Note:** Database data will be lost (PVCs cleaned up), but sessions will persist.

## Best Practices

### For Development
```bash
# Use simple, memorable secrets
helm install ... \
  --set keycloak.postgres.password="dev123" \
  --set pgvector.postgres.password="dev456" \
  --set keycloak.realm.client.clientSecret="dev-client-secret-1234567890123456" \
  --set peoplemesh.security.sessionSecret="dev-session-secret-1234567890123456" \
  --set peoplemesh.security.oauthStateSecret="dev-oauth-secret-1234567890123456" \
  --set peoplemesh.security.maintenanceApiKey="dev-maint-key-1234567890123456"
```

### For Production
```bash
# Use secrets manager (Vault, External Secrets Operator)
# Or generate strong random secrets
SECRETS=$(./generate-production-secrets.sh)
helm install ... --values production-secrets.yaml
```

### For CI/CD
```bash
# Store in CI/CD secret vault
helm install ... \
  --set keycloak.postgres.password="${CI_KC_DB_PASSWORD}" \
  --set pgvector.postgres.password="${CI_PG_DB_PASSWORD}" \
  # ... etc
```

## Files Modified

- `charts/keycloak/templates/_helpers.tpl` - Removed lookup, added required
- `charts/keycloak/templates/client-secret.yaml` - Removed resource-policy
- `charts/keycloak/templates/postgres-secret.yaml` - Removed resource-policy
- `charts/pgvector/templates/_helpers.tpl` - Removed lookup, added required
- `charts/pgvector/templates/secrets.yaml` - Removed resource-policy
- `charts/peoplemesh/templates/secrets.yaml` - Removed defaults, added required
- `peoplemesh-umbrella/values.yaml` - Updated comments to reflect REQUIRED fields

## Testing

```bash
# Test: Missing secrets fail
helm template test . 
# Expected: Error listing required fields

# Test: All secrets provided succeed
helm template test . --values test-secrets.yaml
# Expected: Success, templates render

# Test: Uninstall removes everything
helm install test . --values test-secrets.yaml
helm uninstall test
oc get secrets  # Should show no peoplemesh/keycloak/pgvector secrets
oc get pvc      # Should show no PVCs (cleanup job removed them)
```
