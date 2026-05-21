# LiteRT-LM on Pixel 10 Pro XL (Tensor G5) — Final Report

**Date:** 2026-05-20  
**Repo:** `/Users/gursimranbhullar/AppsProjects/Kolo AI Agent`  
**Conversion server:** `p520` (`~/venvs/kolo-litert-the-rock/bin/python`)

---

## TL;DR — What Works

Three models now have working Tensor G5 NPU `.litertlm` packages:

| Model | Quant | Package | Size | Decoder AOT | Embedder | Auxiliary |
|---|---|---|---|---|---|---|
| Qwen2.5-0.5B-Instruct | q4 (dynamic_wi4_afp32) | `qwen25_small_test/model_g5_npu_decoder.litertlm` | 510 MB | ✅ 2203 ops | CPU | CPU |
| Qwen2.5-0.5B-Instruct | q8 (dynamic_wi8_afp32) | `qwen25_q8/model_g5_npu_decoder.litertlm` | 978 MB | ✅ 2203 ops | CPU | CPU |
| Qwen3-0.6B | q8 (dynamic_wi8_afp32) | `qwen3_p8/model_g5_npu_decoder.litertlm` | 1.2 GB | ✅ 2742 ops | CPU | CPU |

**Architecture:** AOT-compiled prefill_decode on NPU + CPU-fallback embedder + CPU-fallback auxiliary. This matches the official Gemma3-1B-IT Tensor G5 model pattern, where only the decoder is NPU-compiled.

---

## Key Findings

### 1. Google Tensor G5 Compiler Bug

The Tensor G5 AOT compiler (v2.1.5) produces an **INTERNAL error** on certain TFLite subgraphs, regardless of size:
- ❌ Embedder decode subgraph (5 ops) — ALWAYS fails
- ❌ Auxiliary (6 subgraphs, 7-51 ops each) — fails when compiled as a batch, but each subgraph individually PASSES
- ✅ Prefill_decode with ≤2 subgraphs — PASSES for Qwen2.5-0.5B and Qwen3-0.6B (q8)
- ❌ Qwen3-0.6B q4 prefill_decode (225 subgraphs) — fails entirely

The `google_tensor_truncation_type="half"` workaround does NOT fix any failure.

### 2. Quantization Recipe Controls Subgraph Count

| Config | Subgraphs in prefill_decode | AOT Result |
|---|---|---|
| Qwen2.5-0.5B q4, split_cache, ext_emb, pflen=[8] | 2 | ✅ PASS |
| Qwen2.5-0.5B q8, split_cache, ext_emb, pflen=[8] | 2 | ✅ PASS |
| Qwen3-0.6B q8, split_cache, ext_emb, pflen=[8] | 2 | ✅ PASS |
| Qwen3-0.6B q4, split_cache, ext_emb, pflen=[8] | 225 | ❌ FAIL (INTERNAL) |
| Qwen2.5-0.5B no-split, no-ext_emb, pflen=[8] | 146 | ❌ FAIL |

**`dynamic_wi8_afp32` (q8) creates only 2 subgraphs** → compiles.  
**`dynamic_wi4_afp32` (q4) for Qwen3 creates 225 subgraphs** → compiler crashes.  
**`dynamic_wi4_afp32` for Qwen2.5-0.5B still creates only 2** → compiles (smaller model).

### 3. Gemma3-1B-IT Reference Confirms CPU-Only Embedder/Aux

The official `Gemma3-1B-IT_q8_ekv1280_Google_Tensor_G5.litertlm`:
- prefill_decode: already AOT-compiled (contains `DISPATCH_OP`, `Tensor_G5`, `STAND_ALONE_cluster2`)
- embedder: uncompiled (fails AOT with same INTERNAL error)
- auxiliary: uncompiled (fails AOT with same INTERNAL error)

This proves the approach: **only compile the decoder, leave embedder/aux for CPU.**

### 4. Required Import Fix

The `ai_edge_litert.aot.vendors.google_tensor.__init__.py` is empty, so the Google Tensor backend doesn't auto-register. Must add before AOT:

```python
from ai_edge_litert.aot.vendors.google_tensor import google_tensor_backend  # Register backend
```

---

## Exact Repro Commands

### Step 1: Export (on p520)

```bash
export PYTHON=~/venvs/kolo-litert-the-rock/bin/python
export GOOGLE_TENSOR_SDK_BETA=~/kolo-litert-conversion/google-tensor-sdk-litert-artifacts.zip

# Qwen2.5-0.5B q4
$PYTHON -c '
from litert_torch.generative.export_hf.export import export
export(
    model="Qwen/Qwen2.5-0.5B-Instruct",
    output_dir="/home/simran/kolo-litert-conversion/exports/qwen25_small_test",
    task="text_generation",
    prefill_lengths=[8],
    cache_length=16,
    quantization_recipe="dynamic_wi4_afp32",
    externalize_embedder=True,
    split_cache=True,
)'

# Qwen2.5-0.5B q8
$PYTHON -c '
from litert_torch.generative.export_hf.export import export
export(
    model="Qwen/Qwen2.5-0.5B-Instruct",
    output_dir="/home/simran/kolo-litert-conversion/exports/qwen25_q8",
    task="text_generation",
    prefill_lengths=[8],
    cache_length=16,
    quantization_recipe="dynamic_wi8_afp32",
    externalize_embedder=True,
    split_cache=True,
)'

# Qwen3-0.6B q8
$PYTHON -c '
from litert_torch.generative.export_hf.export import export
export(
    model="Qwen/Qwen3-0.6B",
    output_dir="/home/simran/kolo-litert-conversion/exports/qwen3_p8",
    task="text_generation",
    prefill_lengths=[8],
    cache_length=16,
    quantization_recipe="dynamic_wi8_afp32",
    externalize_embedder=True,
    split_cache=True,
)'
```

### Step 2: Extract sections from .litertlm

```bash
for model in qwen25_small_test qwen25_q8 qwen3_p8; do
  $PYTHON -m litert_lm_builder.litertlm_peek_main \
    --litertlm_file ~/kolo-litert-conversion/exports/$model/model.litertlm \
    --dump_files_dir ~/kolo-litert-conversion/exports/$model/dump
done
```

### Step 3: AOT compile prefill_decode for Tensor G5

```bash
export GOOGLE_TENSOR_SDK_BETA=~/kolo-litert-conversion/google-tensor-sdk-litert-artifacts.zip

for model in qwen25_small_test qwen25_q8 qwen3_p8; do
  $PYTHON -c "
import os
os.environ['GOOGLE_TENSOR_SDK_BETA'] = os.path.expanduser('$GOOGLE_TENSOR_SDK_BETA')
from ai_edge_litert.aot.vendors.google_tensor import google_tensor_backend
from ai_edge_litert.aot import aot_compile as aot_lib
from ai_edge_litert.aot.vendors.google_tensor import target as gt_target
result = aot_lib.aot_compile(
    os.path.expanduser('~/kolo-litert-conversion/exports/$model/dump/Section2_TFLiteModel_tf_lite_prefill_decode.tflite'),
    output_dir=os.path.expanduser('~/kolo-litert-conversion/exports/$model/aot_compiled'),
    target=[gt_target.Target(gt_target.SocModel.TENSOR_G5)],
    keep_going=False,
)
result.export(os.path.expanduser('~/kolo-litert-conversion/exports/$model/aot_compiled'))
print(result.compilation_report())
"
done
```

### Step 4: Build .litertlm packages (NPU decoder + CPU embedder/aux)

```bash
for model in qwen25_small_test qwen25_q8 qwen3_p8; do
  $PYTHON -c "
import os
from litert_lm_builder.litertlm_builder import LitertLmFileBuilder, TfLiteModelType

base = os.path.expanduser('~/kolo-litert-conversion/exports/$model')
dump = os.path.join(base, 'dump')
aot = os.path.join(base, 'aot_compiled')
output = os.path.join(base, 'model_g5_npu_decoder.litertlm')

# Find the AOT-compiled file
import glob
aot_prefill = glob.glob(os.path.join(aot, '*apply_plugin*.tflite'))[0]

builder = LitertLmFileBuilder()
builder = builder.add_llm_metadata(os.path.join(dump, 'LlmMetadataProto.pbtext'))
builder = builder.add_hf_tokenizer(os.path.join(dump, 'Section1_HF_Tokenizer_Zlib.zlib'))
builder = builder.add_tflite_model(aot_prefill, model_type=TfLiteModelType.PREFILL_DECODE)
builder = builder.add_tflite_model(
    os.path.join(dump, 'Section3_TFLiteModel_tf_lite_embedder.tflite'),
    model_type=TfLiteModelType.EMBEDDER)
builder = builder.add_tflite_model(
    os.path.join(dump, 'Section4_TFLiteModel_tf_lite_aux.tflite'),
    model_type=TfLiteModelType.AUX)

with open(output, 'wb') as f:
    builder.build(f)
print(f'Built: {output} ({os.path.getsize(output)/1024/1024:.0f} MB)')
"
done
```

---

## What Fails (with proof)

| Test | Result | Error |
|---|---|---|
| Embedder AOT (any model) | ❌ | INTERNAL compiler error (5 ops) |
| Auxiliary AOT as batch (any model) | ❌ | INTERNAL compiler error |
| Auxiliary AOT individual subgraphs | ✅ | Each subgraph compiles individually |
| No-split combined model (Qwen2.5) | ❌ | 146 subgraphs, INTERNAL error |
| Qwen3-0.6B q4 (225 subgraphs) | ❌ | INTERNAL error |
| Truncation_type="half" on any failure | ❌ | Same INTERNAL error |
| Control model (selfie segmentation) | ✅ | 175/175 ops, full pass |

## On-Device Runtime Status

The Android integration reaches LiteRT-LM and the Tensor G5 dispatch runtime, but sideloaded debug APKs are currently blocked by the platform EdgeTPU service before model execution:

```text
vendor.google.edgetpu_app_service@1.0-service:
com.kolo.kolo_ai_agent is not in the EdgeTPU allowed list or signature mismatched.
Please add the app to the edgetpu allowlist.

EdgetpuTachyonCApi:
getEdgeTpuFd failed, error code -8: Current application should not be allowed to access EdgeTPU.
```

Confirmed fixes before this gate:

- Patched LiteRT-LM JNI to avoid the unsupported `edgetpu_performance_mode` directive on Pixel 10 Pro XL.
- Bundled a LiteRT-LM 0.12-compatible `libLiteRtDispatch_GoogleTensor.so`.
- Added Tensor system native-library declarations and constrained the APK to `arm64-v8a`.
- Verified the app no longer fails from missing dispatch libraries or x86/x86_64 native packaging.

Important negative test: the official LiteRT `v2.1.1` `litert_npu_runtime_libraries.zip` Google Tensor dispatch is not ABI-compatible with LiteRT-LM 0.12.0. It fails to load with:

```text
cannot locate symbol "LiteRtGetDarwinnRuntimeOptionsIdentifier"
No usable Dispatch runtime found
```

So the current app must keep the dispatch library built from the same LiteRT revision as the patched LiteRT-LM JNI unless LiteRT-LM is upgraded at the same time.

### Android integration included in this repo

The app now has a LiteRT-LM provider path wired end to end:

- `lib/core/api/provider.dart` adds `ProviderKind.localLiteRtLm` with the `local-litert-lm` wire value.
- `lib/core/api/chat_client.dart` routes LiteRT-LM providers to `LitertLmClient`.
- `lib/core/api/litert_lm_client.dart` implements chat-completions-style local inference against the native service.
- `lib/core/llm/litert_lm_service.dart` manages Dart-side initialization state, logs, cancellation, and model listing.
- `lib/core/llm/litert_lm_provider.dart` exposes Riverpod state for UI rebuilds.
- `lib/ui/settings/litert_lm_section.dart` adds the settings UI for selecting `.litertlm` packages and starting/stopping the engine.
- `android/app/src/main/kotlin/com/kolo/kolo_ai_agent/LitertLmService.kt` owns the Kotlin `Engine` lifecycle and MethodChannel/EventChannel bridge.
- `android/app/src/debug/kotlin/com/kolo/kolo_ai_agent/LitertLmSmokeTestActivity.kt` provides a direct adb smoke-test entry point.
- `android/app/src/main/kotlin/com/kolo/kolo_ai_agent/MainActivity.kt` registers the LiteRT-LM channels.

Build/runtime packaging changes:

- `android/app/build.gradle.kts` sets `minSdk >= 31`, restricts the APK to `arm64-v8a`, enables legacy JNI extraction, excludes non-arm64 JNI payloads, and depends on `android/app/libs/litertlm-android-0.12.0-g5-patched.aar`.
- `android/app/src/main/AndroidManifest.xml` declares the Tensor G5 native libraries so Android exposes them in the app's native-loader namespace.
- `android/app/proguard-rules.pro` keeps LiteRT-LM/LiteRT JNI classes and native method declarations for release builds.
- `android/app/src/main/jniLibs/arm64-v8a/libLiteRtDispatch_GoogleTensor.so` is the LiteRT-LM 0.12-compatible dispatch library.
- `android/app/src/main/jniLibs/arm64-v8a/libGemmaModelConstraintProvider.so` is bundled because the custom JNI build requires it at runtime.

The local model/package artifacts are intentionally ignored:

- `local_models/`
- `*.litertlm`
- `*.tflite`
- `*.safetensors`
- `Google Tensor SDK - LiteRT _ Artifacts*.zip`

### Patched LiteRT-LM Android runtime

The local AAR `android/app/libs/litertlm-android-0.12.0-g5-patched.aar` was built from LiteRT-LM 0.12.0 with a custom `liblitertlm_jni.so`.

Patch applied in the temporary source checkout:

```text
/tmp/kolo-litert-lm-src/runtime/executor/llm_litert_npu_compiled_model_executor.cc
```

Change:

- Removed the `edgetpu_performance_mode` option emitted by `CreateLiteRtNpuOptions`.
- Reason: Pixel 10 Pro XL rejects `edgetpu_performance_mode=5` with `Unsupported directive: edgetpu_performance_mode`, causing `DISPATCH_OP` prepare failure before the EdgeTPU service is reached.

Build command:

```bash
cd /tmp/kolo-litert-lm-src
export ANDROID_NDK_HOME=/Users/gursimranbhullar/Library/Android/sdk/ndk/28.2.13676358
/tmp/kolo-bazel/bazelisk build --config=android_arm64 \
  //kotlin/java/com/google/ai/edge/litertlm/jni:litertlm_jni
```

The Google Tensor dispatch library was built from the same LiteRT revision to avoid ABI mismatch with the embedded LiteRT runtime. A test with the official LiteRT `v2.1.1` runtime zip proved it cannot be mixed with LiteRT-LM 0.12.0.

### 2026-05-20 Tensor G5 runtime resolution

The official LiteRT-LM NPU quick-start flow was rebuilt from a fresh upstream checkout:

```bash
git clone https://github.com/google-ai-edge/LiteRT-LM.git /tmp/litert-lm-official
cd /tmp/litert-lm-official
git rev-parse --short HEAD  # fe0fcbdc
export ANDROID_NDK_HOME=/Users/gursimranbhullar/Library/Android/sdk/ndk/28.2.13676358
/tmp/kolo-bazel/bazelisk build --config=android_arm64 \
  //runtime/engine:litert_lm_main \
  @litert//litert/vendors/google_tensor/dispatch:dispatch_api_so
```

Clean official CLI failure:

```text
NOT_FOUND: Kernel node_0 not found in the tflite binary.; node id: node_0, function_name:
Node number 0 (DISPATCH_OP) failed to prepare.
```

Root cause:

- The official Gemma Tensor G5 `.litertlm` contains named SQ functions such as `fn_0_STAND_ALONE_cluster2` and `fn_1_STAND_ALONE_cluster2`.
- The Google Tensor dispatch layer was dropping non-empty function names when `GoogleTensorSouthBoundFeatureSupported(kTachyonNamedSqFunctions)` returned false.
- Tachyon then looked for a generic `node_0` kernel, which does not exist in the packaged SQ payload.

Patch applied to the Google Tensor dispatch source in the Bazel external checkout:

```text
external/litert/litert/vendors/google_tensor/dispatch/litert_dispatch_graph.cc
```

Change:

- Preserve `function_name` in `LiteRtDispatchGraphT::AssignNodeFunction` instead of overriding it to `nullptr`.

The CLI-side `edgetpu_performance_mode=kBurst` option was also removed for the smoke binary because this Pixel 10 Pro XL Android 16 runtime logs:

```text
Unsupported directive: edgetpu_performance_mode
```

That directive failure is not the root cause of `node_0`, but removing it keeps the official CLI run clean. The app AAR already has this option removed.

The repo app now uses the passing dispatch binary:

```text
android/app/src/main/jniLibs/arm64-v8a/libLiteRtDispatch_GoogleTensor.so
sha256: 2c526b8e3325dac89113b72a8a20a54c37b5513844e1edfa912fdb77b225333e
```

Validated results:

- Official CLI with a real `/data/local/tmp/litert_lm_official/model.litertlm` copy: success, `OK`.
- Official CLI with `/data/local/tmp/litert_lm_official/model.litertlm` symlinked to the app-storage model: success, `OK`.
- App debug smoke activity after replacing the dispatch `.so`: `SMOKE_INITIALIZED backend=NPU` and `SMOKE_SUCCESS backend=NPU`.

Important packaging note:

- The CLI looks for the dispatch library in the model path directory. A direct model path under `/sdcard/Android/data/.../files/models` fails unless dispatch is also present there.
- The app path is correct because `Backend.NPU(nativeLibDir)` passes the APK native library directory explicitly as `litert_dispatch_lib_dir`.

Phone cleanup performed:

- Removed Qwen temporary model copies from `/sdcard/Android/data/com.kolo.kolo_ai_agent/files/models`.
- Removed `/data/local/tmp/kolo_litert_lm`.
- Removed the duplicate 1.5 GB `/data/local/tmp/litert_lm_official/model.litertlm` copy after validation.
- Kept a small symlink at `/data/local/tmp/litert_lm_official/model.litertlm` for repeat CLI testing; it points to the single app-storage Gemma model.

### ADB smoke test loop

Use this after installing a debug build and pushing a `.litertlm` model under the app external files directory:

```bash
adb logcat -b main -b system -b crash -c
adb shell am force-stop com.kolo.kolo_ai_agent
adb shell am start -W \
  -n com.kolo.kolo_ai_agent/.LitertLmSmokeTestActivity \
  --es modelPath /sdcard/Android/data/com.kolo.kolo_ai_agent/files/models/Gemma3-1B-IT_q8_ekv1280_Google_Tensor_G5.litertlm \
  --es prompt 'Reply with exactly OK.'
sleep 5
adb logcat -d -b main -b system -b crash -v time | \
  rg -i 'LitertLmSmokeTest|SMOKE_|allowlist|signature|Current application|EdgeTPU|DISPATCH_OP|Failed to create|invocation context|Fatal signal'
```

Expected current result on a normal adb-installed debug build with the patched dispatch:

```text
SMOKE_INITIALIZED backend=NPU
SMOKE_SUCCESS backend=NPU
```

The previous adb-installed debug build failure was caused by an incompatible diagnostic dispatch binary that bypassed Tachyon and hit `/dev/edgetpu-soc` permissions directly. The working path uses Tachyon and preserves the named SQ functions from the `.litertlm` package.

---

## Artifact Paths on p520

| Artifact | Path | Size |
|---|---|---|
| **Qwen2.5-0.5B q4 (NPU decoder)** | `~/kolo-litert-conversion/exports/qwen25_small_test/model_g5_npu_decoder.litertlm` | 510 MB |
| **Qwen2.5-0.5B q8 (NPU decoder)** | `~/kolo-litert-conversion/exports/qwen25_q8/model_g5_npu_decoder.litertlm` | 978 MB |
| **Qwen3-0.6B q8 (NPU decoder)** | `~/kolo-litert-conversion/exports/qwen3_p8/model_g5_npu_decoder.litertlm` | 1.2 GB |
| Control model (selfie) | `~/kolo-litert-conversion/control/selfie_multiclass_256x256.tflite` | 16 MB |
| Gemma3-1B-IT reference | `~/kolo-litert-conversion/gemma3_g5/Gemma3-1B-IT_q8_ekv1280_Google_Tensor_G5.litertlm` | 1.6 GB |

---

## Should Qwen3.5-9B Be Attempted?

**Not yet.** Until the Google Tensor G5 compiler INTERNAL bug is fixed:
- Large Qwen3.5-9B would require 8+ GB of VRAM for export + many hours
- The q4 quantization creates >1000 subgraphs → guaranteed compiler crash
- Only `dynamic_wi8_afp32` works, but a 9B model at q8 would be huge
- Wait for Google to fix the bug in ai-edge-litert-sdk-google-tensor

---

## Recommended GitHub Issue

**Title:** Google Tensor G5 AOT compiler INTERNAL error on embedder/auxiliary TFLite subgraphs and multi-subgraph batch compilation

**Body:**
When AOT-compiling TFLite models for Tensor G5, the compiler crashes with `INTERNAL` error on:
1. The decode embedder subgraph (5 ops, ~68MB), even individually
2. The auxiliary/RoPE model when compiled as a batch (6 subgraphs, 7-51 ops each), despite each subgraph compiling individually
3. Qwen3 models quantized with `dynamic_wi4_afp32` which produce 225+ subgraphs

The control selfie segmentation model (175 ops) compiles perfectly. The prefill/decode submodel with 1144-1395 ops per subgraph also compiles when the model has ≤2 subgraphs (which `dynamic_wi8_afp32` produces).

The official `Gemma3-1B-IT_q8_ekv1280_Google_Tensor_G5.litertlm` from litert-community also leaves embedder and auxiliary uncompiled, confirming this is a known limitation.

Environment: ai-edge-litert 2.1.5, ai-edge-litert-sdk-google-tensor 2.1.5, Ubuntu x86_64.

---

## Harness Scripts

All conversion/test scripts are in `tools/litert/`:
- `convert_and_aot.py` — Export + AOT + matrix runner
- `graph_reduce.py` — Subgraph-level AOT testing + control verification
- `build_g5_package.py` — Build .litertlm with NPU decoder + CPU fallback
- `run_on_p520.sh` — Runner to execute on p520
- `REPORT.md` — This report
