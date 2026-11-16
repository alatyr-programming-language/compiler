## e2e — #1576 (IR-19): a NICHE-FOLDED `Option(ptr(T))` crosses a call on the shared IR, in both
## directions, on x86_64. It is exactly one pointer word with NO discriminant (Types §6.2/§8,
## Memory §4.2; `lower_layout::is_niche_folded` is the one place that decides it): `None` is the
## payload's null pattern (0), `Some(p)` is the pointer `p`, and a `match` tests that word against 0.
## It crosses as any aggregate does — a parameter is the ADDRESS of a caller-owned copy of its words,
## a result of one word comes back in the result register — the convention x86_64's legacy emitter
## already uses (measured: `leaq` of the spilled word, `%rax`). `lg_rd` and `lg_pass` hold a float
## literal the IR does not build, so the legacy emitter emits them; `rd`, `mk` and `main` are IR-built.
##   * IR -> legacy: `lg_rd(mk(…))` — a legacy callee reads an IR-built callee's folded result;
##   * legacy -> IR: `lg_pass` passes a folded value it built to `rd`;
##   * IR -> IR: `rd(s)` through a folded local, and `rd(mk(…))` straight from a call.
## Each check owns its own bit of the mask; 42 when all held. On the parent every function here was
## refused (`CSigParamUnresolved`, `CSigResultWide`) and the whole program went to the legacy emitter.
## The directive is x86_64-only, as it is for the whole folded-option family (`niche_option_ptr`,
## `issue775_…` and the rest): aarch64, riscv64 and wasm keep such a signature on the LEGACY emitter —
## `ir::sig_has_folded_option` names it, and each of those selectors refuses it at both ends, the
## function itself (`sa_fn`, `sr_fn`, `sw_fn`) and every IR-built call to one (`sa_call`, `sr_call`,
## `sw_call`), because THEIR legacy emitter passes an aggregate as the unfolded tag and payload words
## (`[x2,#0]`, `[x2,#8]`) and a mixed crossing was measured wrong there. Measured on this program:
## aarch64 and riscv64 answer 42 through that legacy emitter, wasm traps (134) on the folded LOCAL in
## `main`, which is what its legacy emitter does for every fixture of this family. Undeclared, then,
## and unchanged from the parent — this slice moves no value on those three targets.
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
## expect(x86_64): run 42
