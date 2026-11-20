## e2e — IR-35 (#980): `bitcast` between a pointer and a register-width integer, in EITHER direction.
## Types §4.2's `reinterpret` row ("same-size bit reinterpretation", bits unchanged, cost zero) and Types
## §4.4 ("`bitcast` — a **bit** reinterpretation. It *preserves the bits*, requires **equal bit-width**,
## and emits ~zero instructions … Where the reinterpretation crosses between a pointer and an integer —
## **in either direction** — this section's mechanics still apply, and Memory §4.5 confines the operation
## to an `unchecked` grant"). Memory §4.5 names both directions: "fabricating a pointer from an integer
## (`bitcast` to a pointer type …), and reading a pointer out as an integer **value**". ABI §6 gives them
## one register class: "`uN` / `iN` / `bitsN` / `bool` / `char` and every pointer classify **integer**".
## So the IR carries ONE word unchanged (`bits`) and each selector moves it.
##
## The address never becomes the answer: it is read out, round-tripped through a fabricated pointer and
## read out again, and only a small count returns (1 + 2 + 39 = 42), so the fixture is stable across runs
## and ASLR. `a != 0` compares two INTEGERS (`a` is a `usize`), not a pointer with an integer, so it
## needs no grant of its own (Memory §4.5's comparison rule).
##
## WHY THE CROSSING SITS IN A CALLEE TAKING A POINTER: every emit entry erases an identity-class
## `bitcast` — a word-scalar target such as `usize`, or `ptr(<scalar>)` such as `ptr(u64)` — into its
## operand in place (`ast::bitcast_identity_erase`, #529), while sema's record for that node stays the
## bitcast's target type. On the emit path the builder therefore meets `p` recorded
## as an integer and holding a pointer vreg, and refuses `cross` as a sema-gap disagreement — correctly,
## since it never builds on a type that contradicts the value's own record. `main` keeps its `ptr(x)` and
## its call IR-built while `cross` falls back to the legacy emitter, which already lowers this crossing
## (#548). `alatyr ir` does not erase, and there BOTH functions are Built with `verify_failed=0`: that is
## the half this slice changes, and `check_ir_bitcast_ptr` in `scripts/e2e.sh` pins it. Until #1781
## is fixed no selector receives THESE crossings; a `ptr(<user type>)` target is not erased and does
## reach every selector (`ir_bitcast_ptr_user`).
cross := fn(p : ptr(u64)) -> u64 {
  ## pointer → usize: the address read out as an integer value (Memory §4.5).
  a := unchecked bitcast(usize, p)
  ## usize → pointer: those same bits fabricated back, and read out again. The round trip is exact
  ## because the word is never converted — only re-typed (Types §4.4: bits unchanged).
  q := unchecked bitcast(ptr(u64), a)
  b := unchecked bitcast(usize, q)
  mut n : u64 = 0
  if a == b { n = n + 1 }
  if a != 0 { n = n + 2 }
  ## 1 + 2 + 39 = 42; the address itself is never returned (it differs every run).
  n + 39
}
main := fn() -> u64 { x : u64 = 1000; cross(ptr(x)) }
## expect: run 42
