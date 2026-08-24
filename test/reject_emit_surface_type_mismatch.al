## e2e (I11 correct-or-trap) — the three EMIT-to-stdout surfaces must TYPE-CHECK before they emit.
##
## `alatyr wat|aarch64|riscv64 <file>` used to emit whatever the PARSER accepted and then return 0
## unconditionally: the parser's own reject fired, but no type-checker ran anywhere on those paths, so
## a program the `-o` build path refuses came back as a complete, legitimate-looking module on stdout
## with a success exit status. Machine code for a program the compiler already knows is wrong is worse
## than a missing feature, and it silently distorted every gate that reads those surfaces — three of
## the four columns of EVERY reject fixture recorded "accepted".
##
## THIS program is the ill-typed one the roadmap entry measured: a `bool` local initialized from an
## integer literal, which the `-o` path rejects with a located diagnostic naming the kind and the line
## and exits 1. MEASURED before the check pass landed, on this exact file: wat exit 0 with 34 lines on
## stdout, aarch64 exit 0 with 44 lines, riscv64 exit 0 with 54 lines. AFTER: all three exit 1, write
## ZERO bytes to stdout, and print the same located diagnostic the `-o` path prints, naming line 16.
main := fn() -> u64 {
  ok : bool = 1
  return 0
}
