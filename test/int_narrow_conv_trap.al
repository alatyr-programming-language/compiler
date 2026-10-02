## Types §4.2 (narrow row): a CHECKED narrowing `T(v)` traps when the value does not fit `T`, read at
## the operand's DECLARED signedness. The i64 value -129 is below i8's range, so `i8(x)` traps (x86_64
## `ud2` → 132; the twins trap `narrow` through the shared IR's `fit`). Before #872, x86_64 silently
## answered the sign-extended low byte, 127. The truncating forms are written inside `unchecked`
## (`test/int_narrow_conv.al`).
f := fn(x : i64) -> i8 { i8(x) }
main := fn() -> u64 { u64(i64(f(0 - 129)) + 1) }
