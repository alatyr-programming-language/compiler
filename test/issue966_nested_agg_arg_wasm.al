## e2e (#966 — Concurrency §6.2 / Types §2.3: `unchecked` guards an operation, it does not change the
## VALUE, so a literal-only expression inside it still folds; and a declared type is the CONTEXT of the
## expression in that position, Types §2.3).
## The constant fold did not look through `Unchecked` (`ib_lit_fold` answered None for the block), so
## `S1(k1 = unchecked (10 | 0), …)` never folded: the walk descended and asked each `Num` its OWN type
## — `VcLit`, no context having reached it — and `mk17` was refused as `sema-gap literal: expr Num`.
## The function then fell back to the LEGACY wasm emitter, which builds an aggregate in expression
## position through the single global `$__tmp`; the nested enum-literal arguments of the `bf6` call
## overwrite it, and the outer struct literal yields the INNER block's address (#967) — the shape that
## answered 2 where 11 was due in the un-reduced program. Progen seed 2074802946, reduced by hand.
## Closing the fold/context gap removes the fallback, so the shape is built by the shared IR, which
## gives every aggregate its own place. The frozen seed TRAPS on all three twins here (133/133/134,
## loud rather than wrong) and answers 11 on x86_64; the row pins 11 on all four, so what it holds is
## that this shape stays ANSWERED and correct everywhere rather than falling back.
## Values: bf6 = B5(10) → v20 = 10; mk17 returns S1{k1=1,k2=10}; bf23 = B5(10); acc = 0^10 = 10;
## (10 % 113) + 1 = 11.
## reproduce: python3 scripts/progen.py show --seed 2074802946
## progen seed=2074802946 ty=u64 forms=brand,enum,struct (scripts/progen.py) — a generated program; see #582.
## The uncalled function below is the ambient prelude trigger (#532).
progen_trigger := fn() -> u64 {
  match checked_add(u8(1), u8(1)) { Some(v) => { u64(v) } None => { 0 } }
}
S1 := struct { k1 : u64, k2 : u64 }
E2 := enum { V1, V2(u64), V3, V4(u64, u64) }
E3 := enum { V1(u64, u64, u64), V2(u64, u64, u64), V3(u64, u64), V4(u64) }
B4 := brand(u64)
B5 := brand(u64)
bf6 := fn(p7 : E2, p8 : E3, p9 : S1) -> B5 {
  return B5(10)
}
mk17 := fn(p18 : B5, p19 : u64) -> S1 {
  mut v20 : u64 = u64(bf6(E2.V4(1, 1), E3.V3(1, 1), S1(k1 = unchecked (10 | 0), k2 = 1)))
  return S1(k1 = 1, k2 = u64(bf6(E2.V2(1), E3.V4(1), S1(k1 = 1, k2 = 1))))
}
bf23 := fn(p24 : E2, p25 : B4) -> B5 {
  mut v26 : u64 = mk17(B5(1), 2147483648).k2
  return B5(v26)
}
main := fn() -> u64 {
  mut acc : u64 = 0
  acc = unchecked ((acc * 31) ^ u64(bf23(E2.V1, B4(255))))
  return (acc % 113) + 1
}
## expect: run 11
