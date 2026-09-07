## e2e — Types §7 + Memory §4.3/§4.6: a `[T]` binding IS the two-word `{ptr, len}` VIEW ("the view
## *is* the value"), `ptr(x)` is the ADDRESS of that place, and `deref(q).len` / `deref(q).ptr` is an
## ordinary read through the pointer — so `deref(ptr(v)) == v`. Issue #484: the `[T]` dual of #451
## (the `ptr(str)` PARAMETER) and #456 (the `ptr(str)` LOCAL).
##
## Failure-first on the parent (`origin/main` 71ea8df, x86_64, default build path, frozen-seed
## Stage1): this file exits 48 — the very first subject probe, `deref(q).len` through a `ptr([u64])`
## PARAMETER, classified as "the run's SECOND element". `ptr(<slice local>)` handed back the ARRAY
## BASE instead of the address of the local's own pair (`emit_addr_of`'s by-ref `movq` branch, taken
## because `bind_slice_slot` marks a slice local `is_ref`), so the pointee-view read's ascending
## `8(%rax)` landed on element 1 of the run. With the fix this file exits 42.
##
## WHY THE CODES ARE SHAPED THIS WAY — "not the length" has at least TWO distinct wrong forms in the
## field, and one of them is a plausible-looking number rather than obvious garbage (the hazard this
## repository already recorded for #421). Before PR #482 the inline read on an inferred pointer local
## answered ZERO because no arm served it; #482 routed it to the pointee-view arm, so it answered the
## SECOND ELEMENT like the other spellings. Both are wrong, and a fixture that only asserts "not the
## length" cannot tell them apart — nor can it catch a "fix" that returns an ELEMENT. So every `.len`
## probe is CLASSIFIED by `clen` into FIVE outcomes with FOUR distinct codes per (spelling, subject):
##
##   the LENGTH (correct) -> 0, the probe stays silent
##   ZERO                 -> base + 0     (the pre-#482 shape, and the commonest accidental default)
##   the FIRST element    -> base + 1     (an off-by-one pair address, or a `.ptr`/`.len` swap)
##   the SECOND element   -> base + 2     (the #484 defect itself: the array base + 8)
##   anything else        -> base + 3     (a stale frame word, a folded constant, garbage)
##
## THREE SUBJECTS OF DIFFERENT LENGTH, and one of them is a slice of LENGTH 1:
##
##   subject   run                 view        len   elem 0   elem 1   base of the four codes
##   A         [7, 3, 9, 11, 13]   xs[0..4]      4        7        3    +0
##   B         [10, 20, 30]        ys[0..3]      3       10       20    +4
##   C         [5, 6, 7]           zs[0..1]      1        5        6    +8
##
## Subject C is the one that cannot be passed by coincidence: its length is 1 while the two run words
## under it are 5 and 6, so a read that answers an ELEMENT — either element — is a DIFFERENT number
## from the length and is classified as such. Subject A's length (4) is also not a value in any of the
## three runs, and no two subjects share a length, so a read that answers a stale slot or a folded
## constant cannot agree with more than one subject.
##
## THE SPELLINGS, all of which issue #484's acceptance criterion 1 names, each with its own code
## block so the log says WHICH spelling broke:
##
##   spelling                                              `.len` codes      `.ptr` code
##   PARAMETER   `plen(q : ptr([u64]))`                        46-57            106
##   LOCAL, inferred    `q := ptr(v)`                          58-69            108
##   LOCAL, annotated   `q : ptr([u64]) = ptr(v)`              70-81            110
##   LOCAL, bitcast     `q := unchecked bitcast(ptr([u64]),…)` 82-93            112
##   BOUND, annotated  `ss := deref(q)`                        94-105           114
##   BOUND, inferred   `q := ptr(v)` then `ss := deref(q)`      3-14             15
##   BOUND, bitcast    `ss := deref(q)`, `.len` two-code         40-41            -
##
## THIS FILE PROBES THE ADDRESS `ptr(v)` HANDS BACK, i.e. `.len` and `.ptr`. Reserving two words is
## not the same as reserving the RIGHT two words, and no `.len` probe can see the difference: a `[T]`
## pointee bound by `bind_str_slot` (ek 4) has a correct `.len` and a BYTE-indexed `[i]`. That second
## half is `test/issue484_bound_slice_elem.al`, the sibling fixture, which is kept SEPARATE precisely
## so this file still exits with a classified 48 on the parent — the element read is REFUSED there
## (`indexing a SCALAR local/param`), which would make a joint file fail at compile time and say
## nothing about which wrong number the address defect answered.
##
## A `.ptr` probe is classified by `cptr` against the subject's OWN data pointer, read directly off
## the view: correct -> 0, zero -> base + 0, any other address -> base + 1. A non-null but FOREIGN
## pointer is therefore a failure, not a pass.
##
## THE BOUND FORM ON AN INFERRED POINTER LOCAL IS PROBED AND FIXED (codes 3-16), which it was not on
## 240b8ff — this fixture's first base. There the binding went through the SPAN-valued
## `slot_ptr_pointee_span`, which has no pointee type span for a declaration that spells no type, so
## it reserved ONE word and `ss.len` read a never-written neighbouring slot (0). #501 (issue #483)
## then gave the source scan a SLOT-COLLECTION entry so the `str` dual of that binding reserves both
## words. This change makes the same entry answer for `[T]`, and — the part a boolean could not
## answer — bind the pair as an ELEMENT-indexed slice rather than a byte-indexed `str`.
##
## CONTROLS, checked before the subjects and re-checked after every one of them has run:
##   * a user STRUCT behind a local pointer (codes 20, 44) — `ptr(<struct local>)`/`deref` in general.
##   * the `str` dual through a PARAMETER (#451, code 21) and through an inferred LOCAL (#456, code
##     22) — the shapes #484 must not disturb.
##   * a by-reference aggregate PARAM (`in out`) reached as `ptr(x)` and handed to a `ptr(Bag)` callee
##     (code 23) — the shape whose slot really does hold a pointer to the caller's value, and which
##     must KEEP the by-ref `movq`. (Reading the same field through an INLINE `deref(ptr(x)).b` in the
##     callee instead answers 0 on both sides of this change — a separate, pre-existing gap in the
##     `Field(Deref(AddrOf(<by-ref param>)))` shape, measured on the parent and left alone here.)
##   * the DIRECT, non-pointer `.len` / `.ptr` read on each subject (codes 24-33) — the working
##     deliverer this fix routes the pointer spellings onto.
## On the parent this file returns 48, not 20-33, which is what proves the defect is specific to a
## view read THROUGH a pointer and not to slices, to `deref`, or to pointer locals in general.
##
## Codes are distinct constants below 126 (WASI `proc_exit` rejects more, and exits are mod 256);
## 42 is reserved for success and no probe can produce it.

Box := struct { v : u64 }

Bag := struct { a : u64, b : u64, c : u64 }

## The by-reference aggregate PARAM control: `ptr(x)` over an `in out` struct param must still LOAD
## the stored pointer (`movq`), not take the slot's own address (`leaq`) — that slot really does hold
## a pointer to the caller's value, and taking its address instead would read the pointer word as if
## it were the struct. Handed to a `ptr(Bag)` callee so the address crosses a call boundary.
bag_b_via := fn(q : ptr(Bag)) -> u64 { deref(q).b }
bag_b := fn(in out x : Bag) -> u64 { bag_b_via(ptr(x)) }

## The `str` duals, kept green: #451's PARAMETER spelling.
slen := fn(q : ptr(str)) -> usize { deref(q).len }

## The subject spelling under test: a `ptr([T])` PARAMETER.
plen := fn(q : ptr([u64])) -> usize { deref(q).len }
pptr := fn(q : ptr([u64])) -> usize { unchecked bitcast(usize, deref(q).ptr) }

## Classify one `.len` answer into the five outcomes above. 0 means "the length"; every other result
## is `base` plus the offset naming WHICH wrong shape was answered.
clen := fn(got : usize, want : usize, e0 : usize, e1 : usize, base : u64) -> u64 {
  if got == want { return 0 }
  if got == 0 { return base }
  if got == e0 { return base + 1 }
  if got == e1 { return base + 2 }
  base + 3
}

## Classify one `.ptr` answer against the subject's own data pointer. 0 means correct.
cptr := fn(got : usize, want : usize, base : u64) -> u64 {
  if got == want { return 0 }
  if got == 0 { return base }
  base + 1
}

## Classify one ELEMENT read (`ss[i]`) or one two-code length. 0 means correct; `base` is the BYTE-read
## shape (a `[T]` view bound as a byte-indexed `str`: byte 1 of a small element is 0) and `base + 1` is
## any other wrong value.
celem := fn(got : u64, want : u64, base : u64) -> u64 {
  if got == want { return 0 }
  if got == 0 { return base }
  base + 1
}

main := fn() -> u64 {
  ## ---- control: a user struct behind a local pointer ----
  bx := Box(v = 7)
  qb := ptr(bx)
  if deref(qb).v != 7 { return 20 }

  ## ---- control: the `str` duals (#451 parameter, #456 inferred local) ----
  cs := "a,bc"
  if slen(ptr(cs)) != 4 { return 21 }
  qcs := ptr(cs)
  if deref(qcs).len != 4 { return 22 }

  ## ---- control: a BY-REFERENCE aggregate param keeps the by-ref `movq` ----
  mut bag := Bag(a = 1, b = 61, c = 3)
  if bag_b(bag) != 61 { return 23 }

  ## ---- the three subjects, of DIFFERENT length, read DIRECTLY first ----
  xs := [7, 3, 9, 11, 13]
  ys := [10, 20, 30]
  zs := [5, 6, 7]
  va := xs[0..4]
  vb := ys[0..3]
  vc := zs[0..1]
  if va.len != 4 { return 24 }
  if vb.len != 3 { return 25 }
  if vc.len != 1 { return 26 }
  ## the LENGTH-1 subject's length (1) differs from BOTH run words under it (5 and 6), so a read
  ## that answers an ELEMENT cannot be mistaken for the length
  if xs[0] != 7 or xs[1] != 3 { return 27 }
  if ys[0] != 10 or ys[1] != 20 { return 28 }
  if zs[0] != 5 or zs[1] != 6 { return 29 }
  apn := unchecked bitcast(usize, va.ptr)
  bpn := unchecked bitcast(usize, vb.ptr)
  cpn := unchecked bitcast(usize, vc.ptr)
  if apn == 0 or bpn == 0 or cpn == 0 { return 30 }
  if apn == bpn { return 31 }
  if apn == cpn { return 32 }
  if bpn == cpn { return 33 }

  ## ---- SPELLING 1: the `ptr([u64])` PARAMETER (codes 46-57, 106) ----
  mut r := clen(plen(ptr(va)), 4, 7, 3, 46)
  if r != 0 { return r }
  r = clen(plen(ptr(vb)), 3, 10, 20, 50)
  if r != 0 { return r }
  r = clen(plen(ptr(vc)), 1, 5, 6, 54)
  if r != 0 { return r }
  r = cptr(pptr(ptr(va)), apn, 106)
  if r != 0 { return r }

  ## ---- SPELLING 2: an INFERRED pointer local, read INLINE (codes 58-69, 108) ----
  qai := ptr(va)
  qbi := ptr(vb)
  qci := ptr(vc)
  r = clen(deref(qai).len, 4, 7, 3, 58)
  if r != 0 { return r }
  r = clen(deref(qbi).len, 3, 10, 20, 62)
  if r != 0 { return r }
  r = clen(deref(qci).len, 1, 5, 6, 66)
  if r != 0 { return r }
  r = cptr(unchecked bitcast(usize, deref(qai).ptr), apn, 108)
  if r != 0 { return r }

  ## ---- SPELLING 3: an ANNOTATED pointer local, read INLINE (codes 70-81, 110) ----
  qaa : ptr([u64]) = ptr(va)
  qba : ptr([u64]) = ptr(vb)
  qca : ptr([u64]) = ptr(vc)
  r = clen(deref(qaa).len, 4, 7, 3, 70)
  if r != 0 { return r }
  r = clen(deref(qba).len, 3, 10, 20, 74)
  if r != 0 { return r }
  r = clen(deref(qca).len, 1, 5, 6, 78)
  if r != 0 { return r }
  r = cptr(unchecked bitcast(usize, deref(qaa).ptr), apn, 110)
  if r != 0 { return r }

  ## ---- SPELLING 4: a BITCAST pointer local, read INLINE (codes 82-93, 112) ----
  qab := unchecked bitcast(ptr([u64]), ptr(va))
  qbb := unchecked bitcast(ptr([u64]), ptr(vb))
  qcb := unchecked bitcast(ptr([u64]), ptr(vc))
  r = clen(deref(qab).len, 4, 7, 3, 82)
  if r != 0 { return r }
  r = clen(deref(qbb).len, 3, 10, 20, 86)
  if r != 0 { return r }
  r = clen(deref(qcb).len, 1, 5, 6, 90)
  if r != 0 { return r }
  r = cptr(unchecked bitcast(usize, deref(qab).ptr), apn, 112)
  if r != 0 { return r }

  ## ---- SPELLING 5: the BOUND form `ss := deref(q)` on an annotated local (codes 94-105, 114) ----
  ssa := deref(qaa)
  ssb := deref(qba)
  ssc := deref(qca)
  r = clen(ssa.len, 4, 7, 3, 94)
  if r != 0 { return r }
  r = clen(ssb.len, 3, 10, 20, 98)
  if r != 0 { return r }
  r = clen(ssc.len, 1, 5, 6, 102)
  if r != 0 { return r }
  r = cptr(unchecked bitcast(usize, ssa.ptr), apn, 114)
  if r != 0 { return r }

  ## ---- SPELLING 6: the BOUND form on an INFERRED pointer local (codes 3-16) ----
  ## `q := ptr(v)` spells no type, so the binder has no pointee TYPE span to resolve and must go
  ## through the shared source scan instead. On 240b8ff this answered 0 (the binding reserved ONE
  ## word); on 71ea8df, after #501 gave that scan its slot-collection entry, it still answered 0
  ## because the scan only recognized a `str` local.
  ssia := deref(qai)
  ssib := deref(qbi)
  ssic := deref(qci)
  r = clen(ssia.len, 4, 7, 3, 3)
  if r != 0 { return r }
  r = clen(ssib.len, 3, 10, 20, 7)
  if r != 0 { return r }
  r = clen(ssic.len, 1, 5, 6, 11)
  if r != 0 { return r }
  r = cptr(unchecked bitcast(usize, ssia.ptr), apn, 15)
  if r != 0 { return r }

  ## ---- the BOUND form on a BITCAST pointer local, `.len` (codes 40-41) ----
  ssbb := deref(qbb)
  r = celem(u64(ssbb.len), 3, 40)
  if r != 0 { return r }

  ## ---- the controls must STILL answer after every subject has run ----
  if deref(qb).v != 7 { return 44 }
  if slen(ptr(cs)) != 4 { return 45 }

  42
}
