## build_reject — a deep-chain ENUM final field whole-assign (`o.mid.c = Col.G(42)`) must FAIL LOUD.
## The nested str/enum FINAL-field access is unsupported END-TO-END — even the READ (`match o.mid.c`)
## is not lowered by the self-host lower — so a whole-assign here can only produce garbage; the compiler
## refuses it loudly rather than emit a silent (word-0-only / mis-staged) store. Flatten to a single hop
## or bind the inner struct to a local. (The single-hop enum field write `s.c = Col.G(v)` works.)
Col := enum { R(i64), G(i64) }
Mid := struct { c : Col, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  mut o : Outer = Outer(mid = Mid(c = Col.R(0), x = 0), tag = 7)
  o.mid.c = Col.G(42)
  match o.mid.c { Col.R(v) => { return 0 }  Col.G(v) => { return u64(v) } }
}
