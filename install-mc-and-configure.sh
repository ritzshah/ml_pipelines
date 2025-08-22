#!/bin/bash

# Complete MinIO Client Installation and Configuration Script for Mac
# This script installs mc, connects to MinIO, and configures webhook notifications

echo "============================================"
echo "MinIO Client Installation and Configuration"
echo "============================================"

# Step 1: Install MinIO Client (mc)
echo "Step 1: Installing MinIO Client (mc)..."

# Check if mc is already installed
if command -v mc &> /dev/null; then
    echo "✓ MinIO Client (mc) is already installed"
    mc --version
else
    echo "Installing MinIO Client using Homebrew..."
    
    # Check if Homebrew is installed
    if command -v brew &> /dev/null; then
        echo "✓ Homebrew found, installing mc..."
        brew install minio/stable/mc
    else
        echo "Homebrew not found. Installing mc manually..."
        
        # Download mc binary for macOS
        echo "Downloading mc binary..."
        curl -O https://dl.min.io/client/mc/release/darwin-amd64/mc
        
        # Make it executable
        chmod +x mc
        
        # Move to /usr/local/bin
        sudo mv mc /usr/local/bin/
        
        echo "✓ MinIO Client installed manually"
    fi
fi

# Verify installation
echo ""
echo "Verifying mc installation..."
mc --version

# Step 2: Configure MinIO connection
echo ""
echo "Step 2: Configuring MinIO connection..."

# MinIO connection details
MINIO_ALIAS="myminio"
MINIO_ENDPOINT="http://minio.ic-shared-rag-minio.svc:9000"
MINIO_ACCESS_KEY="minio"
MINIO_SECRET_KEY="minio123"

# Note: Since this is an internal service, we need to use port-forwarding
echo ""
echo "⚠️  IMPORTANT: MinIO is running inside OpenShift cluster"
echo "We need to set up port forwarding to access it from your Mac"
echo ""

# Check if user is logged into OpenShift
if ! oc whoami &> /dev/null; then
    echo "❌ Please log into OpenShift first:"
    echo "oc login --server=<your-cluster-url>"
    exit 1
fi

echo "✓ OpenShift session active"

# Set up port forwarding in background
echo ""
echo "Step 3: Setting up port forwarding to MinIO..."
echo "This will forward local port 9000 to MinIO service"

# Kill any existing port-forward on port 9000
pkill -f "port-forward.*9000:9000" 2>/dev/null || true

# Start port forwarding in background
oc port-forward -n ic-shared-rag-minio svc/minio 9000:9000 &
PORT_FORWARD_PID=$!

echo "✓ Port forwarding started (PID: $PORT_FORWARD_PID)"
echo "Waiting 5 seconds for port forwarding to establish..."
sleep 5

# Step 4: Configure mc alias with local forwarded port
echo ""
echo "Step 4: Configuring mc alias..."
MINIO_LOCAL_ENDPOINT="http://localhost:9000"

mc alias set $MINIO_ALIAS $MINIO_LOCAL_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY --api S3v4

# Test connection
echo ""
echo "Step 5: Testing MinIO connection..."
if mc ls $MINIO_ALIAS/ &> /dev/null; then
    echo "✓ Successfully connected to MinIO"
    mc ls $MINIO_ALIAS/
else
    echo "❌ Failed to connect to MinIO"
    echo "Please check if port forwarding is working:"
    echo "curl http://localhost:9000/minio/health/live"
    exit 1
fi

# Step 6: Configure webhook target
echo ""
echo "Step 6: Configuring webhook target..."
WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"
WEBHOOK_NAME="webhook"

echo "Setting webhook configuration..."
mc admin config set $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME \
    endpoint="$WEBHOOK_URL" \
    auth_token="" \
    queue_limit="100"

if [ $? -eq 0 ]; then
    echo "✓ Webhook target configured successfully"
else
    echo "❌ Failed to configure webhook target"
    exit 1
fi

# Step 7: Restart MinIO to apply configuration
echo ""
echo "Step 7: Restarting MinIO service..."
mc admin service restart $MINIO_ALIAS

echo "Waiting 15 seconds for MinIO to restart..."
sleep 15

# Re-establish connection after restart
echo "Re-establishing connection after restart..."
mc alias set $MINIO_ALIAS $MINIO_LOCAL_ENDPOINT $MINIO_ACCESS_KEY $MINIO_SECRET_KEY --api S3v4

# Step 8: Add event notifications
echo ""
echo "Step 8: Adding event notifications..."
BUCKET_NAME="pipeline-artifacts"

# Check if bucket exists
if mc ls $MINIO_ALIAS/ | grep -q $BUCKET_NAME; then
    echo "✓ Bucket '$BUCKET_NAME' exists"
else
    echo "Creating bucket '$BUCKET_NAME'..."
    mc mb $MINIO_ALIAS/$BUCKET_NAME
fi

# Add event for .bin files
echo "Adding event notification for .bin files..."
mc event add $MINIO_ALIAS/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".bin"

# Add event for .xml files
echo "Adding event notification for .xml files..."
mc event add $MINIO_ALIAS/$BUCKET_NAME arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".xml"

# Step 9: Verify configuration
echo ""
echo "Step 9: Verifying configuration..."
echo "Event notifications:"
mc event list $MINIO_ALIAS/$BUCKET_NAME

echo ""
echo "Webhook configuration:"
mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME

echo ""
echo "============================================"
echo "Configuration Complete!"
echo "============================================"
echo ""
echo "✓ MinIO Client installed and configured"
echo "✓ Port forwarding active (PID: $PORT_FORWARD_PID)"
echo "✓ Webhook target configured"
echo "✓ Event notifications set up"
echo ""
echo "Configuration Summary:"
echo "- MinIO Alias: $MINIO_ALIAS"
echo "- Webhook URL: $WEBHOOK_URL"
echo "- Bucket: $BUCKET_NAME"
echo "- Path Filter: 02_model_training/models/cats_and_dogs/"
echo "- File Types: .bin, .xml"
echo ""
echo "To test the webhook:"
echo "1. Create a test file: echo 'test' > test-model.bin"
echo "2. Upload it: mc cp test-model.bin $MINIO_ALIAS/$BUCKET_NAME/02_model_training/models/cats_and_dogs/"
echo "3. Check webhook logs: oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm"
echo ""
echo "To stop port forwarding: kill $PORT_FORWARD_PID"
echo ""
echo "IMPORTANT: Keep this terminal open to maintain port forwarding!"