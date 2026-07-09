# Typical Deployment Sequence for Peoplemesh

## Sequence Diagram

```mermaid
sequenceDiagram
    actor User
    participant Navigator as Navigator<br/>(AI Chat Interface)
    participant Registry as Quickstart<br/>Registry
    participant Manifest as quickstart-manifest.yaml
    participant Cluster as OpenShift<br/>Cluster
    participant Job as Installer Job<br/>(Container)

    %% Step 1-2: Discovery
    User->>Navigator: "I need a quickstart that connects<br/>people and skills"
    activate Navigator
    Navigator->>Registry: Query available quickstarts
    activate Registry
    Registry-->>Navigator: List of quickstarts with metadata
    deactivate Registry
    Note over Navigator: Analyzes descriptions, tags,<br/>and use cases to find matches

    %% Step 3: Learn about quickstart
    Navigator->>Manifest: Read peoplemesh-quickstart manifest
    activate Manifest
    Manifest-->>Navigator: Prerequisites, parameters,<br/>deployment config
    deactivate Manifest
    Note over Navigator: Learns:<br/>- Requires Keycloak Operator<br/>- Needs test password<br/>- Optional GPU settings

    %% Step 4: Validate prerequisites
    Navigator->>Cluster: Check prerequisites
    activate Cluster
    Cluster-->>Navigator: Keycloak Operator status
    Cluster-->>Navigator: Available resources
    Cluster-->>Navigator: Storage classes
    deactivate Cluster
    Note over Navigator: Validates:<br/>- Operator installed<br/>- Sufficient resources<br/>- Storage available

    %% Step 5-6: Recommend and get approval
    Navigator->>User: "Peoplemesh is a great fit!<br/>Connects people via semantic search.<br/>Install?"
    deactivate Navigator
    User->>Navigator: "Yes, install it"
    activate Navigator

    %% Step 7-8: Gather parameters
    Navigator->>User: "Please provide:<br/>- Test user password<br/>- Enable GPU? (optional)<br/>- Organization name? (optional)"
    deactivate Navigator
    User->>Navigator: "Password: MySecure123<br/>Enable GPU: true<br/>Org: Acme Corp"
    activate Navigator
    Note over Navigator: Validates inputs,<br/>generates remaining secrets

    %% Step 9: Create installer job
    Navigator->>Cluster: Create Job with installer image
    activate Cluster
    Note over Cluster: Job spec:<br/>- Image: peoplemesh-installer:1.0.0<br/>- Env: ACTION=install<br/>- Env: PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD=***<br/>- Env: PARAM_OLLAMA_GPU_ENABLED=true<br/>- Env: TARGET_NAMESPACE=peoplemesh-quickstart
    Cluster->>Job: Start installer container
    deactivate Cluster
    activate Job

    %% Step 10: Monitor installation (multiple approaches)
    Note over Navigator,Job: Installation Progress Monitoring<br/>(Multiple approaches available)
    
    par Monitor via Job Logs
        Job-->>Navigator: Stream JSON logs<br/>{"status":"running","phase":"deploying",...}
    and Monitor via Status Endpoint
        loop Every 10 seconds
            Navigator->>Cluster: Query peoplemesh status endpoint<br/>GET /api/v1/quickstart/status
            Cluster-->>Navigator: {"status":"INSTALLING","description":"..."}
        end
    and Monitor via Job Status
        loop Until complete
            Navigator->>Cluster: Get Job status
            Cluster-->>Navigator: Job phase and conditions
        end
    end

    Job->>Cluster: Deploy Helm chart
    Note over Job: - Generates secrets<br/>- Runs helm install<br/>- Waits for pods

    Job-->>Navigator: {"status":"success","endpoints":[...]}
    deactivate Job
    
    Navigator->>User: "✅ Peoplemesh installed!<br/>URL: https://peoplemesh-...<br/>Login: testuser@example.com"
    deactivate Navigator
```

## Key Points

### Discovery Phase (Steps 1-3)
- Navigator uses **semantic understanding** to match user intent with quickstart capabilities
- **Registry** provides high-level metadata (tags, descriptions, use cases)
- **Manifest** provides detailed deployment requirements and configuration
- Navigator conserves its context by retrieving only the manifests it needs 

### Validation Phase (Step 4)
Navigator checks cluster state before suggesting installation:
- Required operators (Keycloak Operator in target namespace)
- Resource availability (CPU, memory, GPU if requested)
- Storage classes (ReadWriteOnce volumes)
- OpenShift version compatibility

### Parameter Collection (Steps 7-8)
Navigator asks for **minimal user input**:
- It's not necessary to expose every deployment option the quickstart has.
- Quickstarts can simplify their parameter surface by wrapper helm, etc. with a shell script (this is an internal quickstart detail)
- **Required**: Test user password (for demo login)
- **Optional**: GPU acceleration flags
- **Optional**: Organization customization
- **Auto-generated**: All 6 internal secrets (DB passwords, encryption keys)

### Installation Execution (Step 9)
Navigator creates a Kubernetes **Job** that runs the installer container:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: peoplemesh-installer-xyz
  namespace: navigator-system
spec:
  template:
    spec:
      containers:
      - name: installer
        image: ghcr.io/rh-ai-quickstart/peoplemesh-installer:1.0.0
        env:
        - name: ACTION
          value: "install"
        - name: TARGET_NAMESPACE
          value: "peoplemesh-quickstart"
        - name: INSTALL_MODE
          value: "demo"
        - name: PARAM_KEYCLOAK_REALM_TESTUSER_PASSWORD
          value: "MyPassword"
        - name: PARAM_OLLAMA_GPU_ENABLED
          value: "true"
      restartPolicy: Never
```

### Progress Monitoring (Step 10)
Navigator has **multiple approaches** to monitor installation progress:

#### 1. **Job Log Streaming** (Real-time)
- Installer outputs structured JSON to stdout
- Navigator streams and parses log lines
- Example: `{"status":"running","phase":"deploying","message":"Installing Helm chart..."}`

#### 2. **Status Endpoint Polling** (Post-deployment)
- After pods are running, query `/api/v1/quickstart/status`
- Returns operational health of deployed components
- Defined in `quickstart-manifest.yaml` status section

#### 3. **Job Status API** (Kubernetes-native)
- Query Job resource conditions and phase
- Reliable but less detailed than structured logs

**Recommended**: Combine approaches:
- Use **log streaming** during active installation
- Use **status endpoint** for ongoing health monitoring
- Use **Job status** as fallback/validation
- Do we need the status deployment action?

## Error Handling

If installation fails, Navigator receives error details via:
1. **Job logs**: `{"status":"error","message":"Keycloak Operator not found"}`
2. **Job status**: `Failed` condition with reason
3. **Exit code**: Container exit code (0=success, 1=error, 2=prerequisites failed)

Navigator can then:
- Report specific error to user
- Suggest remediation (e.g., "Install Keycloak Operator first")
- Offer to retry or clean up

## Prerequisites Not Met

If prerequisites check fails (Step 4):

```mermaid
sequenceDiagram
    Navigator->>Cluster: Check for Keycloak Operator
    Cluster-->>Navigator: Not found in target namespace
    Navigator->>User: "⚠️ Keycloak Operator required.<br/>Install from OperatorHub?<br/>(peoplemesh-quickstart namespace)"
    User->>Navigator: "Yes, install it"
    Navigator->>User: "Opening OperatorHub installation guide..."
```

Navigator guides user through prerequisite installation before proceeding.