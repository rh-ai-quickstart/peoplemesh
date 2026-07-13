#!/bin/bash

# Common constants shared across installer scripts
# Guard against multiple sourcing
if [[ -n "${_INSTALLER_COMMON_SOURCED:-}" ]]; then
  return 0
fi
readonly _INSTALLER_COMMON_SOURCED=1

# OLM resource names (fully qualified to avoid conflicts)
readonly OLM_SUBSCRIPTION_RESOURCE="subscriptions.operators.coreos.com"
readonly OLM_CSV_RESOURCE="clusterserviceversions.operators.coreos.com"
readonly OLM_OPERATORGROUP_RESOURCE="operatorgroups.operators.coreos.com"

# Keycloak operator constants
readonly KEYCLOAK_OPERATOR_NAME="rhbk-operator"
readonly KEYCLOAK_OPERATOR_CHANNEL="stable-v26"
readonly KEYCLOAK_OPERATOR_MIN_VERSION="rhbk-operator.v26.6.4-opr.1"
readonly KEYCLOAK_OPERATOR_YAML="/installer/operators/keycloak.yaml"
