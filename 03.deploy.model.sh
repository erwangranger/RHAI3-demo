#!/bin/bash

# Script to deploy LLM model to OpenShift project
# This script creates the required secret and deploys the model
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

# Configuration
PROJECT_NAME="${OC_PROJECT:-${PROJECT_NAME:-demo-rh-ai-3-0}}"
MODELS_DIR="${MODELS_DIR:-${SCRIPT_DIR}/models}"
SECRETS_DIR="${SECRETS_DIR:-${SCRIPT_DIR}/secrets}"
MODEL_FILE="${MODEL_FILE:-llmd.yaml}"

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

# Function to create secret if it doesn't exist
create_secret_if_needed() {
    local secret_name="$1"
    local uri="$2"
    local description="$3"

    print_status "Checking if secret ${secret_name} exists..."

    if oc get secret "$secret_name" -n "$PROJECT_NAME" &> /dev/null; then
        print_warning "Secret ${secret_name} already exists. Skipping creation."
        return 0
    fi

    print_status "Creating secret ${secret_name}..."

    # Base64 encode the URI
    local encoded_uri=$(echo -n "$uri" | base64)

    # Create secret YAML
    local secret_yaml=$(cat <<EOF
kind: Secret
apiVersion: v1
metadata:
  name: ${secret_name}
  labels:
    opendatahub.io/dashboard: 'true'
  annotations:
    opendatahub.io/connection-type-protocol: uri
    opendatahub.io/connection-type-ref: uri-v1
    openshift.io/description: '${description}'
    openshift.io/display-name: '${description}'
data:
  URI: ${encoded_uri}
type: Opaque
EOF
)

    # Apply the secret
    if echo "$secret_yaml" | oc apply -f - -n "$PROJECT_NAME" &> /dev/null; then
        print_success "Secret ${secret_name} created successfully"
        return 0
    else
        print_error "Failed to create secret ${secret_name}"
        return 1
    fi
}

# Function to deploy model
deploy_model() {
    local model_file="$1"

    if [ ! -f "$model_file" ]; then
        print_error "Model file not found: ${model_file}"
        return 1
    fi

    print_status "Deploying model from ${model_file}..."

    # Extract model name from YAML
    local model_name=$(grep -E "^  name:" "$model_file" | head -1 | awk '{print $2}' | tr -d "'\"")

    if [ -z "$model_name" ]; then
        print_error "Could not extract model name from ${model_file}"
        return 1
    fi

    print_status "Deploying LLMInferenceService: ${model_name}"

    if oc apply -f "$model_file" -n "$PROJECT_NAME" &> /dev/null; then
        print_success "Model ${model_name} deployed successfully"
        return 0
    else
        local apply_output=$(oc apply -f "$model_file" -n "$PROJECT_NAME" 2>&1)
        print_error "Failed to deploy model ${model_name}"
        echo "$apply_output" | sed 's/^/  /'
        return 1
    fi
}

# Main execution
main() {
    print_status "Starting model deployment..."
    print_status "Project: ${PROJECT_NAME}"

    # Check if project exists
    if ! oc get project "$PROJECT_NAME" &> /dev/null; then
        print_error "Project ${PROJECT_NAME} does not exist. Please create it first."
        exit 1
    fi

    # Switch to project
    oc project "$PROJECT_NAME" &> /dev/null || true

    # Get model file path
    local model_path="${MODELS_DIR}/${MODEL_FILE}"

    if [ ! -f "$model_path" ]; then
        print_error "Model file not found: ${model_path}"
        exit 1
    fi

    # Extract connection secret name and URI from model file
    local connection_secret=$(grep -E "opendatahub.io/connections:" "$model_path" | awk '{print $2}' | tr -d "'\"")
    local model_uri=$(grep -E "uri:" "$model_path" | awk '{print $2}' | tr -d "'\"")

    if [ -z "$connection_secret" ]; then
        print_warning "No connection secret specified in model file. Skipping secret creation."
    else
        # Extract description from URI (model name and tag)
        local description=""
        if [ -n "$model_uri" ]; then
            # Extract from URI like oci://quay.io/redhat-ai-services/modelcar-catalog:llama-3.2-3b-instruct
            description=$(echo "$model_uri" | sed 's|.*:||' | sed 's|.*/||')
        fi

        if [ -z "$description" ]; then
            description="$connection_secret"
        fi

        # Create secret if needed
        if ! create_secret_if_needed "$connection_secret" "$model_uri" "$description"; then
            print_error "Failed to create required secret. Aborting deployment."
            exit 1
        fi
    fi

    # Deploy the model
    if ! deploy_model "$model_path"; then
        print_error "Failed to deploy model. Aborting."
        exit 1
    fi

    echo ""
    print_success "Model deployment complete!"
    print_status "Check status with: oc get llminferenceservice -n ${PROJECT_NAME}"
    print_status "Check pods with: oc get pods -n ${PROJECT_NAME} | grep ${model_name}"
}

# Run main function
main

