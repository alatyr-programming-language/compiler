## Issue #403 — every shape the bare-spelling tightening must LEAVE ALONE, with a distinct rejection
## code each, so a single regressed shape is named rather than absorbed into a wrong total.
##
##   1. Stdlib §1 injects the base prelude UNQUALIFIED, so a `pub` base-tier name must stay reachable
##      bare: `byte_len` / `chars` / `next` (appendix §3.6, §2.4) and `wrapping_add` (§4.3).
##   2. Modules §3 lines 80-85: a module names its OWN private helper (`geo::run` -> bare `helper`).
##   3. The same lines: a DESCENDANT names its ANCESTOR's private helper bare (`geo::child`).
##   4. A parse-time DESUGAR writes a callee nobody named: `defer` synthesizes `__deferblk` /
##      `__defer` spans. §3 line 73 scopes visibility to who may *name* a declaration, so a
##      synthesized span is exempt, and a capturing lambda keeps its captured local.
##
## The other two synthesized-callee shapes have their own corpus rows and are not duplicated here:
## `@alloc(a) x := init` -> `test/ambient_alloc_attr.al` / `test/ambient_alloc_scalar.al`, and the
## deep-cloned `__hoflam<fnpos>` closure -> `test/map_capture.al`.
mut ACC : u64 = 0
bump := fn(n : u64) -> u64 { ACC = ACC + n ; 0 }
deferred := fn() -> u64 {
  defer bump(1)
  defer bump(2)
  0
}

main := fn() -> u64 {
  s := "abc"
  ## the qualified reference is what pulls `lib/base/str.al` into the compile (the ambient trigger is
  ## a literal text scan); the BARE spellings below are what this control is about.
  if base::str::byte_len(s) != 3 { return 1 }
  if byte_len(s) != 3 { return 8 }

  mut cur := chars("Aé")
  c0 := unwrap(char, next(cur))
  if u32(c0) != 65 { return 2 }

  if wrapping_add(u64(40), u64(2)) != 42 { return 3 }

  if geo::run() != 7 { return 4 }
  if geo::child::from_ancestor() != 11 { return 5 }

  d := deferred()
  if ACC != 3 or d != 0 { return 6 }

  k := 2
  f := fn(x : u64) -> u64 { return x * k }
  if f(21) != 42 { return 7 }

  42
}
