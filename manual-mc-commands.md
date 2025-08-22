# Manual MinIO Client Commands

## Prerequisites
Make sure you're logged into OpenShift:
```bash
oc login --server=<your-cluster-url>
```

## 1. Install MinIO Client (mc)

### Option A: Using Homebrew (Recommended)
```bash
brew install minio/stable/mc
```

### Option B: Manual Installation
```bash
# Download mc for macOS
curl -O https://dl.min.io/client/mc/release/darwin-amd64/mc

# Make executable and move to PATH
chmod +x mc
sudo mv mc /usr/local/bin/
```

## 2. Set up Port Forwarding
```bash
# Forward MinIO service to local port 9000
oc port-forward -n ic-shared-rag-minio svc/minio 9000:9000
```
**Keep this terminal open!**

## 3. Configure MinIO Alias (in new terminal)
```bash
# Set up alias for local connection
mc alias set myminio http://localhost:9000 minio minio123 --api S3v4

# Test connection
mc ls myminio/
```

## 4. Configure Webhook Target
```bash
# Set webhook configuration
mc admin config set myminio notify_webhook:webhook \
    endpoint="https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com" \
    auth_token="" \
    queue_limit="100"

# Restart MinIO to apply changes
mc admin service restart myminio
```

## 5. Wait and Re-establish Connection
```bash
# Wait 15 seconds for MinIO to restart
sleep 15

# Re-establish connection
mc alias set myminio http://localhost:9000 minio minio123 --api S3v4
```

## 6. Add Event Notifications
```bash
# Add notification for .bin files
mc event add myminio/pipeline-artifacts arn:minio:sqs::webhook:webhook \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".bin"

# Add notification for .xml files
mc event add myminio/pipeline-artifacts arn:minio:sqs::webhook:webhook \
  --event put \
  --prefix "02_model_training/models/cats_and_dogs/" \
  --suffix ".xml"
```

## 7. Verify Configuration
```bash
# List event notifications
mc event list myminio/pipeline-artifacts

# Check webhook configuration
mc admin config get myminio notify_webhook:webhook
```

## 8. Test the Webhook
```bash
# Create test file
echo "test model data" > test-model.bin

# Upload to trigger webhook
mc cp test-model.bin myminio/pipeline-artifacts/02_model_training/models/cats_and_dogs/

# Check webhook logs
oc logs -f deployment/el-s3-model-update-listener -n ic-shared-rag-llm

# Check pipeline runs
oc get pipelineruns -n ic-shared-rag-llm
```

## Troubleshooting

### If connection fails:
```bash
# Check port forwarding is active
curl http://localhost:9000/minio/health/live

# List active port forwards
ps aux | grep "port-forward"
```

### If webhook doesn't trigger:
```bash
# Check MinIO logs
oc logs -f deployment/minio -n ic-shared-rag-minio

# Verify webhook endpoint is reachable
curl -k https://s3-model-trigger-webhook-ic-shared-rag-llm.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com
```

### To remove event notifications:
```bash
mc event remove myminio/pipeline-artifacts arn:minio:sqs::webhook:webhook
```