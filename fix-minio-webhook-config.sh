#!/bin/bash

# Fixed MinIO Webhook Configuration Script
# This script properly configures webhook target first, then adds event notifications

echo "============================================"
echo "MinIO Webhook Configuration - FIXED VERSION"
echo "============================================"

# Configuration variables
MINIO_ALIAS="myminio"
MINIO_ENDPOINT="http://localhost:9000"  # Using port-forwarded endpoint
MINIO_ACCESS_KEY="minio"
MINIO_SECRET_KEY="minio123"
BUCKET_NAME="pipeline-artifacts"
WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"
WEBHOOK_NAME="webhook"

echo "MinIO Endpoint: $MINIO_ENDPOINT"
echo "Bucket: $BUCKET_NAME"
echo "Webhook URL: $WEBHOOK_URL"
echo ""

# Step 1: Check if port forwarding is active
echo "Step 1: Checking port forwarding to MinIO..."
if curl -s http://localhost:9000/minio/health/live > /dev/null 2>&1; then
    echo "✓ MinIO is accessible via port forwarding"
else
    echo "❌ MinIO not accessible. Please set up port forwarding first:"
    echo "oc port-forward -n ic-shared-rag-minio svc/minio 9000:9000"
    exit 1
fi

# Step 2: Configure MinIO alias
echo ""
echo "Step 2: Configuring MinIO client alias..."
mc alias set $MINIO_ALIAS $MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY --api S3v4

# Step 3: Test connection
echo ""
echo "Step 3: Testing MinIO connection..."
if mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
    echo "✓ Successfully connected to MinIO"
    mc ls $MINIO_ALIAS/
else
    echo "❌ Failed to connect to MinIO"
    exit 1
fi

# Step 4: Check current webhook configuration
echo ""
echo "Step 4: Checking current webhook configuration..."
CURRENT_CONFIG=$(mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>/dev/null)
if [ $? -eq 0 ] && [ ! -z "$CURRENT_CONFIG" ]; then
    echo "Webhook configuration exists:"
    echo "$CURRENT_CONFIG"
else
    echo "No webhook configuration found. Will create new one."
fi

# Step 5: Configure webhook target (this creates the ARN)
echo ""
echo "Step 5: Configuring webhook target in MinIO..."
mc admin config set $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME \
    endpoint="$WEBHOOK_URL" \
    auth_token="" \
    queue_limit="100" \
    queue_dir="" \
    client_cert="" \
    client_key=""

if [ $? -eq 0 ]; then
    echo "✓ Webhook target configured successfully"
else
    echo "❌ Failed to configure webhook target"
    exit 1
fi

# Step 6: Restart MinIO to activate the webhook target
echo ""
echo "Step 6: Restarting MinIO to activate webhook target..."
mc admin service restart $MINIO_ALIAS

echo "Waiting 20 seconds for MinIO to fully restart..."
sleep 20

# Step 7: Re-establish connection
echo ""
echo "Step 7: Re-establishing connection after restart..."
mc alias set $MINIO_ALIAS $MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY --api S3v4

# Verify connection after restart
echo "Testing connection after restart..."
for i in {1..5}; do
    if mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
        echo "✓ Connection re-established"
        break
    else
        echo "Attempt $i: Connection not ready, waiting 5 more seconds..."
        sleep 5
    fi
done

# Step 8: Verify webhook target is active
echo ""
echo "Step 8: Verifying webhook target is active..."
mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME

# Step 9: Check if bucket exists
echo ""
echo "Step 9: Checking bucket..."
if mc ls $MINIO_ALIAS/ | grep -q $BUCKET_NAME; then
    echo "✓ Bucket '$BUCKET_NAME' exists"
else
    echo "Creating bucket '$BUCKET_NAME'..."
    mc mb $MINIO_ALIAS/$BUCKET_NAME
fi

# Step 10: Now add event notifications (ARN should exist now)
echo ""
echo "Step 10: Adding event notifications..."

# Remove any existing notifications first
echo "Removing any existing notifications..."
mc event remove $MINIO_ALIAS/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME --force 2>/dev/null || true

# Add event for .bin files
echo "Adding event notification for .bin files..."
mc event add $MINIO_ALIAS/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".bin"

if [ $? -eq 0 ]; then
    echo "✓ .bin file notification added successfully"
else
    echo "❌ Failed to add .bin file notification"
fi

# Add event for .xml files
echo "Adding event notification for .xml files..."
mc event add $MINIO_ALIAS/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".xml"

if [ $? -eq 0 ]; then
    echo "✓ .xml file notification added successfully"
else
    echo "❌ Failed to add .xml file notification"
fi

# Step 11: Verify final configuration
echo ""
echo "Step 11: Verifying final configuration..."
echo ""
echo "Event notifications:"
mc event list $MINIO_ALIAS/$BUCKET_NAME

echo ""
echo "Webhook target configuration:"
mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME

echo ""
echo "============================================"
echo "Configuration Complete!"
echo "============================================"
echo ""
echo "✓ Webhook target configured and active"
echo "✓ Event notifications set up"
echo ""
echo "Test the configuration:"
echo "1. Create test file: echo 'test' > test-model.bin"
echo "2. Upload: mc cp test-model.bin $MINIO_ALIAS/$BUCKET_NAME/02_model_training/models/cats_and_dogs/"
echo "3. Check logs: oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm"