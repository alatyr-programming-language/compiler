## TYP-13 / Types §9.1 under the CG-7 verification grant (#558). `unchecked e` is a verification MODE,
## not a different value: within its scope the checked-guard family is dropped and, "as an expression it
## yields the inner value" (Grammar §3.7). It therefore never changes the wrapped expression's type or
## value, so every `unchecked` spelling below MUST equal its plain twin. Before the fix the four
## per-backend integer-constant predicates matched `Expr::Num`/`Expr::Bin` only; `Expr::Unchecked` is a
## distinct AST node, so the conversion was skipped and the integer bits were stored raw and read back
## as a denormal (0) on ALL FOUR backends.
##
## Every case is classified, not merely compared, because 0 is BOTH the observed defect (a denormal read
## back) and the commonest default of any broken read: `class` separates a correct value (0) from that
## zero (1), from a magnitude-losing truncation (2), and from anything else (3). The returned code is
## `10 * case + class` of the FIRST failing case, so a failure names the case AND the outcome class;
## 99 is returned only when all nine cases are correct. Every code is below 126 and no two distinct
## outcomes share one (#386): the failure codes run 11..93 and 99 is outside that range, so no broken
## classification can alias onto the success sentinel. Case 8 is the negative seam (#444): no other cross-backend fixture reads a
## negative number back, and `scvtf`/`cvtsi2sd`/`f64.convert_i64_s` are all SIGNED conversions. It reads
## back through `i64(f)`, not `u64(f)`, because an unsigned truncation of a negative double traps under
## wasmtime and saturates elsewhere — a separate divergence this fixture must not depend on.
classify := fn(got : i64, want : i64) -> u64 {
  if got == want { return 0 }
  if got == 0 { return 1 }
  if want > 0 and got > 0 and got < want { return 2 }
  if want < 0 and got < 0 and got > want { return 2 }
  return 3
}

main := fn() -> u64 {
  ## 1 — f64, bare literal.
  c1 : f64 = unchecked 3
  k1 := classify(i64(c1), 3)
  if k1 != 0 { return 10 + k1 }

  ## 2 — f32, bare literal.
  c2 : f32 = unchecked 7
  k2 := classify(i64(c2), 7)
  if k2 != 0 { return 20 + k2 }

  ## 3 — f64, folded `Bin` under the grant.
  c3 : f64 = unchecked (1 + 2)
  k3 := classify(i64(c3), 3)
  if k3 != 0 { return 30 + k3 }

  ## 4 — f32, folded `Bin` under the grant.
  c4 : f32 = unchecked (20 * 2)
  k4 := classify(i64(c4), 40)
  if k4 != 0 { return 40 + k4 }

  ## 5 — the f64 spellings agree. The plain twin was already correct, so this is the equality the
  ## grant's definition demands, measured directly rather than inferred from two separate constants.
  p5 : f64 = 3
  k5 := classify(i64(c1), i64(p5))
  if k5 != 0 { return 50 + k5 }

  ## 6 — the f32 spellings agree.
  p6 : f32 = 7
  k6 := classify(i64(c2), i64(p6))
  if k6 != 0 { return 60 + k6 }

  ## 7 — the f32 exact-representability boundary survives the grant: 16777217 - 1 is the largest
  ## consecutive integer f32 still holds exactly, so a lost conversion here shows up as class 2 or 3
  ## rather than as the class-1 zero the bare literals produce.
  c7 : f32 = unchecked (16777217 - 1)
  k7 := classify(i64(c7), 16777216)
  if k7 != 0 { return 70 + k7 }

  ## 8 — NEGATIVE (#444). The conversion is signed on every backend; a sign lost here reads back as a
  ## large positive (class 3), not as the zero the other cases produce.
  c8 : f64 = unchecked (0 - 5)
  k8 := classify(i64(c8), 0 - 5)
  if k8 != 0 { return 80 + k8 }

  ## 9 — nested grants collapse to the same value: `unchecked` is idempotent as a mode.
  c9 : f64 = unchecked (unchecked 3)
  k9 := classify(i64(c9), 3)
  if k9 != 0 { return 90 + k9 }

  99
}
