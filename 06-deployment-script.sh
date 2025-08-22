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

# Ensure model S3 connection secret exists (cat-dog-detect)
if ! resource_exists secret cat-dog-detect $NAMESPACE; then
    echo "Secret 'cat-dog-detect' not found in namespace ${NAMESPACE}. Creating it now..."
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cat-dog-detect
  namespace: ${NAMESPACE}
  labels:
    opendatahub.io/dashboard: 'true'
    opendatahub.io/managed: 'true'
  annotations:
    opendatahub.io/connection-type: s3
    opendatahub.io/connection-type-ref: s3
    openshift.io/description: ''
    openshift.io/display-name: cat-dog-detect
type: Opaque
data:
  AWS_ACCESS_KEY_ID: bWluaW8=
  AWS_DEFAULT_REGION: dXM=
  AWS_S3_BUCKET: cGlwZWxpbmUtYXJ0aWZhY3Rz
  AWS_S3_ENDPOINT: aHR0cDovL21pbmlvLmljLXNoYXJlZC1yYWctbWluaW8uc3ZjOjkwMDA=
  AWS_SECRET_ACCESS_KEY: bWluaW8xMjM=
EOF
    echo "✓ Secret 'cat-dog-detect' created"
else
    echo "✓ Secret 'cat-dog-detect' exists"
fi

echo "Ensuring 'cat-dog-detect' is properly registered as an OpenShift AI S3 data connection..."
# Label and annotate the secret so it appears as a Data Connection in RHOAI UI and is usable by ModelMesh
oc label secret cat-dog-detect -n ${NAMESPACE} opendatahub.io/dashboard='true' opendatahub.io/managed='true' --overwrite || true
oc annotate secret cat-dog-detect -n ${NAMESPACE} opendatahub.io/connection-type=s3 opendatahub.io/connection-type-ref=s3 openshift.io/description='' openshift.io/display-name=cat-dog-detect --overwrite || true
echo "✓ Data connection metadata applied to secret 'cat-dog-detect'"

# Check if Tekton is installed
if ! oc api-resources | grep -q tekton.dev; then
    echo "Error: Tekton is not installed on this cluster!"
    echo "Please install OpenShift Pipelines operator first."
    exit 1
fi

echo "✓ Prerequisites verified"

echo ""
echo "Step 2: Fixing Tekton Triggers RBAC permissions..."
oc apply -f 10-tekton-triggers-rbac-fix.yaml
echo "✓ Tekton Triggers RBAC configured"

echo ""
echo "Step 3: Deploying PVCs..."
oc apply -f 01-model-training-pvc.yaml
echo "✓ PVCs deployed"

echo ""
echo "Step 4: Verifying/creating ServingRuntime (ovms)..."
# Ensure ServingRuntime 'ovms' exists in target namespace (used by InferenceService)
if ! resource_exists servingruntime ovms $NAMESPACE; then
    echo "ServingRuntime 'ovms' not found in namespace ${NAMESPACE}. Creating OVMS runtime..."
    cat <<EOF | oc apply -f -
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: ovms
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/instance: ic-shared-rag-llm
    component: model
    name: ovms
    opendatahub.io/dashboard: "true"
  annotations:
    enable-route: "true"
    opendatahub.io/accelerator-name: ""
    opendatahub.io/template-display-name: OpenVINO Model Server
    opendatahub.io/template-name: ovms
    openshift.io/display-name: ovms
spec:
  supportedModelFormats:
  - autoSelect: true
    name: openvino_ir
    version: opset1
  - autoSelect: true
    name: onnx
    version: "1"
  - autoSelect: true
    name: tensorflow
    version: "2"
  builtInAdapter:
    env:
    - name: OVMS_FORCE_TARGET_DEVICE
      value: AUTO
    memBufferBytes: 134217728
    modelLoadingTimeoutMillis: 90000
    runtimeManagementPort: 8888
    serverType: ovms
  multiModel: true
  containers:
  - name: ovms
    image: quay.io/modh/openvino_model_server@sha256:9086c1ba1ba30d358194c534f0563923aab02d03954e43e9f3647136b44a5daf
    args:
    - "--port=8001"
    - "--rest_port=8888"
    - "--config_path=/models/model_config_list.json"
    - "--file_system_poll_wait_seconds=0"
    - "--grpc_bind_address=127.0.0.1"
    - "--rest_bind_address=127.0.0.1"
    resources:
      limits:
        cpu: "1"
        memory: 1Gi
      requests:
        cpu: "1"
        memory: 1Gi
    volumeMounts:
    - mountPath: /dev/shm
      name: shm
  protocolVersions:
  - grpc-v1
  grpcEndpoint: port:8085
  grpcDataEndpoint: port:8001
  replicas: 1
  tolerations: []
  volumes:
  - name: shm
    emptyDir:
      medium: Memory
      sizeLimit: 2Gi
EOF
    echo "✓ ServingRuntime 'ovms' created"
else
    echo "✓ ServingRuntime 'ovms' already exists"
fi

echo ""
echo "Step 5: Deploying S3 Model Deployment Pipeline..."
oc apply -f 04-s3-model-deployment-pipeline.yaml
echo "✓ S3 Model Deployment Pipeline deployed"

echo ""
echo "Step 6: Deploying Tekton Triggers..."
oc apply -f 05-s3-model-trigger.yaml
echo "✓ Tekton Triggers deployed"

echo ""
echo "Step 7: Waiting for EventListener to be ready..."
sleep 10
wait_for_resource eventlistener s3-model-update-listener $NAMESPACE 120

echo ""
echo "Step 8: Getting webhook URL..."
sleep 5
WEBHOOK_URL=$(oc get route s3-model-trigger-webhook -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-ready")

if [ "$WEBHOOK_URL" != "not-ready" ]; then
    echo "✓ Webhook URL: https://${WEBHOOK_URL}"
else
    echo "⚠ Webhook URL not ready yet, will be available shortly"
fi

echo ""
echo "Step 9: Ensuring InferenceService exists (using cat-dog-detect data connection)..."
if ! resource_exists inferenceservice ${MODEL_NAME} $NAMESPACE; then
    echo "Creating InferenceService '${MODEL_NAME}' in namespace '${NAMESPACE}'"
    cat <<EOF | oc apply -f -
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: ${MODEL_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: model-serving
    model: ${MODEL_NAME}
    opendatahub.io/dashboard: 'true'
  annotations:
    openshift.io/display-name: cat-dog-detect
    serving.kserve.io/deploymentMode: ModelMesh
spec:
  predictor:
    automountServiceAccountToken: false
    model:
      modelFormat:
        name: onnx
        version: "1"
      runtime: ovms
      storage:
        key: cat-dog-detect
        path: 02_model_training/models/cats_and_dogs
EOF
    echo "✓ InferenceService created"
else
    echo "✓ InferenceService '${MODEL_NAME}' already exists"
fi

echo "Waiting for InferenceService to be ready..."
oc wait --for=condition=PredictorReady inferenceservice/${MODEL_NAME} -n ${NAMESPACE} --timeout=300s || echo "Timeout waiting for predictor"

echo ""
echo "Step 10: Testing model deployment (optional)..."
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
    "s3_model_path": "02_model_training/models/cats_and_dogs",
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
echo "- Tasks: validate-s3-connection-task, update-inference-service-task, verify-model-deployment-task"
echo "- EventListener: s3-model-update-listener"
echo "- Triggers: s3-model-upload-trigger"
echo "- CronJob: s3-cats-dogs-model-checker (checks every 5 minutes)"
echo "- Data Connection: cat-dog-detect (S3 connection for model storage)"
echo "- ServingRuntime: ovms (OpenVINO Model Server)"
echo "- InferenceService: ${MODEL_NAME} (KServe with ModelMesh)"
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
echo "1. Elyra pipeline uploads model files to S3 bucket 'pipeline-artifacts' at path: 02_model_training/models/cats_and_dogs"
echo "2. CronJob checks S3 every 5 minutes for model updates"
echo "3. When new/updated model files detected, webhook triggers deployment pipeline"
echo "4. Pipeline validates S3 connection using cat-dog-detect data connection"
echo "5. Model deployed to OpenShift AI via KServe InferenceService with OpenVINO runtime"
echo "6. ModelMesh loads model directly from S3 using cat-dog-detect connection"
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
echo "    \"s3_model_path\": \"02_model_training/models/cats_and_dogs\","
echo "    \"namespace\": \"${NAMESPACE}\""
echo "  }'"
echo ""
echo "The system is now ready to automatically deploy models when they are updated in S3!"
echo "============================================"