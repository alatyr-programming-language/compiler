## #651 — the three non-x86 backends recover a local's declared type for their SIGNEDNESS decision
## by scanning the source, and that scan walked only the TOP-LEVEL statement list of the function
## body: every nested arm was stepped past. Two shapes therefore never resolved and both fell to the
## backends' UNSIGNED default.
##
##   1. a local DECLARED INSIDE A BLOCK — `mut k : i64 = neg()` in an `if`/`while`/`loop`/`match`
##      arm. The annotation is right there in the source and the scan never reached it, so `k + 1`
##      took the unsigned CARRY guard while `k < hi` beside it kept the SIGNED comparison. At k = -1
##      the two disagree and the guard traps a program the language defines.
##   2. a local INFERRED FROM ARITHMETIC — `d := m - 1` records no annotation to find at all, so an
##      enclosing `d + p` took the unsigned guard, and `d / 2`, `d % 4`, `shr(d, 1)` took the
##      unsigned INSTRUCTION and returned a WRONG NUMBER from a clean run.
##
## Types §3.2 puts signedness in the operations — "the operand's interpretation picks the intrinsic
## exactly as it does for `+` and `<`" — so one operand cannot be signed for the compare and
## unsigned for the add, nor signed for `+` and unsigned for `/`. Concurrency §6.1 traps only an
## operation that OVERFLOWS, and neither -1 + 1 nor -2 + -3 overflows i64. x86_64 answers both
## shapes already (the slot map plus `lower::infer_local_scalar_type`), and is the control.
##
## MEASURED ON THE PARENT (f81caf6, the #646 repair): x86_64 answers 42; aarch64 and riscv64 exit
## 133 and wasm 134 on the guard shapes, and all three exit 1 — a clean run with the wrong number —
## on the division/remainder/shift shapes. Both classes reproduce identically on b61bfa4, so this is
## pre-existing and not a regression of #646.
##
## Every nesting level and every missing annotation below is LOAD-BEARING. Lift a declaration to the
## function's top level, or annotate a `d`/`p`/`q`, and the flat scan already finds it and that
## function passes on the unfixed compiler. A reduction that does either proves nothing.
neg := fn() -> i64 { 0 - 1 }

## SHAPE 1, one block deep, in an `if` arm.
block_if := fn() -> i64 {
  mut r : i64 = 0
  if r == 0 {
    mut k : i64 = neg()
    k = k + 1
    r = r + k
  }
  r
}

## SHAPE 1, three blocks deep (`if` > `while` > `if`), so a repair that descends only one level
## does not pass.
block_deep := fn(sel : u64) -> i64 {
  mut out : i64 = 7
  if sel == 1 {
    mut go := true
    while go {
      if out == 7 {
        mut n : i64 = neg()
        n = n + 1
        out = out + n
      }
      go = false
    }
  }
  out
}

## SHAPE 1, in a `while` arm and in a `loop` arm — the two block carriers an `if`-only descent
## would miss.
block_while_loop := fn() -> i64 {
  mut acc : i64 = 0
  mut i := 0
  while i < 1 {
    mut w : i64 = neg()
    w = w + 1
    acc = acc + w
    i = i + 1
  }
  mut j := 0
  loop {
    if j > 0 { break }
    mut l : i64 = neg()
    l = l - 1
    acc = acc - l
    j = j + 1
  }
  acc
}

## SHAPE 1, in a `match` arm.
block_match := fn(sel : u64) -> i64 {
  mut r : i64 = 0
  match sel {
    0 => {
      mut m : i64 = neg()
      m = m * 3
      r = r + m
    }
    _ => { r = 9 }
  }
  r
}

## SHAPE 2 — the guard. `d` and `p` are inferred from arithmetic over a signed local, so neither
## carries an annotation the scan could read, and `0 + d + p` at -2 + -3 trapped.
bin_inferred_sum := fn() -> i64 {
  mut m : i64 = neg()
  d := m - 1
  p := m * 3
  0 + d + p
}

## SHAPE 2 — the WRONG VALUE. `/`, `%` and `shr` select the instruction, not a guard, so these three
## ran to completion and returned the unsigned answer.
bin_inferred_div := fn() -> i64 {
  mut m : i64 = neg()
  d := m - 1
  d / 2
}

bin_inferred_mod := fn() -> i64 {
  mut m : i64 = neg()
  d := m * 7
  d % 4
}

bin_inferred_shr := fn() -> i64 {
  mut m : i64 = neg()
  d := m * 4
  shr(d, 1)
}

## THE OTHER DIRECTION MUST NOT MOVE. `s := u + 1` over a `u64` is a `Bin`-inferred local too, and
## the widened signed proof must decline it: it requires BOTH operands proven signed (or one proven
## plus a bare literal), which a proven-UNSIGNED partner is not. The value chosen makes the two
## readings disagree — 18446744073709551611 / 2 is 9223372036854775805 unsigned and -3 signed — so
## this assertion FAILS the moment the proof claims an operand it has not proven. That direction is
## #546's question and stays there.
bin_unsigned_untouched := fn() -> u64 {
  u : u64 = 18446744073709551610
  s := u + 1
  s / 2
}

main := fn() -> u64 {
  if block_if() != 0 { return 1 }
  if block_deep(0) != 7 { return 2 }
  if block_deep(1) != 7 { return 3 }
  if block_while_loop() != 2 { return 4 }
  if block_match(0) != 0 - 3 { return 5 }
  if block_match(1) != 9 { return 6 }
  if bin_inferred_sum() != 0 - 5 { return 7 }
  if bin_inferred_div() != 0 - 1 { return 8 }
  if bin_inferred_mod() != 0 - 3 { return 9 }
  if bin_inferred_shr() != 0 - 2 { return 10 }
  if bin_unsigned_untouched() != 9223372036854775805 { return 11 }
  return 42
}
