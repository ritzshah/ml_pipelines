#!/bin/bash

# Manual webhook test - bypasses MinIO and tests webhook directly

echo "============================================"
echo "Manual Webhook Test"
echo "============================================"

WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"

echo "Testing webhook endpoint: $WEBHOOK_URL"
echo ""

# Test 1: Basic connectivity
echo "Test 1: Basic connectivity test..."
curl -k -v --max-time 10 "$WEBHOOK_URL" 2>&1 | head -10
echo ""

# Test 2: Send actual webhook payload
echo "Test 2: Sending webhook payload..."
RESPONSE=$(curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "Ce-Specversion: 1.0" \
  -H "Ce-Type: s3.model.uploaded" \
  -H "Ce-Source: manual-test" \
  -w "HTTP_CODE:%{http_code}" \
  -d '{
    "action": "s3_model_uploaded",
    "event_type": "s3_model_ready", 
    "trigger_source": "manual_test",
    "model_name": "cats-and-dogs",
    "model_version": "v1",
    "s3_model_path": "02_model_training/models/cats_and_dogs",
    "namespace": "ic-shared-rag-llm",
    "timestamp": "'$(date -Iseconds)'"
  }' 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')

echo "HTTP Response Code: $HTTP_CODE"
echo "Response Body: $BODY"

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "202" ]; then
    echo "✅ Webhook test successful!"
    echo ""
    echo "Check if pipeline was triggered:"
    echo "oc get pipelineruns -n ic-shared-rag-llm --sort-by=.metadata.creationTimestamp"
    echo ""
    echo "Check EventListener logs:"
    echo "oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm"
else
    echo "❌ Webhook test failed with HTTP code: $HTTP_CODE"
fi

echo ""
echo "============================================"
echo "Alternative: Upload Test File to MinIO"
echo "============================================"
echo ""
echo "If webhook configuration is too complex, you can:"
echo "1. Upload a test file to MinIO manually"
echo "2. Trigger the pipeline using the webhook directly"
echo ""
echo "Manual file upload (if you have access to MinIO console):"
echo "- Navigate to: pipeline-artifacts/02_model_training/models/cats_and_dogs/"
echo "- Upload any file named: model.bin or model.xml"
echo ""
echo "Or test pipeline directly:"
echo "oc create -f - <<EOF"
echo "apiVersion: tekton.dev/v1beta1"
echo "kind: PipelineRun"
echo "metadata:"
echo "  generateName: manual-test-"
echo "  namespace: ic-shared-rag-llm"
echo "spec:"
echo "  pipelineRef:"
echo "    name: s3-model-deployment-pipeline"
echo "  params:"
echo "  - name: model-name"
echo "    value: cats-and-dogs"
echo "  - name: model-version"
echo "    value: v1"
echo "  - name: s3-model-path"
echo "    value: 02_model_training/models/cats_and_dogs"
echo "  - name: namespace"
echo "    value: ic-shared-rag-llm"
echo "EOF"