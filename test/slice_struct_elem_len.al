## e2e (Types §9.4 / §7.2 — `.len` of a STRUCT-element slice LOCAL). `s := arr[lo..hi]` over an array
## of structs stores {data ptr, len} DIRECTLY in the slice local's two frame words, exactly like a
## scalar-element slice view — but it carries the ELEMENT TYPE span in the slot's `sns`/`snl` (so
## `s[i].field` resolves), so it matched neither of the two "read the len word directly" markers and
## fell to the by-reference double-deref: `s.len` / `s.len()` read `8(data_ptr)` = the first element's
## SECOND word. A SILENT MISCOMPILE (a normal exit with a wrong length: 2 instead of 3 here, which then
## silently truncates every `for`/bounds use built on it). A slice/array PARAM (whose slot really does
## hold a POINTER to the caller's {ptr,len} block) keeps the double-deref and is told apart by its
## `name : T` type ANNOTATION — the slot entry alone cannot distinguish the two.
## Locks all four shapes against each other:
##   s  = arr[0..3]  -> .len 3, .len() 3, s[0].x 1     (full-range struct-element slice LOCAL)
##   r  = arr[1..3]  -> .len 2, r[0].x 3                (offset slice: len must not track the data)
##   n  = nums[0..4] -> .len 4                          (scalar-element slice LOCAL, unchanged path)
##   take(arr[0..3]) -> .len 3                          (struct-element slice PARAM, unchanged path)
## total = (3 + 3 + 1) + (2 + 3) + 4 + 3 = 7 + 5 + 4 + 3 = 19.
## NB the result MUST stay < 126 (WASI `proc_exit` accepts only [0,126) — the WASM sweep runs this).
Pt := struct { x : u64, y : u64 }
take := fn(s : Slice(Pt)) -> u64 {
  return u64(s.len)
}
main := fn() -> u64 {
  arr := [Pt(x = 1, y = 2), Pt(x = 3, y = 4), Pt(x = 5, y = 6)]
  nums := [10, 20, 30, 40]
  s := arr[0..3]
  r := arr[1..3]
  n := nums[0..4]
  a := u64(s.len) + u64(s.len()) + u64(s[0].x)
  b := u64(r.len) + u64(r[0].x)
  c := u64(n.len)
  return a + b + c + take(arr[0..3])
}
