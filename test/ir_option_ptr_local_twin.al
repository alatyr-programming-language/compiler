## e2e — #1576 (IR-19b): a NICHE-FOLDED `Option(ptr(T))` LOCAL, read with `match`, in a program whose
## signatures mention NO folded option — the shape that lets the twins and wasm take it from the shared
## IR, and the value regression of this slice. `Option(ptr(T))` is exactly one pointer word with NO
## discriminant (Types §6.2/§7, Memory §4.2; `lower_layout::is_niche_folded` is the one place that
## decides it): `None` is the payload's null pattern (0), `Some(p)` is the pointer `p`, and a `match`
## tests that word against 0. The absent case WRITES the null pattern: `t` answered `Some`, is
## re-assigned `None`, and must answer `None` after it — the `Some` arm's `deref(p)` is a tripwire, a
## null dereference there is SIGSEGV (139), never a quiet 42.
## On the PARENT the builder refused `main` (`NotYet(stmt Assign …)`, the folded-option local), so the
## whole program went to each backend's legacy emitter, which traps on it: aarch64 and riscv64 at
## `brk #0` / `ebreak` (`unsupported match statement`, 133) and wasm at `unreachable` (`unsupported
## expr AddrOf`, 134); x86_64's legacy emitter answered 42. On the HEAD `main` is IR-built on all
## four (`alatyr ir` reports it Built; the twins' and wasm's dumps each carry one `ir: selected`),
## and every backend answers 42. So this fixture fails on the parent on aarch64, riscv64 and wasm.
## It keeps NO folded option in any signature on purpose: `ir::sig_pins_legacy` pins a signature that
## mentions one to the legacy emitter on those three targets, which would put `main` back on the
## emitter that traps — see `test/ir_option_ptr_local.al` and `test/ir_option_ptr_cross.al`.
## 42 when every check held; otherwise 100 + the mask of the failed ones.
main := fn() -> u64 {
  mut x : u64 = 8
  mut m : u64 = 0
  s : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(x))
  match s { Some(p) => { if deref(p) != 8 { m = m + 1 } } None => { m = m + 2 } }
  mut t : Option(ptr(u64)) = s
  t = Option(ptr(u64)).None
  match t { Some(p) => { if deref(p) != 0 { m = m + 4 } } None => { m = m + 0 } }
  if deref(ptr(x)) != 8 { m = m + 8 }
  if m != 0 { return 100 + m }
  return 42
}
## expect(x86_64): run 42
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
