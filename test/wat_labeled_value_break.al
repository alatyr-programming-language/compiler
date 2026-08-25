## Issue #44 bounded WAT slice: scalar integer-valued `break outer <expr>` from nested statement-only
## loop, while, and range-for bodies into an enclosing value-bearing `@label(outer) loop`.
## Failure-first baseline on parent origin/main e82a54e2686c3fd10ca00fa02ef5d8e4b87af8b9: x86_64=25,
## WAT=134. After the fix both targets must return 25.
## Each case evaluates the value expression `bump(4) + 4` before the inner defer bump(2) and outer defer
## bump(1) drain. The resulting trace is 421 (value evaluation, then LIFO cleanup); each checked case computes
## 425 and returns a distinct low exit on an order/value regression. Aggregate/tuple/enum/str values and
## other control-flow forms remain outside this bounded slice and must stay fail-loud.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC * 10 + n ; 0 }

main := fn() -> u64 {
  x_loop := @label(outer) loop {
    defer bump(1)
    loop {
      defer bump(2)
      break outer (bump(4) + 4)
    }
    break 9
  }
  first := ACC + x_loop
  if first != 425 { return 1 }
  ACC = 0
  mut once : u64 = 0
  x_while := @label(outer) loop {
    defer bump(1)
    while once < 1 {
      defer bump(2)
      break outer (bump(4) + 4)
    }
    break 9
  }
  second := ACC + x_while
  if second != 425 { return 2 }
  ACC = 0
  x_for := @label(outer) loop {
    defer bump(1)
    for i in 0 .. 1 {
      defer bump(2)
      break outer (bump(4) + 4)
    }
    break 9
  }
  if ACC + x_for != 425 { return 3 }
  25
}
