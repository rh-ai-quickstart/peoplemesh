# Peoplemesh Quickstart Installation Options

## Quick Demo (Default)

For quick testing and demos where you don't care about data persistence:

```bash
helm install peoplemesh . --namespace peoplemesh-demo --create-namespace --timeout 15m --wait
```

**What happens:**
- All secrets and passwords are auto-generated randomly
- Every `helm install` creates fresh databases and secrets
- **Sessions are invalidated** on each reinstall (must clear cookies or use incognito)
- Data is lost between installs

## Persistent Installation (Recommended for Development)

For development environments where you want sessions and data to persist across reinstalls:

```bash
helm install peoplemesh . \
  --namespace peoplemesh-dev \
  --create-namespace \
  --timeout 15m \
  --wait \
  --set peoplemesh.security.sessionSecret="your-stable-session-secret-min-32-chars" \
  --set peoplemesh.security.oauthStateSecret="your-stable-oauth-secret-min-32-chars" \
  --set pgvector.postgres.password="your-stable-db-password" \
  --set keycloak.postgres.password="your-stable-keycloak-db-password"
```

**What happens:**
- Same secrets are used on every install
- **Sessions persist** - no need to clear cookies between reinstalls
- Database passwords remain stable
- Keycloak client secret is automatically persisted (uses `resource-policy: keep`)

**Example with generated secrets:**

```bash
# Generate stable secrets once
SESSION_SECRET=$(openssl rand -hex 32)
OAUTH_SECRET=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
KC_DB_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)

# Use the same secrets for all installs
helm install peoplemesh . \
  --namespace peoplemesh-dev \
  --create-namespace \
  --timeout 15m \
  --wait \
  --set peoplemesh.security.sessionSecret="$SESSION_SECRET" \
  --set peoplemesh.security.oauthStateSecret="$OAUTH_SECRET" \
  --set pgvector.postgres.password="$DB_PASSWORD" \
  --set keycloak.postgres.password="$KC_DB_PASSWORD"
```

## What Gets Cleaned Up

The quickstart includes a **pre-install cleanup job** that:
- Deletes old PVCs (PostgreSQL data) before each install
- Ensures fresh database state
- Prevents password mismatch issues

**Secrets that persist automatically:**
- ✅ Keycloak client secret (has `resource-policy: keep`)

**Secrets that change on each install (unless you provide them):**
- ❌ Peoplemesh session secret → breaks existing user sessions
- ❌ OAuth state secret → breaks in-flight OAuth flows
- ❌ Database passwords → databases are wiped anyway (PVC cleanup)

## Troubleshooting

### "No OIDC provider configured" error after reinstall

**Cause:** Session secret changed between installs, invalidating your browser session.

**Solution:**
1. Clear cookies for the peoplemesh domain, OR
2. Use incognito mode, OR
3. Provide stable secrets (see "Persistent Installation" above)

### Database password mismatch

**Cause:** This shouldn't happen anymore - the pre-install cleanup job deletes old PVCs.

**If it still happens:**
```bash
# Manually clean up
helm uninstall peoplemesh -n your-namespace
oc delete pvc --all -n your-namespace
# Then reinstall
```

## Production Considerations

For production deployments:

1. **Use a secrets manager** (Vault, External Secrets Operator)
2. **Disable PVC cleanup** - remove `peoplemesh-umbrella/templates/cleanup-*` files
3. **Use persistent storage class** with backup/snapshot capabilities
4. **Set CORS origins** to specific domains (not `*`)
5. **Change default test user password** or disable test user entirely
6. **Use dedicated OAuth provider** (not the demo Keycloak)
