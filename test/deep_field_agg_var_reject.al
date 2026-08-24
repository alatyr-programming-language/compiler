## build_reject — a multi-word STRUCT-VAR source into a struct field (`o.mid.inner = r`) must FAIL LOUD,
## never a silent word-0-only store. The naive per-word copy loop, when placed in the shared field-store
## helper, is mis-lowered by the self-host seed to a SINGLE iteration (dropping word 1+); rather than
## emit that silent miscompile the compiler refuses the struct-VAR field source. Workaround: a struct
## literal `S(a = r.a, b = r.b)` or an if/match value (both delivered correctly). Applies to the
## single-hop `o.f = r` and this deep-chain `o.mid.inner = r` alike.
Rec := struct { a : i64, b : i64 }
Mid := struct { inner : Rec, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  mut o : Outer = Outer(mid = Mid(inner = Rec(a = 0, b = 0), x = 0), tag = 7)
  r := Rec(a = 12, b = 30)
  o.mid.inner = r
  return u64(o.mid.inner.a + o.mid.inner.b)
}
