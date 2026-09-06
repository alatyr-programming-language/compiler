## e2e (#411) — writing THROUGH a str literal. `"abc"[0] = 65` names no storage: a literal's bytes
## are emitted once into read-only data and the pair that denotes them is a value (Types §7; Memory
## §1.6), so Grammar §3.3's `place` — rooted at an ident, a path or a `deref(…)` — cannot derive a
## literal-led index chain, and the store below has nothing to write into. This is NOT the address-of
## form #405 fenced in lower: the line was not recognized as a statement at all, so it fell to the
## trailing-expression path, where the `=` was consumed as an opening parenthesis, the `65` as the
## parenthesized expression and the `7` below as its closing token. The build then succeeded and the
## program exited 65, never reaching the declared result — the silent wrong value I11 forbids. The
## parser refuses it now, upstream of x86_64, AArch64, RISC-V64 and WAT alike; the harness asserts the
## wording and the reported line, which are deliberately not quoted here, and that no artifact remains.
main := fn() -> u64 {
  "abc"[0] = 65
  7
}
