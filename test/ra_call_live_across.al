## REGALLOC COMMIT 5 — a value LIVE ACROSS A CALL must survive the callee's caller-saved clobber.
## `main` matches the scalar-CALL shape (`emit_fn_ir` register-allocates it): `t` is computed BEFORE the
## call to `add` and used AFTER it, so it is live across the call. A `call` clobbers every caller-saved
## register — if the allocator parked `t` in one without a save, `add` would corrupt it. It MUST land in a
## callee-saved register (saved/restored by main's prologue/epilogue) or a spill slot. 20+20 + add(1,1) =
## 40 + 2 = 42, a UNIQUE correct answer; a dropped clobber would return a different value. Same under
## default (regalloc) and ALATYR_RA=0 (text path).
add := fn(a : u64, b : u64) -> u64 { a + b }
main := fn() -> u64 {
  t := 20 + 20
  x := add(1, 1)
  t + x
}
