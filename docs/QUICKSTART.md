# Peoplemesh Quickstart - Single Command Install

## Quick Install (All Secrets Required)

```bash
helm install peoplemesh peoplemesh-umbrella \
  --namespace peoplemesh-quickstart \
  --create-namespace \
  --timeout 15m \
  --wait \
  --set keycloak.postgres.password="YourKeycloakDbPassword123" \
  --set pgvector.postgres.password="YourPgvectorDbPassword123" \
  --set keycloak.realm.client.clientSecret="your-client-secret-min-32-chars-here" \
  --set peoplemesh.security.sessionSecret="your-session-secret-min-32-chars-here" \
  --set peoplemesh.security.oauthStateSecret="your-oauth-secret-min-32-chars-here" \
  --set peoplemesh.security.maintenanceApiKey="your-maint-key-min-32-chars-here" \
  --set keycloak.realm.testUser.password="YourTestUserPassword"
```

**Important:** Replace all placeholder values with your own secrets. **Use the same values for reinstallation** to preserve sessions.

## What Gets Installed

- ✅ Keycloak (OIDC authentication server)
- ✅ PostgreSQL databases (Keycloak + Peoplemesh with pgvector)
- ✅ Ollama (local LLM with granite models)
- ✅ Docling (document processing)
- ✅ Peoplemesh application with test data (500 users, 200 jobs, 2000 skills)

## Access the Application

```bash
# Get application URL
oc get route peoplemesh -n peoplemesh-quickstart -o jsonpath='{.spec.host}'

# Login with test user
# Username: testuser
# Password: changeme123
```

## Uninstall

```bash
helm uninstall peoplemesh --namespace peoplemesh-quickstart
```

**Complete cleanup** - removes all resources including PVCs.

## Reinstall

Use **the exact same secret values** for reinstallation to avoid cookie/session issues.

## Full Documentation

See [INSTALL.md](./INSTALL.md) for complete installation guide with secret generation examples.
