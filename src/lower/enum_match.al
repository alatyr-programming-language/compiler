## selfhost::lower::enum_match — ENUM SCRUTINEE RESOLUTION and `match` LOWERING: how a `match` finds
## the enum it is dispatching on (a local, a by-reference param, a module global, a struct field, an
## array element, an array-element field), the `@repr` tag load/store, `_`-arm expansion over the
## variant set, and the jump table itself.
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. Every UNQUALIFIED name below that this file does not
## import — `streq`, `decl_at`, `entry_of`, `slot_of`, `svec_at`, `emit_expr`, and the TYPES
## `SlotEntry` and `ScrutInfo` — binds `lower.al`'s OWN declaration through the ancestor chain
## (Modules §3 for values, TYPE-ANCESTOR for types).
##
## Types: `DInfo` and `FEScrut` move HERE with the band because only the band names them.
## `ScrutInfo` DELIBERATELY stays declared in `src/lower.al` — `emit_gas` constructs one at
## `src/lower.al:16615` and §3 is one-way, so an ancestor cannot name a descendant's type. That is
## the same rule that keeps a band's shared globals in the parent: whatever the PARENT still names
## stays in the parent, whatever only the BAND names travels with the band.
##
## The twelve externally-called entry points are re-imported into `lower.al` by BARE NAME, which
## leaves every call site unchanged and keeps the boundary `@inline`-transparent.
##
## NOTE the import ORDER: a BARE module alias (`strbuf := rt`) followed by a listed projection is a
## parse error in the self-host parser unless a QUALIFIED alias (`x := m::y`) separates them.
strbuf := rt
arm_p := ast::arm_p
fld_p := ast::fld_p
(Arm, Decl, Expr, Stmt, bnd_ns, bnd_nl, bnd_next) := ast
(push_str, push_int) := strbuf
(LCtx, num_lit_value, var_name_span) := lower_ctx
(base_type_name, enum_decl_of, enum_inst_words, enum_repr_ty, field_word_offset, is_niche_folded, repr_tag_code, struct_decl_of, struct_words, variant_index, variant_payload_type) := lower_layout
## SIBLING child, reached by an EXPLICIT qualified path (Modules §4). It was a bare name until the
## place band moved to `src/lower/place.al`; a bare child-to-child call would bind through the
## unique-declaration leniency, which `scripts/callee_module_check.sh` cannot see.
(emit_index_addr) := lower::place

## Whether `deref(p)` is a `Var`, and (if so) its name span — a function-body `match` over a
## pointer param (the lowerable shape, mirroring `enum_lit_info`/`struct_lit_info`), so
## `scrut_enum_info` can resolve a `match deref(p)` scrutinee without a nested `match`.
DInfo := struct { is_v : bool, s : usize, n : usize }
pub deref_var_info := fn(p : ptr(Expr)) -> DInfo {
  ## BRACED arms (a STATEMENT match) whose tail expression IS the returned struct — the value
  ## flows through the `cx.tail` ExprStmt path (`emit_return_value`), like `enum_lit_info` /
  ## `struct_lit_info`. (A bare `=> DInfo(...)` EXPRESSION-match over this ENUM scrutinee is not
  ## delivered — only the integer-scrutinee bare form is; see `emit_return_value`.)
  match deref(p) {
    Expr::Var(s, n) => { DInfo(is_v = true, s = s, n = n) }
    _ => { DInfo(is_v = false, s = 0, n = 0) }
  }
}

pub scrut_enum_info := fn(scrut : ptr(Expr), cx : ptr(LCtx)) -> ScrutInfo {
  match deref(scrut) {
    Expr::Var(s, n) => {
      ent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, s, n)))
      if ent.ek == 3 { return ScrutInfo(is_e = true, base = ent.off, es = ent.sns, el = ent.snl, is_ref = ent.is_ref, tmod_s = ent.tmod_s, tmod_l = ent.tmod_l) }
      return ScrutInfo(is_e = false, base = 0, es = 0, el = 0, is_ref = false, tmod_s = 0, tmod_l = 0)
    }
    ## `match deref(p)` over a `ptr(Enum)` local/param (`ek == 6`, the arena-AST shape): the
    ## scrutinee is the pointee enum. `base` is `p`'s slot (holding the pointer) and `is_ref`
    ## true, so `materialize_ref_enum` loads the pointer + copies the pointee's words exactly as
    ## for a by-ref enum parameter; `es`/`el` is the pointee enum's type span. `deref_var_info`
    ## extracts the inner `Var` spans via a function-body `match` (the lowerable shape — a
    ## `match` nested inside this arm is not lowered by the seed compiler yet).
    Expr::Deref(p) => {
      dv := deref_var_info(p)
      if dv.is_v {
        ent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, dv.s, dv.n)))
        if ent.ek == 6 { return ScrutInfo(is_e = true, base = ent.off, es = ent.sns, el = ent.snl, is_ref = true, tmod_s = ent.tmod_s, tmod_l = ent.tmod_l) }
        return ScrutInfo(is_e = false, base = 0, es = 0, el = 0, is_ref = false, tmod_s = 0, tmod_l = 0)
      }
      return ScrutInfo(is_e = false, base = 0, es = 0, el = 0, is_ref = false, tmod_s = 0, tmod_l = 0)
    }
    _ => { return ScrutInfo(is_e = false, base = 0, es = 0, el = 0, is_ref = false, tmod_s = 0, tmod_l = 0) }
  }
}

## Materialize a **by-reference** enum scrutinee (a by-ref enum parameter or a `deref(ptr(E))`,
## `is_ref`) into the scratch temp `cx.tslot` so the inline `emit_enum_match` path can dispatch
## on it. `base` is the slot holding the POINTER to the caller's enum word 0; copy the
## discriminant (word 0, `(%rax)`) and **every** payload word — word `i` at `-(i*8)(%rax)` (the
## down-growing aggregate layout) → scratch slot `tslot+i` — so a multi-word payload enum
## (`Bin(op, ptr, ptr)`) materializes whole (the scratch is sized to `1 + max enum arity`).
## Returns a `ScrutInfo` over the scratch (`is_ref = false`), so the caller proceeds exactly as
## for an enum local.
pub materialize_ref_enum := fn(base : usize, es : usize, el : usize, in out sb : strbuf::StrBuf, cx : ptr(LCtx)) -> ScrutInfo {
  ## §8 `Option(ptr(T))` is a one-word niche value even when it arrives through the ordinary
  ## by-reference aggregate-parameter ABI. The raw generic `Option(T)` span would make the old loop
  ## copy a discriminant plus a second word from a one-word caller value. Materialize only word 0;
  ## the folded matcher then tests that word for null and aliases a `Some` payload to the same slot.
  if is_niche_folded(cx.src, es, el) {
    tbase := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
    push_str(sb, "  movq -")
    push_int(sb, i64((base + 1) * 8))
    push_str(sb, "(%rbp), %rax\n  movq (%rax), %rcx\n  movq %rcx, -")
    push_int(sb, i64((tbase + 1) * 8))
    push_str(sb, "(%rbp)\n")
    return ScrutInfo(is_e = true, base = tbase, es = es, el = el, is_ref = false, tmod_s = 0, tmod_l = 0)
  }
  nw := 1 + enum_inst_words(cx.decls, cx.src, es, el, deref(cx.mar))
  ## scratch level for THIS match's nesting depth (see LCtx.mdepth) — a nested match uses a higher level.
  tbase := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
  push_str(sb, "  movq -")
  push_int(sb, i64((base + 1) * 8))
  push_str(sb, "(%rbp), %rax\n")
  for i in 0..nw {
    push_str(sb, "  movq ")
    push_int(sb, i64(i * 8))
    push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
    push_int(sb, i64((tbase - i + 1) * 8))
    push_str(sb, "(%rbp)\n")
  }
  ScrutInfo(is_e = true, base = tbase, es = es, el = el, is_ref = false, tmod_s = 0, tmod_l = 0)
}
## If `scrut` is a mutable ENUM GLOBAL (`match STATE`), MATERIALIZE its `.data` words (ascending
## `[disc, payload…]` at `LABEL + i*8`) into this match's scratch temp and return a ScrutInfo pointing
## there — so the inline `emit_enum_match` dispatches on it exactly like a local. Emits nothing and
## returns `is_e = false` when `scrut` is not a mutable enum global. Enables a direct `match <global>`
## (else the scrutinee had no frame slot and the disc resolved to garbage).
pub try_global_enum_scrut := fn(scrut : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx)) -> ScrutInfo {
  z := ScrutInfo(is_e = false, base = 0, es = 0, el = 0, is_ref = false, tmod_s = 0, tmod_l = 0)
  gvn := var_name_span(scrut)
  if gvn.n == 0 { return z }
  mgv := mut_global_value(cx.decls, cx.src, gvn.s, gvn.n)
  if unchecked bitcast(usize, mgv) == 0 { return z }
  gei := enum_lit_info(mgv)
  if gei.is_e == false { return z }
  nw := 1 + enum_inst_words(cx.decls, cx.src, gei.es, gei.el, deref(cx.mar))
  tbase := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
  push_str(sb, "  leaq ")
  emit_global_label(sb, cx.decls, cx.src, gvn.s, gvn.n)
  push_str(sb, "(%rip), %rax\n")
  for i in 0..nw {
    push_str(sb, "  movq ")
    push_int(sb, i64(i * 8))
    push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
    push_int(sb, i64((tbase - i + 1) * 8))
    push_str(sb, "(%rbp)\n")
  }
  ScrutInfo(is_e = true, base = tbase, es = gei.es, el = gei.el, is_ref = false, tmod_s = 0, tmod_l = 0)
}

## If `scrut` is `s.c` where `c` is an ENUM FIELD of a struct local/param `s`, MATERIALIZE the field's
## enum words (disc + payload, `1 + max_arity`) from the struct into this match's scratch temp and
## return a ScrutInfo over it — so `match s.c` dispatches correctly. Without this a struct-enum-field
## scrutinee fell to the integer path and read a garbage discriminant (silent wrong-arm). Emits nothing
## + returns `is_e = false` when `scrut` isn't an enum field with a plain-Var base. `a` = the AST arena.
## The base-Var + field spans of a `Field(Var(s), f)` scrutinee (`ok` false otherwise). A
## single-expression match arm (no mid-arm early return — the lean-lower gotcha) so the destructure
## lowers; the fallible logic lives in `try_field_enum_scrut`'s BODY where early returns are safe.
FEScrut := struct { ok : bool, bs : usize, bn : usize, fs : usize, fl : usize }
field_var_scrut := fn(scrut : ptr(Expr)) -> FEScrut {
  mut r := FEScrut(ok = false, bs = 0, bn = 0, fs = 0, fl = 0)
  match deref(scrut) {
    Expr::Field(base, fs, fl) => {
      bv := var_name_span(base)
      if bv.n != 0 { r = FEScrut(ok = true, bs = bv.s, bn = bv.n, fs = fs, fl = fl) }
    }
    _ => {}
  }
  r
}
pub try_field_enum_scrut := fn(scrut : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx)) -> ScrutInfo {
  z := ScrutInfo(is_e = false, base = 0, es = 0, el = 0, is_ref = false, tmod_s = 0, tmod_l = 0)
  ## `arena_of(cx)` (a by-value return), NOT `deref(cx.mar)` bound to a local — the latter derefs a
  ## FIELD and does NOT lower as a struct copy (the documented lean-runtime landmine), yielding a
  ## broken arena that crashes `field_type_span`.
  a := arena_of(cx)
  ## `match GLOBAL.f1.f2….c` — an enum FIELD at ANY depth of a mutable-global struct chain (the base has
  ## no frame slot): resolve the cumulative `.data` offset with `global_place`, materialize the field's
  ## enum `[disc, payload…]` words ASCENDING (`LABEL + (off+j)*8`) into this match's scratch. Subsumes
  ## the old 1-level `match STATE.c`. The `if`s + return are at fn-body level (safe under the seed).
  gp := global_place(scrut, cx, a)
  if gp.found and gp.tl != 0 and enum_decl_of(cx.decls, cx.src, gp.ts, gp.tl) >= 0 {
    gpnw := 1 + enum_inst_words(cx.decls, cx.src, gp.ts, gp.tl, a)
    gptb := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
    push_str(sb, "  leaq ")
    emit_global_label(sb, cx.decls, cx.src, gp.gs, gp.gn)
    push_str(sb, "(%rip), %rax\n")
    mut gpj := 0
    while gpj < gpnw {
      push_str(sb, "  movq ")
      push_int(sb, (gp.off + i64(gpj)) * 8)
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((gptb - gpj + 1) * 8))
      push_str(sb, "(%rbp)\n")
      gpj += 1
    }
    return ScrutInfo(is_e = true, base = gptb, es = gp.ts, el = gp.tl, is_ref = false, tmod_s = 0, tmod_l = 0)
  }
  ## a struct-field enum scrutinee of a LOCAL / by-ref param struct (its base has a frame slot).
  fe := field_var_scrut(scrut)
  if fe.ok == false { return z }
  bent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, fe.bs, fe.bn)))
  ## the base struct's type span (a plain-Var struct local/param records it in sns/snl).
  if bent.snl == 0 { return z }
  ft := field_type_span(cx.decls, cx.src, bent.sns, bent.snl, fe.fs, fe.fl, a)
  if ft.n == 0 { return z }
  ## §8 `@niche`: a NICHE-FOLDED `Option(ptr(T))` FIELD is ONE pointer word (no discriminant) that
  ## `enum_decl_of` can't resolve (the parenthesized generic instance), so the ordinary enum-field
  ## path below rejects it. Materialize that single field word (at struct word `fwo`) into the scratch
  ## WORD-0 slot (`-((ftb+1)*8)`) — exactly where the folded dispatch reads `%r12`
  ## (`emit_repr_tag_load`, code 0) and where the `Some(p)` payload binds (`off = base`). Return the
  ## full `Option(ptr(T))` span as `es`/`el` so `is_niche_folded` fires in BOTH match paths. Gated by
  ## `is_niche_folded` → every non-folded enum field is byte-identical (the corpus has no such field).
  if is_niche_folded(cx.src, ft.s, ft.n) {
    ffwo := field_word_offset(cx.decls, cx.src, bent.sns, bent.snl, fe.fs, fe.fl, a)
    if ffwo < 0 { return z }
    ftb := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
    emit_agg_base_addr(bent, sb)                     ## struct word-0 address → %rax
    push_str(sb, "  movq ")
    push_int(sb, ffwo * 8)
    push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
    push_int(sb, i64((ftb + 1) * 8))
    push_str(sb, "(%rbp)\n")
    return ScrutInfo(is_e = true, base = ftb, es = ft.s, el = ft.n, is_ref = false, tmod_s = 0, tmod_l = 0)
  }
  if enum_decl_of(cx.decls, cx.src, ft.s, ft.n) < 0 { return z }
  fwo := field_word_offset(cx.decls, cx.src, bent.sns, bent.snl, fe.fs, fe.fl, a)
  if fwo < 0 { return z }
  nw := 1 + enum_inst_words(cx.decls, cx.src, ft.s, ft.n, a)
  tbase := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
  emit_agg_base_addr(bent, sb)                       ## struct word-0 address → %rax
  mut j := 0
  while j < nw {
    ## enum field word `j` sits at struct word `fwo + j` (down-growing: `-((fwo+j)*8)(%rax)`);
    ## copy it into scratch slot `tbase + 1 + j`.
    push_str(sb, "  movq ")
    push_int(sb, (fwo + i64(j)) * 8)
    push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
    push_int(sb, i64((tbase - j + 1) * 8))
    push_str(sb, "(%rbp)\n")
    j += 1
  }
  ScrutInfo(is_e = true, base = tbase, es = ft.s, el = ft.n, is_ref = false, tmod_s = 0, tmod_l = 0)
}

## If `scrut` is `cs[i]` where `cs` is an ENUM-element array local (ek 5, eek 3), MATERIALIZE element
## `i`'s enum words (disc + payload) into this match's scratch temp and return a ScrutInfo over it —
## so `match cs[i]` dispatches correctly (the array/index dual of `try_field_enum_scrut`). Emits
## nothing + `is_e = false` otherwise. The logic lives INSIDE the `Index` arm with nested `if`s (no
## mid-arm early return, no ptr-in-struct destructure — both lean-lower landmines) and a `mut` result.
pub try_index_enum_scrut := fn(scrut : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), in out nl : usize) -> ScrutInfo {
  mut r := ScrutInfo(is_e = false, base = 0, es = 0, el = 0, is_ref = false, tmod_s = 0, tmod_l = 0)
  a := arena_of(cx)
  match deref(scrut) {
    Expr::Index(base, idx) => {
      bvn := var_name_span(base)
      ## `match GE[i]` over an ENUM-element ARRAY GLOBAL. A module global has NO frame slot, so
      ## `entry_of` below falls back to slot 0 and `emit_index_addr` would address the FRAME — the
      ## scrutinee then dispatched on a garbage discriminant (a SILENT wrong-arm miscompile). Resolve
      ## the element out of `.data` instead: base `LABEL + i*stride*8` (bounds-checked), word j at
      ## `+j*8`, copied into this match's scratch — the `.data` twin of the frame-array path below.
      mut gaen := GAEnum(is_e = false, es = 0, el = 0, stride = 0, nel = 0)
      if bvn.n != 0 { gaen = global_arr_enum(cx.decls, cx.src, global_arr_value(cx.slots, cx.decls, cx.src, bvn.s, bvn.n), a) }
      if gaen.is_e {
        gtb := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
        emit_gas(idx, sb, cx, a, nl)                   ## index → stack
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, bvn.s, bvn.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(gaen.nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  imulq $")
        push_int(sb, i64(gaen.stride * 8))
        push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
        mut gj := 0
        while gj < gaen.stride {
          push_str(sb, "  movq ")
          push_int(sb, i64(gj * 8))
          push_str(sb, "(%r13), %rcx\n  movq %rcx, -")
          push_int(sb, i64((gtb - gj + 1) * 8))
          push_str(sb, "(%rbp)\n")
          gj += 1
        }
        r = ScrutInfo(is_e = true, base = gtb, es = gaen.es, el = gaen.el, is_ref = false, tmod_s = 0, tmod_l = 0)
      }
      if bvn.n != 0 and gaen.is_e == false {
        bent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, bvn.s, bvn.n)))
        ## Resolve the indexed element's ENUM type: a uniform enum-element array (ek 5, eek 3) records it
        ## in `sns/snl`; a MIXED-kind TUPLE component that is an enum records `eek 3` + the enum type span
        ## in its `tcomps` entry (keyed by the base slot's `off`). Either way `emit_index_addr` computes
        ## the element's word-0 address (its `tcomps`/is_ref branches handle a mixed tuple + by-ref param).
        mut isenum := false
        mut ees := 0
        mut eel := 0
        if bent.ek == 5 and bent.eek == 3 and bent.snl != 0 { isenum = true ; ees = bent.sns ; eel = bent.snl }
        if not isenum {
          tc := tcomp_find(cx, bent.off, usize(num_lit_value(idx)))
          if tc.eek == 3 and tc.snl != 0 { isenum = true ; ees = tc.sns ; eel = tc.snl }
        }
        if isenum {
          nw := 1 + enum_inst_words(cx.decls, cx.src, ees, eel, a)
          tbase := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
          emit_index_addr(base, idx, sb, cx, a, nl)     ## element word-0 address → %rax
          mut j := 0
          while j < nw {
            ## element word `j` at `-(j*8)(%rax)` (down-growing) → scratch slot `tbase+1+j`.
            push_str(sb, "  movq ")
            push_int(sb, i64(j * 8))
            push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
            push_int(sb, i64((tbase - j + 1) * 8))
            push_str(sb, "(%rbp)\n")
            j += 1
          }
        r = ScrutInfo(is_e = true, base = tbase, es = ees, el = eel, is_ref = false, tmod_s = 0, tmod_l = 0)
        }
      }
    }
    _ => {}
  }
  r
}

## `match xs[i].c` — an ENUM FIELD of a STRUCT-element array element (`Field(Index(arr, idx), c)`).
## Materialize the field's enum words into the match scratch. `field_base_index` destructures the
## `Index` (a proven ptr-in-FBIx helper — no nested match / ptr-in-struct in this arm), the array's
## element struct type comes from its slot's `sns`/`snl` (eek 2), and `emit_index_addr` gives the
## element base; the enum field sits at `-((fwo+j)*8)(%rax)` (down-growing). 0/0 otherwise.
pub try_arrelem_field_enum_scrut := fn(scrut : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), in out nl : usize) -> ScrutInfo {
  mut r := ScrutInfo(is_e = false, base = 0, es = 0, el = 0, is_ref = false, tmod_s = 0, tmod_l = 0)
  a := arena_of(cx)
  match deref(scrut) {
    Expr::Field(fbase, ffs, ffl) => {
      fbi := field_base_index(fbase)
      if fbi.is_ix {
        aent := deref(svec_at(SlotEntry, cx.slots, index_base_entry(fbi.arr, cx.slots, cx.src)))
        if aent.ek == 5 and aent.eek == 2 and aent.snl != 0 {
          ft := field_type_span(cx.decls, cx.src, aent.sns, aent.snl, ffs, ffl, a)
          if ft.n != 0 and enum_decl_of(cx.decls, cx.src, ft.s, ft.n) >= 0 {
            fwo := field_word_offset(cx.decls, cx.src, aent.sns, aent.snl, ffs, ffl, a)
            if fwo >= 0 {
              nw := 1 + enum_inst_words(cx.decls, cx.src, ft.s, ft.n, a)
              tbase := usize(cx.tslot) + cx.mdepth * cx.swidth + cx.swidth - 1
              emit_index_addr(fbi.arr, fbi.idx, sb, cx, a, nl)   ## element base address → %rax
              mut j := 0
              while j < nw {
                push_str(sb, "  movq ")
                push_int(sb, (fwo + i64(j)) * 8)
                push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
                push_int(sb, i64((tbase - j + 1) * 8))
                push_str(sb, "(%rbp)\n")
                j += 1
              }
              r = ScrutInfo(is_e = true, base = tbase, es = ft.s, el = ft.n, is_ref = false, tmod_s = 0, tmod_l = 0)
            }
          }
        }
      }
    }
    _ => {}
  }
  r
}

## Lower an enum `match` (`match e { V(x) => body ; W => body ; _ => body }`). The scrutinee
## `e` is an enum-typed `Var` local at `si.base` (discriminant word at slot `base`, payload
## words at `base+1`, `base+2`). The discriminant is loaded into %r12 (callee-saved, survives
## the per-arm body emission). FIRST pass: emit the dispatch — a variant-pattern arm compares
## %r12 to the variant's declaration index and `je`s to a fresh body label; a wildcard arm is
## an unconditional jump; with no wildcard, fall through to a default `$0`. SECOND pass: emit
## each arm body under its reserved label. For a variant arm with payload bindings, the
## binding NAME is temporarily aliased to the scrutinee's payload slot (`base+1+i`) by pushing
## a `SlotEntry` onto `cx.slots` before emitting the body and truncating it after — so a `Var`
## reference to the binding inside the body reads the payload word (last-match-wins lookup).
## Set an `Arm`'s `next` link (bind-then-store — an inline `deref(node_ptr(Arm,…)) = Arm(…)` mis-lowers).
pub set_arm_next := fn(mar : ptr(mut rt::Arena), h : ptr(mut Arm), nx : ptr(mut Arm)) {
  old := deref(arm_p(h))
  upd := Arm(wild = old.wild, lit = old.lit, body = old.body, next = nx, vs = old.vs, vl = old.vl, binds_head = old.binds_head, body_stmts = old.body_stmts, hi = old.hi)
  deref(arm_p(h)) = upd
}

## Expand a match's arm list: a COMPTIME-VARIANT-TEMPLATE arm (`wild == 2`, from `comptime for var in
## typeinfo(T).variants { T.(var)(p) => body }`) becomes ONE real arm per variant of the scrutinee's
## enum `es`/`el` (each with that variant's name + the template's bindings/body). Non-template arms are
## copied through. Returns the new head (built in the AST arena `cx.mar`). No template → returns `head`
## unchanged (byte-identical for ordinary matches). Only meaningful in a mono instance (concrete enum).
pub expand_variant_arms := fn(head : ptr(mut Stmt), es : usize, el : usize, cx : ptr(LCtx), a : rt::Arena) -> usize {
  mut has2 := false
  mut sc := head
  while sc != 0 {
    scm := deref(arm_p(sc))
    if scm.wild == 2 or scm.wild == 3 { has2 = true }
    sc = scm.next
  }
  if has2 == false { return head }
  mut nh := 0
  mut nt := 0
  mut arm := head
  while arm != 0 {
    am := deref(arm_p(arm))
    if am.wild == 2 {
      edi := enum_decl_of(cx.decls, cx.src, es, el)
      if edi >= 0 {
        ed := deref(decl_at(Decl, rt::vec_get(deref(cx.decls), usize(edi))))
        mut fv := ed.fields_head
        while fv != 0 {
          fvm := deref(fld_p(fv))
          ai := mk_arm(deref(cx.mar), Arm(wild = 0, lit = 0, body = am.body, next = 0, vs = fvm.ns, vl = fvm.nl, binds_head = am.binds_head, body_stmts = am.body_stmts, hi = 0))
          if nh == 0 { nh = ai } else { set_arm_next(cx.mar, nt, ai) }
          nt = ai
          fv = fvm.next
        }
      }
    } else if am.wild == 3 {
      ## `T.(v)` comptime-variant PATTERN → resolve `v` to the current loop variant (`cf_curvar`,
      ## set by the enclosing comptime-for arm body). A concrete variant arm matching that variant.
      ai := mk_arm(deref(cx.mar), Arm(wild = 0, lit = 0, body = am.body, next = 0, vs = cx.cf_curvar_s, vl = cx.cf_curvar_l, binds_head = am.binds_head, body_stmts = am.body_stmts, hi = 0))
      if nh == 0 { nh = ai } else { set_arm_next(cx.mar, nt, ai) }
      nt = ai
    } else {
      ai := mk_arm(deref(cx.mar), Arm(wild = am.wild, lit = am.lit, body = am.body, next = 0, vs = am.vs, vl = am.vl, binds_head = am.binds_head, body_stmts = am.body_stmts, hi = am.hi))
      if nh == 0 { nh = ai } else { set_arm_next(cx.mar, nt, ai) }
      nt = ai
    }
    arm = am.next
  }
  nh
}

## §8 `@repr(T)` — load an enum's discriminant (tag) from slot `base` into %r12 at T's WIDTH (spec
## Types §8: "the tag is emitted as T's width … each discriminant encoded in T", read sign/zero-extended
## per T). `code` (from `repr_tag_code`) selects the sized load; a word tag (code 0, the whole no-`@repr`
## corpus) keeps the exact former `movq` → BYTE-IDENTICAL, so the change is fixpoint-neutral. The tag
## VALUE stored is the small non-negative variant index (a clean word), so every sized load below reads
## the identical dispatch value; the width honors the lever's C-ABI contract. Flat exclusive `if`s.
pub emit_repr_tag_load := fn(in out sb : strbuf::StrBuf, base : usize, code : usize) {
  off := i64((base + 1) * 8)
  if code == 0 { push_str(sb, "  movq -"); push_int(sb, off); push_str(sb, "(%rbp), %r12\n") }
  if code == 1 { push_str(sb, "  movsbq -"); push_int(sb, off); push_str(sb, "(%rbp), %r12\n") }
  if code == 2 { push_str(sb, "  movzbl -"); push_int(sb, off); push_str(sb, "(%rbp), %r12d\n") }
  if code == 3 { push_str(sb, "  movswq -"); push_int(sb, off); push_str(sb, "(%rbp), %r12\n") }
  if code == 4 { push_str(sb, "  movzwl -"); push_int(sb, off); push_str(sb, "(%rbp), %r12d\n") }
  if code == 5 { push_str(sb, "  movslq -"); push_int(sb, off); push_str(sb, "(%rbp), %r12\n") }
  if code == 6 { push_str(sb, "  movl -"); push_int(sb, off); push_str(sb, "(%rbp), %r12d\n") }
}

## §8 `@repr(T)` — STORE the discriminant (tag) constant `disc` into slot `base` at T's WIDTH: the STORE
## dual of `emit_repr_tag_load`. `code` (from `repr_tag_code`) selects the sized store; a word tag (code
## 0, the whole no-`@repr` corpus) keeps the exact former `movq $disc, %rax` + `movq %rax, -off(%rbp)`
## sequence → BYTE-IDENTICAL, so the change is fixpoint-neutral. A narrow store (`movb`/`movw`/`movl`)
## writes ONLY the tag's low bytes (the immediate straight to memory) — it does NOT clobber the rest of
## the tag word, whereas the over-wide `movq` zeroed the high bytes a C-ABI peer reads. `disc` is the
## small non-negative variant index, so every sized store below encodes the identical value at T's width.
## Slot→byte-offset is `(base + 1) * 8`, the same mapping the load uses. Flat exclusive `if`s.
pub emit_repr_tag_store := fn(in out sb : strbuf::StrBuf, base : i64, disc : i64, code : usize) {
  off := (base + 1) * 8
  if code == 0 { push_str(sb, "  movq $"); push_int(sb, disc); push_str(sb, ", %rax\n  movq %rax, -"); push_int(sb, off); push_str(sb, "(%rbp)\n") }
  if code == 1 { push_str(sb, "  movb $"); push_int(sb, disc); push_str(sb, ", -"); push_int(sb, off); push_str(sb, "(%rbp)\n") }
  if code == 2 { push_str(sb, "  movb $"); push_int(sb, disc); push_str(sb, ", -"); push_int(sb, off); push_str(sb, "(%rbp)\n") }
  if code == 3 { push_str(sb, "  movw $"); push_int(sb, disc); push_str(sb, ", -"); push_int(sb, off); push_str(sb, "(%rbp)\n") }
  if code == 4 { push_str(sb, "  movw $"); push_int(sb, disc); push_str(sb, ", -"); push_int(sb, off); push_str(sb, "(%rbp)\n") }
  if code == 5 { push_str(sb, "  movl $"); push_int(sb, disc); push_str(sb, ", -"); push_int(sb, off); push_str(sb, "(%rbp)\n") }
  if code == 6 { push_str(sb, "  movl $"); push_int(sb, disc); push_str(sb, ", -"); push_int(sb, off); push_str(sb, "(%rbp)\n") }
}

pub emit_enum_match := fn(head_in : usize, si : ScrutInfo, in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  ## Capture the comptime-for-VARIANT loop-var name from the template arm (`wild==2`, whose `vs/vl`
  ## still hold the loop var — `expand_variant_arms` overwrites the GENERATED arms' `vs/vl` with each
  ## variant's own name). Threaded into `cx.cf_vloop_*` for the body pass so `var.name`/`var.payload`
  ## resolve; restored at the end. 0/0 for an ordinary (non-template) match → byte-identical.
  ov_vls := cx.cf_vloop_s; ov_vll := cx.cf_vloop_l
  mut tpl := head_in
  while tpl != 0 {
    tm := deref(arm_p(tpl))
    if tm.wild == 2 { cx.cf_vloop_s = tm.vs; cx.cf_vloop_l = tm.vl }
    tpl = tm.next
  }
  ## A scrutinee slot may carry the nominal enum's declaration module even when its source type span
  ## is only the tail (`Error`). Publish that identity for arm expansion, layout and variant lookup;
  ## remember the caller's context so arm expressions remain lexically scoped to the caller.
  entry_type_on := lower_layout::type_ref_mod_on()
  entry_type_s := lower_layout::type_ref_mod_s()
  entry_type_l := lower_layout::type_ref_mod_l()
  mut owner_type_ctx := entry_type_on
  mut owner_type_s := entry_type_s
  mut owner_type_l := entry_type_l
  mut match_owner_ctx := false
  if si.tmod_l != 0 {
    owner_type_ctx = true
    owner_type_s = si.tmod_s
    owner_type_l = si.tmod_l
    lower_layout::set_type_ref_module(owner_type_s, owner_type_l, ROOT_MOD_S, ROOT_MOD_L)
    match_owner_ctx = true
  }
  if owner_type_ctx == false { owner_type_s = 0; owner_type_l = 0 }
  head := expand_variant_arms(head_in, si.es, si.el, cx, a)
  body_type_swap := owner_type_ctx and not streq(cx.src, owner_type_s, owner_type_l, cx.mod_s, cx.mod_l)
  lend := nl
  nl += 1
  ## load the discriminant (slot `base`) into %r12 — at the `@repr(T)` tag WIDTH if the enum pins one
  ## (spec §8), else the word-sized `movq` (code 0 → byte-identical for the no-`@repr` corpus).
  rsp := enum_repr_ty(cx.decls, cx.src, si.es, si.el)
  emit_repr_tag_load(sb, si.base, repr_tag_code(cx.src, rsp.s, rsp.n))
  ## §8 `@niche`: a NICHE-FOLDED `Option(ptr(T))` scrutinee is ONE word (loaded into %r12 above), with
  ## NO discriminant — the word IS the payload, and the `None` case is the null (0) niche. So a variant
  ## arm dispatches on `word == 0`: the NULLARY (`None`) arm takes the zero, the PAYLOAD (`Some`) arm the
  ## nonzero (a non-null `ptr` — Memory §4.2). `si.es/el` is the folded slot's full `Option(ptr(T))` span.
  folded := is_niche_folded(cx.src, si.es, si.el)
  ## dispatch pass
  mut arm := head
  mut hadwild := false
  while arm != 0 {
    am := deref(arm_p(arm))
    lbody := nl
    nl += 1
    if am.wild != 0 {
      push_str(sb, "  jmp ")
      emit_label(sb, lbody)
      push_str(sb, "\n")
      hadwild = true
    } else if folded {
      ## nullary `None` (binds none) ⟺ `word == 0`; payload `Some` (binds one) ⟺ `word != 0`. The bind
      ## count avoids resolving the parenthesized `Option(ptr(T))` span through `enum_decl_of`.
      mut fnb := 0
      mut fcb := am.binds_head
      while unchecked bitcast(usize, fcb) != 0 { fnb = fnb + 1; fcb = bnd_next(fcb) }
      if fnb == 0 { push_str(sb, "  cmpq $0, %r12\n  je ") }          ## None ⟺ null (0)
      else { push_str(sb, "  cmpq $0, %r12\n  jne ") }                ## Some ⟺ nonzero pointer
      emit_label(sb, lbody)
      push_str(sb, "\n")
    } else {
      disc := variant_index(cx.decls, cx.src, si.es, si.el, am.vs, am.vl, deref(cx.mar))
      push_str(sb, "  movq $")
      push_int(sb, disc)
      push_str(sb, ", %rax\n  cmpq %rax, %r12\n  je ")
      emit_label(sb, lbody)
      push_str(sb, "\n")
    }
    arm = am.next
  }
  if hadwild == false {
    push_str(sb, "  pushq $0\n  jmp ")
    emit_label(sb, lend)
    push_str(sb, "\n")
  }
  ## body pass — bind payloads, emit, restore the slot map
  mut arm2 := head
  mut lbody2 := lend + 1
  while arm2 != 0 {
    am2 := deref(arm_p(arm2))
    emit_label(sb, lbody2)
    push_str(sb, ":\n")
    ## alias each payload binding name to its scrutinee payload slot (binding `i` → word
    ## `base + 1 + i`), walking the arm's arena-linked `Bind` list. Pushed onto `cx.slots`
    ## (last-match-wins lookup) for the body emission, then truncated back after.
    saved := svec_len(cx.slots)
    ## count the arm's payload bindings — a SINGLE binding whose (substituted) payload type is a
    ## struct/enum is bound as an AGGREGATE local (ek 2/3) at the payload slot `base+1`, so a use
    ## like `ty_eq(bt, …)` passes it BY REFERENCE (its slot address). A multi-binding variant
    ## (`Bin(op,l,r)`) or a scalar payload keeps the one-word-per-binding scalar aliasing. Fixes
    ## the `check`/sema crash: `Ok(bt : Ty)` was bound as a 1-word scalar → passed by-value to a
    ## by-ref `Ty` param → deref of the tag value. The payload TYPE is resolved via the enum's
    ## variant + the instance's type-args (`variant_payload_type`, generic-aware).
    mut nbind := 0
    mut cb := am2.binds_head
    while unchecked bitcast(usize, cb) != 0 { nbind = nbind + 1; cb = bnd_next(cb) }
    pty := variant_payload_type(cx.decls, cx.src, si.es, si.el, am2.vs, am2.vl, deref(cx.mar))
    mut agg_ek : u8 = 0
    mut agg_ess := 0
    mut agg_esl := 0
    mut agg_estride := 1
    mut agg_nel := 0
    if nbind == 1 and pty.n != 0 {
      if struct_decl_of(cx.decls, cx.src, base_type_name(cx.src, pty.s, pty.n).s, base_type_name(cx.src, pty.s, pty.n).n) >= 0 { agg_ek = 2 }
      else if enum_decl_of(cx.decls, cx.src, base_type_name(cx.src, pty.s, pty.n).s, base_type_name(cx.src, pty.s, pty.n).n) >= 0 { agg_ek = 3 }   ## nested generic-instance payload resolves via BASE name; FULL span kept in the slot
      else if str_at((cx.src + pty.s), pty.n) == "str" { agg_ek = 4 }   ## a str payload → 2-word {ptr, len} binding
      else {
        ## A single fixed-array payload is itself an indexable aggregate binding. Preserve its
        ## element type/stride in the alias SlotEntry so `xs[i].a.arr[j]` reaches the existing
        ## deep fixed-array place resolver. The enum payload parser keeps the complete `[T; N]`
        ## span; no source-side type invention is needed here.
        pae := array_elem_span(cx.src, pty.s, pty.n)
        if pae.n != 0 {
          pbn := base_type_name(cx.src, pae.s, pae.n)
          if struct_decl_of(cx.decls, cx.src, pbn.s, pbn.n) < 0 {
            panic("selfhost: a match binding rooted at an array payload currently requires a plain-struct element (`xs[i].a.arr[j]`); aggregate array leaves remain a fail-loud frontier")
          }
          agg_ek = 5
          agg_ess = pae.s
          agg_esl = pae.n
          agg_estride = struct_words(cx.decls, cx.src, pbn.s, pbn.n, a)
          agg_nel = parse_arr_len(cx.src, pty.s, pty.n)
          if agg_nel == 0 or agg_estride == 0 {
            panic("selfhost: a match binding array payload has no resolvable fixed length/element stride")
          }
        }
      }
    }
    mut bnd := am2.binds_head
    mut bi := 0
    while unchecked bitcast(usize, bnd) != 0 {
      bmns := bnd_ns(bnd)
      bmnl := bnd_nl(bnd)
      if agg_ek == 5 {
        ## Match aliases point into the enum's already-reserved payload block rather than owning a
        ## newly allocated array block. Mirror bind_array_slot's filler metadata solely for checked
        ## bounds recovery (`agg_arr_fill_count`); the filler `off`s are intentionally irrelevant.
        for fi in 0..(agg_nel * agg_estride) {
          svec_push(deref(cx.slots), SlotEntry(ns = 0, nl = 0, off = 0, sns = 0, snl = 0, ek = 0, estride = 1, eek = 0, is_ref = false))
        }
        svec_push(deref(cx.slots), SlotEntry(ns = bmns, nl = bmnl, off = si.base - 1 - bi, sns = agg_ess, snl = agg_esl, ek = 5, estride = agg_estride, eek = 2, is_ref = false, tmod_s = owner_type_s, tmod_l = owner_type_l))
      } else if agg_ek != 0 {
        ## aggregate payload (struct ek 2 / enum ek 3): the payload words live inline at
        ## `base+1 …`; record the type span so a field/aggregate use resolves + is passed by-ref.
        svec_push(deref(cx.slots), SlotEntry(ns = bmns, nl = bmnl, off = si.base - 1 - bi, sns = pty.s, snl = pty.n, ek = agg_ek, estride = 1, eek = 0, is_ref = false, tmod_s = owner_type_s, tmod_l = owner_type_l))
      } else if folded {
        ## §8 `@niche`: the folded `Some(p)` payload IS word 0 (`si.base`) — the pointer occupies the
        ## whole slot (no separate payload word), so bind `p` there as a scalar (ek 0) pointer value.
        svec_push(deref(cx.slots), SlotEntry(ns = bmns, nl = bmnl, off = si.base, sns = 0, snl = 0, ek = 0, estride = 1, eek = 0, is_ref = false, tmod_s = owner_type_s, tmod_l = owner_type_l))
      } else {
        svec_push(deref(cx.slots), SlotEntry(ns = bmns, nl = bmnl, off = si.base - 1 - bi, sns = 0, snl = 0, ek = 0, estride = 1, eek = 0, is_ref = false, tmod_s = owner_type_s, tmod_l = owner_type_l))
      }
      bi += 1
      bnd = bnd_next(bnd)
    }
    ov_cvs := cx.cf_curvar_s; ov_cvl := cx.cf_curvar_l
    if am2.wild == 0 { cx.cf_curvar_s = am2.vs; cx.cf_curvar_l = am2.vl }
    cx.mdepth = cx.mdepth + 1                            ## a nested match uses a higher scratch level
    if body_type_swap {
      if entry_type_on { lower_layout::set_type_ref_module(entry_type_s, entry_type_l, ROOT_MOD_S, ROOT_MOD_L) } else { lower_layout::clear_type_ref_module() }
    }
    emit_gas(am2.body, sb, cx, a, nl)   ## body — leaves its value on the stack
    if body_type_swap { lower_layout::set_type_ref_module(owner_type_s, owner_type_l, ROOT_MOD_S, ROOT_MOD_L) }
    cx.mdepth = cx.mdepth - 1
    cx.cf_curvar_s = ov_cvs; cx.cf_curvar_l = ov_cvl
    svec_truncate(deref(cx.slots), saved)
    push_str(sb, "  jmp ")
    emit_label(sb, lend)
    push_str(sb, "\n")
    lbody2 += 1
    arm2 = am2.next
  }
  emit_label(sb, lend)
  push_str(sb, ":\n")
  cx.cf_vloop_s = ov_vls; cx.cf_vloop_l = ov_vll
  if match_owner_ctx {
    if entry_type_on { lower_layout::set_type_ref_module(entry_type_s, entry_type_l, ROOT_MOD_S, ROOT_MOD_L) } else { lower_layout::clear_type_ref_module() }
  }
}
