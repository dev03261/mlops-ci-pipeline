#!/bin/bash
# scripts/wait-for-ingress.sh
# Advanced ingress readiness checking

set -euo pipefail

INGRESS_NAME=${1:-}
TIMEOUT=${2:-120}
NAMESPACE=${3:-default}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅${NC} $1"; }
warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
error() { echo -e "${RED}❌${NC} $1"; }

if [[ -z "$INGRESS_NAME" ]]; then
    error "Ingress name is required"
    echo "Usage: $0 <ingress_name> [timeout_seconds] [namespace]"
    exit 1
fi

log "Waiting for ingress $INGRESS_NAME to be ready (timeout: ${TIMEOUT}s)"

# Function to check ingress readiness
check_ingress_ready() {
    # Check if ingress exists and has rules
    if ! kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        return 1
    fi
    
    # For kind clusters, ingress is ready when it exists and has rules configured
    local rules_count
    rules_count=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules}' | jq '. | length' 2>/dev/null || echo "0")
    
    if [[ "$rules_count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Wait loop with timeout
start_time=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [[ $elapsed -gt $TIMEOUT ]]; then
        error "Timeout waiting for ingress $INGRESS_NAME"
        kubectl describe ingress "$INGRESS_NAME" -n "$NAMESPACE" || true
        exit 1
    fi
    
    if check_ingress_ready; then
        success "Ingress $INGRESS_NAME is configured and ready"
        break
    fi
    
    log "Waiting for ingress configuration... (${elapsed}/${TIMEOUT}s)"
    sleep 3
done

# Additional wait for ingress controller propagation
log "Allowing time for ingress controller to process rules..."
sleep 15

# Verify ingress configuration
log "Ingress configuration:"
kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o wide

success "Ingress $INGRESS_NAME is ready for traffic"