#!/bin/bash
################################################################################
# Fleet Setup Script
# Purpose: Configure Fleet in Kibana and deploy Fleet Server
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-elastic}"
KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"
KIBANA_USER="${KIBANA_USER:-elastic}"
KIBANA_PASSWORD="${KIBANA_PASSWORD:-elastic}"
FLEET_SERVER_URL="${FLEET_SERVER_URL:-http://fleet-server:8220}"
ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-http://elasticsearch-master:9200}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HELM_CHARTS_DIR="$SCRIPT_DIR/../helm_charts"

# Print functions
print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header "Fleet Setup Script"
echo ""
echo "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Kibana URL: $KIBANA_URL"
echo "  Fleet Server URL: $FLEET_SERVER_URL"
echo "  Elasticsearch URL: $ELASTICSEARCH_URL"
echo ""

################################################################################
# Check if Fleet Server is already deployed
################################################################################
print_header "Checking Fleet Server Status"

FLEET_DEPLOYED=false
if kubectl get deployment fleet-server -n "$NAMESPACE" &>/dev/null || \
   kubectl get statefulset fleet-server -n "$NAMESPACE" &>/dev/null; then
    FLEET_DEPLOYED=true
    print_info "Fleet Server is already deployed in namespace '$NAMESPACE'"

    # Check if it's running
    if kubectl get pods -n "$NAMESPACE" -l app=fleet-server --field-selector=status.phase=Running 2>/dev/null | grep -q fleet-server; then
        print_info "✓ Fleet Server pod is running"
        echo ""
        print_header "Fleet Server is Ready!"
        echo ""
        echo "Access Fleet management in Kibana:"
        echo ""
        echo -e "  ${GREEN}http://localhost:5601/app/fleet/agents${NC}"
        echo ""
        echo "Steps to access:"
        echo "  1. Port-forward Kibana (if not already done):"
        echo -e "     ${YELLOW}kubectl port-forward -n $NAMESPACE svc/kibana 5601:5601${NC}"
        echo ""
        echo "  2. Open the URL above in your browser"
        echo ""
        echo "  3. Login with:"
        echo "     Username: $KIBANA_USER"
        echo "     Password: $KIBANA_PASSWORD"
        echo ""
        echo "Fleet Server details:"
        echo "  • Check Fleet Server status: Management → Fleet → Settings → Fleet Server hosts"
        echo "  • View enrolled agents: Fleet → Agents"
        echo "  • Create agent policies: Fleet → Agent policies"
        echo ""
        exit 0
    else
        print_warning "Fleet Server is deployed but not running yet"
        echo ""
        echo "Monitor Fleet Server startup:"
        echo -e "  ${YELLOW}kubectl logs -n $NAMESPACE -l app=fleet-server -f${NC}"
        echo ""
        echo "Check pod status:"
        echo -e "  ${YELLOW}kubectl get pods -n $NAMESPACE -l app=fleet-server${NC}"
        echo ""
        exit 0
    fi
else
    print_info "Fleet Server is not deployed yet"
fi

################################################################################
# Wait for Kibana to be ready
################################################################################
print_header "Waiting for Kibana"

echo "Checking Kibana availability at $KIBANA_URL..."
RETRIES=0
MAX_RETRIES=30
until curl -sf -u "$KIBANA_USER:$KIBANA_PASSWORD" "$KIBANA_URL/api/status" >/dev/null 2>&1; do
    RETRIES=$((RETRIES+1))
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        print_error "Kibana is not accessible after $MAX_RETRIES attempts"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check if Kibana pod is running:"
        echo "     kubectl get pods -n $NAMESPACE -l app=kibana"
        echo ""
        echo "  2. Port-forward Kibana if needed:"
        echo "     kubectl port-forward -n $NAMESPACE svc/kibana 5601:5601"
        echo ""
        echo "  3. Check Kibana logs:"
        echo "     kubectl logs -n $NAMESPACE -l app=kibana"
        echo ""
        exit 1
    fi
    echo "  Waiting for Kibana... (attempt $RETRIES/$MAX_RETRIES)"
    sleep 5
done
print_info "✓ Kibana is ready"
echo ""

################################################################################
# Configure Fleet in Kibana
################################################################################
print_header "Configuring Fleet in Kibana"

# Create Fleet Server host
echo "1. Creating Fleet Server host..."
FLEET_HOST_RESPONSE=$(curl -s -X POST "$KIBANA_URL/api/fleet/fleet_server_hosts" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Fleet Server\",
    \"host_urls\": [\"$FLEET_SERVER_URL\"],
    \"is_default\": true
  }")

if echo "$FLEET_HOST_RESPONSE" | grep -q "id"; then
  FLEET_HOST_ID=$(echo "$FLEET_HOST_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  print_info "✓ Fleet Server host created with ID: $FLEET_HOST_ID"
else
  if echo "$FLEET_HOST_RESPONSE" | grep -q "already exists"; then
    print_info "✓ Fleet Server host already exists"
  else
    print_warning "Could not create Fleet Server host (may already exist)"
  fi
fi
echo ""

# Configure Elasticsearch output
echo "2. Configuring Elasticsearch output..."
OUTPUT_RESPONSE=$(curl -s -X POST "$KIBANA_URL/api/fleet/outputs" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"default\",
    \"type\": \"elasticsearch\",
    \"hosts\": [\"$ELASTICSEARCH_URL\"],
    \"is_default\": true,
    \"is_default_monitoring\": true,
    \"config_yaml\": \"ssl.verification_mode: none\"
  }")

if echo "$OUTPUT_RESPONSE" | grep -q "id"; then
  OUTPUT_ID=$(echo "$OUTPUT_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  print_info "✓ Elasticsearch output created with ID: $OUTPUT_ID"
else
  if echo "$OUTPUT_RESPONSE" | grep -q "already exists"; then
    print_info "✓ Elasticsearch output already exists"
  else
    print_warning "Could not create output (may already exist)"
  fi
fi
echo ""

# Create Fleet Server policy
echo "3. Creating Fleet Server policy..."
POLICY_RESPONSE=$(curl -s -X POST "$KIBANA_URL/api/fleet/agent_policies" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "fleet-server-policy",
    "namespace": "default",
    "description": "Fleet Server policy for quickstart deployment",
    "monitoring_enabled": ["logs", "metrics"],
    "has_fleet_server": true
  }')

if echo "$POLICY_RESPONSE" | grep -q "id"; then
  POLICY_ID=$(echo "$POLICY_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  print_info "✓ Fleet Server policy created with ID: $POLICY_ID"
else
  if echo "$POLICY_RESPONSE" | grep -q "already exists\|fleet-server-policy"; then
    print_info "✓ Fleet Server policy already exists"
  else
    print_warning "Could not create policy (may already exist)"
  fi
fi
echo ""

# Get Fleet setup status
echo "4. Verifying Fleet configuration..."
SETUP_RESPONSE=$(curl -s -X GET "$KIBANA_URL/api/fleet/setup" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -H "kbn-xsrf: true")

if echo "$SETUP_RESPONSE" | grep -q '"isReady":true'; then
    print_info "✓ Fleet is configured and ready"
else
    print_warning "Fleet configuration may not be complete"
fi
echo ""

################################################################################
# Deploy Fleet Server
################################################################################
print_header "Deploying Fleet Server"

echo "Installing Fleet Server Helm chart..."
echo ""

cd "$HELM_CHARTS_DIR"

if helm install fleet-server ./fleet-server --namespace "$NAMESPACE" 2>&1; then
    print_info "✓ Fleet Server Helm chart installed"
else
    print_error "Failed to install Fleet Server Helm chart"
    exit 1
fi

echo ""
print_header "Waiting for Fleet Server to be Ready"

echo "Waiting for Fleet Server pod to start..."
RETRIES=0
MAX_RETRIES=60
until kubectl get pods -n "$NAMESPACE" -l app=fleet-server 2>/dev/null | grep -q fleet-server; do
    RETRIES=$((RETRIES+1))
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        print_error "Fleet Server pod did not start after $MAX_RETRIES attempts"
        echo ""
        echo "Check deployment status:"
        echo "  kubectl get pods -n $NAMESPACE -l app=fleet-server"
        echo "  kubectl describe pod -n $NAMESPACE -l app=fleet-server"
        echo ""
        exit 1
    fi
    echo "  Waiting for pod... (attempt $RETRIES/$MAX_RETRIES)"
    sleep 2
done

echo "Waiting for Fleet Server pod to be ready..."
kubectl wait --for=condition=ready pod -l app=fleet-server -n "$NAMESPACE" --timeout=300s || {
    print_warning "Fleet Server pod may not be fully ready yet"
    echo ""
    echo "Monitor Fleet Server logs:"
    echo "  kubectl logs -n $NAMESPACE -l app=fleet-server -f"
    echo ""
}

################################################################################
# Display Success Message
################################################################################
print_header "Fleet Server Deployment Complete!"

echo ""
echo -e "${GREEN}✓ Fleet Server is deployed and ready!${NC}"
echo ""
echo "Access Fleet management in Kibana:"
echo ""
echo -e "  ${GREEN}http://localhost:5601/app/fleet/agents${NC}"
echo ""
echo "Steps to access:"
echo "  1. Port-forward Kibana (if not already done):"
echo -e "     ${YELLOW}kubectl port-forward -n $NAMESPACE svc/kibana 5601:5601${NC}"
echo ""
echo "  2. Open the URL above in your browser"
echo ""
echo "  3. Login with:"
echo "     Username: $KIBANA_USER"
echo "     Password: $KIBANA_PASSWORD"
echo ""
echo "Fleet Server details:"
echo "  • Fleet Server URL: $FLEET_SERVER_URL"
echo "  • Check status: Management → Fleet → Settings → Fleet Server hosts"
echo "  • View agents: Fleet → Agents"
echo "  • Create policies: Fleet → Agent policies"
echo ""
echo "Monitor Fleet Server:"
echo -e "  ${YELLOW}kubectl logs -n $NAMESPACE -l app=fleet-server -f${NC}"
echo ""
