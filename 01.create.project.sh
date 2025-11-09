#!/bin/bash

# Script to create OpenShift project "Demo RH AI 3.0"
# This script creates a project with the same configuration as the "erwan" project
# This script is idempotent - safe to run multiple times

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/00.ENV.sh" ]; then
    source "${SCRIPT_DIR}/00.ENV.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Project configuration (from environment variables)
# Defaults are set in 00.ENV.sh
PROJECT_NAME="${PROJECT_NAME:-demo-rh-ai-3-0}"
DISPLAY_NAME="${DISPLAY_NAME:-Demo RH AI 3.0}"
REQUESTER="${REQUESTER:-${USER}@redhat.com}"

# Check if oc command is available
if ! command -v oc &> /dev/null; then
    print_error "oc command not found. Please install the OpenShift CLI."
    exit 1
fi

# Check if user is logged in to OpenShift
if ! oc whoami &> /dev/null; then
    print_error "Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

# Check if project already exists
print_status "Checking if project ${PROJECT_NAME} exists..."
if oc get project "${PROJECT_NAME}" &> /dev/null; then
    print_warning "Project ${PROJECT_NAME} already exists. Ensuring configuration is up to date..."
    oc project "${PROJECT_NAME}" &> /dev/null || true
else
    # Create the project
    print_status "Creating OpenShift project: ${PROJECT_NAME}"
    if oc new-project "${PROJECT_NAME}" --display-name="${DISPLAY_NAME}" 2>/dev/null; then
        print_success "Project ${PROJECT_NAME} created successfully"
    else
        print_error "Failed to create project ${PROJECT_NAME}"
        exit 1
    fi
fi

# Apply labels (idempotent operation)
print_status "Applying labels to project..."

if oc label namespace "${PROJECT_NAME}" \
    kubernetes.io/metadata.name="${PROJECT_NAME}" \
    modelmesh-enabled="${MODELMESH_ENABLED:-false}" \
    opendatahub.io/dashboard="${ODH_DASHBOARD_ENABLED:-true}" \
    pod-security.kubernetes.io/audit="${POD_SECURITY_AUDIT:-baseline}" \
    pod-security.kubernetes.io/audit-version="${POD_SECURITY_AUDIT_VERSION:-latest}" \
    pod-security.kubernetes.io/warn="${POD_SECURITY_WARN:-baseline}" \
    pod-security.kubernetes.io/warn-version="${POD_SECURITY_WARN_VERSION:-latest}" \
    --overwrite &> /dev/null; then
    print_success "Labels applied successfully"
else
    print_warning "Some labels may have failed to apply, but continuing..."
fi

# Apply annotations (idempotent operation)
print_status "Applying annotations to project..."

if oc annotate namespace "${PROJECT_NAME}" \
    openshift.io/display-name="${DISPLAY_NAME}" \
    openshift.io/description="" \
    openshift.io/requester="${REQUESTER}" \
    --overwrite &> /dev/null; then
    print_success "Annotations applied successfully"
else
    print_warning "Some annotations may have failed to apply, but continuing..."
fi

# Display project information
print_status "Verifying project configuration..."
echo ""
if oc describe project "${PROJECT_NAME}" &> /dev/null; then
    print_status "Project details:"
    oc describe project "${PROJECT_NAME}"
    echo ""
    print_success "Setup complete! Project '${DISPLAY_NAME}' is ready to use."
else
    print_warning "Could not retrieve project details, but setup operations completed."
    print_success "Setup operations completed for project '${DISPLAY_NAME}'."
fi

