## e2e — returning `Slice(T)` BY VALUE (spec §7.2 / Types §9.4). A slice is a 2-word {ptr, len}
## aggregate returned via the register convention (ptr/%rax, len/%rdx). Formerly a SILENT MISCOMPILE:
## a `-> Slice(T)` return bound as a BARE SCALAR (dropping `.ptr`/`.len`) so `r.len` read 0 and `r[i]`
## read garbage — even when bound. This program has NO prelude/lib import, so the `Slice` type-decl is
## ABSENT from the compiler's decl table (the `slice_ret_call` binding + `fn_returns_slice` return path).
## Exercises the result BOUND (`r.len`, `r[i]`, `for x in r`) AND DIRECT (`get(...).len`). Returns 42.
get := fn(s : Slice(u64)) -> Slice(u64) { return s }

main := fn() -> u64 {
  xs := [10, 20, 12, 40]
  r := get(xs[0..4])

  ## bound `.len` (was 0)
  if r.len != 4 { return 1 }

  ## bound `[i]` element reads (were garbage)
  if r[0] != 10 { return 2 }
  if r[1] != 20 { return 3 }
  if r[2] != 12 { return 4 }
  if r[3] != 40 { return 5 }

  ## `for x in r` iteration over the returned slice
  mut acc := 0
  for x in r { acc = acc + x }
  if acc != 82 { return 6 }

  ## DIRECT `.len` on the call result (no binding)
  if get(xs[0..3]).len != 3 { return 7 }

  ## a sub-range returned by value: len + first two elements = 2 + 20 + 12 = 34
  r2 := get(xs[1..3])
  if r2.len != 2 { return 8 }
  if r2[0] != 20 { return 9 }
  if r2[1] != 12 { return 10 }

  return 42
}
