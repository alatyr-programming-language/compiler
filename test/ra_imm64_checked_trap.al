## e2e — the imm32 widening must NOT drop a checked guard. A checked `u64` subtract whose right operand is a
## literal WIDER than the sign-extended imm32 field is materialized into a register, so the emitted shape
## becomes `movabsq $2^32, %vt; subq %vt, %v; jnc CONT; ud2; CONT:` — the guard stays IMMEDIATELY after the
## flag-producing instruction. 5 - 2^32 underflows u64, so this MUST trap (x86 exact 132, `ud2`).
main := fn() -> u64 {
  a := 5
  a - 4294967296
}
