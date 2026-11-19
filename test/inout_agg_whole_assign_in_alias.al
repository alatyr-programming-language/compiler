## e2e — #1760's review: `inc(s, s)` with `inc := fn(in out p : P, x : P)`. Functions §4.1 passes `x`
## as a copy of the caller's value and `p` by reference to the caller's place, so the whole store
## `p = P(a = 30, b = 30)` reaches `s` but never `x`: `inc` answers the old 10 + 11 = 21, from each of its
## two callers. `ir_side` is built by the IR; `main` stays on each backend's legacy emitter (its generic
## call `id(u64, 0)` is refused by the IR). 21 + 21 = 42.
## Every legacy caller passes an `in` aggregate argument as its own place, not a copy (#1637), so an
## IR-built `inc` would answer 60 to `main`: a silent wrong value. The IR therefore does not build the
## whole store while `inc` takes an `in` parameter that may alias `p`, and each legacy emitter refuses
## `inc` at its entry, located. The build is refused on every backend until #1637 is fixed
## (scripts/known-deviations.tsv); it must never run to anything but 42.
## spec: Functions §2.1, §2.3, §4.1
## expect: run 42
P := struct { a : u64, b : u64 }

id := fn(T : type, x : T) -> T { x }

inc := fn(in out p : P, x : P) -> u64 {
  p = P(a = 30, b = 30)
  x.a + x.b
}

ir_side := fn() -> u64 {
  mut s := P(a = 10, b = 11)
  inc(s, s)
}

main := fn() -> u64 {
  mut t := P(a = 10, b = 11)
  r := inc(t, t)
  ir_side() + r + id(u64, 0)
}
