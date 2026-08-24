## §8 backend breadth: an UNSIGNED integer conversion `u8(x)` masks the low 8 bits on EVERY backend
## (x86_64 movzbq, aarch64 uxtb, riscv64 andi, wasm i64.and). Formerly the three non-x86 backends
## trapped on any `uN(x)`/`iN(x)` conversion as an unsupported builtin call. u8(810) = 810 & 0xFF = 42.
main := fn() -> u64 { return u8(810) }
