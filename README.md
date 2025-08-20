# ML Pipelines - S3-Based Model Deployment CI/CD

This repository contains a comprehensive CI/CD system for automated machine learning model deployment using Tekton pipelines, S3 storage integration, and OpenShift AI with OpenVINO runtime.

## Overview

The system automatically monitors S3 storage for model updates and triggers deployment pipelines when new cats and dogs classification models are uploaded by Elyra pipelines. The deployed models are served using OpenVINO runtime in OpenShift AI with exposed endpoints for inference.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│ Elyra Pipeline  │    │ S3 Storage       │    │ Tekton CI/CD        │
│ (Model Training)│───▶│ Model Artifacts  │───▶│ Deployment Pipeline │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
                                                           │
                                                           ▼
                                                ┌─────────────────────┐
                                                │ OpenShift AI        │
                                                │ OpenVINO Runtime    │
                                                │ Model Serving       │
                                                └─────────────────────┘
```

## Components

### 1. S3 Model Storage
- **Bucket**: `pipeline-artifacts`
- **Path**: `02_model_training/models/cats_and_dogs`
- **Files**: `model.bin`, `model.xml` (OpenVINO IR format)
- **Secret**: `aws-shared-rag-connection` (pre-configured S3 credentials)

### 2. Automated Monitoring
- **CronJob**: Checks S3 every 5 minutes for model updates
- **Webhook Triggers**: Manual deployment trigger via REST API
- **EventListeners**: Responds to S3 model upload events

### 3. Deployment Pipeline
- **S3 Download Task**: Retrieves model files from S3 storage
- **OpenShift AI Deploy Task**: Creates KServe/ModelMesh deployment
- **Endpoint Exposure Task**: Creates routes and services for inference

## Quick Start

### Prerequisites
- OpenShift cluster with OpenShift AI operator installed
- Tekton Pipelines operator installed
- Project/namespace: `ic-shared-rag-llm`
- S3 secret: `aws-shared-rag-connection` configured

### Deployment

1. **Deploy the complete system**:
   ```bash
   chmod +x 06-deployment-script.sh
   ./06-deployment-script.sh
   ```

2. **Verify deployment**:
   ```bash
   # Check pipeline components
   oc get pipelines -n ic-shared-rag-llm
   oc get tasks -n ic-shared-rag-llm
   oc get eventlisteners -n ic-shared-rag-llm
   
   # Check CronJob monitoring
   oc get cronjobs -n ic-shared-rag-llm
   ```

3. **Get webhook URL**:
   ```bash
   oc get route s3-model-trigger-webhook -n ic-shared-rag-llm -o jsonpath='{.spec.host}'
   ```

### Cleanup

**Verify existing resources**:
```bash
./08-verify-resources.sh
```

**Complete cleanup** (removes all deployed resources):
```bash
./07-cleanup-script.sh
```

**Manual verification after cleanup**:
```bash
# Check for any remaining resources
oc get all,pvc,configmap,cronjob -n ic-shared-rag-llm | grep -i "cats-and-dogs\|s3-model\|model-artifacts"

# Check Tekton resources
oc get pipelines,tasks,eventlisteners -n ic-shared-rag-llm
```

## Usage

### Automatic Deployment
The system automatically monitors S3 and deploys models when:
- New model files are uploaded to the S3 path
- Existing model files are updated (based on modification time)
- CronJob detects changes every 5 minutes

### Manual Deployment
Trigger deployment manually via webhook:

```bash
WEBHOOK_URL=$(oc get route s3-model-trigger-webhook -n ic-shared-rag-llm -o jsonpath='{.spec.host}')

curl -X POST "https://${WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "s3_model_uploaded",
    "model_name": "cats-and-dogs",
    "model_version": "v1",
    "s3_model_path": "02_model_training/models/cats_and_dogs",
    "namespace": "ic-shared-rag-llm"
  }'
```

### Model Inference
Once deployed, access the model endpoints:

```bash
# Get model endpoint URL
MODEL_URL=$(oc get route cats-and-dogs-route -n ic-shared-rag-llm -o jsonpath='{.spec.host}')

# Health check
curl "https://${MODEL_URL}/v1/config"

# Model information
curl "https://${MODEL_URL}/v1/models/cats-and-dogs"

# Make predictions
curl -X POST "https://${MODEL_URL}/v1/models/cats-and-dogs:predict" \
  -H "Content-Type: application/json" \
  -d '{
    "instances": [
      {
        "data": "base64_encoded_image_data"
      }
    ]
  }'
```

## Monitoring

### Pipeline Runs
```bash
# List all pipeline runs
oc get pipelineruns -n ic-shared-rag-llm

# Watch pipeline run progress
oc get pipelineruns -n ic-shared-rag-llm -w

# Get pipeline run logs
oc logs -f pipelinerun/[PIPELINE-RUN-NAME] -n ic-shared-rag-llm
```

### Model Deployments
```bash
# Check model deployments
oc get deployments -n ic-shared-rag-llm -l app=model-serving

# Check model services and routes
oc get services -n ic-shared-rag-llm -l app=model-serving
oc get routes -n ic-shared-rag-llm -l app=model-serving

# Get endpoint information
oc get configmap -n ic-shared-rag-llm -l app=model-endpoint-info
```

### S3 Monitoring
```bash
# Check CronJob status
oc get cronjobs s3-cats-dogs-model-checker -n ic-shared-rag-llm

# View CronJob logs
oc logs job/[JOB-NAME] -n ic-shared-rag-llm
```

### Event Listeners
```bash
# Check EventListener status
oc get eventlisteners -n ic-shared-rag-llm

# View EventListener logs
oc logs deployment/el-s3-model-update-listener -n ic-shared-rag-llm
```

## File Structure

```
ml_pipelines/
├── 01-model-training-pvc.yaml          # PVC for model storage
├── 02-tekton-model-deployment-pipeline.yaml  # Legacy pipeline
├── 03-tekton-triggers.yaml             # Legacy triggers
├── 04-s3-model-deployment-pipeline.yaml    # Main S3 deployment pipeline
├── 05-s3-model-trigger.yaml            # S3 triggers and monitoring
├── 06-deployment-script.sh             # Automated deployment script
├── 07-cleanup-script.sh               # Complete cleanup script
├── 08-verify-resources.sh             # Resource verification script
└── README.md                           # This documentation
```

## Configuration

### S3 Configuration
The system uses the existing `aws-shared-rag-connection` secret with:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`  
- `AWS_DEFAULT_REGION`
- `AWS_S3_ENDPOINT`
- `AWS_S3_BUCKET`

### Model Configuration
- **Model Name**: `cats-and-dogs`
- **Model Type**: Image classification (cats vs dogs)
- **Framework**: OpenVINO IR format
- **Input Shape**: `[1, 3, 224, 224]` (batch, channels, height, width)
- **Output Shape**: `[1, 2]` (batch, classes)
- **Classes**: `["cat", "dog"]`

## Troubleshooting

### Pipeline Failures
```bash
# Check pipeline run status
oc describe pipelinerun [PIPELINE-RUN-NAME] -n ic-shared-rag-llm

# Check task logs
oc logs [POD-NAME] -c step-[STEP-NAME] -n ic-shared-rag-llm
```

### S3 Connection Issues
```bash
# Verify S3 secret
oc get secret aws-shared-rag-connection -n ic-shared-rag-llm -o yaml

# Test S3 connectivity
oc run s3-test --image=quay.io/opendatahub/workbench-images:jupyter-datascience-ubi9-python-3.9-2023b-20231016 \
  --env="AWS_ACCESS_KEY_ID=$(oc get secret aws-shared-rag-connection -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)" \
  --restart=Never -- python3 -c "import boto3; print('S3 connection test')"
```

### Model Serving Issues
```bash
# Check model deployment logs
oc logs deployment/cats-and-dogs-deployment -n ic-shared-rag-llm

# Check OpenVINO server status
oc port-forward deployment/cats-and-dogs-deployment 8080:8080 -n ic-shared-rag-llm
curl http://localhost:8080/v1/config
```

### Webhook Issues
```bash
# Check EventListener status
oc get eventlisteners s3-model-update-listener -n ic-shared-rag-llm

# Test webhook manually
WEBHOOK_URL=$(oc get route s3-model-trigger-webhook -n ic-shared-rag-llm -o jsonpath='{.spec.host}')
curl -X POST "https://${WEBHOOK_URL}" -H "Content-Type: application/json" -d '{"test": "webhook"}'
```

## Integration with Elyra

This CI/CD system is designed to work seamlessly with the existing Elyra pipeline:

1. **Elyra Pipeline**: Trains the cats and dogs classification model
2. **Upload Task**: Uploads `model.bin` and `model.xml` to S3 storage
3. **Automatic Trigger**: S3 monitoring detects new/updated files
4. **Deployment**: Tekton pipeline automatically deploys the model
5. **Serving**: Model becomes available via OpenShift AI endpoints

## Security Considerations

- S3 credentials are stored securely in OpenShift secrets
- All communications use TLS encryption
- RBAC controls access to pipeline resources
- Model endpoints are secured with OpenShift routes

## Performance

- **Monitoring Frequency**: 5-minute intervals (configurable)
- **Deployment Time**: ~5-10 minutes for complete deployment
- **Model Serving**: Auto-scaling based on OpenShift AI configuration
- **Resource Requests**: 500m CPU, 1Gi memory (configurable)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes in a development environment
4. Submit a pull request with detailed description

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review OpenShift AI and Tekton documentation
3. Check pipeline run logs for specific error messages
4. Verify S3 connectivity and permissions

---

**Note**: This system provides a production-ready foundation for automated ML model deployment. Customize the configurations based on your specific requirements for different models, storage backends, or serving frameworks.