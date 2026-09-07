## issue #567 — the x86_64 CONTROL. #567 is about the module-unaware backends' qualified-callee
## resolution binding a `u64` call to the last-declared (`i64`) overload. x86_64 never uses that
## resolution: it has its own per-signature machinery (`lower::emit_overload_suffix` /
## `lower::emit_sig_suffix`) and reaches the library through the BARE spelling instead — a qualified
## call to an overloaded `base::` declaration does not even LINK there (#568), which is exactly why
## the sweeps never compared the two backends on this shape and the wrong value stayed invisible.
##
## So this file asserts the SAME numbers as `test/issue567_overload_signedness.al` through the BARE
## spelling, on x86_64, and must keep answering 42 both before and after #567's fix: it is the control
## that says the fix did not disturb the one backend that was already right. It lives in its own file
## because a bare spelling of these names anywhere in a file un-resolves the qualified ones (#569).
##
## `run_x86` for the reason `test/overload_policy.al` is: the scalar numeric operators the library
## rests on are x86_64-gated, so the other three backends have nothing to compare against here.
##
## Parent and fixed: 42. Every failure returns its own code (< 126).
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
  o1 : Option(u64) = checked_sub(one, two)
  mut g1 : u64 = 0
  match o1 { Some(v) => { g1 = 1 } None => { g1 = 2 } }
  if g1 != 2 { return 2 }
  s1 : u64 = saturating_sub(one, two)
  if s1 != 0 { return 3 }
  s2 : u64 = saturating_sub(zero, umax)
  if s2 != 0 { return 4 }
  p1 : (u64, bool) = overflowing_sub(one, two)
  if p1.0 != umax { return 5 }
  if p1.1 == false { return 6 }
  o3 : Option(i64) = checked_add(nforty, ntwo)
  mut v3 : i64 = 0
  match o3 { Some(v) => { v3 = v } None => { v3 = 0 } }
  if v3 != (0 - 42) { return 7 }
  s3 : i64 = saturating_add(nforty, ntwo)
  if s3 != (0 - 42) { return 8 }
  o4 : Option(i64) = checked_add(imin, none)
  mut g4 : u64 = 0
  match o4 { Some(v) => { g4 = 1 } None => { g4 = 2 } }
  if g4 != 2 { return 9 }
  s4 : i64 = saturating_add(imin, none)
  if s4 != imin { return 10 }
  s5 : i64 = saturating_add(imax, 1)
  if s5 != imax { return 11 }
  42
}
