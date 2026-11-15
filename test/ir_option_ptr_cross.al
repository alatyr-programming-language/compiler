## e2e — #1576 (IR-19): a NICHE-FOLDED `Option(ptr(T))` crosses a call on the shared IR, in both
## directions, on every backend. It is exactly one pointer word with NO discriminant (Types §6.2/§8,
## Memory §4.2; `lower_layout::is_niche_folded` is the one place that decides it): `None` is the
## payload's null pattern (0), `Some(p)` is the pointer `p`, and a `match` tests that word against 0.
## It crosses as any aggregate does — a parameter is the ADDRESS of a caller-owned copy of its words,
## a result of one word comes back in the result register — the conventions every legacy emitter uses
## (measured: x86_64 `leaq` of the spilled word and `%rax`; aarch64/riscv64 the same in x0/a0; wasm
## a linear-memory address). `lg_rd` and `lg_pass` hold a float literal the IR does not build, so the
## legacy emitter emits them; `rd`, `mk` and `main` are IR-built.
##   * IR -> legacy: `lg_rd(mk(…))` — a legacy callee reads an IR-built callee's folded result;
##   * legacy -> IR: `lg_pass` passes a folded value it built to `rd`;
##   * IR -> IR: `rd(s)` through a folded local, and `rd(mk(…))` straight from a call.
## Each check owns its own bit of the mask; 42 when all held. On the parent every function here was
## refused (`CSigParamUnresolved`, `CSigResultWide`) and the register twins trapped (SIGTRAP) while a
## `main` that stored the folded value in a LOCAL crashed wasm.
rd := fn(o : Option(ptr(u64))) -> u64 {
  match o { Some(p) => deref(p); None => 7 }
}
mk := fn(p : ptr(u64), z : u64) -> Option(ptr(u64)) {
  if z == 0 { return Option(ptr(u64)).None }
  Option(ptr(u64)).Some(p)
}
lg_rd := fn(o : Option(ptr(u64))) -> u64 {
  w := 1.5
  match o { Some(p) => deref(p); None => 7 }
}
lg_pass := fn(x : ptr(u64)) -> u64 {
  w := 2.5
  return rd(mk(x, 1)) + rd(mk(x, 0))
}
main := fn() -> u64 {
  mut x : u64 = 35
  mut m : u64 = 0
  if rd(mk(ptr(x), 1)) != 35 { m = m + 1 }
  if rd(mk(ptr(x), 0)) != 7 { m = m + 2 }
  s : Option(ptr(u64)) = mk(ptr(x), 1)
  if rd(s) != 35 { m = m + 4 }
  n : Option(ptr(u64)) = Option(ptr(u64)).None
  if rd(n) != 7 { m = m + 8 }
  if lg_rd(mk(ptr(x), 1)) != 35 { m = m + 16 }
  if lg_rd(Option(ptr(u64)).None) != 7 { m = m + 32 }
  if lg_pass(ptr(x)) != 42 { m = m + 64 }
  if m != 0 { return 100 + m }
  return 42
}
## expect: run 42
