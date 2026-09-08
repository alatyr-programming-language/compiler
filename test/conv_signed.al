## §8 backend breadth: a SIGNED integer conversion `i8(x)` sign-extends the low 8 bits on EVERY
## backend (x86_64 movsbq, aarch64 sxtb, riscv64 slli+srai, wasm i64.extend8_s). Exercises the
## sign-extend path (distinct from the unsigned mask in conv_narrow), and needs a NEGATIVE result.
##
## The sign-extended operand is the u8 VALUE 200, not the bare literal `i8(200)` this row used to
## write: 200 is not representable in i8, and Types §9.1 (#564) makes that a compile error through the
## `T(v)` spelling too, so asserting 42 for the old spelling would have frozen a refused silent wrap
## into the corpus oracle (the #527 class). 200 IS representable in u8, and §4.2's narrowing of a
## VALUE is the rule this header always described (`i8(x)`). Measured: the emitted sign-extension is
## unchanged — three movsbq / sxtb / slli+srai and one i64.extend8_s, exactly as before.
## 200 sign-extended from 8 bits = -56; -56 + 98 = 42.
## `test/reject_conv_signed_literal.al` keeps the refused literal spelling.
main := fn() -> u64 { return i8(u8(200)) + 98 }
