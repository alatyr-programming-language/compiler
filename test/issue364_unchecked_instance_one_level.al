## Issue #364 — which instance of a mode-polymorphic conversion a `T(v)` site runs (Comptime §7.5, CT-11).
##
## Comptime §7.5 (v1.8.0): "A function whose body reads `verify.checked` is **mode-polymorphic**: like a
## function generic over a comptime value, it is **instantiated per the verification mode of each call
## site** … The mode reaches **only** the observing functions, one level deep (a call inside a
## mode-polymorphic body runs at that body's own lexical mode unless re-scoped)." Types §4.6 selects the
## in-scope `@convert` for a branded target "checked or unchecked alike".
##
## Each conversion below appends one digit to `SEEN` from its `comptime if verify.checked` branches, so
## the run spells out which instance every site ran — no trap needed, so every backend can answer:
##   `Lvl(5)`            checked instance of `to_lvl`                                  → 1
##   `unchecked Lvl(5)`  unchecked instance of `to_lvl`                                → 2
##   `unchecked Wrap(5)` unchecked instance of `to_wrap`; its own `Lvl(n)` is lexically
##                       checked, so it runs the CHECKED `to_lvl` (one level deep)     → 1, then 4
##   `Wrap(5)`           checked `to_wrap`, checked `to_lvl`                           → 1, then 3
## so `SEEN` must read 121413.
##
## Each body builds its result as `Lvl(n)` / `Wrap(…)` — the site that names the conversion being
## compiled. Types §4.6, Termination: "Step (2) does not re-select the conversion whose own body is being
## compiled: inside a `@convert` to a brand, `T(v)` over the type that brand directly brands resolves at
## step (3) to the **brand** crossing (§4.2)". Re-selecting it would recurse until `SEEN * 10` overflows.
##
## Before the fix, the x86_64 lower emitted each body once, in checked mode, and called it from every
## site (111313, exit 2), and `Lvl(n)` inside `to_lvl` re-selected `to_lvl` (an overflow trap). Before
## the brand peel was narrowed (#364's first half), no `@convert` ran at all: 0 (exit 1).
Lvl := brand(u64)
Wrap := brand(u64)

mut SEEN : u64 = 0

to_lvl := @convert fn(n : u64) -> Lvl {
  comptime if verify.checked { SEEN = SEEN * 10 + 1 } else { SEEN = SEEN * 10 + 2 }
  Lvl(n)
}

to_wrap := @convert fn(n : u64) -> Wrap {
  l := Lvl(n)
  comptime if verify.checked { SEEN = SEEN * 10 + 3 } else { SEEN = SEEN * 10 + 4 }
  Wrap(u64(l))
}

main := fn() -> u64 {
  a := Lvl(5)
  b := unchecked Lvl(5)
  c := unchecked Wrap(5)
  d := Wrap(5)
  if u64(a) + u64(b) + u64(c) + u64(d) != 20 { return 3 }
  if SEEN == 0 { return 1 }
  if SEEN == 111313 { return 2 }
  if SEEN != 121413 { return 4 }
  42
}
## expect: run 42
