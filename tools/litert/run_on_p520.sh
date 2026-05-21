#!/usr/bin/env bash
# Kolo LiteRT Runner — copies harness scripts to p520 and runs them.
# Usage:
#   ./run_on_p520.sh <command> [args...]
# Commands:
#   verify          — AOT compile the control model to verify setup
#   export           — Export a model and optionally AOT compile
#   aot              — AOT compile an existing .tflite
#   reduce           — Graph reduction on a failing .tflite
#   matrix           — Run the full variant matrix
#   inspect          — Inspect a TFLite file
#
# Examples:
#   ./run_on_p520.sh verify
#   ./run_on_p520.sh export --model Qwen/Qwen2.5-0.5B-Instruct --output-dir ~/kolo-litert-conversion/matrix/test1 --quantization-recipe dynamic_wi4_afp32
#   ./run_on_p520.sh aot --tflite ~/kolo-litert-conversion/exports/qwen25_0_5b_q4/model_dynamic_wi4_afp32.tflite --output-dir ~/kolo-litert-conversion/test_aot
#   ./run_on_p520.sh reduce --tflite ~/kolo-litert-conversion/exports/qwen25_0_5b_q4/model_dynamic_wi4_afp32.tflite --output-dir ~/kolo-litert-conversion/reduce_test
#   ./run_on_p520.sh matrix

set -euo pipefail

REMOTE="p520"
REMOTE_BASE="~/kolo-litert-conversion"
REMOTE_PYTHON="~/venvs/kolo-litert-the-rock/bin/python"
LOCAL_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure GOOGLE_TENSOR_SDK_BETA is set on p520
REMOTE_SDK="${REMOTE_BASE}/google-tensor-sdk-litert-artifacts.zip"

echo "=== Kolo LiteRT Runner ==="
echo "Remote: ${REMOTE}"
echo "Script dir: ${LOCAL_SCRIPT_DIR}"

# Copy harness scripts to p520
echo "Copying harness scripts to p520..."
ssh "${REMOTE}" "mkdir -p ${REMOTE_BASE}/scripts"
scp "${LOCAL_SCRIPT_DIR}/convert_and_aot.py" "${REMOTE}:${REMOTE_BASE}/scripts/"
scp "${LOCAL_SCRIPT_DIR}/graph_reduce.py" "${REMOTE}:${REMOTE_BASE}/scripts/"
echo "Scripts copied."

# Run the requested command
COMMAND="${1:-verify}"
shift || true

case "${COMMAND}" in
    verify)
        echo "=== Verifying AOT compiler with control model ==="
        ssh "${REMOTE}" "export GOOGLE_TENSOR_SDK_BETA=${REMOTE_SDK} && ${REMOTE_PYTHON} ${REMOTE_BASE}/scripts/graph_reduce.py control-verify" 2>&1 | tee /tmp/kolo_control_verify.log
        ;;
    export)
        echo "=== Running export ==="
        ssh "${REMOTE}" "export GOOGLE_TENSOR_SDK_BETA=${REMOTE_SDK} && ${REMOTE_PYTHON} ${REMOTE_BASE}/scripts/convert_and_aot.py export $*" 2>&1 | tee /tmp/kolo_export.log
        ;;
    aot)
        echo "=== Running AOT compile ==="
        ssh "${REMOTE}" "export GOOGLE_TENSOR_SDK_BETA=${REMOTE_SDK} && ${REMOTE_PYTHON} ${REMOTE_BASE}/scripts/graph_reduce.py aot --tflite /home/simran/kolo-litert-conversion/exports/qwen25_0_5b_q4/model_dynamic_wi4_afp32.tflite --output-dir /home/simran/kolo-litert-conversion/reports/aot_qwen25_q4_full $*" 2>&1 | tee /tmp/kolo_aot.log
        ;;
    reduce)
        echo "=== Running graph reduction ==="
        ssh "${REMOTE}" "export GOOGLE_TENSOR_SDK_BETA=${REMOTE_SDK} && ${REMOTE_PYTHON} ${REMOTE_BASE}/scripts/graph_reduce.py reduce $*" 2>&1 | tee /tmp/kolo_reduce.log
        ;;
    inspect)
        echo "=== Inspecting TFLite file ==="
        ssh "${REMOTE}" "export GOOGLE_TENSOR_SDK_BETA=${REMOTE_SDK} && ${REMOTE_PYTHON} ${REMOTE_BASE}/scripts/graph_reduce.py inspect $*" 2>&1 | tee /tmp/kolo_inspect.log
        ;;
    matrix)
        echo "=== Running variant matrix ==="
        ssh "${REMOTE}" "export GOOGLE_TENSOR_SDK_BETA=${REMOTE_SDK} && nohup ${REMOTE_PYTHON} ${REMOTE_BASE}/scripts/convert_and_aot.py matrix $* > ${REMOTE_BASE}/matrix/matrix.log 2>&1 &"
        echo "Matrix started in background on p520."
        echo "Monitor with: ssh ${REMOTE} 'tail -f ${REMOTE_BASE}/matrix/matrix.log'"
        ;;
    *)
        echo "Unknown command: ${COMMAND}"
        echo "Use: verify, export, aot, reduce, inspect, matrix"
        exit 1
        ;;
esac