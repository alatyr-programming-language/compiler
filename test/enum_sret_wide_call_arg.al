## a64-ONLY e2e (`run_a64`) — a WIDE-ENUM SRET call in ARGUMENT position: `use_it(mk(1))`, where `mk`
## returns an 11-word enum delivered through the AAPCS64 x8 indirect result. There is no destination
## local for it, so a64 reserves an A64_AGG block, hands its base down as the callee's x8, then passes
## that block BY REFERENCE (emit_a64_enumsret_arg). The consumer then `match`es a WIDE enum PARAM,
## which materializes 11 words into the A64_MTMP frame temp — a region NOTHING reserved, so the write
## ran past the 32-byte frame top and clobbered the CALLER's saved x29/x30 AND the source block: a RAW
## SIGSEGV (exit 139), the outcome the a64 gate forbids outright.
##
## Now CROSS-BACKEND (`run`): x86_64 used to SEGFAULT on this shape (exit 139) — the call fell through to
## the register-return enum-arg path, which wired no hidden result pointer, so the callee wrote its 11
## words through whatever %rdi happened to hold. `emit_arg` now reserves an agg-temp block FIRST, publishes
## its base on `cx.sret_call` (so the block's address rides the hidden %rdi) and passes that same block by
## reference — the x86_64 mirror of `emit_a64_enumsret_arg`. x86/a64/wasm MATCH 22; rv64 traps.
##
## Payload words are DISTINCT and the reader takes the FIRST, a MIDDLE, the LAST and a second interior
## pair: (1 + 5 + 10) + (8 - 2) = 22. Stays < 126.
W := enum { Many(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64), Small(u64) }

mk := fn(base : u64) -> W {
  return W.Many(base, base + 1, base + 2, base + 3, base + 4, base + 5, base + 6, base + 7, base + 8, base + 9)
}
use_it := fn(w : W) -> u64 {
  match w {
    W::Many(a, b, c, d, e, f, g, h, i, j) => (a + e + j) + (h - b)
    W::Small(x) => 0
  }
}

main := fn() -> u64 {
  use_it(mk(1))
}
