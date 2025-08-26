#!/bin/bash

# Complete MinIO Webhook Setup with Connection Management
# Handles port forwarding, connection issues, and provides fallback options

echo "============================================"
echo "Complete MinIO Webhook Setup"
echo "============================================"

MINIO_ALIAS="myminio"
BUCKET_NAME="pipeline-artifacts"
WEBHOOK_URL="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com"
WEBHOOK_NAME="webhook"
MINIO_NAMESPACE="ic-shared-rag-minio"

# Step 1: Check OpenShift connection
echo "Step 1: Checking OpenShift connection..."
if ! oc whoami > /dev/null 2>&1; then
    echo "❌ Not logged into OpenShift. Please run: oc login"
    exit 1
fi
echo "✓ OpenShift connection verified"

# Step 2: Check if MinIO service exists
echo ""
echo "Step 2: Checking MinIO service..."
if ! oc get svc minio -n $MINIO_NAMESPACE > /dev/null 2>&1; then
    echo "❌ MinIO service not found in namespace $MINIO_NAMESPACE"
    echo "Available services:"
    oc get svc -n $MINIO_NAMESPACE
    exit 1
fi
echo "✓ MinIO service found"

# Step 3: Kill any existing port forwarding
echo ""
echo "Step 3: Cleaning up existing port forwarding..."
pkill -f "port-forward.*9000" 2>/dev/null || true
sleep 2

# Step 4: Start fresh port forwarding
echo ""
echo "Step 4: Starting port forwarding..."
oc port-forward -n $MINIO_NAMESPACE svc/minio 9000:9000 &
PORT_FORWARD_PID=$!
echo "Port forwarding started with PID: $PORT_FORWARD_PID"

# Step 5: Wait and test connection
echo ""
echo "Step 5: Testing port forwarding..."
for i in {1..10}; do
    if curl -s http://localhost:9000/minio/health/live > /dev/null 2>&1; then
        echo "✓ Port forwarding successful (attempt $i)"
        break
    else
        echo "Waiting for port forwarding... (attempt $i/10)"
        sleep 2
    fi
    
    if [ $i -eq 10 ]; then
        echo "❌ Port forwarding failed after 10 attempts"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        exit 1
    fi
done

# Step 6: Configure MinIO client
echo ""
echo "Step 6: Configuring MinIO client..."
mc alias set $MINIO_ALIAS http://localhost:9000 minio minio123 --api S3v4

# Step 7: Verify MinIO connection
echo ""
echo "Step 7: Verifying MinIO connection..."
if mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
    echo "✓ MinIO client connected successfully"
else
    echo "❌ MinIO client connection failed"
    kill $PORT_FORWARD_PID 2>/dev/null || true
    exit 1
fi

# Step 8: Configure webhook via MinIO admin
echo ""
echo "Step 8: Configuring webhook target..."

# Remove existing configuration
mc admin config remove $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>/dev/null || true

# Add webhook configuration
mc admin config set $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME \
    endpoint="$WEBHOOK_URL" \
    auth_token="" \
    queue_limit="100"

if [ $? -eq 0 ]; then
    echo "✓ Webhook target configured"
else
    echo "❌ Webhook target configuration failed"
    echo "Trying alternative method..."
    
    # Alternative configuration method
    mc admin config set $MINIO_ALIAS notify_webhook \
        webhook="endpoint=$WEBHOOK_URL"
    
    if [ $? -ne 0 ]; then
        echo "❌ Alternative configuration also failed"
        echo "Manual configuration will be required"
    fi
fi

# Step 9: Restart MinIO
echo ""
echo "Step 9: Restarting MinIO..."
mc admin service restart $MINIO_ALIAS

echo "Waiting 20 seconds for MinIO restart..."
sleep 20

# Step 10: Re-establish port forwarding and connection
echo ""
echo "Step 10: Re-establishing connection after restart..."

# Kill old port forward
kill $PORT_FORWARD_PID 2>/dev/null || true
sleep 2

# Start new port forward
oc port-forward -n $MINIO_NAMESPACE svc/minio 9000:9000 &
NEW_PORT_FORWARD_PID=$!

# Wait for connection
for i in {1..15}; do
    if curl -s http://localhost:9000/minio/health/live > /dev/null 2>&1; then
        echo "✓ Connection re-established (attempt $i)"
        break
    else
        echo "Waiting for MinIO restart... (attempt $i/15)"
        sleep 2
    fi
done

# Re-configure alias
mc alias set $MINIO_ALIAS http://localhost:9000 minio minio123 --api S3v4

# Step 11: Verify webhook configuration
echo ""
echo "Step 11: Verifying webhook configuration..."
WEBHOOK_CHECK=$(mc admin config get $MINIO_ALIAS notify_webhook:$WEBHOOK_NAME 2>&1)
if [[ $WEBHOOK_CHECK == *"error"* ]] || [[ $WEBHOOK_CHECK == *"not found"* ]]; then
    echo "⚠ Webhook configuration verification failed"
    echo "Will attempt bucket notification setup anyway"
else
    echo "✓ Webhook configuration verified"
fi

# Step 12: Configure bucket notifications
echo ""
echo "Step 12: Configuring bucket notifications..."

# Remove existing notifications
mc event remove $MINIO_ALIAS/$BUCKET_NAME --force 2>/dev/null || true

# Try different ARN formats
declare -a ARNS=(
    "arn:minio:sqs::$WEBHOOK_NAME:$WEBHOOK_NAME"
    "arn:minio:sqs:::$WEBHOOK_NAME"
    "arn:minio:sqs::webhook:1"
)

SUCCESS=false
for ARN in "${ARNS[@]}"; do
    echo ""
    echo "Trying ARN: $ARN"
    
    # Test connection before each attempt
    if ! mc ls $MINIO_ALIAS/ > /dev/null 2>&1; then
        echo "Connection lost, skipping ARN: $ARN"
        continue
    fi
    
    # Add .bin notification
    if mc event add $MINIO_ALIAS/$BUCKET_NAME "$ARN" \
        --event put \
        --prefix "02_model_training/models/cats_and_dogs/" \
        --suffix ".bin" 2>/dev/null; then
        
        echo "✓ .bin notification successful"
        
        # Add .xml notification
        if mc event add $MINIO_ALIAS/$BUCKET_NAME "$ARN" \
            --event put \
            --prefix "02_model_training/models/cats_and_dogs/" \
            --suffix ".xml" 2>/dev/null; then
            
            echo "✓ .xml notification successful"
            echo "✅ SUCCESS with ARN: $ARN"
            SUCCESS=true
            break
        fi
    fi
    echo "❌ Failed with ARN: $ARN"
done

# Step 13: Final verification and results
echo ""
echo "Step 13: Final Results..."
echo "============================================"

if [ "$SUCCESS" = true ]; then
    echo "🎉 WEBHOOK CONFIGURATION SUCCESSFUL!"
    echo ""
    echo "Configuration Details:"
    echo "- Webhook URL: $WEBHOOK_URL"
    echo "- Bucket: $BUCKET_NAME"
    echo "- Path: 02_model_training/models/cats_and_dogs/"
    echo "- File Types: .bin, .xml"
    echo ""
    echo "Test the webhook:"
    echo "1. echo 'test model data' > test-model.bin"
    echo "2. mc cp test-model.bin $MINIO_ALIAS/$BUCKET_NAME/02_model_training/models/cats_and_dogs/"
    echo "3. oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm"
    echo ""
    echo "Current bucket notifications:"
    mc event list $MINIO_ALIAS/$BUCKET_NAME 2>/dev/null || echo "Could not list notifications"
    
else
    echo "❌ WEBHOOK CONFIGURATION FAILED"
    echo ""
    echo "Manual Configuration Required:"
    echo ""
    echo "Option 1: MinIO Console UI"
    echo "1. Access MinIO Console (check for route or port-forward port 9001)"
    echo "2. Navigate: Buckets → pipeline-artifacts → Events"
    echo "3. Add Event:"
    echo "   - Service: Webhook"
    echo "   - Endpoint: $WEBHOOK_URL"
    echo "   - Events: s3:ObjectCreated:Put"
    echo "   - Prefix: 02_model_training/models/cats_and_dogs/"
    echo "   - Suffix: .bin (create separate for .xml)"
    echo ""
    echo "Option 2: Check MinIO Console Route"
    oc get routes -n $MINIO_NAMESPACE 2>/dev/null || echo "No routes found"
    echo ""
    echo "Option 3: Manual Test"
    echo "Test webhook directly:"
    echo "curl -X POST '$WEBHOOK_URL' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"action\":\"s3_model_uploaded\",\"model_name\":\"cats-and-dogs\"}'"
fi

echo ""
echo "Port forwarding PID: $NEW_PORT_FORWARD_PID"
echo "To stop port forwarding: kill $NEW_PORT_FORWARD_PID"
echo "============================================"