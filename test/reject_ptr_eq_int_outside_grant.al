## e2e reject (#1030 option B, owner decision · Memory §4.5 · Types §9.4): a pointer meeting an
## INTEGER AT A COMPARISON is ill-formed outside an `unchecked` grant.
##
## `p == 0` is how a fabricated pointer gets tested for null without `Option`. It passed `check` with
## rc=0 on the tree compiler AND on the committed seed 0.2.16 — measured, and counted by the #529
## census as an `OP-CMP` place (`#529 OP-CMP sym bincmp … |return p == 0`). The census could SEE it
## and nothing REFUSED it; that gap between detecting a form and rejecting it is what this fixture
## closes.
##
## The cause was `ty_kinds_compat`, which declares the #529 seam (TyInt<->TyPtr) compatible at the
## single funnel every compatibility site reaches, so `ty_eq` answered TRUE here. The fix is scoped to
## the COMPARISON arm, not to the funnel: binding, argument and result sites keep their verdict in this
## slice, so the reject is exactly the form the owner named and nothing else.
##
## The grant form is the dual fixture `accept_ptr_eq_int_unchecked_grant.al`.
main := fn() -> u64 {
  p : ptr(u8) = unchecked bitcast(ptr(u8), 4096)
  if p == 0 { return 1 }
  return 42
}
