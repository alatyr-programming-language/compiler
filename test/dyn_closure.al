## FN-11 — the type-erased `dyn fn(T…)->R` closure over EXPLICIT storage (x86_64).
## Two DIFFERENT capturing closures (add-a / add-b for different captured values) are lifted to static
## closures held in named places (`s1`/`s2`), erased to a uniform `dyn fn(u64)->u64` fat `{code, env}`
## pair via `dyn_over(ptr(…))` — env borrows the named place, no hidden allocation (I3) — and called
## through the fat pair (`d(x)` = one indirect call through `code`, passing `env`).
## `ptr(s1)` is the canonical spelling (Functions §1.6, spec#152): `s1`/`s2` are immutable places, and
## Memory §4.4 gives an immutable place only the read-only address.
##   d1 = add-10, d2 = add-20 ;  d1(2) + d2(10) = (2+10) + (10+20) = 12 + 30 = 42
main := fn() -> u64 {
  a := 10
  s1 := fn(x : u64) -> u64 { return x + a }
  b := 20
  s2 := fn(x : u64) -> u64 { return x + b }
  d1 : dyn fn(u64) -> u64 = dyn_over(ptr(s1))
  d2 : dyn fn(u64) -> u64 = dyn_over(ptr(s2))
  return d1(2) + d2(10)
}
