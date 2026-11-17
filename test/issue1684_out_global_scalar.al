## e2e — #1684: an `out` SCALAR bound to a MUTABLE MODULE GLOBAL must reach the global. Functions §2.3
## binds an `out` by a place argument when it is not projected, and Memory §3.1 makes `mut g` a writable
## path; the global's storage is its `.data` label, the target its own reads and writes already share.
## The x86_64 lower had no global arm: `emit_out_scalar_arg` asked `entry_of`, whose unbound sentinel is
## frame entry 0, so the callee received `leaq -8(%rbp)` — the CALLER'S FIRST FRAME WORD — and wrote
## there while `g` kept its old value. MEASURED at 1b3b22e0 (native x86_64, Stage1 built by the
## committed seed 0.3.2): this program answered **12** where 22 was due — a silent wrong value, not a
## trap. The callee's `y = 10` now lands in `g`: 10 + 12 = 22.
## x86_64-scoped: the fix is in the legacy x86 lower and the shared IR declines both functions
## (`alatyr ir`: callee `NotYet(signature: parameter with a mode)`, caller `NotYet(expr Call)`), so the
## default route takes this lowering; the twins' surface is a separate question (#1684's note).
## spec: Functions §2.3, Memory §3.1
## expect(x86_64): run 22
mut g : u64 = 0

give := fn(out y : u64) { y = 10 }

main := fn() -> u64 {
  give(g)
  g + 12
}
