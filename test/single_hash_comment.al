## Grammar §2.5: `#` is a line comment (`#` {any-char}) and `##` a doc-comment —
## both must skip to end-of-line. The self-host lexer previously matched ONLY `##`
## (a `b == 35 and peek(…) == 35` gate) and a lone `#` fell through as an unrecognized
## token (kind 23), which the parser mis-parsed as a `(…)` expression, cascading into
## a spurious "unbound name". This file exercises a bare `#` comment on every line
## kind: standalone, mid-statement trailing, and inside a comptime block — the program
## must type-check + run exactly as if the comments were `##`.
##
## The comptime block is gated on `target.arch != Arch.i386` — an arch NO backend in this corpus
## emits, so the gate is TRUE and the block RUNS on every target alike (`b` 1 → 2, result 44). The
## `!=` spelling doubles as a regression guard for the arch fold, which used to ignore the operator
## and take the `==` branch (so the block would NOT have run → 43). It used to read
## `comptime if a == 42` over a RUNTIME local, which is not a comptime-known controlling expression
## (Comptime §9.1) and is now a located reject; and after that `!= Arch.x86_64`, whose value flipped
## per target once the non-x86 backends stopped folding `target.arch` as x86_64 (Tooling §2.7) — 45
## on aarch64/riscv64/wat, 44 on x86_64. `Arch.i386` makes the emission, and the answer, uniform.

# top-level single-hash comment
main := fn() -> u64 {
  a := 40 + 2                    # trailing single-hash comment
  b := 1                         # another trailing
  # full-line inside the body
  comptime if target.arch != Arch.i386 {
    # comment inside a comptime block
    b = b + 1                  # trailing in comptime
  }
  ## doc-comment still works alongside single-hash
  ## a := 999
  return a + b                   # 42 + 2 = 44
}
