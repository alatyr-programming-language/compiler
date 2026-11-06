## e2e — #936: `.len` of a FIXED-ARRAY STRUCT FIELD is the field's declared `N`, on every backend.
## Regression for a SILENT WRONG VALUE (I11): `r.u.len` where `u : [u64; 3]` is a struct FIELD answered
## **0** on x86_64 while `r.u[i]` read the right element and a plain local `xs.len` answered 3. The
## `.len` fold was gated on `fixed_arr_len`, which reads a frame SLOT and so recognizes only a `Var`
## base; a field's length lives in its declared TYPE span, so the read matched no arm and fell to the
## slot default — a never-written frame word. Spec Types §6.4 ("`[T; N]` lays `N` elements
## contiguously… `N` is a compile-time value") and Control-Flow §5.4 (the upper bound is "a `[T; N]`
## array's own length"): a `[T; N]` carries no runtime length word, so `.len` is the comptime `N`.
## Covers the field at word offset 1 (after a scalar), at offset 0, and at a non-zero offset behind
## another field, plus the whole-array read the length must agree with.
Rec := struct { a : u64, u : [u64; 3], b : i64 }
Head := struct { h : [u64; 2] }
Tail := struct { n : u64, t : [u64; 5] }

main := fn() -> u64 {
  r : Rec = Rec(a = 1, u = [10, 20, 30], b = 0 - 4)
  if r.u.len != 3 { return 1 }                 ## the declared N, NOT a frame word (was 0)
  if r.u[0] != 10 { return 2 }                ## the length and the elements agree
  if r.u[1] != 20 { return 3 }
  if r.u[2] != 30 { return 4 }

  ## iteration bounded by the FIELD's own length — proves it is the true N, not a lucky 3
  mut s : u64 = 0
  mut i : u64 = 0
  while i < r.u.len { s = s + r.u[i]; i = i + 1 }
  if s != 60 { return 5 }

  h : Head = Head(h = [7, 8])
  if h.h.len != 2 { return 6 }                ## array field at word offset 0
  if h.h[1] != 8 { return 7 }

  t : Tail = Tail(n = 9, t = [1, 2, 3, 4, 5])
  if t.t.len != 5 { return 8 }                ## array field at a NON-ZERO word offset
  if t.t[4] != 5 { return 9 }

  42
}
## expect: run 42
