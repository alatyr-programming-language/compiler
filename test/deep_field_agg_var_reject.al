## A multi-word STRUCT-VAR source into a deep-chain struct field (`o.mid.inner = r`) answers 12 + 30.
## The legacy x86 emitter's per-word copy in the shared field-store helper was mis-lowered by the seed to
## a SINGLE iteration (dropping word 1+), so it refused the struct-VAR field source rather than store
## word 0 alone. aarch64, riscv64 and wasm answer 42 (#1022). Since the slice-9 flip (#980) x86_64
## emits `main` from the shared IR and answers 42 too; `alatyr x86-legacy` still refuses it. The name
## keeps the refusal's history.
Rec := struct { a : i64, b : i64 }
Mid := struct { inner : Rec, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  mut o : Outer = Outer(mid = Mid(inner = Rec(a = 0, b = 0), x = 0), tag = 7)
  r := Rec(a = 12, b = 30)
  o.mid.inner = r
  return u64(o.mid.inner.a + o.mid.inner.b)
}
## expect: run 42
