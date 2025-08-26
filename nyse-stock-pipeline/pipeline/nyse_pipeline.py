from kfp import dsl

# Optional PVC helper for KFP v2: provided by kfp-kubernetes add-on
try:
    from kfp_kubernetes import use_pvc as k8s_use_pvc
except Exception:
    def k8s_use_pvc(*args, **kwargs):
        # No-op if helper is unavailable; ensure PVC is mounted via platform defaults
        return None


PVC_MOUNT_PATH = "/mnt/pvc"
REPO_SUBDIR = "src/nyse-stock-pipeline"  # repo will be cloned under /mnt/pvc/src


@dsl.container_component
def sync_repo_component(git_url: str, branch: str = "main"):
    target = f"{PVC_MOUNT_PATH}/src"
    return dsl.ContainerSpec(
        image="alpine/git:latest",
        command=["sh", "-lc"],
        args=[
            f"rm -rf {target} && mkdir -p {target} && git clone --depth 1 -b {branch} {git_url} {target}"
        ],
    )


@dsl.container_component
def download_component(symbols: str, start: str, end: str, out_subdir: str):
    repo = f"{PVC_MOUNT_PATH}/{REPO_SUBDIR}"
    return dsl.ContainerSpec(
        image="python:3.10",
        command=["bash", "-lc"],
        args=[
            f"pip install -q -r {repo}/components/data_download/requirements.txt && "
            f"python {repo}/components/data_download/download_nyse.py --symbols {symbols} --start {start} --end {end} --out {PVC_MOUNT_PATH}/{out_subdir}"
        ],
    )


@dsl.container_component
def feature_engineering_component(input_subdir: str, output_subdir: str):
    repo = f"{PVC_MOUNT_PATH}/{REPO_SUBDIR}"
    return dsl.ContainerSpec(
        image="python:3.10",
        command=["bash", "-lc"],
        args=[
            f"pip install -q -r {repo}/components/feature_engineering/requirements.txt && "
            f"python {repo}/components/feature_engineering/feature_engineering.py --input_root {PVC_MOUNT_PATH}/{input_subdir} --output {PVC_MOUNT_PATH}/{output_subdir}"
        ],
    )


@dsl.container_component
def train_lstm_component(features_subdir: str, out_subdir: str, window: int = 20, horizon: int = 1, epochs: int = 5):
    repo = f"{PVC_MOUNT_PATH}/{REPO_SUBDIR}"
    return dsl.ContainerSpec(
        image="tensorflow/tensorflow:2.14.0",
        command=["bash", "-lc"],
        args=[
            "pip install -q pandas numpy && "
            f"pip install -q -r {repo}/components/training_lstm/requirements.txt && "
            f"python {repo}/components/training_lstm/train_lstm.py --features_dir {PVC_MOUNT_PATH}/{features_subdir} --out {PVC_MOUNT_PATH}/{out_subdir} --window {window} --horizon {horizon} --epochs {epochs}"
        ],
    )


@dsl.container_component
def train_arima_component(features_subdir: str, out_subdir: str, order: str = "5,1,0"):
    repo = f"{PVC_MOUNT_PATH}/{REPO_SUBDIR}"
    return dsl.ContainerSpec(
        image="python:3.10",
        command=["bash", "-lc"],
        args=[
            f"pip install -q -r {repo}/components/training_arima/requirements.txt && "
            f"python {repo}/components/training_arima/train_arima.py --features_dir {PVC_MOUNT_PATH}/{features_subdir} --out {PVC_MOUNT_PATH}/{out_subdir} --order {order}"
        ],
    )


@dsl.container_component
def select_best_component(metrics_subdir: str, out_file: str):
    repo = f"{PVC_MOUNT_PATH}/{REPO_SUBDIR}"
    return dsl.ContainerSpec(
        image="python:3.10",
        command=["bash", "-lc"],
        args=[
            f"pip install -q -r {repo}/components/model_selection/requirements.txt && "
            f"python {repo}/components/model_selection/select_best.py --metrics_dir {PVC_MOUNT_PATH}/{metrics_subdir} --out {PVC_MOUNT_PATH}/{out_file}"
        ],
    )


@dsl.container_component
def openvino_convert_component(saved_model_subdir: str, ir_out_subdir: str, model_name: str = "nyse_lstm"):
    repo = f"{PVC_MOUNT_PATH}/{REPO_SUBDIR}"
    return dsl.ContainerSpec(
        image="openvino/ubuntu20_dev:latest",
        command=["bash", "-lc"],
        args=[
            # openvino-dev is preinstalled in dev image, ensure mo is available
            f"python {repo}/components/openvino_convert/convert_to_ir.py --saved_model {PVC_MOUNT_PATH}/{saved_model_subdir} --out {PVC_MOUNT_PATH}/{ir_out_subdir} --model_name {model_name}"
        ],
    )


@dsl.pipeline(
    name="nyse-stock-pipeline",
    description="End-to-end NYSE pipeline (PVC-only) with LSTM/ARIMA and optional OpenVINO conversion",
)
def nyse_pipeline(
    pvc_name: str = "model-artifacts-pvc",
    repo_url: str = "https://github.com/riteshshah/ml_pipelines.git",
    repo_branch: str = "main",
    symbols: str = "AAPL,MSFT",
    start: str = "2018-01-01",
    end: str = "2024-12-31",
    data_subdir: str = "nyse-data",
    features_subdir: str = "nyse-features",
    models_subdir: str = "nyse-models",
    selection_file: str = "nyse-models/best.json",
    enable_openvino_convert: bool = False,
    openvino_out_subdir: str = "nyse-openvino",
):
    # Steps
    git = sync_repo_component(git_url=repo_url, branch=repo_branch)

    dl = download_component(symbols=symbols, start=start, end=end, out_subdir=data_subdir)
    dl.after(git)

    fe = feature_engineering_component(input_subdir=data_subdir, output_subdir=features_subdir)
    fe.after(dl)

    lstm = train_lstm_component(features_subdir=features_subdir, out_subdir=models_subdir)
    lstm.after(fe)

    arima = train_arima_component(features_subdir=features_subdir, out_subdir=models_subdir)
    arima.after(fe)

    select = select_best_component(metrics_subdir=models_subdir, out_file=selection_file)
    select.after(lstm, arima)

    # Optional OpenVINO conversion (assumes one SavedModel path exists, e.g., lstm_AAPL_savedmodel)
    with dsl.If(enable_openvino_convert == True):
        _ = openvino_convert_component(
            saved_model_subdir=f"{models_subdir}/lstm_AAPL_savedmodel",
            ir_out_subdir=openvino_out_subdir,
            model_name="nyse_lstm",
        )

    # Mount PVC on each task using kfp-kubernetes helper if available
    for t in [dl, fe, lstm, arima, select]:
        k8s_use_pvc(task=t, pvc_name=pvc_name, mount_path=PVC_MOUNT_PATH)


