## e2e — whole-STRUCT element WRITE to a LOCAL struct-element array from a struct-RETURNING CALL
## (`arr[i] = mk()`) AND from an if-EXPRESSION with a CALL branch (`arr[i] = if c { mk() } else { … }`).
## Both previously FAILED LOUD (a call's fields ride return registers the element-address computation
## would clobber; a branch is neither a struct literal nor a var). Lower now materializes the call/branch
## aggregate into the agg-temp block and copies all `estride` element words UP to the element base (word
## k at +k*8, ascending) — both words survive, neighbours untouched. Neutral: src/+lib/ index only scalar
## arrays + slice params, never a local aggregate array, so this path never fires on the self-build.
P := struct { a : u64, b : u64 }
mk := fn() -> P { P(a = 40, b = 2) }
main := fn() -> u64 {
  mut arr : [P; 2] = [P(a = 0, b = 0), P(a = 0, b = 0)]
  arr[0] = mk()                                       ## struct-returning CALL RHS
  c := true
  arr[1] = if c { mk() } else { P(a = 0, b = 0) }     ## if-EXPRESSION with a CALL branch
  mut r : u64 = 0
  if arr[0].a + arr[0].b == 42 { r = r + 21 }
  if arr[1].a + arr[1].b == 42 { r = r + 21 }
  r                                                   ## 42 iff BOTH deliveries copied every word
}
