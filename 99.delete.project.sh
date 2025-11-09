#!/bin/bash

# Script to destroy OpenShift project "Demo RH AI 3.0"
# This script deletes the project and waits for it to be fully removed

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

# Maximum wait time in seconds (default: 5 minutes)
MAX_WAIT_TIME="${MAX_WAIT_TIME:-300}"
# Polling interval in seconds
POLL_INTERVAL="${POLL_INTERVAL:-5}"

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

# Check if we can connect to the cluster
if ! oc cluster-info &> /dev/null; then
    print_error "Cannot connect to OpenShift cluster. Please check your connection."
    exit 1
fi

# Check if project exists
PROJECT_CHECK=$(oc get project "${PROJECT_NAME}" 2>&1)
PROJECT_CHECK_EXIT=$?

if [ ${PROJECT_CHECK_EXIT} -ne 0 ]; then
    # Check if it's a "not found" error vs a connection error
    if echo "${PROJECT_CHECK}" | grep -q "NotFound\|not found"; then
        print_warning "Project ${PROJECT_NAME} does not exist. Nothing to delete."
        exit 0
    else
        print_error "Error checking project: ${PROJECT_CHECK}"
        exit 1
    fi
fi

print_status "Deleting OpenShift project: ${PROJECT_NAME} (${DISPLAY_NAME})"

# Delete the project
if oc delete project "${PROJECT_NAME}" &> /dev/null; then
    print_success "Project deletion initiated for ${PROJECT_NAME}"
else
    print_error "Failed to initiate deletion of project ${PROJECT_NAME}"
    exit 1
fi

# Wait for project to be fully deleted
print_status "Waiting for project to be fully deleted..."
print_status "This may take a few minutes. Maximum wait time: ${MAX_WAIT_TIME} seconds"

ELAPSED_TIME=0
while [ ${ELAPSED_TIME} -lt ${MAX_WAIT_TIME} ]; do
    if ! oc get project "${PROJECT_NAME}" &> /dev/null; then
        print_success "Project ${PROJECT_NAME} has been fully deleted!"
        exit 0
    fi

    # Show progress every 30 seconds
    if [ $((ELAPSED_TIME % 30)) -eq 0 ] && [ ${ELAPSED_TIME} -gt 0 ]; then
        print_status "Still waiting... (${ELAPSED_TIME}/${MAX_WAIT_TIME} seconds elapsed)"
    fi

    sleep ${POLL_INTERVAL}
    ELAPSED_TIME=$((ELAPSED_TIME + POLL_INTERVAL))
done

# Check one more time
if ! oc get project "${PROJECT_NAME}" &> /dev/null; then
    print_success "Project ${PROJECT_NAME} has been fully deleted!"
    exit 0
else
    print_warning "Project ${PROJECT_NAME} still exists after ${MAX_WAIT_TIME} seconds."
    print_warning "The project may still be in the process of deletion."
    print_status "You can check the status manually with: oc get project ${PROJECT_NAME}"
    exit 1
fi

