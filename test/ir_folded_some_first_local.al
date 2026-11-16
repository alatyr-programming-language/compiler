## e2e — #1711: a NICHE-FOLDED `Option(ptr(T))` LOCAL whose enum declares `Some` FIRST, read with
## `match` in each arm order, in a program whose signatures mention NO folded option, so `main` is
## IR-built on every backend (a folded signature is pinned to the legacy emitter on aarch64, riscv64
## and wasm by `ir::sig_pins_legacy`; see `test/ir_folded_some_first_cross.al`). The enum is one
## pointer word with no discriminant whatever its variant order (Types §6.2): `Some` is discriminant 0
## here, and the variant is tested by its meaning — `None` is `word == 0`, `Some` is `word != 0`. A
## test against the discriminant would take `Some(p)` for `word == 0`: the null `t` would reach the
## `Some` arm's `deref(p)`, a null dereference (139), never a quiet 42.
## The absent case WRITES the null pattern: `t` answered `Some`, is re-assigned `None`, and must answer
## `None` after it. 42 when every check held; otherwise the failed check's own code, 101 upward.
Option := fn(T : type) -> type { return enum { Some(T), None } }
main := fn() -> u64 {
  mut x : u64 = 8
  s : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(x))
  match s { Some(p) => { if deref(p) != 8 { return 101 } } None => { return 102 } }
  match s { None => { return 103 } Some(p) => { if deref(p) != 8 { return 104 } } }
  mut t : Option(ptr(u64)) = s
  t = Option(ptr(u64)).None
  mut seen : u64 = 0
  match t { Some(p) => { if deref(p) != 0 { return 105 } } None => { seen = seen + 1 } }
  match t { None => { seen = seen + 1 } Some(p) => { return 106 } }
  if seen != 2 { return 107 }
  if deref(ptr(x)) != 8 { return 108 }
  return 42
}
