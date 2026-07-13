# Building the Peoplemesh Container Image

The peoplemesh project doesn't publish pre-built container images. You need to build it yourself.

## Option 1: Using Multi-Stage Docker Build (Recommended)

This builds everything from source in one `podman build` command:

```bash
# Clone the repository
git clone https://github.com/francescopace/peoplemesh.git
cd peoplemesh

# Create a multi-stage Dockerfile
cat > Dockerfile.build <<'EOF'
# Stage 1: Build with Maven
FROM registry.access.redhat.com/ubi9/openjdk-25:latest AS builder
USER root
RUN microdnf install -y maven
WORKDIR /build
COPY . .
RUN mvn clean package -DskipTests

# Stage 2: Runtime
FROM registry.access.redhat.com/ubi9/openjdk-25-runtime:latest
COPY --from=builder --chown=185 /build/target/quarkus-app/lib/ /deployments/lib/
COPY --from=builder --chown=185 /build/target/quarkus-app/*.jar /deployments/
COPY --from=builder --chown=185 /build/target/quarkus-app/app/ /deployments/app/
COPY --from=builder --chown=185 /build/target/quarkus-app/quarkus/ /deployments/quarkus/
COPY --from=builder --chown=185 /build/src/main/web/ /deployments/src/main/web/

EXPOSE 8080
USER 185
ENV JAVA_OPTS_APPEND="-Dquarkus.http.host=0.0.0.0 -Dquarkus.http.port=8080"
ENV JAVA_APP_JAR="/deployments/quarkus-run.jar"
ENTRYPOINT [ "/opt/jboss/container/java/run/run-java.sh" ]
EOF

# Build the container image (no Maven install needed!)
podman build -f Dockerfile.build -t quay.io/YOUR_USERNAME/peoplemesh:latest .

# Push to registry
podman login quay.io
podman push quay.io/YOUR_USERNAME/peoplemesh:latest
```

## Option 2: Using Make + Existing Dockerfile (Requires Maven)

The repo has a Dockerfile at `src/main/docker/Dockerfile.jvm` but it expects pre-built artifacts:

```bash
# Prerequisites: Install Maven 3.9+ and Java 25+
# Clone and build the JAR
git clone https://github.com/francescopace/peoplemesh.git
cd peoplemesh
make build  # or: mvn clean package

# Build the container image
podman build -f src/main/docker/Dockerfile.jvm -t quay.io/YOUR_USERNAME/peoplemesh:latest .

# Push to registry
podman login quay.io
podman push quay.io/YOUR_USERNAME/peoplemesh:latest
```

## Option 3: OpenShift BuildConfig (Build on Cluster)

Create a BuildConfig to build the image directly on OpenShift:

```bash
# Create build from Git source
oc new-build https://github.com/francescopace/peoplemesh.git \
  --name=peoplemesh \
  --strategy=docker \
  --dockerfile=- <<'EOF'
FROM registry.access.redhat.com/ubi9/openjdk-25:latest AS builder
USER root
RUN microdnf install -y maven git
WORKDIR /build
RUN git clone https://github.com/francescopace/peoplemesh.git .
RUN mvn clean package -DskipTests

FROM registry.access.redhat.com/ubi9/openjdk-25-runtime:latest
COPY --from=builder --chown=185 /build/target/quarkus-app/lib/ /deployments/lib/
COPY --from=builder --chown=185 /build/target/quarkus-app/*.jar /deployments/
COPY --from=builder --chown=185 /build/target/quarkus-app/app/ /deployments/app/
COPY --from=builder --chown=185 /build/target/quarkus-app/quarkus/ /deployments/quarkus/
COPY --from=builder --chown=185 /build/src/main/web/ /deployments/src/main/web/

EXPOSE 8080
USER 185
ENV JAVA_OPTS_APPEND="-Dquarkus.http.host=0.0.0.0 -Dquarkus.http.port=8080"
ENV JAVA_APP_JAR="/deployments/quarkus-run.jar"
ENTRYPOINT [ "/opt/jboss/container/java/run/run-java.sh" ]
EOF

# Wait for build to complete
oc logs -f bc/peoplemesh

# Get the image stream reference
oc get imagestream peoplemesh -o jsonpath='{.status.dockerImageRepository}'
```

Then update your Helm values:

```yaml
peoplemesh:
  image:
    repository: image-registry.openshift-image-registry.svc:5000/peoplemesh/peoplemesh
    tag: latest
    pullPolicy: Always
```

## Update Helm Chart

Once you've built and pushed the image, update the installation:

```bash
helm upgrade peoplemesh peoplemesh-umbrella/ \
  --namespace peoplemesh \
  --set peoplemesh.image.repository=quay.io/YOUR_USERNAME/peoplemesh \
  --set peoplemesh.image.tag=latest \
  --reuse-values
```
