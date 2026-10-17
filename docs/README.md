# PSL documentation

[Project](../README.md) / Documentation

Start with a working program, then use the implemented contract for precise
behavior. The design specification describes the larger language; the roadmap
records which gates have passed.

## Use the compiler

| I want to… | Read |
| --- | --- |
| Build PSL and compile my first program | [Getting started](getting-started.md) |
| Find a runnable language or C interop example | [Example catalogue](../examples/README.md) |
| Check accepted syntax, types, profiles, or a limitation | [Implemented language contract](core.md) |
| Understand managed values, roots, and runtime linking | [Hosted runtime](runtime.md) |
| Use or test the compiled native compiler | [Native bootstrap guide](../bootstrap/README.md) |
| Reproduce the complete M8 bootstrap gate | [Release verification](bootstrap-release.md) |

## Work on the compiler

| I want to… | Read |
| --- | --- |
| Find the module that owns a feature | [Architecture](architecture.md) |
| Follow HIR, SSA, LIR, and the compiler-library API | [Compiler pipeline](compiler.md) |
| Understand the intended language and portability rules | [Language design](specification.md) |
| See current support and the remaining release work | [Roadmap](roadmap.md) |
| Change code and choose verification | [Contributor instructions](../AGENTS.md) |
| Trace an earlier implementation slice or proof | [Milestone notes](history/milestone-notes.md) and [native component notes](history/native-bootstrap-notes.md) |

## Two compiler implementations

`./pslcc` is the SBCL-hosted Stage 0 seed. `make native` uses that seed to build
`build/pslcc-native`, whose compiler modules are written in PSL. The native
compiler has its own documented source limits; a feature supported by the seed
may still need a native port.

M8 remains in progress until fresh Stage 1, Stage 2, and Stage 3 builds pass the
complete declared corpus and deterministic Stage 2/3 comparisons. The hosted
profile does not yet claim ANSI Common Lisp conformance.
