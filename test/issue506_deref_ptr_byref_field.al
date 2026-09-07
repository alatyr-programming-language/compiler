## e2e — Memory §4.3 + Types §9.4: `ptr(x)` is the ADDRESS of the place `x`, so `deref(ptr(x))` IS
## the place `x` and `deref(ptr(x)).f` is the ordinary field read `x.f`. Issue #506: when the root
## `x` is a BY-REFERENCE `in out` STRUCT PARAM, that read answered a literal ZERO.
##
## Failure-first on the parent (`origin/main` 038e8ea, x86_64, default build path, frozen-seed
## Stage1): this file exits 62 — the very first probe, the issue's own arithmetic spelling
## `40 + deref(ptr(x)).b`, classified as "the read contributed NOTHING" (the sum came back 40, not
## 101). With the fix this file exits 42.
##
## WHY IT ANSWERED ZERO. The emitter's scalar `Field` case reaches a pointee read through a chain of
## span resolvers, each of which peels a DIFFERENT inner node of the `Deref`: `deref_struct_span`
## wants `Deref(Var)` (an `ek = 7` pointer local), `deref_deref_struct_span` wants `Deref(Deref(..))`,
## `deref_call_struct_span` a `Deref(Call)`, `deref_field_ptrstruct_span` a `Deref(Field(..))`, and
## `deref_index_ptrstruct_span` a `Deref(Index(..))`. `Field(Deref(AddrOf(Var)))` is none of those, so
## EVERY resolver answered 0/0, no arm claimed the node, and `field_slot` fell through to the
## placeholder `movq $0, %rax`. Not a crash, not a diagnostic — the read simply contributed nothing
## to the surrounding arithmetic, which is the #421/#464 silent class: a sum that comes out short is
## a plausible-looking number.
##
## WHY THE CODES ARE SHAPED THIS WAY — "not the value" has FOUR distinct wrong forms here, and one of
## them (zero) is both the defect AND the commonest accidental default of a broken read, so a fixture
## that only asserts "not 61" cannot tell a fix from a differently-broken read. `Bag` therefore has
## THREE fields, and every probe is CLASSIFIED by `cf` into four outcomes with four distinct codes:
##
##   the FIELD's value (correct) -> 0, the probe stays silent
##   ZERO                        -> base + 0   (the #506 defect: no arm, a placeholder `$0`)
##   ANOTHER field's value       -> base + 1 / base + 2   (a wrong word offset, or the wrong root)
##   anything else               -> base + 3   (a stale frame word, an address read as data, garbage)
##
## THE VALUES CANNOT AGREE BY ACCIDENT. `Bag(a = 11, b = 61, c = 33)`: the three fields are pairwise
## distinct, and no sum of any two or three of them equals any single one of them or the awaited
## total (11+61 = 72, 11+33 = 44, 61+33 = 94, 11+61+33 = 105, none of which is 11, 33, 61 or 101).
## In the arithmetic spelling the awaited 101 is `40 + 61`, while reading NOTHING gives 40, reading
## `a` gives 51 and reading `c` gives 73 — four different exits for four different faults. No code
## below equals any field value, any of those sums, 40, or 42.
##
## THE THREE CONTROLS, each measured green on the parent as well as on this tree, so a failure here
## names WHICH spelling broke rather than "structs broke":
##
##   * the DIRECT read `x.f` on the same by-reference param (codes 20-22, and 29-31 re-checked after
##     every subject has run) — the working deliverer this fix routes the subject onto. It emits
##     exactly `movq -<slot>(%rbp), %rax` + `movq <fi>*8(%rax), %rax`, and after the fix the subject
##     emits that same instruction pair.
##   * the `ptr(Bag)` CALLEE-parameter spelling reached from the same by-reference param (codes
##     23-25) — the neighbour #505 used as ITS control, kept here so the fix is shown not to have
##     been needed for a shape that already worked.
##
## MEASURED AND DELIBERATELY NOT ASSERTED: the same SPELLING with a struct LOCAL root,
## `deref(ptr(l)).b`, answers ZERO too — `40 + deref(ptr(l)).b` returns 40 on the parent AND on this
## tree. That root is a DIFFERENT slot kind (`ek = 2` WITHOUT `is_ref`: the slot IS the struct, so
## its address is a `leaq` of the frame, not a pointer word to LOAD) and needs its own emission, so
## it is filed as #554 rather than folded in here — a slice that grows while it is implemented
## produces a measurement nobody can attribute. This file asserts only the root #506
## names, and the fix's guard (`ek == 2` AND `is_ref`) is exactly that root.
##
## BOTH LAYOUT TIERS ARE PROBED, because the arm this fix routes onto does not emit one thing. A
## pointee whose fields are all word-sized takes the word `movq <fi>*8(%rax), %rax`; a STANDARD
## BYTE-LAYOUT pointee (mixed widths) takes `std_struct_has_direct_byte_layout` + a SIZED load at the
## field's BYTE offset, which is a different branch with a different way to be wrong (a `u16` read
## with a `movq` drags in its neighbours). `Trio { p : u32, q : u16, r : u64 }` = 17/29/53 covers the
## second tier at codes 100-111, with its own direct-read controls at 112-114. On the parent the word
## tier fails at 62 and the byte tier fails independently at 103 (measured on its own: parent 103,
## this tree 42); the values 17, 29 and 53 are pairwise distinct and no sum of them is any of them.
##
## THE SUBJECT IS PROBED FIRST, before any control. That order is load-bearing for the cross-target
## sweeps: the aarch64/riscv64/wasm backends fail LOUD on this read (measured 133/133/134 on the
## parent and on this tree), and reaching that trap before any later probe can answer keeps the
## non-x86 rows a clean `trap` verdict. The `ptr(Bag)` callee control at codes 23-25 answers a WRONG
## VALUE on aarch64 today — `ptr(x)` over a by-reference param hands the callee the slot's own
## address instead of the pointer the slot holds — which is a separate, pre-existing, non-x86 defect
## filed as #553; it is measured identically on both sides of this change (aarch64 answers 110 on the
## parent and on this tree) and is reached only after the subject has already trapped that backend.
##
## Codes are distinct constants below 126 (WASI `proc_exit` rejects more, and exits are mod 256);
## 42 is reserved for success and no probe can produce it.

Bag := struct { a : u64, b : u64, c : u64 }

## THE SUBJECT: an inline `deref(ptr(x)).field` whose root is a by-reference `in out` struct param.
sub_a := fn(in out x : Bag) -> u64 { deref(ptr(x)).a }
sub_b := fn(in out x : Bag) -> u64 { deref(ptr(x)).b }
sub_c := fn(in out x : Bag) -> u64 { deref(ptr(x)).c }
## The issue's own spelling: the read in ARITHMETIC position, where a zero is invisible.
sub_sum := fn(in out x : Bag) -> u64 { 40 + deref(ptr(x)).b }

## CONTROL 1 — the DIRECT field read on the same by-reference param (the working deliverer).
dir_a := fn(in out x : Bag) -> u64 { x.a }
dir_b := fn(in out x : Bag) -> u64 { x.b }
dir_c := fn(in out x : Bag) -> u64 { x.c }

## CONTROL 2 — the `ptr(Bag)` CALLEE-parameter spelling, reached from the same by-reference param.
via_a := fn(q : ptr(Bag)) -> u64 { deref(q).a }
via_b := fn(q : ptr(Bag)) -> u64 { deref(q).b }
via_c := fn(q : ptr(Bag)) -> u64 { deref(q).c }
call_a := fn(in out x : Bag) -> u64 { via_a(ptr(x)) }
call_b := fn(in out x : Bag) -> u64 { via_b(ptr(x)) }
call_c := fn(in out x : Bag) -> u64 { via_c(ptr(x)) }

## THE SECOND LAYOUT TIER: a standard BYTE-layout pointee (mixed field widths), which reaches the
## sized-load branch of the same arm rather than the word `movq`.
Trio := struct { p : u32, q : u16, r : u64 }
trio_p := fn(in out x : Trio) -> u64 { u64(deref(ptr(x)).p) }
trio_q := fn(in out x : Trio) -> u64 { u64(deref(ptr(x)).q) }
trio_r := fn(in out x : Trio) -> u64 { deref(ptr(x)).r }
tdir_p := fn(in out x : Trio) -> u64 { u64(x.p) }
tdir_q := fn(in out x : Trio) -> u64 { u64(x.q) }
tdir_r := fn(in out x : Trio) -> u64 { x.r }

## Classify one field answer into the four outcomes above. 0 means "the field's value"; every other
## result is `base` plus the offset naming WHICH wrong shape was answered.
cf := fn(got : u64, want : u64, o1 : u64, o2 : u64, base : u64) -> u64 {
  if got == want { return 0 }
  if got == 0 { return base }
  if got == o1 { return base + 1 }
  if got == o2 { return base + 2 }
  base + 3
}

## Classify the ARITHMETIC spelling, where the read is added to 40 and a zero read is therefore 40
## rather than 0 — the exact shape the issue reports.
cs := fn(got : u64, want : u64, none : u64, o1 : u64, o2 : u64, base : u64) -> u64 {
  if got == want { return 0 }
  if got == none { return base }
  if got == o1 { return base + 1 }
  if got == o2 { return base + 2 }
  base + 3
}

main := fn() -> u64 {
  mut bag := Bag(a = 11, b = 61, c = 33)

  ## ---- THE SUBJECT, probed FIRST (codes 62-65, then 46-49 / 52-55 / 56-59) ----
  ## The issue's own arithmetic spelling: 101 is right, 40 is "the read contributed nothing",
  ## 51 is field `a`, 73 is field `c`, anything else is garbage.
  mut r := cs(sub_sum(bag), 101, 40, 51, 73, 62)
  if r != 0 { return r }
  r = cf(sub_a(bag), 11, 61, 33, 46)
  if r != 0 { return r }
  r = cf(sub_b(bag), 61, 11, 33, 52)
  if r != 0 { return r }
  r = cf(sub_c(bag), 33, 11, 61, 56)
  if r != 0 { return r }

  ## ---- THE SUBJECT, BYTE TIER: mixed field widths -> the SIZED-load branch (codes 100-111) ----
  ## Probed before the controls for the same reason the word tier is: the non-x86 backends must reach
  ## their fail-loud trap here, not answer a control.
  mut t := Trio(p = 17, q = 29, r = 53)
  r = cf(trio_p(t), 17, 29, 53, 100)
  if r != 0 { return r }
  r = cf(trio_q(t), 29, 17, 53, 104)
  if r != 0 { return r }
  r = cf(trio_r(t), 53, 17, 29, 108)
  if r != 0 { return r }

  ## ---- CONTROL 1: the DIRECT read on the by-reference param (codes 20-22) ----
  if dir_a(bag) != 11 { return 20 }
  if dir_b(bag) != 61 { return 21 }
  if dir_c(bag) != 33 { return 22 }

  ## ---- CONTROL 2: the `ptr(Bag)` callee-parameter spelling (codes 23-25) ----
  if call_a(bag) != 11 { return 23 }
  if call_b(bag) != 61 { return 24 }
  if call_c(bag) != 33 { return 25 }

  ## ---- CONTROL 1b: the DIRECT read on the BYTE-tier param (codes 112-114) ----
  if tdir_p(t) != 17 { return 112 }
  if tdir_q(t) != 29 { return 113 }
  if tdir_r(t) != 53 { return 114 }

  ## ---- the DIRECT control must STILL answer after every subject has run (codes 29-31) ----
  if dir_a(bag) != 11 { return 29 }
  if dir_b(bag) != 61 { return 30 }
  if dir_c(bag) != 33 { return 31 }

  42
}
