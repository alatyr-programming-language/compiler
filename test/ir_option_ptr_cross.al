## e2e — #1576 (IR-19): a NICHE-FOLDED `Option(ptr(T))` crosses a call on the shared IR, in both
## directions, on x86_64. It is exactly one pointer word with NO discriminant (Types §6.2/§7,
## Memory §4.2; `lower_layout::is_niche_folded` is the one place that decides it): `None` is the
## payload's null pattern (0), `Some(p)` is the pointer `p`, and a `match` tests that word against 0.
## It crosses as any aggregate does — a parameter is the ADDRESS of a caller-owned copy of its words,
## a result of one word comes back in the result register — the convention x86_64's legacy emitter
## already uses. `lg_rd` and `lg_pass` hold a float literal the IR does not build, so the legacy
## emitter emits them; `rd`, `mk` and `main` are IR-built (`alatyr ir` says so, measured):
##   * IR -> legacy: `main` calls `lg_rd` / `lg_pass`, legacy callees of an IR-built caller;
##   * legacy -> IR: `lg_pass` passes a folded value it built to `rd`, an IR-built callee;
##   * IR -> IR: `rd(s)` through a folded local, and `rd(mk(…))` straight from a call.
## Each check owns its own bit of the mask; 42 when all held.
## On the PARENT every function here was refused by the builder (`signature: parameter type names no
## struct or enum resolvable here`, `signature: aggregate result wider than two words`) and the whole
## program went to the legacy emitter, which ANSWERS 42 on x86_64, aarch64 and riscv64 and traps (134)
## on wasm — measured: the same 42, 42, 42 and 134 on both trees, the aarch64, riscv64 and wasm dumps
## byte-identical. So this fixture pins that the crossing is now the IR's, at the same value; the
## value that MOVES is in `test/ir_option_ptr_local_twin.al`.
## The directive names every backend that answers 42. aarch64 and riscv64 answer it because
## `ir::sig_pins_legacy` keeps such a signature — and every call to one — on THEIR legacy emitter
## (`sa_fn`/`sa_call`, `sr_fn`/`sr_call`), which passes an aggregate as the unfolded tag and payload
## words: nothing here is selected from the IR there (measured, `ir: selected` count 0). wasm is left
## undeclared, as the whole folded-option family leaves it: its legacy emitter traps (134) on the
## folded LOCAL in `main`, unchanged from the parent.
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
## expect(aarch64): run 42
## expect(riscv64): run 42
