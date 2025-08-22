#!/bin/bash

# MinIO Webhook Configuration Script
# This script configures MinIO to send webhook notifications when model files are uploaded

MINIO_ENDPOINT="http://minio.ic-shared-rag-minio.svc:9000"
MINIO_ACCESS_KEY="minio"
MINIO_SECRET_KEY="minio123"
BUCKET_NAME="pipeline-artifacts"
WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"

echo "============================================"
echo "MinIO Webhook Configuration"
echo "============================================"
echo "MinIO Endpoint: $MINIO_ENDPOINT"
echo "Bucket: $BUCKET_NAME"
echo "Webhook URL: $WEBHOOK_URL"
echo ""

# Add MinIO alias (if not already configured)
echo "Configuring MinIO client..."
mc alias set myminio $MINIO_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# Verify connection
echo "Testing MinIO connection..."
mc admin info myminio

# Configure webhook notification
echo ""
echo "Configuring webhook notification..."

# Add webhook notification for object creation events
mc event add myminio/$BUCKET_NAME arn:minio:sqs::webhook:webhook \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".bin,.xml"

# Verify the notification configuration
echo ""
echo "Verifying notification configuration..."
mc event list myminio/$BUCKET_NAME

echo ""
echo "============================================"
echo "Webhook Configuration Complete!"
echo "============================================"
echo ""
echo "The webhook will be triggered when:"
echo "- Files with .bin or .xml extensions are uploaded"
echo "- To the path: 02_model_training/models/cats_and_dogs/"
echo "- In bucket: $BUCKET_NAME"
echo ""
echo "Test the webhook with:"
echo "mc cp model.bin myminio/$BUCKET_NAME/02_model_training/models/cats_and_dogs/"