## e2e — a FIXED array `[T; N]`'s length/size surfaces are the COMPTIME `N`, not a runtime word read.
## Regression for a SILENT WRONG VALUE (I11): `a.len` on a fixed array read word 1 (`a[1]`) as if the
## array were a {ptr,len} slice (`[10,20,30].len` → 20), and `size(a)` fell to the scalar default (8).
## Spec Types §6.4 (`N` is a compile-time value; stride = element size rounded to alignment) +
## Control-Flow §5.4 ("a `[T; N]` array's own length"). Now `a.len` folds to `N` (3) and `size(a)` to
## `N × stride` (24). The SLICE `.len` path (a real runtime word) is unchanged — see slice_len_field.al.
main := fn() -> u64 {
  a : [u64; 3] = [10, 20, 30]
  if a.len != 3 { return 1 }                 ## len = comptime N, NOT a[1] = 20

  c := [1, 2, 3]                             ## untyped literal (default native signed)
  if c.len != 3 { return 2 }

  if size(a) != 24 { return 3 }              ## N × stride = 3 × 8
  if align(a) != 8 { return 4 }              ## align([u64; N]) = align(u64) = 8

  ## a real counted iteration DRIVEN by `.len` — proves it is the true N (no OOB trap)
  mut s : u64 = 0
  for i in 0..a.len { s = s + a[i] }
  if s != 60 { return 5 }                    ## 10 + 20 + 30

  42
}
