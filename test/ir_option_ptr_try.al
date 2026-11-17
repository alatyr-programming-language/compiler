## e2e — #1711: `?` on the prelude's NICHE-FOLDED `Option(ptr(T))` (`None` first), in a function
## whose result is folded too. The operand has no tag word (Types §6.2): its success test is the
## variant's meaning (`Some` is `word != 0`), its payload is the one word at byte 0, and the absent
## result is the null pattern, with no discriminant stored into it. On the PARENT the builder compared
## the word with `Some`'s discriminant (1) and loaded the payload at byte 8 of the one-word object:
## `alatyr ir` reported `fwd VerifyFailed(V6 at inst 12)`, and the build stopped with the internal
## error `IR verify V6 in ir_option_ptr_try::fwd` (exit 70). The Some-first order is
## `test/package/ir1711_some_first_try`.
## Only x86_64 is declared: aarch64 and riscv64 keep a folded signature on their legacy emitter
## (`ir::sig_pins_legacy`), which traps (133) on `?` over a folded option, and wasm is left undeclared
## as the whole folded-option family leaves it.
## Each check answers its own code, 101 upward, when it fails; 42 when all held.
rd := fn(o : Option(ptr(u64))) -> u64 {
  match o { Some(p) => deref(p); None => 7 }
}
fwd := fn(o : Option(ptr(u64))) -> Option(ptr(u64)) {
  p := o?
  Option(ptr(u64)).Some(p)
}
main := fn() -> u64 {
  mut x : u64 = 35
  s : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(x))
  n : Option(ptr(u64)) = Option(ptr(u64)).None
  if rd(fwd(s)) != 35 { return 101 }
  if rd(fwd(n)) != 7 { return 102 }
  return 42
}
## expect(x86_64): run 42
