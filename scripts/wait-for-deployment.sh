#!/bin/bash
set -euo pipefail

NAMESPACE=${1:-default}
DEPLOYMENT_NAME=${2:-}
TIMEOUT=${3:-300}

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}${NC} $1"; }
error() { echo -e "${RED}${NC} $1"; }

if [[ -z "$DEPLOYMENT_NAME" ]]; then
    error "Deployment name is required"
    exit 1
fi

log "Waiting for deployment $DEPLOYMENT_NAME in namespace $NAMESPACE"

if timeout "$TIMEOUT" kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"; then
    # Additional verification - check replica counts
    ready_replicas=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    desired_replicas=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    log "Deployment status: $ready_replicas/$desired_replicas replicas ready"
    
    if [[ "$ready_replicas" == "$desired_replicas" && "$ready_replicas" != "0" ]]; then
        success "Deployment $DEPLOYMENT_NAME is fully ready and healthy"
        exit 0
    else
        error "Not all replicas are ready ($ready_replicas/$desired_replicas)"
        kubectl describe deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"
        exit 1
    fi
else
    error "Timeout waiting for deployment $DEPLOYMENT_NAME"
    log "Gathering debug information..."
    kubectl describe deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" || true
    kubectl get pods -l app="$DEPLOYMENT_NAME" -n "$NAMESPACE" || true
    exit 1
fi
