#!/usr/bin/env python3
"""Run the declared release corpus against fresh Stage 1/2/3 compilers.

Generation builds are performed by bootstrap_release.py before this runner is
invoked. This runner only reads those executables and writes disposable test
outputs and a machine-readable result report.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
STAGE_TARGETS = ("x86_64-linux-gnu", "aarch64-linux-gnu",
                 "riscv64-linux-gnu", "x86_64-windows-gnu")
from bootstrap_release import SEED_ONLY
ENV_MODES = {"compiler-env", "target-env"}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def cross_environment() -> dict[str, str]:
    environment = os.environ.copy()
    root_value = environment.get("PSL_CROSS_TOOL_ROOT")
    root = Path(root_value).resolve() if root_value else (ROOT.parent / "m8-cross-tools").resolve()
    additions = [root / "bin", root / "usr" / "bin"]
    available = [str(item) for item in additions if item.is_dir()]
    if available:
        environment["PATH"] = os.pathsep.join([*available, environment.get("PATH", "")])
    library = str(root / "usr" / "lib" / "x86_64-linux-gnu")
    if Path(library).is_dir():
        environment["LD_LIBRARY_PATH"] = os.pathsep.join(
            [library, environment.get("LD_LIBRARY_PATH", "")]).rstrip(os.pathsep)
    if "AARCH64_SYSROOT" not in environment and (root / "usr" / "aarch64-linux-gnu").is_dir():
        environment["AARCH64_SYSROOT"] = str(root / "usr" / "aarch64-linux-gnu")
    if "RISCV64_SYSROOT" not in environment and (root / "usr" / "riscv64-linux-gnu").is_dir():
        environment["RISCV64_SYSROOT"] = str(root / "usr" / "riscv64-linux-gnu")
    return environment


def declared_gates(data: dict) -> list[str]:
    ordered = []
    seen = set()
    for group in data["release_gate_groups"].values():
        for path in group:
            if path not in seen:
                seen.add(path)
                ordered.append(path)
    return ordered


def run_logged_command(command: list[str], log_path: Path,
                       env: dict[str, str]) -> int:
    """Preserve observable progress and partial output during long release gates."""
    with log_path.open("wb") as log:
        result = subprocess.run(command, cwd=ROOT, env=env,
                                stdout=log, stderr=subprocess.STDOUT)
    return result.returncode


def run_gate(path: str, mode: str, compiler: Path | None,
             stage_directory: Path, env: dict[str, str], log_dir: Path,
             objects: dict[str, Path] | None = None) -> dict:
    script = ROOT / path
    if not script.is_file():
        raise RuntimeError(f"declared corpus gate is missing: {path}")
    command = ["sh", str(script)]
    gate_env = env.copy()
    gate_env["PSL_RELEASE_STAGE_COMPILER"] = str(compiler) if compiler else ""
    # A release gate must execute the full native-core IR capture check.
    gate_env["PSL_SKIP_NATIVE_CORE_DUMP"] = "0"
    if compiler is not None:
        gate_env["PSL_NATIVE_COMPILER"] = str(compiler)
        gate_env["PSL_NATIVE_COMPILER_HOST_TARGET"] = "x86_64-linux-gnu"
    if mode == "compiler":
        command.append(str(compiler))
    elif mode == "compiler-target":
        return run_target_matrix(path, mode, STAGE_TARGETS,
                                 lambda target: command + [str(compiler), target],
                                 gate_env, log_dir)
    elif mode == "stage-native-api":
        if compiler is None or objects is None:
            raise RuntimeError("stage-native API gate requires the current generation compiler and objects")
        gate_env.update({
            "PSL_NATIVE_CORE_OBJECT": str(objects["core"]),
            "PSL_NATIVE_HOST_OBJECT": str(objects["host"]),
            "PSL_NATIVE_SOURCE_OBJECT": str(objects["source"]),
            "PSL_NATIVE_INPUT_OBJECT": str(objects["input"]),
            "PSL_NATIVE_PATH_OBJECT": str(objects["path-posix"]),
            "PSL_NATIVE_DRIVER_OBJECT": str(objects["compiler"]),
            "PSL_NATIVE_OUTPUT_OBJECT": str(objects["output"]),
            "PSL_NATIVE_DIAGNOSTICS_OBJECT": str(objects["diagnostics"]),
        })
        command.append("x86_64-linux-gnu")
    elif mode == "stage-source-loader-allocations":
        if compiler is None or objects is None:
            raise RuntimeError("source-loader allocation gate requires current stage objects")
        command.extend([str(objects["core"]), str(objects["source"]),
                        str(objects["input"]), str(objects["path-posix"])])
    elif mode == "target-native-env":
        return run_target_matrix(path, mode, STAGE_TARGETS,
                                 lambda target: command + [target],
                                 gate_env, log_dir)
    elif mode == "compiler-targets":
        return run_target_matrix(path, mode, STAGE_TARGETS,
                                 lambda target: command + [str(compiler), target],
                                 gate_env, log_dir)
    elif mode == "compiler-target-env":
        return run_target_matrix(path, mode, STAGE_TARGETS,
                                 lambda target: command + [target],
                                 gate_env, log_dir)
    elif mode == "compiler-win64":
        return run_target_matrix(path, mode, ("x86_64-windows-gnu",),
                                 lambda target: command + [str(compiler), target],
                                 gate_env, log_dir)
    elif mode == "compiler-elf-targets":
        targets = ("x86_64-linux-gnu", "aarch64-linux-gnu", "riscv64-linux-gnu")
        return run_target_matrix(path, mode, targets,
                                 lambda target: command + [str(compiler), target],
                                 gate_env, log_dir)
    elif mode == "seed-elf-targets":
        targets = ("x86_64-linux-gnu", "aarch64-linux-gnu", "riscv64-linux-gnu")
        gate_env.pop("PSL_NATIVE_COMPILER", None)
        gate_env.pop("PSL_NATIVE_COMPILER_HOST_TARGET", None)
        return run_target_matrix(path, mode, targets,
                                 lambda target: command + [target],
                                 gate_env, log_dir)
    elif mode == "compiler-env":
        pass
    elif mode == "target-env":
        targets = (("aarch64-linux-gnu", "riscv64-linux-gnu")
                   if path.endswith("bootstrap_native_elf.sh")
                   else ("x86_64-linux-gnu",))
        return run_target_matrix(path, mode, targets,
                                 lambda target: command + [target],
                                 gate_env, log_dir)
    elif mode == "compiler-seed-target":
        if compiler is None or objects is None:
            raise RuntimeError("macro growth gate requires current generation core and host objects")
        gate_env["PSL_NATIVE_CORE_OBJECT"] = str(objects["core"])
        gate_env["PSL_NATIVE_HOST_OBJECT"] = str(objects["host"])
        return run_target_matrix(
            path, mode, STAGE_TARGETS,
            lambda target: command + [str(compiler), str(ROOT / "pslcc"), target],
            gate_env, log_dir)
    elif mode == "seed-only":
        gate_env.pop("PSL_NATIVE_COMPILER", None)
        gate_env.pop("PSL_NATIVE_COMPILER_HOST_TARGET", None)
    else:
        raise RuntimeError(f"no invocation mode declared for release gate: {path}")
    log_path = log_dir / (Path(path).stem + ".log")
    status = run_logged_command(command, log_path, gate_env)
    if status:
        raise RuntimeError(f"{path} failed status {status}; see {log_path}")
    return {"path": path, "mode": mode, "status": status,
            "log": str(log_path)}


def run_target_matrix(path: str, mode: str, targets: tuple[str, ...],
                      command_for_target, env: dict[str, str],
                      log_dir: Path) -> dict:
    failures = []
    for target in targets:
        target_log = log_dir / (Path(path).stem + "-" + target + ".log")
        status = run_logged_command(command_for_target(target), target_log, env)
        if status:
            failures.append(f"{target}: status {status} ({target_log})")
    if failures:
        raise RuntimeError(f"{path} target matrix failed: " + "; ".join(failures))
    return {"path": path, "mode": mode, "status": 0,
            "targets": list(targets)}


def run_example_inventory(stage_compilers: list[Path], report_path: Path,
                          log_dir: Path, runner_path: str) -> dict:
    log_dir.mkdir(parents=True, exist_ok=True)
    runner = ROOT / runner_path
    if not runner.is_file():
        raise RuntimeError(f"declared example inventory runner is missing: {runner_path}")
    command = [sys.executable, str(runner),
               "--stage0", str(ROOT / "pslcc"), "--report", str(report_path),
               "--require-parity"]
    for compiler in stage_compilers:
        command += ["--native", str(compiler)]
    log_path = log_dir / "example-inventory.log"
    status = run_logged_command(command, log_path, cross_environment())
    if status:
        raise RuntimeError(f"complete example inventory failed status {status}; see {log_path}")
    return {"path": "tests/bootstrap_corpus.py", "status": status,
            "report": str(report_path), "log": str(log_path)}


def run_full_test_source_inventory(source_manifest_path: Path,
                                   stage_compilers: list[Path],
                                   report_directory: Path,
                                   source_filter: set[str] | None = None,
                                   stage_gate_results: list[dict] | None = None,
                                   declared_gate_paths: set[str] | None = None) -> dict:
    source_manifest = json.loads(source_manifest_path.read_text(encoding="utf-8"))
    if source_manifest.get("schema") != 3:
        raise RuntimeError("source inventory lacks required per-row owner reasons and target/profile matrix")
    rows = source_manifest.get("files", [])
    sources = [*(ROOT / "tests").rglob("*.lisp"),
               *(ROOT / "examples").rglob("*.lisp")]
    discovered = {path.relative_to(ROOT).as_posix(): path for path in sources}
    if set(row.get("path") for row in rows) != set(discovered):
        raise RuntimeError("source inventory does not cover every tests/**/*.lisp and examples/**/*.lisp input")
    if declared_gate_paths is None:
        manifest = json.loads((ROOT / "tests" / "bootstrap_compiler_manifest.json").read_text(encoding="utf-8"))
        all_gates = set(declared_gates(manifest))
    else:
        all_gates = set(declared_gate_paths)
    for row in rows:
        if row.get("role") != "standalone":
            owners = set(row.get("owner_gates", []))
            if (not owners or not owners <= all_gates or
                    not row.get("owner_reason", "").strip() or
                    any(not (ROOT / gate).is_file() for gate in owners)):
                raise RuntimeError(f"non-standalone source has missing/undeclared owner gate: {row.get('path')}")
    if source_filter is not None:
        unknown = source_filter - set(discovered)
        if unknown:
            raise RuntimeError("unknown focused source path(s): " + ", ".join(sorted(unknown)))
        rows = [row for row in rows if row["path"] in source_filter]
    if stage_gate_results is None:
        stage_gate_results = []
    if len(stage_gate_results) != len(stage_compilers):
        raise RuntimeError("source inventory requires the actual gate results for every generated stage")
    stage_gate_maps = []
    for generation, result in enumerate(stage_gate_results, 1):
        if result.get("generation") != generation:
            raise RuntimeError("source inventory received stage gate results in the wrong generation order")
        stage_gate_maps.append({gate.get("path"): gate for gate in result.get("gates", [])})
    cells = source_manifest.get("status_cells", [])
    if not cells:
        raise RuntimeError("source inventory has no target/profile status matrix")
    records = []
    output_dir = report_directory / "test-source-objects"
    output_dir.mkdir()
    diagnostic_dir = report_directory / "test-source-diagnostics"
    diagnostic_dir.mkdir()
    stage_results = [{"generation": index, "compiler": str(compiler),
                      "sha256": digest(compiler), "source_cells": []}
                     for index, compiler in enumerate(stage_compilers, 1)]
    from bootstrap_release import cached_seed_compile, source_probe_repository_digest
    env = cross_environment()
    seed_toolchain = source_manifest["stage0_toolchain"]
    seed_repository_digest = source_probe_repository_digest()
    # Stage 0 is the slowest part of this inventory. Run the two required
    # optimization levels concurrently, with a hard limit of two compiler
    # processes. Results and object bytes still flow through the same checks
    # below, and the cache makes an interrupted refresh resumable.
    seed_executor = ThreadPoolExecutor(max_workers=2)
    seed_cache_hits = 0
    seed_cache_misses = 0
    readelf = {"x86_64-linux-gnu": "readelf",
               "aarch64-linux-gnu": "aarch64-linux-gnu-readelf",
               "riscv64-linux-gnu": "riscv64-linux-gnu-readelf",
               "x86_64-none-elf": "readelf",
               "riscv64-none-elf": "riscv64-linux-gnu-readelf"}
    for source_index, row in enumerate(rows):
        source = ROOT / row["path"]
        if digest(source) != row.get("sha256"):
            raise RuntimeError(f"stale full-source inventory hash: {row['path']}")
        role = row.get("role")
        if role != "standalone":
            owners = row["owner_gates"]
            stage_owners = [gate for gate in owners if gate not in SEED_ONLY]
            if not stage_owners:
                raise RuntimeError(f"non-standalone source has no per-stage owner gate: {row['path']}")
            evidence = []
            for generation, gate_map in enumerate(stage_gate_maps, 1):
                missing = [gate for gate in stage_owners if gate not in gate_map]
                failed = [gate for gate in stage_owners
                          if gate in gate_map and gate_map[gate].get("status") != 0]
                if missing or failed:
                    raise RuntimeError(
                        f"Stage {generation} did not pass all owner gates for {row['path']}: "
                        f"missing={missing}, failed={failed}")
                evidence.append({"generation": generation,
                                 "compiler": str(stage_compilers[generation - 1]),
                                 "compiler_sha256": digest(stage_compilers[generation - 1]),
                                 "gates": [gate_map[gate] for gate in stage_owners]})
            records.append({"source": row["path"], "role": role,
                            "stage0_status": None,
                            "native_status": "covered-by-verified-owner-gates",
                            "owner_gates": owners,
                            "owner_reason": row["owner_reason"],
                            "stage_gate_evidence": evidence})
            continue
        statuses = row.get("stage0_status")
        if not isinstance(statuses, dict):
            raise RuntimeError(f"source has no Stage 0 status matrix: {row['path']}")
        for cell_index, cell in enumerate(cells):
            target, profile = cell["target"], cell["profile"]
            cell_key = f"{target}|{profile}"
            expected = statuses.get(cell_key)
            if expected not in {"accepted", "rejected"}:
                raise RuntimeError(f"source status missing for {row['path']} at {cell_key}")
            source_record = {"target": target, "profile": profile,
                             "stage0_status": expected, "optimizations": []}
            seed_outputs = {
                level: output_dir / f"seed-{source_index}-{cell_index}-O{level}.o"
                for level in (0, 1)
            }
            seed_futures = {}
            for level, seed_output in seed_outputs.items():
                seed_output.unlink(missing_ok=True)
                seed_futures[level] = seed_executor.submit(
                    cached_seed_compile, source, target, profile, seed_toolchain,
                    seed_repository_digest, f"-O{level}", env, seed_output)
            for level in (0, 1):
                seed_output = seed_outputs[level]
                _, seed_status, seed_stdout, seed_stderr, cache_hit = seed_futures[level].result()
                seed_cache_hits += int(cache_hit)
                seed_cache_misses += int(not cache_hit)
                if seed_status != expected:
                    raise RuntimeError(f"Stage 0 status changed for {row['path']} -O{level} {cell_key}")
                if seed_output.exists() != (seed_status == "accepted"):
                    raise RuntimeError(f"Stage 0 artifact mismatch for {row['path']} -O{level} {cell_key}")
                if seed_status == "rejected":
                    stem = f"seed-{source_index}-{cell_index}-O{level}"
                    (diagnostic_dir / f"{stem}.stdout").write_bytes(seed_stdout)
                    (diagnostic_dir / f"{stem}.stderr").write_bytes(seed_stderr)
                stage1_ir = stage2_bytes = stage2_ir = None
                stage1_diagnostic = stage2_diagnostic = None
                for stage_index, compiler in enumerate(stage_compilers, 1):
                    output = output_dir / f"stage{stage_index}-{source_index}-{cell_index}-O{level}.o"
                    output.unlink(missing_ok=True)
                    command = [str(compiler), f"-O{level}", f"--target={target}",
                               f"--profile={profile}", "-c", str(source), "-o", str(output)]
                    if expected == "accepted":
                        command.append("--dump-ir=all")
                    result = subprocess.run(command, cwd=ROOT, env=env,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    status = "accepted" if result.returncode == 0 else "rejected"
                    if result.returncode not in (0, 1) or status != expected:
                        diagnostic = result.stderr.decode("utf-8", errors="replace")
                        raise RuntimeError(f"Stage {stage_index} differs from Stage 0 for {row['path']} -O{level} {cell_key}: {result.returncode}\n{diagnostic}")
                    if output.exists() != (status == "accepted"):
                        raise RuntimeError(f"Stage {stage_index} artifact mismatch for {row['path']} -O{level} {cell_key}")
                    diagnostic_hash = digest_bytes(result.stdout + b"\0" + result.stderr)
                    if status == "rejected":
                        stem = f"stage{stage_index}-{source_index}-{cell_index}-O{level}"
                        (diagnostic_dir / f"{stem}.stdout").write_bytes(result.stdout)
                        (diagnostic_dir / f"{stem}.stderr").write_bytes(result.stderr)
                        diagnostic = (result.stdout, result.stderr)
                        if stage_index == 1:
                            stage1_diagnostic = diagnostic
                        elif stage_index == 2:
                            stage2_diagnostic = diagnostic
                        elif stage_index == 3 and (diagnostic != stage2_diagnostic or diagnostic != stage1_diagnostic):
                            raise RuntimeError(f"Stage rejection diagnostics differ for {row['path']} -O{level} {cell_key}")
                    else:
                        inspector = readelf.get(target)
                        if target == "x86_64-windows-gnu":
                            header = subprocess.run(["x86_64-w64-mingw32-objdump", "-f", str(output)],
                                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                                    env=env, check=True).stdout
                            if b"pe-x86-64" not in header:
                                raise RuntimeError(f"unexpected COFF object for {row['path']} {cell_key}")
                        else:
                            header = subprocess.run([inspector, "-h", str(output)],
                                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                                    env=env, check=True).stdout
                            machine = {"x86_64-linux-gnu": b"Advanced Micro Devices X86-64",
                                       "aarch64-linux-gnu": b"AArch64",
                                       "riscv64-linux-gnu": b"RISC-V",
                                       "x86_64-none-elf": b"Advanced Micro Devices X86-64",
                                       "riscv64-none-elf": b"RISC-V"}[target]
                            if b"REL (Relocatable file)" not in header or machine not in header:
                                raise RuntimeError(f"unexpected object header for {row['path']} {cell_key}")
                        artifact = output.read_bytes()
                        if stage_index == 1:
                            stage1_ir = result.stdout
                        elif stage_index == 2:
                            stage2_bytes, stage2_ir = artifact, result.stdout
                        elif stage_index == 3:
                            if artifact != stage2_bytes:
                                raise RuntimeError(f"Stage objects differ for {row['path']} -O{level} {cell_key}")
                            if result.stdout != stage2_ir:
                                raise RuntimeError(f"Stage IR differs for {row['path']} -O{level} {cell_key}")
                            if result.stdout != stage1_ir:
                                raise RuntimeError(f"Stage 1 IR differs from fixed point for {row['path']} -O{level} {cell_key}")
                    stage_results[stage_index - 1]["source_cells"].append(
                        {"source": row["path"], "target": target, "profile": profile,
                         "optimization": level, "status": status,
                         "object_sha256": digest(output) if output.exists() else None,
                         "ir_or_diagnostic_sha256": digest_bytes(result.stdout + b"\0" + result.stderr)})
                source_record["optimizations"].append(level)
            records.append({"source": row["path"], "role": role,
                            "target_profile": source_record})
    seed_executor.shutdown(wait=True)
    report = {"schema": 3, "source_manifest_sha256": digest(source_manifest_path),
              "source_count": len(rows),
              "source_target_profile_count": sum(row["role"] == "standalone" for row in records),
              "excluded_by_role": sum(row["role"] != "standalone" for row in records),
              "comparison_contract": {
                  "stage0_native_ir_byte_comparison": False,
                  "native_stage_ir": "exact Stage 1/2/3 stdout comparison for accepted source",
                  "native_stage_diagnostics": "exact Stage 1/2/3 stdout+stderr comparison for rejected source",
                  "native_stage_objects": "exact Stage 2/3 object comparison",
                  "nonstandalone_sources": "explicit owner reason plus successful owner-gate evidence from each generated stage",
                  "stage0": "accepted/rejected outcome oracle per target/profile and optimization; cross-language behavior is owned by declared gates",
              },
              "status_cells": cells, "stage_results": stage_results, "sources": records}
    report["stage0_probe_cache"] = {
        "hits": seed_cache_hits,
        "misses": seed_cache_misses,
        "max_concurrent_compilers": 2,
        "cache_scope": "source status, stdout, stderr, and accepted object bytes",
    }
    path = report_directory / "full-test-source-report.json"
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return {"path": str(path), "sha256": digest(path),
            "source_count": report["source_count"],
            "source_target_profile_count": report["source_target_profile_count"],
            "status_cell_count": len(cells),
            "excluded_by_role": report["excluded_by_role"]}

def run_release_corpus(data: dict, stage_compilers: list[Path],
                       report_directory: Path,
                       gate_filter: set[str] | None = None,
                       source_filter: set[str] | None = None) -> dict:
    if len(stage_compilers) != 3:
        raise RuntimeError("release corpus requires exactly Stage 1, Stage 2, and Stage 3 compilers")
    all_gates = declared_gates(data)
    full_run = gate_filter is None and source_filter is None
    selected_gates = all_gates if full_run else sorted(gate_filter or ())
    required_gates = all_gates if full_run else selected_gates
    for path in required_gates:
        if not (ROOT / path).is_file():
            raise RuntimeError(f"release corpus is incomplete; missing gate: {path}")
    if gate_filter is not None:
        unknown = gate_filter - set(all_gates)
        if unknown:
            raise RuntimeError("unknown focused gate(s): " + ", ".join(sorted(unknown)))
    if not selected_gates and source_filter is None:
        raise RuntimeError("focused corpus selection contains no gates or sources")
    report_directory.mkdir(parents=True, exist_ok=False)
    environment = cross_environment()
    seed_logs = report_directory / "seed-gates"
    seed_logs.mkdir()
    seed_results = []
    for path in sorted(SEED_ONLY & set(selected_gates)):
        mode = data["corpus_runner"]["per_stage_gate_argument_modes"].get(path, "seed-only")
        seed_results.append(run_gate(path, mode, None, ROOT,
                                     environment, seed_logs))
    stage_results = []
    gate_failures = []
    for index, compiler in enumerate(stage_compilers, 1):
        if not compiler.is_file():
            raise RuntimeError(f"missing Stage {index} compiler: {compiler}")
        stage_dir = report_directory / f"stage{index}"
        stage_dir.mkdir()
        logs = stage_dir / "logs"
        logs.mkdir()
        stage_gates = []
        objects = data.get("stage_objects", {}).get(str(index))
        object_paths = ({name: Path(path) for name, path in objects.items()}
                        if objects else None)
        for path in selected_gates:
            if path in SEED_ONLY:
                continue
            mode = data["corpus_runner"]["per_stage_gate_argument_modes"].get(path)
            if mode is None:
                raise RuntimeError(f"release gate has no explicit invocation mode: {path}")
            try:
                stage_gates.append(run_gate(path, mode, compiler, stage_dir,
                                            environment, logs, object_paths))
            except RuntimeError as error:
                failure = {"generation": index, "path": path, "mode": mode,
                           "status": 1, "error": str(error)}
                stage_gates.append(failure)
                gate_failures.append(failure)
        stage_results.append({"generation": index, "compiler": str(compiler),
                              "compiler_sha256": digest(compiler),
                              "gates": stage_gates})
    source_inventory = None
    if full_run or source_filter is not None:
        source_inventory = run_full_test_source_inventory(
            ROOT / data["corpus_runner"]["source_inventory"], stage_compilers,
            report_directory, source_filter, stage_results, set(all_gates))
    examples = None
    if full_run:
        examples = run_example_inventory(
            stage_compilers, report_directory / "example-corpus.json",
            report_directory / "example-logs",
            data["corpus_runner"]["example_inventory_runner"])
    return {"seed_gates": seed_results, "stage_gates": stage_results,
            "full_test_source_inventory": source_inventory,
            "example_inventory": examples,
            "gate_failures": gate_failures,
            "complete": full_run and not gate_failures,
            "focused_selection": {"gates": sorted(gate_filter) if gate_filter else None,
                                  "sources": sorted(source_filter) if source_filter else None}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--stage1", type=Path, required=True)
    parser.add_argument("--stage2", type=Path, required=True)
    parser.add_argument("--stage3", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--stage-report", type=Path,
                        help="Stage 1/2/3 build report containing all generation object paths")
    parser.add_argument("--only-gate", action="append", default=[])
    parser.add_argument("--only-source", action="append", default=[])
    args = parser.parse_args()
    try:
        data = json.loads(args.manifest.read_text(encoding="utf-8"))
        if args.stage_report:
            stage_report = json.loads(args.stage_report.read_text(encoding="utf-8"))
            data["stage_objects"] = stage_report.get("stage_object_paths", {})
        result = run_release_corpus(data,
            [args.stage1.resolve(), args.stage2.resolve(), args.stage3.resolve()],
            args.report_dir.resolve(),
            set(args.only_gate) if args.only_gate else None,
            set(args.only_source) if args.only_source else None)
        result["manifest_sha256"] = digest(args.manifest)
        args.report_dir.mkdir(parents=True, exist_ok=True)
        (args.report_dir / "corpus-report.json").write_text(
            json.dumps(result, indent=2) + "\n", encoding="utf-8")
        if result["gate_failures"]:
            print(f"release corpus: {len(result['gate_failures'])} stage gate failure(s); see {args.report_dir / 'corpus-report.json'}", file=sys.stderr)
            return 1
        label = "release corpus passed" if result["complete"] else "focused corpus selection passed (not a release pass)"
        print(f"{label} for Stage 1/2/3: {args.report_dir / 'corpus-report.json'}")
        return 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        print(f"release corpus: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
