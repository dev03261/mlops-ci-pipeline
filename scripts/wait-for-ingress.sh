#!/bin/bash
set -euo pipefail

INGRESS_NAME=${1:-}
TIMEOUT=${2:-120}
NAMESPACE=${3:-default}

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅${NC} $1"; }
error() { echo -e "${RED}❌${NC} $1"; }

if [[ -z "$INGRESS_NAME" ]]; then
    error "Ingress name is required"
    exit 1
fi

log "Waiting for ingress $INGRESS_NAME"

check_ingress_ready() {
    if ! kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        return 1
    fi
    
    # For kind clusters, ingress is ready when it exists and has rules configured
    rules_count=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules}' | jq '. | length' 2>/dev/null || echo "0")
    
    if [[ "$rules_count" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

start_time=$(date +%s)
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [[ $elapsed -gt $TIMEOUT ]]; then
        error "Timeout waiting for ingress"
        exit 1
    fi
    
    if check_ingress_ready; then
        success "Ingress $INGRESS_NAME is ready"
        break
    fi
    
    sleep 3
done

sleep 15  # Allow ingress to stabilize
success "Ingress ready for traffic"
