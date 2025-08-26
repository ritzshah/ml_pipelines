## NYSE Stock Pipeline on OpenShift AI (OpenDataHub, Kubeflow, KServe, OVMS)

This project sketches an end-to-end pipeline: data collection → storage (PVC) → local processing (pandas) → training (KFP) → evaluation/selection → optimization → deployment (KServe + OpenVINO Model Server) → monitoring.

PVC note: data is written to a PVC mount path you configure in your pipeline/workbench (e.g., `/mnt/pvc/nyse-data`).

### References
- OpenShift AI Data Science Pipelines (KFP v2): [docs](https://ai-on-openshift.io/tools-and-applications/datasciencepipeline/datasciencepipeline/)
- OpenDataHub model serving (KServe runtimes): [docs](https://opendatahub.io/docs/serving-models/)
- KServe (Kubeflow Serving): [intro](https://www.kubeflow.org/docs/external-add-ons/kserve/introduction/)
- OpenVINO Model Server with KServe/OVMS: [OVMS docs](https://docs.openvino.ai/latest/ovms_docs_overview.html)
- Installing KServe via OpenDataHub: [guide](https://developers.redhat.com/articles/2024/06/27/how-install-kserve-using-open-data-hub)
- Spark on OpenShift/ODH (Spark Operator): [guide](https://ai-on-openshift.io/tools-and-applications/odh-spark/)

### Structure
- `components/data_download/` — scripts to fetch NYSE data into PVC
- `pipeline/` — KFP pipeline (to be added)
 - `pipeline/` — KFP pipeline
- `components/feature_engineering/` — pandas-based feature generation

### Data download quick start (workbench or pipeline step)
1) Ensure a PVC is mounted at your desired path (e.g., `/mnt/pvc`).
2) Install requirements: `pip install -r components/data_download/requirements.txt`
3) Run: `python components/data_download/download_nyse.py --symbols AAPL,MSFT,GOOG --start 2015-01-01 --end 2025-01-01 --out /mnt/pvc/nyse-data`


### Feature engineering (local pandas)
```bash
pip install -r components/feature_engineering/requirements.txt
python components/feature_engineering/feature_engineering.py --input_root /mnt/pvc/nyse-data --output /mnt/pvc/nyse-features
```

### LSTM training
```bash
pip install -r components/training_lstm/requirements.txt
python components/training_lstm/train_lstm.py --features_dir /mnt/pvc/nyse-features --out /mnt/pvc/nyse-models --window 20 --horizon 1 --epochs 5
```

### ARIMA training
```bash
pip install -r components/training_arima/requirements.txt
python components/training_arima/train_arima.py --features_dir /mnt/pvc/nyse-features --out /mnt/pvc/nyse-models --order 5,1,0
```

### Model selection
```bash
pip install -r components/model_selection/requirements.txt
python components/model_selection/select_best.py --metrics_dir /mnt/pvc/nyse-models --out /mnt/pvc/nyse-models/best.json
```

### OpenVINO conversion (for TF SavedModel)
```bash
pip install -r components/openvino_convert/requirements.txt
# Example: convert LSTM for one symbol (adjust savedmodel directory)
python components/openvino_convert/convert_to_ir.py --saved_model /mnt/pvc/nyse-models/lstm_AAPL_savedmodel --out /mnt/pvc/nyse-openvino --model_name nyse_lstm
```

### Run Kubeflow pipeline (OpenShift AI Data Science Pipelines)
In a notebook with KFP client configured:
```python
from kfp import Client
from kfp import dsl
from pipeline.nyse_pipeline import nyse_pipeline

client = Client()
run = client.create_run_from_pipeline_func(
    nyse_pipeline,
    arguments=dict(
        pvc_name="model-artifacts-pvc",
        symbols="AAPL,MSFT",
        start="2018-01-01",
        end="2024-12-31",
        data_subdir="nyse-data",
        features_subdir="nyse-features",
        models_subdir="nyse-models",
        selection_file="nyse-models/best.json",
        enable_openvino_convert=False,
        openvino_out_subdir="nyse-openvino",
    ),
)
print(run.run_id)
```

