from kfp import dsl
from kfp import kubernetes


PVC_MOUNT_PATH = "/mnt/pvc"


@dsl.container_component
def download_component(symbols: str, start: str, end: str, out_subdir: str):
    return dsl.ContainerSpec(
        image="python:3.10",
        command=["bash", "-lc"],
        args=[
            "pip install -q -r components/data_download/requirements.txt && "
            f"python components/data_download/download_nyse.py --symbols {symbols} --start {start} --end {end} --out {PVC_MOUNT_PATH}/{out_subdir}"
        ],
    )


@dsl.container_component
def feature_engineering_component(input_subdir: str, output_subdir: str):
    return dsl.ContainerSpec(
        image="python:3.10",
        command=["bash", "-lc"],
        args=[
            "pip install -q -r components/feature_engineering/requirements.txt && "
            f"python components/feature_engineering/feature_engineering.py --input_root {PVC_MOUNT_PATH}/{input_subdir} --output {PVC_MOUNT_PATH}/{output_subdir}"
        ],
    )


@dsl.container_component
def train_lstm_component(features_subdir: str, out_subdir: str, window: int = 20, horizon: int = 1, epochs: int = 5):
    return dsl.ContainerSpec(
        image="tensorflow/tensorflow:2.14.0",
        command=["bash", "-lc"],
        args=[
            "pip install -q pandas numpy && "
            "pip install -q -r components/training_lstm/requirements.txt && "
            f"python components/training_lstm/train_lstm.py --features_dir {PVC_MOUNT_PATH}/{features_subdir} --out {PVC_MOUNT_PATH}/{out_subdir} --window {window} --horizon {horizon} --epochs {epochs}"
        ],
    )


@dsl.container_component
def train_arima_component(features_subdir: str, out_subdir: str, order: str = "5,1,0"):
    return dsl.ContainerSpec(
        image="python:3.10",
        command=["bash", "-lc"],
        args=[
            "pip install -q -r components/training_arima/requirements.txt && "
            f"python components/training_arima/train_arima.py --features_dir {PVC_MOUNT_PATH}/{features_subdir} --out {PVC_MOUNT_PATH}/{out_subdir} --order {order}"
        ],
    )


@dsl.container_component
def select_best_component(metrics_subdir: str, out_file: str):
    return dsl.ContainerSpec(
        image="python:3.10",
        command=["bash", "-lc"],
        args=[
            "pip install -q -r components/model_selection/requirements.txt && "
            f"python components/model_selection/select_best.py --metrics_dir {PVC_MOUNT_PATH}/{metrics_subdir} --out {PVC_MOUNT_PATH}/{out_file}"
        ],
    )


@dsl.container_component
def openvino_convert_component(saved_model_subdir: str, ir_out_subdir: str, model_name: str = "nyse_lstm"):
    return dsl.ContainerSpec(
        image="openvino/ubuntu20_dev:latest",
        command=["bash", "-lc"],
        args=[
            # openvino-dev is preinstalled in dev image, ensure mo is available
            f"python components/openvino_convert/convert_to_ir.py --saved_model {PVC_MOUNT_PATH}/{saved_model_subdir} --out {PVC_MOUNT_PATH}/{ir_out_subdir} --model_name {model_name}"
        ],
    )


@dsl.pipeline(
    name="nyse-stock-pipeline",
    description="End-to-end NYSE pipeline (PVC-only) with LSTM/ARIMA and optional OpenVINO conversion",
)
def nyse_pipeline(
    pvc_name: str = "model-artifacts-pvc",
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
    dl = download_component(symbols=symbols, start=start, end=end, out_subdir=data_subdir)
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

    # Mount PVC on each task
    for t in [dl, fe, lstm, arima, select]:
        t.apply(kubernetes.use_pvc(pvc_name=pvc_name, mount_path=PVC_MOUNT_PATH))


