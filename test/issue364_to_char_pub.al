## Issue #364, library half — `base::char::to_char` is `pub`, so the conversion-constructor that
## Stdlib §3.2 gives to `char(n)` is in scope for a caller at all.
##
## Types §4.6, "Scope, not coherence": "A `@convert` is an ordinary `pub` binding, found by the
## **name-resolution rules in effect at the call site** (Comptime §6.1): it participates in `T(v)`
## exactly where it is in scope (imported)." TYP-14 (spec `730486f`, released as 1.7.0) states the
## stdlib consequence directly: "The stdlib's `to_char` becomes **`pub`** (an unimportable conversion
## is not 'in scope' for anyone, so option 1 would be inert otherwise)."
##
## PARENT `c00eae90`, native x86_64, Stage1 built by the committed seed: REFUSED. `alatyr check` on
## this file printed `alatyr: check: invalid at line 21 in issue364_to_char_pub` and exited 1, and
## the aarch64, riscv64 and wat emit paths refused at the same line with the same status — because
## `lib/base/char.al` declared `to_char := @convert fn(n : u32) -> char` without `pub`.
##
## WITH THE FIX (`pub to_char`) the same four backends build and exit 42.
##
## Only a valid code point is asserted here. The out-of-range guard is not: §3.2 makes it fail through
## `trap()`, and a call to that intrinsic does not link yet (#1427), while `char(n)` itself still
## takes the unguarded brand crossing — the dispatch half of #364, which stays open.
main := fn() -> u64 {
  c := base::char::to_char(65)
  if u32(c) != 65 { return 1 }
  42
}
## expect: run 42
