## e2e — #1711: a NICHE-FOLDED `Option(ptr(T))` whose enum declares `Some` FIRST (as the compiler's own
## `src/ast.al` does) is the same one pointer word as the prelude's, with no discriminant (Types §6.2:
## the single extra variant folds into the payload's niche whatever its position). `None` is the null
## pattern (0) and `Some(p)` the pointer `p`, so a variant is tested by its MEANING — `None` is
## `word == 0`, `Some` is `word != 0` — never by its discriminant, which here is 0 for `Some`.
## Covered: a parameter, a result, a local, a `match` with each arm order, `?` on a folded operand
## in a function with a folded result, and a call across the IR-built / legacy-built boundary in both
## directions. `lg_rd` and `lg_pass` hold a float literal the IR does not build, so the legacy
## emitter emits them; `rd`, `rd_none_first`, `mk`, `fwd` and `main` are IR-built (`alatyr ir`):
##   * IR -> legacy: `main` calls `lg_rd` / `lg_pass`;
##   * legacy -> IR: `lg_pass` passes a folded value to `rd`, an IR-built callee.
## On the PARENT every function with a folded signature was refused by the builder (`signature:
## parameter type names no struct or enum resolvable here`), and the whole program went to the legacy
## emitter. The directive names the backends that answer 42: aarch64 and riscv64 keep a folded
## signature on their legacy emitter (`ir::sig_pins_legacy`), and wasm is left undeclared as the
## whole folded-option family leaves it (its legacy emitter traps on a folded local).
## Each check answers its own code, 101 upward, when it fails; 42 when all held.
Option := fn(T : type) -> type { return enum { Some(T), None } }
rd := fn(o : Option(ptr(u64))) -> u64 {
  match o { Some(p) => deref(p); None => 7 }
}
rd_none_first := fn(o : Option(ptr(u64))) -> u64 {
  match o { None => 7; Some(p) => deref(p) }
}
mk := fn(p : ptr(u64), z : u64) -> Option(ptr(u64)) {
  if z == 0 { return Option(ptr(u64)).None }
  Option(ptr(u64)).Some(p)
}
fwd := fn(o : Option(ptr(u64))) -> Option(ptr(u64)) {
  p := o?
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
  if rd(mk(ptr(x), 1)) != 35 { return 101 }
  if rd(mk(ptr(x), 0)) != 7 { return 102 }
  s : Option(ptr(u64)) = mk(ptr(x), 1)
  if rd_none_first(s) != 35 { return 103 }
  n : Option(ptr(u64)) = Option(ptr(u64)).None
  if rd_none_first(n) != 7 { return 104 }
  if lg_rd(mk(ptr(x), 1)) != 35 { return 105 }
  if lg_rd(Option(ptr(u64)).None) != 7 { return 106 }
  if lg_pass(ptr(x)) != 42 { return 107 }
  if rd(fwd(s)) != 35 { return 108 }
  if rd(fwd(n)) != 7 { return 109 }
  return 42
}
## expect(x86_64): run 42
## expect(aarch64): run 42
## expect(riscv64): run 42
