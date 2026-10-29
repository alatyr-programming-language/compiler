## Expected exit: 42 — a deep-chain ENUM final field whole-assign (`o.mid.c = Col.G(42)`) RUNS and the
## payload survives both hops: the `match` below takes `Col.G(v)` and returns 42. It was registered
## `build_reject` while the nested enum FINAL-field access was unsupported END-TO-END on the self-host
## lower — even the READ (`match o.mid.c`) was not lowered, so a whole-assign there could only produce
## garbage and a loud refusal was the honest answer. It is no longer the honest answer: the shared IR's
## x86 selector lowers the chain and answers 42, which is what aarch64, riscv64 and WAT already
## answered — measured on native x86_64 through the DEFAULT surface after the slice-9 flip
## (`docs/ir.md` §7.4, #980). #1022: a refusal the other three backends do not share is not a
## requirement. (The single-hop enum field write `s.c = Col.G(v)` works on both surfaces.)
Col := enum { R(i64), G(i64) }
Mid := struct { c : Col, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  mut o : Outer = Outer(mid = Mid(c = Col.R(0), x = 0), tag = 7)
  o.mid.c = Col.G(42)
  match o.mid.c { Col.R(v) => { return 0 }  Col.G(v) => { return u64(v) } }
}
