## Direct `return <EnumLit with a MULTI-WORD payload>`: every payload word must reach the caller.
## Regression lock for a silent miscompile where the enum-return emission delivered only the tag +
## payload word 0, DROPPING payload words 1..N (`return E.B(40, 2)` matched to p+q returned 40, not
## 42 — q read 0). The local-store path (`emit_enum_assign`) and the enum-VAR return already stored
## every word; only the direct-enum-LITERAL return truncated. Fixed by delivering each payload field
## into a consecutive return register (field k -> payload reg k+1), the return-register dual of the
## var-return path.

E2 := enum { A(u64), B(u64, u64) }
E3 := enum { A(u64), B(u64, u64, u64) }

## direct return of a 2-word-payload variant
mk2 := fn(x : u64) -> E2 { return E2.B(38, 2) }

## direct return of a 3-word-payload variant
mk3 := fn(x : u64) -> E3 { return E3.B(1, 1, 0) }

main := fn() -> u64 {
  mut a := 0
  match mk2(1) {
    E2::A(v) => { a = v }
    E2::B(p, q) => { a = p + q }        ## 38 + 2 = 40
  }
  match mk3(1) {
    E3::A(v) => { a = a + 100 }
    E3::B(p, q, r) => { a = a + p + q + r }  ## 40 + 1 + 1 + 0 = 42
  }
  return a
}
