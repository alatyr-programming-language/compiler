## e2e — REGALLOC imm32 widening. x86-64 encodes the immediate of `add`/`sub`/`imul`/`cmp`/`and`/`or`/`xor`
## in a 32-bit field that is SIGN-EXTENDED to 64 bits, so folding a wider literal into the instruction makes
## `as` reject the emitted text (`operand type mismatch for 'add'`). Every helper below is a scalar-leaf fn
## (the register-allocated IR path) whose second operand is a literal OUTSIDE that range — the allocator must
## materialize it into a register first. `bfit` keeps the largest value that DOES fit folded; `bhi`/`bmask`
## are just outside it (`2^31` and `0xFFFFFFFF` — 32 bits unsigned is still out of SIGNED range); `bneg` is
## `u64::MAX`, which sign-extends from 32 bits and so must stay a folded `$-1`. Values wider than a byte are
## verified by in-program COMPARISON, never by the exit code alone.
wadd := fn(r : u64) -> u64 { a := unchecked (r + 4294967296)  a }
wsub := fn(r : u64) -> u64 { a := unchecked (r - 4294967296)  a }
wmul := fn(r : u64) -> u64 { a := unchecked (r * 4294967296)  a }
wand := fn(r : u64) -> u64 { a := r & 4294967296  a }
wor  := fn(r : u64) -> u64 { a := r | 4294967296  a }
wxor := fn(r : u64) -> u64 { a := r ^ 4294967296  a }
wcmp := fn(r : u64) -> u64 { if r > 4294967296 { return 1 }  0 }
## the CHECKED (default) add with a wide immediate: the materializing move must not displace the `jcc`
## overflow guard, and the non-overflowing case must still produce the right value.
cadd := fn(r : u64) -> u64 { a := r + 4294967296  a }
bfit := fn(r : u64) -> u64 { a := unchecked (r + 2147483647)  a }
bhi  := fn(r : u64) -> u64 { a := unchecked (r + 2147483648)  a }
bmask := fn(r : u64) -> u64 { a := r & 4294967295  a }
bneg := fn(r : u64) -> u64 { a := r & 18446744073709551615  a }
main := fn() -> u64 {
  mut ok : u64 = 0
  if wadd(5) == 4294967301 { ok = ok + 1 }
  if wsub(5) == 18446744069414584325 { ok = ok + 1 }
  if wmul(5) == 21474836480 { ok = ok + 1 }
  if wand(4294967301) == 4294967296 { ok = ok + 1 }
  if wor(5) == 4294967301 { ok = ok + 1 }
  if wxor(4294967301) == 5 { ok = ok + 1 }
  if wcmp(4294967297) == 1 { ok = ok + 1 }
  if wcmp(5) == 0 { ok = ok + 1 }
  if bfit(1) == 2147483648 { ok = ok + 1 }
  if bhi(1) == 2147483649 { ok = ok + 1 }
  if bmask(4294967301) == 5 { ok = ok + 1 }
  if bneg(4294967301) == 4294967301 { ok = ok + 1 }
  if cadd(5) == 4294967301 { ok = ok + 1 }
  if ok == 13 { return 42 }
  return ok
}
