## Issue #502 — `deref(q)` as a WHOLE-`str` OPERAND answers the POINTER WORD when `q` is INFERRED.
##
## Measured on the frozen seed, native x86_64, default build path, before this change:
##
##   q := ptr(s)              q : ptr(str) = ptr(s)
##   deref(q) == "a,bc"  ->  FALSE (100)          ->  TRUE (104)
##
## Same operand, same bytes, same compiler: the ANNOTATED spelling is right and the INFERRED one is
## wrong. `str` is the base tier's `{ptr, len}` pair and Memory §4.1 makes `deref(q)` an ordinary read
## through the pointer, so a clean compile answering `false` for byte-equal content is a SILENT WRONG
## VALUE (I11) — no diagnostic, no trap, just the wrong answer to `==`.
##
## ## Where it comes from
##
## `is_str_operand` (`src/lower.al`) decides "is this operand a two-word `str` view", and its `deref`
## case asked a SPAN-VALUED question — `deref_view_span_cx(e, cx).n != 0`. An annotated or bitcast
## local answers that from its own spelling; an inferred `q := ptr(s)` cannot, because `str` is
## STRUCTURAL and no `str` span exists anywhere in the source to hand back. The operand was therefore not
## recognized, fell to scalar lowering, and `==` compared the pointer word instead of the bytes.
##
## The decider that answers this WITHOUT a span was already in the tree: `deref_addr_view_ptr_local`
## (#482/#483, which fixed the inline `.len`/`.ptr` read and the `x := deref(q)` binding) scans the
## local's own declaration `q := ptr(<ident>)` and asks `view_dest_is_local` whether the ADDRESSED
## identifier's slot carries its own pair. That is exactly the fact this operand needs — and a fourth site
## asks the same question the same span-valued way: `view_temp_arg`'s `deref` case, which made
## `io::print(deref(p))` print NOTHING. Both sites are widened here, because leaving one is leaving the
## same wrong value through a different door.
##
## ## Why the emitter is safe for the inferred case
##
## `emit_str_pair`'s `Expr::Deref` arm is SPAN-FREE: it lowers the pointer to get an address in `%rax`
## and reads word 0 and word 8 at the ascending pointee offsets. It never needed the pointee's NAME —
## only recognition did. So widening the predicate routes the operand into machinery that already worked.
##
## ## Probes, and what each catches that the others cannot
##
## One code per probe (#386 — no `good * K + bad` aliasing), 42 reserved for success. Codes 20-28 are
## VACUITY GUARDS that reject a malformed subject before any probe runs, so a broken subject can never
## masquerade as a fixed defect.
##
##   probe                                                     code
##   A  INFERRED    `deref(qa) == "a,bc"`                     60   the defect itself
##   B  INFERRED    `deref(qz) == "xyzzy!"`                 61   a SECOND subject, different byte length:
##                                                                    a stale slot cannot satisfy both A and B
##   C  INFERRED    `deref(qd1) == deref(qd2)`, SAME bytes  62   THE DISCRIMINATOR. Two DISTINCT locals
##                                                                    (`"dup"` in `d1` and in `d2`, guard 28
##                                                                    proves their addresses differ) hold EQUAL
##                                                                    bytes: a BYTE compare says TRUE, a
##                                                                    POINTER-WORD compare says FALSE. A and B
##                                                                    alone cannot tell the two mechanisms
##                                                                    apart — comparing `&"a,bc"` against a
##                                                                    literal's own address is false for a
##                                                                    reason that looks like the subject.
##   D  INFERRED    `deref(qa) == deref(qz)`, DIFF bytes    63   must stay FALSE: catches a predicate that
##                                                                    now answers "str" for everything
##   E  INFERRED `mut` `deref(mq) == "qrstuvw"`             64   the `mut` spelling of the same route
##   F  ARG path    `strlen(deref(qa))`, `strlen(deref(mq))` 65, 66  `view_temp_arg`: the pair must be
##                                                                    MATERIALIZED into an agg-temp, not
##                                                                    forwarded as one word
##   G  SCALAR ctl  `deref(qx) == 7` on `ptr(u64)`          67   NON-VACUITY OF THE WIDENING. `x`'s slot
##                                                                    is not a view dest, so the widened
##                                                                    predicate must still say NO here; if it
##                                                                    said yes, every scalar `deref` compare
##                                                                    would route into `emit_str_pair` and this
##                                                                    probe would break
##   H  ANNOT ctl   `deref(qaa) == "a,bc"`                  68   the spelling that was already correct
##   I  INLINE ctl  `deref(qa).len`, `.ptr`                 69, 70  #482's inline route must not have moved
##   J  BOUND ctl   `sa := deref(qa)` then `.len`, `.ptr`   71, 72  #483's bound route must not have moved
##   K  RE-READ     every subject again, after all probes   75-77   the operands must not have been
##                                                                    consumed or the frame disturbed

strlen := fn(s : str) -> u64 { s.len }

main := fn() -> u64 {
  ## ---- subjects, read directly first ----
  a := "a,bc"
  z := "xyzzy!"
  mut mz := "qrstuvw"
  if a.len != 4 { return 20 }
  if z.len != 6 { return 21 }
  if mz.len != 7 { return 22 }
  ap := unchecked bitcast(usize, a.ptr)
  zp := unchecked bitcast(usize, z.ptr)
  if ap == 0 { return 23 }
  if zp == 0 { return 24 }
  if ap == zp { return 25 }

  ## ---- probe C's pair: two DISTINCT locals holding EQUAL bytes ----
  d1 := "dup"
  d2 := "dup"
  if d1.len != 3 or d2.len != 3 { return 26 }
  d1p := unchecked bitcast(usize, d1.ptr)
  d2p := unchecked bitcast(usize, d2.ptr)
  if d1p == 0 or d2p == 0 { return 27 }
  if d1p == d2p { return 28 }      ## if the two literals are folded to one address, C is vacuous

  ## ---- the inferred pointers: the shape that was wrong ----
  qa := ptr(a)
  qz := ptr(z)
  qd1 := ptr(d1)
  qd2 := ptr(d2)
  mut mq := ptr(mz)

  ## A / B — the defect, on two subjects of different length
  if deref(qa) != "a,bc" { return 60 }
  if deref(qz) != "xyzzy!" { return 61 }

  ## C — the discriminator: equal bytes reached through two different pointers
  if deref(qd1) != deref(qd2) { return 62 }

  ## D — different bytes must still be unequal
  if deref(qa) == deref(qz) { return 63 }

  ## E — the `mut` spelling
  if deref(mq) != "qrstuvw" { return 64 }

  ## F — the ARG path (`view_temp_arg`): the pair must arrive materialized
  if strlen(deref(qa)) != 4 { return 65 }
  if strlen(deref(mq)) != 7 { return 66 }

  ## G — SCALAR control: `ptr(u64)` is NOT a view and must not be routed as one
  mut x : u64 = 7
  qx := ptr(x)
  if deref(qx) != 7 { return 67 }

  ## H — ANNOTATED control, the spelling that was already correct
  qaa : ptr(str) = ptr(a)
  if deref(qaa) != "a,bc" { return 68 }

  ## I / J — the inline and bound routes, unmoved
  if deref(qa).len != 4 { return 69 }
  if unchecked bitcast(usize, deref(qa).ptr) != ap { return 70 }
  sa := deref(qa)
  if sa.len != 4 { return 71 }
  if unchecked bitcast(usize, sa.ptr) != ap { return 72 }

  ## K — every subject must STILL answer after every probe has run
  if a.len != 4 or z.len != 6 or mz.len != 7 { return 75 }
  if d1.len != 3 or d2.len != 3 { return 76 }
  if deref(qz) != "xyzzy!" { return 77 }

  42
}
