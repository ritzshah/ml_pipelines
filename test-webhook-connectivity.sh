#!/bin/bash

# Test webhook connectivity and configuration

echo "============================================"
echo "Webhook Connectivity Test"
echo "============================================"

WEBHOOK_URL_NO_PORT="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"
WEBHOOK_URL_WITH_PORT="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com:443"

echo "Testing webhook URLs..."
echo ""

# Test 1: URL without explicit port
echo "1. Testing URL without port: $WEBHOOK_URL_NO_PORT"
curl -k -v --max-time 10 "$WEBHOOK_URL_NO_PORT" 2>&1 | head -20
echo ""

# Test 2: URL with explicit port 443
echo "2. Testing URL with port 443: $WEBHOOK_URL_WITH_PORT"
curl -k -v --max-time 10 "$WEBHOOK_URL_WITH_PORT" 2>&1 | head -20
echo ""

# Test 3: Check if MinIO can reach the webhook from within cluster
echo "3. Testing from within OpenShift cluster..."
echo "Creating test pod to check connectivity from cluster..."

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: webhook-test
  namespace: ic-shared-rag-llm
spec:
  containers:
  - name: curl-test
    image: curlimages/curl:latest
    command: ['sleep', '300']
  restartPolicy: Never
EOF

# Wait for pod to be ready
echo "Waiting for test pod to be ready..."
oc wait --for=condition=Ready pod/webhook-test -n ic-shared-rag-llm --timeout=60s

if [ $? -eq 0 ]; then
    echo "✓ Test pod ready"
    
    echo ""
    echo "Testing webhook from inside cluster (without port):"
    oc exec webhook-test -n ic-shared-rag-llm -- curl -k -v --max-time 10 "$WEBHOOK_URL_NO_PORT" 2>&1 | head -20
    
    echo ""
    echo "Testing webhook from inside cluster (with port 443):"
    oc exec webhook-test -n ic-shared-rag-llm -- curl -k -v --max-time 10 "$WEBHOOK_URL_WITH_PORT" 2>&1 | head -20
    
    echo ""
    echo "Cleaning up test pod..."
    oc delete pod webhook-test -n ic-shared-rag-llm
else
    echo "❌ Test pod failed to start"
fi

echo ""
echo "============================================"
echo "Manual Test Instructions"
echo "============================================"
echo ""
echo "You can manually test the webhook by sending a POST request:"
echo ""
echo "curl -X POST '$WEBHOOK_URL_NO_PORT' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'Ce-Specversion: 1.0' \\"
echo "  -H 'Ce-Type: s3.model.uploaded' \\"
echo "  -H 'Ce-Source: manual-test' \\"
echo "  -d '{"
echo "    \"action\": \"s3_model_uploaded\","
echo "    \"model_name\": \"cats-and-dogs\","
echo "    \"model_version\": \"v1\","
echo "    \"s3_model_path\": \"02_model_training/models/cats_and_dogs\","
echo "    \"namespace\": \"ic-shared-rag-llm\""
echo "  }'"
echo ""
echo "This should trigger a pipeline run. Check with:"
echo "oc get pipelineruns -n ic-shared-rag-llm"