## e2e (#684) — the same refusal when the zero divisor is a module const, the operator is `%`, and the
## bound sits inside `unchecked`.
##
## Comptime §2.6 (spec v1.6.0): "Inside an `unchecked` scope ... division by zero ... remains a
## diagnostic at comptime, because the evaluator has no hardware behaviour to reproduce." So the
## grant does not turn this into a value.
##
## Measured on the parent (`2cf60b45`, native x86_64): every backend compiled it clean and the loop
## unrolled zero times (exit 42 on x86_64, aarch64, riscv64 and wasm), because the `unchecked` bound
## read as 0 (#696) before the division was ever looked at. Here x86 refuses, the twins trap.
D := 0
main := fn() -> u64 {
  mut total : u64 = 0
  comptime for i in 0 .. unchecked (4 % D) { total = total + 1 }
  if total != 0 { return 1 }
  return 42
}
