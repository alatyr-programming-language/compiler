## e2e — Stdlib appendix §3.5/§3.6 + Memory §4.1: a `str` is the base-tier `{ptr : ptr(u8),
## len : usize}` pair, and `deref(q).len` / `deref(q).ptr` through a `ptr(str)` PARAMETER is an
## ordinary read through the pointer. Issue #451.
##
## Failure-first on the parent (`origin/main` 5eb6739, x86_64, default build path, frozen-seed
## Stage1): this file exits 30 — every field read through the `ptr(str)` parameter answered ZERO
## while the same shape over a user struct answered correctly. The parent's `probe` body was
## literally `movq $0, %rax`; the bound form `ss := deref(q)` copied ONE word, so `ss.len` read a
## never-written neighbouring slot. With the fix the file exits 42.
##
## THREE OUTCOMES, THREE CODES — no `good * K + bad` aliasing (#386), and 42 is reserved for success.
## The defect answers 0, and 0 is also the commonest accidental default, so "correct", "zero" and
## "never actually read" must be told apart by DIFFERENT constants. Four probes, one row each:
##
##   probe                          answered 0   answered wrong   never actually read
##   `deref(q).len`                     30             31                 32
##   `deref(q).ptr`                     33             34                 35
##   `ss := deref(q)` then `ss.len`     40             41                 47
##   `ss := deref(q)` then `ss.ptr`     43             44                 45
##
## The last column is real, not decorative. TWO subjects of DIFFERENT byte length ("a,bc" = 4,
## "xyzzy!" = 6) go through the same parameter, so a callee that returns a stale slot, a constant, or
## the pointer word itself instead of reading through it answers the SAME value for both — an
## agreement a real read can never produce. The "answered wrong" column also covers a non-null but
## FOREIGN pointer: the `.ptr` probes compare against the subject's own `s.ptr`, read directly.
## Codes 22-26 reject a malformed subject before any probe runs (wrong direct length, a null or
## shared literal pointer), so a probe row can only mean what it says.
##
## The CONTROL (`Box`, codes 20/21, re-checked as 46 once the subject has run) is the shape issue
## #451 names as already working: the identical `deref(q).field` / `ss := deref(q)` pair over a USER
## struct. It is checked FIRST and is green on BOTH sides — on the parent this file returns 30, not
## 20, 21 or 46, which is what proves the defect is specific to `str` behind a pointer and not to
## pointer parameters in general.
##
## Codes are distinct constants below 126 (WASI `proc_exit` rejects more, and exits are mod 256).

Box := struct { v : u64, w : u64 }

## The control shape over a USER struct — both spellings the subject uses below.
box_direct := fn(q : ptr(Box)) -> u64 { deref(q).v }
box_bound := fn(q : ptr(Box)) -> u64 {
  bb := deref(q)
  bb.w
}

## The subject: the same two spellings over a `ptr(str)` parameter.
slen_direct := fn(q : ptr(str)) -> usize { deref(q).len }
sptr_direct := fn(q : ptr(str)) -> usize { unchecked bitcast(usize, deref(q).ptr) }
slen_bound := fn(q : ptr(str)) -> usize {
  ss := deref(q)
  ss.len
}
sptr_bound := fn(q : ptr(str)) -> usize {
  ss := deref(q)
  unchecked bitcast(usize, ss.ptr)
}

main := fn() -> u64 {
  ## ---- control: green on the parent too ----
  b := Box(v = 7, w = 9)
  if box_direct(ptr(b)) != 7 { return 20 }
  if box_bound(ptr(b)) != 9 { return 21 }

  ## ---- the two subjects, of DIFFERENT length, read directly first ----
  a := "a,bc"
  z := "xyzzy!"
  if a.len != 4 { return 22 }
  if z.len != 6 { return 23 }
  apn := unchecked bitcast(usize, a.ptr)
  zpn := unchecked bitcast(usize, z.ptr)
  if apn == 0 { return 24 }
  if zpn == 0 { return 25 }
  if apn == zpn { return 26 }

  ## ---- `deref(q).len` ----
  la := slen_direct(ptr(a))
  lz := slen_direct(ptr(z))
  if la == 0 or lz == 0 { return 30 }
  if la == lz { return 32 }
  if la != 4 or lz != 6 { return 31 }

  ## ---- `deref(q).ptr` ----
  pa := sptr_direct(ptr(a))
  pz := sptr_direct(ptr(z))
  if pa == 0 or pz == 0 { return 33 }
  if pa == pz { return 35 }
  if pa != apn or pz != zpn { return 34 }

  ## ---- `ss := deref(q)` then `ss.len` ----
  ma := slen_bound(ptr(a))
  mz := slen_bound(ptr(z))
  if ma == 0 or mz == 0 { return 40 }
  if ma == mz { return 47 }
  if ma != 4 or mz != 6 { return 41 }

  ## ---- `ss := deref(q)` then `ss.ptr` ----
  qa := sptr_bound(ptr(a))
  qz := sptr_bound(ptr(z))
  if qa == 0 or qz == 0 { return 43 }
  if qa == qz { return 45 }
  if qa != apn or qz != zpn { return 44 }

  ## the control must STILL answer after the subject ran
  if box_direct(ptr(b)) != 7 { return 46 }

  42
}
