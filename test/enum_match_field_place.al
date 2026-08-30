## e2e — the three enum-scrutinee paths `src/lower/enum_match.al` owns, locked before its field offsets
## moved onto the shared `lower_layout::field_byte_place` helper (issue #273, parent #264).
##
## The file resolved every field offset through `field_word_offset` and multiplied by 8 at each of its
## three call sites — the only file in the tree with a 100% word-model offset share. The helper answers
## the same byte offset through the `layout_kind` oracle, so this fixture is the before/after anchor:
## it passed on the parent and must keep passing, with byte-identical GAS.
##
## The three paths, in the order `enum_match.al` reaches them:
##   1. an enum FIELD of a struct whose neighbours are NARROW — the shape where a word offset and a
##      byte offset could disagree if the enum field were not word-aligned;
##   2. the same with WIDE neighbours — the control where both models agree by construction;
##   3. an enum ELEMENT of a struct-field ARRAY — the `emit_index_addr` path at the third call site,
##      and the shape issue #254 was filed against.
## Returns 42 iff all three resolve their variant and payload correctly.
E := enum { A(u8), B(u8) }
Narrow := struct { tag : u8, e : E, flag : u8 }
Wide   := struct { tag : u64, e : E, flag : u64 }
Held   := struct { items : [E; 2] }

main := fn() -> u64 {
  n := Narrow(tag = 1, e = E.A(7), flag = 3)
  if u64(n.tag) != 1 { return 1 }
  if u64(n.flag) != 3 { return 2 }
  match n.e { E::A(v) => { if u64(v) != 7 { return 3 } } E::B(v) => { return 4 } }

  w := Wide(tag = 1, e = E.B(5), flag = 3)
  if w.tag != 1 { return 5 }
  if w.flag != 3 { return 6 }
  match w.e { E::A(v) => { return 7 } E::B(v) => { if u64(v) != 5 { return 8 } } }

  h := Held(items = [E.A(7), E.B(5)])
  match h.items[0] { E::A(v) => { if u64(v) != 7 { return 9 } } E::B(v) => { return 10 } }
  match h.items[1] { E::A(v) => { return 11 } E::B(v) => { if u64(v) != 5 { return 12 } } }
  42
}
