#!/bin/bash

# Script to find all pods that are using one GPU or more
# This script checks for GPU resource requests and limits in pods

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
ALL_NAMESPACES="${ALL_NAMESPACES:-true}"

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

# Main execution
main() {
    print_status "Finding pods using GPUs..."

    if [ "$ALL_NAMESPACES" = "true" ]; then
        print_status "Searching all namespaces..."
        NAMESPACE_ARG="-A"
    else
        print_status "Searching in project: ${PROJECT_NAME}"
        NAMESPACE_ARG="-n ${PROJECT_NAME}"
    fi

    # Use efficient jsonpath to extract GPU information directly
    # Format: namespace pod_name container_name request_gpu limit_gpu
    local gpu_data=$(oc get pods $NAMESPACE_ARG -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{"\t"}{.resources.requests.nvidia\.com/gpu}{"\t"}{.resources.limits.nvidia\.com/gpu}{"\n"}{end}{end}' 2>/dev/null)

    if [ -z "$gpu_data" ]; then
        print_warning "No pods found or failed to fetch pods."
        exit 0
    fi

    # Process the GPU data and aggregate by pod using awk
    # Format: namespace pod_name container_name request_gpu limit_gpu
    local aggregated_data=$(echo "$gpu_data" | awk -F'\t' '
    {
        namespace = $1
        pod_name = $2
        container_name = $3
        request_gpu = $4
        limit_gpu = $5

        # Skip if no pod name
        if (pod_name == "") next

        # Determine GPU count (use limit if available, otherwise request)
        gpu_count = 0
        if (limit_gpu != "" && limit_gpu != "<none>" && limit_gpu != "null") {
            gpu_count = limit_gpu
        } else if (request_gpu != "" && request_gpu != "<none>" && request_gpu != "null") {
            gpu_count = request_gpu
        }

        # Only process if GPU count >= 1
        if (gpu_count >= 1) {
            pod_key = namespace "/" pod_name
            pod_gpus[pod_key] += gpu_count
        }
    }
    END {
        for (pod in pod_gpus) {
            print pod ":" pod_gpus[pod]
        }
    }' | sort)

    # Convert to array
    local gpu_pods=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            gpu_pods+=("$line")
        fi
    done <<< "$aggregated_data"

    # Display results
    echo ""
    if [ ${#gpu_pods[@]} -eq 0 ]; then
        print_warning "No pods found using GPUs."
    else
        print_success "Found ${#gpu_pods[@]} pod(s) using GPUs:"
        echo ""
        printf "%-60s %-10s\n" "POD" "GPUs"
        printf "%-60s %-10s\n" "---" "----"

        local total_gpus=0
        for pod_info in "${gpu_pods[@]}"; do
            local pod_key=$(echo "$pod_info" | cut -d':' -f1)
            local gpu_count=$(echo "$pod_info" | cut -d':' -f2)
            printf "%-60s %-10s\n" "$pod_key" "$gpu_count"
            total_gpus=$((total_gpus + gpu_count))
        done

        echo ""
        print_status "Total GPUs in use: ${total_gpus}"
    fi
}

# Run main function
main
