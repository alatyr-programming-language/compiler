## §8 backend breadth: a SIGNED integer conversion `i8(x)` sign-extends the low 8 bits on EVERY backend
## (x86_64 movsbq, aarch64 sxtb, riscv64 slli+srai, wasm i64.extend8_s). i8(200) = -56; -56 + 98 = 42.
## Exercises the sign-extend path (distinct from the unsigned mask in conv_narrow).
main := fn() -> u64 { return i8(200) + 98 }
