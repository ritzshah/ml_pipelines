#!/bin/bash

# MinIO Webhook Configuration for RELEASE.2023-06-19T19-52-50Z
# This version has specific requirements for webhook configuration

echo "============================================"
echo "MinIO 2023-06-19 Webhook Configuration"
echo "============================================"

MINIO_ALIAS="myminio"
BUCKET_NAME="pipeline-artifacts"
# For MinIO 2023 version, try without explicit port first
WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"
WEBHOOK_NAME="webhook"

echo "MinIO Version: RELEASE.2023-06-19T19-52-50Z"
echo "Webhook URL: $WEBHOOK_URL"
echo "Bucket: $BUCKET_NAME"
echo ""

# Step 1: Verify connection
echo "Step 1: Verifying MinIO connection..."
if ! mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
    echo "❌ MinIO connection failed. Please ensure port forwarding is active:"
    echo "oc port-forward -n ic-shared-rag-minio svc/minio 9000:9000"
    exit 1
fi
echo "✓ MinIO connection verified"

# Step 2: Check current configuration
echo ""
echo "Step 2: Checking current webhook configuration..."
mc admin config get $MINIO_ALIAS notify_webhook 2>/dev/null || echo "No webhook targets configured"

# Step 3: Remove any existing webhook configuration
echo ""
echo "Step 3: Cleaning existing webhook configuration..."
mc admin config remove $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>/dev/null || true

# Step 4: Configure webhook using MinIO 2023 syntax
echo ""
echo "Step 4: Configuring webhook target (MinIO 2023 syntax)..."

# Method 1: Standard configuration
echo "Trying standard configuration..."
mc admin config set $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME \
    endpoint="$WEBHOOK_URL" \
    auth_token="" \
    queue_limit="100" \
    comment="Cats and Dogs Model Webhook"

if [ $? -ne 0 ]; then
    echo "Standard method failed, trying alternative syntax..."
    
    # Method 2: Alternative syntax for older versions
    mc admin config set $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME \
        endpoint "$WEBHOOK_URL" \
        auth_token "" \
        queue_limit "100"
fi

# Step 5: Verify configuration was set
echo ""
echo "Step 5: Verifying webhook target configuration..."
WEBHOOK_CONFIG=$(mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>&1)
if [[ $WEBHOOK_CONFIG == *"error"* ]] || [[ $WEBHOOK_CONFIG == *"not found"* ]]; then
    echo "❌ Webhook configuration failed"
    echo "Output: $WEBHOOK_CONFIG"
    
    # Try with the legacy format
    echo ""
    echo "Trying legacy configuration format..."
    mc admin config set $MINIO_ALIAS notify_webhook \
        webhook="endpoint=$WEBHOOK_URL"
    
    if [ $? -ne 0 ]; then
        echo "❌ All configuration methods failed"
        echo "Manual configuration required"
        exit 1
    fi
else
    echo "✓ Webhook target configured successfully"
fi

# Step 6: Restart MinIO
echo ""
echo "Step 6: Restarting MinIO to apply configuration..."
mc admin service restart $MINIO_ALIAS

echo "Waiting 20 seconds for restart..."
sleep 20

# Step 7: Re-establish connection
echo ""
echo "Step 7: Re-establishing connection..."
mc alias set $MINIO_ALIAS http://localhost:9000 minio minio123 --api S3v4

# Wait for MinIO to be fully ready
for i in {1..8}; do
    if mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
        echo "✓ MinIO ready after restart"
        break
    else
        echo "Waiting for MinIO... (attempt $i/8)"
        sleep 3
    fi
done

# Step 8: Verify webhook target after restart
echo ""
echo "Step 8: Verifying webhook target after restart..."
mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME

# Step 9: Clear any existing bucket notifications
echo ""
echo "Step 9: Clearing existing bucket notifications..."
mc event remove $MINIO_ALIAS/$BUCKET_NAME --force 2>/dev/null || true

# Step 10: Add bucket notifications
echo ""
echo "Step 10: Adding bucket event notifications..."

# For MinIO 2023, try different ARN formats
ARN_FORMATS=(
    "arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME"
    "arn:minio:sqs:::$WEBHOOK_NAME"
    "arn:minio:sqs::webhook:1"
)

SUCCESS=false

for ARN in "${ARN_FORMATS[@]}"; do
    echo ""
    echo "Trying ARN format: $ARN"
    
    # Test with .bin files first
    echo "Adding .bin file notification..."
    mc event add $MINIO_ALIAS/$BUCKET_NAME "$ARN" \
        --event put \
        --prefix "02_model_training/models/cats_and_dogs/" \
        --suffix ".bin"
    
    if [ $? -eq 0 ]; then
        echo "✓ .bin notification successful with ARN: $ARN"
        
        # Add .xml files with same ARN
        echo "Adding .xml file notification..."
        mc event add $MINIO_ALIAS/$BUCKET_NAME "$ARN" \
            --event put \
            --prefix "02_model_training/models/cats_and_dogs/" \
            --suffix ".xml"
        
        if [ $? -eq 0 ]; then
            echo "✓ .xml notification successful"
            SUCCESS=true
            break
        fi
    else
        echo "❌ Failed with ARN: $ARN"
    fi
done

# Step 11: Results
echo ""
echo "Step 11: Configuration Results..."
if [ "$SUCCESS" = true ]; then
    echo "✓ Event notifications configured successfully"
else
    echo "❌ All ARN formats failed"
    echo ""
    echo "Available notification targets:"
    mc admin config get $MINIO_ALIAS notify_webhook
    echo ""
    echo "Manual configuration may be needed via MinIO Console UI"
fi

# Step 12: Final verification
echo ""
echo "Step 12: Final verification..."
echo ""
echo "Webhook targets:"
mc admin config get $MINIO_ALIAS notify_webhook
echo ""
echo "Bucket notifications:"
mc event list $MINIO_ALIAS/$BUCKET_NAME
echo ""

echo "============================================"
echo "Configuration Summary"
echo "============================================"
echo ""
if [ "$SUCCESS" = true ]; then
    echo "✅ SUCCESS: Webhook notifications configured"
    echo ""
    echo "Test with:"
    echo "1. echo 'test data' > test-model.bin"
    echo "2. mc cp test-model.bin $MINIO_ALIAS/$BUCKET_NAME/02_model_training/models/cats_and_dogs/"
    echo "3. oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm"
else
    echo "❌ FAILED: Manual configuration required"
    echo ""
    echo "Next steps:"
    echo "1. Access MinIO Console UI"
    echo "2. Navigate to Buckets → pipeline-artifacts → Events"
    echo "3. Add webhook manually with URL: $WEBHOOK_URL"
    echo "4. Set prefix: 02_model_training/models/cats_and_dogs/"
    echo "5. Set suffix: .bin,.xml"
fi