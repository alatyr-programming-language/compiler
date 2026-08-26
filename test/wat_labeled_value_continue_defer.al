## Issue #44 bounded WAT slice: a scalar value-bearing loop accepts `continue name` from nested
## statement-only loop, while, and range-for bodies. Each transfer drains the nested defer before the
## target-loop defer in LIFO order, then the target eventually yields its scalar break value.
## Failure-first parent b52d1b2: x86_64=42, WAT=134; after the fix both targets must return 42.
mut ACC : u64 = 0
mut ONCE : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }

main := fn() -> u64 {
  ONCE = 0
  x_loop := @label(v_loop) loop {
    defer bump(1)
    if ONCE == 0 {
      ONCE = ONCE + 1
      loop {
        defer bump(2)
        continue v_loop
      }
    }
    break 7
  }
  if x_loop != 7 or ACC != 211 { return 1 }

  ACC = 0
  ONCE = 0
  x_while := @label(v_while) loop {
    defer bump(1)
    if ONCE == 0 {
      ONCE = ONCE + 1
      while ONCE == 1 {
        defer bump(2)
        continue v_while
      }
    }
    break 7
  }
  if x_while != 7 or ACC != 211 { return 2 }

  ACC = 0
  ONCE = 0
  x_for := @label(v_for) loop {
    defer bump(1)
    if ONCE == 0 {
      ONCE = ONCE + 1
      for i in 0 .. 1 {
        defer bump(2)
        continue v_for
      }
    }
    break 7
  }
  if x_for != 7 or ACC != 211 { return 3 }
  42
}
