## #546 / Types §4.2 — an identity-ERASED `bitcast` TARGET must decide a RELATIONAL operand's
## SIGNEDNESS, on all four backends.
##
## `bitcast` is the reinterpret conversion: same bits, the target `T` decides the reading. A
## relational operator is exactly the construct that reads it. But `src/parser.al` identity-erases a
## WORD-SIZED bare scalar target — `bitcast(i64, off)` builds NO node and the lowerers receive `off`
## itself — so the four `*_cmp_unsigned` predicates saw a bare `usize` name, proved it UNSIGNED, and
## emitted the unsigned ordering. `unchecked bitcast(i64, off) < 0` was therefore FALSE for EVERY
## value of `off`, on x86_64, aarch64, riscv64 and wasm alike (measured: 0 on all four at the parent
## `c1c086f`).
##
## THAT IS A SILENCED GUARD, not a wrong boolean, which is why case 1 comes first and why a fixture
## that only compared a returned `bool` would understate the defect: every refusal predicate of the
## form "if this went negative, refuse" compiled to "never refuse". `src/ast.al::span_high_bit`
## carries the `shr(off, 63) == 1` workaround written when #523's lane hit exactly this — its first
## fix did nothing because the comparison it added read constant-false and the trap it was removing
## survived a full build.
##
## The code returned is the number of the FIRST failing case, and 99 only when all ten pass. Failure
## codes run 1..10, 99 is outside that range, and every code is below 126 (#386) so wasm's
## `proc_exit` accepts them all and no misclassification aliases onto the success sentinel. At the
## parent this program returns 1 on all four backends — the guard-silencing case, failing for the
## reason named above and not for a trap: `build_reject` proves nothing here, the build is clean.
##
## Cases 7..10 are the OVER-EAGERNESS controls, and none of them is decoration. Teaching the
## signedness decision about `bitcast` must not make a genuinely UNSIGNED comparison signed — the
## failure the four twin comments in `src/aarch64.al`, `src/riscv64.al` and `src/wat.al` were written
## for, where a `u64` word above 2^63 ordered as NEGATIVE and `0 < 18446744073709551610` answered
## FALSE. Case 7 is that exact row; case 8 is its literal-partner form (#367's class); case 9 proves
## a `u64` TARGET keeps the unsigned reading rather than acquiring a signed one; and case 10 is the
## recovery's FORWARD boundary — there the target reinterprets the COMPARISON'S BOOL RESULT and says
## nothing about `u`, so a scan that fired one character too far would answer "`u` is `i64`" and turn
## that inner comparison true. All four answer identically at the parent and here.
##
## Registered with plain `run` (not `run_x86`), so the a64/rv64/wasm sweeps carry it too.

## The DAMAGE, as the program that lost it: a modular-underflow handle has its top bit set, so
## "outside the buffer" is exactly what this must answer. 0 = refused, 7 = admitted.
offset_load := fn(off : usize) -> i32 {
  if unchecked bitcast(i64, off) < 0 { return 0 }
  7
}

## The bare relational form, both directions of the cast.
neg_word := fn(off : usize) -> bool { unchecked bitcast(i64, off) < 0 }
pos_word := fn(n : i64) -> bool { unchecked bitcast(u64, n) > 0 }

## Control: a `u64` target must leave the comparison UNSIGNED, never make it signed.
below_ten := fn(off : usize) -> bool { unchecked bitcast(u64, off) < 10 }

## Control: the target here reinterprets the comparison's BOOL result, so `u` keeps its own `usize`
## reading and `u < 0` stays false. A reverse source scan without a forward boundary answers `i64`
## for `u` and turns this true.
cast_of_cmp := fn(u : usize) -> i64 { unchecked bitcast(i64, u < 0) }

main := fn() -> u64 {
  hi : usize = 18446744073709551610      ## bit 63 set; the signed reading is -6
  lo : usize = 5
  neg : i64 = 0 - 1
  pos : i64 = 5
  w : u64 = 18446744073709551610
  n : u64 = 9223372036854775808

  ## 1 — the guard must FIRE on a high-bit offset. Parent: 7 (admitted), on all four backends.
  if offset_load(hi) != 0 { return 1 }
  ## 2 — and must NOT fire on an ordinary one.
  if offset_load(lo) != 7 { return 2 }
  ## 3 — `bitcast(i64, <high-bit usize>) < 0` is true. Parent: false.
  if neg_word(hi) == false { return 3 }
  ## 4 — and false for a small word, where both readings agree.
  if neg_word(lo) { return 4 }
  ## 5 — the MIRROR: a `u64` target forces UNSIGNED where the scan proved signed, so a negative
  ##     `i64` reinterpreted as `u64` is above zero. Parent: false.
  if pos_word(neg) == false { return 5 }
  ## 6 — and a positive one stays above zero.
  if pos_word(pos) == false { return 6 }
  ## 7 — CONTROL, the exact row the twin comments record: a `u64` above 2^63 must still order as
  ##     the large positive number it is.
  if 0 < w { } else { return 7 }
  ## 8 — CONTROL, the literal-partner form of the same row.
  if n >= 10 { } else { return 8 }
  ## 9 — CONTROL: a `u64` target keeps the unsigned reading. Signed would answer true here.
  if below_ten(hi) { return 9 }
  ## 10 — CONTROL: the recovery's forward boundary.
  if cast_of_cmp(hi) != 0 { return 10 }
  99
}
