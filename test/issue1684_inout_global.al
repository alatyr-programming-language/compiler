## e2e — #1684, the `in out` half: a global bound to an `in out` SCALAR is read AND written in place.
## Same root as the `out` case — Functions §2.3's place argument, Memory §3.1's writable `mut` path —
## with the extra fact that the callee's READ must see the global too, not just land a store. The x86_64
## lower passed frame slot 0's address, so both halves went wrong together: MEASURED at 1b3b22e0 (native
## x86_64, Stage1 built by the committed seed 0.3.2) this answered **105** (the old 5 + 100) where 111
## was due. Two bumps: 5 + 3 + 3 = 11, then + 100 = 111.
## spec: Functions §2.3, Memory §3.1
## expect(x86_64): run 111
mut g : u64 = 5

bump := fn(in out y : u64) { y = y + 3 }

main := fn() -> u64 {
  bump(g)
  bump(g)
  g + 100
}
