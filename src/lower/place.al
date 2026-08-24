## selfhost::lower::place — resolving and ADDRESSING an aggregate PLACE: the field path, the index,
## the element. Given `o.inner.tail`, `a[i]`, `a[i].f` or `ptr(<place>)`, this band answers *where the
## bytes are* (`field_place_parts`, `standard_field_path`, `std_idx_path`/`std_idx_one`,
## `resolve_idx_field_place`, `field_read_agg`, `agg_field_of`) and emits the address or the
## element copy (`emit_index_addr`, `emit_addr_of`, `emit_elem_copy_in`).
##
## WHY THIS BAND, measured — the seam was chosen by CO-CHANGE, not by size. Over the two days of lane
## work the four `P1-CLAYOUT` lanes S3(a)–S3(d) ran STRICTLY one after another because each needed
## `src/lower.al` and its neighbours at once. Mapping each of those four commits' diff hunks onto the
## enclosing top-level function shows they touched, inside `lower.al`, almost exactly this set:
##   S3(a) 22acca63: agg_field_of, field_place_parts, field_read_agg, standard_field_path (+ emit_gas,
##                   bind_param, emit_st_field_*)
##   S3(b) 261eca66: field_place_parts, field_read_agg, resolve_idx_field_place (+ emit_st_field_assign)
##   S3(c) f87ccb26: field_read_agg (+ emit_st_assign)
##   S3(d) c13a98ec: emit_elem_copy_in, emit_index_addr, resolve_idx_field_place, standard_field_path,
##                   slot_elem_stride_bytes, agg_arr_fill_count, std_idx_* (+ emit_gas, emit_st_*)
## Of the 65 commits in history that touch this band, 9 touch NOTHING ELSE in `lower.al` — those nine
## are the ones a future lane can now do while owning a leaf.
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. The 14 entry points are re-imported into `lower.al` by
## BARE NAME, which keeps the ~120 call sites unchanged AND keeps the boundary `@inline`-transparent.
##
## What it BORROWS, spelled out — this list IS the band's dependency graph (Modules §3+§4):
##   * from its ANCESTOR `lower` (no import; §3 resolves a bare name up the ancestor chain): 44
##     functions, the types `AggFld`/`FPParts`/`FieldAgg`/`IFPlace`/`SlotEntry`/`StdFieldPath`/
##     `StdIdxOne`/`StdIdxPath`, and the mutable global `EMIT_PARAMS`.
##   * from SIBLING children, as EXPLICIT listed projections off a qualified path, because a bare
##     child-to-child call would bind through the unique-declaration leniency and
##     `scripts/callee_module_check.sh` is SILENT on that: `index_plain_scalar_struct` from
##     `lower::ir` and `lower_show_src_line` from `lower::ctfold`. (`lower::ctfold` in turn borrows
##     `field_place_parts` from here — a mutual sibling import, probed to resolve and run.)
##   * from the top-level modules `rt`, `ast`, `lower_ctx`, `lower_layout`, as the other children do.
## Spelling constraint, measured twice now: a ONE-ELEMENT listed projection immediately after a bare
## module alias is a PARSE ERROR (`strbuf := rt` then `(Expr) := ast` -> "unexpected token `:=`"), so
## `Expr` comes in as a member alias. The same list further down parses fine once a member alias
## separates it from the bare alias.
strbuf := rt
Expr := ast::Expr
(push_str, push_int) := strbuf
(LCtx, SVec, arg_expr_at, num_lit_value, var_name_span) := lower_ctx
(enum_decl_of, field_word_offset, field_words, is_packed, is_union_decl, layout_elem_stride_bytes, layout_field_offset_bytes, layout_kind, layout_kind_is_byte, standard_field_byte_offset, std_array_elem_byte_tier, std_copy_image_bytes, std_copy_kind, std_struct_has_byte_layout, std_struct_is_word_granular, struct_decl_of, struct_words) := lower_layout
## SIBLING children, reached by an explicit qualified path (Modules §4) — never by a bare name.
(index_plain_scalar_struct) := lower::ir
(lower_show_src_line) := lower::ctfold

## Shared core of `agg_field_arg_parts`: is `base.<[fs,fl)>` an aggregate field, and how to address it?
pub agg_field_of := fn(base : ptr(Expr), fs : usize, fl : usize, cx : ptr(LCtx)) -> AggFld {
  mut res := AggFld(ok = false, is_ref = false, ent_idx = 0, slot = 0, fi = 0)
  bt := base_struct_span(base, cx)
  if bt.n != 0 {
    ft := field_type_span(cx.decls, cx.src, bt.s, bt.n, fs, fl, deref(cx.mar))
    ftb := base_type_name(cx.src, ft.s, ft.n)
    ## an aggregate FIELD is passed BY REFERENCE (its address) so `display` recurses into it — a
    ## struct/enum field, OR an ARRAY `[T; N]` / TUPLE `(…)` field (its type text starts `[`/`(`).
    ## A scalar/str field keeps the value path. The array/tuple field's word-0 address is the same
    ## down-growing member address a struct/enum field uses (field_slot / field_base_ref).
    mut is_agg_fld := ftb.n != 0 and (struct_decl_of(cx.decls, cx.src, ftb.s, ftb.n) >= 0 or enum_decl_of(cx.decls, cx.src, ftb.s, ftb.n) >= 0)
    if ft.n != 0 and (str_at((cx.src + ft.s), 1) == "[" or str_at((cx.src + ft.s), 1) == "(") { is_agg_fld = true }
    if ft.n != 0 and (str_at((cx.src + ft.s), ft.n) == "str" or str_at((cx.src + ftb.s), ftb.n) == "Slice") { is_agg_fld = true }
    if is_agg_fld {
      ## P1-CLAYOUT S3(a) FENCE. Both addressing forms below are WORD-model: `fbr.fi * 8` and
      ## `field_slot`. For a STANDARD-BYTE-LAYOUT base struct the aggregate field does not start at a
      ## word multiple of its word-model index — a `[u8;4]` field counts as FOUR words there while it
      ## occupies FOUR BYTES — so this hands the callee (or the return registers) the wrong block.
      ## Measured with the fence absent: `getx(o.inner)` returned 0 instead of 20, and `readx(o)`
      ## (the whole struct by value) 0 instead of 20, on x86_64. Reject located; the byte-precise
      ## param/return ABI is audit stage S3(e), and until it lands binding the inner value to its own
      ## local (`c := o.inner`, which IS byte-aware) is the supported spelling.
      if layout_kind_is_byte(layout_kind(cx.decls, cx.src, bt.s, bt.n, deref(cx.mar))) {
        lower_show_src_line(cx.src, fs)
        panic("selfhost: an AGGREGATE field of a standard-byte-layout struct (the source line above) cannot be passed or returned BY VALUE yet — the by-value paths address it by WORD index while its containing struct is laid out in BYTES, which would hand the callee the wrong block. Bind it to its own local first (`c := o.inner`) and pass THAT.")
      }
      fbr := field_base_ref(base, fs, fl, cx)
      if fbr.is_ref {
        res = AggFld(ok = true, is_ref = true, ent_idx = fbr.ent_idx, slot = 0, fi = fbr.fi)
      } else {
        res = AggFld(ok = true, is_ref = false, ent_idx = 0, slot = field_slot(base, fs, fl, cx), fi = 0)
      }
    }
  }
  res
}
## Count the reserved element FILLER slots (`ns == 0 && nl == 0`) reserved for an array. §4 UP-GROWING:
## `bind_array_slot` now pushes the `nel*stride` fillers BELOW the base (before it), so scan DOWNWARD
## from `bslot - 1`; every real binding (including the previous local's base) carries a name, so the run
## stops exactly at the array's start. Divided by the element stride this recovers the element COUNT of a
## LITERAL-bound AGGREGATE array (whose `snl` holds the element type span, not the count).
pub agg_arr_fill_count := fn(slots : ptr(SVec), bslot : usize) -> usize {
  mut i := bslot
  mut fills := 0
  mut scanning := true
  while i > 0 and scanning {
    e := deref(svec_at(SlotEntry, slots, i - 1))
    if e.ns == 0 and e.nl == 0 { fills = fills + 1; i = i - 1 }
    else { scanning = false }
  }
  fills
}
## P1-CLAYOUT S3(d) — the ELEMENT STRIDE IN BYTES of an array slot, which is the one number every
## element address on this backend is scaled by. `SlotEntry.estride` is denominated in WORDS and every
## pre-existing element kind's byte stride IS `estride * 8` (a scalar/float element is 1 word, a `str`
## element 2, an enum element `1 + max_arity`, a word-tier struct element `struct_words`), so this
## function reduces to the historical `estride * 8` everywhere except the one tier it exists for.
##
## For a BYTE-tier struct element it answers `layout_elem_stride_bytes` — Types §6.4's stride, defined
## once in `lower_layout` and shared with every reader — which is what `estride * 8` cannot express:
## `struct { data : [u8;3], inner : { lead : u16, raw : [u8;2], tail : u16 } }` is 10 bytes with
## alignment 2, so its stride is 10 while `struct_words * 8` is 16 and element 1 would start 6 bytes
## into element 0's padding. Note the slot's word RESERVATION stays `nel * estride` words, which is
## therefore an OVER-reservation for such an element (`round_up(S, align) <= ceil(S/8)*8` always) —
## deliberately, so `agg_arr_fill_count / estride` keeps recovering the element COUNT for the bounds
## check and no slot-allocation arithmetic changes.
pub slot_elem_stride_bytes := fn(ent : SlotEntry, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> i64 {
  if ent.ek == 5 and ent.eek == 2 and ent.snl != 0 {
    if std_array_elem_byte_tier(decls, src, ent.sns, ent.snl, a) { return i64(layout_elem_stride_bytes(decls, src, ent.sns, ent.snl, a)) }
  }
  i64(ent.estride) * 8
}
pub field_place_parts := fn(e : ptr(Expr)) -> FPParts {
  z := unchecked bitcast(ptr(Expr), 0)
  mut res := FPParts(base = z, fs = 0, fl = 0)
  match deref(e) {
    Expr::Field(b, fs, fl) => { res = FPParts(base = b, fs = fs, fl = fl) }
    _ => {}
  }
  res
}
pub standard_field_path := fn(e : ptr(Expr), slots : ptr(SVec), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> StdFieldPath {
  z := StdFieldPath(ok = false, root = 0, bo = 0, ts = 0, tl = 0)
  match deref(e) {
    Expr::Var(s, n) => {
      ent := deref(svec_at(SlotEntry, slots, entry_of(slots, src, s, n)))
      if ent.ek == 2 and not ent.is_ref and ent.snl != 0 and layout_kind_is_byte(layout_kind(decls, src, ent.sns, ent.snl, a)) {
        StdFieldPath(ok = true, root = ent.off, bo = 0, ts = ent.sns, tl = ent.snl)
      } else { z }
    }
    Expr::Field(base, fs, fl) => {
      p := standard_field_path(base, slots, decls, src, a)
      if p.ok {
        bo := layout_field_offset_bytes(decls, src, p.ts, p.tl, fs, fl, a)
        ft := field_type_span(decls, src, p.ts, p.tl, fs, fl, a)
        if bo >= 0 and ft.n != 0 { StdFieldPath(ok = true, root = p.root, bo = p.bo + bo, ts = ft.s, tl = ft.n) } else { StdFieldPath(ok = false, root = 0, bo = 0, ts = 0, tl = 0) }
      } else { StdFieldPath(ok = false, root = 0, bo = 0, ts = 0, tl = 0) }
    }
    _ => { StdFieldPath(ok = false, root = 0, bo = 0, ts = 0, tl = 0) }
  }
}
pub std_idx_path := fn(e : ptr(Expr), slots : ptr(SVec), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> StdIdxPath {
  z := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Index(arr, idx) => {
      ent := deref(svec_at(SlotEntry, slots, index_base_entry(arr, slots, src)))
      if ent.ek == 5 and ent.eek == 2 and not ent.is_ref and ent.snl != 0 and std_array_elem_byte_tier(decls, src, ent.sns, ent.snl, a) {
        StdIdxPath(ok = true, arr = arr, idx = idx, bo = 0, ts = ent.sns, tl = ent.snl)
      } else { StdIdxPath(ok = false, arr = z, idx = z, bo = 0, ts = 0, tl = 0) }
    }
    Expr::Field(base, fs, fl) => {
      p := std_idx_path(base, slots, decls, src, a)
      if p.ok {
        bo := layout_field_offset_bytes(decls, src, p.ts, p.tl, fs, fl, a)
        ft := field_type_span(decls, src, p.ts, p.tl, fs, fl, a)
        if bo >= 0 and ft.n != 0 { StdIdxPath(ok = true, arr = p.arr, idx = p.idx, bo = p.bo + bo, ts = ft.s, tl = ft.n) } else { StdIdxPath(ok = false, arr = z, idx = z, bo = 0, ts = 0, tl = 0) }
      } else { StdIdxPath(ok = false, arr = z, idx = z, bo = 0, ts = 0, tl = 0) }
    }
    _ => { StdIdxPath(ok = false, arr = z, idx = z, bo = 0, ts = 0, tl = 0) }
  }
}
## Is the type `[ts,tl)` reached by an `std_idx_path` walk an AGGREGATE rather than a SCALAR leaf — an
## array, a `str`, a struct, an enum? A scalar leaf has a sized load/store (`emit_packed_load_rax` /
## `emit_packed_store_rax`); an aggregate one needs its own consumer, and the byte-ARRAY case is
## reached through the element-index path instead. Shared by the read and write arms so the two agree
## on what they claim.
pub std_idx_leaf_is_agg := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize) -> bool {
  if array_elem_span(src, ts, tl).n != 0 { return true }
  if tl == 0 { return true }
  if str_at((src + ts), tl) == "str" { return true }
  if struct_decl_of(decls, src, ts, tl) >= 0 { return true }
  if enum_decl_of(decls, src, ts, tl) >= 0 { return true }
  false
}
## P1-CLAYOUT S3(d) — `xs[i].data[j]` (any field depth): is `base` an `std_idx_path` place whose
## terminal type is an explicitly BYTE-typed fixed array? Answers its element kind (8 `u8` / 10 `i8` /
## 11 `bits8`), 0 otherwise. This is the array-element dual of `standard_byte_field_eek`, and it is a
## separate query for one reason: a struct LOCAL's byte-array field has a static frame displacement,
## while an array ELEMENT's does not — the address is `element_addr + field_§6.1_offset + j`, with the
## element address computed at run time. Both denominate the index in BYTES (stride 1, Types §6.4).
pub std_idx_byte_field_eek := fn(base : ptr(Expr), slots : ptr(SVec), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> u8 {
  p := std_idx_path(base, slots, decls, src, a)
  if not p.ok { return 0 }
  es := array_elem_span(src, p.ts, p.tl)
  if es.n == 0 { return 0 }
  byte_type_eek(src, es.s, es.n)
}
pub std_idx_one := fn(arr : ptr(Expr), fs : usize, fl : usize, cx : ptr(LCtx)) -> StdIdxOne {
  a := deref(cx.mar)
  mut r := StdIdxOne(ok = false, bo = 0, ts = 0, tl = 0)
  if var_name_span(arr).n == 0 { return r }
  ent := deref(svec_at(SlotEntry, cx.slots, index_base_entry(arr, cx.slots, cx.src)))
  if ent.ek != 5 or ent.eek != 2 or ent.is_ref or ent.snl == 0 { return r }
  if not std_array_elem_byte_tier(cx.decls, cx.src, ent.sns, ent.snl, a) { return r }
  bo := layout_field_offset_bytes(cx.decls, cx.src, ent.sns, ent.snl, fs, fl, a)
  ft := field_type_span(cx.decls, cx.src, ent.sns, ent.snl, fs, fl, a)
  if bo < 0 or ft.n == 0 { return r }
  StdIdxOne(ok = true, bo = bo, ts = ft.s, tl = ft.n)
}
pub resolve_idx_field_place := fn(e : ptr(Expr), cx : ptr(LCtx)) -> IFPlace {
  a := deref(cx.mar)
  match deref(e) {
    Expr::Index(arr, idx) => {
      ## A STRUCT-element ARRAY GLOBAL has no frame SlotEntry. Recover its element type from the
      ## first initializer element (the same source of truth used by the global element-copy/write
      ## paths), so `TAB[i].a.b` composes exactly like a frame array root.
      avn := var_name_span(arr)
      if avn.n != 0 {
        gmv := global_arr_value(cx.slots, cx.decls, cx.src, avn.s, avn.n)
        if unchecked bitcast(usize, gmv) != 0 {
          ali := array_lit_info(gmv)
          if ali.is_a and ali.nel > 0 {
            ge := struct_lit_info(arg_expr_at(ali.ehead, 0, a))
            if ge.is_s { return IFPlace(found = true, tys = ge.ss, tyn = ge.sl, woff = 0) }
          }
        }
      }
      ent := deref(svec_at(SlotEntry, cx.slots, index_base_entry(arr, cx.slots, cx.src)))
      if ent.eek != 2 or ent.snl == 0 { return IFPlace(found = false, tys = 0, tyn = 0, woff = 0) }
      return IFPlace(found = true, tys = ent.sns, tyn = ent.snl, woff = 0)
    }
    Expr::Field(ib, fs, fl) => {
      inner := resolve_idx_field_place(ib, cx)
      if inner.found == false { return IFPlace(found = false, tys = 0, tyn = 0, woff = 0) }
      if struct_decl_of(cx.decls, cx.src, inner.tys, inner.tyn) < 0 {
        panic("selfhost: `arr[i].field…leaf` where an intermediate `field` is not a plain struct is not yet supported (str/enum/union/slice intermediate — bind it to a local first)")
      }
      fty := field_type_span(cx.decls, cx.src, inner.tys, inner.tyn, fs, fl, a)
      if fty.n == 0 { return IFPlace(found = false, tys = 0, tyn = 0, woff = 0) }   ## not a field of this hop → not this shape
      ## P1-CLAYOUT S3(b) — a BYTE-TIER hop has no word offsets to compose. `field_word_offset` below
      ## counts a `[u8; 4]` field as FOUR WORDS where §6.1 gives it four BYTES, and the element itself
      ## was written by the byte-precise whole-value writer, so composing word offsets through such a
      ## hop reads a place nothing wrote. That was already a SILENT WRONG VALUE before S3(b), measured
      ## on 495e842: `[Outer; 2]` with `Outer = struct { data : [u8;4], inner : struct { x : u64,
      ## y : u64 } }` returned exit 1 for `xs[0].inner.y` (want 42) on x86_64 AND on a64/rv64/wasm —
      ## the offsets differ by 24 bytes (`inner` at §6.1 byte 8 versus word 4 = byte 32). S3(a) hid the
      ## SUB-WORD case of it behind the construction fence; removing that fence would have converted a
      ## reject into the same wrong value, so the cause is fenced here instead. `standard_field_path`
      ## deliberately refuses an `Index` root for the same reason, and giving the array element tier a
      ## byte-precise stride + place resolver is audit stage S3(c).
      if layout_kind_is_byte(layout_kind(cx.decls, cx.src, inner.tys, inner.tyn, a)) {
        ## P1-CLAYOUT S3(d) — the fence STAYS, but it is no longer the only answer: when the byte-precise
        ## element-place resolver owns this whole chain (`std_idx_path` walks the SAME expression and
        ## answers `ok` only when the ROOT element is a byte-tier struct in the one writer's domain AND
        ## every hop has a §6.1 offset), hand the place over instead of refusing it — `found = false` is
        ## how this resolver says "not my shape", and every consumer of it checks the S3(d) arm first.
        ## Asking `std_idx_path` about the FULL expression, not about this hop's type, is what keeps the
        ## two exhaustive: a byte-tier hop reached from a WORD-tier element (a plain `[P; N]` whose `P`
        ## merely contains a byte-layout child) is written by the word-per-field constructor, has no
        ## byte-precise element place, and still panics here rather than becoming a silent 0.
        if std_idx_path(e, cx.slots, cx.decls, cx.src, a).ok { return IFPlace(found = false, tys = 0, tyn = 0, woff = 0) }
        panic("selfhost: `arr[i].field…leaf` through a STANDARD BYTE-LAYOUT intermediate struct is not supported in this slice — the element is written at its §6.1 byte offsets while this place composes WORD offsets, so the two name different bytes (measured: 24 bytes apart for `struct { data : [u8;4], inner }`). Bind the element to a local first (`e := xs[i]`), then read the leaf.")
      }
      wf := field_word_offset(cx.decls, cx.src, inner.tys, inner.tyn, fs, fl, a)
      if wf < 0 { panic("selfhost: `arr[i].field…leaf` — intermediate field not resolvable in the element struct type") }
      return IFPlace(found = true, tys = fty.s, tyn = fty.n, woff = inner.woff + i64(wf))
    }
    _ => { return IFPlace(found = false, tys = 0, tyn = 0, woff = 0) }
  }
}
## Emit `ptr(<place>)` — push the ADDRESS of the place onto the stack. Two place forms:
##   * a local `Var` — `leaq -(slot+1)*8(%rbp), %rax` (its frame slot).
##   * an array ELEMENT `a[i]` (`Expr::Index`) — reuse `emit_index_addr`, which computes the
##     element address `-(base+1)*8(%rbp) - i*8` into %rax; `ptr(a[i])` is exactly "leave
##     that address as the value" instead of loading from it (`Expr::Index` READ loads `(%rax)`).
##     This is the arena `get` shape: a buffer + a handle → a real pointer the caller derefs.
## Any other inner place pushes a placeholder 0. The deref-`match` on the inner pointer PARAM
## stays here (a direct param) — the lowerable shape (mirroring `struct_lit_info`/`field_slot`).
pub emit_addr_of := fn(p : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  match deref(p) {
    Expr::Var(s, n) => {
      ## `ptr(GLOBAL)` — the address of a MUTABLE module global is its `.data` label, not a frame slot:
      ## `leaq LABEL(%rip)`. Enables the canonical shared atomic counter (`atomic::fetch_add(ptr(CTR),…)`).
      ## Checked FIRST — a global has no slot, so the `entry_of`/`slot_of` path below reads garbage.
      if is_module_mut_global(cx.decls, cx.src, s, n) {
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, s, n)
        push_str(sb, "(%rip), %rax\n  pushq %rax\n")
        return
      }
      ent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, s, n)))
      if ent.is_ref {
        ## `ptr(x)` where `x` is a BY-REFERENCE aggregate param: its slot already HOLDS a pointer
        ## to the caller's aggregate, so the address IS that stored pointer — LOAD it (`movq`), do
        ## NOT take the slot's own address (`leaq`). Without this `ptr(slots)` over an `in out S`
        ## param yielded `&slot` (pointing at the pointer word), so a following `deref(...).field`
        ## read the wrong words (the >16B `in out SVec` param crash in bind_param/slot_of).
        push_str(sb, "  movq -")
        push_int(sb, i64((ent.off + 1) * 8))
        push_str(sb, "(%rbp), %rax\n  pushq %rax\n")
      } else {
        slot := slot_of(cx.slots, cx.src, s, n)
        push_str(sb, "  leaq -")
        push_int(sb, (slot + 1) * 8)
        push_str(sb, "(%rbp), %rax\n  pushq %rax\n")
      }
    }
    Expr::Index(base, idx) => {
      ## `ptr(GLOBAL[i])` — the address of an ARRAY global's element. A byte-typed global uses
      ## `LABEL + i`; the historical word-global path remains `LABEL + i*8`. This is still a plain
      ## address value, so no call/parameter ABI changes are involved. A non-global base uses the
      ## frame-array `emit_index_addr` path.
      ibv := var_name_span(base)
      mut imgv := if ibv.n != 0 { mut_global_value(cx.decls, cx.src, ibv.s, ibv.n) } else { unchecked bitcast(ptr(Expr), 0) }
      if unchecked bitcast(usize, imgv) == 0 and ibv.n != 0 { imgv = const_array_value(cx.decls, cx.src, ibv.s, ibv.n) }
      mut ia_done := false
      if unchecked bitcast(usize, imgv) != 0 {
        if array_lit_info(imgv).is_a or global_array_byte_eek(cx.decls, cx.src, ibv.s, ibv.n) != 0 {
          glen := global_array_len(cx.decls, cx.src, ibv.s, ibv.n, imgv)
          emit_gas(idx, sb, cx, a, nl)                 ## index → stack
          push_str(sb, "  leaq ")
          emit_global_label(sb, cx.decls, cx.src, ibv.s, ibv.n)
          push_str(sb, "(%rip), %rax\n  popq %rcx\n")
          if cx.vchk {
            push_str(sb, "  cmpq $")
            push_int(sb, i64(glen))
            push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n")
          }
          gbyte := global_array_byte_eek(cx.decls, cx.src, ibv.s, ibv.n)
          if gbyte != 0 {
            push_str(sb, "  addq %rcx, %rax\n")
          } else {
            push_str(sb, "  leaq (%rax,%rcx,8), %rax\n")
          }
          push_str(sb, "  pushq %rax\n")
          ia_done = true
        }
      }
      if ia_done == false {
        emit_index_addr(base, idx, sb, cx, a, nl)
        push_str(sb, "  pushq %rax\n")
      }
    }
    Expr::Field(base, fs, fl) => {
      ## `ptr(GLOBAL.field)` — the address of a mutable struct global's field is `LABEL + k*8`
      ## (`leaq`), enabling e.g. an atomic op on one field of a global struct. (Address-of a LOCAL
      ## struct field is separate future work; a non-global-field base falls to the `$0` placeholder.)
      gfv := var_name_span(base)
      gfmgv := if gfv.n != 0 { mut_global_value(cx.decls, cx.src, gfv.s, gfv.n) } else { unchecked bitcast(ptr(Expr), 0) }
      mut gf_done := false
      if unchecked bitcast(usize, gfmgv) != 0 {
        gfsli := struct_lit_info(gfmgv)
        if gfsli.is_s {
          gfi := struct_field_index(cx.decls, cx.src, gfsli.ss, gfsli.sl, fs, fl, a)
          if gfi >= 0 {
            push_str(sb, "  leaq ")
            emit_global_label(sb, cx.decls, cx.src, gfv.s, gfv.n)
            push_str(sb, "+")
            push_int(sb, gfi * 8)
            push_str(sb, "(%rip), %rax\n  pushq %rax\n")
            gf_done = true
          }
        }
      }
      if gf_done == false and gfv.n != 0 {
        lent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, gfv.s, gfv.n)))
        if lent.ek == 2 and std_struct_has_byte_layout(cx.decls, cx.src, lent.sns, lent.snl, deref(cx.mar)) {
          lbo := standard_field_byte_offset(cx.decls, cx.src, lent.sns, lent.snl, fs, fl, deref(cx.mar))
          if lbo >= 0 {
            if lent.is_ref {
              push_str(sb, "  movq -")
              push_int(sb, i64((lent.off + 1) * 8))
              push_str(sb, "(%rbp), %rax\n")
              if lbo != 0 { push_str(sb, "  addq $"); push_int(sb, lbo); push_str(sb, ", %rax\n") }
            } else {
              push_str(sb, "  leaq -")
              push_int(sb, i64((lent.off + 1) * 8) - lbo)
              push_str(sb, "(%rbp), %rax\n")
            }
            push_str(sb, "  pushq %rax\n")
            gf_done = true
          }
        }
      }
      ## `pushq $0` here is the ADDRESS ZERO placeholder, and an address is never a safe placeholder:
      ## `ptr(o.inner.x)` and `ptr(o.inner.y)` both reduced to 0, so two distinct fields compared
      ## EQUAL (measured: the `px == py` probe answered "same address" for a byte-layout struct AND —
      ## the same defect, pre-existing and independent of this lane — for an ordinary word-layout
      ## `struct { pad : u64, inner : Inner }`). A wrong address is a wrong value under I11, so refuse
      ## it located instead. Only two corpus fixtures take a field address at all
      ## (`atomic_global_field` — a global, handled above; `standard_byte_array_field` — a byte-layout
      ## local's scalar field, handled above), so this closes the hole rather than narrowing support.
      if gf_done == false {
        lower_show_src_line(cx.src, fs)
        panic("selfhost: `ptr(<field>)` is not supported for this place (the source line above) — only a mutable struct GLOBAL's field and a standard-byte-layout struct LOCAL's own field have an addressable offset here. A nested field path (`ptr(o.inner.x)`) would otherwise take the address ZERO, which makes two distinct fields compare equal. Bind the inner value to a local and take its address.")
      }
    }
    _ => { push_str(sb, "  pushq $0\n") }
  }
}
pub field_read_agg := fn(v : ptr(Expr), slots : ptr(SVec), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> FieldAgg {
  mut r := FieldAgg(kind = 0, s = 0, n = 0, boff = 0, fwo = 0, isr = false)
  ## A standard-byte root has a compressed field before the aggregate, so the old word offset is
  ## not a usable source slot. When the child starts on a word boundary, the existing aggregate
  ## copy loop is correct once it receives the shared byte offset converted to that word base.
  s3fra := standard_field_path(v, slots, decls, src, a)
  mut s3fstd := false
  if s3fra.ok {
    s3ftb := base_type_name(src, s3fra.ts, s3fra.tl)
    mut s3fkind : u8 = 0
    if is_union_decl(decls, src, s3ftb.s, s3ftb.n) { s3fkind = 2 }
    else if struct_decl_of(decls, src, s3ftb.s, s3ftb.n) >= 0 { s3fkind = 2 }
    else if enum_decl_of(decls, src, s3ftb.s, s3ftb.n) >= 0 { s3fkind = 3 }
    else if str_at((src + s3fra.ts), s3fra.tl) == "str" { s3fkind = 4 }
    ## P1-CLAYOUT S3(b)/S3(c) — THE WORD EXTRACT NEEDS A WORD-GRANULAR CHILD; EVERYTHING ELSE IS THE
    ## COPIER'S. S3(b) made a sub-word child CONSTRUCTIBLE (`struct { data : [u8;8], inner : struct
    ## { a : u16, b : u16 } }` now has one byte-precise image on all four backends), which exposed
    ## `copy := o.inner`: this resolver hands the caller a word offset `bo / 8` and the caller copies
    ## `struct_words(child)` WORDS out of a 4-byte child into a standalone local read back at WORD
    ## offsets — a wrong value (measured: exit 1). Falling through to the word-model `match` below is
    ## the same wrong value by another route (`field_word_offset` counts the outer `[u8;8]` as EIGHT
    ## words). S3(c) supplies the missing consumer: `std_copy_kind` decides, ONCE for all four
    ## backends, whether the child has a byte-precise copy and of which shape, and `emit_standard_copy`
    ## spells it. `boff`/`fwo` still describe the WORD extract, so a copier child reports `fwo = 0` and
    ## the EMIT re-derives its byte offset from `standard_field_path` — the same walk that produced
    ## `s3fra` here — rather than carrying a word number that would be wrong if anyone used it.
    ## A child in NEITHER set (one carrying a `str`, an enum, a union, a tuple or a non-byte array)
    ## keeps the located fence, per I11.
    mut s3cck := 0
    if s3fkind == 2 and struct_decl_of(decls, src, s3ftb.s, s3ftb.n) >= 0 and not is_union_decl(decls, src, s3ftb.s, s3ftb.n) and not std_struct_is_word_granular(decls, src, s3fra.ts, s3fra.tl, a) {
      s3cck = std_copy_kind(decls, src, s3fra.ts, s3fra.tl, a)
      if s3cck == 0 {
        lower_show_src_line(src, field_place_parts(v).fs)
        panic("selfhost: extracting a whole nested aggregate field out of a standard byte-layout struct needs the byte-precise whole-value COPIER (the source line above), and this child is outside its domain — a child carrying a str, an enum, a union, a tuple or a non-byte array is written by one constructor and read by another. Read its scalar fields instead of binding the inner value.")
      }
    }
    if s3cck != 0 {
      r = FieldAgg(kind = s3fkind, s = s3fra.ts, n = s3fra.tl, boff = s3fra.root, fwo = 0, isr = false)
      s3fstd = true
    }
    if s3cck == 0 and s3fkind != 0 and (s3fra.bo / 8) * 8 == s3fra.bo {
      r = FieldAgg(kind = s3fkind, s = s3fra.ts, n = s3fra.tl, boff = s3fra.root, fwo = s3fra.bo / 8, isr = false)
      s3fstd = true
    }
  }
  if not s3fstd { match deref(v) {
    Expr::Field(base, fs, fl) => {
      bvn := var_name_span(base)
      if bvn.n != 0 {
        bent := deref(svec_at(SlotEntry, slots, entry_of(slots, src, bvn.s, bvn.n)))
        if bent.ek == 2 and streq(src, bent.ns, bent.nl, bvn.s, bvn.n) and bent.snl != 0 {
          ft := field_type_span(decls, src, bent.sns, bent.snl, fs, fl, a)
          if ft.n != 0 {
            ftb := base_type_name(src, ft.s, ft.n)
            fwo := field_word_offset(decls, src, bent.sns, bent.snl, fs, fl, a)
            if fwo >= 0 {
              if is_union_decl(decls, src, ftb.s, ftb.n) { r = FieldAgg(kind = 2, s = ft.s, n = ft.n, boff = bent.off, fwo = fwo, isr = bent.is_ref) }
              else if struct_decl_of(decls, src, ftb.s, ftb.n) >= 0 { r = FieldAgg(kind = 2, s = ft.s, n = ft.n, boff = bent.off, fwo = fwo, isr = bent.is_ref) }
              else if enum_decl_of(decls, src, ftb.s, ftb.n) >= 0 { r = FieldAgg(kind = 3, s = ft.s, n = ft.n, boff = bent.off, fwo = fwo, isr = bent.is_ref) }
              ## Types §9.4 — a `str` FIELD is a 2-word `{ptr, len}` sub-aggregate (Memory §3.5), so
              ## `c := b.v` must reserve `c` as a str LOCAL and copy BOTH words. It reported kind 0, so
              ## the binding fell to the scalar default and the emit stored word 0 only — `c.len` then
              ## read an uninitialized slot (0): a SILENT MISCOMPILE. kind 4 = str (2 words).
              else if str_at((src + ft.s), ft.n) == "str" { r = FieldAgg(kind = 4, s = ft.s, n = ft.n, boff = bent.off, fwo = fwo, isr = bent.is_ref) }
            }
          }
        }
      }
    }
    _ => {}
  } }
  r
}
## Emit a WHOLE-ELEMENT copy of an aggregate array element `arr[i]` into a LOCAL aggregate's
## reserved frame slots `dst .. dst+stride-1`. Compute the element address (`emit_index_addr` →
## %rax = the element's word-0 address, the discriminant/field-0; deeper words are at LOWER
## addresses, the frame grows DOWN), then for each word `k` copy `-(k*8)(%rax)` → local slot
## `dst + k`. The store dual of `emit_array_assign`'s aggregate-element store, but element→local.
pub emit_elem_copy_in := fn(arr : ptr(Expr), idx : ptr(Expr), dst : i64, in out sb : strbuf::StrBuf, cx : ptr(LCtx), in out nl : usize) {
  a := arena_of(cx)
  ## P1-CLAYOUT S3(d) — `e := xs[i]`, a whole BYTE-TIER element copied OUT into a standalone local. This
  ## is S3(c)'s copier reached through an element rather than through a field, and the decision is the
  ## same one: `std_copy_kind` answers 1 (IMAGE) here — the destination local's own tier is BYTE
  ## (`layout_kind` of the element type, which is what made it an element-tier array in the first
  ## place), so it is read at exactly the source's §6.1 offsets and the copy is the byte image verbatim.
  ## `std_copy_image_bytes` is the count, NOT `estride * 8`: for a 10-byte element in a 10-byte stride
  ## the word copy would read 6 bytes of the NEXT element and write them past the destination's image.
  ## Claimed first, before the array-field / global / slice / frame-array arms, none of which can
  ## express a sub-word element. `emit_index_addr` supplies the §6.4 byte-strided element address.
  if var_name_span(arr).n != 0 {
    s3dce := deref(svec_at(SlotEntry, cx.slots, index_base_entry(arr, cx.slots, cx.src)))
    if s3dce.ek == 5 and s3dce.eek == 2 and not s3dce.is_ref and s3dce.snl != 0 and std_array_elem_byte_tier(cx.decls, cx.src, s3dce.sns, s3dce.snl, a) {
      if std_copy_kind(cx.decls, cx.src, s3dce.sns, s3dce.snl, a) != 1 {
        panic("selfhost: a whole-element copy out of a byte-layout element array needs the byte IMAGE copy (`std_copy_kind` 1) — this element type is outside the copier's domain; read its scalar fields through the element place instead")
      }
      s3dcn := i64(std_copy_image_bytes(cx.decls, cx.src, s3dce.sns, s3dce.snl, a))
      emit_index_addr(arr, idx, sb, cx, a, nl)          ## the element's base address → %rax
      push_str(sb, "  movq %rax, %r13\n")
      mut s3dck := i64(0)
      while s3dck < s3dcn {
        push_str(sb, "  movzbq ")
        push_int(sb, s3dck)
        push_str(sb, "(%r13), %rax\n  movb %al, -")
        push_int(sb, (dst + 1) * 8 - s3dck)
        push_str(sb, "(%rbp)\n")
        s3dck += 1
      }
      return
    }
  }
  ## A WHOLE STRUCT element of an ARRAY FIELD (`p := xs[i].arr[j]`). `arr` is the Field place
  ## itself, so the ordinary `emit_index_addr(arr, idx)` fallback cannot resolve a Var slot. Compose
  ## the outer array element + field offset first, then the inner element's struct stride. The field
  ## storage is word-aligned and ascending within the enclosing element, matching the existing scalar
  ## `xs[i].arr[j]` path and the aggregate-element array write path.
  afe := arr_field_elem(arr, cx)
  if afe.found {
    pl := resolve_idx_field_place(arr, cx)
    ae := array_elem_span(cx.src, pl.tys, pl.tyn)
    if ae.n != 0 and struct_decl_of(cx.decls, cx.src, ae.s, ae.n) >= 0 {
      if is_packed(cx.decls, cx.src, ae.s, ae.n) {
        panic("selfhost: whole-element copy from a @packed aggregate array-field element is not yet supported")
      }
      ## Globals have no frame-owned aggregate place in this bounded increment; do not accidentally
      ## use the scalar/global address path as if it were a local or parameter root.
      gavn := var_name_span(afe.arr)
      if gavn.n != 0 and unchecked bitcast(usize, global_arr_value(cx.slots, cx.decls, cx.src, gavn.s, gavn.n)) != 0 {
        panic("selfhost: whole-element copy from a global aggregate array-field element is not yet supported")
      }
      stride := struct_words(cx.decls, cx.src, ae.s, ae.n, a)
      emit_gas(idx, sb, cx, a, nl)                 ## inner j → stack
      emit_idx_field_addr(afe.arr, afe.idx, afe.woff * 8, sb, cx, nl)
      push_str(sb, "  popq %rcx\n")
      if cx.vchk and afe.elen > 0 {
        push_str(sb, "  cmpq $")
        push_int(sb, afe.elen)
        push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n")
      }
      push_str(sb, "  imulq $")
      push_int(sb, i64(stride * 8))
      push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
      for k in 0..stride {
        push_str(sb, "  movq ")
        push_int(sb, i64(k * 8))
        push_str(sb, "(%r13), %rax\n  movq %rax, -")
        push_int(sb, i64((dst - i64(k) + 1) * 8))
        push_str(sb, "(%rbp)\n")
      }
      return
    }
  }
  ## a STRUCT-element mutable ARRAY GLOBAL element `ARR[i]` — copy from the global's `.data` (ASCENDING:
  ## element base = `LABEL + i*stride*8`, word k at base + k*8) into the down-growing local slots dst+k.
  ## The global has no frame slot, so this precedes the frame-array path (which reads DOWN-growing).
  gvn := var_name_span(arr)
  ## `mut` first (the pre-existing struct-global path), falling back to a CONST array global so an
  ## `e := GE[i]` off a non-`mut` enum array reads its `.data` too (a const array has storage).
  gmv := global_arr_value(cx.slots, cx.decls, cx.src, gvn.s, gvn.n)
  if unchecked bitcast(usize, gmv) != 0 and array_lit_info(gmv).is_a {
    ge := struct_lit_info(arg_expr_at(array_lit_info(gmv).ehead, 0, a))
    ## an ENUM-element array global's stride is `1 + enum_inst_words` (disc + widest payload), NOT the
    ## scalar `1` — with `1` the copy read one word at `LABEL + i*8`, i.e. the middle of an element.
    gaen := global_arr_enum(cx.decls, cx.src, gmv, a)
    mut gstride := 1
    if ge.is_s { gstride = struct_words(cx.decls, cx.src, ge.ss, ge.sl, a) }
    else if gaen.is_e { gstride = gaen.stride }
    emit_gas(idx, sb, cx, a, nl)                 ## index → stack
    push_str(sb, "  leaq ")
    emit_global_label(sb, cx.decls, cx.src, gvn.s, gvn.n)
    push_str(sb, "(%rip), %rax\n  popq %rcx\n")
    ## CHECKED BOUNDS (I11 §358) on the enum path (the pre-existing struct path is left byte-identical).
    if cx.vchk and gaen.is_e { push_str(sb, "  cmpq $"); push_int(sb, i64(gaen.nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
    push_str(sb, "  imulq $")
    push_int(sb, i64(gstride * 8))
    push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
    for k in 0..gstride {
      push_str(sb, "  movq ")
      push_int(sb, i64(k) * 8)
      push_str(sb, "(%r13), %rax\n  movq %rax, -")
      push_int(sb, (dst - i64(k) + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
    return
  }
  ## A multiword `Slice(T)` VALUE element `sl[i]` (arena/mmap-backed — `oset_as_slice` / `omap_values`
  ## / a constructed `Slice(T)(ptr=…, len=…)`): the backing is laid out UPWARD (element i at
  ## `ptr + i*stride*8`, field k at `+k*8`) and reached through the slice's word-0 DATA POINTER — NOT
  ## the down-growing frame slots and NOT a `.data` global. `str` is included explicitly: it has no
  ## named struct declaration, but its element is still the two-word `{ptr,len}` pair. Load the data
  ## ptr (a LOCAL keeps it at slot `off`; a by-ref param derefs), add `i*stride*8`, then copy `stride`
  ## words UP into the local's slots (`dst - k`).
  svn := var_name_span(arr)
  if svn.n != 0 {
    sent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, svn.s, svn.n)))
    if sent.ek == 2 {
      sgw := slice_val_elem_stride(cx.src, sent.sns, sent.snl, cx.decls, a)
      if sgw != 0 {
        if sent.is_ref {
          push_str(sb, "  movq -")
          push_int(sb, i64((sent.off + 1) * 8))
          push_str(sb, "(%rbp), %rax\n  movq (%rax), %rax\n")
        } else {
          push_str(sb, "  movq -")
          push_int(sb, i64((sent.off + 1) * 8))
          push_str(sb, "(%rbp), %rax\n")
        }
        push_str(sb, "  pushq %rax\n")
        emit_gas(idx, sb, cx, a, nl)                 ## index → stack (top)
        push_str(sb, "  popq %rcx\n  imulq $")
        push_int(sb, i64(sgw * 8))
        push_str(sb, ", %rcx\n  popq %rax\n  addq %rcx, %rax\n  movq %rax, %r13\n")
        for k in 0..sgw {
          push_str(sb, "  movq ")
          push_int(sb, i64(k) * 8)
          push_str(sb, "(%r13), %rax\n  movq %rax, -")
          push_int(sb, (dst - i64(k) + 1) * 8)
          push_str(sb, "(%rbp)\n")
        }
        return
      }
    }
  }
  stride := deref(svec_at(SlotEntry, cx.slots, index_base_entry(arr, cx.slots, cx.src))).estride
  emit_index_addr(arr, idx, sb, cx, a, nl)   ## element word-0 address → %rax
  push_str(sb, "  movq %rax, %r13\n")  ## keep the element base in %r13 (callee-saved)
  for k in 0..stride {
    ## source word k: element address MINUS k*8 (the frame grows down); dest local slot dst+k.
    push_str(sb, "  movq ")
    push_int(sb, i64(k) * 8)
    push_str(sb, "(%r13), %rax\n  movq %rax, -")
    push_int(sb, (dst - i64(k) + 1) * 8)
    push_str(sb, "(%rbp)\n")
  }
}
pub emit_index_addr := fn(base : ptr(Expr), idx : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  ## Slice LOCAL/PARAM — the element address reaches the view's backing pointer with the element's
  ## byte/word stride. Keep this before the struct-field and fixed-array paths: a Slice value is a
  ## 2-word view, not an inline frame array, so treating its slot as an array would address the view
  ## metadata instead of its backing storage.
  if emit_slice_index_addr(base, idx, sb, cx, a, nl) { return }
  ## STANDARD BYTE TUPLE COMPONENT INDEX — `t.0[i]` where component 0 is a direct byte array. The
  ## outer tuple component has a standard byte offset; its inner index is a raw byte displacement.
  ## This must precede the generic mixed-tuple guard, whose historical word-offset path would use the
  ## first component's word stride and silently address `t.0[1]` at byte 8 instead of byte 1.
  tbc := tuple_byte_component_base(base, cx)
  if tbc.ok {
    match deref(base) {
      Expr::Index(ib, ii) => {
        vn := var_name_span(ib)
        tent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, vn.s, vn.n)))
        emit_gas(idx, sb, cx, a, nl)
        push_str(sb, "  leaq -")
        push_int(sb, i64((tent.off + 1) * 8))
        push_str(sb, "(%rbp), %rbx\n")
        if tbc.off != 0 { push_str(sb, "  addq $"); push_int(sb, tbc.off); push_str(sb, ", %rbx\n") }
        push_str(sb, "  popq %rax\n")
        if cx.vchk {
          push_str(sb, "  cmpq $")
          push_int(sb, tbc.len)
          push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
        }
        push_str(sb, "  addq %rax, %rbx\n  movq %rbx, %rax\n")
        return
      }
      _ => {}
    }
  }
  ## SOUNDNESS (correct-or-trap, §7.2 / Types §9.4): indexing the result of a `Slice(T)`-returning CALL
  ## DIRECTLY (`f(…)[i]`) is not composed — the {ptr, len} pair lives only in the return registers, with
  ## no frame slot for `index_base_entry` to resolve (it would fall to slot 0 and read a WRONG address, a
  ## silent-0). Fail LOUD; bind the call result to a local first (`r := f(…); r[i]`, the composed path).
  ## Gated to `slice_ret_call` — a `Var`/field/other base is untouched (fixpoint-neutral).
  if slice_ret_call(base, cx.decls, cx.src, a) {
    panic("selfhost: indexing a Slice(T)-returning call result directly (`f(…)[i]`) is not lowered — bind it to a local first (`r := f(…); r[i]`)")
  }
  ## SOUNDNESS (correct-or-trap, I11 / Types §6.4): a fixed-array RETURN has no supported ABI yet.
  ## Unlike a local/param array, the call result has no frame-owned element block for the generic path
  ## below to address. Before this fence `build()[k]` fell through to slot 0 and returned a wrong byte
  ## (the codec repro returned 5 instead of the initialized 42). Locate the call's source line before
  ## the intentional reject; do not widen this to a return-ABI implementation.
  if fixed_array_ret_call(base, cx.decls, cx.src, a) {
    cp := call_parts(base)
    if cp.is_call and cp.cs != 0 { lower_show_src_line(cx.src, cp.cs) }
    panic("selfhost: indexing a fixed-array-returning call result directly (the source line above) is not lowered — the [T; N] return ABI is not implemented yet; do not index a call result until that ABI lands")
  }
  ## Types §9.4 — the index base is a 2-word `{ptr, len}` VIEW FIELD (`st.v[i]` with `v : Slice(T)`),
  ## NOT an inline `[T; N]` array field: its words are a POINTER + a length, so the element address is
  ## `load(field word 0) + i*stride`. Checked BEFORE the `fib.is_fld` array-field branch below, which
  ## reports `is_fld` for this shape too and would read the pair's own words as elements (a SILENT
  ## miscompile — `st.v[1]` returned the LENGTH). `pair_field_elem_stride` is the discriminator: it is
  ## non-zero ONLY for a `Slice(`/`str`-typed field, so every inline-array field is byte-identical.
  ## A BYTE-element view (`str` / `Slice(u8)`) computes the same address, but this fn's callers load a
  ## WORD through it; the READ path handles the byte width itself (the `Index` arm in `emit_gas`) and
  ## never reaches here, so any OTHER use (an element WRITE / address-of) fails LOUD.
  pfstr := pair_field_elem_stride(base, cx, a)
  if pfstr == 1 {
    panic("selfhost: writing through a BYTE-element view FIELD element (`s.v[i] = x` with `v : str` / `Slice(u8)`) is not lowered — the element is one byte, not a word; bind the view to a local first")
  }
  if pfstr != 0 {
    emit_pair_field_index_addr(base, idx, sb, cx, a, nl)
    return
  }
  ## BYTE ARRAY FIELD of a @packed struct: the field's byte offset is ascending from the struct
  ## word-0 address, unlike the ordinary word-model array-field path below. Keep the index on the
  ## stack while materializing the aggregate base; then add the byte offset and the raw byte index.
  pbf := packed_byte_field(base, cx)
  if pbf.ok {
    emit_gas(idx, sb, cx, a, nl)
    pfb := field_index_base(base, cx)
    fent := deref(svec_at(SlotEntry, cx.slots, pfb.ent_idx))
    emit_agg_base_addr(fent, sb)
    push_str(sb, "  movq %rax, %rbx\n")
    if pbf.off != 0 {
      push_str(sb, "  addq $")
      push_int(sb, pbf.off)
      push_str(sb, ", %rbx\n")
    }
    push_str(sb, "  popq %rax\n")
    if cx.vchk {
      push_str(sb, "  cmpq $")
      push_int(sb, pbf.len)
      push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
    }
    push_str(sb, "  addq %rax, %rbx\n  movq %rbx, %rax\n")
    return
  }
  ## BYTE ARRAY FIELD of an ordinary struct using the shared standard layout. The field offset is
  ## padded/natural-byte-aware, while the index itself has byte stride 1. Keep this before the legacy
  ## word-field path: its `field_word_offset * 8` address would silently read from a later word.
  sbf := standard_byte_field(base, cx)
  if sbf.ok {
    emit_gas(idx, sb, cx, a, nl)
    sfb := field_index_base(base, cx)
    fent := deref(svec_at(SlotEntry, cx.slots, sfb.ent_idx))
    emit_agg_base_addr(fent, sb)
    push_str(sb, "  movq %rax, %rbx\n")
    if sbf.off != 0 {
      push_str(sb, "  addq $")
      push_int(sb, sbf.off)
      push_str(sb, ", %rbx\n")
    }
    push_str(sb, "  popq %rax\n")
    if cx.vchk {
      push_str(sb, "  cmpq $")
      push_int(sb, sbf.len)
      push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
    }
    push_str(sb, "  addq %rax, %rbx\n  movq %rbx, %rax\n")
    return
  }
  ## P1-CLAYOUT S3(d) — BYTE ARRAY FIELD of a byte-tier ARRAY ELEMENT (`xs[i].data[j]`, any field
  ## depth). Same shape as the `sbf` arm above, with the aggregate base coming from the element address
  ## instead of a frame slot: `emit_index_addr` on the ELEMENT (Types §6.4 byte stride), plus the
  ## field's §6.1 offset, plus the raw byte index (stride 1). Placed before the `fib.is_fld` path
  ## because that path composes `field_word_offset * 8`, which counts a `[u8; 8]` field as EIGHT WORDS
  ## and would address `xs[i].data[1]` at byte 8.
  s3dbi := std_idx_path(base, cx.slots, cx.decls, cx.src, a)
  if s3dbi.ok and std_idx_byte_field_eek(base, cx.slots, cx.decls, cx.src, a) != 0 {
    s3dblen := i64(parse_arr_len(cx.src, s3dbi.ts, s3dbi.tl))
    emit_gas(idx, sb, cx, a, nl)                                  ## the raw byte index → stack
    emit_index_addr(s3dbi.arr, s3dbi.idx, sb, cx, a, nl)          ## the ELEMENT's base address → %rax
    push_str(sb, "  movq %rax, %rbx\n")
    if s3dbi.bo != 0 {
      push_str(sb, "  addq $")
      push_int(sb, s3dbi.bo)
      push_str(sb, ", %rbx\n")
    }
    push_str(sb, "  popq %rax\n")
    if cx.vchk and s3dblen > 0 {
      push_str(sb, "  cmpq $")
      push_int(sb, s3dblen)
      push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
    }
    push_str(sb, "  addq %rax, %rbx\n  movq %rbx, %rax\n")
    return
  }
  ## NESTED PLACE `v.buf[i]` — the index base is a struct ARRAY FIELD. Element-0 of the field is
  ## the struct's word-0 address MINUS the field's cumulative word offset; the field's elements
  ## are word-sized (stride 1). Handled before the plain-`Var`-array path.
  fib := field_index_base(base, cx)
  if fib.is_fld {
    ## lower the index FIRST (its lowering may clobber %rbx), leaving it on the stack.
    emit_gas(idx, sb, cx, a, nl)
    ## struct word-0 address → %rbx. A pointer-derived root (`deref(p).field[i]`) keeps the
    ## pointee address in an `ek == 7` scalar slot, so load that address directly; ordinary
    ## locals/by-ref aggregate params keep the existing aggregate-base helper.
    fent := deref(svec_at(SlotEntry, cx.slots, fib.ent_idx))   ## bind a LOCAL so the by-ref param gets its address
    if fent.ek == 7 {
      push_str(sb, "  movq -")
      push_int(sb, i64((fent.off + 1) * 8))
      push_str(sb, "(%rbp), %rax\n")
    } else {
      emit_agg_base_addr(fent, sb)
    }
    ## struct word-0 address → %rax, then advance to the array field's word 0.
    push_str(sb, "  movq %rax, %rbx\n")
    if fib.foff != 0 {
      push_str(sb, "  addq $")
      push_int(sb, fib.foff * 8)
      push_str(sb, ", %rbx\n")
    }
    ## index*(stride*8) → %rax, then element address = field-word-0 - index*stride*8.
    push_str(sb, "  popq %rax\n")
    ## CHECKED BOUNDS (I11 §358) for an ARRAY FIELD of a struct (`s.xs[i]`, xs : [T; N]): trap an
    ## out-of-range index (the raw index in %rax) against the field's static length N. Was missing →
    ## `s.xs[i]` read/wrote out of bounds silently. `flen == 0` (not an array field / unknown) → skip.
    if cx.vchk and fib.flen > 0 {
      push_str(sb, "  cmpq $")
      push_int(sb, fib.flen)
      push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
    }
    ## ARRAY-FIELD element STRIDE (words): a `[T; N]` field's elements are `field_words(T)` words each —
    ## 1 for a scalar/word element (byte-identical to the old hardcoded stride 1), `struct_words(T)` for a
    ## STRUCT element (so `s.cells[i]` with `cells : [Cell; N]`, `Cell` > 1 word, advances by the FULL
    ## element width, not one word — the old `imulq $8` mis-addressed every element past the first). Recover
    ## T from the field's declared `[T; N]` span (the base struct's element-type slot + the field name),
    ## then size it via `field_words(T, 1)`. A non-array / unresolvable span → stride 1 (unchanged).
    mut estr := 1
    fibfp := field_place_parts(base)
    fibfts := field_type_span(cx.decls, cx.src, fent.sns, fent.snl, fibfp.fs, fibfp.fl, a)
    fibaes := array_elem_span(cx.src, fibfts.s, fibfts.n)
    if fibaes.n != 0 { estr = i64(field_words(cx.decls, cx.src, fibaes.s, fibaes.n, 1, a)) }
    push_str(sb, "  imulq $")
    push_int(sb, estr * 8)
    push_str(sb, ", %rax\n  addq %rax, %rbx\n  movq %rbx, %rax\n")
    return
  }
  ## NESTED mixed-kind tuple element access `t.N.M` — an Index whose base is itself an Index into a
  ## MIXED tuple (the inner var carries `tcomps`). A VALUE READ (`... = t.N.M`) is handled in `emit_gas`'s
  ## `Index` arm (component N's word-0 address via this fn's `tcomp` branch, then `+M*8`) and never reaches
  ## here. This guard remains for any OTHER path (a WRITE `t.N.M = v` / address-of), which is not yet
  ## modeled: the uniform `index * stride` math below would use the tuple's FIRST-component stride and
  ## silently mis-address the wider component's words (`(40, (1,1))`'s `t.1.0`/`t.1.1` → 81 not 42), so
  ## fail LOUD instead. A UNIFORM array-of-arrays base has no `tcomps` → unaffected; a single-level `t.N`
  ## has a Var base; `t.N.field` goes through the Field path (idx_field_index).
  match deref(base) {
    Expr::Index(ib, ii) => {
      ibv := var_name_span(ib)
      if ibv.n != 0 { if var_has_tcomps(cx, ibv.s, ibv.n) { panic("selfhost: nested mixed-kind tuple element access (t.N.M) not yet supported (pass the component through a named local)") } }
    }
    _ => {}
  }
  ## SOUNDNESS (correct-or-trap, I11 / Types §9.4): an `Index` whose base is a struct ARRAY FIELD
  ## (`something.cells[i]`) is composed ONLY by the `fib.is_fld` path above, and only when that field's
  ## root is a plain `Var` (a local or a by-ref struct param). A `Field` base that fell THROUGH the
  ## `fib.is_fld` branch therefore has a NON-`Var` root — a `deref(p).cells[i]` pointer compound, or a
  ## deeper `a.b.cells[i]` nesting — for which `index_base_entry` resolves to slot 0 and the generic
  ## Var-array path below would read a WRONG address (a silent-0, now that a `[Struct; N]` field
  ## constructs). Fail LOUD rather than silently miscompile; bind the inner struct to a local first.
  fpg := field_place_parts(base)
  if unchecked bitcast(usize, fpg.base) != 0 {
    panic("selfhost: indexing a struct array FIELD through a non-local root (`deref(p).cells[i]` / `a.b.cells[i]`) is not yet supported — the element-address math only composes a `Var`-rooted `s.cells[i]`; bind the inner struct to a local first")
  }
  bslot := index_base_entry(base, cx.slots, cx.src)
  ent := deref(svec_at(SlotEntry, cx.slots, bslot))
  boff := i64(ent.off)
  ## STANDARD BYTE TUPLE COMPONENT — the tuple index selects a component whose address is computed
  ## from the declared standard byte layout. Scalar components use the same address and the ordinary
  ## Index load; byte-array components become the base of the nested `t.N[i]` branch above.
  if ent.ek == 5 and ent.eek == 12 {
    cidx := num_lit_value(idx)
    cbo := tuple_component_offset(base, usize(cidx), cx)
    if cbo < 0 { panic("selfhost: standard-layout byte tuple component has no byte offset") }
    push_str(sb, "  leaq -")
    push_int(sb, i64((ent.off + 1) * 8) - cbo)
    push_str(sb, "(%rbp), %rax\n")
    return
  }
  ent_slice_param_elem := slice_param_elem_span(cx.src, ent.ns, ent.nl)
  ## BYTE-PACKED ARRAY / TYPED BYTE-SLICE. Fixed local arrays start at the first filler word
  ## (`-(off*8)(%rbp)`); a range slice stores that same data pointer directly in its `off` slot.
  ## In both cases the element offset is a BYTE count, not `idx * 8`. A byte store/read is selected
  ## by the caller after this address primitive returns. A concrete fixed-array parameter carries its
  ## static element count in `sns` and its data pointer in the by-ref slot; a slice parameter carries
  ## runtime length in `snl`.
  if ent.ek == 5 and is_byte_array_eek(ent.eek) {
    emit_gas(idx, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n")
    if cx.vchk {
      if ent.is_ref {
        if ent.snl == 1 {
          push_str(sb, "  cmpq -")
          push_int(sb, i64(ent.off * 8))
          push_str(sb, "(%rbp), %rax\n  jb 1f\n  ud2\n1:\n")
        } else {
          push_str(sb, "  cmpq $")
          push_int(sb, i64(ent.sns))
          push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
        }
      } else {
        push_str(sb, "  cmpq $")
        push_int(sb, i64(ent.snl))
        push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
      }
    }
    if ent.is_ref { push_str(sb, "  movq -"); push_int(sb, i64((ent.off + 1) * 8)) } else {
      push_str(sb, "  leaq -"); push_int(sb, i64(ent.off * 8))
    }
    push_str(sb, "(%rbp), %rbx\n  addq %rax, %rbx\n  movq %rbx, %rax\n")
    return
  }
  ## MIXED-KIND tuple LOCAL: element N lives at a CONSTANT cumulative word offset `tc.off` (its components
  ## have differing widths, so `index*stride` is wrong). Emit element-0's address, then subtract the
  ## constant offset — no runtime index math. Uniform tuples/arrays have no `tcomps` entry (`estride == 0`)
  ## → the uniform `index*stride` path below (unchanged, fixpoint-neutral).
  tc := tcomp_find(cx, ent.off, usize(num_lit_value(idx)))
  if tc.estride != 0 {
    if ent.is_ref { push_str(sb, "  movq -") } else { push_str(sb, "  leaq -") }
    push_int(sb, (boff + 1) * 8)
    push_str(sb, "(%rbp), %rbx\n")
    if tc.off != 0 { push_str(sb, "  addq $"); push_int(sb, i64(tc.off) * 8); push_str(sb, ", %rbx\n") }
    push_str(sb, "  movq %rbx, %rax\n")
    return
  }
  ## SOUNDNESS (correct-or-trap, Types §6.4 / §4.5 OP-5): the index BASE names a PLAIN SCALAR slot
  ## (`ek == 0` — one word: an integer, a float, or a raw `ptr(T)`), which is NOT an indexable place.
  ## The uniform path below would `leaq` that SLOT's frame address and treat the surrounding frame as
  ## an array — `p := s.ptr; p[0]` read the pointer WORD itself (0/garbage), `pa := ptr(xs); pa[i]`
  ## read frame slot `pa+i` (xs's own words), `psl := ptr(sl); psl[0]` likewise: SILENT MISCOMPILES on
  ## every spelling. Types §6.4 is explicit — "a raw pointer carries no arithmetic indexing of its own,
  ## so `[i]` on a pointer always means dereference-then-index" — and §4.5's auto-deref resolves the
  ## index operator on the POINTEE, so `p[i]` is well-formed only for an INDEXABLE pointee (an array /
  ## slice / a type with `index`). A scalar pointee (`ptr(u8)`, `ptr(u64)`) has none, and the pointee-
  ## array/slice forms are not composed here (the slot carries no pointee layout), so fail LOUD.
  ## The gate is a NAME-MATCHED `Var` base with `ek == 0`; every indexable slot kind (array/slice `ek
  ## 5`, `Slice` struct `ek 2`, str `ek 4`, tuple `ek 6`) and every non-`Var` base is untouched, and
  ## neither `src/` nor `lib/` indexes a scalar → fixpoint-neutral. EXCEPTION: an explicitly
  ## UNINITIALIZED scalar-element array (`mut xs : [u64; 2]`) is bound by `bind_slot_typed` — `ek == 0`
  ## with the DECLARED `[T; N]` span in `sns`/`snl` — and its uniform stride-1 element math below is
  ## correct, so an `[…]`-shaped slot span is exempt (`array_elem_span`).
  isbv := var_name_span(base)
  if isbv.n != 0 and ent.ek == 0 and streq(cx.src, ent.ns, ent.nl, isbv.s, isbv.n) {
    if array_elem_span(cx.src, ent.sns, ent.snl).n == 0 {
      panic("selfhost: indexing a SCALAR local/param (`x[i]` where `x` is one word — an integer, a float, or a raw `ptr(T)`) is not a place: Types §6.4 gives a raw pointer no indexing of its own, so `p[i]` means `deref(p)[i]` and needs an INDEXABLE pointee. Read a single element with `deref(p)`, or make a view — `Slice(T)(ptr = p, len = n)` / `bytes(s)` for a str — and index that")
    }
  }
  ## index value → %rax (lowered FIRST — its own lowering may clobber %rbx, so compute the
  ## base address afterward), scaled to a byte offset index*stride*8.
  emit_gas(idx, sb, cx, a, nl)
  push_str(sb, "  popq %rax\n")
  ## CHECKED BOUNDS (I11 / Types §5, §358): a STATIC-length frame array `[T; N]` is compiler-emitted
  ## `at` — trap when the index is out of range. `N` is `ent.snl` for a SCALAR/FLOAT-element array
  ## (`eek` 0/9); an aggregate-element array keeps a type span there (no static count → deferred), and
  ## a by-ref array PARAM (`is_ref`) has no static length here. `jb` (unsigned) skips on `idx < N`, so
  ## a negative i64 index (huge unsigned) also traps. Dropped in an `unchecked` scope (CG-7).
  if cx.vchk and ent.ek == 5 and ent.is_ref == false and (ent.eek == 0 or ent.eek == 9) {
    push_str(sb, "  cmpq $")
    push_int(sb, i64(ent.snl))
    push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
  }
  ## CHECKED BOUNDS for a LITERAL-bound AGGREGATE-element frame array (`[P; N]`/`[E; N]`/`[str; N]`, eek
  ## 2/3/4): `ent.snl` holds the element TYPE span, not the count, so the element COUNT is recovered from
  ## the reserved filler slots (`agg_arr_fill_count` = nel*stride) divided by the element stride. Same
  ## `jb`/`ud2` trap as the scalar case, on the raw index in %rax before scaling. `aggn > 0` guards the
  ## recovery (a 0 would emit `cmpq $0` → an always-trap); a by-ref array PARAM (`is_ref`) has no fills.
  if cx.vchk and ent.ek == 5 and ent.is_ref == false and (ent.eek == 2 or ent.eek == 3 or ent.eek == 4 or ent.eek == 7) {
    aggn := agg_arr_fill_count(cx.slots, bslot) / ent.estride
    if aggn > 0 {
      push_str(sb, "  cmpq $")
      push_int(sb, i64(aggn))
      push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
    }
  }
  ## CHECKED BOUNDS for a typed ARRAY-SLICE local (`ek == 5`, `is_ref`, `snl == 1`): its length is the
  ## RUNTIME len word (word 1, at frame `-(off+2)*8(%rbp)`), not a static count — so compare the index
  ## (in %rax) against that memory operand directly (no register clobbered). `jb` skips on `idx < len`;
  ## a negative i64 index (huge unsigned) also traps. Dropped in an `unchecked` scope (CG-7). A struct/
  ## enum-element slice (`snl != 1`, a type span) is not covered here (parallels the array case's eek gate).
  ## `eek == 0` (SCALAR element) gates this: a runtime-len slice is over scalar elements. Without it, a
  ## struct/enum array PARAM whose element type NAME is 1 character (e.g. `[P; 2]`, snl = len("P") = 1)
  ## collided with the `snl == 1` slice marker → this read the 2nd frame slot as a bogus "length" and
  ## mis-trapped even an in-bounds index. (A struct/enum-element slice has snl = a type span, not 1.)
  if cx.vchk and ent.ek == 5 and ent.is_ref and ent.snl == 1 and ent.eek == 0 and ent.sns == 0 {
    push_str(sb, "  cmpq -")
    push_int(sb, i64(ent.off * 8))
    push_str(sb, "(%rbp), %rax\n  jb 1f\n  ud2\n1:\n")
  }
  ## CHECKED BOUNDS for a SLICE PARAM (`sns == 1`): the runtime len is word 1 of the {ptr,len} block the
  ## slot points to — load the block address, compare the index (in %rax) against `8(block)`. `%rcx` is a
  ## scratch here (the element math below reloads its own regs). `jb` skips on `idx < len`.
  if cx.vchk and ent.ek == 5 and ent.is_ref and ent.snl == 1 and ent.eek == 0 and ent.sns == 1 {
    push_str(sb, "  movq -")
    push_int(sb, i64((ent.off + 1) * 8))
    push_str(sb, "(%rbp), %rcx\n  cmpq 8(%rcx), %rax\n  jb 1f\n  ud2\n1:\n")
  }
  ## CHECKED BOUNDS for a STRUCT/ENUM-element SLICE PARAM. Its slot keeps the element type span for
  ## `s[i].field`, so it cannot use the scalar slice-param `sns == 1` marker; recover param-ness from
  ## the declared `s : Slice(T)` type and read len from the caller's {ptr,len} block.
  if cx.vchk and ent.ek == 5 and ent.is_ref and (ent.eek == 2 or ent.eek == 3) and ent_slice_param_elem.n != 0 {
    push_str(sb, "  movq -")
    push_int(sb, i64((ent.off + 1) * 8))
    push_str(sb, "(%rbp), %rcx\n  cmpq 8(%rcx), %rax\n  jb 1f\n  ud2\n1:\n")
  }
  ## CHECKED BOUNDS for a BY-REF SCALAR FIXED-ARRAY PARAM (`a : [T; N]`, ek 5, is_ref, scalar element
  ## eek 0, `snl == 0`): its static length N is in `sns` (bind_param) — trap an out-of-range index like a
  ## frame array. Was previously unchecked (a by-ref param has no static count in the slot) → an OOB
  ## index crashed instead of trapping cleanly. `sns > 0` gates it (0 = no length recorded); `snl == 0`
  ## keeps it distinct from a runtime-len slice (`snl == 1`). Dropped in an `unchecked` scope.
  if cx.vchk and ent.ek == 5 and ent.is_ref and ent.eek == 0 and ent.snl == 0 and ent.sns > 0 {
    push_str(sb, "  cmpq $")
    push_int(sb, i64(ent.sns))
    push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
  }
  ## CHECKED BOUNDS for a plain-struct element of a concrete fixed-array PARAM. The parser keeps the
  ## aggregate element type in `ent.sns`/`ent.snl`, while the array's static N lives in Param.pps;
  ## recover that N before the shared address math. Tuple/generic/slice and non-scalar-field structs
  ## remain on their existing loud/unsupported paths.
  if cx.vchk and ent.ek == 5 and ent.is_ref and ent.eek == 2 and fixed_array_param_len(ent.ns, ent.nl, EMIT_PARAMS, cx.src) > 0 {
    pn := fixed_array_param_len(ent.ns, ent.nl, EMIT_PARAMS, cx.src)
    if index_plain_scalar_struct(cx.src, cx.decls, ent.sns, ent.snl, a) {
      push_str(sb, "  cmpq $")
      push_int(sb, i64(pn))
      push_str(sb, ", %rax\n  jb 1f\n  ud2\n1:\n")
    }
  }
  ## P1-CLAYOUT S3(d) — THE element stride, in BYTES, from the one shared query. Identical to the
  ## historical `ent.estride * 8` for every element kind that existed before this slice (a
  ## word-granular element's §6.4 stride IS `struct_words * 8`); different only for a BYTE-tier struct
  ## element, whose §6.1 size need not be a multiple of 8.
  push_str(sb, "  imulq $")
  push_int(sb, slot_elem_stride_bytes(ent, cx.decls, cx.src, a))
  push_str(sb, ", %rax\n")
  ## element 0's address → %rbx. For a frame-LOCAL array its slot IS element 0, so `leaq` its
  ## frame address; for a BY-REF array PARAM the slot holds a POINTER to the caller's element 0,
  ## so `movq` LOADS that pointer (neither touches %rax). (AGGREGATE-PARAM tier.)
  if ent.is_ref {
    push_str(sb, "  movq -")
  } else {
    push_str(sb, "  leaq -")
  }
  push_int(sb, (boff + 1) * 8)
  push_str(sb, "(%rbp), %rbx\n")
  ## SCALAR SLICE PARAM (`ek 5`, `is_ref`, `sns == 1`): the slot holds a POINTER to the caller's
  ## `{ptr,len}` block, so %rbx is that block address — deref ONCE MORE to the DATA pointer (block word 0)
  ## before adding the element offset. A scalar slice VIEW LOCAL has `sns == 0` and `snl == 1`, so its
  ## slot already contains the data pointer. Keep the aggregate-element source-scan fallback below its
  ## existing eek gate; it is deliberately unchanged for aggregate and variadic forms.
  if ent.ek == 5 and ent.is_ref and (ent.sns == 1 or ((ent.eek == 2 or ent.eek == 3) and ent_slice_param_elem.n != 0)) { push_str(sb, "  movq (%rbx), %rbx\n") }
  ## element address = element-0 address - index*stride*8 (the frame grows down) → %rax
  push_str(sb, "  addq %rax, %rbx\n  movq %rbx, %rax\n")
}
