## DO NOT REGISTER IN scripts/e2e.sh YET — it would go RED on the sweeps, and correctly so.
##
## e2e (deferred) — Verification §: an `unchecked` sum whose partner is a bare INTEGER
## LITERAL must keep its operand's UNSIGNEDNESS. A literal has no type of its own and takes its
## partner's, so `w + 6` over `w : u64` is a `u64` sum.
##
## STATUS: x86_64 answers 42 (CORRECT). The three non-x86 backends now use the same proof: the
## unchecked arithmetic `w + 6` inherits `w : u64` through its bare literal partner, and the final
## comparison uses the unsigned ordering condition. Before this lane they answered 3 — a valid binary,
## normal exit, WRONG value — because their arithmetic peel required BOTH `Bin` operands PROVEN.
##
## PRE-EXISTING and NOT a regression — the registered `unchecked_keeps_unsignedness` fixture only
## exercises TYPED partners (`w + d` over two `u64`s), so the literal shape was never covered. It is
## also NOT the mixed-signedness bug that `unchecked_mixed_signedness.al` locks: there x86 was the
## wrong one and now matches the other three; here x86 is the RIGHT one and the other three must
## catch up. Fixing it belongs to the backend lane (src/aarch64.al, src/riscv64.al, src/wat.al): the
## `Bin` arm now has the same "one operand proven unsigned, the other a bare integer literal" allowance
## that x86's inferred arithmetic type and `expr_is_int_lit` ordering guard provide. Register this the
## day all four agree.
main := fn() -> u64 {
  w : u64 = 18446744073709551610      ## 2^64 - 6
  s := unchecked (w + 6)              ## the partner is a bare LITERAL — wraps to 0
  if s < w { return 42 }              ## 0 < 2^64-6 unsigned -> TRUE
  return 3
}
