## Issue #430 / Declarations §6.1 — a nested block may shadow a PARAMETER, and all four backends must
## agree on WHICH binding a read of that name means. The WAT frame is flat (`local_slot_scan` gives
## one NAME one slot for the whole fn tree) and its `Var` read path resolved a parameter BEFORE a
## local, so the shadow's `:=` wrote a fresh slot while every read still reached the argument. On the
## parent that is `if p == 1 { p := 8 ; acc = p }` trapping with 134 on wasm where x86_64, aarch64 and
## riscv64 all answered, and the `while` form silently answering 6 where the other three answered 10.
## Registered with `run` (not `run_x86`), which is what puts it in the corpus the a64/rv64/wasm sweeps
## walk, so wasm actually executes it.
##
## Each shape is checked on its own with a distinct code from 100, and every accumulator multiplies
## before it adds, so a dropped, swapped or duplicated contribution names itself instead of aliasing
## into a commutative sum.
##
## What is deliberately NOT here: reading the parameter AGAIN after its shadowing block has ended, and
## a parameter shadowed by MORE THAN ONE block. On the parent those disagree between x86_64 and wasm
## for a reason that lives outside this backend, so asserting either side would make an over-rejection
## guard carry someone else's defect. They are #432.

Shape := enum { A(u64), B(u64) }

## THE issue shape: the shadow is read after its own `:=`, inside the block that binds it.
if_block := fn(p : u64) -> u64 {
  mut acc : u64 = 0
  if p == 1 {
    p := 8
    acc = acc * 10 + p
  }
  return acc
}

## The block is entered while `p` still means the PARAMETER: the read before the `:=` must be 3, and
## only the read after it is the shadow. A model that simply pointed every read at the shadow's slot
## would answer 08 here.
seed_before := fn(p : u64) -> u64 {
  mut acc : u64 = 0
  if p == 3 {
    acc = acc * 10 + p
    p := 8
    acc = acc * 10 + p
  }
  return acc
}

## The silent-miscompile form: on the parent this answered 6 on wasm where the other three answered
## 10. The body is re-entered three times and each entry rebinds `p`, so every digit must be the
## BINDING (5) and not the argument (3). The loop count is a literal on purpose — a `while i < p`
## bound would also be asserting where the outer binding ends, which is #432, not this fixture.
loop_body := fn(p : u64) -> u64 {
  mut acc : u64 = 0
  mut i : u64 = 0
  while i < 3 {
    p := 5
    acc = acc * 10 + p
    i = i + 1
  }
  return acc
}

## Two nesting levels: the outer block does not bind `p`, so its read and the inner condition are both
## still the parameter; only the inner block's read is the shadow.
two_levels := fn(p : u64) -> u64 {
  mut acc : u64 = 0
  if p == 2 {
    acc = acc * 10 + p
    if p == 2 {
      p := 9
      acc = acc * 10 + p
    }
  }
  return acc
}

## A `match` arm is a block too. Arm A binds `p`; arm B does not and must still see the parameter, so
## the two arms are probed in both directions.
arm_shadow := fn(p : u64, s : Shape) -> u64 {
  mut acc : u64 = 0
  match s {
    A(v) => { p := v + 1 ; acc = acc * 10 + p }
    B(v) => { acc = acc * 10 + v ; acc = acc * 10 + p }
  }
  return acc
}

## The shadow may have a different type. Reading the `u64` parameter here would be a non-zero (true)
## condition and answer 7; reading the `bool` shadow answers 3.
diff_type := fn(p : u64) -> u64 {
  mut acc : u64 = 0
  if p == 1 {
    p : bool = false
    if p { acc = acc * 10 + 7 } else { acc = acc * 10 + 3 }
  }
  return acc
}

## No shadowing at all — the second half of the same defect. A bare PARAMETER on the right of an `=`
## or of a `:=` was classified as an aggregate PLACE (a parameter's `: T` annotation was taken for a
## struct name without confirming it named one), so a plain scalar read went to the whole-aggregate
## copy arm and trapped.
bare_param := fn(a : u64, b : u64) -> u64 {
  mut acc : u64 = 0
  acc = a
  dup := b
  return acc * 10 + dup
}

main := fn() -> u64 {
  mut bad : u64 = 0
  if bad == 0 and if_block(1) != 8 { bad = 100 }
  if bad == 0 and seed_before(3) != 38 { bad = 101 }
  if bad == 0 and loop_body(3) != 555 { bad = 102 }
  if bad == 0 and two_levels(2) != 29 { bad = 103 }
  if bad == 0 and arm_shadow(1, Shape.A(6)) != 7 { bad = 104 }
  if bad == 0 and arm_shadow(1, Shape.B(4)) != 41 { bad = 105 }
  if bad == 0 and diff_type(1) != 3 { bad = 106 }
  if bad == 0 and bare_param(4, 5) != 45 { bad = 107 }
  if bad != 0 { return bad }
  return 42
}
