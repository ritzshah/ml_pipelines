#!/bin/bash

# MinIO Webhook Configuration Script - Detailed Version
# This script configures MinIO to send webhook notifications when model files are uploaded

MINIO_ENDPOINT="http://minio.ic-shared-rag-minio.svc:9000"
MINIO_ACCESS_KEY="minio"
MINIO_SECRET_KEY="minio123"
BUCKET_NAME="pipeline-artifacts"
WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"
WEBHOOK_NAME="webhook"

echo "============================================"
echo "MinIO Webhook Configuration - Detailed Setup"
echo "============================================"
echo "MinIO Endpoint: $MINIO_ENDPOINT"
echo "Bucket: $BUCKET_NAME"
echo "Webhook URL: $WEBHOOK_URL"
echo ""

# Step 1: Configure MinIO alias
echo "Step 1: Configuring MinIO client alias..."
mc alias set myminio $MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY --api S3v4

# Step 2: Test MinIO connection
echo ""
echo "Step 2: Testing MinIO connection..."
mc ls myminio/

# Step 3: Check if bucket exists
echo ""
echo "Step 3: Checking if bucket exists..."
if mc ls myminio/ | grep -q $BUCKET_NAME; then
    echo "✓ Bucket '$BUCKET_NAME' exists"
else
    echo "✗ Bucket '$BUCKET_NAME' not found"
    echo "Creating bucket..."
    mc mb myminio/$BUCKET_NAME
fi

# Step 4: Configure webhook target in MinIO
echo ""
echo "Step 4: Configuring webhook target in MinIO server..."

# Set webhook configuration
mc admin config set myminio notify_webhook:$WEBHOOK_NAME \
    endpoint="$WEBHOOK_URL" \
    auth_token="" \
    queue_limit="100" \
    queue_dir="" \
    client_cert="" \
    client_key=""

echo "✓ Webhook target configured"

# Step 5: Restart MinIO to apply configuration
echo ""
echo "Step 5: Restarting MinIO service to apply configuration..."
mc admin service restart myminio
echo "✓ MinIO service restarted"

# Wait for MinIO to restart
echo "Waiting 10 seconds for MinIO to fully restart..."
sleep 10

# Step 6: Add event notifications
echo ""
echo "Step 6: Adding event notifications..."

# Add event for .bin files
echo "Adding event notification for .bin files..."
mc event add myminio/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".bin"

# Add event for .xml files  
echo "Adding event notification for .xml files..."
mc event add myminio/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".xml"

echo "✓ Event notifications configured"

# Step 7: Verify configuration
echo ""
echo "Step 7: Verifying event notification configuration..."
mc event list myminio/$BUCKET_NAME

echo ""
echo "Step 8: Checking webhook target configuration..."
mc admin config get myminio notify_webhook:$WEBHOOK_NAME

echo ""
echo "============================================"
echo "MinIO Webhook Configuration Complete!"
echo "============================================"
echo ""
echo "Configuration Summary:"
echo "- Webhook URL: $WEBHOOK_URL"
echo "- Bucket: $BUCKET_NAME"
echo "- Path Filter: 02_model_training/models/cats_and_dogs/"
echo "- File Types: .bin, .xml"
echo "- Events: s3:ObjectCreated:Put"
echo ""
echo "Test the configuration by uploading a file:"
echo "mc cp test-model.bin myminio/$BUCKET_NAME/02_model_training/models/cats_and_dogs/"
echo ""
echo "Check webhook logs with:"
echo "oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm"