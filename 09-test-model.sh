#!/bin/bash

# Model Testing Script for Cats and Dogs Classification
# This script tests the deployed model with sample images

NAMESPACE="ic-shared-rag-llm"
MODEL_NAME="cats-and-dogs"

echo "============================================"
echo "Cats and Dogs Model Testing Script"
echo "============================================"
echo "Namespace: ${NAMESPACE}"
echo "Model Name: ${MODEL_NAME}"
echo "Timestamp: $(date)"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
echo "Checking dependencies..."
if ! command_exists curl; then
    echo "Error: curl is required but not installed"
    exit 1
fi

if ! command_exists oc; then
    echo "Error: oc (OpenShift CLI) is required but not installed"
    exit 1
fi

if ! command_exists base64; then
    echo "Error: base64 is required but not installed"
    exit 1
fi

echo "✓ All dependencies found"
echo ""

# Get model endpoint URL
echo "Step 1: Getting model endpoint URL..."
MODEL_URL=$(oc get route ${MODEL_NAME}-route -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$MODEL_URL" ]; then
    echo "Error: Model route not found!"
    echo "Check if the model is deployed:"
    echo "  oc get routes -n ${NAMESPACE}"
    exit 1
fi

echo "✓ Model URL: https://${MODEL_URL}"
echo ""

# Test health endpoint
echo "Step 2: Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s "https://${MODEL_URL}/v1/config" 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "✓ Health check successful"
    echo "Response: $HEALTH_RESPONSE"
else
    echo "⚠ Health check failed - model may not be ready yet"
    echo "Continuing with other tests..."
fi
echo ""

# Test model info endpoint
echo "Step 3: Testing model info endpoint..."
MODEL_INFO=$(curl -s "https://${MODEL_URL}/v1/models/${MODEL_NAME}" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$MODEL_INFO" ]; then
    echo "✓ Model info retrieved successfully"
    echo "Response: $MODEL_INFO"
else
    echo "⚠ Model info request failed"
fi
echo ""

# Download test images if they don't exist
echo "Step 4: Preparing test images..."

if [ ! -f "cat.jpg" ]; then
    echo "Downloading sample cat image..."
    curl -s -o cat.jpg "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=224&h=224&fit=crop" || {
        echo "Failed to download cat image, creating placeholder..."
        # Create a simple test file if download fails
        echo "placeholder_cat_image_data" > cat.jpg
    }
fi

if [ ! -f "dog.jpg" ]; then
    echo "Downloading sample dog image..."
    curl -s -o dog.jpg "https://images.unsplash.com/photo-1552053831-71594a27632d?w=224&h=224&fit=crop" || {
        echo "Failed to download dog image, creating placeholder..."
        # Create a simple test file if download fails
        echo "placeholder_dog_image_data" > dog.jpg
    }
fi

echo "✓ Test images prepared"
echo ""

# Function to test prediction
test_prediction() {
    local image_file=$1
    local image_type=$2
    
    echo "Testing prediction for $image_type image ($image_file)..."
    
    if [ ! -f "$image_file" ]; then
        echo "⚠ Image file $image_file not found, skipping..."
        return
    fi
    
    # Convert image to base64
    IMAGE_BASE64=$(base64 -w 0 "$image_file" 2>/dev/null)
    
    if [ -z "$IMAGE_BASE64" ]; then
        echo "⚠ Failed to encode $image_file to base64, skipping..."
        return
    fi
    
    # Make prediction request
    PREDICTION_RESPONSE=$(curl -s -X POST "https://${MODEL_URL}/v1/models/${MODEL_NAME}:predict" \
        -H "Content-Type: application/json" \
        -d "{\"instances\": [{\"data\": \"${IMAGE_BASE64}\"}]}" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$PREDICTION_RESPONSE" ]; then
        echo "✓ Prediction successful for $image_type"
        echo "Response: $PREDICTION_RESPONSE"
        
        # Try to parse prediction (basic parsing)
        if echo "$PREDICTION_RESPONSE" | grep -q "predictions"; then
            echo "✓ Response contains predictions field"
        else
            echo "⚠ Response format may be unexpected"
        fi
    else
        echo "✗ Prediction failed for $image_type"
        echo "Response: $PREDICTION_RESPONSE"
    fi
    echo ""
}

# Test cat image prediction
echo "Step 5: Testing cat image prediction..."
test_prediction "cat.jpg" "cat"

# Test dog image prediction
echo "Step 6: Testing dog image prediction..."
test_prediction "dog.jpg" "dog"

# Test batch prediction
echo "Step 7: Testing batch prediction..."
if [ -f "cat.jpg" ] && [ -f "dog.jpg" ]; then
    CAT_BASE64=$(base64 -w 0 cat.jpg 2>/dev/null)
    DOG_BASE64=$(base64 -w 0 dog.jpg 2>/dev/null)
    
    if [ -n "$CAT_BASE64" ] && [ -n "$DOG_BASE64" ]; then
        echo "Testing batch prediction with both images..."
        BATCH_RESPONSE=$(curl -s -X POST "https://${MODEL_URL}/v1/models/${MODEL_NAME}:predict" \
            -H "Content-Type: application/json" \
            -d "{\"instances\": [{\"data\": \"${CAT_BASE64}\"}, {\"data\": \"${DOG_BASE64}\"}]}" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$BATCH_RESPONSE" ]; then
            echo "✓ Batch prediction successful"
            echo "Response: $BATCH_RESPONSE"
        else
            echo "✗ Batch prediction failed"
            echo "Response: $BATCH_RESPONSE"
        fi
    else
        echo "⚠ Could not encode images for batch test"
    fi
else
    echo "⚠ Test images not available for batch test"
fi
echo ""

# Summary
echo "============================================"
echo "MODEL TESTING COMPLETED"
echo "============================================"
echo ""
echo "Model Endpoint: https://${MODEL_URL}"
echo ""
echo "MANUAL TESTING COMMANDS:"
echo ""
echo "# Health check:"
echo "curl \"https://${MODEL_URL}/v1/config\""
echo ""
echo "# Model info:"
echo "curl \"https://${MODEL_URL}/v1/models/${MODEL_NAME}\""
echo ""
echo "# Single prediction (replace with your image):"
echo "curl -X POST \"https://${MODEL_URL}/v1/models/${MODEL_NAME}:predict\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d \"{\\\"instances\\\": [{\\\"data\\\": \\\"\$(base64 -w 0 your_image.jpg)\\\"}]}\""
echo ""
echo "PREDICTION FORMAT:"
echo "- Output: [cat_probability, dog_probability]"
echo "- Values sum to 1.0"
echo "- Higher value = predicted class"
echo "- Example: [0.8, 0.2] = 80% cat, 20% dog"
echo ""
echo "============================================"