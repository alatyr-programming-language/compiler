## IR slice 4b (`docs/ir-slice-4.md` §2): an enum crosses a call. A parameter is the address of a
## caller-owned copy of its {tag, payload…} words and a result comes back in the result registers, tag
## first — the conventions every legacy emitter already uses for an enum (measured: aarch64 x0..x2,
## riscv64 a0..a2, x86_64 %rax/%rdx/%rcx; wasm passes and returns a linear-memory address). So an
## IR-built function and a legacy-emitted one exchange enums in both directions (Q4: proved here).
##
## `lg_*` hold a float local — slice 8's construct — so the shared IR refuses them and they stay
## LEGACY-emitted; `take`, `mk2`, `mk3`, `pass` and `main` are IR-built on the register twins.
##   * IR -> legacy: `main` passes enums to `lg_take`, and reads `lg_mk3`'s three-word result;
##   * legacy -> IR: `lg_call` passes an enum to `take` and reads `mk3`'s result;
##   * IR -> IR: `take(mk3(…))`, `pass` hands its parameter on, `Option(u64)` from `mk2`.
## Each check returns its own code on failure; 42 when all hold, on all four backends.
E := enum { A, B(u64), C(u64, u64) }

take := fn(e : E) -> u64 {
  match e { E.A => { return 1 }; E.B(x) => { return x }; E.C(x, y) => { return x * 10 + y } }
}
pass := fn(e : E) -> u64 { return take(e) }
mk2 := fn(k : u64) -> Option(u64) {
  if k == 0 { return Option(u64).None }
  Option(u64).Some(k)
}
mk3 := fn(k : u64) -> E {
  if k == 0 { return E.A }
  if k == 1 { return E.B(9) }
  E.C(k, 2)
}

lg_take := fn(e : E) -> u64 {
  w : f64 = 1.0
  match e { E.A => { return 1 }; E.B(x) => { return x }; E.C(x, y) => { return x * 10 + y } }
}
lg_mk3 := fn(k : u64) -> E {
  w : f64 = 1.0
  E.C(k, 3)
}
lg_call := fn() -> u64 {
  w : f64 = 1.0
  e := mk3(4)
  return take(E.B(5)) + lg_take(e)
}

main := fn() -> u64 {
  if take(E.C(3, 4)) != 34 { return 1 }
  if lg_take(E.C(5, 6)) != 56 { return 2 }
  if lg_take(E.A) != 1 { return 3 }
  if take(mk3(0)) != 1 or take(mk3(1)) != 9 or take(mk3(7)) != 72 { return 4 }
  if pass(E.B(8)) != 8 { return 5 }
  e := lg_mk3(6)
  if take(e) != 63 { return 6 }
  if lg_call() != 5 + 42 { return 7 }
  o := mk2(3)
  u : u64 = match o { Some(v) => v; None => 100 }
  n := mk2(0)
  z : u64 = match n { Some(v) => v; None => 39 }
  u + z
}
## expect: run 42
