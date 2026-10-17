#!/usr/bin/env python3
"""Auditable source manifest and three-stage native compiler builder.

This tool deliberately separates generation builds from the release corpus.
Generation objects are always compiled directly by the preceding compiler; the
fixture cache is never imported or consulted here.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "tests" / "bootstrap_compiler_manifest.json"
SOURCE_CORPUS = ROOT / "tests" / "bootstrap_release_sources.json"
SCHEMA = 2
# The sibling was copied from this repository snapshot. Later edits are
# identified by the declared per-file hashes, rather than implied clean-commit
# contents.
UNIT_ROOTS = [
    ("core", "bootstrap/native-core.lisp"),
    ("host", "bootstrap/host/driver.lisp"),
    ("source", "bootstrap/host/source_unit.lisp"),
    ("input", "bootstrap/host/source_io.lisp"),
    ("path-posix", "bootstrap/host/source_path_posix.lisp"),
    ("compiler", "bootstrap/host/compiler.lisp"),
    ("output", "bootstrap/host/output.lisp"),
    ("diagnostics", "bootstrap/host/diagnostics.lisp"),
]
PATH_ALTERNATES = {
    "bootstrap/host/source_path_posix.lisp": "POSIX canonical path adapter; selected for the Linux release host.",
    "bootstrap/host/source_path_windows.lisp": "Windows canonical path adapter; alternate host variant compiled only on Windows.",
}
NON_GENERATION_NATIVE_SOURCES = {
    "bootstrap/win64_module.lisp":
        "Standalone Win64 encoder fixture aggregator; its implementation files are already compiled through native-core.lisp, so linking this test unit would duplicate definitions.",
}
HOST_C_ADAPTERS = [
    "bootstrap/driver.c",
    "bootstrap/host/platform_stdio.c",
    "bootstrap/host/platform_toolchain.c",
]
LINUX_RUNTIME_SOURCES = [
    "runtime/value.c",
    "runtime/cons.c",
    "runtime/string.c",
    "runtime/symbol.c",
    "runtime/package.c",
    "runtime/closure.c",
    "runtime/values.c",
    "runtime/vector.c",
    "runtime/gc.c",
    "runtime/startup.c",
    "runtime/platform_linux.c",
]
HOST_TARGETS = [
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "riscv64-linux-gnu",
    "x86_64-windows-gnu",
]
SOURCE_STATUS_CELLS = [
    *[(target, "hosted") for target in HOST_TARGETS],
    *[(target, "freestanding") for target in HOST_TARGETS],
    ("x86_64-none-elf", "hosted"),
    ("x86_64-none-elf", "freestanding"),
    ("riscv64-none-elf", "hosted"),
    ("riscv64-none-elf", "freestanding"),
]
HOST_TOOLS = ["sbcl", "cc", "nm", "readelf", "ar", "ld", "objdump", "python3"]
CROSS_TOOLS = ["aarch64-linux-gnu-gcc", "riscv64-linux-gnu-gcc",
               "riscv64-unknown-elf-ld", "aarch64-linux-gnu-ar",
               "aarch64-linux-gnu-nm", "aarch64-linux-gnu-readelf",
               "aarch64-linux-gnu-objdump", "aarch64-linux-gnu-objcopy",
               "aarch64-linux-gnu-ld", "riscv64-linux-gnu-ar",
               "riscv64-linux-gnu-nm", "riscv64-linux-gnu-readelf",
               "riscv64-linux-gnu-objdump", "riscv64-linux-gnu-objcopy",
               "riscv64-linux-gnu-ld", "x86_64-w64-mingw32-gcc",
               "x86_64-w64-mingw32-ar", "x86_64-w64-mingw32-nm",
               "x86_64-w64-mingw32-objdump", "x86_64-w64-mingw32-ld",
               "riscv64-unknown-elf-gcc", "riscv64-unknown-elf-nm",
               "riscv64-unknown-elf-ar", "riscv64-unknown-elf-objdump",
               "riscv64-unknown-elf-readelf",
               "qemu-aarch64", "qemu-riscv64", "qemu-system-riscv64", "wine"]
REQUIRED_SYSROOTS = ["usr/aarch64-linux-gnu", "usr/riscv64-linux-gnu"]
SOURCE_PROBE_WORKERS = 2
SOURCE_PROBE_OPTIMIZATION = "-O0"
SEED_ONLY = {"tests/smoke.sh", "tests/bootstrap_self_core.sh",
             "tests/bootstrap_macro_constant_oracle.sh", "tests/managed_roots.sh"}
RELEASE_GATE_GROUPS = {
    "accepted-rejected-source-object": [
        "tests/bootstrap_native_compiler.sh",
        "tests/bootstrap_binary.sh",
        "tests/bootstrap_modules.sh",
        "tests/bootstrap_c_output.sh",
        "tests/bootstrap_static_data.sh",
        "tests/bootstrap_native_elf.sh",
        "tests/bootstrap_lexical_validation.sh",
        "tests/bootstrap_source_identities.sh",
        "tests/bootstrap_source_loader_identities.sh",
        "tests/bootstrap_void_conditions.sh",
        "tests/bootstrap_native_cli.sh",
        "tests/bootstrap_native_cli_link.sh",
        "tests/bootstrap_short_source_capacity.sh",
        "tests/bootstrap_cli_diagnostics.sh",
    ],
    "verified-ir-and-diagnostics": [
        "tests/bootstrap_ir_dump.sh",
        "tests/bootstrap_native_cli_ir_dump.sh",
        "tests/bootstrap_native_cli.sh",
        "tests/managed_roots.sh",
    ],
    "managed-runtime-and-interop": [
        "tests/bootstrap_managed_values.sh",
        "tests/bootstrap_managed_roots.sh",
        "tests/bootstrap_byte_strings.sh",
        "tests/bootstrap_string_literals.sh",
        "tests/bootstrap_runtime_symbols.sh",
        "tests/bootstrap_multiple_values.sh",
        "tests/bootstrap_native_closures.sh",
        "tests/bootstrap_native_vectors.sh",
        "tests/bootstrap_word_aggregates.sh",
        "tests/bootstrap_integer_aggregates.sh",
        "tests/bootstrap_float_aggregates.sh",
        "tests/bootstrap_function_addresses.sh",
        "tests/bootstrap_cl_user.sh",
        "tests/bootstrap_source_loader_allocations.sh",
    ],
    "environment-and-macros": [
        "tests/bootstrap_reader_identity.sh",
        "tests/bootstrap_environment.sh",
        "tests/bootstrap_package_operations.sh",
        "tests/bootstrap_package_forms.sh",
        "tests/bootstrap_package_form_edges.sh",
        "tests/bootstrap_macros.sh",
        "tests/bootstrap_macro_destructuring.sh",
        "tests/bootstrap_macro_constant_oracle.sh",
        "tests/bootstrap_cli_macro_growth.sh",
        "tests/bootstrap_compile_time.sh",
    ],
    "freestanding-and-none-targets": [
        "tests/bootstrap_native_cli_none_targets.sh",
        "tests/bootstrap_native_cli_freestanding_link.sh",
        "tests/bootstrap_native_cli_large_startup.sh",
    ],
    "repository-smoke-and-self-host": [
        "tests/smoke.sh",
        "tests/bootstrap_self_core.sh",
    ],
    "cross-target": [
        "tests/bootstrap_native_aarch64.sh",
        "tests/bootstrap_native_riscv64.sh",
        "tests/bootstrap_native_windows.sh",
        "tests/aarch64.sh",
        "tests/riscv64.sh",
        "tests/bootstrap_win64_frame.sh",
        "tests/windows.sh",
        "tests/bootstrap_elf64.sh",
    ],
    "standalone-bootstrap-units": [
        "tests/bootstrap_component.sh",
        "tests/bootstrap_parser.sh",
        "tests/bootstrap_reader.sh",
        "tests/bootstrap_symbols.sh",
        "tests/bootstrap_managed_vectors.sh",
    ],
}
RELEASE_TEST_AREAS = [
    {
        "name": "source-loader",
        "prefixes": ["tests/bootstrap_source_loader_", "tests/harness_source_loader_",
                     "tests/source_loader_identities/"],
        "gates": ["tests/bootstrap_source_loader_identities.sh",
                  "tests/bootstrap_source_loader_allocations.sh"],
        "reason": "Source identity/alias behavior is checked by hosted target gates; the allocation receiver checks each stage's loader tables and cleanup.",
    },
    {
        "name": "managed-runtime",
        "prefixes": ["tests/bootstrap_managed_", "tests/harness_bootstrap_managed_",
                     "tests/managed_roots", "tests/bootstrap_byte_strings",
                     "tests/harness_bootstrap_byte_strings", "tests/bootstrap_string_literals",
                     "tests/harness_bootstrap_string_literals", "tests/bootstrap_runtime_symbols",
                     "tests/harness_bootstrap_runtime_symbols", "tests/bootstrap_multiple_values",
                     "tests/harness_bootstrap_multiple_values", "tests/bootstrap_native_closures",
                     "tests/harness_bootstrap_native_closures", "tests/bootstrap_native_vectors",
                     "tests/harness_bootstrap_native_vectors", "tests/bootstrap_word_aggregates",
                     "tests/harness_bootstrap_word_aggregates", "tests/bootstrap_integer_aggregates",
                     "tests/harness_bootstrap_integer_aggregates", "tests/bootstrap_float_aggregates",
                     "tests/harness_bootstrap_float_aggregates"],
        "gates": ["tests/bootstrap_managed_values.sh", "tests/bootstrap_managed_roots.sh",
                  "tests/bootstrap_byte_strings.sh", "tests/bootstrap_string_literals.sh",
                  "tests/bootstrap_runtime_symbols.sh", "tests/bootstrap_multiple_values.sh",
                  "tests/bootstrap_native_closures.sh", "tests/bootstrap_native_vectors.sh",
                  "tests/bootstrap_word_aggregates.sh", "tests/bootstrap_integer_aggregates.sh",
                  "tests/bootstrap_float_aggregates.sh"],
        "reason": "These inputs exercise hosted VALUE lifetime, precise roots, strings, symbols, vectors, closures and aggregate runtime dependencies on each generated compiler.",
    },
    {
        "name": "native-macros",
        "prefixes": ["tests/bootstrap_macro", "tests/bootstrap_macros.sh",
                     "tests/harness_bootstrap_macro", "tests/harness_seed_macro_patterns",
                     "tests/seed_macro_patterns.lisp"],
        "gates": ["tests/bootstrap_macros.sh", "tests/bootstrap_macro_destructuring.sh",
                  "tests/bootstrap_macro_constant_oracle.sh"],
        "reason": "The macro gate runs source fixtures, independent constant/NIL-key oracles, C O0/O2 observations, API O0/O1 receivers, error rollback and generated-prefix capacity checks.",
    },
    {
        "name": "short-source-capacity",
        "prefixes": ["tests/bootstrap_short_source_"],
        "gates": ["tests/bootstrap_short_source_capacity.sh"],
        "reason": "Each generation compares short hosted source acceptance with Stage 0, deterministic objects, C observations, and failed-output preservation on all four hosted targets.",
    },
    {
        "name": "void-conditions",
        "prefixes": ["tests/bootstrap_void_conditions", "tests/harness_bootstrap_void_"],
        "gates": ["tests/bootstrap_void_conditions.sh"],
        "reason": "The hosted target matrix compares seed/native rejection and verifies output preservation for VOID conditions.",
    },
]


def release_test_ownership() -> list[dict]:
    """Bind special source/API fixtures to the stage gates that observe them."""
    files = [path.relative_to(ROOT).as_posix() for path in tracked_inputs()
             if path.relative_to(ROOT).as_posix().startswith("tests/")]
    ownership = []
    assigned: set[str] = set()
    gate_set = {path for paths in RELEASE_GATE_GROUPS.values() for path in paths}
    for area in RELEASE_TEST_AREAS:
        matches = sorted(path for path in files
                         if any(path.startswith(prefix) for prefix in area["prefixes"]))
        if not matches:
            raise RuntimeError(f"release fixture area has no source inputs: {area['name']}")
        undeclared = sorted(set(area["gates"]) - gate_set)
        missing = sorted(gate for gate in area["gates"] if not (ROOT / gate).is_file())
        if undeclared or missing:
            raise RuntimeError(f"release fixture area has invalid gates: {area['name']}; "
                               f"undeclared={undeclared}, missing={missing}")
        for path in matches:
            assigned.add(path)
            ownership.append({"path": path, "area": area["name"],
                              "owner_gates": area["gates"], "reason": area["reason"]})
    required_prefixes = [prefix for area in RELEASE_TEST_AREAS for prefix in area["prefixes"]]
    required = {path for path in files
                if any(path.startswith(prefix) for prefix in required_prefixes)}
    if assigned != required:
        raise RuntimeError("special release fixture ownership mismatch: "
                           f"unowned={sorted(required - assigned)}, "
                           f"unexpected={sorted(assigned - required)}")
    return ownership
STAGE_CORPUS_GATE_ARGS = {
    "tests/bootstrap_cli_diagnostics.sh": "compiler-target",
    "tests/bootstrap_ir_dump.sh": "compiler-targets",
    "tests/bootstrap_native_cli_ir_dump.sh": "compiler-targets",
    "tests/bootstrap_parser.sh": "compiler-target",
    "tests/bootstrap_reader.sh": "compiler-target",
    "tests/bootstrap_component.sh": "compiler-target",
    "tests/bootstrap_managed_vectors.sh": "compiler-target-env",
        "tests/bootstrap_elf64.sh": "compiler-elf-targets",
    "tests/bootstrap_win64_frame.sh": "compiler-win64",
    "tests/windows.sh": "compiler-win64",
    "tests/bootstrap_symbols.sh": "compiler-env",
    "tests/aarch64.sh": "compiler",
    "tests/riscv64.sh": "compiler",
    "tests/bootstrap_native_compiler.sh": "stage-native-api",
    "tests/bootstrap_self_core.sh": "seed-only",
    "tests/smoke.sh": "seed-only",
    "tests/bootstrap_macro_constant_oracle.sh": "seed-only",
    "tests/managed_roots.sh": "seed-only",
    "tests/bootstrap_binary.sh": "target-native-env",
    "tests/bootstrap_modules.sh": "compiler-env",
    "tests/bootstrap_c_output.sh": "compiler-target",
    "tests/bootstrap_native_aarch64.sh": "compiler-env",
    "tests/bootstrap_native_riscv64.sh": "compiler-env",
    "tests/bootstrap_native_windows.sh": "compiler-env",
    "tests/bootstrap_native_elf.sh": "target-env",
    "tests/bootstrap_static_data.sh": "target-native-env",
    "tests/bootstrap_cli_macro_growth.sh": "compiler-seed-target",
    "tests/bootstrap_compile_time.sh": "compiler-target",
    "tests/bootstrap_lexical_validation.sh": "compiler-target",
    "tests/bootstrap_source_identities.sh": "compiler-target",
    "tests/bootstrap_source_loader_identities.sh": "compiler-target",
    "tests/bootstrap_native_cli.sh": "compiler-target",
    "tests/bootstrap_native_cli_link.sh": "compiler-target",
    "tests/bootstrap_short_source_capacity.sh": "compiler-target",
}
for _targeted_gate in (
        "tests/bootstrap_managed_values.sh", "tests/bootstrap_managed_roots.sh",
        "tests/bootstrap_byte_strings.sh", "tests/bootstrap_string_literals.sh",
        "tests/bootstrap_runtime_symbols.sh", "tests/bootstrap_multiple_values.sh",
        "tests/bootstrap_native_closures.sh", "tests/bootstrap_native_vectors.sh",
        "tests/bootstrap_word_aggregates.sh", "tests/bootstrap_integer_aggregates.sh",
        "tests/bootstrap_float_aggregates.sh", "tests/bootstrap_function_addresses.sh",
        "tests/bootstrap_environment.sh", "tests/bootstrap_package_operations.sh",
        "tests/bootstrap_package_forms.sh", "tests/bootstrap_package_form_edges.sh",
        "tests/bootstrap_macros.sh", "tests/bootstrap_macro_destructuring.sh",
        "tests/bootstrap_reader_identity.sh",
        "tests/bootstrap_package_forms.sh", "tests/bootstrap_package_operations.sh",
        "tests/bootstrap_cl_user.sh", "tests/bootstrap_native_cli_none_targets.sh",
        "tests/bootstrap_native_cli_freestanding_link.sh",
        "tests/bootstrap_native_cli_large_startup.sh"):
    STAGE_CORPUS_GATE_ARGS[_targeted_gate] = "compiler-target"
STAGE_CORPUS_GATE_ARGS["tests/bootstrap_source_loader_allocations.sh"] = "stage-source-loader-allocations"
STAGE_CORPUS_GATE_ARGS["tests/bootstrap_void_conditions.sh"] = "compiler-target"

# Every tests/*.sh entry point is either a release gate above or a declared
# shared helper. Helpers are included transitively by their owning gate; keeping
# this inventory explicit prevents a new standalone test runner from silently
# falling outside the release.
TEST_SCRIPT_HELPERS = {
    "tests/bootstrap_target.sh": {
        "called_by": ["tests/bootstrap_binary.sh", "tests/bootstrap_component.sh", "tests/bootstrap_parser.sh",
                      "tests/bootstrap_reader.sh"],
        "reason": "Selects the target C compiler, suffix, and emulator for module receivers.",
    },
    "tests/bootstrap_test_runner.sh": {
        "called_by": ["tests/bootstrap_byte_strings.sh", "tests/bootstrap_c_aliases.sh",
                      "tests/bootstrap_c_output.sh", "tests/bootstrap_cl_user.sh",
                      "tests/bootstrap_cli_diagnostics.sh", "tests/bootstrap_cli_macro_growth.sh",
                      "tests/bootstrap_compile_time.sh", "tests/bootstrap_data_only.sh",
                      "tests/bootstrap_environment.sh", "tests/bootstrap_float_abi.sh",
                      "tests/bootstrap_float_aggregates.sh", "tests/bootstrap_float_memory.sh",
                      "tests/bootstrap_function_addresses.sh", "tests/bootstrap_integer_aggregates.sh",
                      "tests/bootstrap_ir_dump.sh", "tests/bootstrap_lexical_validation.sh",
                      "tests/bootstrap_macro_destructuring.sh", "tests/bootstrap_macros.sh",
                      "tests/bootstrap_managed_roots.sh", "tests/bootstrap_managed_value_handles.sh",
                      "tests/bootstrap_managed_values.sh", "tests/bootstrap_managed_vectors.sh",
                      "tests/bootstrap_multiple_values.sh", "tests/bootstrap_native_cli.sh",
                      "tests/bootstrap_native_cli_ir_dump.sh", "tests/bootstrap_native_cli_link.sh",
                      "tests/bootstrap_native_cli_none_targets.sh", "tests/bootstrap_native_closures.sh",
                      "tests/bootstrap_native_vectors.sh", "tests/bootstrap_package_form_edges.sh",
                      "tests/bootstrap_package_forms.sh", "tests/bootstrap_package_operations.sh",
                      "tests/bootstrap_packed.sh", "tests/bootstrap_pointer_qualifiers.sh",
                      "tests/bootstrap_reader_identity.sh", "tests/bootstrap_runtime_symbols.sh",
                      "tests/bootstrap_short_source_capacity.sh", "tests/bootstrap_source_identities.sh",
                      "tests/bootstrap_source_loader_identities.sh", "tests/bootstrap_string_literals.sh",
                      "tests/bootstrap_void_conditions.sh", "tests/bootstrap_word_aggregates.sh",
                      "tests/managed_roots.sh", "tests/runtime_precise.sh",
                      "tests/runtime_precise_closure_link.sh", "tests/runtime_precise_closures.sh",
                      "tests/source_identities.sh"],
        "reason": "Shared native compiler host dispatch, target C linking, runtime linkage, and emulator helpers.",
    },
    "tests/bootstrap_c_aliases.sh": {
        "called_by": ["tests/bootstrap_native_compiler.sh", "tests/bootstrap_native_elf.sh",
                      "tests/bootstrap_native_windows.sh"],
        "reason": "Shared C alias cases are run from each native compiler's host/ELF/Windows integration gate.",
    },
    "tests/bootstrap_data_only.sh": {
        "called_by": ["tests/bootstrap_native_compiler.sh", "tests/bootstrap_native_elf.sh",
                      "tests/bootstrap_native_windows.sh"],
        "reason": "Data-only ABI checks are invoked by the host, ELF, and Windows compiler integration gates.",
    },
    "tests/bootstrap_float_abi.sh": {
        "called_by": ["tests/bootstrap_native_compiler.sh", "tests/bootstrap_native_elf.sh",
                      "tests/bootstrap_native_windows.sh"],
        "reason": "Float calling-convention checks run in the host native compiler gate.",
    },
    "tests/bootstrap_float_memory.sh": {
        "called_by": ["tests/bootstrap_native_compiler.sh", "tests/bootstrap_native_elf.sh",
                      "tests/bootstrap_native_windows.sh"],
        "reason": "Float memory-layout checks run in the host native compiler gate.",
    },
    "tests/bootstrap_packed.sh": {
        "called_by": ["tests/bootstrap_native_compiler.sh", "tests/bootstrap_native_elf.sh",
                      "tests/bootstrap_native_windows.sh"],
        "reason": "Packed layout checks run in host, ELF, and Windows native compiler gates.",
    },
    "tests/bootstrap_pointer_qualifiers.sh": {
        "called_by": ["tests/bootstrap_native_compiler.sh", "tests/bootstrap_native_elf.sh",
                      "tests/bootstrap_native_windows.sh"],
        "reason": "Pointer qualifier ABI cases run in host, ELF, and Windows native compiler gates.",
    },
    "tests/bootstrap_managed_value_handles.sh": {
        "called_by": ["tests/runtime.sh"],
        "reason": "Runtime API receiver is a subtest of the runtime aggregate, invoked by smoke.sh.",
    },
    "tests/layout_queries.sh": {
        "called_by": ["tests/aarch64.sh", "tests/riscv64.sh", "tests/smoke.sh",
                      "tests/windows.sh"],
        "reason": "Target data-layout C queries are included at the end of the corresponding architecture suite.",
    },
    "tests/negative.sh": {
        "called_by": ["tests/smoke.sh"],
        "reason": "Invalid source and output-preservation checks are run by the seed smoke and self-core gates.",
    },
    "tests/runtime.sh": {
        "called_by": ["tests/smoke.sh"],
        "reason": "Aggregates runtime API suites invoked by the Stage 0 smoke gate.",
    },
    "tests/runtime_precise.sh": {
        "called_by": ["tests/runtime.sh"],
        "reason": "Precise GC runtime checks are a child of the runtime aggregate.",
    },
    "tests/runtime_precise_closure_link.sh": {
        "called_by": ["tests/runtime.sh"],
        "reason": "Closure runtime link checks are a child of the runtime aggregate.",
    },
    "tests/runtime_precise_closures.sh": {
        "called_by": ["tests/runtime.sh"],
        "reason": "Precise closure collection checks are a child of the runtime aggregate.",
    },
    "tests/source_identities.sh": {
        "called_by": ["tests/smoke.sh"],
        "reason": "Stage 0 source/package identity checks are also mirrored by the per-stage source identity gate.",
    },
    "tests/windows_frame.sh": {
        "called_by": ["tests/windows.sh"],
        "reason": "Runs the 400-call large-frame/unwind receiver against the Stage 0 baseline and the compiler supplied by the current Windows gate; the separate Win64 frame gate checks its native-core encoder receiver.",
    },
}

SEED_ONLY_GATE_REASONS = {
    "tests/smoke.sh": "Stage 0's end-to-end seed gate runs the public smoke, invalid-input, runtime, and target-layout checks.",
    "tests/bootstrap_self_core.sh": "This gate validates the Stage 0 bootstrap/self-core contract; generated stages are checked by the eight-unit fixed-point build and stage-native API gate.",
    "tests/bootstrap_macro_constant_oracle.sh": "The independent SBCL oracle checks host macro constant identity; bootstrap_macros.sh invokes it again before every generated-stage macro matrix.",
    "tests/managed_roots.sh": "This is the seed-side Lisp verifier for managed roots; bootstrap_managed_roots.sh owns each generated stage's native C receiver and execution.",
    "tests/bootstrap_elf64.sh": "Runs the Stage 0 object as the byte-exact ELF writer reference, while compiling and executing the writer module with each generated compiler on x86-64, AArch64, and RISC-V.",
    "tests/aarch64.sh": "Runs the broad AArch64 ABI, hosted, library, and layout suite with each generated compiler, cross-linker, and QEMU; bootstrap_native_aarch64.sh retains its separate Stage 0-specific check.",
    "tests/riscv64.sh": "Runs the broad RISC-V ABI, hosted, freestanding, library, and layout suite with each generated compiler, cross-linker, and QEMU; bootstrap_native_riscv64.sh retains its separate Stage 0-specific check.",
}

RELEASE_GATE_REASONS = {
    "tests/bootstrap_component.sh": "Compiles the arena and atom bootstrap modules with each generated compiler, links their public C harnesses, and checks deterministic objects across all hosted targets.",
    "tests/bootstrap_parser.sh": "Compiles the parser module with each generated compiler, runs its public C parser harness over repository examples, and checks deterministic objects across all hosted targets.",
    "tests/bootstrap_reader.sh": "Compiles the reader module with each generated compiler, runs its public C reader harness over repository examples, and checks deterministic objects across all hosted targets.",
    "tests/bootstrap_symbols.sh": "Runs the standalone public symbol identity C receiver, deterministic recompilation, and invalid-name rejection cases against every generated compiler.",
    "tests/bootstrap_managed_vectors.sh": "Runs managed vector runtime bounds/allocation checks and the Lisp-to-C vector receiver against each generated compiler on all hosted targets.",
    "tests/bootstrap_elf64.sh": "Runs the public ELF64 writer harness from each generated compiler on x86-64, AArch64, and RISC-V, comparing writer output and executing target answer objects.",
    "tests/bootstrap_win64_frame.sh": "Keeps Stage 0 large-frame checks and repeats the Win64 encoder and native-core partial-unwind receivers with each generated compiler under Wine.",
    "tests/windows.sh": "Runs the complete Windows native, ABI, hosted runtime, FFI, DLL/static/shared linking, import-data/function, unwind, and determinism assertions with each generated compiler under Wine.",
}


def release_shell_inventory() -> list[dict]:
    """Require each shell entry point to be a gate or an owned helper."""
    gates = {path for paths in RELEASE_GATE_GROUPS.values() for path in paths}
    scripts = {path.relative_to(ROOT).as_posix()
               for path in (ROOT / "tests").rglob("*.sh")}
    classified = gates | set(TEST_SCRIPT_HELPERS)
    if scripts != classified:
        raise RuntimeError("release shell-entry inventory mismatch: "
                           f"ungrouped={sorted(scripts - classified)}, "
                           f"stale={sorted(classified - scripts)}")
    rows = []
    for path in sorted(gates):
        mode = STAGE_CORPUS_GATE_ARGS.get(path, "seed-only")
        reason = (SEED_ONLY_GATE_REASONS.get(path) if path in SEED_ONLY
                  else RELEASE_GATE_REASONS.get(path,
                      f"Runs under the declared {mode} release mode."))
        if not reason:
            raise RuntimeError(f"release gate has no invocation-mode justification: {path}")
        rows.append({"path": path, "role": "release-gate", "mode": mode,
                     "groups": sorted(group for group, paths in RELEASE_GATE_GROUPS.items()
                                      if path in paths),
                     "reason": reason})
    for path, details in sorted(TEST_SCRIPT_HELPERS.items()):
        rows.append({"path": path, "role": "shared-helper",
                     "called_by": details["called_by"], "reason": details["reason"]})
    for row in rows:
        if row["role"] == "shared-helper":
            missing = sorted(set(row["called_by"]) - scripts)
            if missing:
                raise RuntimeError(f"shell helper has unknown caller(s): {row['path']}: {missing}")
    return rows
SOURCE_OWNERSHIP_DOCUMENT = "docs/m8-source-contract-gaps.md"
SOURCE_ORACLE_GATES = {
    "tests/ir_verifier.lisp": ["tests/smoke.sh", "tests/bootstrap_native_cli_ir_dump.sh",
                               "tests/bootstrap_native_compiler.sh"],
    "tests/managed_roots_verifier.lisp": ["tests/managed_roots.sh", "tests/bootstrap_managed_roots.sh"],
    "tests/reference_bootstrap_binary.lisp": ["tests/bootstrap_binary.sh"],
    "tests/library.lisp": ["tests/smoke.sh", "tests/bootstrap_native_compiler.sh"],
    "tests/bootstrap_environment_catalogue.lisp": ["tests/bootstrap_environment.sh"],
    "tests/bootstrap_environment_oracle.lisp": ["tests/bootstrap_environment.sh"],
    "tests/bootstrap_macro_constant_oracle.lisp": ["tests/bootstrap_macro_constant_oracle.sh", "tests/bootstrap_macros.sh"],
    "tests/bootstrap_macro_nil_key_sbcl_oracle.lisp": ["tests/bootstrap_macros.sh"],
    "tests/bootstrap_package_forms_oracle.lisp": ["tests/bootstrap_package_forms.sh"],
    "tests/bootstrap_package_operations_oracle.lisp": ["tests/bootstrap_package_operations.sh"],
    "tests/bootstrap_cl_user_oracle.lisp": ["tests/bootstrap_cl_user.sh"],
}
SOURCE_OWNER_REASONS = {
    "tests/ir_verifier.lisp": "The seed smoke gate runs this Lisp verifier; the per-stage native compiler gate runs the C HIR/SSA/LIR verifier harness, while the IR dump gate checks generated stage text and object preservation.",
    "tests/managed_roots_verifier.lisp": "The seed managed-roots gate runs this Lisp verifier; the per-stage gate's C harness checks native root push/pop behavior and execution.",
    "tests/reference_bootstrap_binary.lisp": "The binary gate compiles and executes this reference program alongside the generation compiler.",
    "tests/bootstrap_environment_oracle.lisp": "The environment gate runs this oracle against the generation compiler and compares its observable package/environment behavior.",
    "tests/bootstrap_macro_constant_oracle.lisp": "The seed-only oracle gate checks the host macro result, and the per-stage macro gate invokes the same oracle before native macro fixtures.",
    "tests/bootstrap_macro_nil_key_sbcl_oracle.lisp": "The per-stage macro gate runs this SBCL oracle before checking native macro keyword handling.",
    "tests/bootstrap_package_forms_oracle.lisp": "The package-forms gate runs this oracle and compares source-level package results for each generation.",
    "tests/bootstrap_package_operations_oracle.lisp": "The package-operations gate runs this oracle and checks package mutation and lookup through each generation.",
    "tests/library.lisp": "The seed smoke gate executes this Stage 0 compiler API client; the per-stage native compiler gate exercises the corresponding compiler API through native C receivers.",
    "tests/bootstrap_environment_catalogue.lisp": "The environment gate runs this Stage 0 package catalogue generator and compares its results with the native environment reader's C harness.",
    "tests/bootstrap_cl_user_oracle.lisp": "The CL-USER gate runs this Stage 0 package/name visibility oracle, then checks the same source behavior and rejection through each generated compiler.",
}
INCLUDE_FIXTURE_GATES = {
    "tests/source_loader_identities/entry.lisp": ["tests/bootstrap_source_loader_identities.sh", "tests/bootstrap_source_loader_allocations.sh"],
    "tests/source_loader_identities/valid-leaf.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/shadowed.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/unknown-package.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/malformed.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/cycle.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/missing.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/package-order.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/child files/declarations.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/child files/functions.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/source_loader_identities/child files/select-package.lisp": ["tests/bootstrap_source_loader_identities.sh"],
    "tests/include/entry.lisp": ["tests/bootstrap_modules.sh", "tests/bootstrap_native_compiler.sh"],
    "tests/include/invalid_c_source.lisp": ["tests/bootstrap_c_output.sh", "tests/bootstrap_native_compiler.sh"],
    "tests/include/missing_c_source.lisp": ["tests/bootstrap_native_compiler.sh"],
    "tests/include/duplicate_c_source.lisp": ["tests/bootstrap_native_compiler.sh"],
    "tests/include/native_header.lisp": ["tests/bootstrap_c_output.sh"],
    "tests/include/native/main.lisp": ["tests/bootstrap_native_compiler.sh", "tests/bootstrap_self_core.sh"],
    "tests/include/native/flat.lisp": ["tests/bootstrap_native_compiler.sh"],
    "tests/include/native/shared.lisp": ["tests/bootstrap_native_compiler.sh"],
    "tests/include/native/missing.lisp": ["tests/bootstrap_self_core.sh", "tests/bootstrap_native_compiler.sh"],
    "tests/include/native/cycle-a.lisp": ["tests/bootstrap_self_core.sh", "tests/bootstrap_native_compiler.sh"],
    "tests/include/native/cycle-b.lisp": ["tests/bootstrap_self_core.sh", "tests/bootstrap_native_compiler.sh"],
    "tests/include/native/invalid.lisp": ["tests/bootstrap_self_core.sh", "tests/bootstrap_native_compiler.sh"],
    "tests/include/native/unterminated.lisp": ["tests/bootstrap_self_core.sh", "tests/bootstrap_native_compiler.sh"],
    "tests/include/native/nested/entry.lisp": ["tests/bootstrap_native_compiler.sh"],
}
INCLUDE_FIXTURE_REASONS = {
    "tests/source_loader_identities/entry.lisp": "The loader-identity gate compiles this entry through all four compiler targets and checks deterministic objects, C ABI behavior, include/package identity, and negative output preservation; the per-stage allocation gate also reads it while injecting failures and checks full storage cleanup.",
    "tests/source_loader_identities/valid-leaf.lisp": "The loader-identity gate reaches this included unit through alias and nickname directives, then verifies its exported C behavior against Stage 0 and each generated compiler.",
    "tests/source_loader_identities/shadowed.lisp": "The loader-identity gate verifies this lookalike shadowed directive is rejected with a diagnostic and preserves an existing output at every generated stage.",
    "tests/source_loader_identities/unknown-package.lisp": "The loader-identity gate verifies this unknown package directive is rejected with a diagnostic and preserves an existing output at every generated stage.",
    "tests/source_loader_identities/malformed.lisp": "The loader-identity gate verifies malformed source directives reject deterministically and preserve an existing output at every generated stage.",
    "tests/source_loader_identities/cycle.lisp": "The loader-identity gate verifies cyclic source inclusion rejects deterministically and preserves an existing output at every generated stage.",
    "tests/source_loader_identities/missing.lisp": "The loader-identity gate verifies a missing included source rejects deterministically and preserves an existing output at every generated stage.",
    "tests/source_loader_identities/package-order.lisp": "The loader-identity gate checks package-selection changes across ordered included files through observable compilation and C execution at every generated stage.",
    "tests/source_loader_identities/child files/declarations.lisp": "The loader-identity gate reaches this included unit through a path containing spaces and checks package identity plus relative C-source collection at every generated stage.",
    "tests/source_loader_identities/child files/functions.lisp": "The loader-identity gate reaches this included unit after package selection and validates the linked C caller result at every generated stage.",
    "tests/source_loader_identities/child files/select-package.lisp": "The loader-identity gate verifies that package selection in an included file governs the following source unit at every generated stage.",
    "tests/include/entry.lisp": "The module gate compiles the included entry unit; the native compiler gate checks include-unit collection and ordering.",
    "tests/include/invalid_c_source.lisp": "The C-output gate checks rejection of this malformed source declaration; the native compiler gate checks include error propagation.",
    "tests/include/missing_c_source.lisp": "The native compiler gate checks the missing included source diagnostic and confirms failed output is not published.",
    "tests/include/duplicate_c_source.lisp": "The native compiler gate checks duplicate included source collection and deterministic diagnostics.",
    "tests/include/native_header.lisp": "The C-output gate verifies header emission from this included native declaration.",
    "tests/include/native/main.lisp": "The native compiler gate checks nested native-unit collection; the seed self-core gate compiles this entry during bootstrap.",
    "tests/include/native/flat.lisp": "The native compiler gate verifies flattening of this included native unit into the compiler source set.",
    "tests/include/native/shared.lisp": "The native compiler gate verifies a shared included native source is collected once.",
    "tests/include/native/missing.lisp": "The seed self-core gate checks missing-file diagnostics; the per-stage native compiler gate runs this fixture and checks its diagnostic and output cleanup.",
    "tests/include/native/cycle-a.lisp": "The seed self-core gate checks cycle detection; the per-stage native compiler gate runs this fixture and checks its circular-include diagnostic and output cleanup.",
    "tests/include/native/cycle-b.lisp": "The seed self-core gate checks cycle detection through the peer file; the per-stage native compiler gate reaches it from cycle-a and checks its circular-include diagnostic.",
    "tests/include/native/invalid.lisp": "The seed self-core gate checks malformed include syntax; the per-stage native compiler gate runs this fixture and checks its diagnostic and output cleanup.",
    "tests/include/native/unterminated.lisp": "The seed self-core gate checks unterminated include syntax; the per-stage native compiler gate runs this fixture and checks its reader diagnostic and output cleanup.",
    "tests/include/native/nested/entry.lisp": "The native compiler gate verifies recursive collection of this nested entry unit.",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def digest_rows(rows: list[dict], roles: set[str]) -> str:
    digest = hashlib.sha256()
    for row in rows:
        if row["role"] in roles:
            digest.update(row["path"].encode("utf-8"))
            digest.update(b"\0")
            digest.update(row["sha256"].encode("ascii"))
            digest.update(b"\n")
    return digest.hexdigest()


def source_functional_ownership() -> list[dict]:
    path = ROOT / SOURCE_OWNERSHIP_DOCUMENT
    if not path.is_file():
        raise RuntimeError(f"missing seed-to-native ownership document: {SOURCE_OWNERSHIP_DOCUMENT}")
    mapping = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| `src/"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 2:
            raise RuntimeError(f"malformed ownership row in {SOURCE_OWNERSHIP_DOCUMENT}: {line}")
        seed_path = cells[0].strip("`")
        owners = [owner.strip() for owner in cells[1].split(";") if owner.strip()]
        mapping.append({"seed_unit": seed_path, "native_owners": owners})
    seed_files = {path.relative_to(ROOT).as_posix()
                  for path in (ROOT / "src").rglob("*.lisp")}
    mapped = {row["seed_unit"] for row in mapping}
    if len(mapped) != len(mapping):
        raise RuntimeError("duplicate Stage 0 unit in seed-to-native ownership map")
    if seed_files != mapped:
        raise RuntimeError("seed-to-native ownership coverage mismatch: "
                           f"unmapped={sorted(seed_files - mapped)}, "
                           f"stale={sorted(mapped - seed_files)}")
    return mapping


def tracked_inputs() -> list[Path]:
    roots = ["src", "bootstrap", "runtime", "tests", "examples", "docs", "linker"]
    paths: set[Path] = set()
    for root_name in roots:
        root = ROOT / root_name
        if not root.exists():
            continue
        for path in root.rglob("*"):
            relative = path.relative_to(ROOT)
            generated_python_cache = "__pycache__" in relative.parts or path.suffix == ".pyc"
            if path.is_file() and path != MANIFEST and not generated_python_cache:
                paths.add(path)
    for name in ("Makefile", "README.md", "AGENTS.md", "pslcc"):
        path = ROOT / name
        if path.is_file():
            paths.add(path)
    return sorted(paths, key=lambda path: path.relative_to(ROOT).as_posix())


def classify(path: Path) -> tuple[str, str, str]:
    relative = path.relative_to(ROOT).as_posix()
    if relative == "src/load.lisp" or relative.startswith("src/"):
        return "seed-source", "Stage 0 seed", "Loaded by src/load.lisp for SBCL-hosted Stage 0."
    if relative == "pslcc":
        return "seed-entry", "Stage 0 seed", "Fresh-checkout executable entry that invokes SBCL and src/cli.lisp."
    if relative == "bootstrap/README.md":
        return "contract", "Native compiler documentation", "Bootstrap ownership and design contract."
    if relative.startswith("bootstrap/"):
        if relative in {path for _, path in UNIT_ROOTS}:
            return "native-unit-root", "Native compiler", "Explicit compiler object unit built in every generation."
        if relative in PATH_ALTERNATES:
            return "host-path-variant", "Host adapter", PATH_ALTERNATES[relative]
        if relative.endswith(".lisp"):
            return "native-include", "Native compiler", "Transitive PSL include/source input owned by a declared native unit."
        if relative.endswith(".c"):
            return "host-adapter", "Host adapter", "C boundary code used to link and run a native compiler generation."
        if relative.endswith(".h"):
            return "host-interface", "Host adapter", "C interface/header used by native units or their host adapters."
    if relative.startswith("runtime/"):
        return "host-runtime", "Hosted compiler runtime", "Runtime implementation/header input for hosted compiler execution."
    if relative.startswith("linker/"):
        return "linker-script", "Target support", "Freestanding target linker script used by target gates."
    if relative.startswith("tests/"):
        return "release-corpus", "Release gate", "Accepted/rejected source, object, IR, diagnostics, C interop, or gate runner input."
    if relative.startswith("examples/"):
        return "example-corpus", "Release gate", "Documented executable source/C interop example input."
    if relative.startswith("docs/") or relative in {"README.md", "AGENTS.md"}:
        return "contract", "Repository contract", "Language, architecture, milestone, or agent workflow contract."
    if relative == "Makefile":
        return "build-interface", "Build system", "Native compiler object/link recipe and exposed test gates."
    return "unowned", "", ""


def config_template(snapshot_base_revision: str | None = None) -> dict:
    gates = {path for values in RELEASE_GATE_GROUPS.values() for path in values}
    unmapped = sorted(gates - SEED_ONLY - set(STAGE_CORPUS_GATE_ARGS))
    stale_modes = sorted(set(STAGE_CORPUS_GATE_ARGS) - gates)
    if unmapped or stale_modes:
        raise RuntimeError(f"release gate invocation-mode inventory mismatch: unmapped={unmapped}, stale={stale_modes}")
    sbcl = subprocess.run(["sbcl", "--version"], check=True,
                          capture_output=True, text=True).stdout.strip()
    sbcl_executable = Path(shutil.which("sbcl")).resolve()
    snapshot_base = snapshot_base_revision or os.environ.get("PSL_RELEASE_SNAPSHOT_BASE")
    if not snapshot_base:
        git_root = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--show-toplevel"],
                                  capture_output=True, text=True)
        if git_root.returncode != 0 or Path(git_root.stdout.strip()).resolve() != ROOT.resolve():
            raise RuntimeError("isolated release snapshot requires PSL_RELEASE_SNAPSHOT_BASE to record its actual source base revision")
        snapshot_base = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                                       check=True, capture_output=True, text=True).stdout.strip()
    if not re.fullmatch(r"[0-9a-fA-F]{40,64}", snapshot_base):
        raise RuntimeError("PSL_RELEASE_SNAPSHOT_BASE must be an explicit Git revision or full object id")
    rows = []
    for path in tracked_inputs():
        role, owner, reason = classify(path)
        if role == "unowned":
            raise RuntimeError(f"unowned release input: {path.relative_to(ROOT)}")
        rows.append({"path": path.relative_to(ROOT).as_posix(), "role": role,
                     "owner": owner, "reason": reason, "sha256": sha256(path)})
    seed_digest = digest_rows(rows, {"seed-source", "seed-entry"})
    compiler_digest = digest_rows(rows, {
        "native-unit-root", "native-include", "host-adapter", "host-interface", "host-runtime"})
    return {
        "schema": SCHEMA,
        "seed": {
            "identity": f"sbcl-stage0+sha256:{seed_digest}",
            "snapshot_base_revision": snapshot_base,
            "source_digest_sha256": seed_digest,
            "engine": "SBCL",
            "engine_version": sbcl,
            "executable": str(sbcl_executable),
            "executable_sha256": sha256(sbcl_executable),
            "entry": "pslcc",
            "source_loader": "src/load.lisp",
        },
        "generation_source_digest_sha256": compiler_digest,
        "source_ownership_document": SOURCE_OWNERSHIP_DOCUMENT,
        "seed_to_native_functional_ownership": source_functional_ownership(),
        "generation_units": [
            {"name": name, "path": path, "optimization": "-O1",
             "profile": "hosted", "fresh_object_each_stage": True}
            for name, path in UNIT_ROOTS
        ],
        "host_path_variants": [
            {"path": path, "selected_on": "matching host OS", "reason": reason}
            for path, reason in PATH_ALTERNATES.items()
        ],
        "non_generation_native_sources": [
            {"path": path, "reason": reason}
            for path, reason in NON_GENERATION_NATIVE_SOURCES.items()
        ],
        "host_c_adapters": HOST_C_ADAPTERS,
        "linux_host_runtime_sources": LINUX_RUNTIME_SOURCES,
        "supported_host_targets": HOST_TARGETS,
        "host_tool_requirements": HOST_TOOLS,
        "cross_tool_requirements": CROSS_TOOLS,
        "cross_tool_root": "../m8-cross-tools",
        "required_sysroots": REQUIRED_SYSROOTS,
        "corpus_runner": {
            "path": "tests/bootstrap_release_corpus.py",
            "source_inventory": "tests/bootstrap_release_sources.json",
            "source_inventory_schema": 3,
            "source_report_schema": 3,
            "runs_each_declared_stage_gate": True,
            "compiles_all_standalone_test_sources_at_o0_o1": True,
            "stage0_probe_cache": {
                "schema": 2,
                "content_keyed_by": ["source", "target", "profile", "optimization",
                                     "stage0_toolchain", "repository_input_digest",
                                     "compiler_environment"],
                "stores": ["status", "stdout", "stderr", "accepted_object_bytes"],
                "reuses_o0_between_source_refresh_and_full_corpus": True,
                "maximum_concurrent_stage0_compilers": SOURCE_PROBE_WORKERS,
                "cache_location_environment": "PSL_RELEASE_SOURCE_CACHE",
            },
            "source_status_cells": [{"target": target, "profile": profile}
                                    for target, profile in SOURCE_STATUS_CELLS],
            "compares_stage1_stage2_stage3_ir_for_accepted_sources": True,
            "compares_stage2_stage3_ir_for_accepted_sources": True,
            "runs_stage_native_api_receivers_from_stage_owned_objects": True,
            "stage_native_api_object_source": "stage-report.json stage_object_paths",
            "requires_nonstandalone_owner_reason": True,
            "requires_nonstandalone_stage_owner_gate_per_generation": True,
            "records_nonstandalone_owner_gate_evidence_per_generation": True,
            "runs_example_inventory_against_seed_and_all_stages": True,
            "example_inventory_runner": "tests/bootstrap_corpus.py",
            "seed_only_gates": sorted(SEED_ONLY),
            "per_stage_gate_argument_modes": STAGE_CORPUS_GATE_ARGS,
            "shell_entrypoint_inventory": release_shell_inventory(),
        },
        "release_gate_groups": RELEASE_GATE_GROUPS,
        "release_test_ownership": release_test_ownership(),
        "files": rows,
    }


def validate_snapshot_base_revision(revision: str) -> None:
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-fA-F]{40,64}", revision):
        raise RuntimeError("release manifest has an invalid seed snapshot base revision")
    git_root = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--show-toplevel"],
                              capture_output=True, text=True)
    if git_root.returncode != 0 or Path(git_root.stdout.strip()).resolve() != ROOT.resolve():
        return
    present = subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e",
                              f"{revision}^{{commit}}"], capture_output=True)
    if present.returncode != 0:
        return
    ancestor = subprocess.run(["git", "-C", str(ROOT), "merge-base", "--is-ancestor",
                               revision, "HEAD"], capture_output=True)
    if ancestor.returncode != 0:
        raise RuntimeError("release manifest seed snapshot base is not an ancestor of the current checkout")


def source_corpus_role(path: Path) -> str:
    relative = path.relative_to(ROOT).as_posix()
    if relative.startswith("examples/"):
        return "standalone"
    if (relative.startswith("tests/include/") or
            relative.startswith("tests/source_loader_identities/")):
        return "include-fixture"
    if relative in SOURCE_ORACLE_GATES:
        return "api-oracle"
    if relative.startswith("tests/"):
        source = path.read_text(encoding="utf-8")
        api_markers = (re.search(r"\(\s*load\b", source, re.IGNORECASE) or
                       re.search(r"\bpsl\.(?:compiler|ir):", source, re.IGNORECASE) or
                       "_oracle" in path.stem or "_verifier" in path.stem)
        if api_markers:
            raise RuntimeError(f"test API/oracle source needs explicit owner gates and reason: {relative}")
    return "standalone"


def source_owner_metadata(path: Path, role: str | None = None) -> tuple[list[str], str]:
    relative = path.relative_to(ROOT).as_posix()
    role = role or source_corpus_role(path)
    if role == "include-fixture":
        owners = INCLUDE_FIXTURE_GATES.get(relative, [])
        reason = INCLUDE_FIXTURE_REASONS.get(relative, "")
    elif role == "api-oracle":
        owners = SOURCE_ORACLE_GATES.get(relative, [])
        reason = SOURCE_OWNER_REASONS.get(relative, "")
    else:
        owners = ["tests/bootstrap_release_corpus.py"]
        collection = "repository example" if relative.startswith("examples/") else "test source"
        reason = (f"The full source inventory compiles this standalone {collection} against Stage 0 "
                  "and Stage 1/2/3 for every declared target/profile at -O0 and -O1; the separate "
                  "example gate also compares documented linked behavior where applicable.")
    if not owners or not reason.strip():
        raise RuntimeError(f"source row has no explicit gate owner and reason: {relative}")
    return owners, reason


def discover_test_sources() -> list[Path]:
    sources = [*(ROOT / "tests").rglob("*.lisp"),
               *(ROOT / "examples").rglob("*.lisp")]
    return sorted(sources, key=lambda path: path.relative_to(ROOT).as_posix())


def source_probe_toolchain() -> dict:
    environment = source_probe_process_environment()
    search_path = environment.get("PATH", "")
    rows = {}
    missing = []
    for tool in HOST_TOOLS + CROSS_TOOLS:
        found = shutil.which(tool, path=search_path)
        if found is None:
            missing.append(tool)
            continue
        resolved = Path(found).resolve()
        version = subprocess.run([str(resolved), "--version"],
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, timeout=10, env=environment)
        version_text = version.stdout.strip().splitlines()
        rows[tool] = {"path": str(resolved), "sha256": sha256(resolved),
                      "version_status": version.returncode,
                      "version": version_text[0] if version_text else ""}
    if missing:
        raise RuntimeError("cannot classify source outcomes before required tools are present: "
                           + ", ".join(missing))
    return rows


def source_probe_process_environment() -> dict[str, str]:
    environment = os.environ.copy()
    cross_value = environment.get("PSL_CROSS_TOOL_ROOT")
    cross_root = Path(cross_value).resolve() if cross_value else (ROOT.parent / "m8-cross-tools").resolve()
    additions = [cross_root / "bin", cross_root / "usr" / "bin"]
    available = [str(path) for path in additions if path.is_dir()]
    if available:
        environment["PATH"] = os.pathsep.join([*available, environment.get("PATH", "")])
    library = cross_root / "usr" / "lib" / "x86_64-linux-gnu"
    if library.is_dir():
        environment["LD_LIBRARY_PATH"] = os.pathsep.join(
            [str(library), environment.get("LD_LIBRARY_PATH", "")]).rstrip(os.pathsep)
    for variable, relative in (("AARCH64_SYSROOT", "usr/aarch64-linux-gnu"),
                               ("RISCV64_SYSROOT", "usr/riscv64-linux-gnu")):
        candidate = cross_root / relative
        if variable not in environment and candidate.is_dir():
            environment[variable] = str(candidate)
    return environment


def source_probe_repository_digest() -> str:
    rows = []
    for path in tracked_inputs():
        relative = path.relative_to(ROOT).as_posix()
        if path in {MANIFEST, SOURCE_CORPUS}:
            continue
        rows.append({"path": relative, "sha256": sha256(path)})
    digest = hashlib.sha256()
    for row in rows:
        digest.update(row["path"].encode("utf-8"))
        digest.update(b"\0")
        digest.update(row["sha256"].encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def source_probe_cache_directory() -> Path:
    configured = os.environ.get("PSL_RELEASE_SOURCE_CACHE")
    if configured:
        return Path(configured).resolve()
    return ROOT.parent / ".psl-release-source-cache-v2"


def source_probe_environment(environment: dict[str, str] | None) -> dict[str, str]:
    if environment is None:
        environment = os.environ
    names = ("PATH", "LD_LIBRARY_PATH", "PSL_CROSS_TOOL_ROOT", "CC",
             "AARCH64_CC", "RISCV64_CC", "WINDOWS_CC", "AARCH64_SYSROOT",
             "RISCV64_SYSROOT", "WINEPREFIX", "TMPDIR", "CFLAGS", "CPPFLAGS",
             "LDFLAGS", "ARFLAGS", "LANG", "LC_ALL", "SBCL_HOME")
    names = tuple(sorted(set(names) | {
        name for name in environment
        if name.endswith(("_CC", "_CFLAGS", "_CPPFLAGS", "_LDFLAGS", "_SYSROOT"))
    } | {name for name in environment if name.startswith("LC_")}))
    return {name: environment[name] for name in names if name in environment}


def source_probe_cache_key(source: Path, target: str, profile: str,
                           toolchain: dict, repository_digest: str,
                           optimization: str = SOURCE_PROBE_OPTIMIZATION,
                           environment: dict[str, str] | None = None) -> tuple[str, dict]:
    source_hash = sha256(source)
    identity = {
        "schema": 2,
        "compiler_root": str(ROOT.resolve()),
        "repository_digest_sha256": repository_digest,
        "stage0_toolchain": toolchain,
        "environment": source_probe_environment(environment),
        "source": source.relative_to(ROOT).as_posix(),
        "source_sha256": source_hash,
        "target": target,
        "profile": profile,
        "optimization": optimization,
        "arguments": [optimization, f"--target={target}",
                      f"--profile={profile}", "-c"],
    }
    encoded = json.dumps(identity, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest(), identity


def cached_seed_compile(source: Path, target: str, profile: str,
                        toolchain: dict, repository_digest: str,
                        optimization: str = SOURCE_PROBE_OPTIMIZATION,
                        environment: dict[str, str] | None = None,
                        output: Path | None = None) -> tuple[str, str, bytes, bytes, bool]:
    key, identity = source_probe_cache_key(source, target, profile,
                                           toolchain, repository_digest,
                                           optimization, environment)
    cache_path = source_probe_cache_directory() / key[:2] / key
    owned_output = output is None
    if owned_output:
        temporary_output = tempfile.TemporaryDirectory(prefix="psl-release-source-probe-output-")
        output = Path(temporary_output.name) / "source.o"
    assert output is not None
    output.unlink(missing_ok=True)
    if cache_path.is_dir():
        try:
            cached = json.loads((cache_path / "result.json").read_text(encoding="utf-8"))
            stdout = (cache_path / "stdout.bin").read_bytes()
            stderr = (cache_path / "stderr.bin").read_bytes()
            object_path = cache_path / "object.o"
            object_bytes = object_path.read_bytes() if object_path.is_file() else None
            if (cached.get("identity") == identity and
                    cached.get("status") in {"accepted", "rejected"} and
                    cached.get("stdout_sha256") == hashlib.sha256(stdout).hexdigest() and
                    cached.get("stderr_sha256") == hashlib.sha256(stderr).hexdigest() and
                    ((cached["status"] == "accepted" and object_bytes is not None and
                      cached.get("object_sha256") == hashlib.sha256(object_bytes).hexdigest()) or
                     (cached["status"] == "rejected" and object_bytes is None))):
                if cached["status"] == "accepted":
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(object_bytes)
                if owned_output:
                    temporary_output.cleanup()
                return key, cached["status"], stdout, stderr, True
        except (OSError, json.JSONDecodeError):
            pass

    result = subprocess.run(
        [str(ROOT / "pslcc"), optimization, f"--target={target}",
         f"--profile={profile}", "-c", str(source), "-o", str(output)],
        cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode not in (0, 1):
        if owned_output:
            temporary_output.cleanup()
        raise RuntimeError(f"Stage 0 source inventory probe failed operationally for {source} ({target}/{profile}/{optimization}): {result.returncode}")
    if output.exists() != (result.returncode == 0):
        if owned_output:
            temporary_output.cleanup()
        raise RuntimeError(f"Stage 0 source inventory artifact mismatch for {source} ({target}/{profile}/{optimization})")
    status = "accepted" if result.returncode == 0 else "rejected"
    object_bytes = output.read_bytes() if status == "accepted" else None
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_cache = Path(tempfile.mkdtemp(prefix=f".{key}.", dir=cache_path.parent))
    (temporary_cache / "stdout.bin").write_bytes(result.stdout)
    (temporary_cache / "stderr.bin").write_bytes(result.stderr)
    if object_bytes is not None:
        (temporary_cache / "object.o").write_bytes(object_bytes)
    cache_record = {
        "identity": identity,
        "status": status,
        "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
        "stderr_sha256": hashlib.sha256(result.stderr).hexdigest(),
        "object_sha256": hashlib.sha256(object_bytes).hexdigest() if object_bytes is not None else None,
    }
    (temporary_cache / "result.json").write_text(json.dumps(cache_record, sort_keys=True) + "\n",
                                                  encoding="utf-8")
    try:
        os.rename(temporary_cache, cache_path)
    except FileExistsError:
        shutil.rmtree(temporary_cache)
    if owned_output:
        temporary_output.cleanup()
    return key, status, result.stdout, result.stderr, False


def probe_source_cells(jobs: list[tuple[Path, str, str]], toolchain: dict) -> dict[tuple[str, str, str], str]:
    repository_digest = source_probe_repository_digest()
    process_environment = source_probe_process_environment()
    results: dict[tuple[str, str, str], str] = {}
    if not jobs:
        return results
    print(f"Stage 0 source inventory: checking {len(jobs)} cells with a {SOURCE_PROBE_WORKERS}-process ceiling",
          file=sys.stderr)
    cache_hits = 0
    with ThreadPoolExecutor(max_workers=SOURCE_PROBE_WORKERS) as executor:
        futures = {
            executor.submit(cached_seed_compile, source, target, profile,
                            toolchain, repository_digest, SOURCE_PROBE_OPTIMIZATION,
                            process_environment): (source, target, profile)
            for source, target, profile in jobs
        }
        completed = 0
        for future in as_completed(futures):
            source, target, profile = futures[future]
            _, status, _, _, cache_hit = future.result()
            cache_hits += int(cache_hit)
            results[(source.relative_to(ROOT).as_posix(), target, profile)] = status
            completed += 1
            if completed % 100 == 0 or completed == len(jobs):
                print(f"Stage 0 source inventory: {completed}/{len(jobs)} cells complete; "
                      f"{cache_hits} reused",
                      file=sys.stderr)
    return results


def write_source_corpus() -> None:
    toolchain = source_probe_toolchain()
    sources = discover_test_sources()
    jobs = [(source, target, profile)
            for source in sources
            if source_corpus_role(source) == "standalone"
            for target, profile in SOURCE_STATUS_CELLS]
    statuses = probe_source_cells(jobs, toolchain)
    rows = []
    for source in sources:
        role = source_corpus_role(source)
        relative = source.relative_to(ROOT).as_posix()
        expected = None
        if role == "standalone":
            expected = {f"{target}|{profile}": statuses[(relative, target, profile)]
                        for target, profile in SOURCE_STATUS_CELLS}
        owners, owner_reason = source_owner_metadata(source, role)
        rows.append({"path": relative, "role": role,
                     "owner_gates": owners, "owner_reason": owner_reason,
                     "stage0_status": expected,
                     "sha256": sha256(source)})
    data = {"schema": 3,
            "status_cells": [{"target": target, "profile": profile}
                             for target, profile in SOURCE_STATUS_CELLS],
            "optimization": "-O0 oracle; native verification at -O0 and -O1",
            "stage0": "pslcc",
            "stage0_toolchain": toolchain,
            "coverage": "all tests/**/*.lisp and examples/**/*.lisp source files",
            "files": rows}
    SOURCE_CORPUS.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def probe_seed_source(source: Path, target: str = "x86_64-linux-gnu",
                      profile: str = "hosted") -> str:
    toolchain = source_probe_toolchain()
    relative = source.relative_to(ROOT).as_posix()
    return probe_source_cells([(source, target, profile)], toolchain)[(relative, target, profile)]


def refresh_source_corpus_ownership() -> None:
    if not SOURCE_CORPUS.is_file():
        raise RuntimeError("release source-status inventory missing; run --write-source-corpus first")
    data = json.loads(SOURCE_CORPUS.read_text(encoding="utf-8"))
    toolchain = source_probe_toolchain()
    toolchain_changed = data.get("stage0_toolchain") != toolchain
    data["schema"] = 3
    data["status_cells"] = [{"target": target, "profile": profile}
                            for target, profile in SOURCE_STATUS_CELLS]
    data["optimization"] = "-O0 oracle; native verification at -O0 and -O1"
    data.pop("profile", None)
    data.pop("target", None)
    old_rows = {row["path"]: row for row in data.get("files", [])}
    discovered = {path.relative_to(ROOT).as_posix(): path for path in discover_test_sources()}
    removed = sorted(set(old_rows) - set(discovered))
    if removed:
        raise RuntimeError("source-status inventory contains removed source paths: " + ", ".join(removed))

    rows = []
    jobs = []
    for relative, path in discovered.items():
        row = old_rows.get(relative)
        if row is None:
            row = {"path": relative, "sha256": sha256(path), "stage0_status": None}
        role = source_corpus_role(path)
        source_hash = sha256(path)
        if row.get("sha256") != source_hash:
            raise RuntimeError(f"cannot refresh stale source-status record: {relative}")
        owners, owner_reason = source_owner_metadata(path, role)
        if role == "standalone":
            previous = row.get("stage0_status")
            if not isinstance(previous, dict):
                previous = {}
            for target, profile in SOURCE_STATUS_CELLS:
                key = f"{target}|{profile}"
                if (toolchain_changed or
                        previous.get(key) not in {"accepted", "rejected"}):
                    jobs.append((path, target, profile))
            row["stage0_status"] = previous
        else:
            row["stage0_status"] = None
        row["sha256"] = source_hash
        row["role"] = role
        row["owner_gates"] = owners
        row["owner_reason"] = owner_reason
        rows.append(row)

    statuses = probe_source_cells(jobs, toolchain)
    for row in rows:
        if row["role"] != "standalone":
            continue
        source = discovered[row["path"]]
        for target, profile in SOURCE_STATUS_CELLS:
            key = f"{target}|{profile}"
            status_key = (row["path"], target, profile)
            if status_key in statuses:
                row["stage0_status"][key] = statuses[status_key]
    data["files"] = sorted(rows, key=lambda row: row["path"])
    data["stage0_toolchain"] = toolchain
    SOURCE_CORPUS.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def check_source_corpus() -> dict:
    if not SOURCE_CORPUS.is_file():
        raise RuntimeError("release source-status inventory missing; run --write-source-corpus")
    data = json.loads(SOURCE_CORPUS.read_text(encoding="utf-8"))
    if (data.get("schema") != 3 or
            data.get("coverage") != "all tests/**/*.lisp and examples/**/*.lisp source files"):
        raise RuntimeError("unsupported or incomplete release source-status inventory")
    expected_cells = [{"target": target, "profile": profile}
                      for target, profile in SOURCE_STATUS_CELLS]
    if data.get("status_cells") != expected_cells:
        raise RuntimeError("release source-status inventory lacks the required target/profile matrix")
    if data.get("stage0_toolchain") != source_probe_toolchain():
        raise RuntimeError("Stage 0 source-status inventory was produced with a different toolchain")
    listed = {row["path"]: row for row in data.get("files", [])}
    discovered = {path.relative_to(ROOT).as_posix(): path for path in discover_test_sources()}
    if set(listed) != set(discovered):
        raise RuntimeError("release source-status inventory coverage mismatch: "
                           f"missing={sorted(set(discovered)-set(listed))}, "
                           f"stale={sorted(set(listed)-set(discovered))}")
    for name, path in discovered.items():
        row = listed[name]
        role = source_corpus_role(path)
        owners, owner_reason = source_owner_metadata(path, role)
        gate_set = {gate for values in RELEASE_GATE_GROUPS.values() for gate in values}
        if role != "standalone" and (not (set(owners) - SEED_ONLY) or
                                     not set(owners) <= gate_set):
            raise RuntimeError(f"non-standalone source lacks declared per-stage owner gate: {name}")
        if (row.get("role") != role or row.get("owner_gates") != owners or
                row.get("owner_reason") != owner_reason or
                row.get("sha256") != sha256(path)):
            raise RuntimeError(f"release source-status inventory is stale: {name}")
        if role == "standalone":
            statuses = row.get("stage0_status")
            expected_cells = {f"{target}|{profile}" for target, profile in SOURCE_STATUS_CELLS}
            if not isinstance(statuses, dict) or set(statuses) != expected_cells or any(
                    value not in {"accepted", "rejected"} for value in statuses.values()):
                raise RuntimeError(f"source lacks explicit Stage 0 target/profile status matrix: {name}")
        if role in {"api-oracle", "include-fixture"} and row.get("stage0_status") is not None:
            raise RuntimeError(f"non-standalone source has unexpected compile status: {name}")
    return data


def write_manifest() -> None:
    data = config_template()
    MANIFEST.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def check_manifest() -> dict:
    if not MANIFEST.is_file():
        raise RuntimeError(f"release manifest missing: {MANIFEST}")
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if data.get("schema") != SCHEMA:
        raise RuntimeError("unsupported release manifest schema")
    seed = data.get("seed")
    if not isinstance(seed, dict):
        raise RuntimeError("release manifest is missing seed provenance")
    snapshot_base = seed.get("snapshot_base_revision")
    validate_snapshot_base_revision(snapshot_base)
    expected = config_template(snapshot_base_revision=snapshot_base)
    for key in ("seed", "generation_units", "host_path_variants",
                "non_generation_native_sources", "host_c_adapters",
                "linux_host_runtime_sources", "supported_host_targets",
                "host_tool_requirements", "cross_tool_requirements",
                "cross_tool_root", "required_sysroots", "corpus_runner",
                "generation_source_digest_sha256",
                "source_ownership_document", "seed_to_native_functional_ownership",
                "release_gate_groups", "release_test_ownership"):
        if data.get(key) != expected[key]:
            raise RuntimeError(f"release manifest configuration is stale: {key}")
    listed = {row["path"]: row for row in data.get("files", [])}
    discovered = {path.relative_to(ROOT).as_posix(): path for path in tracked_inputs()}
    missing = sorted(set(discovered) - set(listed))
    stale = sorted(set(listed) - set(discovered))
    if missing or stale:
        raise RuntimeError(f"manifest coverage mismatch: unowned={missing}, stale={stale}")
    changed = []
    for name, path in discovered.items():
        row = listed[name]
        role, owner, reason = classify(path)
        if role == "unowned":
            raise RuntimeError(f"unowned release input: {name}")
        if row.get("role") != role or row.get("owner") != owner or row.get("reason") != reason:
            changed.append(name + " (ownership metadata)")
        if row.get("sha256") != sha256(path):
            changed.append(name + " (content hash)")
    if changed:
        raise RuntimeError("release manifest hashes/ownership are stale: " + ", ".join(changed))
    return data


def dry_run_configuration() -> dict:
    """Validate the release plan without writing a manifest or building stages."""
    data = config_template(snapshot_base_revision="0" * 40)
    units = data["generation_units"]
    if len(units) != 8 or len({unit["name"] for unit in units}) != 8:
        raise RuntimeError("dry run requires the complete eight-unit generation set")
    cells = data["corpus_runner"]["source_status_cells"]
    if len(cells) != 12 or len({(cell["target"], cell["profile"]) for cell in cells}) != 12:
        raise RuntimeError("dry run requires all 12 source target/profile cells")
    gates = sorted({path for paths in data["release_gate_groups"].values() for path in paths})
    missing = [path for path in gates if not (ROOT / path).is_file()]
    if missing:
        raise RuntimeError("dry run found missing release gates: " + ", ".join(missing))
    example_runner = data["corpus_runner"]["example_inventory_runner"]
    if not (ROOT / example_runner).is_file():
        raise RuntimeError(f"dry run found missing example runner: {example_runner}")
    source_files = discover_test_sources()
    example_sources = [path for path in source_files
                       if path.relative_to(ROOT).as_posix().startswith("examples/")]
    if not example_sources:
        raise RuntimeError("dry run found no repository example sources for the source matrix")
    return {"generation_units": len(units), "source_status_cells": len(cells),
            "release_gates": len(gates), "special_fixture_owners": len(data["release_test_ownership"]),
            "source_files": len(source_files), "example_sources": len(example_sources),
            "example_runner": example_runner,
            "manifest_written": False, "stages_built": False}


def preflight(data: dict) -> dict:
    seed_version = subprocess.run(["sbcl", "--version"], check=True,
                                  capture_output=True, text=True).stdout.strip()
    if seed_version != data["seed"]["engine_version"]:
        raise RuntimeError(f"SBCL seed mismatch: expected {data['seed']['engine_version']}, got {seed_version}")
    for unit in data["generation_units"]:
        if not (ROOT / unit["path"]).is_file():
            raise RuntimeError(f"missing native generation unit: {unit['path']}")
    for path in data["host_c_adapters"] + data["linux_host_runtime_sources"]:
        if not (ROOT / path).is_file():
            raise RuntimeError(f"missing declared host build input: {path}")
    if len({unit["path"] for unit in data["generation_units"]}) != len(data["generation_units"]):
        raise RuntimeError("duplicate native generation unit path")
    if {unit["name"] for unit in data["generation_units"]} != {
            "core", "host", "source", "input", "path-posix", "compiler", "output", "diagnostics"}:
        raise RuntimeError("native generation unit inventory differs from the declared complete unit set")
    reachable = include_closure(unit["path"] for unit in data["generation_units"])
    declared_exclusions = {row["path"] for row in data["non_generation_native_sources"]}
    variants = {row["path"] for row in data["host_path_variants"]}
    native_sources = {path.relative_to(ROOT).as_posix()
                      for path in (ROOT / "bootstrap").rglob("*.lisp")}
    unowned_native = sorted(native_sources - reachable - declared_exclusions - variants)
    missing_native = sorted((reachable | declared_exclusions | variants) - native_sources)
    if unowned_native or missing_native:
        raise RuntimeError(f"native PSL source ownership mismatch: unowned={unowned_native}, missing={missing_native}")
    missing_corpus_gates = [path for paths in data["release_gate_groups"].values()
                            for path in paths if not (ROOT / path).is_file()]
    if missing_corpus_gates:
        raise RuntimeError("release is closed; declared corpus gates are missing: "
                           + ", ".join(sorted(set(missing_corpus_gates))))
    configured_cross_root = os.environ.get("PSL_CROSS_TOOL_ROOT")
    cross_root = (Path(configured_cross_root).resolve() if configured_cross_root
                  else (ROOT.parent / "m8-cross-tools").resolve())
    cross_bin = cross_root / "bin"
    path_dirs = [str(cross_bin), str(cross_root / "usr" / "bin"),
                 os.environ.get("PATH", "")]
    search_path = os.pathsep.join(path_dirs)
    missing = [tool for tool in data["host_tool_requirements"]
               if shutil.which(tool) is None]
    missing.extend(tool for tool in data["cross_tool_requirements"]
                   if shutil.which(tool, path=search_path) is None)
    sysroots = resolve_required_sysroots(data["required_sysroots"], cross_root)
    missing_sysroots = [name for name, path in sysroots.items() if not path.is_dir()]
    if missing:
        raise RuntimeError("missing release host tools: " + ", ".join(missing))
    if missing_sysroots:
        details = [f"{name}={sysroots[name]}" for name in missing_sysroots]
        raise RuntimeError("missing target sysroots: " + ", ".join(details))
    source_corpus = check_source_corpus()
    declared_gate_set = {path for paths in data["release_gate_groups"].values()
                         for path in paths}
    for row in source_corpus["files"]:
        if row["role"] == "standalone":
            continue
        unowned = sorted(set(row["owner_gates"]) - declared_gate_set)
        no_stage_owner = not (set(row["owner_gates"]) - SEED_ONLY)
        if unowned or no_stage_owner or not row.get("owner_reason", "").strip():
            raise RuntimeError(f"source fixture has incomplete gate ownership for {row['path']}: "
                               f"undeclared={unowned}, per_stage_owner={not no_stage_owner}, "
                               f"reason={bool(row.get('owner_reason', '').strip())}")
    return {"sbcl_version": seed_version, "host": "x86_64-linux-gnu",
            "unit_count": len(data["generation_units"]),
            "transitive_native_lisp_sources": len(reachable),
            "test_source_inventory": {
                "path": "tests/bootstrap_release_sources.json",
                "standalone": sum(row["role"] == "standalone" for row in source_corpus["files"]),
                "include_fixtures": sum(row["role"] == "include-fixture" for row in source_corpus["files"]),
                "api_oracles": sum(row["role"] == "api-oracle" for row in source_corpus["files"]),
                "sha256": sha256(SOURCE_CORPUS)},
            "missing_release_gates": missing_corpus_gates,
            "cross_tool_root": str(cross_root),
            "sysroots": {name: str(path) for name, path in sysroots.items()},
            "cross_tools": {tool: shutil.which(tool, path=search_path)
                            for tool in data["cross_tool_requirements"]},
            "required_cross_tools": data["cross_tool_requirements"],
            "tools": data["host_tool_requirements"]}


def resolve_required_sysroots(required: list[str], cross_root: Path,
                              environ: dict[str, str] | None = None) -> dict[str, Path]:
    environment = os.environ if environ is None else environ
    mappings = {
        "usr/aarch64-linux-gnu": ("aarch64-linux-gnu", "AARCH64_SYSROOT"),
        "usr/riscv64-linux-gnu": ("riscv64-linux-gnu", "RISCV64_SYSROOT"),
    }
    resolved = {}
    for relative in required:
        fallback = cross_root / relative
        name, variable = mappings.get(relative, (relative, ""))
        override = environment.get(variable) if variable else None
        path = Path(override).expanduser() if override else fallback
        resolved[name] = path.resolve()
    return resolved


def include_closure(entry_paths) -> set[str]:
    reachable: set[str] = set()
    pending = [ROOT / path for path in entry_paths]
    pattern = re.compile(r'\(include\s+"([^"]+)"\)', re.IGNORECASE)
    while pending:
        path = pending.pop().resolve()
        try:
            relative = path.relative_to(ROOT).as_posix()
        except ValueError as error:
            raise RuntimeError(f"native include escapes repository: {path}") from error
        if relative in reachable:
            continue
        if not path.is_file():
            raise RuntimeError(f"missing native source include: {relative}")
        reachable.add(relative)
        for include in pattern.findall(path.read_text(encoding="utf-8")):
            pending.append(path.parent / include)
    return reachable


def run(command: list[str], env: dict[str, str] | None = None) -> None:
    subprocess.run(command, cwd=ROOT, env=env, check=True)


def compiler_command(path: Path) -> list[str]:
    return [str(path)]


def build_generation(compiler: list[str], generation: int, directory: Path,
                     data: dict) -> tuple[Path, dict[str, Path]]:
    object_dir = directory / "objects"
    object_dir.mkdir(parents=True, exist_ok=True)
    objects: dict[str, Path] = {}
    for unit in data["generation_units"]:
        output = object_dir / f"{unit['name']}.o"
        command = compiler + [unit["optimization"], f"--profile={unit['profile']}",
                              "-c", str(ROOT / unit["path"]), "-o", str(output)]
        run(command)
        if not output.is_file() or output.stat().st_size == 0:
            raise RuntimeError(f"generation {generation} failed to produce {unit['name']} object")
        objects[unit["name"]] = output
    executable = directory / "pslcc-native"
    c_compiler = os.environ.get("CC", "cc")
    link_command = [c_compiler, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                    "-Wl,--build-id=none", "-Iruntime"]
    link_command.extend(str(ROOT / path) for path in data["host_c_adapters"])
    link_command.extend(str(objects[unit["name"]]) for unit in data["generation_units"])
    link_command.extend(str(ROOT / path) for path in data["linux_host_runtime_sources"])
    link_command.extend(["-pthread", "-o", str(executable)])
    run(link_command)
    run(compiler_command(executable) + ["--help"])
    return executable, objects


def build_stages(data: dict, work_dir: Path) -> dict:
    reports = []
    stage_object_paths = {}
    seed = [str(ROOT / "pslcc")]
    previous_objects = None
    previous_executable_hash = None
    for generation in range(1, 4):
        directory = work_dir / f"stage{generation}"
        directory.mkdir(parents=True, exist_ok=False)
        compiler = seed if generation == 1 else compiler_command(work_dir / f"stage{generation - 1}" / "pslcc-native")
        executable, objects = build_generation(compiler, generation, directory, data)
        stage_object_paths[str(generation)] = {name: str(path.resolve())
                                               for name, path in objects.items()}
        if previous_objects is not None:
            mismatches = [name for name in objects
                          if sha256(objects[name]) != sha256(previous_objects[name])]
            if mismatches and generation == 3:
                raise RuntimeError("Stage 2/3 unit objects differ: " + ", ".join(mismatches))
            if generation == 3 and sha256(executable) != previous_executable_hash:
                raise RuntimeError("Stage 2/3 compiler executables differ")
        if generation == 2:
            previous_objects = objects
            previous_executable_hash = sha256(executable)
        reports.append({"generation": generation, "executable": str(executable),
                        "sha256": sha256(executable),
                        "objects": {name: sha256(path) for name, path in objects.items()}})
    return {"stages": reports, "stage_object_paths": stage_object_paths}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-manifest", action="store_true",
                        help="write exact source/tool ownership hashes; set PSL_RELEASE_SNAPSHOT_BASE for an isolated snapshot")
    parser.add_argument("--write-source-corpus", action="store_true",
                        help="probe standalone test/example sources across all declared target/profile cells with Stage 0")
    parser.add_argument("--refresh-source-corpus", action="store_true",
                        help="refresh source roles/gate ownership and probe newly included fragments without changing existing statuses")
    parser.add_argument("--check", action="store_true", help="verify exact inventory, ownership, and file hashes")
    parser.add_argument("--dry-run", action="store_true",
                        help="validate unit, source-cell, fixture-owner, and gate mappings without writing files")
    parser.add_argument("--preflight", action="store_true", help="verify declared seed/tools/units")
    parser.add_argument("--build-stages", action="store_true", help="freshly build Stage 1, 2, and 3")
    parser.add_argument("--release", action="store_true", help="build all stages and run the complete release corpus")
    parser.add_argument("--work-dir", type=Path)
    args = parser.parse_args()
    try:
        if args.dry_run:
            print(json.dumps(dry_run_configuration(), indent=2))
            return 0
        if args.write_manifest:
            write_manifest()
            print(f"wrote {MANIFEST}")
            return 0
        if args.write_source_corpus:
            write_source_corpus()
            print(f"wrote {SOURCE_CORPUS}")
            return 0
        if args.refresh_source_corpus:
            refresh_source_corpus_ownership()
            print(f"refreshed {SOURCE_CORPUS}")
            return 0
        data = check_manifest()
        details = None
        if args.check or args.preflight or args.build_stages or args.release:
            details = preflight(data)
        if args.check or args.preflight:
            print(json.dumps({"manifest": str(MANIFEST), "files": len(data["files"]),
                              "seed": data["seed"], "preflight": details}, indent=2))
        if args.release:
            missing = details["missing_release_gates"]
            if missing:
                raise RuntimeError("release is closed; required corpus gates are missing: " + ", ".join(missing))
            runner = data["corpus_runner"]
            if not runner or not (ROOT / runner["path"]).is_file():
                raise RuntimeError("release is closed: configured Stage 1/2/3 corpus runner is missing")
        if args.build_stages or args.release:
            if args.work_dir:
                work_dir = args.work_dir.resolve()
                work_dir.mkdir(parents=True, exist_ok=False)
                temporary = False
            else:
                work_dir = Path(tempfile.mkdtemp(prefix="psl-release-"))
                temporary = True
            report = build_stages(data, work_dir)
            report["manifest_sha256"] = sha256(MANIFEST)
            report["seed"] = data["seed"]
            report["generation_source_digest_sha256"] = data["generation_source_digest_sha256"]
            report["preflight"] = details
            (work_dir / "stage-report.json").write_text(json.dumps(report, indent=2) + "\n")
            if args.release:
                from bootstrap_release_corpus import run_release_corpus
                stage_compilers = [work_dir / f"stage{index}" / "pslcc-native"
                                   for index in (1, 2, 3)]
                corpus_data = dict(data)
                corpus_data["stage_objects"] = report["stage_object_paths"]
                corpus = run_release_corpus(corpus_data, stage_compilers, work_dir / "corpus")
                report["corpus"] = corpus
                report["release_complete"] = bool(corpus.get("complete"))
                if not report["release_complete"]:
                    raise RuntimeError("corpus runner did not report all required Stage1/2/3 gates")
                (work_dir / "stage-report.json").write_text(json.dumps(report, indent=2) + "\n")
            if args.release:
                print(f"Stage 1/2/3 and complete release corpus passed: {work_dir / 'stage-report.json'}")
            elif temporary:
                print(f"stages built under temporary directory {work_dir}; this is not a release pass")
            else:
                print(f"Stage 1/2/3 build report: {work_dir / 'stage-report.json'}; release corpus has not been run")
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"release builder: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
