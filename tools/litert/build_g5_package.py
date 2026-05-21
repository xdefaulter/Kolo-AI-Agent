#!/usr/bin/env python3
"""
Build a .litertlm package with AOT-compiled decoder for Tensor G5 NPU
and CPU-fallback embedder/auxiliary.

This works around the Google Tensor G5 compiler bug that crashes on
embedder and auxiliary subgraphs (INTERNAL error).

Usage:
  python3 build_g5_package.py \
    --dump-dir ~/kolo-litert-conversion/exports/qwen25_small_test/dump \
    --aot-dir ~/kolo-litert-conversion/exports/qwen25_small_test/aot_compiled \
    --output ~/kolo-litert-conversion/exports/qwen25_small_test/model_g5_npu.litertlm
"""

import argparse
import os
import subprocess
import sys
import time

PYTHON = os.environ.get(
    "KOLO_LITERT_PYTHON",
    os.path.expanduser("~/venvs/kolo-litert-the-rock/bin/python"),
)
BASE_DIR = os.environ.get(
    "KOLO_LITERT_BASE_DIR",
    os.path.expanduser("~/kolo-litert-conversion"),
)
GOOGLE_TENSOR_SDK_BETA = os.environ.get(
    "GOOGLE_TENSOR_SDK_BETA",
    os.path.expanduser("~/kolo-litert-conversion/google-tensor-sdk-litert-artifacts.zip"),
)


def aot_compile_decoder(tflite_path: str, output_dir: str, target_soc: str = "TENSOR_G5") -> dict:
    """AOT compile the prefill_decode TFLite to Tensor G5."""
    script = f'''
import os
os.environ["GOOGLE_TENSOR_SDK_BETA"] = "{GOOGLE_TENSOR_SDK_BETA}"

from ai_edge_litert.aot.vendors.google_tensor import google_tensor_backend  # noqa: F401
from ai_edge_litert.aot import aot_compile as aot_lib
from ai_edge_litert.aot.vendors.google_tensor import target as gt_target

soc = gt_target.SocModel.{target_soc}
tgt = gt_target.Target(soc)

print("AOT compiling decoder for Tensor G5...")
result = aot_lib.aot_compile(
    "{tflite_path}",
    output_dir="{output_dir}",
    target=[tgt],
    keep_going=False,
)
print(result.compilation_report())
result.export("{output_dir}")
print("AOT_EXPORT_DONE")
'''
    env = os.environ.copy()
    env["GOOGLE_TENSOR_SDK_BETA"] = GOOGLE_TENSOR_SDK_BETA

    r = subprocess.run(
        [PYTHON, "-c", script],
        capture_output=True, text=True,
        env=env,
        timeout=600,
    )

    success = "AOT_EXPORT_DONE" in r.stdout
    return {
        "success": success,
        "returncode": r.returncode,
        "stdout": r.stdout[-2000:],
        "stderr": r.stderr[-2000:],
    }


def build_litertlm_package(dump_dir: str, aot_dir: str, output_path: str) -> dict:
    """Build a .litertlm package from AOT-compiled decoder + original embedder/aux."""
    # Find the AOT-compiled prefill_decode
    aot_files = list(Path(aot_dir).glob("*apply_plugin*.tflite"))
    if not aot_files:
        aot_files = list(Path(aot_dir).glob("model_*.tflite"))
    if not aot_files:
        return {"success": False, "error": f"No AOT-compiled files found in {aot_dir}"}
    aot_prefill = str(aot_files[0])

    # Find original sections from dump
    dump_path = Path(dump_dir)
    tokenizer = str(dump_path / "Section1_HF_Tokenizer_Zlib.zlib")
    metadata = str(dump_path / "LlmMetadataProto.pbtext")

    embedder = None
    for f in dump_path.glob("*embedder*.tflite"):
        embedder = str(f)
        break

    aux = None
    for f in dump_path.glob("*aux*.tflite"):
        aux = str(f)
        break

    script = f'''
import os
from litert_lm_builder.litertlm_builder import LitertLmFileBuilder, TfLiteModelType

output_path = "{output_path}"
builder = LitertLmFileBuilder()
# Match the official Tensor G5 LiteRT-LM packages: model sections first,
# tokenizer next, metadata last. Some native executor paths assume this
# order even though the package format also carries section metadata.
builder = builder.add_tflite_model(
    tflite_model_path="{aot_prefill}",
    model_type=TfLiteModelType.PREFILL_DECODE,
)
{"builder = builder.add_tflite_model(tflite_model_path='" + embedder + "', model_type=TfLiteModelType.EMBEDDER)" if embedder else ""}
{"builder = builder.add_tflite_model(tflite_model_path='" + aux + "', model_type=TfLiteModelType.AUX)" if aux else ""}
builder = builder.add_hf_tokenizer("{tokenizer}")
builder = builder.add_llm_metadata("{metadata}")

with open(output_path, "wb") as f:
    builder.build(f)

print(f"PACKAGE_BUILT: {{os.path.getsize(output_path)}} bytes")
'''
    r = subprocess.run(
        [PYTHON, "-c", script],
        capture_output=True, text=True,
        timeout=300,
    )

    success = "PACKAGE_BUILT" in r.stdout
    return {
        "success": success,
        "stdout": r.stdout[-2000:],
        "stderr": r.stderr[-2000:],
        "output_path": output_path,
    }


from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="Build G5 NPU-ready .litertlm package")
    parser.add_argument("--dump-dir", required=True, help="Path to the dump/extracted .litertlm sections dir")
    parser.add_argument("--aot-output-dir", default=None, help="Path for AOT compilation output (default: <dump_dir>/../aot_compiled)")
    parser.add_argument("--output", default=None, help="Output .litertlm path (default: <dump_dir>/../model_g5_npu.litertlm)")
    parser.add_argument("--skip-aot", action="store_true", help="Skip AOT compilation, use existing aot_output_dir")
    args = parser.parse_args()

    dump_dir = os.path.expanduser(args.dump_dir)
    aot_dir = os.path.expanduser(args.aot_output_dir) if args.aot_output_dir else os.path.join(os.path.dirname(dump_dir.rstrip("/")), "aot_compiled")
    output_path = os.path.expanduser(args.output) if args.output else os.path.join(os.path.dirname(dump_dir.rstrip("/")), "model_g5_npu.litertlm")

    print(f"Dump dir: {dump_dir}")
    print(f"AOT dir: {aot_dir}")
    print(f"Output: {output_path}")

    # Step 1: AOT compile the prefill_decode
    if not args.skip_aot:
        # Find the prefill_decode TFLite
        prefill_files = list(Path(dump_dir).glob("*prefill_decode*.tflite"))
        if not prefill_files:
            print("ERROR: No prefill_decode TFLite found in dump dir!")
            sys.exit(1)
        prefill_path = str(prefill_files[0])
        print(f"\nStep 1: AOT compiling {prefill_path}")

        os.makedirs(aot_dir, exist_ok=True)
        result = aot_compile_decoder(prefill_path, aot_dir)

        if not result["success"]:
            print(f"AOT compilation FAILED!")
            print(f"stderr: {result['stderr'][:2000]}")
            sys.exit(1)
        print("AOT compilation succeeded!")
    else:
        print("\nStep 1: Skipping AOT (using existing compiled files)")

    # Step 2: Build .litertlm package
    print(f"\nStep 2: Building .litertlm package at {output_path}")
    result = build_litertlm_package(dump_dir, aot_dir, output_path)

    if not result["success"]:
        print(f"Package build FAILED!")
        print(f"stderr: {result['stderr'][:2000]}")
        sys.exit(1)

    print(f"\nPackage built successfully!")
    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"  Path: {output_path}")
    print(f"  Size: {size_mb:.1f} MB")

    # Verify the package
    print(f"\nStep 3: Verifying package...")
    r = subprocess.run(
        [PYTHON, "-m", "litert_lm_builder.litertlm_peek_main",
         "--litertlm_file", output_path],
        capture_output=True, text=True,
        timeout=30,
    )
    print(r.stdout[:1000])

    print("\nDone! This .litertlm package has:")
    print("  - AOT-compiled prefill_decode for Google Tensor G5 NPU")
    print("  - Original embedder (will run on CPU)")
    print("  - Original auxiliary (will run on CPU)")


if __name__ == "__main__":
    main()
