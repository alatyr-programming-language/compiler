## FN-6 §6.2 regression, WAT emitter — the unsupported-construct BREADCRUMB must never change what the
## surrounding emitted text means. A capturing closure passed BY VALUE to a non-forwarding HOF hits two
## out-of-scope WAT paths at once: the bare closure VALUE at the call site (there is no code-pointer /
## funcref model on wasm yet) and the indirect call through the callable param inside the specialized
## `__hoflam<fnpos>` clone. Both leave an `(unreachable)` plus a note saying which construct it was.
##
## The note used to be written in WAT's LINE-comment form, and the call-site one sits INSIDE an
## s-expression — so it swallowed the rest of that call (its remaining operands and its own closing
## paren), the module lost its balance, and the next module-level function definition read as a
## continuation of the previous function's body. wat2wasm then stopped at that definition and the whole
## file failed to assemble. Written in the BLOCK form the note is closed explicitly, so the module is
## well formed, wat2wasm accepts it, and the program TRAPS at the `(unreachable)` — a trap is an
## acceptable outcome for a construct the backend does not model; text the assembler refuses is not.
##
## PRE-FIX MEASUREMENT (this tree's parent commit, `alatyr wat` piped to wat2wasm): the assembler
## refused the file at line 43, pointing at the clone's own `(func $__hoflam<fnpos> …` header and
## calling that `func` an unexpected token where it wanted an expr — i.e. it never saw the end of
## `$main`'s body. (The diagnostic is PARAPHRASED on purpose: a header that quotes its own needle
## verbatim makes a grep-based check pass on an unfixed tree, which has happened twice here.)
##
## Deliberately NOT a copy of `twice_capture`: three calls of the callable, so the HOF clone plants the
## note three times in one function body, and one bare closure value at the call site.
##
## MEASURED, all four backends: x86_64 = 42 (c := 4; thrice(f, 10) = (10+4) * 3), and a clean TRAP on
## each of the other three — wasm 134 at the `(unreachable)`, aarch64 and riscv64 133 (SIGTRAP), since
## none of the three models an indirect call through a callable param. The trap is the POINT here: what
## this fixture pins is that every backend produces text its assembler ACCEPTS, so the failure is the
## program's own fail-loud rather than the emitter handing the toolchain something unparsable.
thrice := fn(g : u64, x : u64) -> u64 { return g(x) + g(x) + g(x) }
main := fn() -> u64 {
  c := 4
  f := fn(n : u64) -> u64 { return n + c }
  return thrice(f, 10)
}
