## e2e — Types §7 + Memory §4.3/§4.6: `deref(ptr(v)) == v` for a `[T]`, so `ss := deref(q)` binds a
## slice VIEW and `ss[i]` / `for x in ss` read ELEMENTS at the view's own stride. Issue #484, second
## half — the sibling of `test/issue484_ptr_slice_view_field.al`, which probes the ADDRESS `ptr(v)`
## hands back (`.len` / `.ptr`). This file probes WHICH VIEW the binder reserved.
##
## Reserving two words is not the same as reserving the RIGHT two words, and no `.len` probe can see
## the difference. `x := deref(<pointer to a §7 view>)` bound every pointee with `bind_str_slot`
## (ek 4, BYTE-indexed) because the binder was asked one boolean — "is the pointee the two-word
## pair" — which is true for both `str` and `[T]`. A `[T]` bound that way has a correct `.len` and a
## byte-indexed `[i]`, so `ss[1]` answers BYTE 1 of element 0: 0 for every element below 256.
##
## WHY THIS IS A SEPARATE FILE, and the measurement that decided it. On the parent (`origin/main`
## 71ea8df, x86_64, frozen-seed Stage1) the three bound spellings do THREE different things, and only
## one of them is a value:
##
##   spelling                          on 71ea8df                       with only the ADDRESS fixed
##   BOUND, inferred  `q := ptr(v)`    REFUSED at compile time          0   (a silent byte read)
##   BOUND, annotated `q : ptr([u64])` SIGSEGV (the byte index ran off  0   (a silent byte read)
##   BOUND, bitcast   `bitcast(...)`   the array base held as a ptr)    0   (a silent byte read)
##
## So this file is REFUSED on the parent — `selfhost: indexing a SCALAR local/param (…) is not a
## place` — while the sibling exits a classified 48. Joining them would have replaced that 48 with a
## compile failure and said nothing about which wrong number the address defect answered. And the
## right-hand column is why the binding had to be typed in the same change as the address: fixing the
## address alone turns a compile refusal and a segfault into a silent 0, which is the one transition
## this repository's evidence rules forbid outright.
##
## SUBJECTS. Two runs whose element values are all distinct and none of which equals a length, plus a
## LENGTH-1 view whose length (1) differs from both run words under it, so an answer that is an
## element, a length, a byte of an element or a stale word is a different number in every case:
##
##   subject   run                 view        len   elem 0   elem 1   elem 2
##   B         [10, 20, 30]        ys[0..3]      3       10       20       30
##   C         [5, 6, 7]           zs[0..1]      1        5        -        -
##
## CODES — `celem` classifies each read into correct -> 0, the BYTE-READ shape (0) -> base, any other
## wrong value -> base + 1. 42 is success and no probe can produce it; every code is below 126.
##
##   50-51  `ss[1]` on the BOUND view, INFERRED spelling, subject B   (want 20)
##   52-53  `ss[1]` on the BOUND view, ANNOTATED spelling, subject B  (want 20)
##   54-55  `ss[1]` on the BOUND view, BITCAST spelling, subject B    (want 20)
##   56-57  `ss[0]` on the BOUND view, INFERRED spelling, subject C   (want 5)
##   58-59  `ss[2]` on the BOUND view, ANNOTATED spelling, subject B  (want 30)
##   60-61  `ss.len` on each bound view, re-checked next to the element read
##   62     `for x in ss` sum, INFERRED spelling  (want 60)
##   63     `for x in ss` sum, ANNOTATED spelling (want 60)
##   64     `for x in ss` sum, BITCAST spelling   (want 60)
##
## CONTROLS, green on BOTH sides of this change and checked before and after every subject:
##   20  the element read on the view read DIRECTLY, with no pointer — the working deliverer this
##       change routes the bound spellings onto, and the reason "bind the same slot the source view
##       has" is the right answer rather than "change the read".
##   21  the `str` dual of the same bound spelling (#456/#483): `q := ptr(s)`, `ss := deref(q)`,
##       `ss.len` — the shape that must KEEP `bind_str_slot` and its BYTE indexing.
##   22  `bytes(<bound str view>)[i]`, the byte read that a `str` pointee must still answer.

celem := fn(got : u64, want : u64, base : u64) -> u64 {
  if got == want { return 0 }
  if got == 0 { return base }
  base + 1
}

main := fn() -> u64 {
  ys := [10, 20, 30]
  zs := [5, 6, 7]
  vb := ys[0..3]
  vc := zs[0..1]

  ## ---- control: the direct, pointer-free element read ----
  if vb[1] != 20 or vc[0] != 5 or vb.len != 3 or vc.len != 1 { return 20 }

  ## ---- control: the `str` dual keeps its BYTE-indexed binding ----
  cs := "a,bc"
  qcs := ptr(cs)
  sscs := deref(qcs)
  if sscs.len != 4 { return 21 }
  if bytes(sscs)[1] != 44 { return 22 }

  ## ---- BOUND, INFERRED: `q := ptr(v)` then `ss := deref(q)` ----
  qbi := ptr(vb)
  qci := ptr(vc)
  ssbi := deref(qbi)
  ssci := deref(qci)
  mut r := celem(u64(ssbi.len), 3, 60)
  if r != 0 { return r }
  r = celem(u64(ssbi[1]), 20, 50)
  if r != 0 { return r }
  r = celem(u64(ssci[0]), 5, 56)
  if r != 0 { return r }

  ## ---- BOUND, ANNOTATED: `q : ptr([u64]) = ptr(v)` then `ss := deref(q)` ----
  qba : ptr([u64]) = ptr(vb)
  ssba := deref(qba)
  r = celem(u64(ssba.len), 3, 60)
  if r != 0 { return r }
  r = celem(u64(ssba[1]), 20, 52)
  if r != 0 { return r }
  r = celem(u64(ssba[2]), 30, 58)
  if r != 0 { return r }

  ## ---- BOUND, BITCAST: `q := unchecked bitcast(ptr([u64]), ptr(v))` then `ss := deref(q)` ----
  qbb := unchecked bitcast(ptr([u64]), ptr(vb))
  ssbb := deref(qbb)
  r = celem(u64(ssbb.len), 3, 60)
  if r != 0 { return r }
  r = celem(u64(ssbb[1]), 20, 54)
  if r != 0 { return r }

  ## ---- iteration: the third consumer of the slot's element layout, after `.len` and `[i]` ----
  ## A byte-indexed binding walks a different number of elements of a different size.
  mut i1 := 0
  for x in ssbi { i1 = i1 + x }
  if i1 != 60 { return 62 }
  mut i2 := 0
  for x in ssba { i2 = i2 + x }
  if i2 != 60 { return 63 }
  mut i3 := 0
  for x in ssbb { i3 = i3 + x }
  if i3 != 60 { return 64 }

  ## ---- the controls must STILL answer after every subject has run ----
  if vb[1] != 20 or vc[0] != 5 { return 20 }
  if sscs.len != 4 { return 21 }
  if bytes(sscs)[1] != 44 { return 22 }

  42
}
