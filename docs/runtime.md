# Hosted runtime (M4)

The first hosted runtime supports x86-64 Linux and Windows as a single-threaded
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
package, and closure objects. C functions that hold values across an allocation
register them with `psl_rt_push_roots`, then remove the frame with
`psl_rt_pop_roots`. Compiled PSL stack slots are scanned conservatively at a
collection point. Objects reachable from either root source are marked; the
rest are swept without moving live objects. The collector runs on the only
supported thread. Conservative false positives can retain an unreachable
object until a later collection.

The runtime starts lazily. `startup.c` asks `platform_linux.c` or
`platform_windows.c` for the current thread's stack bounds. Neither startup nor
platform code is built into the
language frontend. The collector runs automatically after its allocation
threshold or explicitly through `collect-garbage`.

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
| `values` | `gc` | Two-value return storage. |

`pslcc -c` leaves runtime calls as ELF or COFF relocations and does not compile C
runtime modules. For executables, static libraries, and shared libraries,
`pslcc` compiles only selected modules and passes their objects to the system
linker or archiver. A typed program selects no modules. Generated lambda
functions have local ELF symbols, so separately compiled closure-bearing
objects can link into the same program. When `--link-input` names another
object or archive, the linker also reads its undefined `psl_rt_` symbols and
selects the corresponding modules.

## Hosted source subset

Use `--profile=hosted` for `value`, integer fixnum literals in a `value`
position, UTF-8 string literals, `nil`, `t`, `cons`, `car`, `cdr`, `eq`,
`make-symbol`, `symbol-name`,
and `package-name`. `if` treats a managed `nil` as false and every other
managed value as true. PSL extensions provide `box-fixnum`, `unbox-fixnum`,
`make-byte-string`, `string-byte`, `set-string-byte`,
`make-package-from-name`, `intern-symbol`, and `collect-garbage`.

A lexical `#'(lambda (argument) ...)` captures visible `value` variables and
can be called with `funcall`. This first closure convention has one argument
and one result. `(multiple-value-bind (first second) (values a b) ...)`
provides two managed values; the binding form currently requires a direct
`values` expression. General lambda lists and full
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
