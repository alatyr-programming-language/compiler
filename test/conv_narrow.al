## §8 backend breadth: an UNSIGNED integer conversion `u8(x)` masks the low 8 bits on EVERY backend
## (x86_64 movzbq, aarch64 uxtb, riscv64 andi, wasm i64.and). Formerly the three non-x86 backends
## trapped on any `uN(x)`/`iN(x)` conversion as an unsupported builtin call, so what this row proves
## first is that the conversion EXISTS on all four; the mask is then observed through the value.
##
## The masked operand is the u16 VALUE 810, not the bare literal `u8(810)` this row used to write.
## Types §9.1 (#564) makes a literal outside the target type's range a compile error through the
## `T(v)` spelling too, so `u8(810)` is refused now — and asserting 42 for it would have frozen the
## silent wrap this compiler refuses into the corpus oracle (the #527 class). 810 IS representable in
## u16, and §4.2's narrowing of a VALUE is the rule this row's own header always described (`u8(x)`).
## Measured: the emitted mask is unchanged — one movzbq / uxtb / andi / i64.and, exactly as before.
## 810 & 0xFF = 42. `test/reject_conv_narrow_literal.al` keeps the refused literal spelling.
main := fn() -> u64 { return u8(u16(810)) }
