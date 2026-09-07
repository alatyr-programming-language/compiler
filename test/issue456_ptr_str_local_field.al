## e2e — Stdlib appendix §3.5/§3.6 + Memory §4.1: a `str` is the base-tier `{ptr : ptr(u8),
## len : usize}` pair, and an INLINE `deref(q).len` / `deref(q).ptr` through a `ptr(str)` LOCAL is an
## ordinary read through the pointer. Issue #456 — the LOCAL dual of #451 (the `ptr(str)` PARAMETER).
##
## Failure-first on the parent (`origin/main` c1bb614, x86_64, default build path, frozen-seed
## Stage1): this file exits 50 — the very first subject probe. Every INLINE field read through a
## `ptr(str)` LOCAL answered ZERO, in all three spellings of the local (inferred `q := ptr(s)`,
## annotated `q : ptr(str) = ptr(s)`, and `q := unchecked bitcast(ptr(str), ptr(s))`), for BOTH
## `.len` and `.ptr`. The emitted body was the plain literal zero (`movq $0, %rbx`). With the fix
## this file exits 42.
##
## THREE OUTCOMES PER PROBE, THREE CODES — no `good * K + bad` aliasing (#386), and 42 is reserved
## for success. The defect answers 0, and 0 is also the commonest accidental default, so "correct",
## "zero" and "never actually read" must be told apart by DIFFERENT constants:
##
##   probe                                    answered 0   answered wrong   never actually read
##   INFERRED   `deref(q).len`                    50             52                 51
##   INFERRED   `deref(q).ptr`                    53             55                 54
##   ANNOTATED  `deref(q).len`                    56             58                 57
##   ANNOTATED  `deref(q).ptr`                    59             61                 60
##   BITCAST    `deref(q).len`                    62             64                 63
##   BITCAST    `deref(q).ptr`                    65             67                 66
##
## The last column is real, not decorative. TWO subjects of DIFFERENT byte length ("a,bc" = 4,
## "xyzzy!" = 6) go through the same spelling, so a read that answers a stale slot, a folded
## constant, or the pointer word itself instead of reading THROUGH the pointer answers the SAME
## value for both — an agreement a real read can never produce. The "answered wrong" column also
## covers a non-null but FOREIGN pointer: every `.ptr` probe compares against the subject's own
## `s.ptr`, read directly. Codes 21-25 reject a malformed subject before any probe runs (wrong
## direct length, a null or shared literal pointer), so a probe row can only mean what it says.
##
## The CONTROLS are the three shapes issue #456 names as ALREADY CORRECT, and they are checked
## BEFORE the subjects and re-checked after: a user STRUCT behind a local pointer (code 20, again
## 68), the same read through a `ptr(str)` PARAMETER (#451; codes 26-31), and the BOUND form on the
## same annotated local — `ss := deref(q)` then `ss.len` (codes 32-37). On the parent this file
## returns 50, not 20 or 26-37, which is what proves the defect is specific to the INLINE field read
## through a pointer LOCAL and not to pointer locals, to `str` behind a pointer, or to `deref` in
## general. All three controls are green on BOTH sides of the change.
##
## Codes are distinct constants below 126 (WASI `proc_exit` rejects more, and exits are mod 256).

Box := struct { v : u64 }

## The #451 shape: the same inline read through a `ptr(str)` PARAMETER.
plen := fn(q : ptr(str)) -> usize { deref(q).len }
pptr := fn(q : ptr(str)) -> usize { unchecked bitcast(usize, deref(q).ptr) }

main := fn() -> u64 {
  ## ---- control: a user struct behind a local pointer (green on the parent too) ----
  b := Box(v = 7)
  qb := ptr(b)
  if deref(qb).v != 7 { return 20 }

  ## ---- the two subjects, of DIFFERENT length, read directly first ----
  a := "a,bc"
  z := "xyzzy!"
  if a.len != 4 { return 21 }
  if z.len != 6 { return 22 }
  apn := unchecked bitcast(usize, a.ptr)
  zpn := unchecked bitcast(usize, z.ptr)
  if apn == 0 { return 23 }
  if zpn == 0 { return 24 }
  if apn == zpn { return 25 }

  ## ---- control: the #451 PARAMETER form ----
  cla := plen(ptr(a))
  clz := plen(ptr(z))
  if cla == 0 or clz == 0 { return 26 }
  if cla == clz { return 27 }
  if cla != 4 or clz != 6 { return 28 }
  cpa := pptr(ptr(a))
  cpz := pptr(ptr(z))
  if cpa == 0 or cpz == 0 { return 29 }
  if cpa == cpz { return 30 }
  if cpa != apn or cpz != zpn { return 31 }

  ## ---- control: the BOUND form on an annotated `ptr(str)` local ----
  qac : ptr(str) = ptr(a)
  qzc : ptr(str) = ptr(z)
  ssa := deref(qac)
  ssz := deref(qzc)
  if ssa.len == 0 or ssz.len == 0 { return 32 }
  if ssa.len == ssz.len { return 33 }
  if ssa.len != 4 or ssz.len != 6 { return 34 }
  bpa := unchecked bitcast(usize, ssa.ptr)
  bpz := unchecked bitcast(usize, ssz.ptr)
  if bpa == 0 or bpz == 0 { return 35 }
  if bpa == bpz { return 36 }
  if bpa != apn or bpz != zpn { return 37 }

  ## ---- SUBJECT 1: the INFERRED local `q := ptr(s)` ----
  qai := ptr(a)
  qzi := ptr(z)
  lai := deref(qai).len
  lzi := deref(qzi).len
  if lai == 0 or lzi == 0 { return 50 }
  if lai == lzi { return 51 }
  if lai != 4 or lzi != 6 { return 52 }
  pai := unchecked bitcast(usize, deref(qai).ptr)
  pzi := unchecked bitcast(usize, deref(qzi).ptr)
  if pai == 0 or pzi == 0 { return 53 }
  if pai == pzi { return 54 }
  if pai != apn or pzi != zpn { return 55 }

  ## ---- SUBJECT 2: the ANNOTATED local `q : ptr(str) = ptr(s)` ----
  qaa : ptr(str) = ptr(a)
  qza : ptr(str) = ptr(z)
  laa := deref(qaa).len
  lza := deref(qza).len
  if laa == 0 or lza == 0 { return 56 }
  if laa == lza { return 57 }
  if laa != 4 or lza != 6 { return 58 }
  paa := unchecked bitcast(usize, deref(qaa).ptr)
  pza := unchecked bitcast(usize, deref(qza).ptr)
  if paa == 0 or pza == 0 { return 59 }
  if paa == pza { return 60 }
  if paa != apn or pza != zpn { return 61 }

  ## ---- SUBJECT 3: the BITCAST local `q := unchecked bitcast(ptr(str), ptr(s))` ----
  qab := unchecked bitcast(ptr(str), ptr(a))
  qzb := unchecked bitcast(ptr(str), ptr(z))
  lab := deref(qab).len
  lzb := deref(qzb).len
  if lab == 0 or lzb == 0 { return 62 }
  if lab == lzb { return 63 }
  if lab != 4 or lzb != 6 { return 64 }
  pab := unchecked bitcast(usize, deref(qab).ptr)
  pzb := unchecked bitcast(usize, deref(qzb).ptr)
  if pab == 0 or pzb == 0 { return 65 }
  if pab == pzb { return 66 }
  if pab != apn or pzb != zpn { return 67 }

  ## the control must STILL answer after every subject has run
  if deref(qb).v != 7 { return 68 }

  42
}
