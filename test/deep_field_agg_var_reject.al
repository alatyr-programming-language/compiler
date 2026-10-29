## Expected exit: 42 — a multi-word STRUCT-VAR source into a struct field (`o.mid.inner = r`) RUNS and
## answers 42. It was registered `build_reject` while the legacy x86 emitter mis-lowered the per-word
## copy loop to a SINGLE iteration (dropping word 1+), so any answer but a refusal would have been a
## silent word-0-only store. That is no longer the case: the shared IR's x86 selector lowers it and
## answers 42, which is what aarch64, riscv64 and WAT already answered — measured on native x86_64
## through the DEFAULT surface after the slice-9 flip (`docs/ir.md` §7.4, #980). #1022 states the rule
## this follows: a refusal the other three backends do not share is not a requirement, and registering it
## as one would make the IR path inherit the legacy slot map's limits as law.
## The shape that made the refusal necessary: the naive per-word copy loop, placed in the shared
## field-store helper, was mis-lowered by the self-host seed to a SINGLE iteration (dropping word 1+);
## rather than emit that silent miscompile the legacy emitter refused the struct-VAR field source.
## Workaround on the legacy surface: a struct literal `S(a = r.a, b = r.b)` or an if/match value (both
## delivered correctly). Applies to the single-hop `o.f = r` and this deep-chain form alike.
Rec := struct { a : i64, b : i64 }
Mid := struct { inner : Rec, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  mut o : Outer = Outer(mid = Mid(inner = Rec(a = 0, b = 0), x = 0), tag = 7)
  r := Rec(a = 12, b = 30)
  o.mid.inner = r
  return u64(o.mid.inner.a + o.mid.inner.b)
}
