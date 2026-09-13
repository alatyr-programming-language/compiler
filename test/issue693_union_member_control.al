## e2e — issue #693 CONTROL 4: a RAW UNION member read.
##
## This control exists because the census for this change found it. A raw union (Types §6.3) shares
## the front end's aggregate kind with an enum, so an owner test written on the kind alone would have
## refused every union member read in the tree — seven sites, in five landed fixtures. A union is not
## a discriminant plus one variant: §6.3 gives it named members and a canonical representation, and
## `u.a` is exactly how one is used. The refusal therefore excludes unions explicitly, and this row
## is what keeps that exclusion honest.
##
## 77 is written into member `a` and read straight back out.
U := union { a(u64), b(u64) }
main := fn() -> u64 {
  u := U.a(77)
  u.a
}
