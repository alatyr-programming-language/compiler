## #1518 — Types §4.6 dispatch step (2): `T(v)` selects "the one in-scope `@convert` whose return type
## is `T` and whose parameter accepts `typeof(v)` — equal to it, or assignable to it per §4.3". A
## conversion is keyed by its (source parameter type, return type), so two conversions to one target
## from different sources coexist and the operand picks between them: an integer literal and a `u32`
## local (a widen) reach `from_u64`, `true` reaches `from_bool`, and a `K` operand of the builtin target
## `u64` reaches `from_k`, not `from_c`. Before the fix every one of these sites was refused as an
## ambiguous conversion, because only the return type was compared.
P := struct { a : u64, b : u64 }
from_bool := @convert fn(x : bool) -> P { return P(a = 7, b = 0) }
from_u64 := @convert fn(x : u64) -> P { return P(a = x, b = 0) }
C := struct { v : u64 }
K := struct { v : u64, w : u64 }
from_c := @convert fn(c : C) -> u64 { return c.v }
from_k := @convert fn(k : K) -> u64 { return k.w }
main := fn() -> u64 {
  p := P(20)
  n : u32 = 10
  q := P(n)
  r := P(true)
  k := K(v = 1, w = 5)
  return p.a + q.a + r.a + u64(k)
}
## expect: run 42
