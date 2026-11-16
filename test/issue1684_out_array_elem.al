## e2e — #1684: an ARRAY ELEMENT bound to an `out` / `in out` parameter is a PLACE argument (Functions
## §2.3: "a place-expression the callee reads and writes **in place**", a mutable place by Memory §3.3),
## so the callee's store must reach the element. The x86_64 lower passed the element's VALUE instead:
## `emit_out_scalar_arg` claimed only a `Var` and let an `Index` fall to the value path, which computes
## the element address and then loads through it. MEASURED at 1b3b22e0 (native x86_64, Stage1 built by
## the committed seed 0.3.2): `put(a[0])` exited **139 (SIGSEGV)** — the callee stored through the
## integer 1. Here both a constant and a runtime index write back: 1 + 10 = 11, then `a[1] := 7`, and
## the untouched `a[2]` stays 3 — 11 + 7 + 3 = 21.
## The twins are not this fix's surface: aarch64 answers 139 for the same shape (filed as a follow-up),
## so the row is x86_64-scoped and sweep-excluded (`run_x86`).
## spec: Functions §2.3, Memory §3.1/§3.3
## expect(x86_64): run 21
put := fn(in out x : u64) { x = x + 10 }
bump := fn(out y : u64) { y = 7 }

main := fn() -> u64 {
  mut a : [u64; 3] = [1, 2, 3]
  mut i : usize = 1
  put(a[0])
  bump(a[i])
  a[0] + a[1] + a[2]
}
