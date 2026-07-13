# Peoplemesh Deployment Notes

## Key Configuration Requirements

Based on the [official peoplemesh container documentation](https://github.com/francescopace/peoplemesh/blob/main/docs/how-to/build-and-run-container.md), here are the critical requirements:

### 1. Container Image
- ✅ **Image**: `frapax/peoplemesh:main` (NOT `latest`)
- Published on Docker Hub with `amd64` and `arm64` support

### 2. Required Environment Variables

#### Database (All Required)
- `DB_URL` - JDBC connection string
- `DB_USER` - Database username  
- `DB_PASSWORD` - Database password

#### LLM Configuration (All Required)
- `OPENAI_API_KEY` - API key (or 'ollama' for local)
- `OPENAI_BASE_URL` - LLM endpoint URL
- `LLM_MODEL` - Model name
- `EMBEDDING_MODEL` - Embedding model name

#### Document Processing (Required for CV import)
- `CV_IMPORT_PROVIDER` - Must be `docling` (not `local`)
- `DOCLING_BASE_URL` - Docling service endpoint

#### Security (All Required)
- `SESSION_SECRET` - Must be 32+ bytes
- `OAUTH_STATE_SECRET` - Must be 32+ bytes  
- `MAINTENANCE_API_KEY` - Shared key for maintenance endpoints
- `CORS_ORIGINS` - Allowed CORS origins

#### OIDC Authentication (**AT LEAST ONE REQUIRED**)
Must configure either Google OR Microsoft (or both):
- Google: `OIDC_GOOGLE_CLIENT_ID` + `OIDC_GOOGLE_CLIENT_SECRET`
- Microsoft: `OIDC_MICROSOFT_CLIENT_ID` + `OIDC_MICROSOFT_CLIENT_SECRET`

**Note**: These use `OIDC_` prefix, not just `GOOGLE_` or `MICROSOFT_`

### 3. Port Configuration
- Port **8080** - Main application HTTP port

### 4. Health Checks
- Liveness: `GET /q/health/live`
- Readiness: `GET /q/health/ready`
- Info: `GET /api/v1/info`

## OpenShift-Specific Requirements

### GPU Node Tolerations
The cluster has GPU nodes with taints. All pods need these tolerations:

```yaml
tolerations:
  - key: "nvidia.com/gpu"
    operator: "Exists"
    effect: "NoSchedule"
  - key: "g5-gpu"
    operator: "Exists"
    effect: "NoSchedule"
```

✅ Added to: pgvector, docling, peoplemesh deployments

### PostgreSQL Extension Creation
The pgvector extension requires superuser privileges:

```bash
# Must use postgres user, not the application user
PGPASSWORD="$POSTGRESQL_ADMIN_PASSWORD" psql -U postgres -d peoplemesh -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

✅ Fixed in pgvector init script

## Installation Checklist

Before installing, ensure you have:

- [ ] PostgreSQL password set
- [ ] External LLM endpoint URL and API key (if using external mode)
- [ ] LLM model names (chat and embedding)
- [ ] At least ONE OIDC provider configured (Google or Microsoft)
- [ ] CORS origins configured (use `*` for testing, specific origins for production)

## Minimal Installation Command

With external LLM (no GPU required):

```bash
helm install peoplemesh peoplemesh-umbrella/ \
  --create-namespace \
  --namespace peoplemesh \
  --set pgvector.postgres.password=MySecurePassword123 \
  --set vllm.enabled=false \
  --set peoplemesh.llm.mode=external \
  --set peoplemesh.llm.external.baseUrl=https://your-vllm-server.example.com/v1 \
  --set peoplemesh.llm.external.apiKey=your-api-key \
  --set peoplemesh.llm.external.chatModel=qwen3-14b \
  --set peoplemesh.llm.external.embeddingModel=qwen3-14b \
  --set peoplemesh.llm.external.embeddingDimension=5120 \
  --set peoplemesh.security.oidc.google.clientId=YOUR_GOOGLE_CLIENT_ID \
  --set peoplemesh.security.oidc.google.clientSecret=YOUR_GOOGLE_CLIENT_SECRET
```

**Note**: Replace the OIDC credentials with real values from your Google Cloud Console.

## Verification

After installation:

```bash
# Check pod status
oc get pods -n peoplemesh

# Check peoplemesh logs
oc logs -f deployment/peoplemesh -n peoplemesh

# Get the route
oc get route peoplemesh -n peoplemesh

# Test health endpoint
oc exec deployment/peoplemesh -n peoplemesh -- curl -sf http://localhost:8080/q/health
```

## Common Issues

### Issue: OIDC not configured
**Error**: Application fails to start or login doesn't work  
**Solution**: Configure at least one OIDC provider (Google or Microsoft)

### Issue: Wrong environment variable names
**Error**: `GOOGLE_CLIENT_ID` not found  
**Solution**: Use `OIDC_GOOGLE_CLIENT_ID` (with `OIDC_` prefix)

### Issue: CV import fails
**Error**: Docling connection error  
**Solution**: Ensure `CV_IMPORT_PROVIDER=docling` and `DOCLING_BASE_URL` is correct

### Issue: Pods stuck in Pending (Insufficient CPU)
**Error**: `0/20 nodes available: 6 Insufficient cpu`  
**Solution**: Pods need GPU node tolerations to schedule on available nodes (already fixed in charts)

### Issue: ImagePullBackOff with latest tag
**Error**: `manifest unknown` for `frapax/peoplemesh:latest`  
**Solution**: Use `frapax/peoplemesh:main` tag instead (already fixed in charts)
