#!/usr/bin/env python3
"""Reuse only API-harness core/driver objects within one native regression.

Compiler generation and fixed-point builds never call this helper. Every entry
identifies the compiler executable, complete source inputs and compile recipe.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def source_inputs(root):
    files = [root / "pslcc"]
    for directory in ("bootstrap", "src", "runtime"):
        files.extend(path for path in (root / directory).rglob("*")
                     if path.is_file())
    return {str(path.relative_to(root)): digest(path)
            for path in sorted(files)}


def compiler_command(mode, compiler, level, target, profile, source, output):
    command = [str(compiler), f"-O{level}", f"--target={target}",
               f"--profile={profile}"]
    if mode == "seed":
        return command + ["-c", str(source), "-o", str(output)]
    command += [str(source), str(output)]
    host = os.environ.get("PSL_NATIVE_COMPILER_HOST_TARGET", "x86_64-linux-gnu")
    if host == "x86_64-linux-gnu":
        return command
    if host == "x86_64-windows-gnu":
        return ["wine"] + command
    for triple, runner, variable, default in (
            ("aarch64-linux-gnu", "qemu-aarch64", "AARCH64_SYSROOT", "/usr/aarch64-linux-gnu"),
            ("riscv64-linux-gnu", "qemu-riscv64", "RISCV64_SYSROOT", "/usr/riscv64-linux-gnu")):
        if host == triple:
            return [runner, "-L", os.environ.get(variable, default)] + command
    raise ValueError(f"unsupported compiler host target: {host}")


def checked_compile(command, output):
    status = subprocess.run(command).returncode
    if status:
        return status if status > 0 else 1
    if not output.is_file():
        raise ValueError("successful fixture compilation produced no object")
    return 0


def main():
    root_text, mode, compiler_text, level, target, profile, source_text, output_text = sys.argv[1:]
    root = Path(root_text).resolve()
    compiler = Path(compiler_text).resolve(strict=True)
    source = Path(source_text).resolve(strict=True)
    output = Path(output_text)
    if mode not in ("native", "seed") or level not in ("0", "1"):
        raise ValueError("invalid fixture compilation recipe")
    if source not in (root / "bootstrap/native-core.lisp", root / "bootstrap/host/driver.lisp"):
        raise ValueError("only API core/driver fixtures may be reused")
    command = compiler_command(mode, compiler, level, target, profile, source, output)
    cache_text = os.environ.get("PSL_BOOTSTRAP_FIXTURE_CACHE")
    if not cache_text:
        return checked_compile(command, output)
    inputs = source_inputs(root)
    recipe = {"command": command[:-1], "inputs": inputs,
              "compiler": digest(compiler), "host": os.environ.get("PSL_NATIVE_COMPILER_HOST_TARGET")}
    if mode == "seed":
        recipe["sbcl"] = digest(Path(shutil.which("sbcl") or "sbcl"))
    key = hashlib.sha256(json.dumps(recipe, sort_keys=True).encode()).hexdigest()
    cache = Path(cache_text)
    cache.mkdir(parents=True, exist_ok=True)
    entry = cache / key
    if entry.is_dir():
        metadata = json.loads((entry / "record.json").read_text())
        if metadata["recipe"] != recipe or metadata["object"] != digest(entry / "fixture.o"):
            raise ValueError("fixture cache identity or object hash mismatch")
        shutil.copyfile(entry / "fixture.o", output)
        return 0
    with tempfile.TemporaryDirectory(prefix="pending-", dir=cache) as temporary:
        pending = Path(temporary)
        object_path = pending / "fixture.o"
        command[-1] = str(object_path)
        status = checked_compile(command, object_path)
        if status:
            return status
        if source_inputs(root) != inputs or digest(compiler) != recipe["compiler"]:
            raise ValueError("compiler inputs changed during fixture compilation")
        record = {"recipe": recipe, "object": digest(object_path)}
        (pending / "record.json").write_text(json.dumps(record, sort_keys=True) + "\n")
        # Each full regression owns its private cache and invokes fixtures in order.
        pending.rename(entry)
        shutil.copyfile(entry / "fixture.o", output)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f"bootstrap fixture cache: {error}", file=sys.stderr)
        sys.exit(1)
