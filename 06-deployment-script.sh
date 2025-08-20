#!/bin/bash
set -e

# ML Pipelines Deployment Script
# This script deploys the complete CI/CD pipeline for cats_and_dogs model

NAMESPACE="ic-shared-rag-llm"
MODEL_NAME="cats-and-dogs"

echo "============================================"
echo "ML Pipelines Deployment Script"
echo "============================================"
echo "Namespace: ${NAMESPACE}"
echo "Model Name: ${MODEL_NAME}"
echo "Timestamp: $(date)"
echo ""

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if [ -n "$namespace" ]; then
        oc get $resource_type $resource_name -n $namespace >/dev/null 2>&1
    else
        oc get $resource_type $resource_name >/dev/null 2>&1
    fi
}

# Function to wait for resource to be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-300}
    
    echo "Waiting for $resource_type/$resource_name to be ready..."
    oc wait --for=condition=Ready $resource_type/$resource_name -n $namespace --timeout=${timeout}s || true
}

echo "Step 1: Verifying prerequisites..."

# Check if namespace exists
if ! resource_exists namespace $NAMESPACE; then
    echo "Error: Namespace $NAMESPACE does not exist!"
    echo "Please create the namespace first: oc new-project $NAMESPACE"
    exit 1
fi

# Check if secret exists
if ! resource_exists secret aws-shared-rag-connection $NAMESPACE; then
    echo "Error: Secret aws-shared-rag-connection does not exist in namespace $NAMESPACE!"
    echo "Please ensure the S3 connection secret is created."
    exit 1
fi

# Check if Tekton is installed
if ! oc api-resources | grep -q tekton.dev; then
    echo "Error: Tekton is not installed on this cluster!"
    echo "Please install OpenShift Pipelines operator first."
    exit 1
fi

echo "✓ Prerequisites verified"

echo ""
echo "Step 2: Deploying PVCs..."
oc apply -f 01-model-training-pvc.yaml
echo "✓ PVCs deployed"

echo ""
echo "Step 3: Deploying S3 Model Deployment Pipeline..."
oc apply -f 04-s3-model-deployment-pipeline.yaml
echo "✓ S3 Model Deployment Pipeline deployed"

echo ""
echo "Step 4: Deploying Tekton Triggers..."
oc apply -f 05-s3-model-trigger.yaml
echo "✓ Tekton Triggers deployed"

echo ""
echo "Step 5: Waiting for EventListener to be ready..."
sleep 10
wait_for_resource eventlistener s3-model-update-listener $NAMESPACE 120

echo ""
echo "Step 6: Getting webhook URL..."
sleep 5
WEBHOOK_URL=$(oc get route s3-model-trigger-webhook -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-ready")

if [ "$WEBHOOK_URL" != "not-ready" ]; then
    echo "✓ Webhook URL: https://${WEBHOOK_URL}"
else
    echo "⚠ Webhook URL not ready yet, will be available shortly"
fi

echo ""
echo "Step 7: Testing model deployment (optional)..."
read -p "Do you want to trigger a test deployment now? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Triggering test deployment..."
    
    if [ "$WEBHOOK_URL" != "not-ready" ]; then
        TEST_PAYLOAD=$(cat <<EOF
{
    "action": "s3_model_uploaded",
    "event_type": "s3_model_ready",
    "trigger_source": "manual_test",
    "model_name": "${MODEL_NAME}",
    "model_version": "v$(date +%Y%m%d%H%M%S)",
    "s3_model_path": "pipeline-artifacts/02_model_training/models/cats_and_dogs",
    "namespace": "${NAMESPACE}",
    "timestamp": "$(date -Iseconds)"
}
EOF
)
        
        echo "Sending test webhook..."
        curl -X POST "https://${WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -H "Ce-Specversion: 1.0" \
            -H "Ce-Type: s3.model.uploaded" \
            -H "Ce-Source: deployment-script" \
            -d "${TEST_PAYLOAD}" \
            --insecure \
            -w "\nHTTP Status: %{http_code}\n" || echo "Webhook request failed"
        
        echo ""
        echo "Test deployment triggered! Check pipeline runs with:"
        echo "oc get pipelineruns -n ${NAMESPACE} -l app=s3-model-deployment"
    else
        echo "Cannot trigger test - webhook URL not ready"
    fi
else
    echo "Skipping test deployment"
fi

echo ""
echo "============================================"
echo "DEPLOYMENT COMPLETED SUCCESSFULLY!"
echo "============================================"
echo ""
echo "RESOURCES DEPLOYED:"
echo "- PVCs: 02-model-training-v2-pvc, model-artifacts-pvc"
echo "- Pipeline: s3-model-deployment-pipeline"
echo "- Tasks: s3-model-download-task, openshift-ai-model-deploy-task, expose-model-endpoint-task"
echo "- EventListener: s3-model-update-listener"
echo "- Triggers: s3-model-upload-trigger"
echo "- CronJob: s3-cats-dogs-model-checker (checks every 5 minutes)"
echo ""
echo "WEBHOOK ENDPOINT:"
if [ "$WEBHOOK_URL" != "not-ready" ]; then
    echo "- URL: https://${WEBHOOK_URL}"
else
    echo "- URL: (Getting webhook URL...)"
    echo "  Run: oc get route s3-model-trigger-webhook -n ${NAMESPACE} -o jsonpath='{.spec.host}'"
fi
echo ""
echo "HOW IT WORKS:"
echo "1. Elyra pipeline uploads model files to S3: pipeline-artifacts/02_model_training/models/cats_and_dogs"
echo "2. CronJob checks S3 every 5 minutes for model updates"
echo "3. When new/updated model files detected, webhook triggers deployment pipeline"
echo "4. Pipeline downloads models.bin and models.xml from S3"
echo "5. Model deployed to OpenShift AI with OpenVINO runtime"
echo "6. Service and Route created to expose model endpoint"
echo ""
echo "MONITORING:"
echo "- Pipeline runs: oc get pipelineruns -n ${NAMESPACE}"
echo "- Deployments: oc get deployments -n ${NAMESPACE} -l app=model-serving"
echo "- Routes: oc get routes -n ${NAMESPACE} -l app=model-serving"
echo "- Model info: oc get configmap -n ${NAMESPACE} -l app=model-endpoint-info"
echo ""
echo "MANUAL TRIGGER:"
echo "curl -X POST \"https://${WEBHOOK_URL}\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{"
echo "    \"action\": \"s3_model_uploaded\","
echo "    \"model_name\": \"${MODEL_NAME}\","
echo "    \"model_version\": \"v1\","
echo "    \"s3_model_path\": \"pipeline-artifacts/02_model_training/models/cats_and_dogs\","
echo "    \"namespace\": \"${NAMESPACE}\""
echo "  }'"
echo ""
echo "The system is now ready to automatically deploy models when they are updated in S3!"
echo "============================================"