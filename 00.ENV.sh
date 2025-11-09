#!/bin/bash

# Environment variables for RHAI3-demo project setup
# Source this file before running other scripts: source 00.ENV.sh
# Or export variables: export $(cat 00.ENV.sh | grep -v '^#' | xargs)

# Project Configuration
export PROJECT_NAME="${PROJECT_NAME:-demo-rh-ai-3-0}"
export DISPLAY_NAME="${DISPLAY_NAME:-Demo RH AI 3.0}"
export REQUESTER="${REQUESTER:-${USER}@redhat.com}"

# Project Labels
export MODELMESH_ENABLED="${MODELMESH_ENABLED:-false}"
export ODH_DASHBOARD_ENABLED="${ODH_DASHBOARD_ENABLED:-true}"
export POD_SECURITY_AUDIT="${POD_SECURITY_AUDIT:-baseline}"
export POD_SECURITY_AUDIT_VERSION="${POD_SECURITY_AUDIT_VERSION:-latest}"
export POD_SECURITY_WARN="${POD_SECURITY_WARN:-baseline}"
export POD_SECURITY_WARN_VERSION="${POD_SECURITY_WARN_VERSION:-latest}"

# Project Deletion Configuration
export MAX_WAIT_TIME="${MAX_WAIT_TIME:-300}"
export POLL_INTERVAL="${POLL_INTERVAL:-5}"

# OpenShift Configuration
export OC_PROJECT="${OC_PROJECT:-${PROJECT_NAME}}"

# Secrets Configuration
export SECRETS_DIR="${SECRETS_DIR:-secrets}"

# Output Configuration
export VERBOSE="${VERBOSE:-false}"
export DRY_RUN="${DRY_RUN:-false}"

