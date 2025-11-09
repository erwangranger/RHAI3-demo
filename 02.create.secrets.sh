#!/bin/bash

# Script to generate Kubernetes Secret YAML files from OCI registry URIs
# This script extracts model names from URIs and creates properly formatted secrets
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
SECRETS_DIR="${SECRETS_DIR:-${SCRIPT_DIR}/secrets}"
PROJECT_NAME="${OC_PROJECT:-${PROJECT_NAME:-demo-rh-ai-3-0}}"
APPLY_SECRETS="${APPLY_SECRETS:-true}"

# Array of URIs to process
URIS=(
    "oci://registry.redhat.io/rhelai1/modelcar-granite-8b-lab-v1:1.4.0"
    "oci://registry.redhat.io/rhelai1/modelcar-qwen2-5-7b-instruct-fp8-dynamic:1.5"
    "oci://registry.redhat.io/rhelai1/modelcar-mistral-small-24b-instruct-2501:1.5"
    "oci://registry.redhat.io/rhelai1/modelcar-kimi-k2-instruct-quantized-w4a16:1.5"
    "oci://registry.redhat.io/rhelai1/modelcar-llama-3-1-8b-instruct-fp8-dynamic:1.5"
)

# Function to extract model name and tag from URI
# Input: oci://registry.redhat.io/rhelai1/modelcar-{model-name}:{tag}
# Output: model_name (without modelcar- prefix) and tag
extract_model_info() {
    local uri="$1"

    # Extract the image name with tag (everything after the last /)
    local image_with_tag="${uri##*/}"

    # Check if URI contains modelcar- prefix
    if [[ "$image_with_tag" != modelcar-* ]]; then
        print_error "URI does not contain 'modelcar-' prefix: $uri"
        return 1
    fi

    # Remove modelcar- prefix
    local model_with_tag="${image_with_tag#modelcar-}"

    # Extract model name (before :) and tag (after :)
    if [[ "$model_with_tag" == *:* ]]; then
        MODEL_NAME="${model_with_tag%%:*}"
        TAG="${model_with_tag##*:}"
    else
        MODEL_NAME="$model_with_tag"
        TAG=""
    fi
}

# Function to generate secret name from model name and tag
# Removes dots from tag and appends with hyphen separator
generate_secret_name() {
    local model_name="$1"
    local tag="$2"

    if [ -n "$tag" ]; then
        # Remove dots and colons from tag, then append with hyphen
        local tag_cleaned=$(echo "$tag" | tr -d '.:')
        SECRET_NAME="${model_name}-${tag_cleaned}"
    else
        SECRET_NAME="$model_name"
    fi
}

# Function to generate description from model name and tag
# Keeps the tag with : separator
generate_description() {
    local model_name="$1"
    local tag="$2"

    if [ -n "$tag" ]; then
        DESCRIPTION="${model_name}:${tag}"
    else
        DESCRIPTION="$model_name"
    fi
}

# Function to base64 encode URI
encode_uri() {
    local uri="$1"
    ENCODED_URI=$(echo -n "$uri" | base64)
}

# Function to generate YAML file for a secret
generate_secret_yaml() {
    local uri="$1"
    local secret_name="$2"
    local description="$3"
    local encoded_uri="$4"
    local output_file="${SECRETS_DIR}/${secret_name}.yaml"

    print_status "Generating secret YAML: ${output_file}" >&2

    cat > "$output_file" <<EOF
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

    print_success "Secret YAML generated: ${output_file}" >&2
    echo "$output_file"
}

# Function to apply secret to OpenShift project
apply_secret() {
    local yaml_file="$1"
    local secret_name="$2"

    if [ "$APPLY_SECRETS" != "true" ]; then
        print_status "Skipping secret application (APPLY_SECRETS=false)"
        return 0
    fi

    # Check if oc command is available
    if ! command -v oc &> /dev/null; then
        print_warning "oc command not found. Skipping secret application."
        return 1
    fi

    # Check if user is logged in to OpenShift
    if ! oc whoami &> /dev/null; then
        print_warning "Not logged in to OpenShift. Skipping secret application."
        return 1
    fi

    print_status "Applying secret ${secret_name} to project ${PROJECT_NAME}..."

    local apply_output
    apply_output=$(oc apply -f "$yaml_file" -n "$PROJECT_NAME" 2>&1)
    local apply_exit=$?

    if [ $apply_exit -eq 0 ]; then
        print_success "Secret ${secret_name} applied successfully to project ${PROJECT_NAME}"
        return 0
    else
        print_error "Failed to apply secret ${secret_name} to project ${PROJECT_NAME}"
        echo "$apply_output" | sed 's/^/  /'
        return 1
    fi
}

# Main execution
main() {
    print_status "Starting secret generation..."

    # Create secrets directory if it doesn't exist
    if [ ! -d "$SECRETS_DIR" ]; then
        print_status "Creating secrets directory: ${SECRETS_DIR}"
        mkdir -p "$SECRETS_DIR"
    fi

    # Display project information if applying
    if [ "$APPLY_SECRETS" = "true" ]; then
        if command -v oc &> /dev/null && oc whoami &> /dev/null; then
            local current_project=$(oc project -q 2>/dev/null || echo "$PROJECT_NAME")
            print_status "Secrets will be applied to project: ${current_project}"
        else
            print_warning "oc command not available or not logged in. Secrets will only be generated as YAML files."
            APPLY_SECRETS="false"
        fi
    fi

    local applied_count=0
    local generated_count=0

    # Process each URI
    for uri in "${URIS[@]}"; do
        print_status "Processing URI: ${uri}"

        # Extract model information
        if ! extract_model_info "$uri"; then
            print_error "Failed to extract model info from URI: $uri"
            continue
        fi

        # Generate secret name
        generate_secret_name "$MODEL_NAME" "$TAG"

        # Generate description
        generate_description "$MODEL_NAME" "$TAG"

        # Encode URI
        encode_uri "$uri"

        # Generate YAML file
        local yaml_file
        yaml_file=$(generate_secret_yaml "$uri" "$SECRET_NAME" "$DESCRIPTION" "$ENCODED_URI")
        generated_count=$((generated_count + 1))

        # Apply secret to OpenShift project
        if apply_secret "$yaml_file" "$SECRET_NAME"; then
            applied_count=$((applied_count + 1))
        fi

        echo ""
    done

    print_success "Secret generation complete!"
    print_status "Generated ${generated_count} secret(s) in ${SECRETS_DIR}"
    if [ "$APPLY_SECRETS" = "true" ]; then
        print_status "Applied ${applied_count} secret(s) to project ${PROJECT_NAME}"
    fi
}

# Run main function
main

