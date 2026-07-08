FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Install required tools
RUN microdnf install -y \
    python3 \
    python3-pip \
    curl \
    jq \
    tar \
    gzip \
    bc \
    && microdnf clean all

# Install oc CLI
RUN curl -L https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz | \
    tar -xzv -C /usr/local/bin/ oc && \
    chmod +x /usr/local/bin/oc

# Install Helm
RUN curl -L https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz | \
    tar -xzv -C /tmp && \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    rm -rf /tmp/linux-amd64

# Copy installer scripts
COPY installer/entrypoint.sh /installer/entrypoint.sh
COPY installer/lib/ /installer/lib/
RUN chmod +x /installer/entrypoint.sh /installer/lib/*.sh

# Copy migration scripts
COPY installer/migrations/ /installer/migrations/
RUN find /installer/migrations/ -type f -name "*.sh" -exec chmod +x {} \;

# Copy bundled Helm chart
# Note: This assumes the peoplemesh-umbrella chart is at the root of the repo
COPY peoplemesh-umbrella/ /installer/charts/peoplemesh-umbrella/

# Copy manifest
COPY quickstart-manifest.yaml /installer/manifest.yaml

# Set working directory
WORKDIR /installer

# Entrypoint
ENTRYPOINT ["/installer/entrypoint.sh"]
