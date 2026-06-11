# Architecture Diagram

Since this is a text-based environment, here's a Mermaid diagram that should be converted to PNG for the README:

```mermaid
graph TB
    subgraph "OpenShift Namespace: peoplemesh-quickstart"
        subgraph "Frontend & API"
            UI[Peoplemesh UI<br/>React SPA]
            API[Peoplemesh API<br/>Quarkus REST]
        end
        
        subgraph "Authentication"
            KC[Keycloak Server<br/>OIDC Provider]
            KCDB[(Keycloak DB<br/>PostgreSQL<br/>10Gi PVC)]
        end
        
        subgraph "AI Services"
            LLM[Ollama<br/>Granite 3B<br/>CPU or GPU]
            DOC[Docling<br/>Document Parser<br/>CPU or GPU]
        end
        
        subgraph "Data Layer"
            PGVEC[(PgVector DB<br/>PostgreSQL + pgvector<br/>50Gi PVC)]
        end
        
        USER[👤 User] -->|HTTPS| ROUTE[OpenShift Route]
        ROUTE -->|TLS Termination| UI
        UI -->|API Calls| API
        
        API -->|OIDC Auth| KC
        KC -->|User Data| KCDB
        
        API -->|Query Parsing<br/>CV Structuring| LLM
        API -->|Resume Parsing| DOC
        API -->|Vector Search<br/>Profile Storage| PGVEC
        
        LLM -.->|Optional| GPU1[🎮 NVIDIA GPU<br/>A10G 23GB]
        DOC -.->|Optional| GPU2[🎮 NVIDIA GPU<br/>A10G 23GB]
    end
    
    style USER fill:#e1f5ff
    style ROUTE fill:#fff3e0
    style UI fill:#c8e6c9
    style API fill:#c8e6c9
    style KC fill:#ffe0b2
    style LLM fill:#f8bbd0
    style DOC fill:#f8bbd0
    style PGVEC fill:#d1c4e9
    style KCDB fill:#d1c4e9
    style GPU1 fill:#ffccbc
    style GPU2 fill:#ffccbc
```

## Component Details

**Peoplemesh Application:**
- Frontend: React single-page application
- Backend: Quarkus (Java) REST API
- Handles search queries, profile management, authentication flow

**Keycloak:**
- OIDC authentication provider
- User management and SSO
- Supports multiple identity providers (Google, Microsoft, etc.)

**Ollama:**
- Local LLM runtime (Granite 3B model)
- Parses search queries into structured filters
- Extracts structured data from résumé text
- Optional GPU acceleration (10-20x faster)

**Docling:**
- Converts PDFs/DOCX to markdown text
- Extracts text from résumés
- Optional GPU acceleration for faster processing

**PgVector Database:**
- PostgreSQL with pgvector extension
- Stores user profiles and vector embeddings
- Semantic similarity search using cosine distance

**Data Flow:**

1. **Search Flow:**
   ```
   User → UI → API → Ollama (parse query) → PgVector (vector search) → API → UI
   ```

2. **Resume Upload Flow:**
   ```
   User → UI → API → Docling (PDF→text) → Ollama (text→structured) → PgVector (store) → API → UI
   ```

3. **Authentication Flow:**
   ```
   User → UI → Keycloak (login) → OIDC callback → API (session) → UI
   ```

## Deployment Options

**CPU-Only Mode:**
- Works on any OpenShift cluster
- No GPU required
- Resume processing: 2-3 minutes per upload
- Search queries: 5-10 seconds

**GPU Mode:**
- Requires NVIDIA GPU nodes
- Resume processing: 10-20 seconds per upload
- Search queries: 1-2 seconds
- Both Ollama and Docling can share same GPU or use separate GPUs

## Network Flow

```
Internet
   ↓
OpenShift Router (HAProxy)
   ↓
Route (TLS termination)
   ↓
Service (ClusterIP)
   ↓
Pod (Peoplemesh)
   ↓
Internal Services (Keycloak, Ollama, Docling, PgVector)
```

All external traffic goes through HTTPS. Internal traffic uses ClusterIP services within the namespace.
