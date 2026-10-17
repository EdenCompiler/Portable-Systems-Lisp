# Bootstrap release verification

[Documentation](README.md) / M8 release gate

This gate builds the complete declared native compiler and compares three
fresh generations. It covers all test and example sources, their owning API
or include gates, object inspection, IR, diagnostics, runtime behavior, C
interoperability and cross-target execution. M8 remains in progress until a
frozen snapshot passes the entire gate.

## Requirements

Run on an x86-64 Linux compiler host with SBCL, a C compiler, Make, Python 3.11
or newer and binutils. The full gate also needs the AArch64 and RISC-V Linux
cross toolchains and sysroots, RISC-V bare-metal tools, QEMU user/system
emulators, MinGW-w64 and Wine. Missing tools fail preflight.

Installed tools can be found on `PATH`. An unpacked tool bundle can be selected
with `PSL_CROSS_TOOL_ROOT`; its `bin` and `usr/bin` directories are searched.
`AARCH64_SYSROOT` and `RISCV64_SYSROOT` override the corresponding sysroots.
Select `WINEPREFIX` when you need a specific Wine environment.

## Freeze, generate and run

Finish source and gate changes before generating the inventories. From the
repository root:

```sh
python3 tests/bootstrap_release.py --dry-run
python3 tests/bootstrap_release.py --write-source-corpus
python3 tests/bootstrap_release.py --write-manifest
python3 tests/bootstrap_release.py --check
python3 tests/bootstrap_release.py --preflight
python3 tests/bootstrap_release.py --release --work-dir build/m8-release
```

The work directory must be new. `--write-source-corpus` probes Stage 0 outcomes
for every standalone test and example in all 12 target/profile cells. It runs
at most two seed compiler processes concurrently. Generate the compiler
manifest afterward so it hashes that fresh inventory.

`--refresh-source-corpus` updates ownership metadata for unchanged source
inputs; use `--write-source-corpus` after compiler or source changes. Manifest
checks reject stale hashes and missing ownership. `--dry-run` validates the
unit, gate, source and target/profile inventories without building or writing
manifests.

Every `tests/*.sh` entry point must appear in the manifest as a release gate
or as a helper with named callers. Adding an unclassified script fails inventory
validation. The gate modes record how each suite receives the generated compiler,
its API objects, and its target matrix; seed-only oracles have explicit reasons.

## What the gate proves

1. Stage 0 builds all eight hosted PSL units for Stage 1. Stage 1 builds the
   same units for Stage 2, and Stage 2 builds Stage 3. Generation objects are
   always freshly compiled.
2. Each generated compiler runs every declared stage gate, using its own
   compiler API objects. Cross gates inspect and execute the appropriate
   target artifacts through QEMU or Wine. Seed-only oracles remain explicit.
3. Standalone test and example sources are checked against current Stage 0
   acceptance/rejection at O0/O1 in every cell. API clients and include
   fragments require successful owner-gate evidence from every generated stage.
4. Accepted sources receive object-format checks and exact native-stage IR
   comparisons. Rejected sources compare native-stage diagnostics and must
   leave no output artifact. Deterministic Stage 2/3 objects and compiler
   executables must match.
5. The separate example inventory compares linked behavior with the seed and
   requires native parity for every example. Dedicated gates cover environment,
   runtime, C ABI, CLI and freestanding execution.

The API fixture cache may reuse validated objects within a focused regression.
It never supplies generation objects. Stage 0 source-probe caching includes
source, toolchain, environment and repository hashes; it cannot turn an earlier
compiler snapshot into a release pass.

## Reports and failures

| Artifact | Contents |
| --- | --- |
| `tests/bootstrap_release_sources.json` | Every test/example source, hash, role, owner reason and Stage 0 target/profile outcomes |
| `tests/bootstrap_compiler_manifest.json` | Seed/tool provenance, compiler units, transitive ownership, gate modes and input hashes |
| `build/m8-release/stage-report.json` | Generated compiler/object paths and hashes, preflight details and final corpus status |
| `build/m8-release/corpus/` | Per-stage gate logs, source/IR/diagnostic comparisons and the example report |

Logs are written while each gate runs, preserving partial output. Inspect the
failing gate before changing source; a failed or partial run is evidence for
that run only. Preserve its reports, make the fix, regenerate stale inventories,
and start a new release work directory. Component passes and a successful
`--build-stages` run alone do not complete the release corpus.

See the [native guide](../bootstrap/README.md) for smaller development checks
and the [roadmap](roadmap.md#m8--self-hosting--in-progress) for the full acceptance
boundary.
