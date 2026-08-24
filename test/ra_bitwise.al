## e2e — REGALLOC: bitwise `&` / `|` / `^` on the register-allocated scalar-leaf IR path. `bits` is
## scalar-leaf (native scalar params + return, only bitwise binops) → the IR path (new opcodes 16=and,
## 17=or, 18=xor rendered `andq`/`orq`/`xorq`, 2-operand src-first like `add`, no clobber). Same exit
## whether built default (regalloc) or ALATYR_RA=0 (text). (a&b)|(a^b) == a|b; 40|2 = 0b101010 = 42.
bits := fn(a : u64, b : u64) -> u64 { (a & b) | (a ^ b) }
main := fn() -> u64 {
  bits(40, 2)
}
