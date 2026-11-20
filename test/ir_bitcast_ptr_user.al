## e2e — IR-35 (#980): the integer → pointer `bitcast` REACHES the four selectors when its target is a
## pointer to a user type. Types §4.4 ("`bitcast` — a **bit** reinterpretation. It *preserves the bits*,
## requires **equal bit-width** … Where the reinterpretation crosses between a pointer and an integer —
## **in either direction** — this section's mechanics still apply, and Memory §4.5 confines the operation
## to an `unchecked` grant"); ABI §6 classifies every pointer and every word integer in one register
## class. So the IR carries the word unchanged (`bits`), and each selector moves it.
##
## Why this shape and not `ptr(u64)`: the parser keeps a `bitcast` whose target is `ptr(<user type>)` as
## its own node all the way to the emitters, while a word-scalar target or a `ptr(<scalar>)` target is
## the identity class, erased into its operand at every emit entry, where the builder then refuses its
## function (see `ir_bitcast_ptr_usize`). Here `get` is IR-built and selected on x86_64, aarch64, riscv64
## and wasm — `check_ir_bitcast_ptr` in `scripts/e2e.sh` asserts the selection on each — and the pointer
## it fabricates is passed on and read through. `addr` reads the address out the other way; it is the
## identity class, so it stays with the legacy emitter, and the round trip crosses the two paths.
## The answer is the second field read back through the fabricated pointer, 42; a word moved wrongly would
## read another word or fault.
S := struct { v : u64, w : u64 }
rd := fn(p : ptr(S)) -> u64 { deref(p).w }
addr := fn(p : ptr(S)) -> usize { unchecked bitcast(usize, p) }
get := fn(a : usize) -> u64 {
  q := unchecked bitcast(ptr(S), a)
  rd(q)
}
main := fn() -> u64 {
  s := S(v = 1, w = 42)
  get(addr(ptr(s)))
}
## expect: run 42
