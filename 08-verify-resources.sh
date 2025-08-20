#!/bin/bash

# Resource Verification Script
# This script lists all resources created by the ML pipelines system

NAMESPACE="ic-shared-rag-llm"
MODEL_NAME="cats-and-dogs"

echo "============================================"
echo "ML Pipelines Resource Verification"
echo "============================================"
echo "Namespace: ${NAMESPACE}"
echo "Model Name: ${MODEL_NAME}"
echo "Timestamp: $(date)"
echo ""

# Function to check and list resources
check_resources() {
    local resource_type=$1
    local label_selector=$2
    local namespace=$3
    local description=$4
    
    echo "=== $description ==="
    
    if [ -n "$label_selector" ]; then
        if [ -n "$namespace" ]; then
            oc get $resource_type -l "$label_selector" -n $namespace 2>/dev/null || echo "No $resource_type found with label: $label_selector"
        else
            oc get $resource_type -l "$label_selector" 2>/dev/null || echo "No $resource_type found with label: $label_selector"
        fi
    else
        if [ -n "$namespace" ]; then
            oc get $resource_type -n $namespace 2>/dev/null || echo "No $resource_type found"
        else
            oc get $resource_type 2>/dev/null || echo "No $resource_type found"
        fi
    fi
    echo ""
}

# Function to check specific resources by name pattern
check_named_resources() {
    local resource_type=$1
    local name_pattern=$2
    local namespace=$3
    local description=$4
    
    echo "=== $description ==="
    
    if [ -n "$namespace" ]; then
        oc get $resource_type -n $namespace 2>/dev/null | grep -E "$name_pattern" || echo "No $resource_type found matching: $name_pattern"
    else
        oc get $resource_type 2>/dev/null | grep -E "$name_pattern" || echo "No $resource_type found matching: $name_pattern"
    fi
    echo ""
}

echo "TEKTON PIPELINE RESOURCES:"
check_resources "pipelines" "app=ml-pipeline" "$NAMESPACE" "Pipelines"
check_resources "tasks" "" "$NAMESPACE" "Tasks"
check_resources "pipelineruns" "app=s3-model-deployment" "$NAMESPACE" "Pipeline Runs"
check_resources "taskruns" "app=s3-model-deployment" "$NAMESPACE" "Task Runs"

echo "TEKTON TRIGGER RESOURCES:"
check_resources "eventlisteners" "" "$NAMESPACE" "Event Listeners"
check_resources "triggerbindings" "" "$NAMESPACE" "Trigger Bindings"
check_resources "triggertemplates" "" "$NAMESPACE" "Trigger Templates"

echo "MODEL SERVING RESOURCES:"
check_resources "deployments" "app=model-serving" "$NAMESPACE" "Model Deployments"
check_resources "services" "app=model-serving" "$NAMESPACE" "Model Services"
check_resources "routes" "app=model-serving" "$NAMESPACE" "Model Routes"

echo "KSERVE RESOURCES:"
check_resources "inferenceservices" "" "$NAMESPACE" "Inference Services"
check_resources "servingruntimes" "" "$NAMESPACE" "Serving Runtimes"

echo "STORAGE RESOURCES:"
check_named_resources "pvc" "${MODEL_NAME}|model-artifacts|02-model-training" "$NAMESPACE" "Persistent Volume Claims"

echo "CONFIGURATION RESOURCES:"
check_resources "configmaps" "app=model-endpoint-info" "$NAMESPACE" "Model ConfigMaps"
check_named_resources "configmaps" "${MODEL_NAME}" "$NAMESPACE" "Model-specific ConfigMaps"

echo "MONITORING RESOURCES:"
check_resources "cronjobs" "app=s3-model-deployment-scheduler" "$NAMESPACE" "CronJobs"
check_named_resources "jobs" "s3.*model" "$NAMESPACE" "Monitoring Jobs"

echo "RBAC RESOURCES:"
check_resources "serviceaccounts" "" "$NAMESPACE" "Service Accounts"
check_resources "roles" "" "$NAMESPACE" "Roles"
check_resources "rolebindings" "" "$NAMESPACE" "Role Bindings"

echo "TRIGGER NETWORKING:"
check_named_resources "services" "s3-model" "$NAMESPACE" "Trigger Services"
check_named_resources "routes" "s3-model" "$NAMESPACE" "Trigger Routes"

echo "PODS AND RUNTIME:"
check_resources "pods" "app=model-serving" "$NAMESPACE" "Model Serving Pods"
check_resources "pods" "app=s3-model-deployment" "$NAMESPACE" "Pipeline Pods"

echo "============================================"
echo "SUMMARY CHECK"
echo "============================================"

# Count total resources
TOTAL_PIPELINES=$(oc get pipelines -n $NAMESPACE 2>/dev/null | grep -c "s3-model" || echo "0")
TOTAL_TASKS=$(oc get tasks -n $NAMESPACE 2>/dev/null | grep -c -E "(s3-model|openshift-ai|expose-model)" || echo "0")
TOTAL_TRIGGERS=$(oc get eventlisteners,triggerbindings,triggertemplates -n $NAMESPACE 2>/dev/null | grep -c "s3-model" || echo "0")
TOTAL_DEPLOYMENTS=$(oc get deployments -n $NAMESPACE 2>/dev/null | grep -c "$MODEL_NAME" || echo "0")
TOTAL_PVCS=$(oc get pvc -n $NAMESPACE 2>/dev/null | grep -c -E "${MODEL_NAME}|model-artifacts|02-model-training" || echo "0")
TOTAL_CRONJOBS=$(oc get cronjobs -n $NAMESPACE 2>/dev/null | grep -c "s3.*model" || echo "0")

echo "Resource Count Summary:"
echo "- Pipelines: $TOTAL_PIPELINES"
echo "- Tasks: $TOTAL_TASKS" 
echo "- Triggers: $TOTAL_TRIGGERS"
echo "- Deployments: $TOTAL_DEPLOYMENTS"
echo "- PVCs: $TOTAL_PVCS"
echo "- CronJobs: $TOTAL_CRONJOBS"
echo ""

if [ "$TOTAL_PIPELINES" -gt 0 ] || [ "$TOTAL_TASKS" -gt 0 ] || [ "$TOTAL_TRIGGERS" -gt 0 ] || [ "$TOTAL_DEPLOYMENTS" -gt 0 ] || [ "$TOTAL_PVCS" -gt 0 ] || [ "$TOTAL_CRONJOBS" -gt 0 ]; then
    echo "Status: ⚠ ML Pipeline resources found"
    echo "Run ./07-cleanup-script.sh to remove all resources"
else
    echo "Status: ✓ No ML Pipeline resources found"
    echo "System is clean"
fi

echo ""
echo "============================================"