## e2e (I11 correct-or-trap) — the emit-to-stdout surfaces reject an UNBOUND NAME too, not only a type
## mismatch: the point is that the whole type-checker runs on those paths, not one hand-picked check.
##
## A local declared with an explicit type and initialized from a name that no declaration binds. The
## `-o` build path rejects it with a located diagnostic naming the kind and the line, exit 1.
## MEASURED before the check pass landed, on this exact file: `alatyr wat` exit 0 with 35 lines on
## stdout, `alatyr aarch64` exit 0 with 44 lines, `alatyr riscv64` exit 0 with 54 lines — the compiler
## emitted a reference to a name it had just failed to resolve. AFTER: all three exit 1 with zero bytes
## on stdout and the same located diagnostic the `-o` path prints, naming line 11.
main := fn() -> u64 {
  n : u64 = no_such_declaration_anywhere
  return 0
}
