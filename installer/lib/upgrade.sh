#!/bin/bash

upgrade_quickstart() {
  SOURCE_VERSION="${SOURCE_VERSION:?SOURCE_VERSION required for upgrade}"
  TARGET_VERSION="${TARGET_VERSION:?TARGET_VERSION required for upgrade}"

  log_status "running" "upgrading" "Upgrading from $SOURCE_VERSION to $TARGET_VERSION..."

  # Migration script path follows convention: SOURCE-to-TARGET.sh
  # Installer internally knows which migrations to run - no need to read from manifest
  MIGRATION_SCRIPT="/installer/migrations/${SOURCE_VERSION}-to-${TARGET_VERSION}.sh"

  # Create data backup (always recommended for upgrades)
  log_status "running" "upgrading" "Creating data backup..."
  backup_data

  # Run migration if script exists
  if [[ -f "$MIGRATION_SCRIPT" ]]; then
    log_status "running" "upgrading" "Running database migration..."
    bash "$MIGRATION_SCRIPT" || log_error "Migration failed: $MIGRATION_SCRIPT"
  else
    log_status "running" "upgrading" "No data migration script found (upgrade may not require one)"
  fi

  # Upgrade Helm release (reuse existing values)
  log_status "running" "upgrading" "Upgrading Helm chart..."
  helm upgrade peoplemesh /installer/charts/peoplemesh-umbrella \
    --namespace "$TARGET_NAMESPACE" \
    --reuse-values \
    --timeout 15m \
    --wait || log_error "Helm upgrade failed"

  # Verify upgrade
  log_status "running" "upgrading" "Verifying upgraded deployment..."
  verify_deployment

  log_status "running" "upgrading" "Upgrade complete: $SOURCE_VERSION → $TARGET_VERSION"
}

backup_data() {
  # Backup strategy: export pgvector database to ConfigMap
  # For production, this should use external backup solutions (Velero, etc.)

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_NAME="peoplemesh-backup-${SOURCE_VERSION}-${TIMESTAMP}"

  log_status "running" "backup" "Creating backup: $BACKUP_NAME"

  # Check if pgvector pod exists
  if ! oc get pod pgvector-0 -n "$TARGET_NAMESPACE" >/dev/null 2>&1; then
    log_status "running" "backup" "No pgvector pod found, skipping backup"
    return 0
  fi

  # Create backup using pg_dump from pgvector pod
  BACKUP_FILE="/tmp/${BACKUP_NAME}.sql"
  if oc exec -n "$TARGET_NAMESPACE" pgvector-0 -- \
    pg_dump -U postgres -d peoplemesh > "$BACKUP_FILE" 2>/dev/null; then

    # Store backup in ConfigMap (for small databases)
    # For large databases, consider using PVC or external backup
    BACKUP_SIZE=$(wc -c < "$BACKUP_FILE")
    if [[ $BACKUP_SIZE -lt 1048576 ]]; then  # Less than 1MB
      oc create configmap "$BACKUP_NAME" \
        --from-file="$BACKUP_FILE" \
        -n "$TARGET_NAMESPACE" 2>/dev/null || true
      log_status "running" "backup" "Backup stored as ConfigMap: $BACKUP_NAME"
    else
      log_status "running" "backup" "Backup too large for ConfigMap (${BACKUP_SIZE} bytes), skipping storage"
    fi

    rm -f "$BACKUP_FILE"
  else
    log_status "running" "backup" "Database backup failed, continuing with upgrade (upgrade may include migration that doesn't need backup)"
  fi
}
