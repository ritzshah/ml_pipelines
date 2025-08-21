import requests
import numpy as np
from PIL import Image
import json

# Load and preprocess image correctly
img = Image.open('dog.jpg').convert('RGB')

# Resize to exactly 160x160 (model's expected input size)
img = img.resize((160, 160), Image.LANCZOS)  # Use high-quality resampling

# Convert to numpy array and normalize
img_array = np.array(img).astype(np.float32) / 255.0

# Reshape to [1, 160, 160, 3]
img_array = img_array.reshape(1, 160, 160, 3)

print(f"Image shape: {img_array.shape}")
print(f"Pixel range: {img_array.min():.3f} to {img_array.max():.3f}")

# Prepare payload
payload = {
    "inputs": [{
        "name": "layer_0_input",
        "shape": [1, 160, 160, 3],
        "datatype": "FP32",
        "data": img_array.flatten().tolist()
    }]
}

# Send request
response = requests.post(
    "https://cat-dog-detect-ic-shared-img-det.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com/v2/models/cat-dog-detect/infer",
    headers={"Content-Type": "application/json"},
    data=json.dumps(payload)
)

result = response.json()
confidence = result['outputs'][0]['data'][0]

print(f"\nModel output: {confidence}")

# Interpretation
#if confidence > 0.5:
#    print(f"🐶 DOG detected with {confidence*100:.2f}% confidence")
#else:
#    print(f"🐱 CAT detected with {(1-confidence)*100:.2f}% confidence")
