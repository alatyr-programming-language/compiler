## e2e — Stdlib appendix §3.5/§3.6 + Memory §4.1: a `str` is the base-tier `{ptr : ptr(u8),
## len : usize}` pair, and BINDING the pointee first — `ss := deref(q)`, then `ss.len` / `ss.ptr` —
## is an ordinary read through the pointer. Issue #483 — the BOUND dual of #456 (the INLINE
## `deref(q).len`, fixed by PR #482) on an INFERRED pointer local `q := ptr(<str local>)`.
##
## Failure-first on the parent (`origin/main` d256330, x86_64, default build path, frozen-seed
## Stage1; also measured 60 on 240b8ff, this branch's first base): this file exits 60 — the first
## subject probe. `ss.len` answered ZERO for both subjects
## because the binding reserved ONE scalar word for `ss` (the emitted frame was `subq $64` where the
## pair needs `$80`), so the ptr word landed and the len word was NEVER WRITTEN; `ss.len` then read a
## never-written neighbouring slot. `ss.ptr` was accidentally right on the parent — word 0 of the pair
## IS the pointer, so the single stored word answered it — which is exactly why `.len` and `.ptr` need
## separate probes here rather than one combined check. With the fix this file exits 42.
##
## Why the BOUND form is not the INLINE form. `deref(q).len` is decided at EMIT time by one Field arm
## (#482 widened its guard). `ss := deref(q)` is decided TWICE and needs both halves to agree:
## `collect_slots` must RESERVE two words for `ss`, and the assign emit must WRITE both. Both gates
## asked a SPAN-valued question ("name the pointee type"), which the annotated (`q : ptr(str) = …`)
## and bitcast (`q := unchecked bitcast(ptr(str), …)`) spellings can answer from their own source
## spelling and the INFERRED one cannot — `str` is structural, so no `str` span exists anywhere in the
## source. A reservation without the matching store is still 0, which is why both halves are probed.
##
## THREE OUTCOMES PER PROBE, THREE CODES — no `good * K + bad` aliasing (#386), and 42 is reserved
## for success. The defect answers 0, and 0 is also the commonest accidental default, so "correct",
## "zero" and "never actually read" must be told apart by DIFFERENT constants:
##
##   probe                                          answered 0   never actually read   answered wrong
##   INFERRED       `ss := deref(q)` then `ss.len`       60               61                  62
##   INFERRED       `ss := deref(q)` then `ss.ptr`       63               64                  65
##   INFERRED `mut` `ss := deref(q)` then `ss.len`       66               67                  68
##   INFERRED `mut` `ss := deref(q)` then `ss.ptr`       70               71                  72
##
## The middle column is real, not decorative. TWO subjects of DIFFERENT byte length go through each
## spelling ("a,bc" = 4 vs "xyzzy!" = 6 for the plain locals, "mn,op" = 5 vs "qrstuvw" = 7 for the
## `mut` ones — four distinct lengths, so a stale neighbouring slot cannot hold a value that happens
## to be right), so a read that answers a stale slot, a folded constant, or the pointer word itself
## instead of reading THROUGH the pointer answers the SAME value for both — an agreement a real read
## can never produce. The "answered wrong" column also covers a non-null but FOREIGN pointer: every
## `.ptr` probe compares against its own subject's `s.ptr`, read directly. Codes 20-24 reject a
## malformed subject before any probe runs (wrong direct length, a null or shared literal pointer).
##
## The CONTROLS are the four shapes that must be green on BOTH sides, and they are checked BEFORE the
## subjects, with the struct one and both direct re-reads re-checked AFTER:
##
##   * a user STRUCT behind a local pointer, bound (`bb := deref(qb)`) — code 25, again 75;
##   * the BOUND form on an ANNOTATED local, `.len` + `.ptr` — codes 30-35;
##   * the BOUND form on a BITCAST local, `.len` + `.ptr` — codes 36-41;
##   * the BOUND form through a `ptr(str)` PARAMETER (#451/#459) — codes 44-49;
##   * the INLINE read on the SAME inferred locals the subjects use (#456, fixed by #482) — codes
##     50-55. That control is the sharp one: it proves the widened guard did not move the inline
##     read's route while fixing the bound one, and it shares `qai`/`qzi` with the subjects so both
##     spellings of ONE pointer are measured in the same frame.
##
## Codes 76 and 77 re-read the four subjects DIRECTLY after every probe: the fix makes a slot two
## words where it was one, so a wide store landing on a neighbour would show up there rather than
## silently. On the parent this file returns 60, not 20-25, 30-41, 44-55, 76 or 77 — that is what
## proves the defect is specific to the BOUND read through an INFERRED pointer local and not to
## pointer locals, to `str` behind a pointer, or to `deref` in general.
##
## Codes are distinct constants below 126 (WASI `proc_exit` rejects more, and exits are mod 256).

Box := struct { v : u64 }

## The #451/#459 shape: the same BOUND read through a `ptr(str)` PARAMETER.
plen := fn(q : ptr(str)) -> usize { ss := deref(q)  ss.len }
pptr := fn(q : ptr(str)) -> usize { ss := deref(q)  unchecked bitcast(usize, ss.ptr) }

main := fn() -> u64 {
  ## ---- control: a user struct behind a local pointer, BOUND (green on the parent too) ----
  b := Box(v = 7)
  qb := ptr(b)
  bb := deref(qb)
  if bb.v != 7 { return 25 }

  ## ---- the four subjects, of FOUR DIFFERENT lengths, read directly first ----
  a := "a,bc"
  z := "xyzzy!"
  mut ma := "mn,op"
  mut mz := "qrstuvw"
  if a.len != 4 { return 20 }
  if z.len != 6 { return 21 }
  apn := unchecked bitcast(usize, a.ptr)
  zpn := unchecked bitcast(usize, z.ptr)
  if apn == 0 { return 22 }
  if zpn == 0 { return 23 }
  if apn == zpn { return 24 }

  ## ---- control: the BOUND form on an ANNOTATED `ptr(str)` local ----
  qaa : ptr(str) = ptr(a)
  qza : ptr(str) = ptr(z)
  saa := deref(qaa)
  sza := deref(qza)
  if saa.len == 0 or sza.len == 0 { return 30 }
  if saa.len == sza.len { return 31 }
  if saa.len != 4 or sza.len != 6 { return 32 }
  paa := unchecked bitcast(usize, saa.ptr)
  pza := unchecked bitcast(usize, sza.ptr)
  if paa == 0 or pza == 0 { return 33 }
  if paa == pza { return 34 }
  if paa != apn or pza != zpn { return 35 }

  ## ---- control: the BOUND form on a BITCAST local ----
  qab := unchecked bitcast(ptr(str), ptr(a))
  qzb := unchecked bitcast(ptr(str), ptr(z))
  sab := deref(qab)
  szb := deref(qzb)
  if sab.len == 0 or szb.len == 0 { return 36 }
  if sab.len == szb.len { return 37 }
  if sab.len != 4 or szb.len != 6 { return 38 }
  pab := unchecked bitcast(usize, sab.ptr)
  pzb := unchecked bitcast(usize, szb.ptr)
  if pab == 0 or pzb == 0 { return 39 }
  if pab == pzb { return 40 }
  if pab != apn or pzb != zpn { return 41 }

  ## ---- control: the BOUND form through a `ptr(str)` PARAMETER (#451/#459) ----
  cla := plen(ptr(a))
  clz := plen(ptr(z))
  if cla == 0 or clz == 0 { return 44 }
  if cla == clz { return 45 }
  if cla != 4 or clz != 6 { return 46 }
  cpa := pptr(ptr(a))
  cpz := pptr(ptr(z))
  if cpa == 0 or cpz == 0 { return 47 }
  if cpa == cpz { return 48 }
  if cpa != apn or cpz != zpn { return 49 }

  ## ---- the INFERRED pointer locals the subjects and the #482 control SHARE ----
  qai := ptr(a)
  qzi := ptr(z)

  ## ---- control: the INLINE read on those same locals (#456, fixed by #482) ----
  ila := deref(qai).len
  ilz := deref(qzi).len
  if ila == 0 or ilz == 0 { return 50 }
  if ila == ilz { return 51 }
  if ila != 4 or ilz != 6 { return 52 }
  ipa := unchecked bitcast(usize, deref(qai).ptr)
  ipz := unchecked bitcast(usize, deref(qzi).ptr)
  if ipa == 0 or ipz == 0 { return 53 }
  if ipa == ipz { return 54 }
  if ipa != apn or ipz != zpn { return 55 }

  ## ---- SUBJECT 1: the BOUND form on those INFERRED locals ----
  ssa := deref(qai)
  ssz := deref(qzi)
  if ssa.len == 0 or ssz.len == 0 { return 60 }
  if ssa.len == ssz.len { return 61 }
  if ssa.len != 4 or ssz.len != 6 { return 62 }
  bpa := unchecked bitcast(usize, ssa.ptr)
  bpz := unchecked bitcast(usize, ssz.ptr)
  if bpa == 0 or bpz == 0 { return 63 }
  if bpa == bpz { return 64 }
  if bpa != apn or bpz != zpn { return 65 }

  ## ---- SUBJECT 2: the same, through the `ptr(mut <str local>)` spelling of the same scan ----
  mpn := unchecked bitcast(usize, ma.ptr)
  mqn := unchecked bitcast(usize, mz.ptr)
  qmi := ptr(mut ma)
  qni := ptr(mut mz)
  smm := deref(qmi)
  smn := deref(qni)
  if smm.len == 0 or smn.len == 0 { return 66 }
  if smm.len == smn.len { return 67 }
  if smm.len != 5 or smn.len != 7 { return 68 }
  mpa := unchecked bitcast(usize, smm.ptr)
  mpz := unchecked bitcast(usize, smn.ptr)
  if mpa == 0 or mpz == 0 { return 70 }
  if mpa == mpz { return 71 }
  if mpa != mpn or mpz != mqn { return 72 }

  ## every control must STILL answer after every subject has run
  if bb.v != 7 { return 75 }
  if a.len != 4 or z.len != 6 { return 76 }
  if ma.len != 5 or mz.len != 7 { return 77 }

  42
}
