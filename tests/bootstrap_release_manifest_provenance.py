#!/usr/bin/env python3
"""Exercise committed-manifest provenance in an isolated Git checkout."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


SOURCE_ROOT = Path(__file__).resolve().parent.parent


def run_git(root: Path, *arguments: str) -> str:
    result = subprocess.run(["git", "-C", str(root), *arguments], check=True,
                            capture_output=True, text=True)
    return result.stdout.strip()


def import_release_builder(root: Path):
    path = root / "tests" / "bootstrap_release.py"
    spec = importlib.util.spec_from_file_location("isolated_release_builder", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def copy_source_tree(destination: Path) -> None:
    ignored = shutil.ignore_patterns(".git", "build", "evidence", "__pycache__", "*.pyc")
    shutil.copytree(SOURCE_ROOT, destination, ignore=ignored)


def commit_all(root: Path, message: str) -> None:
    run_git(root, "add", "--all")
    subprocess.run(["git", "-C", str(root), "commit", "-m", message], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="psl-release-provenance-") as temporary:
        isolated_root = Path(temporary) / "repo"
        copy_source_tree(isolated_root)
        subprocess.run(["git", "-C", str(isolated_root), "init", "--quiet"], check=True)
        run_git(isolated_root, "config", "user.name", "PSL release test")
        run_git(isolated_root, "config", "user.email", "psl-release-test@example.invalid")
        commit_all(isolated_root, "isolated source snapshot")
        snapshot_base = run_git(isolated_root, "rev-parse", "HEAD")

        builder = import_release_builder(isolated_root)
        previous_base = os.environ.get("PSL_RELEASE_SNAPSHOT_BASE")
        os.environ["PSL_RELEASE_SNAPSHOT_BASE"] = snapshot_base
        try:
            builder.write_manifest()
        finally:
            if previous_base is None:
                os.environ.pop("PSL_RELEASE_SNAPSHOT_BASE", None)
            else:
                os.environ["PSL_RELEASE_SNAPSHOT_BASE"] = previous_base
        commit_all(isolated_root, "commit generated release manifest")

        committed_head = run_git(isolated_root, "rev-parse", "HEAD")
        assert committed_head != snapshot_base
        record = builder.check_manifest()
        assert record["seed"]["snapshot_base_revision"] == snapshot_base

        source = isolated_root / "bootstrap" / "native-core.lisp"
        original = source.read_bytes()
        try:
            source.write_bytes(original + b"\n;; isolated manifest mutation regression\n")
            try:
                builder.check_manifest()
            except RuntimeError as error:
                assert ("generation_source_digest_sha256" in str(error) or
                        "hashes/ownership are stale" in str(error))
            else:
                raise AssertionError("manifest accepted a changed owned compiler source")
        finally:
            source.write_bytes(original)

        builder.check_manifest()
        print("isolated release manifest accepts post-commit base, rejects changed owned source, and accepts restore")


if __name__ == "__main__":
    main()
