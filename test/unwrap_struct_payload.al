## e2e — the `unwrap(T, o)` / `expect(T, o, msg)` PREFIX form on a generic `Option(T)` whose payload
## `T` resolves to a MULTI-WORD struct (`Rec`, 2 words). The generic enum-value param `self : Option(T)`
## must be sized/materialized/matched as the concrete `Option(Rec)` (disc + 2-word payload) and the
## `Some(v) => v` arm delivered via the struct-return convention — the enum-value-param payload
## substitution (Hunk A). The `None => panic(msg)` arm (not taken here) must lower through the aggregate
## return path without mangling `panic` (Hunk B). Both `unwrap` and `expect` sum to 42 → exit 42.
Rec := struct { a : i64, b : i64 }

getit := fn() -> Option(Rec) { Option(Rec).Some(Rec(a = 12, b = 30)) }

main := fn() -> u64 {
  o := getit()
  r := unwrap(Rec, o)              ## Some(Rec{12,30}) -> Rec ; None-arm is a panic (Hunk B)
  o2 := getit()
  e := expect(Rec, o2, "should be Some")
  s := (r.a + r.b) + (e.a + e.b)   ## 42 + 42 = 84
  return unchecked u64(s - 42)     ## 42
}
