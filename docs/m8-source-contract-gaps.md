# M8 source-contract and compiler-unit inventory

Audit basis: `src/load.lisp`, `src/cli.lisp`, `bootstrap/native-core.lisp`, the bootstrap include graph, `README.md`, `docs/core.md`, `docs/architecture.md`, and the M8 release requirements in `docs/roadmap.md`. This report distinguishes the Stage 0 seed (`src/`) from its separately implemented native replacement (`bootstrap/`). It is a gap inventory, not an M8 completion claim. This snapshot loads 41 units from `src/load.lisp`; the two entry/manifest files `src/cli.lisp` and `src/load.lisp` are listed separately below.

## Scope boundary

Only behavior implemented by the seed and within the documented source contract can count as an M8 seed-to-native port gap. The following are explicit Stage 0 exclusions in `docs/core.md`; they must not be counted as remaining M8 work or added to the seed contract merely to make the native implementation appear closer: package redefinition; floating arithmetic and comparisons; packed aggregates passed by value; records larger than 16 bytes passed by value; variadic calls; and `long double`. Floating literals, parameters, calls, and returns are supported, and packed layout/field access is supported, but those do not imply the excluded operations. Other documented unsupported forms likewise need a seed-side support check before entering the M8 gap list.

Stage 0's current entry unit `src/cli.lisp` loads the 41 units in `src/load.lisp`; those files are the reference implementation and compiler seed, not additional unported native files. The native compiler is an independently organized replacement. Its ownership below is therefore functional and many-to-many: native modules split or combine seed responsibilities. This mapping does not claim complete semantic parity.

## Stage 0 seed units mapped to native owners

| Stage 0 seed unit | Native replacement owner(s) |
|---|---|
| `src/package.lisp` | `bootstrap/native_api.h`; `bootstrap/frontend/environment/{types,seed,seed_catalogue,seed_words,operations,packages}.lisp` |
| `src/common.lisp` | `bootstrap/unit_types.lisp`; `bootstrap/binary_types.lisp`; `bootstrap/ir/{ir_types,integer_types}.lisp`; `bootstrap/frontend/*_types.lisp`; `bootstrap/host/*_types.lisp` |
| `src/ir/hir.lisp` | `bootstrap/ir/{hir,hir_types}.lisp`; `bootstrap/frontend/hir_analyze_*.lisp` |
| `src/ir/types.lisp` | `bootstrap/ir/{types,ir_types,integer_types}.lisp`; `bootstrap/frontend/scalar_types.lisp`; `bootstrap/frontend/aggregate_types.lisp` |
| `src/ir/ssa.lisp` | `bootstrap/ir/{ssa,ssa_types,ssa_lower,ssa_lower_control,ssa_optimize,ssa_fold,ssa_fold_scalar,ssa_inline,ssa_inline_insert,ssa_inline_templates,ssa_live,ssa_remap,ssa_compact}.lisp` |
| `src/binary.lisp` | `bootstrap/{binary,binary_types}.lisp`; `bootstrap/object/bytes.lisp` |
| `src/target.lisp` | `bootstrap/target.lisp`; `bootstrap/host/compiler_target_options.lisp` |
| `src/frontend/layout.lisp` | `bootstrap/frontend/{layout,layout_types,layout_packed}.lisp`; `bootstrap/frontend/hir_analyze_layout.lisp` |
| `src/frontend/reader.lisp` | `bootstrap/frontend/{reader,reader_types,parser,parser_types,atoms,atoms_types,identity_syntax,symbol_names,symbols,source_reader}.lisp`; `bootstrap/frontend/environment/*`; `bootstrap/host/{source_environment,source_imports,source_unit}.lisp` |
| `src/frontend/packages.lisp` | `bootstrap/frontend/{package_forms,package_forms_types,package_form_names,package_form_validation}.lisp`; `bootstrap/frontend/environment/{packages,visibility,aliases}.lisp`; `bootstrap/host/source_environment.lisp` |
| `src/frontend/identities.lisp` | `bootstrap/frontend/{identity_syntax,symbol_names,symbols,source_reader}.lisp`; `bootstrap/frontend/environment/{index,resolve,symbols,words}.lisp`; `bootstrap/host/source_environment.lisp` |
| `src/frontend/runtime.lisp` | `bootstrap/frontend/{runtime_catalogue_capacity,runtime_signatures,signatures,signatures_types,ffi}.lisp`; `bootstrap/host/environment_{initialize,storage}.lisp`; runtime/link closure in `bootstrap/host/compiler_link.lisp` |
| `src/frontend/closures.lisp` | `bootstrap/frontend/hir_analyze_closures.lisp`; `bootstrap/ir/root_*.lisp`; `bootstrap/backend/*roots*.lisp`; `bootstrap/backend/root_frame.lisp` |
| `src/frontend/strings.lisp` | `bootstrap/frontend/{string_types,string_decode,string_literals,c_strings}.lisp`; managed data in `bootstrap/frontend/{data,data_types}.lisp` |
| `src/frontend/multiple-values.lisp` | `bootstrap/frontend/hir_analyze_values.lisp`; `bootstrap/ir/{hir,ssa}.lisp`; value lowering in `bootstrap/ir/lir_lower.lisp` |
| `src/frontend/pointers.lisp` | `bootstrap/frontend/{pointer_types,pointer_references}.lisp`; `bootstrap/frontend/hir_analyze_memory.lisp`; `bootstrap/backend/*memory*.lisp` |
| `src/frontend/analyze.lisp` | `bootstrap/frontend/hir_analyze_*.lisp`; `bootstrap/frontend/{scalar_resolve,scalar_syntax,signatures}.lisp` |
| `src/frontend/macro_bridge.lisp` | `bootstrap/frontend/macros/{eval,primitive_eval,expand,functions,key_bindings,key_parameters}.lisp`; macro registration and execution boundary |
| `src/frontend/macro_variables.lisp` | `bootstrap/frontend/macros/{key_parameters,key_bindings,binding_values}.lisp`; macro lambda-list binding and constant-name validation |
| `src/frontend/effects.lisp` | `bootstrap/frontend/{effects,effects_syntax}.lisp`; `bootstrap/driver_effects.lisp` |
| `src/ir/lower.lisp` | `bootstrap/ir/{ssa_lower,ssa_lower_control,lir_lower}.lisp` |
| `src/ir/verify/common.lisp` | `bootstrap/ir/{ir_verify_type_helpers,hir_verify_types,ssa_verify}.lisp` |
| `src/ir/verify/hir.lisp` | `bootstrap/ir/{hir_verify_memory,hir_verify_memory_shape,hir_verify_scope,hir_verify_types}.lisp` |
| `src/ir/verify/ssa.lisp` | `bootstrap/ir/{ssa_verify,ssa_verify_cfg}.lisp` |
| `src/ir/verify/lir.lisp` | `bootstrap/ir/{lir_verify,lir_verify_cfg}.lisp` |
| `src/ir/roots.lisp` | `bootstrap/ir/{root_catalog,root_lower,root_verify}.lisp`; backend root-frame modules |
| `src/ir/optimize.lisp` | `bootstrap/ir/{ssa_optimize,ssa_fold,ssa_fold_scalar,ssa_inline,ssa_live,ssa_compact}.lisp` |
| `src/ir/dump.lisp` | `bootstrap/ir/{dump,dump_types}.lisp`; current CLI dump integration `bootstrap/host/compiler_ir.lisp` |
| `src/backend/common.lisp` | `bootstrap/backend/{common,common_types,dispatch}.lisp` |
| `src/backend/x86-64.lisp` | `bootstrap/backend/{x86_calls,x86_calls_types,x86_control,x86_expr,x86_memory,x86_stack,x86_aggregate,x86_function_addresses,lir_emit_x86}.lisp` |
| `src/backend/x86-roots.lisp` | `bootstrap/backend/{x86_roots,root_frame}.lisp` |
| `src/backend/win64-abi.lisp` | `bootstrap/backend/{win64_arguments,win64_frame,win64_probe,win64_roots,win64_aggregate,lir_emit_win64}.lisp`; `bootstrap/win64_module.lisp` |
| `src/backend/aarch64.lisp` | `bootstrap/backend/{aarch64_encode,aarch64_branches,aarch64_frame,a64_aggregate,a64_function_addresses,lir_emit_aarch64}.lisp` |
| `src/backend/aarch64-roots.lisp` | `bootstrap/backend/{a64_roots,root_frame}.lisp` |
| `src/backend/riscv64.lisp` | `bootstrap/backend/{riscv64_encode,riscv64_branches,riscv64_frame,riscv64_memory,rv_aggregate,rv_function_addresses,lir_emit_riscv64}.lisp` |
| `src/backend/riscv64-roots.lisp` | `bootstrap/backend/{rv_roots,root_frame}.lisp` |
| `src/object/elf64.lisp` | `bootstrap/object/{elf64,elf64_calls,elf64_data_imports,elf64_multi,elf64_target_calls}.lisp` |
| `src/object/coff.lisp` | `bootstrap/object/{coff64_layout,coff64_sections,coff64_symbols,coff64_relocations,coff64_calls,coff64_data_imports,coff64_validation}.lisp` |
| `src/ffi/toolchain.lisp` | `bootstrap/host/{compiler_link,compiler_target_options}.lisp`; `bootstrap/host/platform_toolchain.c` |
| `src/ffi/freestanding.lisp` | `bootstrap/host/compiler_link.lisp`; `bootstrap/host/platform_toolchain.c`; `bootstrap/driver.lisp` |
| `src/driver.lisp` | `bootstrap/{driver,driver_effects,driver_inline}.lisp`; hosted orchestration `bootstrap/host/{driver,compiler}.lisp` |
| `src/root-runtime.lisp` | `bootstrap/ir/root_*.lisp`; `bootstrap/backend/*roots*.lisp`; runtime module selection in `bootstrap/host/compiler_link.lisp` |
| `src/cli.lisp` | `bootstrap/host/{compiler,compiler_cli_options,compiler_profile_options,compiler_target_options,compiler_imports,compiler_diagnostics,diagnostics,output}.lisp`; C boundary `bootstrap/host/{platform_stdio.c,platform_toolchain.c}` |
| `src/load.lisp` | Seed load manifest itself; native input ownership is `bootstrap/native-core.lisp`, whose transitive includes define the current native-core subset. The release builder declares the eight complete native generation units and checks their transitive include closure; the frozen manifest and full three-stage release proof remain open. |

Additional native build-host compilation-environment ownership is in `bootstrap/frontend/macros/*.lisp`, `bootstrap/frontend/source.lisp`, `bootstrap/frontend/source_reader.lisp`, and `bootstrap/host/{macro_storage,source_*,environment_*,initialize,storage}.lisp`. In particular, `bootstrap/frontend/source_reader.lisp` owns directive-form reading and identity recognition, while `bootstrap/host/source_environment.lisp` owns package state and typed reader tables across included units. The `bootstrap_source_loader_identities.sh` gate checks source-order package/alias behavior and observable linked output on all four hosted targets; `bootstrap_source_loader_allocations.sh` exercises allocation-failure cleanup with each stage's selected CORE/SOURCE/INPUT/PATH objects on the Linux compiler host. These implement build-host source reading, macro execution, identity/package storage, source loading, and diagnostics that Stage 0 distributes across SBCL and its frontend/driver. The list names the owners; it does not imply every source form or compiler environment feature has been ported.

## Actual M8 gaps and open proofs

The following are genuine seed-to-native or milestone gaps, not the shared exclusions listed above:

| Area | Remaining M8 work |
|---|---|
| Complete source manifest | The hash-checked compiler-input manifest, fresh eight-unit Stage 1/2/3 builder, and fail-closed corpus runner are implemented in the release candidate. No previous `bootstrap_release_sources.json` is carried into this snapshot. After source integration is frozen, generate the 12-cell Stage 0 outcome inventory for every `tests/**/*.lisp` input and all 31 `examples/**/*.lisp` sources, then generate the compiler manifest so its tracked-input hashes include that fresh inventory. Next run all declared owner gates and the parity-required linked example inventory on Stage 1/2/3, then run the complete source/profile/target matrix. Tooling and partial wiring evidence do not establish a release pass. |
| Compilation environment | Native macro evaluation and top-level `eval-when` are bounded subsets. Port the seed's documented compile-time forms and source-order effects, or list any seed-supported form that is intentionally deferred as an explicit M8 parity gap. All compile-time execution stays on the build host. |
| Source loading and identity | Port the seed's supported includes, package/source identity behavior, escaped names, source spelling and diagnostics over the full compiler corpus. Hosted CLI syntax/identity capacity must grow/retry for valid expansion growth; caller-owned library arenas may retain explicit capacity errors. |
| Frontend/IR coverage | Compare every seed-accepted and seed-rejected source form within `docs/core.md` through native analysis and verified HIR/SSA/LIR. Keep parity checks for optimization, effects, dumps and rejection behavior; do not derive support from module names. |
| Target and object coverage | Run the documented core target/profile matrix through object inspection, C ABI comparison and execution where an emulator/runner exists. A target/profile listed by Stage 0 but missing native is a native port gap; unsupported-by-both ABI cases are not. |
| CLI, host services, and artifacts | Match seed-supported CLI/source traversal, link/runtime selection, diagnostics, output cleanup, and no-partial-artifact behavior. Include negative and filesystem cases in the same manifest. |
| Self-hosting stages | Build Stage 1 from the complete frozen seed manifest, then Stage 2 and Stage 3 from the same manifest. Run the same acceptance/rejection, diagnostics, IR, object, interop and runtime corpus on all stages and compare deterministic outputs. M8 remains incomplete until these gates pass. |

Hosted CLI growth now retries only the latched syntax-capacity failure, reparses the same assembled source at a checked larger driver arena, and releases each failed parser/macro attempt before retrying. The native macro-growth gate exercises expansion depths 3–10 on all four hosted targets at O0/O1, including deterministic objects, output preservation on semantic errors, and fixed-capacity caller-owned API behavior. This resolves the earlier depth-4–8 CLI repro; it does not make caller-owned syntax or macro arenas growable.

## Release fixture and gate ownership

The compiler manifest records every test, runtime, source and example input by
hash. The source-status inventory treats ordinary `tests/**/*.lisp` units as
standalone and compiles all 12 declared target/profile cells. Inputs that need
their surrounding gate are assigned explicit owner gates and reasons. In
particular:

| Area | Release owner gates |
|---|---|
| Source-loader identity, included packages, and failure cleanup | `tests/bootstrap_source_loader_identities.sh`; `tests/bootstrap_source_loader_allocations.sh` |
| Managed values, roots, strings, vectors, closures, and aggregates | The managed-runtime gates in the `managed-runtime-and-interop` group, including `tests/bootstrap_managed_values.sh`, `tests/bootstrap_managed_roots.sh`, `tests/bootstrap_byte_strings.sh`, `tests/bootstrap_string_literals.sh`, `tests/bootstrap_native_closures.sh`, `tests/bootstrap_native_vectors.sh`, and the word/integer/float aggregate gates |
| Macro source fixtures and public C/API receivers, including nested patterns, NIL key names, and prefix-allocation rollback | `tests/bootstrap_macros.sh` and `tests/bootstrap_macro_destructuring.sh` (source matrices, C O0/O2 receivers, compiler O0/O1 API receivers, rejection/rollback cases and the SBCL constant/NIL-key oracles) |
| Short hosted source and runtime catalogue capacity | `tests/bootstrap_short_source_capacity.sh`, comparing each generated compiler with Stage 0 on all four hosted targets, including C observations and failed-output preservation |
| VOID condition rejection and output preservation | `tests/bootstrap_void_conditions.sh`, dispatched against each hosted compiler target |
| Example source and linked behavior | `tests/bootstrap_corpus.py`, dispatched for Stage 0 and all three generated compilers by the release runner |

The source fixture owner mappings are generated from the checked gate table;
the release preflight rejects missing paths, stale gate invocation modes,
unowned source units, incomplete target/profile cells, and missing per-stage
owner evidence. The compiler manifest is generated only after the final source
snapshot is frozen.

The earlier 97 top-level compile checks and 74/74 accepted seed/native inputs are parity samples, not a complete source manifest and not object/link/runtime/diagnostic or Stage 1–3 evidence. Likewise, the 31-example inventory and native-core self-compilation do not close M8.
