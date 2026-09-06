## e2e — Stdlib appendix §3.6 + §2.4: `base::str::split(s : ptr(str), sep : u8) -> SplitIter` is
## the base library's only `ptr(str)` entry point, so it inherited the #451 field read: `deref(s)`
## delivered one word, `ss.len` read a never-written slot, and the returned iterator was EMPTY.
##
## Failure-first on the parent (`origin/main` 5eb6739, x86_64, default build path, frozen-seed
## Stage1): this file exits 20 — `split(ptr(s), 44)` over the eight-byte subject `"a,bb,ccc"`
## returned a `SplitIter` whose `len` was 0. With the fix it exits 42.
##
## WHY THIS FILE EXISTS ALONGSIDE `test/iter_for_split.al`: that fixture HAND-BUILDS its
## `SplitIter(ptr = s.ptr, len = s.len, …)` from the subject's own fields and never calls `split`,
## which is exactly why the gate never saw this wrong value. Here the iterator comes from `split`
## itself and the loop drives the protocol's `next`.
##
## Distinct rejection codes below 126, no `good * K + bad` aliasing (#386), and 42 is reserved for
## success. The defect answers ZERO, so each of the three subjects separates an EMPTY iterator from a
## merely wrong one and from wrong pieces, with its own constants:
##
##   subject       empty len   wrong len   loop overran   wrong count   wrong content
##   "a,bb,ccc"       20          21            22             23         24 / 25 / 26
##   "abc"            30          31            32             33         34
##   "x,"             40          41            43             44         45 / 46
##
## Piece CONTENT is asserted, not only the count: a `len` that survives while the `ptr` is null would
## still yield the right NUMBER of pieces, made of the wrong bytes. The third subject's trailing
## separator also pins the final EMPTY piece, which a length-only check cannot see.

main := fn() -> u64 {
  ## ---- three pieces, two separators ----
  s := "a,bb,ccc"
  it := base::str::split(ptr(s), 44)
  if it.len == 0 { return 20 }
  if it.len != 8 { return 21 }

  mut n : u64 = 0
  mut hit_a := false
  mut hit_bb := false
  mut hit_ccc := false
  for p in it {
    n = n + 1
    if n > 8 { return 22 }
    if p == "a" { hit_a = true }
    if p == "bb" { hit_bb = true }
    if p == "ccc" { hit_ccc = true }
  }
  if n != 3 { return 23 }
  if hit_a == false { return 24 }
  if hit_bb == false { return 25 }
  if hit_ccc == false { return 26 }

  ## ---- no separator at all is ONE piece, the whole subject ----
  t := "abc"
  u := base::str::split(ptr(t), 44)
  if u.len == 0 { return 30 }
  if u.len != 3 { return 31 }
  mut m : u64 = 0
  mut hit_abc := false
  for q in u {
    m = m + 1
    if m > 4 { return 32 }
    if q == "abc" { hit_abc = true }
  }
  if m != 1 { return 33 }
  if hit_abc == false { return 34 }

  ## ---- a TRAILING separator yields a final EMPTY piece ----
  v := "x,"
  w := base::str::split(ptr(v), 44)
  if w.len == 0 { return 40 }
  if w.len != 2 { return 41 }
  mut k : u64 = 0
  mut hit_x := false
  mut hit_empty := false
  for r in w {
    k = k + 1
    if k > 4 { return 43 }
    if r == "x" { hit_x = true }
    if r.len == 0 { hit_empty = true }
  }
  if k != 2 { return 44 }
  if hit_x == false { return 45 }
  if hit_empty == false { return 46 }

  42
}
