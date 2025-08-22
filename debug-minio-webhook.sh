#!/bin/bash

# Debug script to troubleshoot MinIO webhook configuration issues

echo "============================================"
echo "MinIO Webhook Debug Information"
echo "============================================"

MINIO_ALIAS="myminio"
WEBHOOK_NAME="webhook"
BUCKET_NAME="pipeline-artifacts"

# Check 1: MinIO connection
echo "1. Testing MinIO connection..."
if mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
    echo "✓ MinIO connection: OK"
    mc ls $MINIO_ALIAS/
else
    echo "❌ MinIO connection: FAILED"
    echo "Please check port forwarding: oc port-forward -n ic-shared-rag-minio svc/minio 9000:9000"
    exit 1
fi

# Check 2: MinIO server info
echo ""
echo "2. MinIO server information..."
mc admin info $MINIO_ALIAS

# Check 3: Current webhook configuration
echo ""
echo "3. Current webhook targets..."
mc admin config get $MINIO_ALIAS notify_webhook

# Check 4: Specific webhook target
echo ""
echo "4. Checking specific webhook target: $WEBHOOK_NAME"
WEBHOOK_CONFIG=$(mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>&1)
if [[ $WEBHOOK_CONFIG == *"configuration not found"* ]]; then
    echo "❌ Webhook target '$WEBHOOK_NAME' not configured"
    echo "This is why the ARN doesn't exist!"
else
    echo "✓ Webhook target exists:"
    echo "$WEBHOOK_CONFIG"
fi

# Check 5: All notification targets
echo ""
echo "5. All available notification targets..."
mc admin config get $MINIO_ALIAS | grep notify

# Check 6: Current bucket notifications
echo ""
echo "6. Current bucket notifications..."
mc event list $MINIO_ALIAS/$BUCKET_NAME

# Check 7: Test webhook endpoint accessibility from local machine
echo ""
echo "7. Testing webhook endpoint accessibility..."
WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"
if curl -k -s --max-time 10 "$WEBHOOK_URL" > /dev/null 2>&1; then
    echo "✓ Webhook endpoint is accessible from local machine"
else
    echo "❌ Webhook endpoint not accessible from local machine"
    echo "This might cause issues for MinIO to reach it"
fi

echo ""
echo "============================================"
echo "Debug Summary"
echo "============================================"
echo ""
echo "Common issues and solutions:"
echo ""
echo "1. If webhook target not found:"
echo "   - Run: mc admin config set $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME endpoint=\"$WEBHOOK_URL\""
echo "   - Then: mc admin service restart $MINIO_ALIAS"
echo ""
echo "2. If ARN error persists:"
echo "   - Restart MinIO after setting webhook target"
echo "   - Wait for MinIO to fully restart before adding notifications"
echo ""
echo "3. If webhook unreachable:"
echo "   - MinIO pods need network access to OpenShift routes"
echo "   - Check network policies and firewall rules"