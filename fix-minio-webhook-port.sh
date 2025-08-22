#!/bin/bash

# Fixed MinIO Webhook Configuration - Addresses port and URL issues

echo "============================================"
echo "MinIO Webhook Configuration - PORT FIX"
echo "============================================"

MINIO_ALIAS="myminio"
BUCKET_NAME="pipeline-artifacts"
# Fix: Add explicit port 443 for HTTPS
WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com:443"
WEBHOOK_NAME="webhook"

echo "Webhook URL (with port): $WEBHOOK_URL"
echo "Bucket: $BUCKET_NAME"
echo ""

# Step 1: Test MinIO connection
echo "Step 1: Testing MinIO connection..."
if ! mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
    echo "❌ MinIO connection failed. Please ensure:"
    echo "1. Port forwarding is active: oc port-forward -n ic-shared-rag-minio svc/minio 9000:9000"
    echo "2. Alias is configured: mc alias set myminio http://localhost:9000 minio minio123"
    exit 1
fi
echo "✓ MinIO connection successful"

# Step 2: Remove any existing webhook configuration
echo ""
echo "Step 2: Cleaning up any existing webhook configuration..."
mc admin config remove $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>/dev/null || true
echo "✓ Cleanup complete"

# Step 3: Configure webhook target with explicit port
echo ""
echo "Step 3: Configuring webhook target (with port)..."
mc admin config set $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME \
    endpoint="$WEBHOOK_URL" \
    auth_token="" \
    queue_limit="100"

if [ $? -eq 0 ]; then
    echo "✓ Webhook target configuration command executed"
else
    echo "❌ Failed to configure webhook target"
    exit 1
fi

# Step 4: Restart MinIO
echo ""
echo "Step 4: Restarting MinIO..."
mc admin service restart $MINIO_ALIAS

echo "Waiting 15 seconds for restart..."
sleep 15

# Step 5: Re-establish connection
echo ""
echo "Step 5: Re-establishing connection..."
mc alias set $MINIO_ALIAS http://localhost:9000 minio minio123 --api S3v4

# Wait for MinIO to be ready
for i in {1..6}; do
    if mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
        echo "✓ MinIO is ready"
        break
    else
        echo "Waiting for MinIO... (attempt $i/6)"
        sleep 5
    fi
done

# Step 6: Verify webhook target exists
echo ""
echo "Step 6: Verifying webhook target..."
WEBHOOK_CHECK=$(mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>&1)
if [[ $WEBHOOK_CHECK == *"error"* ]] || [[ $WEBHOOK_CHECK == *"not found"* ]]; then
    echo "❌ Webhook target not found after restart"
    echo "Output: $WEBHOOK_CHECK"
    
    # Try alternative configuration method
    echo ""
    echo "Trying alternative configuration method..."
    mc admin config set $MINIO_ALIAS notify_webhook \
        webhook="endpoint=$WEBHOOK_URL auth_token= queue_limit=100"
    
    if [ $? -eq 0 ]; then
        echo "✓ Alternative configuration successful"
        mc admin service restart $MINIO_ALIAS
        sleep 15
        mc alias set $MINIO_ALIAS http://localhost:9000 minio minio123 --api S3v4
    else
        echo "❌ Alternative configuration also failed"
    fi
else
    echo "✓ Webhook target verified:"
    echo "$WEBHOOK_CHECK"
fi

# Step 7: Remove existing bucket notifications
echo ""
echo "Step 7: Removing any existing bucket notifications..."
mc event remove $MINIO_ALIAS/$BUCKET_NAME --force 2>/dev/null || true

# Step 8: Add event notifications
echo ""
echo "Step 8: Adding event notifications..."

echo "Adding notification for .bin files..."
mc event add $MINIO_ALIAS/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".bin"

BIN_RESULT=$?

echo "Adding notification for .xml files..."
mc event add $MINIO_ALIAS/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".xml"

XML_RESULT=$?

# Step 9: Verify results
echo ""
echo "Step 9: Configuration Results..."
if [ $BIN_RESULT -eq 0 ] && [ $XML_RESULT -eq 0 ]; then
    echo "✓ Both event notifications configured successfully"
elif [ $BIN_RESULT -eq 0 ] || [ $XML_RESULT -eq 0 ]; then
    echo "⚠ Partial success - some notifications configured"
else
    echo "❌ Event notification configuration failed"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check webhook target exists:"
    echo "   mc admin config get $MINIO_ALIAS notify_webhook"
    echo ""
    echo "2. Test webhook URL accessibility:"
    echo "   curl -k -v $WEBHOOK_URL"
    echo ""
    echo "3. Check MinIO logs for errors:"
    echo "   oc logs -f deployment/minio -n ic-shared-rag-minio"
fi

# Step 10: Final verification
echo ""
echo "Step 10: Final verification..."
echo ""
echo "Current webhook configuration:"
mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>/dev/null || echo "No webhook configuration found"

echo ""
echo "Current bucket notifications:"
mc event list $MINIO_ALIAS/$BUCKET_NAME

echo ""
echo "============================================"
echo "Configuration Complete"
echo "============================================"
echo ""
echo "To test the webhook:"
echo "1. Create test file: echo 'test data' > test-model.bin"
echo "2. Upload file: mc cp test-model.bin $MINIO_ALIAS/$BUCKET_NAME/02_model_training/models/cats_and_dogs/"
echo "3. Check logs: oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm"