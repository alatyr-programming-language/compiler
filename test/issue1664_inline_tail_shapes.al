## e2e — #1664, the shapes around the fix. `outer`/`inner` are a NESTED `@inline` chain whose bodies
## each end in a bare expression (the inner expansion's value must survive into the outer one);
## `retter` is the SAME statement-body shape spelled with `return`, which already worked and must keep
## working — the fix emits a tail only when the body HAS one, so `return` still delivers once; `mk`
## ends in a nominal-struct expression, delivered through the struct return registers. Each arm owes
## 42: `outer(20)` = inner(20) + 2 = 40 + 2, `retter(20)` = (20 + 1) * 2 = 42 at the spelled width,
## `mk(40)` = (40, 2) read back as x + y. A wrong value anywhere leaves `ok` below 3 and the fixture
## answers that number instead of 42.
Vec := struct { x : u64, y : u64 }
@inline inner := fn(x : u64) -> u64 {
  d : u64 = x * 2
  d
}
@inline outer := fn(k : u64) -> u64 {
  z : u64 = inner(k)
  z + 2
}
@inline retter := fn(q : u64) -> u64 {
  w : u64 = q + 1
  return w * 2
}
@inline mk := fn(k : u64) -> Vec {
  p : Vec = Vec(x = k, y = 2)
  p
}
main := fn() -> u64 {
  mut ok : u64 = 0
  if outer(20) == 42 { ok = ok + 1 }
  if retter(20) == 42 { ok = ok + 1 }
  r := mk(40)
  if r.x + r.y == 42 { ok = ok + 1 }
  if ok == 3 { return 42 }
  ok
}
## expect: run 42
