## issue #567 — a QUALIFIED call to an overloaded `base::num` declaration bound to the LAST-DECLARED
## overload instead of the one its arguments select. `base::num` declares each overflow-policy family
## eight times, in the order u8 u16 u32 u64 i8 i16 i32 i64, and `driver::d_qual_target` matched a
## callee by (module, tail NAME) alone, keeping the last hit — so every `u64` call ran the **i64**
## body. A clean compile, a clean run, and a SIGNED answer for an UNSIGNED call.
##
## The rows below are chosen so the two readings DISAGREE ON THE VALUE, not merely on a flag, because
## an exit status cannot see this — the parent's own wrong answers are ordinary-looking numbers:
##   * `checked_sub(1, 2)` — `None` unsigned, `Some(-1)` signed;
##   * `saturating_sub(1, 2)` — 0 unsigned, -1 (18446744073709551615) signed;
##   * `saturating_sub(0, u64::MAX)` — 0 unsigned, 1 signed;
##   * `overflowing_sub(1, 2)` — the same wrapped word either way, but the OVERFLOW FLAG is true
##     unsigned and false signed, so the flag is asserted separately from the word.
## Following #444 the signed half asserts NEGATIVE VALUES (-42, i64 MIN), not just exit codes, and it
## carries the boundary cases that have no positive counterpart: i64 MIN + (-1) and i64 MAX + 1.
##
## WHY THE `when` GUARD AND THE QUALIFIED SPELLING (measured; see #532's census and #568/#569). The two
## spellings of a prelude call reach the library on DISJOINT backends: bare/UFCS resolves on x86_64 and
## is an undefined callee on the other three, while `base::num::…` resolves on aarch64/riscv64/wasm and
## leaves x86_64 with an undefined mangled symbol at LINK. Worse, a BARE spelling of the same name
## ANYWHERE in the file un-resolves the qualified one. So the qualified calls live in
## `when target.arch != Arch.x86_64` declarations that x86_64 DROPS (it therefore links, and asserts
## only that the guard dropped them), and the bare-spelling control for x86_64 is a SEPARATE file,
## `test/issue567_x86_bare_control.al`. Those two routing gaps are #568/#569; this fixture is the
## wrong VALUE.
##
## Each NAME here is used at exactly ONE overload, so the program keeps one declaration per label and
## reaches the library on ALL THREE module-unaware backends — the defect and its fix are not
## wasm-specific, only the reachability that made it observable was. The companion
## `test/issue567_wasm_overload_pair.al` uses BOTH members of one name, which additionally needs the
## per-signature label the wat emitter now gives them.
##
## SHAPE CONSTRAINTS, all measured on this tree and all unrelated to #567: on aarch64/riscv64 a
## statement-position `match` is `brk #0 // unsupported match statement` when an arm holds a `return`,
## an `if`, or MORE THAN ONE statement — and when it is the SECOND such `match` in one function. So
## every arm below is a single assignment and every function holds at most one `match`, which is why
## the assertions are split across three guarded helpers.
##
## Parent (4619197): x86_64 42, aarch64 2, riscv64 2, wasm 2 — `checked_sub(1u64, 2u64)` answered
## `Some(-1)` on all three module-unaware backends. Fixed: 42 on all four. Every failure returns its
## own code (< 126, none aliasing 133/134).
uq := fn(one : u64, two : u64, zero : u64, umax : u64) -> u64 when target.arch != Arch.x86_64 {
  o1 : Option(u64) = base::num::checked_sub(one, two)
  mut g1 : u64 = 0
  match o1 { Some(v) => { g1 = 1 } None => { g1 = 2 } }
  if g1 != 2 { return 2 }
  s1 : u64 = base::num::saturating_sub(one, two)
  if s1 != 0 { return 3 }
  s2 : u64 = base::num::saturating_sub(zero, umax)
  if s2 != 0 { return 4 }
  p1 : (u64, bool) = base::num::overflowing_sub(one, two)
  if p1.0 != umax { return 5 }
  if p1.1 == false { return 6 }
  0
}
sq := fn(nforty : i64, ntwo : i64) -> u64 when target.arch != Arch.x86_64 {
  o3 : Option(i64) = base::num::checked_add(nforty, ntwo)
  mut v3 : i64 = 0
  match o3 { Some(v) => { v3 = v } None => { v3 = 0 } }
  if v3 != (0 - 42) { return 7 }
  s3 : i64 = base::num::saturating_add(nforty, ntwo)
  if s3 != (0 - 42) { return 8 }
  0
}
## i64 MIN + (-1) does not fit and saturates DOWNWARD; i64 MAX + 1 saturates UPWARD.
sb := fn(imin : i64, imax : i64, none : i64) -> u64 when target.arch != Arch.x86_64 {
  o4 : Option(i64) = base::num::checked_add(imin, none)
  mut g4 : u64 = 0
  match o4 { Some(v) => { g4 = 1 } None => { g4 = 2 } }
  if g4 != 2 { return 9 }
  s4 : i64 = base::num::saturating_add(imin, none)
  if s4 != imin { return 10 }
  s5 : i64 = base::num::saturating_add(imax, 1)
  if s5 != imax { return 11 }
  0
}
main := fn() -> u64 {
  one : u64 = 1
  two : u64 = 2
  zero : u64 = 0
  umax : u64 = 18446744073709551615
  nforty : i64 = 0 - 40
  ntwo : i64 = 0 - 2
  imin : i64 = 0 - 9223372036854775807 - 1
  imax : i64 = 9223372036854775807
  none : i64 = 0 - 1
  mut r : u64 = 0
  comptime if target.arch != Arch.x86_64 { r = uq(one, two, zero, umax) }
  if r != 0 { return r }
  comptime if target.arch != Arch.x86_64 { r = sq(nforty, ntwo) }
  if r != 0 { return r }
  comptime if target.arch != Arch.x86_64 { r = sb(imin, imax, none) }
  if r != 0 { return r }
  42
}
