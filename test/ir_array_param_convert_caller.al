## e2e — #1626, #1641's second review (B1): a fixed-array parameter function that a LEGACY caller reaches
## as a user conversion. Types §4.6: `W(v)` calls the in-scope `@convert` whose parameter accepts
## `typeof(v)` and which returns `W`; the call site names the target type, never the function.
## Functions §2.1/§4.1: the converter reads the caller's array.
## `main` holds an `f64` local, which the shared IR does not build, so every backend emits it with its
## legacy emitter, and the aarch64 and riscv64 legacy emitters pass `s.arr` by the value of the array's
## FIRST ELEMENT. MEASURED on `f1d31328`, whose plan found callers from the source text alone: the
## converter was IR-built and aarch64 and riscv64 answered 139 (SIGSEGV), where main trapped (133). A
## `@convert` is now held to legacy (`ir::ap_plan_begin`), so x86_64 answers 42 and the twins trap as
## before (`scripts/known-deviations.tsv`, #1194).
## expect: run 42
S := struct { tag : u64, arr : [u64; 3] }
W := struct { k : u64 }

to_w := @convert fn(xs : [u64; 3]) -> W { W(k = xs[0] * 100 + xs[1] * 10 + xs[2]) }

main := fn() -> u8 {
  z : f64 = 1.0
  if z > 2.0 { return 9 }
  s := S(tag = 1, arr = [0, 4, 2])
  w := W(s.arr)
  if w.k != 42 { return 1 }
  42
}
