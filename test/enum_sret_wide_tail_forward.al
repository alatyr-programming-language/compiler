## e2e / a64 NON-X86 BREADTH — WIDE-ENUM SRET TAIL-FORWARD. `fwd` returns an enum whose
## {disc, payload…} block is 11 words (> the 8-word register-return budget), so it delivers through
## the AAPCS64 x8 indirect result; its return VALUE is itself a call to another wide-enum-returning
## fn, so BOTH sides want an x8 destination. The inner call must be handed the OUTER fn's OWN result
## pointer (`ldr x8, [x29, #<spilled x8 slot>]`) — the enum analogue of the wide-STRUCT tail-forward.
## Before this, the enum branch of `emit_a64_sret_store` returned early with a fail-loud `brk` (SIGTRAP,
## exit 133) for `return <wide-enum call>`; never a silent wrong value.
##
## Now CROSS-BACKEND (`run`): x86_64 used to SILENTLY MISCOMPILE this shape — `return <wide-enum call>`
## matched no arm of `emit_enum_to_sret`, so the inner call was emitted with NO hidden result pointer at
## all, the destination was never written and `main` exited 0 (a normal exit with a wrong value). x86_64
## now stages the inner call into an aggregate temp and copies it through this fn's own result pointer
## (the enum twin of `emit_struct_to_sret`'s tail-forward arm). x86/a64/wasm MATCH 22; rv64 traps.
## Every payload word carries a DISTINCT value (base+0 .. base+9) and `main` reads the FIRST (a), a
## MIDDLE (e), the LAST (j) and a second interior pair (h - b), so a dropped, zeroed or swapped word
## changes the answer: (1 + 5 + 10) + (8 - 2) = 16 + 6 = 22. Stays < 126 (WASI proc_exit range).
W := enum { Many(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64), Small(u64) }

mk := fn(base : u64) -> W {
  return W.Many(base, base + 1, base + 2, base + 3, base + 4, base + 5, base + 6, base + 7, base + 8, base + 9)
}
fwd := fn(base : u64) -> W {
  return mk(base)
}

main := fn() -> u64 {
  v := fwd(1)
  match v {
    W::Many(a, b, c, d, e, f, g, h, i, j) => (a + e + j) + (h - b)
    W::Small(x) => 0
  }
}
