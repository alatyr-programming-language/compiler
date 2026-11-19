## e2e — #1760's review, N1: the reverse of test/inout_agg_whole_assign_in_alias.al. `inc(t, t.inner)`
## with `inc := fn(in out q : Q, x : P)` and `Q := struct { inner : P }`: the `in` parameter `x` is a part
## of the `in out` target, not the other way round. Functions §4.1 passes `x` as a copy, so the whole store
## `q = Q(inner = P(a = 30, b = 30))` reaches `t` but never `x`: `inc` answers the old 10 + 11 = 21, from
## each of its two callers. `ir_side` is meant for the IR; `main` stays on each backend's legacy emitter
## (its generic call `id(u64, 0)` is refused by the IR). 21 + 21 = 42.
## A legacy caller passes `t.inner` as its own place, not a copy (#1637), so an IR-built `inc` would answer
## 60 to `main`. Today the IR refuses `inc`'s signature first (a struct parameter with an aggregate field);
## when that lifts, `ir::build`'s alias guard (`ib_in_param_may_hold`, both directions) keeps the store
## unbuilt and each legacy emitter refuses `inc` at its entry, located. The build is refused on every
## backend until #1637 is fixed (scripts/known-deviations.tsv); it must never run to anything but 42.
## spec: Functions §2.1, §2.3, §4.1
## expect: run 42
P := struct { a : u64, b : u64 }
Q := struct { inner : P }

id := fn(T : type, x : T) -> T { x }

inc := fn(in out q : Q, x : P) -> u64 {
  q = Q(inner = P(a = 30, b = 30))
  x.a + x.b
}

ir_side := fn() -> u64 {
  mut s := Q(inner = P(a = 10, b = 11))
  inc(s, s.inner)
}

main := fn() -> u64 {
  mut t := Q(inner = P(a = 10, b = 11))
  r := inc(t, t.inner)
  ir_side() + r + id(u64, 0)
}
