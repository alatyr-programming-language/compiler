## e2e (I11 correct-or-trap) — the third check kind on the emit-to-stdout surfaces: a DUPLICATE
## declaration at module scope. Together with the type-mismatch and unbound-name fixtures this pins
## all three verdicts the check pass can return, on each of the three non-x86 emit surfaces.
##
## Two module-level declarations of one name. The `-o` build path rejects it with a located diagnostic
## naming the kind and the line, exit 1. MEASURED before the check pass landed, on this exact file:
## `alatyr wat` exit 0 with 34 lines on stdout, `alatyr aarch64` exit 0 with 48 lines, `alatyr riscv64`
## exit 0 with 58 lines — each backend picked one of the two declarations and emitted it. AFTER: all
## three exit 1 with zero bytes on stdout and the same located diagnostic the `-o` path prints, naming
## line 12.
value := 1
value := 2

main := fn() -> u64 {
  return 0
}
