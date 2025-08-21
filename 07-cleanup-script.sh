#!/bin/bash
set -e

# ML Pipelines Cleanup Script
# This script removes all resources created by the deployment script

NAMESPACE="ic-shared-rag-llm"
MODEL_NAME="cats-and-dogs"

echo "============================================"
echo "ML Pipelines Cleanup Script"
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

# Function to delete resource with retry
delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local force=${4:-false}
    
    if resource_exists "$resource_type" "$resource_name" "$namespace"; then
        echo "Deleting $resource_type/$resource_name..."
        
        if [ -n "$namespace" ]; then
            if [ "$force" = "true" ]; then
                oc delete $resource_type $resource_name -n $namespace --force --grace-period=0 || true
            else
                oc delete $resource_type $resource_name -n $namespace || true
            fi
        else
            if [ "$force" = "true" ]; then
                oc delete $resource_type $resource_name --force --grace-period=0 || true
            else
                oc delete $resource_type $resource_name || true
            fi
        fi
        
        # Wait for deletion
        local count=0
        while resource_exists "$resource_type" "$resource_name" "$namespace" && [ $count -lt 30 ]; do
            echo "  Waiting for $resource_type/$resource_name to be deleted..."
            sleep 2
            count=$((count + 1))
        done
        
        if resource_exists "$resource_type" "$resource_name" "$namespace"; then
            echo "  ⚠ $resource_type/$resource_name still exists after 60 seconds"
            if [ "$force" = "true" ]; then
                echo "  Force deletion already attempted"
            else
                echo "  Attempting force deletion..."
                delete_resource "$resource_type" "$resource_name" "$namespace" "true"
            fi
        else
            echo "  ✓ $resource_type/$resource_name deleted successfully"
        fi
    else
        echo "  - $resource_type/$resource_name not found (already deleted)"
    fi
}

# Function to delete all resources matching a label selector
delete_by_label() {
    local resource_type=$1
    local label_selector=$2
    local namespace=$3
    local force=${4:-false}
    
    echo "Deleting all $resource_type with label: $label_selector"
    
    if [ -n "$namespace" ]; then
        local resources=$(oc get $resource_type -l "$label_selector" -n $namespace -o name 2>/dev/null || true)
    else
        local resources=$(oc get $resource_type -l "$label_selector" -o name 2>/dev/null || true)
    fi
    
    if [ -n "$resources" ]; then
        for resource in $resources; do
            local resource_name=$(echo $resource | cut -d'/' -f2)
            delete_resource "$resource_type" "$resource_name" "$namespace" "$force"
        done
    else
        echo "  - No $resource_type found with label: $label_selector"
    fi
}

echo "Step 1: Stopping active pipeline runs..."
delete_by_label "pipelineruns" "app=s3-model-deployment" "$NAMESPACE" "true"
delete_by_label "pipelineruns" "model=${MODEL_NAME}" "$NAMESPACE" "true"
delete_by_label "taskruns" "app=s3-model-deployment" "$NAMESPACE" "true"

echo ""
echo "Step 2: Deleting model deployments and services..."
delete_resource "deployment" "${MODEL_NAME}-deployment" "$NAMESPACE"
delete_resource "deployment" "${MODEL_NAME}-openvino-server" "$NAMESPACE"
delete_resource "service" "${MODEL_NAME}-service" "$NAMESPACE"
delete_resource "route" "${MODEL_NAME}-route" "$NAMESPACE"

echo ""
echo "Step 3: Deleting ConfigMaps..."
delete_resource "configmap" "${MODEL_NAME}-model-files" "$NAMESPACE"
delete_resource "configmap" "${MODEL_NAME}-model-config" "$NAMESPACE"
delete_resource "configmap" "${MODEL_NAME}-endpoint-info" "$NAMESPACE"
delete_by_label "configmap" "app=model-endpoint-info" "$NAMESPACE"

echo ""
echo "Step 4: Deleting KServe resources..."
delete_resource "inferenceservice" "${MODEL_NAME}" "$NAMESPACE"
delete_resource "servingruntime" "${MODEL_NAME}-openvino-runtime" "$NAMESPACE"

echo ""
echo "Step 5: Deleting Tekton pipeline resources..."
delete_resource "pipeline" "s3-model-deployment-pipeline" "$NAMESPACE"
delete_resource "task" "s3-model-download-task" "$NAMESPACE"
delete_resource "task" "openshift-ai-model-deploy-task" "$NAMESPACE"
delete_resource "task" "expose-model-endpoint-task" "$NAMESPACE"

echo ""
echo "Step 6: Deleting Tekton triggers..."
delete_resource "eventlistener" "s3-model-update-listener" "$NAMESPACE"
delete_resource "triggerbinding" "s3-model-deployment-binding" "$NAMESPACE"
delete_resource "triggertemplate" "s3-model-deployment-template" "$NAMESPACE"
delete_resource "task" "s3-model-watcher-task" "$NAMESPACE"

echo ""
echo "Step 7: Deleting trigger services and routes..."
delete_resource "service" "el-s3-model-update-listener" "$NAMESPACE"
delete_resource "route" "s3-model-trigger-webhook" "$NAMESPACE"

echo ""
echo "Step 8: Deleting CronJobs and monitoring..."
delete_resource "cronjob" "s3-cats-dogs-model-checker" "$NAMESPACE"
delete_by_label "job" "app=s3-model-deployment-scheduler" "$NAMESPACE" "true"

echo ""
echo "Step 9: Deleting RBAC resources..."
delete_resource "rolebinding" "tekton-triggers-binding" "$NAMESPACE"
delete_resource "role" "tekton-triggers-role" "$NAMESPACE"
delete_resource "serviceaccount" "tekton-triggers-sa" "$NAMESPACE"

# Delete cluster-scoped RBAC resources
delete_resource "clusterrolebinding" "tekton-triggers-cluster-binding" ""
delete_resource "clusterrole" "tekton-triggers-cluster-role" ""

echo ""
echo "Step 10: Force deleting PVCs and storage..."
delete_resource "pvc" "${MODEL_NAME}-model-storage" "$NAMESPACE" "true"
delete_resource "pvc" "${MODEL_NAME}-model-files-pvc" "$NAMESPACE" "true"
delete_resource "pvc" "02-model-training-v2-pvc" "$NAMESPACE" "true"
delete_resource "pvc" "model-artifacts-pvc" "$NAMESPACE" "true"

# Delete model copy jobs
delete_resource "job" "${MODEL_NAME}-copy-model-files" "$NAMESPACE" "true"

# Delete any PVCs created by volumeClaimTemplates
delete_by_label "pvc" "app=s3-model-deployment" "$NAMESPACE" "true"

echo ""
echo "Step 11: Cleaning up any remaining pods..."
delete_by_label "pod" "app=s3-model-deployment" "$NAMESPACE" "true"
delete_by_label "pod" "model=${MODEL_NAME}" "$NAMESPACE" "true"
delete_by_label "pod" "app=model-serving" "$NAMESPACE" "true"

echo ""
echo "Step 12: Verification - Checking for remaining resources..."

# List any remaining resources
echo "Checking for remaining pipeline resources..."
oc get pipelines,tasks,pipelineruns,taskruns -n $NAMESPACE -l app=s3-model-deployment 2>/dev/null || echo "  ✓ No pipeline resources found"

echo "Checking for remaining trigger resources..."
oc get eventlisteners,triggerbindings,triggertemplates -n $NAMESPACE 2>/dev/null || echo "  ✓ No trigger resources found"

echo "Checking for remaining model serving resources..."
oc get deployments,services,routes,configmaps -n $NAMESPACE -l model=${MODEL_NAME} 2>/dev/null || echo "  ✓ No model serving resources found"

echo "Checking for remaining PVCs..."
oc get pvc -n $NAMESPACE | grep -E "(${MODEL_NAME}|model-artifacts|02-model-training)" || echo "  ✓ No model-related PVCs found"

echo "Checking for remaining CronJobs..."
oc get cronjobs -n $NAMESPACE | grep "s3.*model" || echo "  ✓ No model-related CronJobs found"

echo ""
echo "Step 13: Force cleanup any stuck resources..."

# Find and force delete any stuck resources
echo "Checking for stuck resources..."

# Force delete any remaining PVCs with finalizers
STUCK_PVCS=$(oc get pvc -n $NAMESPACE -o name | grep -E "(${MODEL_NAME}|model-artifacts|02-model-training)" 2>/dev/null || true)
if [ -n "$STUCK_PVCS" ]; then
    echo "Found stuck PVCs, removing finalizers..."
    for pvc in $STUCK_PVCS; do
        pvc_name=$(echo $pvc | cut -d'/' -f2)
        echo "  Removing finalizers from $pvc_name..."
        oc patch pvc $pvc_name -n $NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge || true
        oc delete pvc $pvc_name -n $NAMESPACE --force --grace-period=0 || true
    done
fi

# Force delete any remaining InferenceServices
STUCK_ISVC=$(oc get inferenceservice -n $NAMESPACE -o name 2>/dev/null | grep "${MODEL_NAME}" || true)
if [ -n "$STUCK_ISVC" ]; then
    echo "Found stuck InferenceServices, removing finalizers..."
    for isvc in $STUCK_ISVC; do
        isvc_name=$(echo $isvc | cut -d'/' -f2)
        echo "  Removing finalizers from $isvc_name..."
        oc patch inferenceservice $isvc_name -n $NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge || true
        oc delete inferenceservice $isvc_name -n $NAMESPACE --force --grace-period=0 || true
    done
fi

echo ""
echo "============================================"
echo "CLEANUP COMPLETED!"
echo "============================================"
echo ""
echo "SUMMARY:"
echo "- All pipeline resources deleted"
echo "- All trigger resources deleted"  
echo "- All model serving resources deleted"
echo "- All PVCs force deleted"
echo "- All RBAC resources deleted"
echo "- All monitoring resources deleted"
echo ""
echo "FINAL VERIFICATION:"
echo "Run the following commands to verify cleanup:"
echo ""
echo "# Check for any remaining resources:"
echo "oc get all,pvc,configmap,secret,cronjob -n ${NAMESPACE} | grep -i \"${MODEL_NAME}\\|s3-model\\|model-artifacts\\|02-model-training\""
echo ""
echo "# Check for any remaining Tekton resources:"
echo "oc get pipelines,tasks,pipelineruns,taskruns,eventlisteners,triggerbindings,triggertemplates -n ${NAMESPACE}"
echo ""
echo "# Check for any remaining KServe resources:"
echo "oc get inferenceservices,servingruntimes -n ${NAMESPACE}"
echo ""
echo "If any resources remain, you can manually delete them with:"
echo "oc delete [resource-type] [resource-name] -n ${NAMESPACE} --force --grace-period=0"
echo ""
echo "Cleanup completed at: $(date)"
echo "============================================"