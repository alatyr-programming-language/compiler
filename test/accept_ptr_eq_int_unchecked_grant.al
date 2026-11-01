## The dual of `reject_ptr_eq_int_outside_grant.al` (#1030 option B, owner decision · Memory §4.5):
## the SAME comparison, INSIDE an `unchecked` grant, must stay ACCEPTED and run.
##
## Memory §4.5 makes a pointer fabricated from an integer ill-formed OUTSIDE a grant; inside one the
## crossing is spelled out and legal. Option B puts the comparison on the same rule as the fabrication,
## so this fixture is the half that proves the enforcement is a GRANT and not a ban: if it were a ban,
## this program would refuse too and the strict form would be unimplementable in the places the spec
## already allows.
##
## `p` is non-null by construction (4096), so the comparison is false and the program returns 42. The
## value is load-bearing: it proves the comparison was not merely tolerated but evaluated.
main := fn() -> u64 {
  p : ptr(u8) = unchecked bitcast(ptr(u8), 4096)
  mut hit : u64 = 0
  unchecked {
    if p == 0 { hit = 1 }
  }
  return 42 + hit
}
## expect: run 42
