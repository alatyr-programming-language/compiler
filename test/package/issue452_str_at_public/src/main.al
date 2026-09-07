## Issue #452 / Stdlib appendix §3.6 — an external package must reach the fifth enumerated `str`
## operation through its public QUALIFIED path. §3.6 lists it as
## `str_at(in p : usize, in n : usize) -> str` — "raw view: `n` bytes at address `p`", the raw
## inverse of `bytes`, reinterpreting the bytes at an address in ONE step
## (`usize` -> `ptr(u8)` -> `[u8]` -> `str`) so a scanner walking a buffer by address (`base +
## offset`) names a lexeme without the three-line pointer dance. §8.2 items 2 and 6 make the
## enumerated operations required v1 content, and Modules §3 fixes a library's public API as exactly
## the pub-chain-to-root-reachable surface.
##
## Failure-first on parent 71ea8df (default build path, no ALATYR_OSPLIT): the qualified
## `base::str::str_at(...)` is rejected with `check: invalid at line 46 in main` (rc=1) because the
## declaration carries no visibility marker.
##
## The first parameter is the address held as a pointer-width unsigned integer (appendix §1
## Conventions; Type System §7). Fabricating a pointer back out of it is `bitcast` under an
## `unchecked` grant (Memory §4.5) — which is precisely why §3.6 calls the operation unchecked and
## says the unsafety is encapsulated in the one function instead of repeated at each call site.
##
## EVERY call below passes a `usize` address, spelled the way §3.6 spells it, and that is the point
## rather than a detail. A `ptr(u8)` argument would also be accepted — `tag_compat` (`src/sema.al`)
## makes int and pointer compatible in both directions on purpose, to model the `usize`/`ptr(T)`
## handle seam the lower already lowers identically — so a row carrying `b.ptr` would pass whatever
## the declared parameter type happened to be. That is exactly what makes it useless HERE: it cannot
## distinguish the specified signature from the one this fixture's parent declared, so it would
## assert nothing about the surface under test while reading as though it did. Keeping every argument
## a `usize` is what makes each row a statement about §3.6's signature.
##
## The two CONTROL rows are the unqualified and UFCS spellings. What they prove is reachability of
## the operation through the notation the appendix itself writes — Stdlib §1 injects the base prelude
## unqualified and Grammar §3.4 fixes `a.f(args)` == `f(a, args)`. They already resolved on the
## parent, through the unqualified arm's missing visibility test (#403), and must keep resolving:
## they are conformance coverage of the specified spelling, not the red measurement.
##
## Every rejection code is distinct and below 126 (WASI `proc_exit` rejects anything above), so no
## two failures can alias one another and none can be confused with the success value 42. Codes 3
## and 4 are deliberately unused: they belonged to a second qualified row that passed `b.ptr`, which
## was removed for the reason given above. The remaining codes are NOT renumbered, so this file's
## history stays readable against that removal.

main := fn() -> u64 {
  s := "hello"
  b := base::str::bytes(s)

  ## the qualified §3.6 path, argument spelled as §3.6 spells it — the address as a `usize`
  a := unchecked bitcast(usize, b.ptr)
  v := base::str::str_at(a, b.len)
  if v.len != 5 { return 1 }
  if v != "hello" { return 2 }

  ## `n` is honoured, so the view is a length-bounded window and not the whole string
  h := base::str::str_at(a, 4)
  if h.len != 4 { return 5 }
  if h != "hell" { return 6 }

  ## the `base + offset` scanner shape §3.6 names as the motivation: an address computed by
  ## arithmetic on the integer, viewed as three bytes
  o := base::str::str_at(a + 1, 3)
  if o.len != 3 { return 7 }
  if o != "ell" { return 8 }

  ## CONTROL — the bare prelude spelling (Stdlib §1), carrying the specified `usize` argument
  x := str_at(a, b.len)
  if x.len != 5 { return 9 }
  if x != "hello" { return 10 }

  ## CONTROL — the UFCS spelling the appendix intro writes (`a.f(args)` == `f(a, args)`,
  ## Grammar §3.4), also over the specified `usize` argument
  y := a.str_at(b.len)
  if y.len != 5 { return 11 }
  if y != "hello" { return 12 }

  42
}
