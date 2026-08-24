## e2e — a bare `Slice(` INSTANTIATION as the ONLY prelude trigger in a single-file program (Stdlib
## §3.5 / appendix 160: `Slice` is a LIBRARY pair — a `struct { ptr : ptr(T), len : usize }`
## type-function in `lib/base/slice.al` — not a layout primitive). The ambient-prelude scan in
## `src/cli.al` triggered on `Option`/`Result`/`u128`/`uint(`/`@alloc` but NOT on `Slice(`, so a file
## like this one compiled with NO `Slice` declaration in scope: `field_words` sized `v : Slice(u64)`
## as ONE word, so `b.v.len` read 0 and the FOLLOWING field overlapped the slice's len word — a SILENT
## MISCOMPILE. The very same program with any `Option` mention compiled and ran correctly, so the two
## spellings disagreed. This file DELIBERATELY mentions no `Option`/`Result`/`alloc::`/`std::`/`u128`:
## the bare `Slice(` must pull the base prelude on its own.
## Both field ORDERS are locked, so a mis-sized 2-word field shows up as a shifted scalar either way.
## Values: (4 + 5) + (3 + 6) + 3 + (3 + 6) = 30 (the same arithmetic as `slice_field_struct`, whose
## `View(T)` is declared LOCALLY — here the type comes from the injected prelude instead).
SA := struct { v : Slice(u64), n : u64 }
SB := struct { n : u64, v : Slice(u64) }

## The 2-word field of a BY-REFERENCE struct param, extracted to a local first — the composed spelling
## `slice_field_struct` locks (a DIRECT `x.v.len` on a by-ref param is a separate, still-open gap).
byref := fn(x : SA) -> u64 {
  w := x.v
  return u64(w.len) + x.n
}

main := fn() -> u64 {
  xs := [1, 2, 3, 4]
  s := xs[1..4]                       ## a slice VAR of length 3
  a := SA(v = xs[0..4], n = 5)        ## the 2-word field FIRST, from a range-slice EXPR
  b := SA(v = s, n = 6)               ## the 2-word field FIRST, from a slice VAR
  c := SB(n = 3, v = s)               ## the 2-word field LAST
  if a.v.len != 4 { return 1 }        ## was 0 (the field sized as ONE word)
  if a.n != 5 { return 2 }            ## the scalar after the slice must not overlap it
  if b.v.len != 3 { return 3 }
  if c.v.len != 3 { return 4 }
  if c.n != 3 { return 5 }
  return (u64(a.v.len) + a.n) + (u64(b.v.len) + b.n) + u64(c.n) + byref(b)
}
