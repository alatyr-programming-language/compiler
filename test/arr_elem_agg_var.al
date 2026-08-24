## e2e — whole-STRUCT element WRITE to a LOCAL struct-element array from a struct VAR (`arr[i] = r`).
## The single-word fallback kept only word 0 (`a`), dropping `b` (was exit 12). Lower now copies the
## var's `estride` frame words straight to the element base. A second element is written to prove the
## element stride (no cross-element clobber).
Rec := struct { a : i64, b : i64 }
main := fn() -> u64 {
  mut arr : [Rec; 4] = [Rec(a = 0, b = 0), Rec(a = 0, b = 0), Rec(a = 0, b = 0), Rec(a = 0, b = 0)]
  r := Rec(a = 5, b = 25)
  q := Rec(a = 8, b = 4)
  arr[1] = r
  arr[2] = q
  u64(arr[1].a + arr[1].b + arr[2].a + arr[2].b)   ## 5+25 + 8+4 = 42
}
