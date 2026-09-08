## issue #567, the LABEL half. Its companion `test/issue567_overload_signedness.al` uses each family
## NAME at one overload, so one declaration per label survives the driver's prune. This one calls BOTH
## the `u64` and the `i64` member of the SAME name in one program, which is the shape #532's fixture
## already has and the shape the wat emitter could not name: it labels a function by its BARE source
## identifier, so two members of one overload set collided on `$saturating_sub`.
##
## Before, the collision never happened because `driver::d_qual_target` resolved both calls to the
## LAST-declared (i64) member — one label, and the unsigned call silently running the signed body.
## Resolving each call to its own member makes the pair real, so `wat.al` now suffixes both the
## definition and the rewritten call with the decl's parameter signature (`$saturating_sub__u64_u64`
## vs `$saturating_sub__i64_i64`), derived from the SAME `Decl` on both sides so they cannot drift.
##
## The two readings disagree on the VALUE, not on a flag: `saturating_sub(1, 2)` is 0 unsigned and -1
## signed, `saturating_sub(0, u64::MAX)` is 0 unsigned and 1 signed, and the signed rows assert
## NEGATIVE VALUES and the i64 MIN boundary (#444).
##
## BACKENDS. aarch64 labels a non-generic definition `<module>__<fn>` and riscv64 labels it with the
## bare name — module-qualified at best, and with NO signature either way — so neither can separate
## the pair. `d_kept_name_clash` therefore keeps dropping the injected closure for them and both now
## trap LOUD on the undefined callee (133) where the PARENT answered 20, the same wrong value wasm
## did: a trap is acceptable, a wrong value is not, and giving those two a signature-bearing label is
## #475's remaining half. x86_64 drops the guarded declarations (#568), so its row asserts only that
## the guard dropped them. The qualified spelling and the absence of any bare spelling of these names
## are load-bearing — see the companion fixture's header, and #569.
##
## Parent (4619197): x86_64 42, aarch64 20, riscv64 20, wasm 20 — the unsigned `saturating_sub(1, 2)`
## answered 18446744073709551615, so the `!= 0` assertion returned 20 on all three.
## Fixed: x86_64 42, aarch64 133, riscv64 133, wasm 42.
pq := fn(one : u64, two : u64, zero : u64, umax : u64) -> u64 when target.arch != Arch.x86_64 {
  su : u64 = base::num::saturating_sub(one, two)
  if su != 0 { return 20 }
  s0 : u64 = base::num::saturating_sub(zero, umax)
  if s0 != 0 { return 21 }
  0
}
pi := fn(one : i64, two : i64, imin : i64, ione : i64) -> u64 when target.arch != Arch.x86_64 {
  si : i64 = base::num::saturating_sub(one, two)
  if si != (0 - 1) { return 22 }
  ## i64 MIN - 1 does not fit and saturates DOWNWARD, where the unsigned member would answer 0.
  sm : i64 = base::num::saturating_sub(imin, ione)
  if sm != imin { return 23 }
  0
}
main := fn() -> u64 {
  one : u64 = 1
  two : u64 = 2
  zero : u64 = 0
  umax : u64 = 18446744073709551615
  ione : i64 = 1
  itwo : i64 = 2
  imin : i64 = 0 - 9223372036854775807 - 1
  mut r : u64 = 0
  comptime if target.arch != Arch.x86_64 { r = pq(one, two, zero, umax) }
  if r != 0 { return r }
  comptime if target.arch != Arch.x86_64 { r = pi(ione, itwo, imin, ione) }
  if r != 0 { return r }
  42
}
