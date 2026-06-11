# Deploy an AI-Powered Talent Discovery Platform

Connect people with opportunities using semantic search and AI-powered skill matching to build stronger teams and unlock organizational expertise.

## Table of Contents

- [Detailed Description](#detailed-description)
  - [See it in Action](#see-it-in-action)
  - [Architecture](#architecture)
- [Requirements](#requirements)
  - [Hardware Requirements](#hardware-requirements)
  - [Software Requirements](#software-requirements)
- [Deploy](#deploy)
  - [Quick Start](#quick-start)
  - [GPU Acceleration (Optional)](#gpu-acceleration-optional)
  - [Verify Deployment](#verify-deployment)
  - [Delete](#delete)
- [Using the Application](#using-the-application)
- [Advanced Configuration](#advanced-configuration)
- [Reference](#reference)
- [Tags](#tags)

## Detailed Description

Organizations struggle to connect the right people with the right opportunities. Traditional directory searches rely on exact keyword matches, missing talented individuals whose skills are described differently or whose expertise lies hidden in résumés and project histories. This creates missed opportunities for staffing projects, forming teams, and leveraging existing organizational knowledge.

This quickstart deploys **Peoplemesh**, an AI-powered talent discovery platform that uses semantic search and vector embeddings to understand the meaning behind searches, not just keywords. When someone searches for "mobile developer in Italy," the system understands related concepts like "iOS engineer," "Android developer," and geographic variations, surfacing the best matches even when exact words don't match. It processes résumés and profiles using large language models to extract skills, experience, and expertise automatically.

The platform enables organizations to find hidden talent, build diverse teams, identify skill gaps, and connect people with relevant opportunities—all through a simple search interface powered by open-source AI. Whether staffing a critical project, building a community of practice, or identifying mentors, Peoplemesh helps you find the right people quickly.

### See it in Action

![Peoplemesh Screenshot](docs/images/screenshot1.png)

**Key Features:**
- 🔍 **Semantic Search**: Find people by skills, experience, location, or any combination using natural language
- 📄 **AI Resume Processing**: Upload résumés and automatically extract structured profiles using LLMs
- 🎯 **Smart Matching**: Vector embeddings understand "data scientist" matches "ML engineer" and "machine learning specialist"
- 🌍 **Geographic Intelligence**: Understands locations, time zones, and work mode preferences
- 🔐 **Enterprise Authentication**: Built-in Keycloak integration with support for Google, Microsoft, and custom OIDC providers

### Architecture

![Architecture Diagram](docs/images/architecture.png)

**Components:**
- **Peoplemesh Application**: React frontend + Quarkus backend serving the search interface and REST API
- **Keycloak**: Authentication and user management with OIDC support
- **PostgreSQL + pgvector**: Vector database for semantic search using embeddings
- **Ollama** (or vLLM): Local LLM for query parsing and résumé processing
- **Docling**: Document parsing service for extracting text from résumés (PDF, DOCX, etc.)

**Data Flow:**
1. User uploads résumé → Docling extracts text → LLM structures profile → Stored with vector embeddings
2. User searches "mobile developer" → LLM parses intent → Vector similarity search → Ranked results
3. Authentication flow → Keycloak OIDC → Session management → Secure API access

## Requirements

### Hardware Requirements

**Minimum (CPU-only):**
- **CPU**: 4 cores
- **Memory**: 16 GB RAM
- **Storage**: 100 GB available (50 GB for models, 50 GB for databases)

**Recommended (with GPU acceleration for 10-20x faster performance):**
- **CPU**: 8 cores
- **Memory**: 32 GB RAM
- **GPU**: 1x NVIDIA GPU with 16GB+ VRAM (A10G, T4, V100, or better)
- **Storage**: 150 GB available

**Notes:**
- CPU-only mode works but résumé processing takes 2-3 minutes per upload
- With GPU: résumé processing completes in 10-20 seconds
- GPU requires NVIDIA GPU Operator installed on cluster

### Software Requirements

**Required:**
- **OpenShift**: 4.12 or later
- **Helm**: 3.x
- **oc CLI**: Matching your OpenShift version
- **Red Hat build of Keycloak Operator**: 24.0 or later (installed cluster-wide or in any namespace)

**Verify Keycloak Operator:**
```bash
oc get csv -A | grep rhbk-operator
```

If not installed: OpenShift Console → OperatorHub → Search "Red Hat build of Keycloak" → Install

## Deploy

### Quick Start

**1. Clone the repository:**
```bash
git clone https://github.com/rh-ai-quickstart/peoplemesh-quickstart.git
cd peoplemesh-quickstart/peoplemesh-umbrella
```

**2. Generate secure secrets:**
```bash
# Generate all required secrets
export KC_DB_PASSWORD=$(openssl rand -base64 24)
export PG_DB_PASSWORD=$(openssl rand -base64 24)
export CLIENT_SECRET=$(openssl rand -base64 24)
export SESSION_SECRET=$(openssl rand -base64 24)
export OAUTH_SECRET=$(openssl rand -base64 24)
export MAINT_KEY=$(openssl rand -base64 24)
export TEST_USER_PASSWORD="SecurePassword1!"
```

**3. Build helm dependencies:**
```bash
helm dependency update
```

**4. Deploy (CPU-only mode):**
```bash
helm install peoplemesh . \
  --namespace peoplemesh-quickstart \
  --create-namespace \
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

**5. Get the application URL:**
```bash
echo "Application URL: https://$(oc get route peoplemesh -n peoplemesh-quickstart -o jsonpath='{.spec.host}')"
```

**6. Access the application:**
- Open the URL in your browser
- Click "Sign In"
- Choose "Continue with Keycloak"
- Login with:
  - Username: `testuser@example.com`
  - Password: `$TEST_USER_PASSWORD`

**Deployment time:** ~10-15 minutes (models and images download on first install)

### GPU Acceleration (Optional)

For **10-20x faster** LLM inference and document processing, enable GPU:

```bash
helm install peoplemesh . \
  --namespace peoplemesh-quickstart \
  --create-namespace \
  --timeout 15m \
  --wait \
  --set ollama.gpu.enabled=true \
  --set docling.gpu.enabled=true \
  --set keycloak.postgres.password="$KC_DB_PASSWORD" \
  --set pgvector.postgres.password="$PG_DB_PASSWORD" \
  --set keycloak.realm.client.clientSecret="$CLIENT_SECRET" \
  --set peoplemesh.security.sessionSecret="$SESSION_SECRET" \
  --set peoplemesh.security.oauthStateSecret="$OAUTH_SECRET" \
  --set peoplemesh.security.maintenanceApiKey="$MAINT_KEY" \
  --set keycloak.realm.testUser.password="$TEST_USER_PASSWORD"
```

**GPU Requirements:**
- At least 1 NVIDIA GPU available in cluster
- NVIDIA GPU Operator installed
- GPU tolerations pre-configured (works with common taints like `nvidia.com/gpu`, `g5-gpu`)

See [GPU-SETUP.md](GPU-SETUP.md) for detailed GPU configuration.

### Verify Deployment

**Check all pods are running:**
```bash
oc get pods -n peoplemesh-quickstart
```

Expected output:
```
NAME                             READY   STATUS    RESTARTS   AGE
docling-xxx                      1/1     Running   0          5m
keycloak-0                       1/1     Running   0          5m
keycloak-postgres-db-0           1/1     Running   0          5m
ollama-0                         1/1     Running   0          5m
peoplemesh-xxx                   1/1     Running   0          5m
pgvector-0                       1/1     Running   0          5m
```

**Test the application:**
```bash
# Health check
curl -k "https://$(oc get route peoplemesh -n peoplemesh-quickstart -o jsonpath='{.spec.host}')/q/health/ready"

# Should return: {"status":"UP"}
```

**Verify GPU allocation (if enabled):**
```bash
oc describe pod ollama-0 -n peoplemesh-quickstart | grep nvidia.com/gpu
# Should show: nvidia.com/gpu: 1 (in both Requests and Limits)
```

### Delete

To completely remove the deployment and all data:

```bash
# Uninstall the helm release
helm uninstall peoplemesh -n peoplemesh-quickstart

# Delete the namespace (removes all persistent volumes and data)
oc delete namespace peoplemesh-quickstart
```

**Warning:** This permanently deletes all data including:
- All user profiles and uploaded résumés
- Search history and analytics
- Database contents
- Keycloak users and configuration

## Using the Application

### Upload a Résumé

1. Click your profile icon → "My Profile"
2. Click "Upload CV"
3. Select a PDF or DOCX résumé
4. Wait 10-20 seconds (GPU) or 2-3 minutes (CPU) for processing
5. Review extracted information and click "Apply Changes"

**Supported formats:** PDF, DOCX, TXT

### Search for People

**Example searches:**
- `data engineer with Python experience`
- `mobile developer in Italy`
- `senior architect who speaks Italian`
- `machine learning engineer with 5+ years experience`

**Search features:**
- Semantic matching finds related terms (e.g., "ML" matches "machine learning")
- Location-aware (understands cities, countries, regions)
- Experience level filtering (junior, mid, senior, lead)
- Language requirements
- Industry experience

**Score breakdown:** Click the ℹ️ icon next to each result to see how the score was calculated (semantic similarity, must-have skills, location match, etc.)

### Add Additional Users

Keycloak admin console:
```bash
echo "Keycloak URL: https://$(oc get route keycloak -n peoplemesh-quickstart -o jsonpath='{.spec.host}')"
# Default admin credentials are auto-generated - check keycloak-admin-secret
```

## Advanced Configuration

### External LLM Provider

Use OpenAI or another provider instead of local Ollama (no GPU required):

```bash
helm install peoplemesh . \
  --namespace peoplemesh-quickstart \
  --create-namespace \
  --set ollama.enabled=false \
  --set peoplemesh.llm.mode=external \
  --set peoplemesh.llm.external.baseUrl="https://api.openai.com/v1" \
  --set peoplemesh.llm.external.apiKey="sk-your-key-here" \
  --set peoplemesh.llm.external.chatModel="gpt-4o-mini" \
  # ... other required secrets
```

### Custom Organization Branding

```bash
--set peoplemesh.organization.name="Acme Corporation" \
--set peoplemesh.organization.contactEmail="admin@acme.com" \
--set peoplemesh.organization.dataLocation="United States" \
--set peoplemesh.organization.governingLaw="State of California"
```

### Additional OIDC Providers

Enable Google or Microsoft authentication alongside Keycloak:

```bash
--set peoplemesh.oidc.google.clientId="your-google-client-id" \
--set peoplemesh.oidc.google.clientSecret="your-google-secret" \
--set peoplemesh.oidc.microsoft.clientId="your-microsoft-client-id" \
--set peoplemesh.oidc.microsoft.clientSecret="your-microsoft-secret"
```

See [INSTALL.md](INSTALL.md) for complete configuration reference.

## Reference

**Project Documentation:**
- [Installation Guide](INSTALL.md) - Complete installation reference with all configuration options
- [GPU Setup Guide](GPU-SETUP.md) - Detailed GPU configuration and troubleshooting
- [Deployment Summary](QUICKSTART-SUMMARY.md) - Architecture decisions and design rationale
- [Logout Fix Documentation](LOGOUT-FIX.md) - OIDC logout implementation details

**Upstream Projects:**
- [Peoplemesh GitHub](https://github.com/francescopace/peoplemesh) - Main application repository
- [Peoplemesh Documentation](https://github.com/francescopace/peoplemesh/blob/main/docs/how-to/deploy-openshift-helm.md) - Upstream deployment guide
- [Keycloak Documentation](https://www.keycloak.org/documentation) - Authentication server docs
- [Red Hat build of Keycloak](https://access.redhat.com/products/red-hat-build-of-keycloak) - Enterprise Keycloak

**Technologies:**
- [pgvector](https://github.com/pgvector/pgvector) - PostgreSQL extension for vector similarity search
- [Ollama](https://ollama.ai/) - Local LLM runtime
- [Docling](https://github.com/DS4SD/docling) - Document processing
- [LangChain4j](https://docs.langchain4j.dev/) - Java LLM framework

**Related AI Quickstarts:**
- [OpenShift AI Quickstarts](https://ai-on-openshift.io/odh-rhoai/configuration/) - Additional AI deployment patterns
- [Red Hat AI Quickstart Catalog](https://github.com/rh-ai-quickstart) - Browse all quickstarts

## Tags

**Industry:** Human Resources, Talent Management, Organizational Development
**Use Cases:** Talent Discovery, Skills Management, Team Building, Knowledge Management
**Technologies:** Vector Search, Semantic Search, LLM, RAG, OIDC Authentication
**AI/ML:** Natural Language Processing, Embeddings, Retrieval-Augmented Generation
