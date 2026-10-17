# Hosted runtime (M4)

[Documentation](README.md) / Hosted runtime

The first hosted runtime supports x86-64 Linux, x86-64 Windows, AArch64
Linux, and RISC-V64 Linux as a single-threaded
module set. Its
public C interface is [runtime/psl_runtime.h](../runtime/psl_runtime.h), ABI
version 1. It is selected only by hosted source that uses managed values.
Ordinary typed objects and binaries have no PSL runtime dependency.

## Values and roots

`value` is an opaque 64-bit source type. Runtime values use these bit patterns:

| Value | Representation |
| --- | --- |
| Fixnum | Signed 63-bit payload shifted left one bit, with bit 0 set; valid range is −2^62 through 2^62−1. |
| `nil` | Immediate value `2`. |
| `t` | Immediate value `6`. |
| Managed object | Aligned heap address with its low three bits clear. |

The object layout is private. The runtime has cons, byte-string, symbol,
package, closure, and VALUE-vector objects. C functions that hold values across an allocation
register them with `psl_rt_push_roots`, then remove the frame with
`psl_rt_pop_roots`. Stage 0 emits registered root frames around potentially
allocating/collecting calls in managed functions. Only `value` virtual registers
enter the root array; machine integers and raw pointers are excluded. Arguments
are saved before registration, and unused managed slots start as NIL. The array
is synchronized before calls and removed before return. These typed roots may
retain dead temporaries until function exit.
The default collector additionally scans the stack conservatively.
Objects reachable from either root source are marked; the
rest are swept without moving live objects. The collector runs on the only
supported thread. Conservative false positives can retain an unreachable
object until a later collection.

The runtime starts lazily. `startup.c` asks `platform_linux.c` or
`platform_windows.c` for the current thread's stack bounds. Neither startup nor
platform code is built into the
language frontend. The collector runs automatically after its allocation
threshold or explicitly through `collect-garbage`.

The C API additionally exposes `psl_rt_collect_precise`, which marks only
registered frames and permanent roots, and `psl_rt_cons_precise`, whose automatic
collection uses the same rule. The constructor registers its two arguments
internally; callers must register every other live managed value held across
these operations. Unregistered pointer bits on the C stack do not retain an
object. These functions share the existing nonmoving heap and ABI value layout.
Stage 0's ordinary runtime operations continue to use the conservative
collector, while its emitted frames also support the precise C boundaries.
Imports annotated `:no-allocation` must exclude collection as well as allocation.
Root registration selects the GC runtime module explicitly; certified
allocation-free managed functions remain free of this extra dependency.
The native compiler also emits precise root frames for its documented hosted
source subset. Native managed compiler collections remain M8 work.

Precise VALUE vectors use a stable managed header and separate managed storage.
`psl_rt_make_value_vector_precise` and `psl_rt_value_vector_push_precise` root
their live arguments across allocation. Growth copies initialized values and
publishes the new storage without changing vector identity. Logical length is
distinct from capacity; spare slots hold NIL and are traced. Length/ref/set
reject wrong kinds and out-of-bounds indices and do not allocate. Stage 0 and
native hosted source use the same five PSL vector operations. Compiler-owned
collection migration remains open.

The native compiler's macro registry uses opaque value handles as C-owned
roots. Handle tokens are monotonic, nonzero, and never reused. Opening creates
an active NIL root; get/set do not allocate or collect; close accepts any
active token regardless of close order and rejects stale or zero tokens.
Precise collection marks values held by active handles. These handles are a
compiler-host service; freestanding user objects do not acquire a GC dependency
unless their own source explicitly requires managed runtime modules.

## Modules and linking

The linker compiles the transitive dependency closure of the modules used by
the source. `src/ffi/toolchain.lisp` records the dependency edges:

| Module | Direct dependencies | Provides |
| --- | --- | --- |
| `value` | none | Fixnum, truth, and identity operations. |
| `gc` | `startup` | Heap, root registration, marking, and sweeping. |
| `startup` | `platform` | Lazy stack-bound setup. |
| `platform` | none | Selected OS stack-bound query. |
| `cons` | `gc` | Cons allocation and access. |
| `string` | `gc` | Mutable byte strings. |
| `symbol` | `string` | Symbol allocation and names. |
| `package` | `symbol` | Packages and symbol interning. |
| `closure` | `gc` | Closure allocation and invocation. |
| `vector` | `gc` | Precise VALUE vectors with stable identity and growing storage. |
| `values` | `gc` | Two-value return storage. |

`pslcc -c` leaves runtime calls as ELF or COFF relocations and does not compile C
runtime modules. For executables, static libraries, and shared libraries,
`pslcc` compiles only selected modules and passes their objects to the system
linker or archiver. A typed program selects no modules. Generated lambda
functions have local ELF symbols, so separately compiled closure-bearing
objects can link into the same program. When `--link-input` names another
object or archive, the linker also reads its undefined `psl_rt_` symbols and
selects the corresponding modules. It also recognizes known runtime imports
in the PSL object itself, including explicitly imported precise constructors.

## Hosted source subset

Use `--profile=hosted` for `value`, integer fixnum literals in a `value`
position, UTF-8 string literals, `nil`, `t`, `cons`, `car`, `cdr`, `eq`,
`make-symbol`, `symbol-name`,
and `package-name`. `if` treats a managed `nil` as false and every other
managed value as true. PSL extensions provide `box-fixnum`, `unbox-fixnum`,
`make-byte-string`, `string-byte`, `set-string-byte`,
`make-package-from-name`, `intern-symbol`, and `collect-garbage`.

String literals copy a private byte span into a fresh mutable string on each
evaluation. Their explicit byte length preserves embedded zero bytes. Stage 0
uses the conservative copy constructor; the native compiler uses its precise
counterpart with explicit root frames. Both constructors perform one runtime
copy rather than emitting one mutation call per literal byte.

A lexical `#'(lambda (argument) ...)` captures visible `value` variables and
can be called with `funcall`. This first closure convention has one argument
and one result. `(multiple-value-bind (first second) (values a b) ...)`
provides two managed values in both Stage 0 and the native hosted compiler. The
binding requires two distinct nonconstant names and a direct `values` expression.
Arguments evaluate once in source order in the outer lexical environment, and
both bindings are installed before the body starts. General lambda lists and full
Common Lisp multiple-value propagation remain for later milestones. These
limits are diagnosed rather than given different silent semantics.

`without-allocation` verifies the transitive direct-call graph before code
generation. Runtime allocation, unknown imports, and indirect closure calls
invalidate the guarantee. An imported function can declare
`:no-allocation` after its result type; the compiler treats that as a trusted
effect declaration. Explicit collection conservatively invalidates a certified
region; macro expansion on the build host does not count as target allocation.

The [hosted examples](../examples/README.md#hosted-values) run each facility
without a user C source or harness. `sh tests/smoke.sh` checks behavior at
`-O0` and `-O1`, selected runtime symbols, and typed binary exclusion.
`sh tests/runtime.sh` exercises the C ABI modules and reachable/unreachable
collector behavior.

`sh tests/runtime_precise.sh TARGET` checks explicit roots, unregistered stack
values, shared lists, temporary constructor arguments and automatic collection
on the four hosted targets. It also links through `pslcc` at O0/O1 to verify
runtime selection from the new symbols in a C link input. Collector/cons code
is checked at C O0/O2; the OS stack-bound adapter keeps its baseline C build.

`sh tests/managed_roots.sh TARGET` links generated PSL with an independent C
caller and precise collector. It checks typed roots against untyped pointer
bits, locals, joins, recursion, loops, constructor arguments, large frames,
stack/float/aggregate ABI transport, root release and deterministic O0/O1
objects. Its Linux API gate rejects malformed catalogues and frame lifetimes,
missing synchronization, late argument saves and reserved-symbol conflicts.

The native compiler uses the precise symbol/package constructor and interning
entries. They protect managed arguments internally during allocation; compiled
callers publish their other live values through explicit root frames. Existing
conservative C entries remain available to Stage 0. Runtime symbol/package
cycles are traced and become collectible after all registered roots are removed.


The two-value buffer uses static state, matching the single-thread runtime. Its
latest pair is permanently rooted until overwritten by `psl_rt_values2`; compiled
binding locals remain independently rooted. The first VALUES call registers the
buffer. `psl_rt_nth_value` and `psl_rt_value_count` allocate nothing, including
before initialization. This avoids an emulated TLS allocation in the Windows
accessor. `tests/bootstrap_multiple_values.sh` checks cold accessors, exact C ABI,
O0/O1 execution, source order, nested bindings and precise collection on all four
hosted targets.

Precise closure entries `psl_rt_make_closure_precise` and
`psl_rt_call_closure_precise` protect their environment, closure and argument
through allocation or collection. Native source closures select these explicit
entries and the closure/GC/startup/platform dependency closure. Generated body
addresses use PSL-owned same-text instruction encoding and patching. Closure
allocation and indirect invocation cannot certify a WITHOUT-ALLOCATION region.
`tests/runtime_precise_closures.sh` checks capture/argument lifetimes and release;
`tests/bootstrap_native_closures.sh` checks native and Stage 0 source behavior.
