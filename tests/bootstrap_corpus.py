#!/usr/bin/env python3
"""Audit every example against Stage 0 and compare native compiler generations.

This is an x86-64 Linux hosted-profile development gate. Passing it does not
certify M8: the complete compiler manifest, other profile parity, and cross-host
gates are separate.
"""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COMMAND_TIMEOUT = 300
COMMAND_TIMEOUT = DEFAULT_COMMAND_TIMEOUT


def run(command):
    return subprocess.run(command, cwd=ROOT, capture_output=True,
                          timeout=COMMAND_TIMEOUT)


def require_success(result, description):
    if result.returncode:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"{description}: status {result.returncode}\n{detail}")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_manifest():
    path = ROOT / "tests/bootstrap_example_corpus.tsv"
    with path.open() as stream:
        rows = list(csv.reader((line for line in stream if not line.startswith("#")),
                               delimiter="\t"))
    sources = []
    for row in rows:
        if len(row) != 4 or row[1] not in ("accepted", "gap"):
            raise RuntimeError(f"invalid example manifest row: {row!r}")
        if row[3] not in ("harness", "main", "object", "closure-harness"):
            raise RuntimeError(f"invalid execution mode: {row!r}")
        sources.append(row[0])
    actual = {str(path.relative_to(ROOT)) for path in (ROOT / "examples").rglob("*.lisp")}
    if len(sources) != len(set(sources)) or set(sources) != actual:
        missing = sorted(actual - set(sources))
        extra = sorted(set(sources) - actual)
        raise RuntimeError(f"example manifest coverage mismatch: missing={missing}, extra={extra}")
    return rows


def compile_command(compiler, source, output, level, stage0=False):
    command = [str(compiler), f"-O{level}", "--target=x86_64-linux-gnu",
               "--profile=hosted"]
    if stage0:
        command += ["-c", str(source), "-o", str(output)]
    else:
        command += [str(source), str(output)]
    return command


def compile_source(compiler, source, output, level, stage0=False):
    result = run(compile_command(compiler, source, output, level, stage0))
    if output.exists() != (result.returncode == 0):
        raise RuntimeError(f"invalid artifact outcome for {source}: status {result.returncode}")
    return result


def check_object(path):
    result = run(["readelf", "-h", str(path)])
    require_success(result, f"inspect {path.name}")
    if b"REL (Relocatable file)" not in result.stdout or b"Advanced Micro Devices X86-64" not in result.stdout:
        raise RuntimeError(f"unexpected example object header: {path.name}")


def execute_object(source, mode, object_path, executable, cc):
    if mode == "object":
        return None  # UART memory needs the separate RISC-V freestanding runner.
    command = cc + ["-std=c11", "-Wall", "-Wextra", "-Werror", "-pthread"]
    if mode == "harness":
        command.append(str(source.with_name(f"harness_{source.stem}.c")))
    elif mode == "closure-harness":
        command.append(str(ROOT / "tests/harness_closure_module.c"))
    if source.parent.name == "hosted":
        command += [str(path) for path in sorted((ROOT / "runtime").glob("*.c"))
                    if path.name != "platform_windows.c"]
    command += [str(object_path), "-o", str(executable)]
    require_success(run(command), f"link {source.relative_to(ROOT)}")
    result = run([str(executable)])
    require_success(result, f"execute {source.relative_to(ROOT)}")
    return result.stdout, result.stderr


def compare_generations(rows, compilers, stage0, work_dir, cc):
    evidence = []
    for index, (relative, minimum, capability, mode) in enumerate(rows):
        source = ROOT / relative
        observations = []
        for level in (0, 1):
            baseline = work_dir / f"seed-{index}-{level}.o"
            require_success(compile_source(stage0, source, baseline, level, True),
                            f"Stage 0 rejected example {relative}")
            baseline_behavior = None
            previous = None
            for generation, compiler in enumerate(compilers):
                output = work_dir / f"native-{index}-{level}-{generation}.o"
                result = compile_source(compiler, source, output, level)
                status = "accepted" if result.returncode == 0 else "gap"
                if result.returncode not in (0, 1):
                    raise RuntimeError(f"native compiler failed operationally on {relative}: {result.returncode}")
                if minimum == "accepted" and status != "accepted":
                    raise RuntimeError(f"native example regression: {relative}\n{result.stderr.decode()}")
                if status == "accepted":
                    check_object(output)
                    repeat = work_dir / "repeat.o"
                    repeat.unlink(missing_ok=True)
                    repeated = compile_source(compiler, source, repeat, level)
                    require_success(repeated, f"native repeat failed: {relative}")
                    if output.read_bytes() != repeat.read_bytes():
                        raise RuntimeError(f"nondeterministic native example: {relative}")
                    if (result.stdout, result.stderr) != (repeated.stdout, repeated.stderr):
                        raise RuntimeError(f"nondeterministic native diagnostic: {relative}")
                    if baseline_behavior is None:
                        baseline_behavior = execute_object(source, mode, baseline,
                                                           work_dir / "seed-run", cc)
                    behavior = execute_object(source, mode, output, work_dir / "native-run", cc)
                    if behavior != baseline_behavior:
                        raise RuntimeError(f"Stage 0/native execution differs: {relative}")
                current = (result.returncode, result.stdout, result.stderr,
                           output.read_bytes() if output.exists() else None)
                if previous is not None and current != previous:
                    raise RuntimeError(f"native generation behavior/artifact differs: {relative} -O{level}")
                previous = current
                observations.append({"level": level, "generation": generation,
                                     "status": status, "exit_status": result.returncode,
                                     "object_sha256": digest(output) if output.exists() else None,
                                     "diagnostic": result.stderr.decode("utf-8", errors="replace").strip()})
        statuses = {entry["status"] for entry in observations}
        if len(statuses) != 1:
            raise RuntimeError(f"native optimization levels disagree on acceptance: {relative}")
        status = statuses.pop()
        print(f"{status}\t{relative}\t{capability if status == 'gap' else '-'}", flush=True)
        evidence.append({"source": relative, "status": status,
                         "remaining_capability": capability if status == "gap" else None,
                         "observations": observations})
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", action="append", type=Path,
                        help="native compiler path; repeat to compare generations in order")
    parser.add_argument("--stage0", type=Path, default=ROOT / "pslcc")
    parser.add_argument("--command-timeout", type=int, default=DEFAULT_COMMAND_TIMEOUT,
                        help="timeout in seconds for each compiler, linker, and inspection command")
    parser.add_argument("--report", type=Path, help="write seed, binary hashes and per-example JSON evidence")
    parser.add_argument("--require-parity", action="store_true",
                        help="fail when any Stage 0 example is still a native gap; this is not the full M8 gate")
    args = parser.parse_args()
    if args.command_timeout <= 0:
        parser.error("--command-timeout must be positive")
    global COMMAND_TIMEOUT
    COMMAND_TIMEOUT = args.command_timeout
    compilers = [path.resolve() for path in (args.native or [Path(os.environ.get(
        "PSL_NATIVE_COMPILER", ROOT / "build/pslcc-native"))])]
    stage0 = args.stage0.resolve()
    try:
        rows = load_manifest()
        with tempfile.TemporaryDirectory(prefix="psl-example-corpus-") as directory:
            evidence = compare_generations(rows, compilers, stage0, Path(directory),
                                           shlex.split(os.environ.get("CC", "cc")))
        gaps = sum(row["status"] == "gap" for row in evidence)
        sbcl = Path(shutil.which("sbcl") or "sbcl")
        report = {"scope": "repository example inventory; x86-64 Linux; hosted profile; object compilation; O0/O1",
                  "m8_complete": False,
                  "full_source_object_interop_corpus_and_stage1_3": "open",
                  "command_timeout_seconds": COMMAND_TIMEOUT,
                  "seed_version": run([str(sbcl), "--version"]).stdout.decode().strip(),
                  "seed_sha256": digest(sbcl), "stage0_launcher_sha256": digest(stage0),
                  "example_manifest_sha256": digest(ROOT / "tests/bootstrap_example_corpus.tsv"),
                  "stage0_source_sha256": {str(path.relative_to(ROOT)): digest(path)
                                           for path in sorted((ROOT / "src").rglob("*.lisp"))},
                  "native_compilers": [{"path": str(path), "sha256": digest(path)} for path in compilers],
                  "accepted": len(evidence) - gaps, "gaps": gaps, "examples": evidence}
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(f"PSL example corpus: {len(evidence) - gaps}/{len(evidence)} native accepted; {gaps} gaps")
        print("This example-only x86-64 hosted gate leaves the full source/object/interop corpus and Stage 1–3 open.")
        return 1 if args.require_parity and gaps else 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"PSL example corpus failure: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
