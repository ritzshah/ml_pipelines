#!/bin/bash

# Test script to verify MinIO webhook is working

echo "============================================"
echo "Testing MinIO Webhook Configuration"
echo "============================================"

MINIO_ALIAS="myminio"
BUCKET_NAME="pipeline-artifacts"
MODEL_PATH="02_model_training/models/cats_and_dogs"

# Check if mc is configured
if ! mc ls $MINIO_ALIAS/ &> /dev/null; then
    echo "❌ MinIO client not configured. Run install-mc-and-configure.sh first"
    exit 1
fi

echo "✓ MinIO connection verified"

# Create test files
echo "Creating test model files..."
echo "fake model binary data" > test-model.bin
echo '<?xml version="1.0"?><model><input shape="1,3,224,224"/></model>' > test-model.xml

echo "✓ Test files created"

# Upload test files
echo ""
echo "Uploading test files to trigger webhook..."

echo "Uploading test-model.bin..."
mc cp test-model.bin $MINIO_ALIAS/$BUCKET_NAME/$MODEL_PATH/

echo "Uploading test-model.xml..."
mc cp test-model.xml $MINIO_ALIAS/$BUCKET_NAME/$MODEL_PATH/

echo "✓ Files uploaded"

# Check if files were uploaded
echo ""
echo "Verifying files in MinIO:"
mc ls $MINIO_ALIAS/$BUCKET_NAME/$MODEL_PATH/

# Clean up local test files
rm -f test-model.bin test-model.xml

echo ""
echo "============================================"
echo "Test Complete!"
echo "============================================"
echo ""
echo "✓ Test files uploaded to MinIO"
echo ""
echo "To check if webhook was triggered:"
echo "oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm"
echo ""
echo "To check pipeline runs:"
echo "oc get pipelineruns -n ic-shared-rag-llm"
echo ""
echo "Files uploaded to: $BUCKET_NAME/$MODEL_PATH/"