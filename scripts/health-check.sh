#!/bin/bash
# scripts/health-check.sh
# Comprehensive health validation with proper retry logic

set -euo pipefail

# Configuration with environment variable support
MAX_RETRIES=${HEALTH_CHECK_RETRIES:-20}
RETRY_DELAY=${HEALTH_CHECK_DELAY:-3}
BASE_URL=${BASE_URL:-"http://localhost"}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅${NC} $1"; }
warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
error() { echo -e "${RED}❌${NC} $1"; }

# Advanced endpoint checking with detailed diagnostics
check_endpoint() {
    local host=$1
    local expected_response=$2
    local retries=0
    
    log "Testing endpoint: $host (expecting: '$expected_response')"
    
    while [[ $retries -lt $MAX_RETRIES ]]; do
        local response http_code curl_exit_code
        
        # Capture both response and HTTP status
        if response=$(curl -s -H "Host: $host" "$BASE_URL/" 2>/dev/null) && \
           http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" "$BASE_URL/" 2>/dev/null); then
            curl_exit_code=0
        else
            curl_exit_code=$?
        fi
        
        if [[ $curl_exit_code -eq 0 && "$http_code" == "200" ]]; then
            if [[ "$response" == "$expected_response" ]]; then
                success "✓ $host: HTTP $http_code, response: '$response'"
                return 0
            else
                warning "✗ $host: HTTP $http_code, got '$response', expected '$expected_response'"
            fi
        else
            warning "✗ $host: Connection failed (exit code: $curl_exit_code, HTTP: ${http_code:-'N/A'})"
        fi
        
        retries=$((retries + 1))
        if [[ $retries -lt $MAX_RETRIES ]]; then
            log "  Retry $((retries + 1))/$MAX_RETRIES in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
    done
    
    error "Endpoint $host failed after $MAX_RETRIES attempts"
    return 1
}

# Kubernetes resource validation
validate_k8s_resources() {
    log "Validating Kubernetes resources..."
    
    local exit_code=0
    
    # Check deployments
    log "Deployment status:"
    if kubectl get deployments foo bar -o wide 2>/dev/null; then
        success "Deployments found"
        
        # Check if all replicas are ready
        for deployment in foo bar; do
            local ready desired
            ready=$(kubectl get deployment "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            desired=$(kubectl get deployment "$deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            
            if [[ "$ready" == "$desired" && "$ready" != "0" ]]; then
                success "  $deployment: $ready/$desired replicas ready"
            else
                error "  $deployment: $ready/$desired replicas ready"
                exit_code=1
            fi
        done
    else
        error "Required deployments not found"
        exit_code=1
    fi
    
    # Check services
    log "Service status:"
    if kubectl get services foo bar -o wide 2>/dev/null; then
        success "Services found and accessible"
    else
        error "Required services not found"
        exit_code=1
    fi
    
    # Check ingress
    log "Ingress status:"
    if kubectl get ingress echo-ingress -o wide 2>/dev/null; then
        success "Ingress found and configured"
    else
        error "Ingress not found"
        exit_code=1
    fi
    
    # Check pod health
    log "Pod health status:"
    local unhealthy_pods
    unhealthy_pods=$(kubectl get pods -l component=http-echo --field-selector=status.phase!=Running -o name 2>/dev/null | wc -l)
    
    if [[ $unhealthy_pods -eq 0 ]]; then
        success "All pods are running and healthy"
        kubectl get pods -l component=http-echo -o wide
    else
        error "Found $unhealthy_pods unhealthy pods"
        kubectl get pods -l component=http-echo
        exit_code=1
    fi
    
    return $exit_code
}

# Ingress controller validation
validate_ingress_controller() {
    log "Validating ingress controller..."
    
    local controller_pods
    controller_pods=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
    
    if [[ $controller_pods -gt 0 ]]; then
        success "Ingress controller is running ($controller_pods healthy pods)"
        return 0
    else
        error "Ingress controller is not running properly"
        kubectl get pods -n ingress-nginx
        return 1
    fi
}

# Main health check orchestration
main() {
    log "🏥 Starting comprehensive health validation..."
    
    local overall_exit_code=0
    
    # Phase 1: Kubernetes resources
    if ! validate_k8s_resources; then
        overall_exit_code=1
    fi
    
    # Phase 2: Ingress controller
    if ! validate_ingress_controller; then
        overall_exit_code=1
    fi
    
    # Phase 3: Wait for services to stabilize
    log "⏳ Allowing services to stabilize..."
    sleep 10
    
    # Phase 4: End-to-end connectivity tests
    log "🌐 Testing end-to-end connectivity..."
    if ! check_endpoint "foo.localhost" "foo"; then
        overall_exit_code=1
    fi
    
    if ! check_endpoint "bar.localhost" "bar"; then
        overall_exit_code=1
    fi
    
    # Final report
    if [[ $overall_exit_code -eq 0 ]]; then
        success "🎉 All health checks passed! System is ready for load testing."
    else
        error "❌ Health check failures detected. Check logs above for details."
    fi
    
    return $overall_exit_code
}

# Execute main function
main "$@" 