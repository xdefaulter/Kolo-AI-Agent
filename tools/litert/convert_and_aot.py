#!/usr/bin/env python3
"""
Kolo LiteRT-LM Conversion & AOT Compilation Harness.

Runs on p520 via: ~/venvs/kolo-litert-the-rock/bin/python

Supports:
  - HF model id or local path
  - Export to TFLite via litert_torch
  - Quantization (q8, q4, fp16, raw)
  - AOT compilation to Google Tensor G5
  - Optional split_cache, externalize_embedder
  - Optional google_tensor_truncation_type
  - Subgraph-level AOT testing

Logs everything to a report directory under the output folder.
"""

import argparse
import datetime
import json
import os
import platform
import shutil
import subprocess
import sys
import time
import traceback
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
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
CONTROL_MODEL = os.path.join(BASE_DIR, "control", "selfie_multiclass_256x256.tflite")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg: str, logfile=None):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    if logfile:
        logfile.write(line + "\n")
        logfile.flush()


def disk_usage(path: str) -> int:
    """Return disk usage in bytes."""
    r = subprocess.run(["du", "-sb", path], capture_output=True, text=True)
    if r.returncode == 0:
        return int(r.stdout.split()[0])
    return 0


def pip_versions(python: str) -> dict:
    r = subprocess.run(
        [python, "-m", "pip", "list", "--format=json"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return {}
    try:
        pkgs = json.loads(r.stdout)
        return {p["name"]: p["version"] for p in pkgs}
    except Exception:
        return {}


def summarize_tflite_ops(tflite_path: str, python: str) -> dict | None:
    """Read a TFLite flatbuffer and summarize op types."""
    script = f'''
import sys
sys.path.insert(0, '/')
from ai_edge_litert import interpreter as litert_interp
import json

interp = litert_interp.Interformer(model_path="{tflite_path}")
# Use flatbuf directly
try:
    from ai_edge_litert import _litert_so
    # Try flatbuffer API
    info = _litert_so.get_model_info("{tflite_path}")
    print(json.dumps({{"info": str(info)}}))
except Exception as e:
    print(json.dumps({{"error": str(e)}}))
'''
    # Fallback: use flatbuffers directly
    script2 = f'''
import json
try:
    # Read tflite as flatbuffer; extract op codes
    import flatbuffers
    # The tflite schema is large. We'll just read the raw bytes and count.
    with open("{tflite_path}", "rb") as f:
        data = f.read()
    print(json.dumps({{"size_bytes": len(data)}}))
except Exception as e:
    print(json.dumps({{"error": str(e)}}))
'''
    r = subprocess.run(
        [python, "-c", script2],
        capture_output=True, text=True, timeout=30,
    )
    try:
        return json.loads(r.stdout.strip())
    except Exception:
        return {"raw_stdout": r.stdout[:500], "raw_stderr": r.stderr[:500]}


def aot_compile_tflite(
    tflite_path: str,
    output_dir: str,
    python: str,
    target_soc: str = "TENSOR_G5",
    keep_going: bool = True,
    google_tensor_truncation_type: str | None = None,
    subgraphs_to_compile: list[int] | None = None,
    logfile=None,
) -> dict:
    """Run AOT compile on a single TFLite file. Returns result dict."""
    output_dir = os.path.expanduser(output_dir)
    tflite_path = os.path.expanduser(tflite_path)
    os.makedirs(output_dir, exist_ok=True)
    env = os.environ.copy()
    if GOOGLE_TENSOR_SDK_BETA:
        env["GOOGLE_TENSOR_SDK_BETA"] = GOOGLE_TENSOR_SDK_BETA

    kwargs_str = ""
    if google_tensor_truncation_type:
        kwargs_str += f', google_tensor_truncation_type="{google_tensor_truncation_type}"'

    subgraphs_str = ""
    if subgraphs_to_compile is not None:
        subgraphs_str = f", subgraphs_to_compile={subgraphs_to_compile}"

    # Must import google_tensor_backend to register the GOOGLE backend
    # before calling aot_compile. The package's __init__.py is empty.
    script = f'''
import os
os.environ["GOOGLE_TENSOR_SDK_BETA"] = "{GOOGLE_TENSOR_SDK_BETA}"
import json
import sys

# Register the Google Tensor backend (empty __init__.py doesn't auto-import)
from ai_edge_litert.aot.vendors.google_tensor import google_tensor_backend  # noqa: F401

from ai_edge_litert.aot import aot_compile as aot_lib
from ai_edge_litert.aot.vendors.google_tensor import target as gt_target
from ai_edge_litert.aot.core import aot_types

soc_map = {{
    "TENSOR_G5": gt_target.SocModel.TENSOR_G5,
    "TENSOR_G4": gt_target.SocModel.TENSOR_G4,
    "TENSOR_G3": gt_target.SocModel.TENSOR_G3,
}}
soc = soc_map.get("{target_soc}", gt_target.SocModel.TENSOR_G5)
tgt = gt_target.Target(soc)

try:
    result = aot_lib.aot_compile(
        "{tflite_path}",
        output_dir="{output_dir}",
        target=[tgt],
        keep_going={keep_going}{kwargs_str}{subgraphs_str},
    )
    report = result.compilation_report()
    print("AOT_COMPILE_SUCCESS")
    print("REPORT_START")
    print(report)
    print("REPORT_END")
    # Try to export
    result.export("{output_dir}")
    print("EXPORT_SUCCESS")
except Exception as e:
    import traceback
    print("AOT_COMPILE_FAILED")
    print(traceback.format_exc())
    sys.exit(1)
'''
    log(f"  Running AOT compile: {tflite_path} -> {output_dir}", logfile)
    log(f"  Target: {target_soc}, truncation: {google_tensor_truncation_type}, subgraphs: {subgraphs_to_compile}", logfile)

    start = time.time()
    r = subprocess.run(
        [python, "-c", script],
        capture_output=True, text=True,
        env=env,
        timeout=600,
    )
    elapsed = time.time() - start

    result = {
        "tflite_path": tflite_path,
        "target_soc": target_soc,
        "google_tensor_truncation_type": google_tensor_truncation_type,
        "subgraphs_to_compile": subgraphs_to_compile,
        "keep_going": keep_going,
        "elapsed_sec": round(elapsed, 2),
        "returncode": r.returncode,
        "stdout": r.stdout,
        "stderr": r.stderr,
    }

    if "AOT_COMPILE_SUCCESS" in r.stdout:
        result["status"] = "pass"
        # Extract report
        if "REPORT_START" in r.stdout and "REPORT_END" in r.stdout:
            report_text = r.stdout.split("REPORT_START")[1].split("REPORT_END")[0].strip()
            result["compilation_report"] = report_text
        if "EXPORT_SUCCESS" in r.stdout:
            result["export_status"] = "success"
    else:
        result["status"] = "fail"

    # Check output file sizes
    out_files = list(Path(output_dir).glob("*.tflite"))
    result["output_files"] = {f.name: f.stat().st_size for f in out_files}

    return result


def export_model(
    model_id: str,
    output_dir: str,
    python: str,
    prefill_lengths: list[int] | None = None,
    cache_length: int | None = None,
    quantization_recipe: str | None = None,
    split_cache: bool = False,
    externalize_embedder: bool = False,
    bundle_litert_lm: bool = False,
    aot_soc: str | None = None,
    aot_truncation_type: str | None = None,
    logfile=None,
) -> dict:
    """Export an HF model to TFLite using litert_torch, then optionally AOT compile."""

    output_dir = os.path.expanduser(output_dir)
    os.makedirs(output_dir, exist_ok=True)
    report_path = os.path.join(output_dir, "conversion_report.json")
    log_path = os.path.join(output_dir, "conversion.log")

    with open(log_path, "w") as lf:
        report = {
            "model_id": model_id,
            "output_dir": output_dir,
            "timestamp": datetime.datetime.now().isoformat(),
            "config": {
                "prefill_lengths": prefill_lengths,
                "cache_length": cache_length,
                "quantization_recipe": quantization_recipe,
                "split_cache": split_cache,
                "externalize_embedder": externalize_embedder,
                "bundle_litert_lm": bundle_litert_lm,
                "aot_soc": aot_soc,
                "aot_truncation_type": aot_truncation_type,
            },
            "python": python,
            "platform": {
                "system": platform.system(),
                "node": platform.node(),
                "python_version": platform.python_version(),
            },
        }

        log("=== KOLO LITERT CONVERSION HARNESS ===", lf)
        log(f"Model: {model_id}", lf)
        log(f"Output: {output_dir}", lf)
        log(f"Config: {json.dumps(report['config'], indent=2)}", lf)

        # Record pip versions
        disk_before = disk_usage(output_dir)
        log(f"Disk usage before: {disk_before} bytes", lf)
        report["disk_before_bytes"] = disk_before

        versions = pip_versions(python)
        key_packages = [
            "ai-edge-litert", "ai-edge-litert-sdk-google-tensor",
            "ai-edge-quantizer", "litert-torch", "litert-lm-builder",
            "litert-converter", "torch", "transformers", "accelerate",
            "flatbuffers", "numpy",
        ]
        report["pip_versions"] = {
            k: v for k, v in versions.items()
            if any(kp.lower() in k.lower() for kp in key_packages)
        }
        log(f"Key pip versions: {json.dumps(report['pip_versions'], indent=2)}", lf)

        # Export step
        env = os.environ.copy()
        if GOOGLE_TENSOR_SDK_BETA:
            env["GOOGLE_TENSOR_SDK_BETA"] = GOOGLE_TENSOR_SDK_BETA

        export_args = [
            python, "-m", "litert_torch.generative.export_hf.export",
            f"--model={model_id}",
            f"--output_dir={output_dir}",
            f"--task=text_generation",
        ]
        if prefill_lengths:
            export_args.append(f"--prefill_lengths={','.join(str(p) for p in prefill_lengths)}")
        if cache_length is not None:
            export_args.append(f"--cache_length={cache_length}")
        if quantization_recipe:
            export_args.append(f"--quantization_recipe={quantization_recipe}")
        if split_cache:
            export_args.append("--split_cache=True")
        if externalize_embedder:
            export_args.append("--externalize_embedder=True")
        if bundle_litert_lm:
            export_args.append("--bundle_litert_lm=True")

        log(f"\n--- EXPORT COMMAND ---\n{' '.join(export_args)}\n", lf)

        start_export = time.time()
        export_proc = subprocess.run(
            export_args,
            capture_output=True, text=True,
            env=env,
            timeout=1800,  # 30 min max
        )
        export_elapsed = time.time() - start_export

        log(f"Export completed in {export_elapsed:.1f}s, returncode={export_proc.returncode}", lf)

        report["export"] = {
            "command": " ".join(export_args),
            "returncode": export_proc.returncode,
            "elapsed_sec": round(export_elapsed, 2),
            "stdout_tail": export_proc.stdout[-3000:] if len(export_proc.stdout) > 3000 else export_proc.stdout,
            "stderr_tail": export_proc.stderr[-3000:] if len(export_proc.stderr) > 3000 else export_proc.stderr,
        }

        # Save full stdout/stderr
        with open(os.path.join(output_dir, "export_stdout.log"), "w") as f:
            f.write(export_proc.stdout)
        with open(os.path.join(output_dir, "export_stderr.log"), "w") as f:
            f.write(export_proc.stderr)

        export_success = export_proc.returncode == 0

        # List output files
        disk_after = disk_usage(output_dir)
        log(f"Disk usage after export: {disk_after} bytes", lf)
        report["disk_after_export_bytes"] = disk_after

        # Find TFLite files
        tflite_files = list(Path(output_dir).rglob("*.tflite"))
        tflite_info = {}
        for f in tflite_files:
            tflite_info[str(f)] = f.stat().st_size
            log(f"  TFLite: {f.name} ({f.stat().st_size} bytes)", lf)

        # Check for litertlm file
        litertlm_files = list(Path(output_dir).rglob("*.litertlm"))
        for f in litertlm_files:
            log(f"  LiteRTLM: {f.name} ({f.stat().st_size} bytes)", lf)

        report["tflite_files"] = tflite_info
        report["export_success"] = export_success

        if not export_success:
            log("EXPORT FAILED — skipping AOT compile.", lf)
            with open(report_path, "w") as f:
                json.dump(report, f, indent=2, default=str)
            return report

        # AOT compile step
        aot_results = []

        # AOT compile each TFLite subgraph
        for tf_path in tflite_files:
            if "apply_plugin" in tf_path.name:
                continue  # Skip already compiled files

            aot_dir = os.path.join(output_dir, f"aot_{tf_path.stem}")
            aot_result = aot_compile_tflite(
                str(tf_path), aot_dir, python,
                target_soc=aot_soc or "TENSOR_G5",
                keep_going=True,
                google_tensor_truncation_type=aot_truncation_type,
                logfile=lf,
            )
            aot_results.append(aot_result)

            # If full model failed, try subgraphs one at a time
            if aot_result["status"] == "fail" and "decoder" not in tf_path.stem.lower() and "embedder" not in tf_path.stem.lower():
                log(f"  Full model AOT failed for {tf_path.name}. Not trying subgraphs on non-decoder model.", lf)

        report["aot_results"] = aot_results
        disk_final = disk_usage(output_dir)
        report["disk_final_bytes"] = disk_final
        log(f"Final disk usage: {disk_final} bytes", lf)

    # Save report
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2, default=str)
    log(f"Report saved to {report_path}")

    return report


def aot_compile_subgraph(
    tflite_path: str,
    subgraph_indices: list[int],
    output_dir: str,
    python: str,
    target_soc: str = "TENSOR_G5",
    logfile=None,
) -> dict:
    """AOT compile specific subgraphs of a TFLite model."""
    return aot_compile_tflite(
        tflite_path, output_dir, python,
        target_soc=target_soc,
        keep_going=True,
        subgraphs_to_compile=subgraph_indices,
        logfile=logfile,
    )


def aot_compile_control(
    output_dir: str,
    python: str,
    logfile=None,
) -> dict:
    """AOT compile the control model (selfie segmentation) to verify the compiler works."""
    output_dir = os.path.expanduser(output_dir)
    os.makedirs(output_dir, exist_ok=True)
    log("=== AOT COMPILING CONTROL MODEL ===", logfile)
    return aot_compile_tflite(
        CONTROL_MODEL, output_dir, python,
        target_soc="TENSOR_G5",
        keep_going=True,
        logfile=logfile,
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Kolo LiteRT-LM Conversion Harness")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # --- export command ---
    p_export = subparsers.add_parser("export", help="Export HF model to TFLite + AOT compile")
    p_export.add_argument("--model", required=True, help="HF model ID or local path")
    p_export.add_argument("--output-dir", required=True, help="Output directory")
    p_export.add_argument("--prefill-lengths", nargs="+", type=int, default=None)
    p_export.add_argument("--cache-length", type=int, default=None)
    p_export.add_argument("--quantization-recipe", type=str, default=None,
                          help="e.g. 'dynamic_wi4_afp32' or 'dynamic_wi8_afp32'")
    p_export.add_argument("--split-cache", action="store_true")
    p_export.add_argument("--externalize-embedder", action="store_true")
    p_export.add_argument("--bundle-litert-lm", action="store_true")
    p_export.add_argument("--aot-soc", type=str, default="TENSOR_G5")
    p_export.add_argument("--aot-truncation-type", type=str, default=None)

    # --- aot command ---
    p_aot = subparsers.add_parser("aot", help="AOT compile a TFLite file")
    p_aot.add_argument("--tflite", required=True, help="Path to .tflite file")
    p_aot.add_argument("--output-dir", required=True, help="Output directory")
    p_aot.add_argument("--soc", type=str, default="TENSOR_G5")
    p_aot.add_argument("--truncation-type", type=str, default=None)
    p_aot.add_argument("--subgraphs", nargs="+", type=int, default=None,
                        help="Subgraph indices to compile (default: all)")

    # --- aot-control command ---
    p_ctrl = subparsers.add_parser("aot-control", help="AOT compile the control model")
    p_ctrl.add_argument("--output-dir", default=os.path.join(BASE_DIR, "control_aot_verify"))

    # --- matrix command ---
    p_matrix = subparsers.add_parser("matrix", help="Run a matrix of export+AOT variants")
    p_matrix.add_argument("--output-base-dir", default=os.path.join(BASE_DIR, "matrix"))
    p_matrix.add_argument("--models", nargs="+", default=[
        "Qwen/Qwen2.5-0.5B-Instruct",
        "Qwen/Qwen3-0.6B",
    ])
    p_matrix.add_argument("--prefill-lengths", nargs="+", type=int, default=[8, 16])
    p_matrix.add_argument("--cache-length", type=int, default=32)
    p_matrix.add_argument("--variants", nargs="+", default=[
        "q8_nosplit",
        "q4_nosplit",
        "q8_split",
        "q4_split",
        "q4_nosplit_trunchalf",
        "q4_split_extemb",
    ], help="Matrix variant names (resolved internally)")

    args = parser.parse_args()

    if args.command == "export":
        recipe = None
        if args.quantization_recipe:
            recipe = args.quantization_recipe
        export_model(
            model_id=args.model,
            output_dir=args.output_dir,
            python=PYTHON,
            prefill_lengths=args.prefill_lengths,
            cache_length=args.cache_length,
            quantization_recipe=recipe,
            split_cache=args.split_cache,
            externalize_embedder=args.externalize_embedder,
            bundle_litert_lm=args.bundle_litert_lm,
            aot_soc=args.aot_soc,
            aot_truncation_type=args.aot_truncation_type,
        )

    elif args.command == "aot":
        result = aot_compile_tflite(
            tflite_path=args.tflite,
            output_dir=args.output_dir,
            python=PYTHON,
            target_soc=args.soc,
            keep_going=True,
            google_tensor_truncation_type=args.truncation_type,
            subgraphs_to_compile=args.subgraphs,
        )
        print(json.dumps(result, indent=2, default=str))

    elif args.command == "aot-control":
        aot_compile_control(
            output_dir=args.output_dir,
            python=PYTHON,
        )

    elif args.command == "matrix":
        run_matrix(args)


def run_matrix(args):
    """Run a matrix of export+AOT variants for small Qwen models."""
    # Define variant configurations
    variant_configs = {
        "q8_nosplit": {
            "quantization_recipe": "dynamic_wi8_afp32",
            "split_cache": False,
            "externalize_embedder": False,
        },
        "q4_nosplit": {
            "quantization_recipe": "dynamic_wi4_afp32",
            "split_cache": False,
            "externalize_embedder": False,
        },
        "raw_nosplit": {
            "quantization_recipe": None,
            "split_cache": False,
            "externalize_embedder": False,
        },
        "q8_split": {
            "quantization_recipe": "dynamic_wi8_afp32",
            "split_cache": True,
            "externalize_embedder": False,
        },
        "q4_split": {
            "quantization_recipe": "dynamic_wi4_afp32",
            "split_cache": True,
            "externalize_embedder": False,
        },
        "q4_split_extemb": {
            "quantization_recipe": "dynamic_wi4_afp32",
            "split_cache": True,
            "externalize_embedder": True,
        },
        "q4_nosplit_trunchalf": {
            "quantization_recipe": "dynamic_wi4_afp32",
            "split_cache": False,
            "externalize_embedder": False,
            "aot_truncation_type": "half",
        },
        "q4_split_trunchalf": {
            "quantization_recipe": "dynamic_wi4_afp32",
            "split_cache": True,
            "externalize_embedder": False,
            "aot_truncation_type": "half",
        },
        "q4_split_extemb_trunchalf": {
            "quantization_recipe": "dynamic_wi4_afp32",
            "split_cache": True,
            "externalize_embedder": True,
            "aot_truncation_type": "half",
        },
    }

    # Filter to requested variants
    selected_variants = {}
    for v in args.variants:
        if v in variant_configs:
            selected_variants[v] = variant_configs[v]
        else:
            print(f"WARNING: Unknown variant '{v}', skipping")

    results_summary = []

    for model_id in args.models:
        model_slug = model_id.replace("/", "_")
        for variant_name, vcfg in selected_variants.items():
            run_name = f"{model_slug}__{variant_name}"
            run_dir = os.path.join(args.output_base_dir, run_name)
            print(f"\n{'='*60}")
            print(f"MATRIX RUN: {run_name}")
            print(f"{'='*60}")

            report = export_model(
                model_id=model_id,
                output_dir=run_dir,
                python=PYTHON,
                prefill_lengths=args.prefill_lengths,
                cache_length=args.cache_length,
                quantization_recipe=vcfg.get("quantization_recipe"),
                split_cache=vcfg.get("split_cache", False),
                externalize_embedder=vcfg.get("externalize_embedder", False),
                bundle_litert_lm=True,
                aot_soc="TENSOR_G5",
                aot_truncation_type=vcfg.get("aot_truncation_type"),
            )

            # Summarize
            export_ok = report.get("export_success", False)
            aot_results = report.get("aot_results", [])
            aot_pass = any(r.get("status") == "pass" for r in aot_results)
            aot_fail_count = sum(1 for r in aot_results if r.get("status") == "fail")

            results_summary.append({
                "run_name": run_name,
                "model_id": model_id,
                "variant": variant_name,
                "export_success": export_ok,
                "aot_pass_any": aot_pass,
                "aot_fail_count": aot_fail_count,
                "aot_results_count": len(aot_results),
            })

            # Be conservative with disk - clean up large intermediates if AOT failed
            if not export_ok or (aot_results and all(r.get("status") == "fail" for r in aot_results)):
                # Keep logs but remove large .tflite model files
                for tf in list(Path(run_dir).rglob("*.tflite")):
                    if "apply_plugin" not in tf.name:
                        tf_size = tf.stat().st_size
                        if tf_size > 100_000_000:  # > 100MB
                            print(f"  Cleaning up large intermediate: {tf.name} ({tf_size/1e6:.1f} MB)")
                            # Move to a compressed archive instead of deleting
                            import gzip
                            gz_path = str(tf) + ".gz_info"
                            with open(gz_path, "w") as f:
                                f.write(f"Removed {tf.name} ({tf_size} bytes) to save disk\n")
                            tf.unlink()

    # Write summary
    summary_path = os.path.join(args.output_base_dir, "matrix_summary.json")
    with open(summary_path, "w") as f:
        json.dump(results_summary, f, indent=2, default=str)

    print(f"\n{'='*60}")
    print("MATRIX SUMMARY")
    print(f"{'='*60}")
    for r in results_summary:
        status = "PASS" if r["export_success"] and r["aot_pass_any"] else "FAIL"
        print(f"  {r['run_name']:50s} export={r['export_success']} aot_pass={r['aot_pass_any']} => {status}")
    print(f"\nFull summary: {summary_path}")


if __name__ == "__main__":
    main()