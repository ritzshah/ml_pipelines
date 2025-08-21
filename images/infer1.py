import requests
import numpy as np
from PIL import Image
import json

img = Image.open('cat.jpg').convert('RGB')
img = img.resize((160, 160), Image.LANCZOS)
img_array = np.array(img).astype(np.float32) / 255.0
img_array = img_array.reshape(1, 160, 160, 3)

payload = {
    'inputs': [{
        'name': 'layer_0_input',
        'shape': [1, 160, 160, 3],
        'datatype': 'FP32',
        'data': img_array.flatten().tolist()
    }]
}

response = requests.post(
    'https://cat-dog-detect-ic-shared-img-det.apps.cluster-bq2z4.bq2z4.sandbox2576.opentlc.com/v2/models/cat-dog-detect/infer',
    headers={'Content-Type': 'application/json'},
    data=json.dumps(payload)
)

result = response.json()
confidence = result['outputs'][0]['data'][0]
print(f'Cat image result: {confidence}')

