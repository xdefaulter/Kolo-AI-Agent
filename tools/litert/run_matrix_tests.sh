#!/usr/bin/env bash
# Phase 2-3: Systematic AOT compilation tests for Qwen models on Tensor G5.
# Run on p520.
#
# Findings so far:
# - Control (selfie_multiclass) PASSES: 175/175 ops on G5
# - Qwen2.5-0.5B-Instruct with split_cache+externalize_embedder:
#   - prefill_decode (1144 ops) PASSES AOT to G5
#   - embedder (5+5 ops) FAILS AOT (INTERNAL compiler error)
#   - auxiliary (52+51+15+13+7+6 ops) FAILS AOT (INTERNAL compiler error)
# - Previous Qwen exports without split_cache FAIL AOT entirely
#
# This script runs the remaining matrix tests.

set -euo pipefail

PYTHON=~/venvs/kolo-litert-the-rock/bin/python
BASE=~/kolo-litert-conversion
SCRIPTS=$BASE/scripts
export GOOGLE_TENSOR_SDK_BETA=$BASE/google-tensor-sdk-litert-artifacts.zip

LOGDIR=$BASE/matrix_results
mkdir -p $LOGDIR

# Copy latest scripts
cp $SCRIPTS/graph_reduce.py $SCRIPTS/convert_and_aot.py $LOGDIR/

echo "=== PHASE 2-3: Systematic AOT Tests ==="
echo "Start: $(date)"
echo ""

# -------------------------------------------------------------------
# Test 1: Already proven: prefill_decode with split_cache+ext_emb PASSES
# Test 2: Embedder always FAILS - known
# Test 3: Auxiliary always FAILS - known  
# Test 4: Try embedder with truncation_type=half
# Test 5: Try auxiliary with truncation_type=half
# Test 6: Try the NO-split_cache variant (no ext_emb) for comparison
# -------------------------------------------------------------------

echo "=== Test 4: Embedder with truncation_type=half ==="
$PYTHON $SCRIPTS/graph_reduce.py aot \
  --tflite $BASE/exports/qwen25_small_test/dump/Section3_TFLiteModel_tf_lite_embedder.tflite \
  --output-dir $LOGDIR/aot_embedder_half \
  --truncation-type half \
  --timeout 300 2>&1 | tee $LOGDIR/test4_embedder_half.log

echo ""
echo "=== Test 5: Auxiliary with truncation_type=half ==="
$PYTHON $SCRIPTS/graph_reduce.py aot \
  --tflite $BASE/exports/qwen25_small_test/dump/Section4_TFLiteModel_tf_lite_aux.tflite \
  --output-dir $LOGDIR/aot_aux_half \
  --truncation-type half \
  --timeout 120 2>&1 | tee $LOGDIR/test5_aux_half.log

echo ""
echo "=== Test 6: Previous failing Qwen2.5-0.5B Q4 dynamic_wi4 model (no split, no ext_emb) ==="
# This is the model from earlier exports that failed - 146 subgraphs
$PYTHON $SCRIPTS/graph_reduce.py aot \
  --tflite $BASE/exports/qwen25_0_5b_q4/model_dynamic_wi4_afp32.tflite \
  --output-dir $LOGDIR/aot_qwen25_nosplit \
  --timeout 300 2>&1 | tee $LOGDIR/test6_qwen25_nosplit.log

echo ""
echo "=== Test 7: Export Qwen3-0.6B with split_cache+ext_emb and test ==="
rm -rf $BASE/exports/qwen3_split_test
$PYTHON -c '
from litert_torch.generative.export_hf.export import export
export(
    model="Qwen/Qwen3-0.6B",
    output_dir="/home/simran/kolo-litert-conversion/exports/qwen3_split_test",
    task="text_generation",
    prefill_lengths=[8],
    cache_length=16,
    quantization_recipe="dynamic_wi4_afp32",
    externalize_embedder=True,
    split_cache=True,
)
print("EXPORT_DONE_QWEN3")
' 2>&1 | tee $LOGDIR/test7_qwen3_export.log

echo ""
echo "=== Test 8: AOT compile Qwen3-0.6B prefill_decode ==="
$BASE/venvs/kolo-litert-the-rock/bin/python -m litert_lm_builder.litertlm_peek_main \
  --litertlm_file $BASE/exports/qwen3_split_test/model.litertlm \
  --dump_files_dir $BASE/exports/qwen3_split_test/dump 2>&1 | head -30 | tee $LOGDIR/test8_qwen3_peek.log

# Find and AOT compile the prefill_decode section
PREFILL_TFLITE=$(ls $BASE/exports/qwen3_split_test/dump/*prefill_decode*.tflite 2>/dev/null | head -1)
if [ -n "$PREFILL_TFLITE" ]; then
  echo "Found prefill_decode: $PREFILL_TFLITE"
  $PYTHON $SCRIPTS/graph_reduce.py aot \
    --tflite "$PREFILL_TFLITE" \
    --output-dir $LOGDIR/aot_qwen3_prefill_decode \
    --timeout 600 2>&1 | tee $LOGDIR/test8_aot_qwen3_prefill.log
else
  echo "No prefill_decode TFLite found for Qwen3!"
  ls $BASE/exports/qwen3_split_test/dump/ 2>/dev/null || echo "dump dir not found"
fi

echo ""
echo "=== Test 9: AOT compile Qwen3-0.6B embedder ==="
EMBEDDER_TFLITE=$(ls $BASE/exports/qwen3_split_test/dump/*embedder*.tflite 2>/dev/null | head -1)
if [ -n "$EMBEDDER_TFLITE" ]; then
  $PYTHON $SCRIPTS/graph_reduce.py aot \
    --tflite "$EMBEDDER_TFLITE" \
    --output-dir $LOGDIR/aot_qwen3_embedder \
    --timeout 120 2>&1 | tee $LOGDIR/test9_aot_qwen3_embedder.log
fi

echo ""
echo "=== Test 10: Now try without split_cache or ext_embedder on Qwen2.5-0.5B ==="
rm -rf $BASE/exports/qwen25_nosplit_noeemb
$PYTHON -c '
from litert_torch.generative.export_hf.export import export
export(
    model="Qwen/Qwen2.5-0.5B-Instruct",
    output_dir="/home/simran/kolo-litert-conversion/exports/qwen25_nosplit_noeemb",
    task="text_generation",
    prefill_lengths=[8],
    cache_length=16,
    quantization_recipe="dynamic_wi4_afp32",
    externalize_embedder=False,
    split_cache=False,
)
print("EXPORT_DONE_QWEN25_NOSPLIT")
' 2>&1 | tee $LOGDIR/test10_qwen25_nosplit_export.log

# Then AOT compile
PREFILL_TFLITE_NOSPLIT=$(ls $BASE/exports/qwen25_nosplit_noeemb/dump/*prefill_decode*.tflite 2>/dev/null | head -1 || ls $BASE/exports/qwen25_nosplit_noeemb/*model*.tflite 2>/dev/null | head -1)
if [ -n "$PREFILL_TFLITE_NOSPLIT" ]; then
  echo "Found tflite: $PREFILL_TFLITE_NOSPLIT"
  $PYTHON $SCRIPTS/graph_reduce.py aot \
    --tflite "$PREFILL_TFLITE_NOSPLIT" \
    --output-dir $LOGDIR/aot_qwen25_nosplit_prefill \
    --timeout 600 2>&1 | tee $LOGDIR/test10_aot_nosplit.log
fi

echo ""
echo "=== SUMMARY ==="
echo "Tests completed at: $(date)"
echo ""
echo "Results:"
for f in $LOGDIR/test*.log; do
  name=$(basename "$f" .log)
  # Extract status from JSON or log
  status=$(grep -o '"status": "[^"]*"' "$f" 2>/dev/null | tail -1 || echo "unknown")
  echo "  $name: $status"
done