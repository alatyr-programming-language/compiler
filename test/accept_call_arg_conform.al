## The load-bearing half of the call-argument conformance rule: the NEIGHBOURING LEGAL shapes it must
## NOT false-reject. A broad conformance check regressed ~90 stdlib tests earlier in this project, so
## every one of these is a proven accept, not a tuning matter:
##   - a NARROWER literal into a WIDER parameter — only **widen** is implicit (Types §4.3), and an
##     untyped integer literal takes its type from context (§3.4);
##   - a `str` literal into a `str` parameter, a bool literal into a `bool` parameter, a struct
##     literal into its own struct parameter, an enum literal into its own enum parameter — the
##     conforming cases;
##   - a fixed-ARRAY literal into an array parameter: a `[T; N]` parameter records its ELEMENT type in
##     `Param.ts`, so a naive read would compare `[40, 2]` against `u64` and reject a legal call;
##   - a UFCS method call `recv.m(arg)` — the receiver becomes ARGUMENT 0, so an off-by-one in the
##     parameter index would false-reject half the stdlib.
S := struct { a : u64, b : u64 }
E := enum { Lo, Hi }

wide := fn(n : u64) -> u64 { return n }
astr := fn(s : str) -> u64 { return s.len() }
abool := fn(b : bool) -> u64 { if b { return 1 } return 0 }
astruct := fn(s : S) -> u64 { return s.a + s.b }
anenum := fn(e : E) -> u64 { match e { Lo => { return 1 } Hi => { return 2 } } }
anarray := fn(xs : [u64; 2]) -> u64 { return xs[0] + xs[1] }
atuple := fn(t : (u64, u64)) -> u64 { return t.0 + t.1 }
tack := fn(s : str, n : u64) -> u64 { return s.len() + n }

main := fn() -> u64 {
  mut t := 0
  t = t + wide(7)               ## 7          → 7
  t = t + astr("abcd")          ## +4         → 11
  t = t + abool(true)           ## +1         → 12
  t = t + astruct(S(a = 3, b = 4))  ## +7     → 19
  t = t + anenum(E.Hi)          ## +2         → 21
  t = t + anarray([2, 4])       ## +6         → 27
  tp : (u64, u64) = (5, 6)
  t = t + atuple(tp)            ## +11        → 38
  t = t + "ab".tack(2)          ## +4         → 42
  return t
}
