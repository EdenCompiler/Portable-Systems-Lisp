# Portable Systems Lisp

Portable Systems Lisp is an experimental native Lisp compiler. The repository
currently contains the first Stage 0 vertical slice, implemented in SBCL.
Standalone source uses ordinary Lisp function forms:

```lisp
(defun add42 (value)
  (declare (type u64 value) (returns u64) (c-export :c))
  (wrap+ value 42))
```

Explicit C integration uses `ffi:source`, `ffi:import-function`, and
`ffi:call`; see [the C source example](examples/ffi_source.lisp).
See [the implemented core](docs/core.md) for exact language and target support.
See [the source organization](docs/architecture.md) for module responsibilities.
See [milestone status](docs/roadmap.md) for the remaining work.
See [repository instructions](AGENTS.md) for implementation rules.

```sh
./pslcc -c examples/add.lisp -o /tmp/add.o
cc examples/harness.c /tmp/add.o -o /tmp/psl-example
/tmp/psl-example
```

Run `sh tests/smoke.sh` to check object generation, C interoperability, and
deterministic output. SBCL, `cc`, `readelf`, `nm`, and `cmp` are required.

This is not yet a hosted Common Lisp implementation. The
[roadmap](docs/roadmap.md) tracks completed proofs and incomplete milestones.
