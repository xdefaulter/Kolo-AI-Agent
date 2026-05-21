#!/usr/bin/env python3
"""
Kolo LiteRT-LM Graph Reduction & Subgraph Analysis.

Tools to:
  - Inspect TFLite model subgraphs and operator types
  - AOT compile individual subgraphs
  - Reduce a failing model to the smallest failing subgraph
  - Compare against the control (selfie) model

Runs on p520 via: ~/venvs/kolo-litert-the-rock/bin/python
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

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


def inspect_tflite(tflite_path: str, python: str) -> dict:
    """Inspect a TFLite file and return subgraph info, op types, etc."""

    script = f'''
import json
import struct

# Read the TFLite file using flatbuffers to extract op info
# Since we may not have tflite runtime with schema, use the flatbuffer directly

path = "{tflite_path}"
size = os.path.getsize(path) if os.path.exists(path) else 0

# Try using ai_edge_litert interpreter for model info
result = {{"path": path, "size_bytes": size}}

# Try the LiteRT interpreter to get signature info
try:
    from ai_edge_litert.interpreter import Interpreter
    interp = Interpreter(model_path=path)
    interp.allocate_tensors()

    input_details = interp.get_input_details()
    output_details = interp.get_output_details()

    result["inputs"] = []
    for inp in input_details:
        result["inputs"].append({{
            "name": inp.get("name", ""),
            "shape": list(inp.get("shape", [])),
            "dtype": str(inp.get("dtype", "")),
        }})

    result["outputs"] = []
    for out in output_details:
        result["outputs"].append({{
            "name": out.get("name", ""),
            "shape": list(out.get("shape", [])),
            "dtype": str(out.get("dtype", "")),
        }})

    # Get subgraph count if possible
    result["num_subgraphs"] = len(interp._subgraphs) if hasattr(interp, '_subgraphs') else "unknown"

except Exception as e:
    result["interpreter_error"] = str(e)

# Try using flatbuffers to extract operator codes
try:
    # Use flatbuffers python library to parse the TFLite schema
    # The schema file should be in the tflite package
    import flatbuffers
    # Read raw bytes
    with open(path, "rb") as f:
        buf = f.read()

    # The TFLite file format starts with a flatbuffer header
    # We can try to use the tflite schema from ai_edge_litert
    result["file_size_human"] = f"{{size / 1e6:.1f}} MB"

except Exception as e:
    result["flatbuffers_error"] = str(e)

print(json.dumps(result, indent=2, default=str))
'''

    # Simpler version using just file size and name
    script_simple = f'''
import json
import os

path = "{tflite_path}"
result = {{
    "path": path,
    "size_bytes": os.path.getsize(path) if os.path.exists(path) else 0,
}}

# Try to use tflite with ai_edge_litert
try:
    from ai_edge_litert.interpreter import Interpreter
    interp = Interpreter(model_path=path)
    interp.allocate_tensors()

    input_details = interp.get_input_details()
    output_details = interp.get_output_details()

    result["inputs"] = []
    for inp in input_details:
        result["inputs"].append({{
            "name": inp.get("name", ""),
            "shape": str(inp.get("shape", [])),
            "dtype": str(inp.get("dtype", "")),
        }})

    result["outputs"] = []
    for out in output_details:
        result["outputs"].append({{
            "name": out.get("name", ""),
            "shape": str(out.get("shape", [])),
            "dtype": str(out.get("dtype", "")),
        }})

    result["interpreter_success"] = True
except Exception as e:
    result["interpreter_error"] = str(e)[:500]
    result["interpreter_success"] = False

print(json.dumps(result, indent=2, default=str))
'''

    r = subprocess.run(
        [python, "-c", script_simple],
        capture_output=True, text=True, timeout=60,
    )

    try:
        return json.loads(r.stdout.strip())
    except json.JSONDecodeError:
        return {
            "path": tflite_path,
            "parse_error": True,
            "stdout": r.stdout[:1000],
            "stderr": r.stderr[:1000],
        }


def aot_compile_with_log(
    tflite_path: str,
    output_dir: str,
    python: str,
    target_soc: str = "TENSOR_G5",
    truncation_type: str | None = None,
    subgraphs: list[int] | None = None,
    keep_going: bool = True,
    timeout: int = 600,
) -> dict:
    """AOT compile a TFLite model and capture full output."""
    output_dir = os.path.expanduser(output_dir)
    tflite_path = os.path.expanduser(tflite_path)
    os.makedirs(output_dir, exist_ok=True)
    env = os.environ.copy()
    env["GOOGLE_TENSOR_SDK_BETA"] = GOOGLE_TENSOR_SDK_BETA

    subgraphs_arg = f", subgraphs_to_compile={subgraphs}" if subgraphs else ""
    truncation_arg = f', google_tensor_truncation_type="{truncation_type}"' if truncation_type else ""

    # Must import google_tensor_backend to register the GOOGLE backend
    # before calling aot_compile. The package's __init__.py is empty.
    script = f'''
import os
os.environ["GOOGLE_TENSOR_SDK_BETA"] = "{GOOGLE_TENSOR_SDK_BETA}"
import json
import sys

from ai_edge_litert.aot.vendors.google_tensor import google_tensor_backend  # noqa: F401

from ai_edge_litert.aot import aot_compile as aot_lib
from ai_edge_litert.aot.vendors.google_tensor import target as gt_target

soc_map = {{
    "TENSOR_G5": gt_target.SocModel.TENSOR_G5,
    "TENSOR_G4": gt_target.SocModel.TENSOR_G4,
}}
soc = soc_map.get("{target_soc}", gt_target.SocModel.TENSOR_G5)
tgt = gt_target.Target(soc)

try:
    result = aot_lib.aot_compile(
        "{tflite_path}",
        output_dir="{output_dir}",
        target=[tgt],
        keep_going={keep_going}{truncation_arg}{subgraphs_arg},
    )
    report = result.compilation_report()
    print("AOT_SUCCESS")
    print("REPORT_START")
    print(report)
    print("REPORT_END")
    try:
        result.export("{output_dir}")
        print("EXPORT_OK")
    except Exception as e:
        print(f"EXPORT_ERROR: {{e}}")
except Exception as e:
    import traceback
    print("AOT_FAILED")
    print(traceback.format_exc())
    sys.exit(1)
'''

    start = time.time()
    r = subprocess.run(
        [python, "-c", script],
        capture_output=True, text=True,
        env=env, timeout=timeout,
    )
    elapsed = time.time() - start

    result = {
        "tflite_path": tflite_path,
        "output_dir": output_dir,
        "target_soc": target_soc,
        "truncation_type": truncation_type,
        "subgraphs": subgraphs,
        "elapsed_sec": round(elapsed, 2),
        "returncode": r.returncode,
        "stdout": r.stdout,
        "stderr": r.stderr[:5000],
    }

    # Extract compilation report and determine actual pass/fail
    if "REPORT_START" in r.stdout and "REPORT_END" in r.stdout:
        report_text = r.stdout.split("REPORT_START")[1].split("REPORT_END")[0].strip()
        result["compilation_report"] = report_text
        # keep_going=True masks failures; detect them from the report
        if "COMPILATION FAILURES" in report_text:
            result["status"] = "fail_with_report"
        else:
            result["status"] = "pass"
    elif "AOT_SUCCESS" in r.stdout:
        result["status"] = "pass"
    else:
        result["status"] = "fail"

    # Check output files
    out_files = list(Path(output_dir).glob("*.tflite"))
    result["output_files"] = {f.name: f.stat().st_size for f in out_files}

    # Save logs
    with open(os.path.join(output_dir, "aot_stdout.log"), "w") as f:
        f.write(r.stdout)
    with open(os.path.join(output_dir, "aot_stderr.log"), "w") as f:
        f.write(r.stderr)

    return result


def reduce_graph(tflite_path: str, output_dir: str, python: str) -> dict:
    """
    Binary search for the smallest failing subgraph.
    Try AOT on subgraphs 0, 1, 2... individually, then try combinations.
    """
    os.makedirs(output_dir, exist_ok=True)
    log_path = os.path.join(output_dir, "reduction.log")

    with open(log_path, "w") as lf:
        lf.write(f"=== Graph Reduction for {tflite_path} ===\n")
        lf.write(f"Started: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        # First: try the full model
        lf.write("Step 0: Full model AOT compile\n")
        full_dir = os.path.join(output_dir, "step00_full")
        full_result = aot_compile_with_log(tflite_path, full_dir, python)
        full_status = full_result["status"]

        lf.write(f"  Full model: {full_status}\n")
        lf.write(f"  Report: {full_result.get('compilation_report', 'N/A')[:500]}\n\n")

        if full_status == "pass":
            lf.write("Full model passes AOT — nothing to reduce.\n")
            return {"status": "pass", "steps": [full_result]}

        # Try individual subgraphs 0 through 4
        subgraph_results = []
        for sg_idx in range(5):  # Try subgraphs 0-4
            lf.write(f"Step: AOT compile subgraph {sg_idx} only\n")
            sg_dir = os.path.join(output_dir, f"step_subgraph_{sg_idx}")
            sg_result = aot_compile_with_log(
                tflite_path, sg_dir, python,
                subgraphs=[sg_idx],
            )
            sg_result["subgraph_index"] = sg_idx
            subgraph_results.append(sg_result)
            lf.write(f"  Subgraph {sg_idx}: {sg_result['status']}\n")

            # If subgraph compilation failed, we've isolated the failure
            if sg_result["status"] == "fail":
                lf.write(f"\n  ISOLATED: Subgraph {sg_idx} is the failing subgraph.\n")

                # Try to parse the error for op information
                error_text = sg_result.get("stderr", "") + sg_result.get("stdout", "")
                lf.write(f"  Error excerpt: {error_text[:1000]}\n")

        return {
            "status": "fail",
            "full_result": full_result,
            "subgraph_results": subgraph_results,
            "log_path": log_path,
        }


def compare_with_control(python: str) -> dict:
    """Verify the compiler works by compiling the control model."""
    control_dir = os.path.join(BASE_DIR, "control_verify")
    result = aot_compile_with_log(CONTROL_MODEL, control_dir, python)
    return result


def main():
    parser = argparse.ArgumentParser(description="Kolo LiteRT Graph Reduction Tools")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # inspect
    p_inspect = subparsers.add_parser("inspect", help="Inspect a TFLite file")
    p_inspect.add_argument("--tflite", required=True, help="Path to .tflite file")

    # aot
    p_aot = subparsers.add_parser("aot", help="AOT compile a TFLite file")
    p_aot.add_argument("--tflite", required=True, help="Path to .tflite file")
    p_aot.add_argument("--output-dir", required=True, help="Output directory")
    p_aot.add_argument("--soc", type=str, default="TENSOR_G5")
    p_aot.add_argument("--truncation-type", type=str, default=None)
    p_aot.add_argument("--subgraphs", nargs="+", type=int, default=None)
    p_aot.add_argument("--timeout", type=int, default=600)

    # reduce
    p_reduce = subparsers.add_parser("reduce", help="Binary-search for smallest failing subgraph")
    p_reduce.add_argument("--tflite", required=True, help="Path to .tflite file")
    p_reduce.add_argument("--output-dir", required=True, help="Output directory")

    # control-verify
    p_ctrl = subparsers.add_parser("control-verify", help="AOT compile the control model to verify compiler works")

    args = parser.parse_args()

    if args.command == "inspect":
        result = inspect_tflite(args.tflite, PYTHON)
        print(json.dumps(result, indent=2))

    elif args.command == "aot":
        result = aot_compile_with_log(
            tflite_path=args.tflite,
            output_dir=args.output_dir,
            python=PYTHON,
            target_soc=args.soc,
            truncation_type=args.truncation_type,
            subgraphs=args.subgraphs,
            timeout=args.timeout,
        )
        print(json.dumps(result, indent=2, default=str))

    elif args.command == "reduce":
        result = reduce_graph(args.tflite, args.output_dir, PYTHON)
        print(json.dumps(result, indent=2, default=str))

    elif args.command == "control-verify":
        result = compare_with_control(PYTHON)
        print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()