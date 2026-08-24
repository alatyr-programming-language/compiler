## e2e — TYP-10 ADMISSIBILITY (Types §7 / TYP-10): `uint(N)` admits only a POSITIVE MULTIPLE OF
## 64 — a partial-top-word width is out of v1 scope (its mask/carry rules are unpinned).
## `uint(100)` (100 = 64 + 36, not a multiple of 64) must FAIL LOUD at compile time: the comptime
## array-length fold `[u64; N/64]` rejects the inexact division rather than silently laying out
## trunc(100/64) = 1 word (a 64-bit type masquerading as 100 bits — a silent miscompile). The
## bare `uint(` pulls the prelude `lib/base/u128.al` through ambient injection (no local decl),
## so this probes the SHIPPED recipe, not a local copy. build_reject: any non-zero build rc.
main := fn() -> u64 {
  x := uint(100)(words = [0])
  x.words[0]
}
