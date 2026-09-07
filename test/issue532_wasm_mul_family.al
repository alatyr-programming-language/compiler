## issue #532 — the overflow-policy MULTIPLY family kept the LEFT OPERAND as its high word on a target
## whose high-half intrinsic arm is absent, so every non-zero `a` reported overflow. `checked_mul`,
## `overflowing_mul` and `saturating_mul` derive the flag from `mut hi := a` followed by
## `comptime if target.arch == Arch.{x86_64,aarch64,riscv64}`; `Arch` has NO wasm variant (Manifest §3.2
## / Assembly §10 name six machines and WASM is an ADDITIVE backend, FND-6 — see `wat_target_arch` in
## `src/wat.al`), so on the wat emitter EVERY arm folds false, `hi` stays `a`, and `checked_mul(7, 6)`
## answered `None` — a clean compile with the wrong answer. The fix gives those six bodies a portable
## division-based fall-through (`a != 0 and w / a != b`) under the complementary `comptime if`.
##
## WHY THE `when` GUARD AND THE QUALIFIED SPELLING. Measured on this tree, the two spellings of a
## prelude call reach the library on DISJOINT backends:
##   * bare `checked_mul(a, b)` resolves on x86_64 and is an "undefined/builtin callee" on
##     aarch64 / riscv64 / wasm (a LOUD `brk #0` / `(unreachable)`, exit 133/134) — so the bare spelling
##     cannot observe this defect at all;
##   * qualified `base::num::checked_mul(a, b)` resolves on wasm but leaves x86_64 with an undefined
##     `base__num__checked_mul__u64_u64` at LINK, and adding a bare spelling ANYWHERE in the same file
##     un-resolves the qualified one on wasm too.
## So the qualified calls live in `when target.arch != Arch.x86_64` declarations: x86_64 DROPS them (it
## therefore links, and asserts only that the guard dropped them — `main` returns 42 with nothing else
## run), aarch64/riscv64 keep them and trap LOUD on the undefined callee (133), and wasm both keeps and
## resolves them — the one backend where the wrong value was reachable. Those two routing gaps are
## separate issues; this fixture is the wrong VALUE.
##
## The wat emitter has no overload mangling either, so all eight `checked_mul` overloads collapse onto
## the LAST declared one (the `i64` body). Every assertion below therefore holds under BOTH the `u64`
## and the `i64` reading: 7*6, 9*0, 0*9 and 2^32*2^32 agree on value and on flag either way, and the
## signed half is asserted with i64 locals directly. Following #444, the signed rows assert NEGATIVE
## VALUES (-42, i64 MIN), not just exit codes.
##
## Parent (038e8ea): x86_64 42, aarch64 133, riscv64 133, wasm 2 — `checked_mul(7, 6)` was `None`.
## Fixed: wasm 42. Every failure below returns its own code (< 126, none aliasing 133/134).
uq := fn(a : u64, b : u64, big : u64) -> u64 when target.arch != Arch.x86_64 {
  o1 : Option(u64) = base::num::checked_mul(a, b)
  match o1 { Some(v) => { if v != 42 { return 3 } } None => { return 2 } }
  o2 : Option(u64) = base::num::checked_mul(9, 0)
  match o2 { Some(v) => { if v != 0 { return 5 } } None => { return 4 } }
  o3 : Option(u64) = base::num::checked_mul(0, 9)
  match o3 { Some(v) => { if v != 0 { return 7 } } None => { return 6 } }
  ## 2^32 * 2^32 = 2^64: the wrapped product is 0 and the high word is 1 under either reading.
  o4 : Option(u64) = base::num::checked_mul(big, big)
  match o4 { Some(v) => { return 8 } None => {} }
  p1 : (u64, bool) = base::num::overflowing_mul(a, b)
  if p1.0 != 42 { return 9 }
  if p1.1 { return 10 }
  p2 : (u64, bool) = base::num::overflowing_mul(big, big)
  if p2.0 != 0 { return 11 }
  if p2.1 == false { return 12 }
  s1 : u64 = base::num::saturating_mul(a, b)
  if s1 != 42 { return 13 }
  s2 : u64 = base::num::saturating_mul(9, 0)
  if s2 != 0 { return 14 }
  0
}
sq := fn(na : i64, sb : i64, mn : i64) -> u64 when target.arch != Arch.x86_64 {
  o5 : Option(i64) = base::num::checked_mul(na, sb)
  match o5 { Some(v) => { if v != (0 - 42) { return 16 } } None => { return 15 } }
  s3 : i64 = base::num::saturating_mul(na, sb)
  if s3 != (0 - 42) { return 17 }
  p3 : (i64, bool) = base::num::overflowing_mul(na, sb)
  if p3.0 != (0 - 42) { return 18 }
  if p3.1 { return 19 }
  ## i64 MIN * 1 fits exactly and its true high word is -1, not `a`.
  o6 : Option(i64) = base::num::checked_mul(mn, 1)
  match o6 { Some(v) => { if v != mn { return 21 } } None => { return 20 } }
  ## i64 MIN * -1 is the one product that does not fit; the fall-through must NOT divide by -1 here.
  o7 : Option(i64) = base::num::checked_mul(mn, 0 - 1)
  match o7 { Some(v) => { return 22 } None => {} }
  0
}
main := fn() -> u64 {
  a : u64 = 7
  b : u64 = 6
  big : u64 = 4294967296
  na : i64 = 0 - 7
  sb : i64 = 6
  mn : i64 = 0 - 9223372036854775807 - 1
  mut r : u64 = 0
  comptime if target.arch != Arch.x86_64 { r = uq(a, b, big) }
  if r != 0 { return r }
  comptime if target.arch != Arch.x86_64 { r = sq(na, sb, mn) }
  if r != 0 { return r }
  42
}
