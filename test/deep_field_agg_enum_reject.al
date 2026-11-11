## A deep-chain ENUM final field whole-assign (`o.mid.c = Col.G(42)`) keeps its payload over both hops:
## the `match` takes `Col.G(v)` and answers 42. The legacy x86 emitter lowered neither the store nor the
## nested read (`match o.mid.c`), so it refused the program. aarch64, riscv64 and wasm answer 42
## (#1022). Since the slice-9 flip (#980) x86_64 emits `main` from the shared IR and answers 42 too;
## `alatyr x86-legacy` still refuses it. (`deep_field_agg_str_reject`, the str final field, stays a
## refusal on both paths.) The name keeps the refusal's history.
Col := enum { R(i64), G(i64) }
Mid := struct { c : Col, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  mut o : Outer = Outer(mid = Mid(c = Col.R(0), x = 0), tag = 7)
  o.mid.c = Col.G(42)
  match o.mid.c { Col.R(v) => { return 0 }  Col.G(v) => { return u64(v) } }
}
## expect: run 42
