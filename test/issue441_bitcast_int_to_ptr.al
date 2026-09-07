## e2e / issue #441 — Types §4.4 — an INTEGER→POINTER `bitcast` must LOWER on aarch64 and riscv64.
##
## A pointer value is one machine word and a `bitcast` is the identity on the bits, so the preserved
## `Expr::Bitcast` node lowers to exactly its inner value. `src/lower.al` has always emitted that for
## x86_64; `src/aarch64.al` and `src/riscv64.al` answered every pointer target with a fail-loud stub
## instead, so this program trapped on those two (exit 133 = SIGTRAP) while x86_64 and wasm ran to 42.
##
## Isolation is the point: the struct is declared HERE, has three fields and no ambient name appears
## anywhere in the file, so nothing about the prelude or the arena surface can explain the result.
## The pointer is never dereferenced — only the struct's own scalar fields are read — so the null base
## is inert and the assertion is purely about the reinterpret reaching a lowering.
##
## All three preserved pointer spellings the grammar admits are exercised: `ptr(mut T)`, `ptr(T)`
## without the mutability marker (a distinct parse in `ptr_target_pointee`), and the blank-separated
## `ptr (mut T)`, which a fixed `"ptr("` prefix test would classify as an aggregate and send to the
## aggregate fence instead of to the pointer identity.
##
## 42 means every spelling lowered; each miss owns its own code, all of them below 126 and none a sum
## or a product of the others.
Handle := struct { base : ptr(mut bits8), cap : u64, off : u64 }
RoHandle := struct { base : ptr(bits8), cap : u64, off : u64 }

cap_of := fn(h : Handle) -> u64 { return h.cap }

ro_cap_of := fn(h : RoHandle) -> u64 { return h.cap }

main := fn() -> u64 {
  mp := unchecked bitcast(ptr(mut bits8), usize(0))
  m := Handle(base = mp, cap = 7, off = 0)
  if cap_of(m) != 7 { return 10 }
  rp := unchecked bitcast(ptr(bits8), usize(0))
  r := RoHandle(base = rp, cap = 9, off = 0)
  if ro_cap_of(r) != 9 { return 11 }
  sp := unchecked bitcast(ptr (mut bits8), usize(0))
  s := Handle(base = sp, cap = 13, off = 0)
  if cap_of(s) != 13 { return 12 }
  return 42
}
