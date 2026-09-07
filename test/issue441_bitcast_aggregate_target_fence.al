## e2e / issue #441 (control) — the AGGREGATE bitcast target must stay fail-loud on aarch64/riscv64.
##
## Issue #441's fix makes a preserved POINTER target the machine-word identity on those two backends.
## The parser preserves a third non-scalar shape — a bare USER TYPE name, `bitcast(B, a)` — and that
## one is NOT a single machine word: `emit_a64_expr` / `emit_rv_expr` deliver one word, and this
## backend pair has no aggregate-value bitcast path at all, so emitting the inner value there would
## answer with a WRONG value where there had been a trap. The fence therefore stays, and this control
## pins it: x86_64 (which routes an aggregate bitcast through its struct-value path) answers 42, while
## aarch64 and riscv64 must still refuse loudly rather than return a number.
##
## The aarch64/riscv64 assertions want 133 — the SIGTRAP status of a fail-loud emit, not a program
## exit code. A later lane that gives those two an aggregate-value bitcast path is expected to flip
## exactly these two rows to 42; a change that flips them to any OTHER value below 128 is the silent
## miscompile this file exists to catch.
##
## 42 means the x86_64 reinterpret held; a miss owns 30, never a sum or a product.
Src := struct { x : u64, y : u64 }
Dst := struct { p : u64, q : u64 }

main := fn() -> u64 {
  a := Src(x = 42, y = 3)
  b := bitcast(Dst, a)
  if b.p != 42 { return 30 }
  return 42
}
