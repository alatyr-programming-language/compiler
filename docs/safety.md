# Safety, ownership, and ABI contract

Alatyr's safety model is expressed in the language specification and checked
at the boundary where a value becomes an address or an external call. This
repository documents the implementation boundary so a backend change cannot
turn an unchecked operation into an accidental safe guarantee.

## Ownership and views

`@owning` values are linear resources. A value is consumed by its release
operation exactly once; a borrow (`ptr(T)` or `ptr(mut T)`) does not transfer
ownership and cannot outlive the owner. Arena handles are scoped to their arena
and are not a substitute for an owning OS resource. `in out` parameters make a
mutation explicit, while `in` parameters are read-only borrows.

`std::os::OsArena` demonstrates the distinction: `arena` returns an owning
`mmap` handle, `region` returns a non-owning allocator view, and `free` consumes
the handle. The compiler must reject use after consume, duplicate release, and
escaping borrowed references.

## Unsafe and manual boundaries

`unchecked` is required for raw pointer arithmetic, syscall results, and
bit-level reinterpretation whose preconditions cannot be proved by the type
checker. `@abi(...)` declarations are body-less foreign boundaries; each call
site owns the argument and result contract. Manual memory and raw ABI code must
be isolated in a small wrapper whose safe-facing API states the preconditions.

An unchecked operation is not a license to infer an ABI. The target support
matrix is authoritative for where a syscall or assembler is available; other
targets fail closed with a located diagnostic.

## Negative coverage

The existing safety fixtures cover use-after-consume, double free, borrowed
escape, mutable aliasing, unchecked requirements, and syscall result handling.
The package and full gates must keep these negative cases active. New wrappers
must add a focused fixture when they introduce a new ownership or ABI shape.

## ABI status

The Linux x86_64 syscall ABI is the only production OS ABI in v1. AArch64 and
RISC-V lowering currently serve cross-assembly/test-only probes where the host
toolchain provides an assembler; they are not runtime support claims. 32-bit
and non-Linux ABIs remain explicit roadmap items until their calling convention,
syscall layer, and conformance fixtures are specified together.
