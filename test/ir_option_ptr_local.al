## e2e — #1576 (IR-19): a NICHE-FOLDED `Option(ptr(T))` LOCAL is built by the shared IR in every
## form, and its `match` reads the one word against 0 instead of a discriminant (Types §6.2/§7,
## Memory §4.2). The absent case WRITES the null pattern: a local that answered `Some` and is
## re-assigned `None` must answer `None` after it, never the pointer the earlier `Some` left behind.
## 42 when every form held; otherwise 100 + the mask of the failed ones.
## On the PARENT every function here was refused by the builder (`signature: parameter type names no
## struct or enum resolvable here` for `rd`, `signature: aggregate result wider than two words` for
## `mk`, and `main` behind them), so the whole program went to each backend's legacy emitter — which
## ANSWERS 42 here on x86_64, aarch64 and riscv64 and traps (134) on wasm. Measured on both trees:
## the same 42, 42, 42 and the same 134, with the aarch64, riscv64 and wasm dumps byte-identical. So
## this fixture pins the IR-built side (`alatyr ir` reports `rd`, `mk` and `main` Built on x86_64,
## nothing selected on the other three) and holds the value; the value that MOVES is in
## `test/ir_option_ptr_local_twin.al`, where the parent traps 133 on aarch64 and riscv64.
## The directive names every backend that answers 42. The twins keep a signature that mentions a folded
## option on the legacy emitter (`ir::sig_pins_legacy`, refused in `sa_fn`/`sr_fn` and in each
## `*_call`, because THEIR legacy emitter passes an aggregate as the unfolded tag and payload words);
## wasm traps here because `main` calls such a callee and so stays on its legacy emitter too.
rd := fn(o : Option(ptr(u64))) -> u64 {
  match o { Some(p) => deref(p); None => 7 }
}
mk := fn(z : u64, p : ptr(u64)) -> Option(ptr(u64)) {
  if z == 0 { return Option(ptr(u64)).None }
  Option(ptr(u64)).Some(p)
}
main := fn() -> u64 {
  mut x : u64 = 40
  mut m : u64 = 0
  s : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(x))
  if rd(s) != 40 { m = m + 1 }
  n : Option(ptr(u64)) = Option(ptr(u64)).None
  if rd(n) != 7 { m = m + 2 }
  mut t : Option(ptr(u64)) = n
  if rd(t) != 7 { m = m + 4 }
  t = s
  if rd(t) != 40 { m = m + 8 }
  t = Option(ptr(u64)).None
  if rd(t) != 7 { m = m + 16 }
  u := mk(1, ptr(x))
  if rd(u) != 40 { m = m + 32 }
  v := mk(0, ptr(x))
  if rd(v) != 7 { m = m + 64 }
  mut a : u64 = 0
  match u { Some(p) => { a = deref(p) } None => { a = 1 } }
  if a != 40 { m = m + 128 }
  mut b : u64 = 0
  match v { Some(p) => { b = deref(p) } None => { b = 2 } }
  if b != 2 { m = m + 256 }
  if m != 0 { return 100 + m }
  return 42
}
## expect(x86_64): run 42
## expect(aarch64): run 42
## expect(riscv64): run 42
