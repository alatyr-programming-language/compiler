## e2e (Hunk C) — the ERGONOMIC UFCS `o.unwrap()` / `o.expect(msg)` form on a generic `Option(T)`
## whose payload `T` resolves to a MULTI-WORD struct (`Rec`, 2 words). The UFCS spelling desugars
## with the `T` type-arg OMITTED (the receiver `o` is a value arg), so the instance must be re-tagged
## by the CONCRETE payload type (`Rec`) at BOTH the mono pre-pass and emit — mangling to EXACTLY the
## same `unwrap__Rec` / `expect__Rec` instance the prefix `unwrap(Rec, o)` produces (`unwrap_struct_payload`).
## `Option(Rec).Some(v) => v` is delivered via the struct-return convention (Hunk A). Both sum to 42.
Rec := struct { a : i64, b : i64 }

getit := fn() -> Option(Rec) { Option(Rec).Some(Rec(a = 12, b = 30)) }

main := fn() -> u64 {
  o := getit()
  r := o.unwrap()                  ## Some(Rec{12,30}) -> Rec ; None-arm is a panic
  o2 := getit()
  e := o2.expect("should be Some")
  s := (r.a + r.b) + (e.a + e.b)   ## 42 + 42 = 84
  return unchecked u64(s - 42)     ## 42
}
