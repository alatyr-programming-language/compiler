## selfhost::lower::assign — the ASSIGNMENT FORMS: the `@packed` sized field load/store, the standard
## (byte-layout) field store, and the whole-struct construction store.
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. That is what lets every UNQUALIFIED name below that this
## file does not import (`emit_expr`, `streq`, `decl_at`, `array_elem_span`, `struct_lit_info`,
## `slot_of`, …) bind `lower.al`'s OWN copy through the ancestor chain (Modules §3, privacy flows
## DOWN) instead of an unrelated module's same-named private duplicate.
##
## The cleanest boundary in the file: this band names NO module global and declares NO type. The five
## externally-called entry points are re-imported into `lower.al` by BARE NAME
## (`(emit_packed_load, …) := assign`), which leaves every call site unchanged and keeps the boundary
## `@inline`-transparent — a qualified `assign::f(x)` site does NOT expand an `@inline` callee, a
## bare-name one does.
##
## The imports below are exactly the names the band uses that `lower.al` itself imports; nothing is
## imported "just in case", because a listed projection tells the module-boundary gates which module
## a name means and would mask a rebinding it did not intend.
## NOTE the ORDER: a BARE module alias (`strbuf := rt`) followed by a listed projection is a parse
## error in the self-host parser unless a QUALIFIED alias (`x := m::y`) separates them — the same
## order `src/lower.al`'s own prologue uses. Keep it.
strbuf := rt
arg_p := ast::arg_p
fld_p := ast::fld_p
(Decl, Expr, local_is_uninit, local_type_span) := ast
(push_str, push_int) := strbuf
(CSpan, LCtx, arg_expr_at, num_lit_value, var_name_span) := lower_ctx
(eff_field_wsize, enum_decl_of, enum_inst_words, field_align_attr, field_byte_size, field_endian_attr, field_offset_attr, field_word_offset, field_words, is_niche_folded, is_packed, is_packed_aggregate, is_union_decl, is_view_type, layout_copy_nsteps, layout_copy_step, layout_kind, layout_kind_is_byte, layout_struct_is_word_stored, packed_field_byte_offset, packed_field_endian, round_up_to, scalar_byte_size, standard_field_byte_offset, standard_struct_bytes, std_array_elem_byte_tier, std_copy_image_bytes, std_copy_kind, std_struct_has_direct_byte_layout, std_struct_is_byte_writable, std_struct_is_word_granular, struct_decl_of, struct_words, subst_field_ty, variant_index) := lower_layout
## SIBLING children, reached by an EXPLICIT qualified path (Modules §4) — never by a bare name. Each
## of these was a bare name while the arms lived in `src/lower.al` and the ancestor chain answered;
## from here a bare call would bind through the unique-declaration leniency instead, and
## `scripts/callee_module_check.sh` is SILENT on that. Spelled out, this is the arms' real fan-out.
(abi_c_ret_mem_call) := lower::abi_c
(lower_show_src_line) := lower::ctfold
(dyn_user_arg_is_float, fnval_ty_pos, lam_cap_is_float) := lower::fnval
(emit_elem_copy_in, emit_index_addr, field_place_parts, field_read_agg, resolve_idx_field_place, standard_field_path, std_idx_byte_field_eek, std_idx_leaf_is_agg, std_idx_one, std_idx_path) := lower::place

## TYP-13: a direct integer Num used to initialize an explicitly typed float local must be
## converted to the floating value before it is stored. The generic scalar path stores the
## integer bits unchanged, so a later `u64(x)` interprets those bits as a tiny/zero float.
## Return 1 for f64 and 2 for f32; every other RHS/annotation stays on the old path.
expr_num_const := fn(v : ptr(Expr)) -> bool {
  mut ok := false
  match deref(v) {
    Expr::Num(_v, _s, _n) => { ok = true }
    Expr::Bin(op, l, r) => { if (op == 16 or op == 17 or op == 18) and expr_num_const(l) and expr_num_const(r) { ok = true } }
    _ => {}
  }
  ok
}

direct_num_float_target := fn(v : ptr(Expr), src : ptr(u8), ns : usize, nl : usize) -> u8 {
  mut r : u8 = 0
  match deref(v) {
    Expr::Num(_v, _s, _n) => {
      lts := local_type_span(src, ns, nl)
      if lts.n == 3 and str_at((src + lts.s), lts.n) == "f64" { r = 1 }
      else if lts.n == 3 and str_at((src + lts.s), lts.n) == "f32" { r = 2 }
    }
    Expr::Bin(_op, _l, _r) => {
      if expr_num_const(v) {
        lts := local_type_span(src, ns, nl)
        if lts.n == 3 and str_at((src + lts.s), lts.n) == "f64" { r = 1 }
        else if lts.n == 3 and str_at((src + lts.s), lts.n) == "f32" { r = 2 }
      }
    }
    _ => {}
  }
  r
}

emit_direct_num_float_assign := fn(v : ptr(Expr), target : u8, base : i64, in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  emit_gas(v, sb, cx, a, nl)
  push_str(sb, "  popq %rax\n")
  if target == 2 {
    ## Materialize through f32, then widen to the canonical f64 value representation used by
    ## the x86 float expression path. This preserves f32 rounding before later arithmetic/casts.
    push_str(sb, "  cvtsi2ss %rax, %xmm0\n  cvtss2sd %xmm0, %xmm0\n")
  } else {
    push_str(sb, "  cvtsi2sd %rax, %xmm0\n")
  }
  push_str(sb, "  movq %xmm0, %rax\n  movq %rax, -")
  push_int(sb, (base + 1) * 8)
  push_str(sb, "(%rbp)\n")
}


## Emit the field stores for a struct construction `name := S(f0 = e0, f1 = e1)` — lower
## each field value (left on the stack) and pop it into the local's reserved slot: field `i`
## lives at `-(base + i + 1) * 8(%rbp)` (the word-sized layout; field values appear in the
## struct's DECLARATION ORDER, which the parser enforces positionally). The deref-match on
## the value pointer `v` stays here (a pointer PARAM) — the lowerable shape.
## STRUCT-WITH-ARRAY-FIELD tier: the field-value list (`Arg` list) is walked in PARALLEL with the
## struct's `FieldDecl` list, accumulating a CUMULATIVE word offset (each field advances by its
## `wsize`). A scalar field (wsize 1) stores its value into one word at slot `base + off`. An
## ARRAY field (wsize N) whose value is an array literal `[…]` stores each element into the
## `wsize` consecutive words starting at slot `base + off` (reusing `emit_array_assign` targeted
## at the field's base slot — the same element-store logic the array tier uses). A scalar-only
## struct walks one word per field — byte-identical to the old layout.
## §8 `@packed` — emit a sized load of a packed field into %rax, then push it. The field lives at frame
## displacement `disp` (bytes below %rbp); `sz` is its byte width and `signed` its signedness (an `iN`
## field sign-extends, else zero-extend). movzbq/movswq/movl(zero-ext)/movslq/movq per width — the
## byte-precise counterpart of the word-sized `movq -(slot+1)*8(%rbp)` read. Flat if/else (no expr-if).
## §8 `@endian(big)` (`ebig`) — a big-endian scalar field is STORED byte-reversed (MSB first), so its
## LOAD reverses the bytes back to the native value: a ZERO-extending sized load of the raw stored bytes,
## a byte-swap (`rolw $8` for 2, `bswap` for 4/8), then a sign-extend from the field width if `signed`.
## `ebig` false → the existing byte-identical native path (gated on the field's `@endian`, so every
## non-big-endian field emits exactly as before → fixpoint/e2e neutral). `sz == 1` needs no swap either way.
pub emit_packed_load := fn(in out sb : strbuf::StrBuf, sz : usize, signed : bool, disp : i64, ebig : bool) {
  if ebig and sz > 1 {
    ## zero-extend load of the raw (byte-reversed) bytes
    if sz == 2 { push_str(sb, "  movzwq -") }
    else if sz == 4 { push_str(sb, "  movl -") }
    else { push_str(sb, "  movq -") }
    push_int(sb, disp)
    if sz == 4 { push_str(sb, "(%rbp), %eax\n") }   ## movl zero-extends into %rax
    else { push_str(sb, "(%rbp), %rax\n") }
    ## byte-swap to recover the native value
    if sz == 2 { push_str(sb, "  rolw $8, %ax\n") }
    else if sz == 4 { push_str(sb, "  bswap %eax\n") }
    else { push_str(sb, "  bswap %rax\n") }
    ## sign-extend from the field width if the field is signed
    if signed and sz == 2 { push_str(sb, "  movswq %ax, %rax\n") }
    else if signed and sz == 4 { push_str(sb, "  movslq %eax, %rax\n") }
    push_str(sb, "  pushq %rax\n")
    return
  }
  if sz == 1 and signed { push_str(sb, "  movsbq -") }
  else if sz == 1 { push_str(sb, "  movzbq -") }
  else if sz == 2 and signed { push_str(sb, "  movswq -") }
  else if sz == 2 { push_str(sb, "  movzwq -") }
  else if sz == 4 and signed { push_str(sb, "  movslq -") }
  else if sz == 4 { push_str(sb, "  movl -") }
  else { push_str(sb, "  movq -") }
  push_int(sb, disp)
  if sz == 4 and not signed { push_str(sb, "(%rbp), %eax\n  pushq %rax\n") }   ## movl zero-extends into %rax
  else { push_str(sb, "(%rbp), %rax\n  pushq %rax\n") }
}

## §8 pointer-to-@packed (ek 7 MMIO map) — SIZED load of a packed scalar field at ASCENDING byte
## offset `off` THROUGH the pointer already in %rax (the pointee's word-0 address), pushing the value.
## The register-relative dual of `emit_packed_load` (which reads `-disp(%rbp)`): here the base is the
## pointer in %rax + a POSITIVE byte offset (the pointer-to-struct / MMIO layout is ascending from the
## base address, matching the word-sized `movq fi*8(%rax)` read it replaces). Sign/zero-extends per the
## field width + signedness; `@endian(big)` byte-reverses back to native (parallel to emit_packed_load).
## The load overwrites %rax (the pointer is dead after the read). Flat if/else. Fires ONLY for a packed
## pointee scalar field (gated at the call sites) → the whole word-sized ptr-field read is byte-identical.
pub emit_packed_load_rax := fn(in out sb : strbuf::StrBuf, sz : usize, signed : bool, off : i64, ebig : bool) {
  if ebig and sz > 1 {
    if sz == 2 { push_str(sb, "  movzwq ") }
    else if sz == 4 { push_str(sb, "  movl ") }
    else { push_str(sb, "  movq ") }
    push_int(sb, off)
    if sz == 4 { push_str(sb, "(%rax), %eax\n") }
    else { push_str(sb, "(%rax), %rax\n") }
    if sz == 2 { push_str(sb, "  rolw $8, %ax\n") }
    else if sz == 4 { push_str(sb, "  bswap %eax\n") }
    else { push_str(sb, "  bswap %rax\n") }
    if signed and sz == 2 { push_str(sb, "  movswq %ax, %rax\n") }
    else if signed and sz == 4 { push_str(sb, "  movslq %eax, %rax\n") }
    push_str(sb, "  pushq %rax\n")
    return
  }
  if sz == 1 and signed { push_str(sb, "  movsbq ") }
  else if sz == 1 { push_str(sb, "  movzbq ") }
  else if sz == 2 and signed { push_str(sb, "  movswq ") }
  else if sz == 2 { push_str(sb, "  movzwq ") }
  else if sz == 4 and signed { push_str(sb, "  movslq ") }
  else if sz == 4 { push_str(sb, "  movl ") }
  else { push_str(sb, "  movq ") }
  push_int(sb, off)
  if sz == 4 and not signed { push_str(sb, "(%rax), %eax\n  pushq %rax\n") }   ## movl zero-extends into %rax
  else { push_str(sb, "(%rax), %rax\n  pushq %rax\n") }
}

## §8 `@packed` — SIZED STORE of a packed scalar field at ASCENDING byte offset `off` THROUGH the
## pointer already in %rax (the pointee's word-0 address), the value on the STACK TOP. The store dual
## of `emit_packed_load_rax` and the pointer-relative dual of `emit_packed_assign`'s `-disp(%rbp)`
## store: pops the value into %rbx, byte-reverses it for `@endian(big)` (the load reverses it back),
## then writes exactly `sz` bytes (`movb`/`movw`/`movl`/`movq`) — a word `movq` would smear the value
## over the FOLLOWING packed fields. Fires ONLY for a packed pointee scalar field (gated at the call
## sites) → every word-sized field store through a pointer is byte-identical.
pub emit_packed_store_rax := fn(in out sb : strbuf::StrBuf, sz : usize, off : i64, ebig : bool) {
  push_str(sb, "  popq %rbx\n")
  if ebig and sz == 2 { push_str(sb, "  rolw $8, %bx\n") }
  else if ebig and sz == 4 { push_str(sb, "  bswap %ebx\n") }
  else if ebig and sz == 8 { push_str(sb, "  bswap %rbx\n") }
  if sz == 1 { push_str(sb, "  movb %bl, ") }
  else if sz == 2 { push_str(sb, "  movw %bx, ") }
  else if sz == 4 { push_str(sb, "  movl %ebx, ") }
  else { push_str(sb, "  movq %rbx, ") }
  push_int(sb, off)
  push_str(sb, "(%rax)\n")
}

## §8 `@packed` — materialize a packed-struct literal `[ss,sl]` (field values `fhead`) into the local at
## base SLOT `base`. Field 0 sits at the block's LOWEST address `rbp-(base+1)*8`; a packed field at byte
## offset `bo` is thus at `rbp-((base+1)*8 - bo)`, stored with a correctly-SIZED store (movb/movw/movl/
## movq of the low bytes of %rax). The reservation stays word-sized (`struct_words`, over-sized — every
## scalar field ≤ 1 word, so the packed bytes always fit in the reserved block), so ONLY the byte
## offsets + store widths change; the base slot math is shared with the word-sized path. Walks the
## `FieldDecl` list (byte sizes) alongside the value list, mirroring `emit_struct_assign`'s idioms.
pub emit_packed_assign := fn(ss : usize, sl : usize, fhead : usize, base : i64, in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  di := struct_decl_of(cx.decls, cx.src, ss, sl)
  mut fd := 0
  if di >= 0 {
    ddh := rt::vec_get(deref(cx.decls), usize(di))
    ddd := deref(decl_at(Decl, ddh))
    fd = ddd.fields_head
  }
  mut g := fhead
  mut boff := 0
  while g != 0 {
    ga := deref(arg_p(g))
    mut sz := 8
    mut fdnext := 0
    mut eo := -1
    mut ea := -1
    mut eb := -1
    mut ats := 0
    mut atl := 0
    mut awsize := 1
    mut is_agg := false
    mut is_byte_arr := false
    if fd != 0 {
      fdn := deref(fld_p(fd))
      sz = scalar_byte_size(cx.src, fdn.ts, fdn.tl)
      fdnext = fdn.next
      eo = field_offset_attr(cx.src, fdn.ns)          ## §8 explicit @offset(N) on this field, or -1
      ea = field_align_attr(cx.src, fdn.ns)           ## §8 @align(N) on this field, or -1
      eb = field_endian_attr(cx.src, fdn.ns)          ## §8 @endian(big)=1 / @endian(little)=0, or -1
      ats = fdn.ts
      atl = fdn.tl
      awsize = fdn.wsize
      aes := array_elem_span(cx.src, fdn.ts, fdn.tl)
      if aes.n != 0 and byte_type_eek(cx.src, aes.s, aes.n) != 0 { is_byte_arr = true }
      ## §8 aggregate FIELD (str / nested struct / enum / array) in a packed struct — a multi-word value
      ## stored via the word-model emitters at an 8-aligned slot (byte→slot), not a scalar sized store.
      is_agg = is_packed_aggregate(cx.decls, cx.src, fdn.ts, fdn.tl, fdn.wsize)
    }
    ## `@align(N)` raises the running cursor to a multiple of N; a field carrying `@offset(N)` sits at
    ## byte N (overriding the cursor), the cursor continuing after it (overlap allowed, union-like).
    ## Mirrors `packed_field_byte_offset` so the store offsets match the read offsets exactly.
    mut cur := boff
    if ea >= 1 { cur = i64(round_up_to(usize(cur), usize(ea))) }
    if eo >= 0 { cur = eo }
    if is_byte_arr {
      ## Explicit byte arrays are the one aggregate shape proven to be byte-contiguous here. Their
      ## literal elements are emitted as sized byte stores at the packed field offset; do not route
      ## them through the word aggregate emitters, whose 8-byte alignment requirement is intentional
      ## for the still-deferred general aggregate case.
      ali := array_lit_info(ga.e)
      if ali.is_a == false { panic("selfhost: a packed byte-array field initializer must be an array literal in this slice") }
      mut ae := ali.ehead
      mut k := 0
      while ae != 0 {
        av := deref(arg_p(ae))
        emit_gas(av.e, sb, cx, a, nl)
        push_str(sb, "  popq %rax\n  movb %al, -")
        push_int(sb, (base + 1) * 8 - cur - i64(k))
        push_str(sb, "(%rbp)\n")
        k = k + 1
        ae = av.next
      }
      boff = cur + i64(awsize)
    } else if is_agg {
      ## The aggregate keeps its natural 8-byte alignment inside the packed struct (the word-model
      ## emitters store whole words), so its byte offset MUST be 8-aligned — else fail LOUD (unaligned
      ## multi-word packing is a deferred slice, never a silent miscompile). Byte `cur` → slot
      ## `base - cur/8`: a field at byte `cur` (8-aligned) is the word slot whose lowest address is
      ## `rbp-((base+1)*8 - cur)`, i.e. slot `base - cur/8` in the down-growing block — exactly where the
      ## word-model emitters (`emit_struct_assign`/`emit_str_assign`/…) lay the aggregate's words, so a
      ## scalar OVERLAY read (`@offset(cur+k)`) of any word lands on the right byte.
      if (cur / 8) * 8 != cur { panic("selfhost: an aggregate/str field in a @packed struct must be 8-byte aligned — use @offset(8*k) or @align(8) (unaligned aggregate packing is a deferred slice)") }
      aslot := base - (cur / 8)
      nsli := struct_lit_info(ga.e)
      sli := str_lit_info(ga.e)
      eli := enum_lit_info(ga.e)
      ali := array_lit_info(ga.e)
      if nsli.is_s { emit_struct_assign(ga.e, aslot, sb, cx, a) }
      else if sli.is_s { emit_str_assign(ga.e, aslot, sb) }
      else if eli.is_e {
        ## A union field is a raw offset-0 aggregate, not an enum's `[disc,payload]` pair.
        if is_union_decl(cx.decls, cx.src, ats, atl) { emit_union_assign(ga.e, aslot, sb, cx, a, nl) }
        else { emit_enum_assign(ga.e, aslot, sb, cx, a, nl) }
      }
      else if ali.is_a { emit_array_assign(ga.e, aslot, sb, cx, nl) }
      boff = cur + i64(field_byte_size(cx.decls, cx.src, ats, atl, awsize, a))
    } else {
      emit_gas(ga.e, sb, cx, a, nl)
      push_str(sb, "  popq %rax\n")
      ## §8 @endian(big): byte-REVERSE the value before the sized store so its bytes land MSB-first on the
      ## little-endian x86 native (the load reverses them back). `sz == 1` and native/`little` need no swap.
      if eb == 1 and sz == 2 { push_str(sb, "  rolw $8, %ax\n") }
      else if eb == 1 and sz == 4 { push_str(sb, "  bswap %eax\n") }
      else if eb == 1 and sz == 8 { push_str(sb, "  bswap %rax\n") }
      disp := (base + 1) * 8 - cur
      if sz == 1 { push_str(sb, "  movb %al, -") }
      else if sz == 2 { push_str(sb, "  movw %ax, -") }
      else if sz == 4 { push_str(sb, "  movl %eax, -") }
      else { push_str(sb, "  movq %rax, -") }
      push_int(sb, disp)
      push_str(sb, "(%rbp)\n")
      boff = cur + i64(sz)
    }
    fd = fdnext
    g = ga.next
  }
}

## STANDARD BYTE LAYOUT — materialize the first ordinary standard-layout struct slice into a local or
## aggregate temporary. This bounded emitter intentionally accepts scalar fields and explicit byte-array
## fields only; a nested struct/enum/str/other aggregate is rejected before the old word emitter can
## silently disagree with the shared byte offsets. The destination frame block still reserves whole
## words (`ceil(T.size()/8)`), but every byte-array element and narrow scalar lands at its exact offset.
## P1-CLAYOUT S3(b) — `bias` is the byte offset of THIS struct value inside the frame block whose
## lowest address is `rbp-(base+1)*8`: 0 for a top-level construction, the accumulated §6.1 offset for
## a nested child. It is what makes this function the ONE byte-precise whole-value writer on x86_64 —
## the nested-struct arm recurses into itself at `bias + bo` instead of handing the child to the
## word-granular `emit_struct_assign`, so every leaf lands at `standard_field_byte_offset` summed down
## the chain, which is exactly the sum `layout_field_offset_bytes` gives every READER, and exactly
## what `a64_std_store_struct` / `rv_std_store_struct` / `wat_std_store_struct` already did.
emit_standard_assign := fn(ss : usize, sl : usize, fhead : usize, base : i64, bias : i64, in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  di := struct_decl_of(cx.decls, cx.src, ss, sl)
  if di < 0 { panic("selfhost: standard-layout struct construction has no declaration") }
  ddh := rt::vec_get(deref(cx.decls), usize(di))
  ddd := deref(decl_at(Decl, ddh))
  mut fd := ddd.fields_head
  mut g := fhead
  while g != 0 {
    if fd == 0 { panic("selfhost: standard-layout struct construction has more values than fields") }
    ga := deref(arg_p(g))
    fdn := deref(fld_p(fd))
    eff := subst_field_ty(cx.decls, cx.src, ss, sl, fdn.ts, fdn.tl, deref(cx.mar))
    ew := eff_field_wsize(cx.decls, cx.src, ss, sl, fdn.ts, fdn.tl, fdn.wsize, deref(cx.mar))
    bo0 := standard_field_byte_offset(cx.decls, cx.src, ss, sl, fdn.ns, fdn.nl, deref(cx.mar))
    if bo0 < 0 { panic("selfhost: standard-layout struct field has no byte offset") }
    bo := bias + bo0
    aes := array_elem_span(cx.src, eff.s, eff.n)
    mut beek := u8(0)
    if aes.n != 0 { beek = byte_type_eek(cx.src, aes.s, aes.n) }
    if beek != 0 {
      ali := array_lit_info(ga.e)
      if ali.is_a == false { panic("selfhost: a standard-layout byte-array field initializer must be an array literal") }
      mut ae := ali.ehead
      mut k := 0
      while ae != 0 {
        av := deref(arg_p(ae))
        if struct_lit_info(av.e).is_s or enum_lit_info(av.e).is_e or str_lit_info(av.e).is_s or array_lit_info(av.e).is_a { panic("selfhost: a standard-layout byte-array field literal must contain scalar elements") }
        emit_gas(av.e, sb, cx, a, nl)
        push_str(sb, "  popq %rax\n  movb %al, -")
        push_int(sb, (base + 1) * 8 - bo - i64(k))
        push_str(sb, "(%rbp)\n")
        k += 1
        ae = av.next
      }
    } else if struct_decl_of(cx.decls, cx.src, eff.s, eff.n) >= 0 {
      ## P1-CLAYOUT S3(b) — THE RECURSION. A nested STRUCT field is a value whose standard layout
      ## starts at the containing field's §6.1 byte offset, so writing it is THIS function again with
      ## `bias = bo`. S3(a) could not do that: it handed the child to `emit_struct_assign`, the
      ## word-per-field constructor, while aarch64/riscv64/wat recursed byte-precisely — so for a child
      ## whose two images differ the four backends built four different memory images. Measured then on
      ## `struct { data : [u8;8], inner : struct { a : u16, b : u16 } }`: the child went in at
      ## child-words 0/1 (bytes 8 and 16) while `o.inner.b` was read at byte 10, so x86_64 answered 0
      ## where its own three siblings answered 22, and all four were made to refuse rather than let one
      ## be wrong (I11). Now one writer, one set of offsets.
      ##
      ## `std_struct_is_byte_writable` is that writer's domain, defined ONCE in `lower_layout` and
      ## asked by all four backends. It needs no 8-boundary guard, because the recursion stores at
      ## ARBITRARY byte offsets — the S3(a) guard existed only because `emit_struct_assign` addresses
      ## whole SLOTS, and it is also why that guard never saw the defect: `bo` was 8, perfectly
      ## aligned. A child OUTSIDE the domain but still word-stored keeps the word constructor, which is
      ## sound precisely because word-granular MEANS its §6.1 offsets are its word offsets times 8 — so
      ## shapes the byte writer has no store for (a `[u64; 3]` field, a `str`, an enum) keep working on
      ## x86_64 exactly as before. A child in NEITHER set stays fail-loud. The nested layout
      ## decision is now expressed directly as the three semantic cases; the parser accepts this
      ## chain, so no temporary flags are needed to avoid the retired desynchronisation.
      if std_struct_is_byte_writable(cx.decls, cx.src, eff.s, eff.n, deref(cx.mar)) {
        emit_standard_value(ga.e, base, bo, sb, cx, a, nl)
      } else if layout_struct_is_word_stored(cx.decls, cx.src, eff.s, eff.n, deref(cx.mar)) {
        if (bo / 8) * 8 != bo { panic("selfhost: a standard-layout nested struct field written by the word constructor must start at an 8-byte boundary") }
        emit_struct_assign(ga.e, base - bo / 8, sb, cx, a, nl)
      } else {
        panic("selfhost: a standard-layout struct's nested aggregate field must be writable by the byte-precise whole-value writer (scalar / byte-array / nested-struct fields only) or by the plain word constructor — a @packed child, or one carrying a str, enum, union, tuple or non-byte array field, is written by a different constructor than the one that reads it; bind the inner value to its own local instead")
      }
    } else if str_at((cx.src + eff.s), eff.n) == "str" or enum_decl_of(cx.decls, cx.src, eff.s, eff.n) >= 0 or ew > 1 {
      panic("selfhost: standard-layout struct construction with this nested aggregate field is not yet supported by all byte consumers")
    } else {
      sz := scalar_byte_size(cx.src, eff.s, eff.n)
      emit_gas(ga.e, sb, cx, a, nl)
      push_str(sb, "  popq %rax\n")
      if sz == 1 { push_str(sb, "  movb %al, -") }
      else if sz == 2 { push_str(sb, "  movw %ax, -") }
      else if sz == 4 { push_str(sb, "  movl %eax, -") }
      else { push_str(sb, "  movq %rax, -") }
      push_int(sb, (base + 1) * 8 - bo)
      push_str(sb, "(%rbp)\n")
    }
    fd = fdn.next
    g = ga.next
  }
}

## The byte-precise whole-value writer's ENTRY POINT, taking the value EXPRESSION rather than an
## already-destructured literal. Two callers need that: the nested-struct recursion above (which needs
## the child's `fhead`, and `struct_lit_info` reports only `is_s`/`ss`/`sl`), and the `o.inner = S(…)`
## whole-child write in `lower.al`, which must write the child with the SAME writer that constructs it
## or the two disagree again. The deref-match on the pointer PARAM `v` is the lowerable shape.
## `bias` is the value's byte offset inside the frame block whose lowest address is `rbp-(base+1)*8`.
pub emit_standard_value := fn(v : ptr(Expr), base : i64, bias : i64, in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  match deref(v) {
    Expr::StructLit(ss, sl, nf, fhead) => { emit_standard_assign(ss, sl, fhead, base, bias, sb, cx, a, nl) }
    _ => { panic("selfhost: the byte-precise standard-layout whole-value writer needs a struct LITERAL — a non-literal aggregate value (a call result, a bound var, a deref) has no byte-precise copy in this slice; bind it to its own local instead") }
  }
}

## P1-CLAYOUT S3(c) — THE ONE BYTE-PRECISE WHOLE-VALUE COPIER on x86_64, the mirror of the writer
## above. It moves a nested child OUT of a standard byte-layout root into a standalone local:
## `copy := o.inner`. `root` is the ROOT local's first slot and `sbo` the child's accumulated §6.1 byte
## offset inside it (both from `standard_field_path`, the same walk every reader uses), so the child's
## byte `k` lives at `rbp-((root+1)*8 - sbo - k)` — the very address `emit_standard_assign` wrote it to.
## `dst` is the destination local's first slot; its word `w` is at `rbp-(dst-w+1)*8` and its byte `k`
## at `rbp-((dst+1)*8 - k)`, exactly as `standard_field_path` / `field_slot` will read it back.
##
## WHICH of those two the destination is read at is not this function's decision: `std_copy_kind`
## (`lower_layout`) makes it once for all four backends, and this function only spells the moves.
## Before S3(c) this copy was `struct_words` whole WORDS regardless, which is right exactly when the
## two layouts coincide — so `std_struct_is_word_granular` children keep that older, byte-identical
## path at every call site and never reach here.
pub emit_standard_copy := fn(ts : usize, tl : usize, root : usize, sbo : i64, dst : i64, in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena) {
  ck := std_copy_kind(cx.decls, cx.src, ts, tl, a)
  if ck == 0 { panic("selfhost: the byte-precise whole-value copier was asked for a type outside its domain — a child carrying a str, an enum, a union, a tuple or a non-byte array has no byte-precise copy; bind its scalar fields instead") }
  ## IMAGE — the destination is BYTE-tier, so it is read at the source's own §6.1 offsets: move the
  ## child's bytes verbatim. Byte at a time, because the child's §6.1 size need not be a multiple of 8
  ## and a wider load would read (and a wider store would write) past it.
  if ck == 1 {
    nb := std_copy_image_bytes(cx.decls, cx.src, ts, tl, a)
    mut k := 0
    while k < nb {
      push_str(sb, "  movzbq -")
      push_int(sb, i64((root + 1) * 8) - sbo - i64(k))
      push_str(sb, "(%rbp), %rax\n  movb %al, -")
      push_int(sb, (dst + 1) * 8 - i64(k))
      push_str(sb, "(%rbp)\n")
      k += 1
    }
  }
  ## GATHER — the destination is WORD-tier, so each field is read as a whole machine word. Load each
  ## scalar leaf at its exact §6.1 source width (sign-extending an `iN`, which is why `signed` travels
  ## with the step) and store the extended value into the destination's word.
  if ck == 2 {
    ns := layout_copy_nsteps(cx.decls, cx.src, ts, tl, a)
    mut i := 0
    while i < ns {
      st := layout_copy_step(cx.decls, cx.src, ts, tl, i64(i), a)
      if not st.found { panic("selfhost: the byte-precise whole-value copier's plan is shorter than its own step count") }
      emit_packed_load(sb, st.sz, st.signed, i64((root + 1) * 8) - sbo - st.sbo, false)
      push_str(sb, "  popq %rax\n  movq %rax, -")
      push_int(sb, (dst - st.dwo + 1) * 8)
      push_str(sb, "(%rbp)\n")
      i += 1
    }
  }
}

pub emit_struct_assign := fn(v : ptr(Expr), base : i64, in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  match deref(v) {
    Expr::StructLit(ss, sl, nf, fhead) => {
      ## §8: a `@packed` struct uses the BYTE-precise store (gated — an un-attributed struct falls to the
      ## word-sized loop below, byte-identically).
      if is_packed(cx.decls, cx.src, ss, sl) {
        emit_packed_assign(ss, sl, fhead, base, sb, cx, a, nl)
        return
      }
      if std_struct_has_direct_byte_layout(cx.decls, cx.src, ss, sl, a) {
        emit_standard_assign(ss, sl, fhead, base, 0, sb, cx, a, nl)
        return
      }
      ## Types §9.4: inside a generic INSTANCE the construction head names the callee's own type
      ## parameter (`Box(T)(v = x)`) — resolve it to the instantiation (`Box(P)`) so the per-field
      ## `subst_field_ty`/`eff_field_wsize` reads below advance `off` by the REAL widths (the raw
      ## `Box(T)` sizes the `v : T` field as ONE word, so a 2-word aggregate field stored one word:
      ## a silent truncation). Unchanged (`ss`/`sl`) for every non-instance / scalar-type-arg head.
      irs := inst_struct_span_cx(ss, sl, cx)
      ## walk the field-decl list (for each field's wsize) and the value list together.
      di := struct_decl_of(cx.decls, cx.src, irs.s, irs.n)
      ## FAIL LOUD on the SILENT-ZERO case of an UNRESOLVABLE construction head (D69): a
      ## generic-CONSTRUCTION-shaped literal `Name(args)(field = …)` with an UNDECLARED `Name`
      ## parses to a bare `StructLit` (the type-arg list is erased), so the decl lookup misses.
      ## With `fd` 0 every field walks as a scalar — fine for genuinely scalar values (a bare
      ## `Slice(u64)(ptr = p, len = n)` stores its two words positionally), but an ARRAY-LITERAL
      ## field value has no frame home on the scalar path and emits `$0`: an all-zero field that
      ## COMPILED (`X(128)(words = [1, 2])`). The legitimate heads resolve (`S`, `Vec(u64)` /
      ## `uint(192)` — the decl is the bare head; `u128` — `struct_decl_of` follows the alias); a
      ## value-fn named call never reaches here (`d_rewrite_named_call` rewrote it to a `Call`).
      if di < 0 {
        mut badz := false
        mut gz := fhead
        while gz != 0 {
          gaz := deref(arg_p(gz))
          if array_lit_info(gaz.e).is_a { badz = true }
          gz = gaz.next
        }
        if badz { panic("selfhost: a struct construction's head does not resolve to a declared struct type — an unknown type constructor (e.g. `X(128)(words = […])` with no `X` declared) cannot materialize an array-literal field; declare the type or fix the name") }
      }
      mut fd := 0
      if di >= 0 {
        ddh := rt::vec_get(deref(cx.decls), usize(di))
        ddd := deref(decl_at(Decl, ddh))
        fd = ddd.fields_head
      }
      mut g := fhead
      mut off := 0
      while g != 0 {
        ga := deref(arg_p(g))
        ## Bind the FieldDecl to a struct LOCAL and read `.wsize`/`.next` from it — an INLINE
        ## `deref(fld_p(fd)).field` read is `Field(Deref(<call>), …)`, which the
        ## self-host lower does not lower (no deref-of-call Field path → `pushq $0`), so b.out read
        ## both as 0: the first field's wsize 0 (no off advance) + `next` 0 (fd→0) collapsed every
        ## struct-ctor arg's field 0 onto field 1. The `fdn := deref(node_ptr(…))` copy is the proven
        ## `ga := deref(node_ptr(Arg,…))` shape both compilers handle.
        mut wsz := 1
        mut fdnext := 0
        mut is_str_fld := false
        mut is_folded_fld := false
        if fd != 0 {
          fdn := deref(fld_p(fd))
          ## the field's TRUE word width — struct-aware (a struct-typed field occupies its struct's
          ## word count; the parser defaults its `wsize` to 1). MUST match the READ side's
          ## `field_word_offset` (which also sums `field_words`), or a nested field reads a wrong slot.
          ## NESTED-GENERIC: substitute a type-PARAM field to the instance's aggregate type-arg (`v : T`
          ## → `Pair` in `Box(Pair(u64))`) so `off` advances by the true width, exactly as the bind
          ## (`struct_words`) + read (`field_word_offset`) sides do (gated to aggregate type-args).
          effc := subst_field_ty(cx.decls, cx.src, irs.s, irs.n, fdn.ts, fdn.tl, deref(cx.mar))
          ## COMPTIME-VALUE-GENERIC: a `[T; <expr>]` field (parser `wsize` 0) stores its array
          ## literal into the FOLDED length's words (`uint(192)` → 3), matching the bind/read sides.
          efw := eff_field_wsize(cx.decls, cx.src, irs.s, irs.n, fdn.ts, fdn.tl, fdn.wsize, deref(cx.mar))
          wsz = field_words(cx.decls, cx.src, effc.s, effc.n, efw, deref(cx.mar))
          fdnext = fdn.next
          ## Types §9.4 — read the SUBSTITUTED type (`effc`), not the raw declared one: a type-PARAM
          ## field of a `str`-instantiated generic (`v : T` in `Box(str)`) is a 2-word `{ptr, len}`
          ## value, but the RAW span is `T`, so the str probe missed and the field fell to the
          ## `wsz > 1` array branch — which matches only an `ArrayLit` and stored NOTHING (`b.v.len`
          ## read 0: a SILENT MISCOMPILE). `subst_field_ty` returns the declared span unchanged for a
          ## non-generic field, so every pre-existing `name : str` field is byte-identical.
          if str_at((cx.src + effc.s), effc.n) == "str" { is_str_fld = true }
          ## §8 `@niche`: a NICHE-FOLDED `Option(ptr(T))` field is ONE word (`field_words` == 1). Its enum
          ## LITERAL initializer must be stored FOLDED (`Some(p)`=p, `None`=0) — not as a `[disc, payload]`
          ## pair, which would spill the payload into the NEXT field's slot (its `wsz` is only 1). Gated by
          ## `is_niche_folded` → every non-folded enum field keeps the byte-identical `emit_enum_assign`.
          if is_niche_folded(cx.src, effc.s, effc.n) { is_folded_fld = true }
        }
        nsli := struct_lit_info(ga.e)
        if nsli.is_s {
          ## a NESTED struct field (`i = I(…)`) — recurse to store the inner struct's words at the
          ## field's base slot (arbitrary nesting). A scalar emit of a `StructLit` would drop it to 0.
          emit_struct_assign(ga.e, base - off, sb, cx, a)
        } else if is_str_fld {
          ## a `str` FIELD (`name = "hi"`) — a 2-word `{ptr, len}` value; store it exactly as a str
          ## LOCAL binding (ptr at `base+off+1`, len at `base+off+2`), matching the `g.name.ptr`/`.len`
          ## read side (`str_field_place`). A LITERAL keeps the byte-identical `emit_str_assign`; any
          ## OTHER str value (a str `Var`/param, a `sub`/`str_at`/`bytes` view, a range slice, a
          ## str-returning call) materializes its pair via `emit_str_pair` — it previously hit
          ## `emit_str_assign`'s `_ => {}` and stored NOTHING (`b.v.len` read 0, a SILENT MISCOMPILE).
          emit_pair_field_store(ga.e, base - off, sb, cx, a, nl)
        } else if is_folded_fld and enum_lit_info(ga.e).is_e {
          ## §8 `@niche`: a folded `Option(ptr(T))` field with an enum-literal init — store the ONE folded
          ## word (`Some(p)`=p / `None`=0) at the field's word 0. `match s.o` reads it back via the folded
          ## branch of `try_field_enum_scrut`. (A folded field initialized by a VAR falls to the scalar
          ## path below — a folded local is one word, stored + loaded scalar-correctly.)
          emit_folded_option_assign(ga.e, base - off, sb, cx, a, nl)
        } else if enum_lit_info(ga.e).is_e and is_union_decl(cx.decls, cx.src, effc.s, effc.n) {
          ## A raw union field stores its constructor payload at the field's word 0. Do not route
          ## through emit_enum_assign, which would write a discriminant and shift the payload by one.
          emit_union_assign(ga.e, base - off, sb, cx, a, nl)
        } else if enum_lit_info(ga.e).is_e {
          ## an ENUM FIELD (`c = Col.G(40)`) — store its discriminant + payload words at the field's
          ## base (its `field_words` == `1 + max_arity` > 1, so it would otherwise fall to the array
          ## branch and be dropped, since an `EnumLit` isn't an `ArrayLit`). `match s.c` reads it back
          ## via `try_field_enum_scrut`.
          emit_enum_assign(ga.e, base - off, sb, cx, a, nl)
        } else if var_agg_info(ga.e, cx.slots, cx.src).ek != 0 {
          ## a struct/enum VAR field value (`inner = s`, `p = q`) — COPY the source aggregate's `wsz`
          ## words into the field's slot. The `wsz > 1` array branch below matches only an `ArrayLit`,
          ## so a bound-var aggregate value fell through to `emit_array_assign`'s `_ => {}` and stored
          ## NOTHING (the field read word 0 as 0 — a silent-wrong-data corner; ROADMAP Priority 2's
          ## generic-struct-LITERAL EMIT case, but general to any struct literal). Field word k lives at
          ## logical slot `base - off - k`; a LOCAL source keeps source word k at frame word k, a by-REF
          ## PARAM holds a pointer with word k at `-(k*8)(ptr)` (the same shape as the `x := <var>` copy).
          fsvn := var_name_span(ga.e)
          fsent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, fsvn.s, fsvn.n)))
          if fsent.is_ref {
            push_str(sb, "  movq -")
            push_int(sb, i64((fsent.off + 1) * 8))
            push_str(sb, "(%rbp), %rax\n")
            for k in 0..wsz {
              push_str(sb, "  movq ")
              push_int(sb, i64(k * 8))
              push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
              push_int(sb, (base - off - i64(k) + 1) * 8)
              push_str(sb, "(%rbp)\n")
            }
          } else {
            for k in 0..wsz {
              push_str(sb, "  movq -")
              push_frame_word(sb, fsent.off, k)
              push_str(sb, "(%rbp), %rcx\n  movq %rcx, -")
              push_int(sb, (base - off - i64(k) + 1) * 8)
              push_str(sb, "(%rbp)\n")
            }
          }
        } else if wsz == 2 and pair_value_expr(ga.e, cx) {
          ## Types §9.4 — a 2-word `{ptr, len}` FIELD (`Slice(T)`, `lib/base/slice.al`) initialized from
          ## a VIEW value (`v = xs[lo..hi]`, or a slice/str `Var`). It is not a `StructLit`/`ArrayLit`
          ## and `var_agg_info` reports ek 0 for a slice slot, so it fell through to `emit_array_assign`,
          ## whose `_ => {}` stored NOTHING — `b.v.len` read 0, a SILENT MISCOMPILE. Store the pair
          ## exactly like a slice LOCAL binding (ptr at word 0, len at word 1), which is what
          ## `field_word_offset` + the `.len` field read expect.
          emit_pair_field_store(ga.e, base - off, sb, cx, a, nl)
        } else if wsz > 1 or array_lit_info(ga.e).is_a {
          ## an ARRAY field — store the array-literal value's elements into the field's words. The
          ## `array_lit_info` disjunct covers the ONE-ELEMENT array literal (`[u64; 1]`, parser
          ## `wsize` 1 — TYP-10's `uint(64)` one-word instance included): gating on `wsz > 1` alone
          ## dropped it to the scalar path, where a bare `ArrayLit` has no frame home and emitted
          ## `$0` — a SILENT zero (a multi-element literal, `wsz > 1`, took this branch already).
          ## An array-of-MULTI-WORD-STRUCT FIELD (`cells : [Cell; 3]`, `Cell` > 1 word) is now correctly
          ## SIZED: `field_words` reserves `N * struct_words(T)` words for the field's frame block (was `N`,
          ## which under-reserved it so element stores overran into adjacent slots / the saved `%rbp` — the
          ## crash / silent-wrong that was previously rejected loud, Types §9.4). `emit_array_assign` places
          ## each struct-literal / bound-struct-var element at its cumulative `struct_words(T)`-strided base,
          ## so the whole `[Struct; N]` field is constructed in place. `off += wsz` (below) now advances by
          ## the true field width. A scalar / 1-word-struct element is byte-identical to before (neutral).
          emit_array_assign(ga.e, base - off, sb, cx, nl)
        } else {
          emit_gas(ga.e, sb, cx, a, nl)
          push_str(sb, "  popq %rax\n  movq %rax, -")
          push_int(sb, (base - off + 1) * 8)
          push_str(sb, "(%rbp)\n")
        }
        off += i64(wsz)
        fd = fdnext
        g = ga.next
      }
    }
    _ => {}
  }
}


## ============================================================================================
## THE SIX ASSIGNMENT-STATEMENT ARMS of `emit_stmts` (`Stmt::Assign`, `FieldAssign`, `DerefAssign`,
## `FieldPathAssign`, `IndexAssign`, `IndexFieldAssign`) — 1 957 lines that were the tail of
## `src/lower.al`. They live here, next to the value-writing primitives they call, because that is
## what the history says: S3(a) 22acca63, S3(b) 261eca66 and S3(c) f87ccb26 EACH touched both these
## arms in `lower.al` AND `src/lower/assign.al` in the same commit — a file-level co-change of 3 in
## two days. Splitting them apart would have kept a lane owning two files; keeping them together
## makes `assign` one leaf. Each arm has exactly ONE caller, `emit_stmts`.
## ============================================================================================
## The `Stmt::FieldAssign` arm of `emit_stmts`, moved out verbatim (Step 4.1). A `var.field = e`
## scalar/aggregate store into the field's reserved frame slot; the caller keeps `s = nx`.
## Touches no module global.
pub emit_st_field_assign := fn(bns : usize, bnl : usize, fns : usize, fnl : usize, fv : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  ## (TYP-6 / D69) the `t.field = <aggregate>` into a scalar struct field soundness net moved UP into
  ## `sema::check_program` (build-path gate).
  ## `GLOBAL.field = v` — a field write to a MUTABLE struct global (`STATE.x = 40`): store the
  ## value into the `.data` cell at `LABEL + field_index*8`. Checked FIRST — the base is a module
  ## global with no frame slot, so `entry_of`/`bent` below must not run for it.
  gwval := mut_global_value(cx.decls, cx.src, bns, bnl)
  mut gw_done := false
  if unchecked bitcast(usize, gwval) != 0 {
    gwsli := struct_lit_info(gwval)
    if gwsli.is_s {
      ## WORD offset (not declaration index): a multi-word field (str/array/nested struct) before
      ## this one shifts its `.data` cell. Identical to the declaration index for an all-scalar struct.
      gwi := field_word_offset(cx.decls, cx.src, gwsli.ss, gwsli.sl, fns, fnl, a)
      if gwi >= 0 {
        ## A MULTI-WORD field of a mutable-GLOBAL struct — an enum (`STATE.c = Col.G(v)`), a str
        ## (`STATE.name = "…"`), or a nested struct (`STATE.inner = P(…)`) — needs ALL its words
        ## written to `.data`; the scalar path below stores one word and drops the rest. Delegate to
        ## `emit_global_agg_store` (shared with the nested `FieldPathAssign` path); it returns false
        ## for a scalar field, which takes the single-word store.
        gwft := field_type_span(cx.decls, cx.src, gwsli.ss, gwsli.sl, fns, fnl, a)
        mut gw_multi := false
        if gwft.n != 0 { gw_multi = emit_global_agg_store(fv, bns, bnl, gwi, gwft.s, gwft.n, sb, cx, a, nl) }
        if gw_multi == false {
          emit_gas(fv, sb, cx, a, nl)
          push_str(sb, "  popq %rax\n  movq %rax, ")
          emit_global_label(sb, cx.decls, cx.src, bns, bnl)
          push_str(sb, "+")
          push_int(sb, gwi * 8)
          push_str(sb, "(%rip)\n")
        }
        gw_done = true
      }
    }
  }
  if gw_done == false {
  bent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, bns, bnl)))
  if bent.ek == 7 {
    ## POINTER-TO-STRUCT base `p.field = v` (p : ptr(S), ek 7 — the slot HOLDS the pointer):
    ## lower the value (on the stack), load p's pointer value into %rax, then store at
    ## `-(field_index*8)(%rax)` — the store through the pointer, the dual of the ek-7 Field
    ## READ (`deref(p).f`). The down-growing pointee layout (field k at a lower address).
    emit_gas(fv, sb, cx, a, nl)
    fi := field_word_offset(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl, deref(cx.mar))
    push_str(sb, "  movq -")
    push_int(sb, i64((bent.off + 1) * 8))
    push_str(sb, "(%rbp), %rax\n  popq %rbx\n  movq %rbx, ")
    push_int(sb, fi * 8)
    push_str(sb, "(%rax)\n")
  } else if bent.is_ref {
    ## BY-REFERENCE struct param `p.field = v`: lower the value (on the stack), load the
    ## base pointer (word-0 address), and store at `-(field_index*8)(%rax)` — the store
    ## through the pointer (visible to the caller), the dual of the by-ref Field READ.
    emit_gas(fv, sb, cx, a, nl)
    fi := field_word_offset(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl, deref(cx.mar))
    emit_agg_base_addr(bent, sb)           ## word-0 address (the pointer) → %rax
    ## §8 `@packed` BY-REFERENCE PARAM WRITE (spec Types §8) — the store dual of the packed by-ref
    ## READ. A `@packed` aggregate param is `is_ref`, so `in out p : Pk { p.b = 21 }` stored a whole
    ## WORD at byte `8*index` of the caller's BYTE-precise block: it both missed the field and
    ## smeared over its neighbours — a SILENT WRONG VALUE visible to the caller. Store exactly the
    ## field's bytes at its packed byte offset. Gated on `is_packed` + a SCALAR field + a resolved
    ## byte offset → every un-attributed by-ref field store is byte-identical (fixpoint-neutral).
    wbpk := is_packed(cx.decls, cx.src, bent.sns, bent.snl)
    mut wbbo := i64(-1)
    mut wbfty := CSpan(s = 0, n = 0)
    if wbpk {
      wbbo = packed_field_byte_offset(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl, deref(cx.mar))
      wbfty = field_type_span(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl, deref(cx.mar))
    }
    wbstd := std_struct_has_direct_byte_layout(cx.decls, cx.src, bent.sns, bent.snl, deref(cx.mar))
    if wbstd {
      wbbo = standard_field_byte_offset(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl, deref(cx.mar))
      wbfty = field_type_span(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl, deref(cx.mar))
    }
    wbaes := array_elem_span(cx.src, wbfty.s, wbfty.n)
    wb_agg := wbaes.n != 0 or (wbfty.n != 0 and (str_at((cx.src + wbfty.s), wbfty.n) == "str" or struct_decl_of(cx.decls, cx.src, wbfty.s, wbfty.n) >= 0 or enum_decl_of(cx.decls, cx.src, wbfty.s, wbfty.n) >= 0))
    if wbpk and wbbo >= 0 and not wb_agg {
      emit_packed_store_rax(sb, scalar_byte_size(cx.src, wbfty.s, wbfty.n), wbbo, packed_field_endian(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl) == 1)
    } else if wbstd and wbbo >= 0 and not wb_agg {
      emit_packed_store_rax(sb, scalar_byte_size(cx.src, wbfty.s, wbfty.n), wbbo, false)
    } else if wbstd {
      panic("selfhost: a standard-layout aggregate field write through a by-reference parameter needs a byte-aware aggregate value path; use indexed byte writes or a supported scalar field")
    } else {
    push_str(sb, "  popq %rbx\n  movq %rbx, ")
    push_int(sb, fi * 8)
    push_str(sb, "(%rax)\n")
    }
  } else {
    ## A single-hop LOCAL struct-field write `g.f = v`. A MULTI-WORD field — a `str` (2-word
    ## {ptr,len}), an `enum` (disc + payload), or a nested STRUCT of >1 word — delivers ALL its
    ## words through the shared `emit_local_field_agg_store` (a scalar store would drop the rest,
    ## a silent word-0-only miscompile). A single scalar word (`emit_local_field_agg_store`
    ## returns false) keeps the byte-identical one-word store below.
    fslot := field_slot_of_name(bns, bnl, fns, fnl, cx)
    mut fw_handled := false
    if bent.ek == 2 {
      fts := field_type_span(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl, deref(cx.mar))
      if std_struct_has_direct_byte_layout(cx.decls, cx.src, bent.sns, bent.snl, deref(cx.mar)) {
        sbo := standard_field_byte_offset(cx.decls, cx.src, bent.sns, bent.snl, fns, fnl, deref(cx.mar))
        saes := array_elem_span(cx.src, fts.s, fts.n)
        smulti := saes.n != 0 or (fts.n != 0 and (str_at((cx.src + fts.s), fts.n) == "str" or struct_decl_of(cx.decls, cx.src, fts.s, fts.n) >= 0 or enum_decl_of(cx.decls, cx.src, fts.s, fts.n) >= 0))
        ## P1-CLAYOUT S3(b) — the whole-child write `o.inner = S(…)` uses the SAME byte-precise
        ## whole-value writer as the construction path, at the child's §6.1 offset inside `o`. Its
        ## domain is `std_struct_is_byte_writable`, defined once in `lower_layout` and asked by all
        ## four backends, so the child's image here is the image every reader resolves. The
        ## `layout_struct_is_word_stored` branch below stays for a child the byte writer has no store
        ## for (a `[u64; N]`, `str` or enum field) but whose word offsets ARE its §6.1 offsets.
        if smulti and struct_decl_of(cx.decls, cx.src, fts.s, fts.n) >= 0 and layout_kind_is_byte(layout_kind(cx.decls, cx.src, bent.sns, bent.snl, deref(cx.mar))) and std_struct_is_byte_writable(cx.decls, cx.src, fts.s, fts.n, deref(cx.mar)) {
          if sbo < 0 { panic("selfhost: a standard-layout aggregate field write has no byte offset for its child") }
          emit_standard_value(fv, i64(bent.off), sbo, sb, cx, a, nl)
          fw_handled = true
        } else if smulti and struct_decl_of(cx.decls, cx.src, fts.s, fts.n) >= 0 and layout_kind_is_byte(layout_kind(cx.decls, cx.src, bent.sns, bent.snl, deref(cx.mar))) and layout_struct_is_word_stored(cx.decls, cx.src, fts.s, fts.n, deref(cx.mar)) {
          ## An aggregate struct field starts at the shared standard byte offset. For the current
          ## frame representation its word-0 address is expressible when that offset is aligned;
          ## delegate the RHS literal to the same recursive constructor used by a top-level value.
          ## The two extra gates are the same pair `emit_standard_assign` carries: the ROOT must be
          ## the BYTE tier by the ORACLE (a `@packed` root belongs to `emit_packed_assign`), and the
          ## CHILD must be word-stored, because `emit_struct_assign` is the word-granular constructor
          ## and any other child representation would be written by one emitter and read by another.
          ## Other aggregate kinds and unaligned children remain a located fail-loud boundary.
          if sbo < 0 or (sbo / 8) * 8 != sbo { panic("selfhost: a standard-layout aggregate field write needs an 8-byte-aligned child in this slice") }
          if struct_lit_info(fv).is_s {
            emit_struct_assign(fv, bent.off - sbo / 8, sb, cx, a, nl)
            fw_handled = true
          } else { panic("selfhost: a standard-layout aggregate field write needs a struct literal in this slice") }
        } else if smulti {
          panic("selfhost: a standard-layout aggregate field write needs a byte-aware aggregate value path; use indexed byte writes or a supported scalar field")
        } else if sbo >= 0 {
          emit_gas(fv, sb, cx, a, nl)
          push_str(sb, "  popq %rax\n")
          ssz := scalar_byte_size(cx.src, fts.s, fts.n)
          if ssz == 1 { push_str(sb, "  movb %al, -") }
          else if ssz == 2 { push_str(sb, "  movw %ax, -") }
          else if ssz == 4 { push_str(sb, "  movl %eax, -") }
          else { push_str(sb, "  movq %rax, -") }
          push_int(sb, i64((bent.off + 1) * 8) - sbo)
          push_str(sb, "(%rbp)\n")
          fw_handled = true
        }
      } else {
        fw_handled = emit_local_field_agg_store(fv, fslot, fts.s, fts.n, sb, cx, a, nl)
      }
    }
    if fw_handled == false {
      emit_gas(fv, sb, cx, a, nl)
      push_str(sb, "  popq %rax\n  movq %rax, -")
      push_int(sb, (fslot + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
  }
  }
}
## The `Stmt::DerefAssign` arm of `emit_stmts`, moved out verbatim (Step 4.1). A `deref(p) = v` store
## through a pointer. The arm's payload binding is spelled `ptr` at the match site; the parameter is
## `dptr` so it cannot shadow the `ptr(T)` type constructor in its own signature. Caller keeps
## `s = nx`. Touches no module global.
pub emit_st_deref_assign := fn(dptr : ptr(Expr), val : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  vw := deref_store_words(val, cx)
  ## §7 VIEW STORE — the destination pointee is a `str` / `[T]`, i.e. the two-word `{dptr, len}`
  ## PAIR itself, so the store must move BOTH words. The scalar path below moves ONE, and for a
  ## by-ref `str` source (a generic `x : T` parameter at `T = str`, whose slot holds a POINTER to
  ## the caller's pair) that one word is the POINTER TO THE PAIR — a stack address — so a
  ## `Vec(str)` element read back a stale frame address and a garbage length: a silent wrong
  ## value. `emit_str_pair` materializes the pair (dptr deeper, len on top) for every str source
  ## shape (literal, local, by-ref param, field, element, `deref`), then both words are stored at
  ## the ascending pointee offsets the pair READ uses. Gated on the destination pointee resolving
  ## to a view through the generic instance — `src/`'s `deref(p) = v` stores are all scalar or
  ## struct pointees, so this is fixpoint-neutral.
  if call_ret_pointee_unresolved(dptr, cx.decls, cx.src, a) { reject_call_pointee_unresolved(dptr, cx.src) }
  dvps := deref_dest_pointee_span(dptr, cx)
  if dvps.n != 0 and is_view_type(cx.src, dvps.s, dvps.n) {
    emit_str_pair(val, sb, cx, a, nl)
    emit_gas(dptr, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n  popq %rcx\n  popq %rbx\n  movq %rbx, (%rax)\n  movq %rcx, 8(%rax)\n")
  } else if slit_scalar_fields(val, cx) {
    ## storing a STRUCT LITERAL through the pointer (`deref(p) = Pt(x, y)`): evaluate each field
    ## and store to `-(k*8)(%rax)` — the down-growing pointee layout matching the field read. Was
    ## a silent BUG: a literal source fell to the scalar path (deref_store_words returns 1 for a
    ## non-Var) and stored ONE garbage word. The dest dptr is saved on the stack across field
    ## evaluation (a field that is a call would clobber a held reg) and peeked per field. Scalar
    ## fields (word k at index k); a nested/wide field is a follow-up.
    emit_gas(dptr, sb, cx, a, nl)
    mut g := struct_lit_fields(val)
    mut k := 0
    while g != 0 {
      ga := deref(arg_p(g))
      emit_gas(ga.e, sb, cx, a, nl)
      push_str(sb, "  popq %rcx\n  movq (%rsp), %rax\n  movq %rcx, ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax)\n")
      k = k + 1
      g = ga.next
    }
    push_str(sb, "  popq %rax\n")
  } else if elit_scalar_payloads(val, cx) {
    ## storing an ENUM LITERAL with scalar payloads through the pointer (`deref(p) = E.V(x)`): the
    ## discriminant at word 0, each scalar payload at words 1.. — all at `-(k*8)(%rax)`, the
    ## down-growing pointee layout the enum match reads. Was the scalar path → one garbage word.
    ## A struct/str/nested-enum payload is deferred (falls to the slow path). The dest dptr is saved
    ## on the stack and peeked per word (a payload that is a call would clobber a held reg).
    ef := enum_lit_full(val)
    disc := variant_index(cx.decls, cx.src, ef.es, ef.el, ef.vs, ef.vl, deref(cx.mar))
    emit_gas(dptr, sb, cx, a, nl)
    push_str(sb, "  movq $")
    push_int(sb, disc)
    push_str(sb, ", %rcx\n  movq (%rsp), %rax\n  movq %rcx, (%rax)\n")
    mut g := ef.phead
    mut k := 1
    while g != 0 {
      ga := deref(arg_p(g))
      emit_gas(ga.e, sb, cx, a, nl)
      push_str(sb, "  popq %rcx\n  movq (%rsp), %rax\n  movq %rcx, ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax)\n")
      k = k + 1
      g = ga.next
    }
    push_str(sb, "  popq %rax\n")
  } else if vw > 1 {
    ## storing a WHOLE multi-word struct through the pointer: load the destination word-0
    ## address into %rax, then copy each of the struct local's words to `-(k*8)(%rax)` — the
    ## down-growing aggregate layout (word k at a LOWER address), matching the by-ref field
    ## read (`-(fi*8)(%rax)`). The source struct local's word k is at slot `off+k`.
    sv := var_name_span(val)
    ent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, sv.s, sv.n)))
    emit_gas(dptr, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n")
    if ent.is_ref {
      ## the source is a BY-REFERENCE struct (its slot holds a POINTER to the words): load
      ## that pointer into %rbx and copy dptr→dptr, source word k at `-(k*8)(%rbx)`.
      push_str(sb, "  movq -")
      push_int(sb, i64((ent.off + 1) * 8))
      push_str(sb, "(%rbp), %rbx\n")
      for k in 0..vw {
        push_str(sb, "  movq ")
        push_int(sb, i64(k * 8))
        push_str(sb, "(%rbx), %rcx\n  movq %rcx, ")
        push_int(sb, i64(k * 8))
        push_str(sb, "(%rax)\n")
      }
    } else {
      ## the source is a struct LOCAL: its word k is at frame slot `off+k`.
      for k in 0..vw {
        push_str(sb, "  movq -")
        push_frame_word(sb, ent.off, k)
        push_str(sb, "(%rbp), %rcx\n  movq %rcx, ")
        push_int(sb, i64(k * 8))
        push_str(sb, "(%rax)\n")
      }
    }
  } else if ptr_var_struct_words(dptr, cx) > 1 and unchecked bitcast(usize, deref_inner_expr(val)) != 0 {
    ## POINTEE→POINTEE whole-struct store `deref(vd) = deref(vs)` where BOTH `vd` and `vs` are
    ## pointer-to-struct (ek 7) — the generic-container element MOVE (`omap_grow` / `omap_insert`
    ## shift with a struct value type, `V` monomorphized to a multi-word struct). The scalar path
    ## (`deref_store_words` returns 1 for a `deref(…)` source) copied ONLY word 0. Load the source
    ## base into %rbx and the dest base into %rax, then copy each of the pointee struct's words
    ## (`+k*8` — the ascending pointee layout the by-ref field read / `deref(p)` load use). Gated on
    ## the DEST being an ek-7 multi-word struct pointer, so `src/`'s `deref(dp) = deref(sp)` through
    ## a `ptr(mut usize)` (ek 0 → 0 words) stays on the scalar path → fixpoint-neutral.
    dw2 := ptr_var_struct_words(dptr, cx)
    srcp := deref_inner_expr(val)
    emit_gas(srcp, sb, cx, a, nl)
    emit_gas(dptr, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n  popq %rbx\n")
    for k in 0..dw2 {
      push_str(sb, "  movq ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rbx), %rcx\n  movq %rcx, ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax)\n")
    }
  } else if ptr_var_struct_words(dptr, cx) > 1 and expr_is_branch(val) {
    ## `deref(p) = if/match …` into a MULTI-WORD pointee — the scalar store path below moves only
    ## word 0 (a silent word-drop; a struct-lit / var / pointee source is handled by the arms above,
    ## but a BRANCH value is neither). Fail LOUD rather than truncate. Tightly gated on an ek-7
    ## multi-word DEST + an if/match source, so every scalar store (`deref(p) = x`) and the existing
    ## multi-word source paths are unaffected → fixpoint-neutral.
    panic("selfhost: a whole-STRUCT store through a pointer from an if/match BRANCH (`deref(p) = if …`) is unsupported (the scalar store path would drop words) — bind the branch value to a local first (`t := if …`), then `deref(p) = t`")
  } else {
    emit_gas(val, sb, cx, a, nl)
    emit_gas(dptr, sb, cx, a, nl)
    ## Narrow the store to the pointee width for a KNOWN sub-word scalar pointer (`ptr(u8)`
    ## etc.); word-sized / unknown keeps the full 8-byte `movq` (else the 7 neighbouring bytes
    ## are clobbered).
    push_str(sb, "  popq %rax\n  popq %rbx\n")
    emit_deref_store(sb, deref_pointee_bytes(dptr, cx))
  }
}
## The `Stmt::FieldPathAssign` arm of `emit_stmts`, moved out verbatim (Step 4.1). A nested
## `o.i.v = <expr>` store resolved through `field_slot`; the caller keeps `s = nx`.
## Touches no module global.
pub emit_st_field_path_assign := fn(pl : ptr(Expr), v : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  fp := field_place_parts(pl)
  ## `GLOBAL.f1.f2… = val` (any depth) — store into a field of a nested struct field of a
  ## mutable-global struct at `LABEL + off*8` (offset via `global_place`). A SCALAR final field is a
  ## single-word store; a multi-word final field (enum / str / nested struct, `STATE.i.sub = P(…)`)
  ## goes through `emit_global_agg_store`. The default path below writes a LOCAL frame slot
  ## (`field_slot`), a silent no-op for a global base. Write dual of the nested global-field READ.
  mut fpa_done := false
  ## STANDARD BYTE LAYOUT — a scalar leaf of a nested local field path. Resolve the complete
  ## declaration-order byte offset before the old word-slot fallback can count a compressed array
  ## as N separate words. Aggregate leaves remain fail-loud in this scalar path.
  s3wpath := standard_field_path(pl, cx.slots, cx.decls, cx.src, a)
  if s3wpath.ok {
    s3warr := array_elem_span(cx.src, s3wpath.ts, s3wpath.tl)
    mut s3wagg := s3warr.n != 0
    if s3wpath.tl != 0 and (str_at((cx.src + s3wpath.ts), s3wpath.tl) == "str" or struct_decl_of(cx.decls, cx.src, s3wpath.ts, s3wpath.tl) >= 0 or enum_decl_of(cx.decls, cx.src, s3wpath.ts, s3wpath.tl) >= 0) { s3wagg = true }
    if s3wagg { panic("selfhost: a standard-layout nested aggregate field write needs its aggregate store consumer") }
    emit_gas(v, sb, cx, a, nl)
    push_str(sb, "  popq %rax")
    push_str(sb, "\n")
    s3wsz := scalar_byte_size(cx.src, s3wpath.ts, s3wpath.tl)
    if s3wsz == 1 { push_str(sb, "  movb %al, -") }
    else if s3wsz == 2 { push_str(sb, "  movw %ax, -") }
    else if s3wsz == 4 { push_str(sb, "  movl %eax, -") }
    else { push_str(sb, "  movq %rax, -") }
    push_int(sb, i64((s3wpath.root + 1) * 8) - s3wpath.bo)
    push_str(sb, "(%rbp)")
    push_str(sb, "\n")
    fpa_done = true
  }
  ## P1-CLAYOUT S3(d) — the WRITE dual of the byte-tier array-element read: `xs[i].inner.b = v` (any
  ## depth). Same resolver, same offsets, opposite direction — which is the point: a place written here
  ## and read by the `s3dr` arm cannot disagree, because both take every hop from
  ## `layout_field_offset_bytes` and the element address from `emit_index_addr`. The store is SIZED to
  ## the leaf's own width, so writing a `u16` leaf leaves its neighbours alone; a `movq` here would
  ## clobber the next three fields. Placed before the two word-offset arms below (they compose
  ## `field_word_offset * 8`) and after the `s3wpath` block, whose `Var` root can never be an `Index`.
  if fpa_done == false {
    s3dw := std_idx_path(pl, cx.slots, cx.decls, cx.src, a)
    if s3dw.ok {
      if std_idx_leaf_is_agg(cx.decls, cx.src, s3dw.ts, s3dw.tl) {
        panic("selfhost: writing a whole AGGREGATE field of a byte-layout array element (`xs[i].inner = …` where the field is a struct, str, enum or array) has no byte-precise store in this slice — write a scalar leaf, index a byte array element, or build the whole element (`xs[i] = Elem(…)`)")
      }
      emit_gas(v, sb, cx, a, nl)
      emit_index_addr(s3dw.arr, s3dw.idx, sb, cx, a, nl)
      emit_packed_store_rax(sb, scalar_byte_size(cx.src, s3dw.ts, s3dw.tl), s3dw.bo, false)
      fpa_done = true
    }
  }
  ## `local.array[index].field = value` is represented as a FieldPathAssign whose base is
  ## `Index(Field(local, array), index)`. Reuse the array-field address emitter and the
  ## element-type-aware field offset resolver for this deeper fixed-array path.
  ## GUARDED by `fpa_done`, like every other arm in this fn: the standard-byte block above already
  ## emitted a complete store when it fired, and a second emission here would store the value twice
  ## (to two different places). Unreachable today only because `standard_field_path` refuses an
  ## `Index` root — one place-form away from a real double emission.
  fidx := field_base_index(fp.base)
  if fpa_done == false and fidx.is_ix {
    ffib := field_index_base(fidx.arr, cx)
    if ffib.is_fld {
      foff := idx_field_index(fidx.arr, fidx.idx, fp.fs, fp.fl, cx)
      emit_gas(v, sb, cx, a, nl)
      emit_idx_field_addr(fidx.arr, fidx.idx, foff * 8, sb, cx, nl)
      push_str(sb, "  popq %rbx\n  movq %rbx, (%rax)\n")
      fpa_done = true
    }
  }
  ## `xs[i].agg1.agg2….leaf = v` — a DEEPER array-element nested-field WRITE (`fp.base` a `Field`
  ## chain rooted at an array-element `Index`). The store dual of the `ddif` READ: compose the
  ## COMBINED element→field word offset, emit the value, compute the leaf ADDRESS, store it. The
  ## default `field_slot` fallback returns -1 for this shape → a store to `-0(%rbp)` (corrupts the
  ## saved frame pointer and DROPS the write, a silent no-op). Scalar leaf only; a multi-word /
  ## non-plain-struct chain already failed loud in `resolve_deep_idx_field`.
  if fpa_done == false {
    wddif := resolve_deep_idx_field(fp.base, fp.fs, fp.fl, cx)
    if wddif.found {
      emit_gas(v, sb, cx, a, nl)
      emit_idx_field_addr(wddif.arr, wddif.idx, wddif.woff * 8, sb, cx, nl)
      push_str(sb, "  popq %rbx\n  movq %rbx, (%rax)\n")
      fpa_done = true
    }
  }
  wgp := global_place(pl, cx, a)
  if wgp.found and global_place_scalar(wgp.ts, wgp.tl, cx) {
    emit_gas(v, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n  movq %rax, ")
    emit_global_label(sb, cx.decls, cx.src, wgp.gs, wgp.gn)
    push_str(sb, "+")
    push_int(sb, wgp.off * 8)
    push_str(sb, "(%rip)\n")
    fpa_done = true
  } else if wgp.found {
    fpa_done = emit_global_agg_store(v, wgp.gs, wgp.gn, wgp.off, wgp.ts, wgp.tl, sb, cx, a, nl)
  }
  ## `deref(p).field = v` / `deref(node.next).field = v` — a scalar-field WRITE THROUGH a pointer (the
  ## store dual of the `deref(p).f` READ at the `dsb`/`dcf`/`dfps` arms). The default `field_slot`
  ## fallback returns -1 for a `Deref` base, so it stored to `-0(%rbp)` — corrupting the saved frame
  ## pointer and dropping the write (a silent no-op; the parser also previously mis-parsed this shape).
  ## Resolve the pointee struct — an ek-7 ptr LOCAL/PARAM (`wdsb`), a `deref(<call>)` (`wdcf`), or a
  ## `deref(<ptr field>)` (`wdfps`) — evaluate the value, load the pointer, and store the field at
  ## `fi*8(ptr)` (the ASCENDING pointee layout the read uses). Scalar-word field only; an AGGREGATE
  ## (str/struct/enum) field through a pointer is a fail-loud panic, never a silent word-drop.
  if fpa_done == false {
    wdsb := deref_struct_span(fp.base, cx.slots, cx.src)
    wdcf := deref_call_struct_span(fp.base, cx.decls, cx.src, deref(cx.mar))
    wdfps := deref_field_ptrstruct_span(fp.base, cx.slots, cx.decls, cx.src, deref(cx.mar))
    ## `deref(s[i]).field = v` — a WRITE through a POINTER element of a slice/array (`eek == 7`, a
    ## `[ptr(mut b0), …]` slice). The store dual of the `dix` inline READ: `deref_inner_expr(fp.base)`
    ## = the Index `s[i]`, whose scalar read yields the element POINTER, so the shared `else` branch
    ## below (`emit_gas(deref_inner_expr(fp.base))` → pointer) stores at `wfi*8(ptr)` correctly.
    wdix := deref_index_ptrstruct_span(fp.base, cx.slots, cx.src)
    ## `deref(deref(pp)).field = v` — a WRITE through a POINTER-TO-POINTER-to-struct (depth-2). The
    ## store dual of the `dddx` READ: `deref_inner_expr(fp.base)` = the inner `deref(pp)`, whose value
    ## is the `&Struct` pointer, so the shared `else` branch stores at `wfi*8(ptr)`.
    wddx := deref_deref_struct_span(fp.base, cx.slots, cx.src)
    ## GENERIC `deref(s[i]).field = v` over a `Slice(ptr(mut T))` PARAM — the pointee `T` is erased in
    ## the param (no per-instance mono binding), so fail LOUD rather than DROP the write (the default
    ## `field_slot` fallback returns -1 → a store to `-0(%rbp)`, a silent no-op). The concrete eek-7
    ## case (`wdix`) is handled and never reaches this guard.
    if wdix.n == 0 and wddx.n == 0 and deref_index_ptr_param_unresolved(fp.base, cx.slots, cx.src) { panic("selfhost: WRITE `deref(s[i]).field = v` over a generic `Slice(ptr(mut T))` PARAM is not yet supported (the pointee type is erased in the param — pass the element pointer across a call and write in the callee, or use a concrete-typed slice)") }
    mut wsp := CSpan(s = 0, n = 0)
    if wdsb.n != 0 { wsp = wdsb } else if wdcf.n != 0 { wsp = wdcf } else if wdfps.n != 0 { wsp = wdfps } else if wdix.n != 0 { wsp = wdix } else if wddx.n != 0 { wsp = wddx }
    if wsp.n != 0 {
      wfty := field_type_span(cx.decls, cx.src, wsp.s, wsp.n, fp.fs, fp.fl, deref(cx.mar))
      wagg := wfty.n != 0 and (str_at((cx.src + wfty.s), wfty.n) == "str" or struct_decl_of(cx.decls, cx.src, wfty.s, wfty.n) >= 0 or enum_decl_of(cx.decls, cx.src, wfty.s, wfty.n) >= 0)
      wfi := field_word_offset(cx.decls, cx.src, wsp.s, wsp.n, fp.fs, fp.fl, deref(cx.mar))
      if wagg and cx.agg_tmp >= 0 {
        ## MULTI-WORD field (str/struct/enum) written THROUGH a pointer (`deref(p).i = mk()` /
        ## `deref(p).i = if c { … }`). The scalar store below keeps only word 0 — a payload-drop — so
        ## deliver ALL the field's words: materialize the RHS aggregate into the agg-temp block
        ## (down-growing, word j at `-(agg_tmp-j+1)*8`), load the pointee pointer into %r13, then copy
        ## the block's `wfw` words ASCENDING into `(wfi+j)*8(%r13)` (the pointee field layout the
        ## nested READ uses). A struct/enum/str LITERAL, a struct/enum/str-returning CALL, an if/match
        ## branch, AND a struct VAR (both a local one and a by-ref param, read through its pointer) are
        ## all delivered whole; only a wide-SRET / tuple / generic-erased CALL RHS stays fail-loud.
        ## `src/`+`lib/` never write a multi-word field through a pointer this way → fixpoint-neutral.
        wis_str := str_at((cx.src + wfty.s), wfty.n) == "str"
        wis_enum := enum_decl_of(cx.decls, cx.src, wfty.s, wfty.n) >= 0
        mut wfw : usize = 0
        if wis_str { wfw = 2 } else if wis_enum { wfw = 1 + enum_inst_words(cx.decls, cx.src, wfty.s, wfty.n, deref(cx.mar)) } else { wfw = struct_words(cx.decls, cx.src, wfty.s, wfty.n, deref(cx.mar)) }
        mut wdel := false
        if struct_lit_info(v).is_s { emit_struct_assign(v, cx.agg_tmp, sb, cx, a, nl); wdel = true }
        else if enum_lit_info(v).is_e { emit_enum_assign(v, cx.agg_tmp, sb, cx, a, nl); wdel = true }
        else if str_lit_info(v).is_s { emit_str_assign(v, cx.agg_tmp, sb); wdel = true }
        else if struct_ret_call(v, cx.decls, cx.src, a) and not sret_ret_call(v, cx.decls, cx.src, a) {
          emit_struct_value(v, sb, cx, a, nl)
          for j in 0..wfw { push_str(sb, "  movq "); emit_retreg(sb, j); push_str(sb, ", -"); push_int(sb, i64((usize(cx.agg_tmp) - j + 1) * 8)); push_str(sb, "(%rbp)\n") }
          wdel = true
        }
        else if enum_ret_call_d(v, cx.decls, cx.src, a) and not enum_sret_ret_call(v, cx.decls, cx.src, a) {
          emit_enum_value(v, sb, cx, a, nl)
          for j in 0..wfw { push_str(sb, "  movq "); emit_retreg(sb, j); push_str(sb, ", -"); push_int(sb, i64((usize(cx.agg_tmp) - j + 1) * 8)); push_str(sb, "(%rbp)\n") }
          wdel = true
        }
        else if str_ret_call(v, cx.decls, cx.src, deref(cx.mar)) {
          emit_struct_value(v, sb, cx, a, nl)
          for j in 0..2 { push_str(sb, "  movq "); emit_retreg(sb, j); push_str(sb, ", -"); push_int(sb, i64((usize(cx.agg_tmp) - j + 1) * 8)); push_str(sb, "(%rbp)\n") }
          wdel = true
        }
        else if var_agg_info(v, cx.slots, cx.src).ek == 2 {
          ## struct VAR RHS (`deref(p).i = nv`) — stage the var's `wfw` words into the agg-temp block.
          ## Each word is a straight-line `movq` pair emitted directly in THIS emit arm; the `for j`
          ## loop runs at COMPILE time (in a pre-existing emit fn the seed lowers correctly), so the
          ## emitted code is fully UNROLLED — NOT the extracted-helper loop the seed collapses to a
          ## single word. A LOCAL struct's word k is contiguous in the frame at `push_frame_word(off,
          ## k)`; a BY-REF struct PARAM (`v : Inner` is passed by-ref = a POINTER to the caller's
          ## Inner) has its word k at `k*8(vptr)` — load the param pointer (emit_agg_base_addr → %rax)
          ## and read THROUGH it (the same ascending pointee layout the by-ref Field read/write uses).
          wvn := var_name_span(v)
          wvent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, wvn.s, wvn.n)))
          if wvent.is_ref {
            emit_agg_base_addr(wvent, sb)              ## v's pointer → %rax
            for j in 0..wfw {
              push_str(sb, "  movq ")
              push_int(sb, i64(j * 8))
              push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
              push_int(sb, i64((usize(cx.agg_tmp) - j + 1) * 8))
              push_str(sb, "(%rbp)\n")
            }
          } else {
            for j in 0..wfw {
              push_str(sb, "  movq -")
              push_frame_word(sb, wvent.off, j)
              push_str(sb, "(%rbp), %rcx\n  movq %rcx, -")
              push_int(sb, i64((usize(cx.agg_tmp) - j + 1) * 8))
              push_str(sb, "(%rbp)\n")
            }
          }
          wdel = true
        }
        else {
          wmak := match_if_agg_kind(v, cx.decls, cx.src, a)
          if wmak.kind != 0 {
            wmi := match_info(v)
            if wmi.is_m { emit_val_match_to_local(wmi.scrut, wmi.head, cx.agg_tmp, sb, cx, a, nl) }
            else { wii := if_info(v); emit_val_if_to_local(wii.cond, wii.then_e, wii.else_e, cx.agg_tmp, sb, cx, a, nl) }
            wdel = true
          }
        }
        if wdel == false { panic("selfhost: an AGGREGATE-field write through a pointer (`deref(p).f = v`) from this RHS kind (a wide-SRET / tuple / generic-erased call) is unsupported — bind the RHS to a local first, or use a field literal") }
        if wdsb.n != 0 {
          wpv := deref_var_span(fp.base)
          wpent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, wpv.s, wpv.n)))
          push_str(sb, "  movq -"); push_int(sb, i64((wpent.off + 1) * 8)); push_str(sb, "(%rbp), %r13\n")
        } else {
          emit_gas(deref_inner_expr(fp.base), sb, cx, a, nl)
          push_str(sb, "  popq %r13\n")
        }
        for j in 0..wfw {
          push_str(sb, "  movq -"); push_int(sb, i64((usize(cx.agg_tmp) - j + 1) * 8)); push_str(sb, "(%rbp), %rcx\n  movq %rcx, ")
          push_int(sb, (wfi + i64(j)) * 8); push_str(sb, "(%r13)\n")
        }
        fpa_done = true
      } else {
        if wagg { panic("selfhost: an AGGREGATE-field (str/struct/enum) write through a pointer (`deref(p).f = v`) is unsupported here (no agg-temp block reserved) — bind the pointee to a local, or write scalar fields") }
        emit_gas(v, sb, cx, a, nl)              ## value → stack
        if wdsb.n != 0 {
          wpv := deref_var_span(fp.base)
          wpent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, wpv.s, wpv.n)))
          push_str(sb, "  movq -")
          push_int(sb, i64((wpent.off + 1) * 8))
          push_str(sb, "(%rbp), %rax\n")
        } else {
          emit_gas(deref_inner_expr(fp.base), sb, cx, a, nl)   ## pointer → stack
          push_str(sb, "  popq %rax\n")
        }
        push_str(sb, "  popq %rcx\n  movq %rcx, ")
        push_int(sb, wfi * 8)
        push_str(sb, "(%rax)\n")
        fpa_done = true
      }
    }
  }
  ## `<ptr-root>.f1…leaf = v` (depth>=2) — a nested SCALAR field WRITE THROUGH a pointer: a BY-REF
  ## struct param (`a.b.pb = v`) or `deref(p).b.pb = v`. The store dual of the `resolve_nested_ptr_field`
  ## READ. The DEEP-CHAIN LOCAL path below (`field_slot`) resolves a by-ref/deref base to -1 → a store
  ## to `-0(%rbp)` (corrupts the saved frame pointer, DROPS the write — a silent no-op). Load the
  ## pointer (`movq -(off+1)*8(%rbp)`), then store the leaf at its ASCENDING pointee word offset.
  ## Scalar leaf only; a multi-word / @packed chain already failed loud in `resolve_nested_ptr_field`.
  if fpa_done == false {
    wnpf := resolve_nested_ptr_field(fp.base, fp.fs, fp.fl, cx)
    if wnpf.found {
      wnent := deref(svec_at(SlotEntry, cx.slots, wnpf.ent_idx))
      emit_gas(v, sb, cx, a, nl)                 ## value → stack
      push_str(sb, "  movq -")
      push_int(sb, i64((wnent.off + 1) * 8))
      push_str(sb, "(%rbp), %rax\n  popq %rbx\n  movq %rbx, ")
      push_int(sb, wnpf.woff * 8)
      push_str(sb, "(%rax)\n")
      fpa_done = true
    }
  }
  ## DEEP-CHAIN LOCAL place `o.mid.inner = v` (`fp.base` a nested `Field`): resolve the final
  ## field's word-0 frame slot via `field_slot` (walks the nested base recursively → the
  ## down-growing inline layout) and its declared TYPE via `base_struct_span` of the parent. A
  ## MULTI-WORD final field (str/enum/nested struct) delivers ALL its words through the shared
  ## `emit_local_field_agg_store` — the scalar default below stored only WORD 0, leaving the
  ## field's other words STALE (a Priority-1 silent miscompile, the deep-chain dual of the
  ## single-hop `FieldAssign` multi-word field store). A single scalar word keeps the store below
  ## (byte-identical). `src/`+`lib/` do no multi-word deep-chain field whole-assign → neutral.
  if fpa_done == false {
    wfslot := field_slot(fp.base, fp.fs, fp.fl, cx)
    wbt := base_struct_span(fp.base, cx)
    if wfslot >= 0 and wbt.n != 0 {
      wfts := field_type_span(cx.decls, cx.src, wbt.s, wbt.n, fp.fs, fp.fl, deref(cx.mar))
      if wfts.n != 0 {
        ## A deep-chain `str`/`enum` FINAL field is unsupported END-TO-END — even the nested READ
        ## (`o.mid.name` / `match o.mid.c`) is not lowered — so a whole-assign here can only produce
        ## garbage; refuse it LOUDLY rather than emit a word-0-only (or wrongly-staged) silent store.
        ## The multi-word STRUCT final field IS delivered (via the shared helper); a scalar field
        ## falls to the single-word store below. Flatten a str/enum deep field to a single hop.
        if str_at((cx.src + wfts.s), wfts.n) == "str" or enum_decl_of(cx.decls, cx.src, wfts.s, wfts.n) >= 0 {
          panic("selfhost: a deep-chain str/enum FINAL field whole-assign (`o.mid.f = v`) is unsupported (the nested str/enum field READ is not lowered either) — flatten to a single hop or bind the inner struct to a local")
        }
        if emit_local_field_agg_store(v, wfslot, wfts.s, wfts.n, sb, cx, a, nl) { fpa_done = true }
      }
    }
  }
  if fpa_done == false {
    fslot := field_slot(fp.base, fp.fs, fp.fl, cx)
    ## `field_slot` answers -1 for a place this resolver cannot reach, and `-(-1+1)*8` is `-0(%rbp)`:
    ## the store lands on the SAVED FRAME POINTER and the write is silently dropped. Measured:
    ## `p := ptr(mut o.inner)` (whose address is correct) then `deref(p).x = 41` emitted
    ## `movq %rax, -0(%rbp)` and reading `o.inner.x` back gave the OLD 20 — for a byte-layout struct
    ## and, identically and pre-existing, for an ordinary `struct { pad : u64, inner : Inner }`. Every
    ## arm above that CAN resolve such a place has already run, so reaching here with a negative slot
    ## is exactly the dropped-write case. Reject it located; a store to `-0(%rbp)` is never intended.
    if fslot < 0 {
      lower_show_src_line(cx.src, fp.fs)
      panic("selfhost: this nested field WRITE (the source line above) has no resolvable frame slot — emitting it would store over the saved frame pointer and DROP the write. A pointer taken into an inner aggregate (`p := ptr(mut o.inner)` then `deref(p).f = v`) does not carry its pointee's layout yet; write through the outer place (`o.inner.f = v`) instead.")
    }
    emit_gas(v, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n  movq %rax, -")
    push_int(sb, (fslot + 1) * 8)
    push_str(sb, "(%rbp)\n")
  }
}
## The `Stmt::IndexFieldAssign` arm of `emit_stmts`, moved out verbatim (Step 4.1). An `a[i].f = v`
## element-field store. READS the module global `cx.vchk` (the bounds-check gate) and writes no
## global, so no state decision is needed; the caller keeps `s = nx`.
pub emit_st_index_field_assign := fn(fia : ptr(Expr), fii : ptr(Expr), ifs : usize, ifl : usize, fiv : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  ## `ARR[i].f = v` on a mutable STRUCT-array global — store into `.data` at
  ## `LABEL + i*stride*8 + fieldidx*8` (ascending). The global has no frame slot, so this precedes
  ## the frame `emit_idx_field_addr` path (which would compute a bogus %rbp-relative address).
  wivn := var_name_span(fia)
  wgmv := if wivn.n != 0 { mut_global_value(cx.decls, cx.src, wivn.s, wivn.n) } else { unchecked bitcast(ptr(Expr), 0) }
  mut w_done := false
  if unchecked bitcast(usize, wgmv) != 0 and array_lit_info(wgmv).is_a {
    wesli := struct_lit_info(arg_expr_at(array_lit_info(wgmv).ehead, 0, a))
    if wesli.is_s {
      wfi := struct_field_index(cx.decls, cx.src, wesli.ss, wesli.sl, ifs, ifl, a)
      if wfi >= 0 {
        wstride := struct_words(cx.decls, cx.src, wesli.ss, wesli.sl, a)
        emit_gas(fiv, sb, cx, a, nl)                 ## value → stack
        emit_gas(fii, sb, cx, a, nl)                 ## index → stack (top)
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, wivn.s, wivn.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        ## CHECKED BOUNDS (I11 §358): trap an out-of-range index before scaling. Was missing →
        ## `TAB[i].f = v` wrote out of bounds silently.
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(array_lit_info(wgmv).nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  imulq $")
        push_int(sb, i64(wstride * 8))
        push_str(sb, ", %rcx\n  addq %rcx, %rax\n  popq %rbx\n  movq %rbx, ")
        push_int(sb, wfi * 8)
        push_str(sb, "(%rax)\n")
        w_done = true
      }
    }
  }
  ## P1-CLAYOUT S3(d) — the DEPTH-1 byte-tier element field WRITE `xs[i].f = v`. Claimed before the
  ## word-offset tail below, which scales `idx_field_index` (a field INDEX) by 8 and would place a
  ## `u16` second field at byte 8 instead of byte 2, with a full-word store over its neighbours.
  if w_done == false {
    s3d1 := std_idx_one(fia, ifs, ifl, cx)
    if s3d1.ok {
      if std_idx_leaf_is_agg(cx.decls, cx.src, s3d1.ts, s3d1.tl) {
        panic("selfhost: writing a whole AGGREGATE field of a byte-layout array element (`xs[i].inner = …` where the field is a struct, str, enum or array) has no byte-precise store in this slice — write a scalar leaf, index a byte array element, or build the whole element (`xs[i] = Elem(…)`)")
      }
      emit_gas(fiv, sb, cx, a, nl)
      emit_index_addr(fia, fii, sb, cx, a, nl)
      emit_packed_store_rax(sb, scalar_byte_size(cx.src, s3d1.ts, s3d1.tl), s3d1.bo, false)
      w_done = true
    }
  }
  if w_done == false {
    emit_gas(fiv, sb, cx, a, nl)
    ifoff := idx_field_index(fia, fii, ifs, ifl, cx) * 8
    emit_idx_field_addr(fia, fii, ifoff, sb, cx, nl)
    push_str(sb, "  popq %rbx\n  movq %rbx, (%rax)\n")
  }
}
## The `Stmt::IndexAssign` arm of `emit_stmts`, moved out verbatim (Step 4.1). An `arr[i] = v`
## element store. READS the module global `cx.vchk` and writes no global. The arm's
## byte-packed fast path used `s = nx ; continue` to skip the rest; here it is a bare `return`,
## and the caller keeps the single `s = nx`.
pub emit_st_index_assign := fn(ib : ptr(Expr), ii : ptr(Expr), iv : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  ## BYTE-PACKED LOCAL ARRAY / TYPED BYTE-SLICE WRITE. The address helper leaves the exact byte
  ## address in %rax; evaluate the value first so index lowering cannot consume it, then store
  ## only `%bl` and preserve the seven neighbouring bytes.
  pbe := packed_byte_base_entry(ib, cx)
  pbfe := packed_byte_field_eek(ib, cx)
  sbfe := standard_byte_field_eek(ib, cx)
  ## P1-CLAYOUT S3(d) — `xs[i].data[j] = v`: the store dual of the byte-tier element's byte-array read.
  ## `emit_index_addr` leaves the exact byte address, so a single `movb` is the whole store and the
  ## seven neighbouring bytes are preserved.
  sdbe := std_idx_byte_field_eek(ib, cx.slots, cx.decls, cx.src, a)
  tbfe := tuple_byte_component_base(ib, cx)
  if pbe >= 0 or pbfe != 0 or sbfe != 0 or sdbe != 0 or tbfe.ok {
    emit_gas(iv, sb, cx, a, nl)
    emit_index_addr(ib, ii, sb, cx, a, nl)
    push_str(sb, "  popq %rbx\n  movb %bl, (%rax)\n")
    return
  }
  ## (TYP-6 / D69) the `xs[i] = <aggregate>` into a scalar-element array soundness net moved UP into
  ## `sema::check_program` (build-path gate).
  ## `GLOBAL[i] = v` on a MUTABLE array global (`TABLE[i] = v`): store into `.data` at
  ## `LABEL + i*8`. Checked FIRST (a module global has no frame slot for `emit_index_addr`).
  gaib := var_name_span(ib)
  gaiv := if gaib.n != 0 { mut_global_value(cx.decls, cx.src, gaib.s, gaib.n) } else { unchecked bitcast(ptr(Expr), 0) }
  mut iga_done := false
  if unchecked bitcast(usize, gaiv) != 0 {
    ## An `embed(...)` initializer is a StrLit, not an ArrayLit. Claim an explicitly typed byte
    ## global here before the ArrayLit-only aggregate ladder below; otherwise it would fall through
    ## to the frame-slot address path and write nowhere near the global.
    if not array_lit_info(gaiv).is_a and global_array_byte_eek(cx.decls, cx.src, gaib.s, gaib.n) != 0 {
      gnel := global_array_len(cx.decls, cx.src, gaib.s, gaib.n, gaiv)
      emit_gas(iv, sb, cx, a, nl)
      emit_gas(ii, sb, cx, a, nl)
      push_str(sb, "  leaq ")
      emit_global_label(sb, cx.decls, cx.src, gaib.s, gaib.n)
      push_str(sb, "(%rip), %rax\n  popq %rcx\n")
      if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(gnel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
      push_str(sb, "  addq %rcx, %rax\n  popq %rbx\n  movb %bl, (%rax)\n")
      iga_done = true
    }
    if array_lit_info(gaiv).is_a {
      ## An explicitly typed BYTE array global keeps the same scalar indexed-assignment ABI
      ## (value + index on the evaluation stack), but its destination is one byte per element.
      ## Claim it before the aggregate/word-global ladder below; the latter would otherwise
      ## emit a word store at `LABEL + i*8`, corrupting adjacent elements.
      gbyte := global_array_byte_eek(cx.decls, cx.src, gaib.s, gaib.n)
      if gbyte != 0 {
        emit_gas(iv, sb, cx, a, nl)                 ## value on the stack
        emit_gas(ii, sb, cx, a, nl)                 ## index on top
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, gaib.s, gaib.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(array_lit_info(gaiv).nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  addq %rcx, %rax\n  popq %rbx\n  movb %bl, (%rax)\n")
        iga_done = true
      }
      gaes := struct_lit_info(arg_expr_at(array_lit_info(gaiv).ehead, 0, a))
      sivl := struct_lit_info(iv)
      ## RHS forms this GLOBAL struct-element path supports beyond a struct LITERAL. A struct
      ## GLOBAL array has NO frame slot, so the local-array whole-element arm below (gated on a
      ## slot with `ek == 5`) can never claim it; without these the write fell to the generic
      ## `emit_index_addr` tail, which resolved the global name to slot 0 and stored ONE word at a
      ## bogus %rbp offset — the store vanished and the ORIGINAL `.data` words read back (a silent
      ## miscompile). `rv_arrname_elem_struct_span`'s riscv64 twin is the reference model.
      gaivag := var_agg_info(iv, cx.slots, cx.src)
      mut gavref := true
      if gaivag.ek == 2 or gaivag.ek == 3 {
        gavvn := var_name_span(iv)
        gavref = deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, gavvn.s, gavvn.n))).is_ref
      }
      ## an ENUM-element array GLOBAL (`mut GE := [E.A(1), …]`): element stride `1 + enum_inst_words`.
      gaen := global_arr_enum(cx.decls, cx.src, gaiv, a)
      gaeli := enum_lit_info(iv)
      gavok := gaes.is_s and gaivag.ek == 2 and not gavref
      gacok := gaes.is_s and cx.agg_tmp >= 0 and struct_ret_call(iv, cx.decls, cx.src, a) and not sret_ret_call(iv, cx.decls, cx.src, a)
      if gaes.is_s and sivl.is_s and cx.agg_tmp >= 0 {
        ## `ARR[i] = Pt(…)` — a whole STRUCT-element write to a struct-array global. Build the
        ## struct value in the down-growing agg-temp, then copy its `stride` words into `.data`
        ## element i (ASCENDING: base LABEL+i*stride*8, word k at +k*8).
        gastride := struct_words(cx.decls, cx.src, gaes.ss, gaes.sl, a)
        emit_struct_assign(iv, cx.agg_tmp, sb, cx, a, nl)   ## struct-lit → agg_tmp
        emit_gas(ii, sb, cx, a, nl)                          ## index → stack
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, gaib.s, gaib.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        ## CHECKED BOUNDS (I11 §358): trap an out-of-range index into the mutable-global STRUCT array
        ## before scaling. Was missing → `TAB[i] = P(…)` wrote out of bounds silently.
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(array_lit_info(gaiv).nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  imulq $")
        push_int(sb, i64(gastride * 8))
        push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
        mut gak := 0
        while gak < gastride {
          push_str(sb, "  movq -")
          push_int(sb, i64((usize(cx.agg_tmp) - gak + 1) * 8))
          push_str(sb, "(%rbp), %rdx\n  movq %rdx, ")
          push_int(sb, i64(gak * 8))
          push_str(sb, "(%r13)\n")
          gak += 1
        }
        iga_done = true
      } else if gavok {
        ## `ARR[i] = q` — a whole STRUCT-element write to a struct-array GLOBAL from a NON-ref
        ## struct LOCAL/param `q`. Element ADDRESS first (LABEL + i*stride*8, bounds-checked) into
        ## %r13, then copy `q`'s `stride` FRAME words (word k at `push_frame_word`) into the
        ## element ASCENDING (word k at `+k*8`) — the `.data` twin of the local-array VAR arm
        ## below. Width-agnostic: a wide (>7-word) element is just a longer copy.
        gavstr := struct_words(cx.decls, cx.src, gaes.ss, gaes.sl, a)
        gavvn2 := var_name_span(iv)
        gavent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, gavvn2.s, gavvn2.n)))
        emit_gas(ii, sb, cx, a, nl)                          ## index → stack
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, gaib.s, gaib.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(array_lit_info(gaiv).nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  imulq $")
        push_int(sb, i64(gavstr * 8))
        push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
        mut gavk := 0
        while gavk < gavstr {
          push_str(sb, "  movq -")
          push_frame_word(sb, gavent.off, gavk)
          push_str(sb, "(%rbp), %rdx\n  movq %rdx, ")
          push_int(sb, i64(gavk * 8))
          push_str(sb, "(%r13)\n")
          gavk += 1
        }
        iga_done = true
      } else if gacok {
        ## `ARR[i] = mk()` — a struct-RETURNING CALL RHS into a struct-array GLOBAL. The call has
        ## no frame home, so land its `stride` returned words (retreg k) in the agg-temp block
        ## first, then copy them into `.data` element i — the same two-step the LITERAL arm uses.
        ## A wide (>7-word) SRET call is excluded and stays fail-loud below.
        gacstr := struct_words(cx.decls, cx.src, gaes.ss, gaes.sl, a)
        emit_struct_value(iv, sb, cx, a, nl)
        for gck in 0..gacstr {
          push_str(sb, "  movq ")
          emit_retreg(sb, gck)
          push_str(sb, ", -")
          push_int(sb, i64((usize(cx.agg_tmp) - gck + 1) * 8))
          push_str(sb, "(%rbp)\n")
        }
        emit_gas(ii, sb, cx, a, nl)                          ## index → stack
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, gaib.s, gaib.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(array_lit_info(gaiv).nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  imulq $")
        push_int(sb, i64(gacstr * 8))
        push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
        mut gack := 0
        while gack < gacstr {
          push_str(sb, "  movq -")
          push_int(sb, i64((usize(cx.agg_tmp) - gack + 1) * 8))
          push_str(sb, "(%rbp), %rdx\n  movq %rdx, ")
          push_int(sb, i64(gack * 8))
          push_str(sb, "(%r13)\n")
          gack += 1
        }
        iga_done = true
      } else if gaen.is_e and gaeli.is_e and cx.agg_tmp >= 0 {
        ## `GE[i] = E.V(…)` — a whole ENUM-element write to an enum-array global from a LITERAL.
        ## Materialize `[disc, payload…]` in the down-growing agg-temp (`emit_enum_assign`, the
        ## same primitive the LOCAL enum-array element write uses), then copy the element's
        ## `stride` words into `.data` at `LABEL + i*stride*8` (word k at `+k*8`, ASCENDING).
        ## Was a SILENT one-word store at `LABEL + i*8` (the scalar arm below) — mid-element.
        emit_enum_assign(iv, cx.agg_tmp, sb, cx, a, nl)
        emit_gas(ii, sb, cx, a, nl)                          ## index → stack
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, gaib.s, gaib.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(gaen.nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  imulq $")
        push_int(sb, i64(gaen.stride * 8))
        push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
        mut gaek := 0
        while gaek < gaen.stride {
          push_str(sb, "  movq -")
          push_int(sb, i64((usize(cx.agg_tmp) - gaek + 1) * 8))
          push_str(sb, "(%rbp), %rdx\n  movq %rdx, ")
          push_int(sb, i64(gaek * 8))
          push_str(sb, "(%r13)\n")
          gaek += 1
        }
        iga_done = true
      } else if gaen.is_e and gaivag.ek == 3 and not gavref and 1 + enum_inst_words(cx.decls, cx.src, gaivag.s, gaivag.n, a) == gaen.stride {
        ## `GE[i] = e` — a whole ENUM-element write from a NON-ref enum LOCAL/param. Element
        ## ADDRESS first (LABEL + i*stride*8, bounds-checked), then `e`'s `stride` FRAME words
        ## (word k at `push_frame_word`) copied in ASCENDING — the enum twin of the struct-VAR
        ## arm above. The width equality gate keeps a differently-shaped enum var off this path
        ## (it falls to the fail-loud terminal below rather than over/under-copying).
        gaevn := var_name_span(iv)
        gaeent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, gaevn.s, gaevn.n)))
        emit_gas(ii, sb, cx, a, nl)                          ## index → stack
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, gaib.s, gaib.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(gaen.nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  imulq $")
        push_int(sb, i64(gaen.stride * 8))
        push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
        mut gaevk := 0
        while gaevk < gaen.stride {
          push_str(sb, "  movq -")
          push_frame_word(sb, gaeent.off, gaevk)
          push_str(sb, "(%rbp), %rdx\n  movq %rdx, ")
          push_int(sb, i64(gaevk * 8))
          push_str(sb, "(%r13)\n")
          gaevk += 1
        }
        iga_done = true
      } else if gaen.is_e {
        ## FAIL-LOUD terminal for an ENUM-element array GLOBAL: every arm past this point is
        ## width-blind (the scalar arm would store ONE word at `LABEL + i*8`, mid-element — a
        ## silent miscompile). Reached by an enum-RETURNING call, a by-ref enum var, a global→
        ## global element copy and an if/match-expression RHS. Bind it to a local first.
        panic("selfhost: `GE[i] = <enum>` into a module-level ENUM-element array GLOBAL from this RHS kind (a call result, a by-ref var, a global element read, or an if/match expression) is not yet supported — bind it to a local first (`t := <rhs>; GE[i] = t`). [fail-loud guard: never a silent mid-element store]")
      } else if gaes.is_s {
        ## FAIL-LOUD terminal for a struct-element array GLOBAL: no later arm can claim it (a
        ## global has no frame slot), and the generic tail below would emit a bogus single-word
        ## %rbp store — a SILENT no-op. Reached by a global→global element copy (`GS[i] = GT[j]`),
        ## a by-ref var, a wide-SRET call, and an if/match-expression RHS. Bind to a local first.
        panic("selfhost: `ARR[i] = <aggregate>` into a module-level struct-element array GLOBAL from this RHS kind (a global/element read, a by-ref var, a wide-SRET call, or an if/match expression) is not yet supported — bind it to a local first (`t := <rhs>; ARR[i] = t`). [fail-loud guard: never a silent dropped store]")
      } else if gaes.is_s == false and gbyte == 0 {
        ## a SCALAR-element array global — store one word at `LABEL + i*8`.
        emit_gas(iv, sb, cx, a, nl)                 ## value on the stack
        emit_gas(ii, sb, cx, a, nl)                 ## index on top
        push_str(sb, "  leaq ")
        emit_global_label(sb, cx.decls, cx.src, gaib.s, gaib.n)
        push_str(sb, "(%rip), %rax\n  popq %rcx\n")
        ## CHECKED BOUNDS (I11 §358): trap an out-of-range index into the mutable-global SCALAR
        ## array before the indexed store. Was missing → `TABLE[i] = v` wrote out of bounds silently.
        if cx.vchk { push_str(sb, "  cmpq $"); push_int(sb, i64(array_lit_info(gaiv).nel)); push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n") }
        push_str(sb, "  popq %rbx\n  movq %rbx, (%rax,%rcx,8)\n")
        iga_done = true
      }
    }
  }
  ## `g.xs[i] = v` — a write to an ARRAY FIELD of a MUTABLE-GLOBAL struct (base `g.xs` is a Field,
  ## so the direct-global path above missed it). Element `i` (word-sized) sits at `LABEL +
  ## (off + i)*8`; store the value there. Dual of the `g.xs[i]` read (`global_field_off`).
  if iga_done == false {
    gfo := global_field_off(ib, cx, a)
    if gfo.found {
      emit_gas(iv, sb, cx, a, nl)                 ## value on the stack
      emit_gas(ii, sb, cx, a, nl)                 ## index on top
      push_str(sb, "  leaq ")
      emit_global_label(sb, cx.decls, cx.src, gfo.gs, gfo.gn)
      push_str(sb, "+")
      push_int(sb, gfo.off * 8)
      push_str(sb, "(%rip), %rax\n  popq %rcx\n  popq %rbx\n  movq %rbx, (%rax,%rcx,8)\n")
      iga_done = true
    }
  }
  ## NESTED tuple-element WRITE `t.N.M = v` — the base `ib` is itself an `Index(Var(t), Num(N))` into a
  ## MIXED tuple LOCAL whose component N is a FLAT single-word-position tuple (`tc.ek == 6`, the exact
  ## shape the two-level READ supports). The STORE dual of the `emit_gas` Index-of-Index read arm:
  ## resolve component N's word-0 ADDRESS (`emit_index_addr` on the inner `Var(t)`/`Num(N)`, is_ref-aware
  ## via its `tcomp` branch), then store `v` at word M within it (`+M*8` — word M == position M since
  ## every position is one word). Gated ON `tc.ek == 6` (SOUNDNESS: a multi-word component keeps `ek`
  ## == 5 → we fall through to `emit_index_addr`'s fail-loud guard, never mis-addressing wider words).
  if iga_done == false {
    nbxw := field_base_index(ib)
    if nbxw.is_ix {
      nbvnw := var_name_span(nbxw.arr)
      if nbvnw.n != 0 {
        niew := deref(svec_at(SlotEntry, cx.slots, index_base_entry(nbxw.arr, cx.slots, cx.src)))
        tcw := tcomp_find(cx, niew.off, usize(num_lit_value(nbxw.idx)))
        if tcw.estride != 0 and tcw.ek == 6 {
          emit_gas(iv, sb, cx, a, nl)                        ## value → stack
          emit_index_addr(nbxw.arr, nbxw.idx, sb, cx, a, nl) ## component N word-0 address → %rax
          mcw := num_lit_value(ii)
          if mcw != 0 { push_str(sb, "  addq $"); push_int(sb, mcw * 8); push_str(sb, ", %rax\n") }
          push_str(sb, "  popq %rbx\n  movq %rbx, (%rax)\n")
          iga_done = true
        }
      }
    }
  }
  ## LOCAL AGGREGATE-element array whole-element WRITE `arr[i] = <aggregate>` (a struct/enum
  ## INLINE-array LOCAL: ek 5 / eek 2|3, NOT a `Slice(T)` view). The single-word store below keeps
  ## ONLY word 0 (and for a literal RHS even word 0 is an address, not a value) — a Priority-1
  ## SILENT MISCOMPILE (every field past the first was dropped). Build/locate the whole aggregate,
  ## then copy its `estride` words to the element base (`emit_index_addr` → word-0 address in %rax;
  ## element word k at `+k*8`, ASCENDING within the element — the store dual of `emit_elem_copy_in`).
  ## Gated on a NON-ref inline aggregate array (a `Slice(T)` param is is_ref → left untouched) and
  ## eek 2|3. `src/`+`lib/` use only scalar `[usize; N]` arrays + slice params, so this path is never
  ## reached during the self-build → fixpoint-NEUTRAL. A struct/enum LITERAL and a NON-ref local
  ## struct/enum VAR RHS are handled; a call/branch/other RHS FAILS LOUD (bind it to a local first).
  ##
  ## P1-CLAYOUT S3(d) — the WHOLE-ELEMENT WRITE `xs[i] = Elem(…)` / `xs[i] = e` for a BYTE-TIER element,
  ## claimed before the word-copy arm below and never falling through to it. Two facts make this its own
  ## arm rather than a tweak of that one:
  ##   * the number of bytes moved is the element's own `standard_struct_bytes`, NOT `estride * 8`.
  ##     For `struct { data : [u8;3], inner : { lead : u16, raw : [u8;2], tail : u16 } }` that is 10
  ##     against 16, and the six extra bytes land in the NEXT element — the aliasing defect this slice
  ##     exists to close, reintroduced from the other side.
  ##   * the source image is byte-precise. `emit_struct_assign` already routes a byte-tier literal to
  ##     `emit_standard_assign` (the ONE writer), so the agg-temp holds the §6.1 image and this arm only
  ##     relocates it; a `str`/enum/tuple-carrying element never reaches here (it is outside
  ##     `std_array_elem_byte_tier`) and a `@packed` element is fenced in `arr_elem_info`.
  ## Byte at a time, because the element's §6.1 size need not be a multiple of 8 and a wider store would
  ## write past it. Any OTHER RHS kind fails LOUD here rather than reaching the word copy (I11).
  if iga_done == false and var_name_span(ib).n != 0 {
    s3dent := deref(svec_at(SlotEntry, cx.slots, index_base_entry(ib, cx.slots, cx.src)))
    if s3dent.ek == 5 and s3dent.eek == 2 and not s3dent.is_ref and s3dent.snl != 0 and std_array_elem_byte_tier(cx.decls, cx.src, s3dent.sns, s3dent.snl, a) {
      s3dnb := i64(standard_struct_bytes(cx.decls, cx.src, s3dent.sns, s3dent.snl, a))
      s3dlit := struct_lit_info(iv)
      s3dvag := var_agg_info(iv, cx.slots, cx.src)
      mut s3dsrc := i64(-1)                       ## the SOURCE block's first slot, once it is settled
      if s3dlit.is_s and cx.agg_tmp >= 0 {
        emit_struct_assign(iv, cx.agg_tmp, sb, cx, a, nl)      ## → the §6.1 byte image in the agg-temp
        s3dsrc = cx.agg_tmp
      }
      if s3dsrc < 0 and s3dvag.ek == 2 and var_name_span(iv).n != 0 {
        s3dvn := var_name_span(iv)
        s3dvent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, s3dvn.s, s3dvn.n)))
        ## a NON-ref local of the SAME element type: its own frame block already holds the §6.1 image
        if not s3dvent.is_ref and streq(cx.src, s3dvent.sns, s3dvent.snl, s3dent.sns, s3dent.snl) { s3dsrc = i64(s3dvent.off) }
      }
      if s3dsrc < 0 {
        panic("selfhost: `xs[i] = <value>` into an array whose ELEMENT is a standard byte-layout struct is supported for a struct LITERAL and for a non-reference LOCAL of the same element type — a call result, a by-reference var, a global element read or an if/match expression has no byte-precise element image yet; bind it to a local of the element type first (`t := <rhs>; xs[i] = t`)")
      }
      emit_index_addr(ib, ii, sb, cx, a, nl)
      push_str(sb, "  movq %rax, %r13\n")
      mut s3dk := i64(0)
      while s3dk < s3dnb {
        push_str(sb, "  movzbq -")
        push_int(sb, (s3dsrc + 1) * 8 - s3dk)
        push_str(sb, "(%rbp), %rax\n  movb %al, ")
        push_int(sb, s3dk)
        push_str(sb, "(%r13)\n")
        s3dk += 1
      }
      iga_done = true
    }
  }
  if iga_done == false and var_name_span(ib).n != 0 {
    ibent := deref(svec_at(SlotEntry, cx.slots, index_base_entry(ib, cx.slots, cx.src)))
    if ibent.ek == 5 and (ibent.eek == 2 or ibent.eek == 3) and not ibent.is_ref {
      estride := ibent.estride
      sivl := struct_lit_info(iv)
      eivl := enum_lit_info(iv)
      ivag := var_agg_info(iv, cx.slots, cx.src)
      if ibent.eek == 2 and sivl.is_s and cx.agg_tmp >= 0 {
        ## struct LITERAL → materialize into the down-growing agg-temp, then copy its words up.
        emit_struct_assign(iv, cx.agg_tmp, sb, cx, a, nl)
        emit_index_addr(ib, ii, sb, cx, a, nl)
        push_str(sb, "  movq %rax, %r13\n")
        for k in 0..estride {
          push_str(sb, "  movq -")
          push_int(sb, i64((usize(cx.agg_tmp) - k + 1) * 8))
          push_str(sb, "(%rbp), %rax\n  movq %rax, ")
          push_int(sb, i64(k * 8))
          push_str(sb, "(%r13)\n")
        }
        iga_done = true
      } else if ibent.eek == 3 and eivl.is_e and cx.agg_tmp >= 0 {
        ## enum LITERAL → materialize the disc + payload into the agg-temp, then copy up.
        emit_enum_assign(iv, cx.agg_tmp, sb, cx, a, nl)
        emit_index_addr(ib, ii, sb, cx, a, nl)
        push_str(sb, "  movq %rax, %r13\n")
        for k in 0..estride {
          push_str(sb, "  movq -")
          push_int(sb, i64((usize(cx.agg_tmp) - k + 1) * 8))
          push_str(sb, "(%rbp), %rax\n  movq %rax, ")
          push_int(sb, i64(k * 8))
          push_str(sb, "(%r13)\n")
        }
        iga_done = true
      } else if ((ibent.eek == 2 and ivag.ek == 2) or (ibent.eek == 3 and ivag.ek == 3)) and not deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, var_name_span(iv).s, var_name_span(iv).n))).is_ref {
        ## a NON-ref local struct/enum VAR RHS (`arr[i] = r`) — copy the var's `estride` frame
        ## words straight to the element base (word k of a local aggregate at `push_frame_word`).
        vvn := var_name_span(iv)
        vent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, vvn.s, vvn.n)))
        emit_index_addr(ib, ii, sb, cx, a, nl)
        push_str(sb, "  movq %rax, %r13\n")
        for k in 0..estride {
          push_str(sb, "  movq -")
          push_frame_word(sb, vent.off, k)
          push_str(sb, "(%rbp), %rax\n  movq %rax, ")
          push_int(sb, i64(k * 8))
          push_str(sb, "(%r13)\n")
        }
        iga_done = true
      } else if ibent.eek == 2 and struct_ret_call(iv, cx.decls, cx.src, a) and not sret_ret_call(iv, cx.decls, cx.src, a) and cx.agg_tmp >= 0 {
        ## struct-RETURNING CALL RHS (`arr[i] = mk()`, mk -> P): the call has no frame home, so
        ## materialize its `estride` returned words (retreg k = %rax:%rdx:%rcx:%r8:%r9:%r10:%r11)
        ## into the agg-temp block (down-growing, word k at `-(agg_tmp-k+1)*8`), then copy them UP
        ## to the element base (the SAME two-step the struct-LITERAL element case above uses —
        ## `emit_index_addr` → word-0 addr in %rax → %r13; element word k at `+k*8`). A wide (>7-word
        ## SRET) call is excluded (`not sret_ret_call`) → stays fail-loud below. `src/`+`lib/` never
        ## store a struct-call result into a struct-element array → fixpoint-neutral.
        emit_struct_value(iv, sb, cx, a, nl)
        for k in 0..estride {
          push_str(sb, "  movq ")
          emit_retreg(sb, k)
          push_str(sb, ", -")
          push_int(sb, i64((usize(cx.agg_tmp) - k + 1) * 8))
          push_str(sb, "(%rbp)\n")
        }
        emit_index_addr(ib, ii, sb, cx, a, nl)
        push_str(sb, "  movq %rax, %r13\n")
        for k in 0..estride {
          push_str(sb, "  movq -")
          push_int(sb, i64((usize(cx.agg_tmp) - k + 1) * 8))
          push_str(sb, "(%rbp), %rax\n  movq %rax, ")
          push_int(sb, i64(k * 8))
          push_str(sb, "(%r13)\n")
        }
        iga_done = true
      } else if ibent.eek == 3 and enum_ret_call_d(iv, cx.decls, cx.src, a) and not enum_sret_ret_call(iv, cx.decls, cx.src, a) and cx.agg_tmp >= 0 {
        ## enum-RETURNING CALL RHS (`arr[i] = mk()`, mk -> E) — the enum dual: disc/%rax +
        ## payload/%rdx… into the agg-temp block (`estride` = 1 + max-payload words), then copy up.
        emit_enum_value(iv, sb, cx, a, nl)
        for k in 0..estride {
          push_str(sb, "  movq ")
          emit_retreg(sb, k)
          push_str(sb, ", -")
          push_int(sb, i64((usize(cx.agg_tmp) - k + 1) * 8))
          push_str(sb, "(%rbp)\n")
        }
        emit_index_addr(ib, ii, sb, cx, a, nl)
        push_str(sb, "  movq %rax, %r13\n")
        for k in 0..estride {
          push_str(sb, "  movq -")
          push_int(sb, i64((usize(cx.agg_tmp) - k + 1) * 8))
          push_str(sb, "(%rbp), %rax\n  movq %rax, ")
          push_int(sb, i64(k * 8))
          push_str(sb, "(%r13)\n")
        }
        iga_done = true
      } else if match_if_agg_kind(iv, cx.decls, cx.src, a).kind != 0 and ((ibent.eek == 2 and match_if_agg_kind(iv, cx.decls, cx.src, a).kind == 2) or (ibent.eek == 3 and match_if_agg_kind(iv, cx.decls, cx.src, a).kind == 3)) and cx.agg_tmp >= 0 {
        ## if/match-EXPRESSION RHS yielding a struct/enum (`arr[i] = if c { mk() } else { P(v=7) }`).
        ## Deliver each branch/arm's value into the agg-temp block (the `emit_val_*_to_local`
        ## primitive — which itself handles a per-arm literal / call / str value), then copy `estride`
        ## words up to the element base. Gated so the branch kind matches the element kind (2/3).
        bmi := match_info(iv)
        if bmi.is_m {
          emit_val_match_to_local(bmi.scrut, bmi.head, cx.agg_tmp, sb, cx, a, nl)
        } else {
          bii := if_info(iv)
          emit_val_if_to_local(bii.cond, bii.then_e, bii.else_e, cx.agg_tmp, sb, cx, a, nl)
        }
        emit_index_addr(ib, ii, sb, cx, a, nl)
        push_str(sb, "  movq %rax, %r13\n")
        for k in 0..estride {
          push_str(sb, "  movq -")
          push_int(sb, i64((usize(cx.agg_tmp) - k + 1) * 8))
          push_str(sb, "(%rbp), %rax\n  movq %rax, ")
          push_int(sb, i64(k * 8))
          push_str(sb, "(%r13)\n")
        }
        iga_done = true
      } else {
        panic("selfhost: `arr[i] = <aggregate>` into a local struct/enum-element array from this RHS kind (a by-ref var, or a wide-SRET / tuple / generic-erased call) is not yet supported — bind it to a local first (`t := <rhs>; arr[i] = t`). [fail-loud guard: never a silent word-0-only store]")
      }
    }
  }
  ## `xs[i].arr[j] = v` — a WRITE into an ARRAY FIELD of an array-of-struct ELEMENT (`ib` is
  ## `Field(Index(xs,i), arr)`). The store dual of the `arr_field_elem` READ: array-field word-0
  ## ADDRESS (`emit_idx_field_addr`) + element j at `+j*8` (ASCENDING), then store. The default
  ## below routes `emit_index_addr` on a `Field` base → slot 0 → a bogus %rbp store (silent no-op).
  if iga_done == false {
    wafe := arr_field_elem(ib, cx)
    if wafe.found {
      ## A plain-STRUCT aggregate leaf is copied word-for-word. The old scalar store below
      ## remains the path for `[u64; N]` fields; struct/enum/str leaves must never silently lose
      ## their tail words. This bounded increment deliberately excludes global roots and every
      ## RHS kind beyond a struct literal or a non-ref aggregate local.
      wpl := resolve_idx_field_place(ib, cx)
      wae := array_elem_span(cx.src, wpl.tys, wpl.tyn)
      if wae.n != 0 and struct_decl_of(cx.decls, cx.src, wae.s, wae.n) >= 0 {
        if is_packed(cx.decls, cx.src, wae.s, wae.n) {
          panic("selfhost: whole-element write to a @packed aggregate array-field element is not yet supported")
        }
        wgvn := var_name_span(wafe.arr)
        if wgvn.n != 0 and unchecked bitcast(usize, global_arr_value(cx.slots, cx.decls, cx.src, wgvn.s, wgvn.n)) != 0 {
          panic("selfhost: whole-element write to a global aggregate array-field element is not yet supported")
        }
        wstride := struct_words(cx.decls, cx.src, wae.s, wae.n, a)
        wsl := struct_lit_info(iv)
        wva := var_agg_info(iv, cx.slots, cx.src)
        mut wsrc_ok := false
        if wsl.is_s and cx.agg_tmp >= 0 {
          ## Struct literal RHS → materialize in the aggregate temp, then copy all words.
          emit_struct_assign(iv, cx.agg_tmp, sb, cx, a, nl)
          wsrc_ok = true
        } else if wva.ek == 2 {
          wvns := var_name_span(iv)
          went := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, wvns.s, wvns.n)))
          if not went.is_ref {
            ## Non-ref local aggregate RHS → copy directly from its down-growing frame block.
            emit_gas(ii, sb, cx, a, nl)                                      ## inner j → stack
            emit_idx_field_addr(wafe.arr, wafe.idx, wafe.woff * 8, sb, cx, nl)
            push_str(sb, "  popq %rcx\n")
            if cx.vchk and wafe.elen > 0 {
              push_str(sb, "  cmpq $")
              push_int(sb, wafe.elen)
              push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n")
            }
            push_str(sb, "  imulq $")
            push_int(sb, i64(wstride * 8))
            push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
            for k in 0..wstride {
              push_str(sb, "  movq -")
              push_frame_word(sb, went.off, k)
              push_str(sb, "(%rbp), %rax\n  movq %rax, ")
              push_int(sb, i64(k * 8))
              push_str(sb, "(%r13)\n")
            }
            wsrc_ok = true
          }
        }
        if wsrc_ok and wsl.is_s {
          ## The literal is in the aggregate-temp pool; now compose the target address and copy.
          emit_gas(ii, sb, cx, a, nl)                                      ## inner j → stack
          emit_idx_field_addr(wafe.arr, wafe.idx, wafe.woff * 8, sb, cx, nl)
          push_str(sb, "  popq %rcx\n")
          if cx.vchk and wafe.elen > 0 {
            push_str(sb, "  cmpq $")
            push_int(sb, wafe.elen)
            push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n")
          }
          push_str(sb, "  imulq $")
          push_int(sb, i64(wstride * 8))
          push_str(sb, ", %rcx\n  addq %rcx, %rax\n  movq %rax, %r13\n")
          for k in 0..wstride {
            push_str(sb, "  movq -")
            push_int(sb, i64((usize(cx.agg_tmp) - k + 1) * 8))
            push_str(sb, "(%rbp), %rax\n  movq %rax, ")
            push_int(sb, i64(k * 8))
            push_str(sb, "(%r13)\n")
          }
        } else if wsrc_ok == false {
          panic("selfhost: `xs[i].arr[j] = <aggregate>` supports only a struct literal or non-ref aggregate local RHS in this lane")
        }
      } else {
        ## Scalar array-field element — preserve the existing one-word path byte-for-byte.
        emit_gas(iv, sb, cx, a, nl)                                        ## value → stack (bottom)
        emit_gas(ii, sb, cx, a, nl)                                        ## inner index j → stack (top)
        emit_idx_field_addr(wafe.arr, wafe.idx, wafe.woff * 8, sb, cx, nl) ## array-field word-0 addr → %rax
        push_str(sb, "  popq %rcx\n")                                      ## j → %rcx (value still on stack)
        if cx.vchk and wafe.elen > 0 {
          push_str(sb, "  cmpq $")
          push_int(sb, wafe.elen)
          push_str(sb, ", %rcx\n  jb 1f\n  ud2\n1:\n")
        }
        push_str(sb, "  imulq $8, %rcx\n  addq %rcx, %rax\n  popq %rbx\n  movq %rbx, (%rax)\n")
      }
      iga_done = true
    }
  }
  if iga_done == false and slice_base_is_byte(ib, cx) {
    ## BYTE Slice LOCAL/PARAM element write — pair the byte-granular address with a byte-width
    ## store. The generic tail is word-sized and would clobber the seven adjacent bytes.
    emit_gas(iv, sb, cx, a, nl)
    emit_index_addr(ib, ii, sb, cx, a, nl)
    push_str(sb, "  popq %rbx\n")
    emit_deref_store(sb, 1)
    iga_done = true
  }
  if iga_done == false {
    emit_gas(iv, sb, cx, a, nl)
    emit_index_addr(ib, ii, sb, cx, a, nl)
    push_str(sb, "  popq %rbx\n  movq %rbx, (%rax)\n")
  }
}
## The `Stmt::Assign` arm of `emit_stmts`, moved out verbatim (Step 4.1) — the largest arm, and it
## touches NO module global. Covers `name := e` / `name = e` in every RHS shape. The
## uninitialised-declaration fast path used `s = nx ; continue`; here it is a bare `return`, and
## the caller keeps the single `s = nx`.
pub emit_st_assign := fn(ns : usize, nl2 : usize, v : ptr(Expr), in out sb : strbuf::StrBuf, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  ## `name : T` has a parser-only zero sentinel but no initializer. Reserve the slot from the
  ## declaration annotation in collect_slots, then emit no store here: checked sema enforces that
  ## every read follows a real write, while unchecked code observes the target's raw contents.
  if local_is_uninit(cx.src, ns, nl2) {
    return
  }
  ## resolve a module-CONSTANT Var RHS to its value (`p := ORIGIN` / `s := MSG`) so the copy
  ## rides the existing struct-lit / str-lit / scalar emit — matching collect_slots' binding.
  mut v := const_rhs(v, cx.decls, cx.src)
  ## A module-level const STRUCT field is a compile-time value, but it is not a bare Var for
  ## const_rhs to resolve. Materialize the selected field before slot/value classification so a
  ## `str` field (for example TOOL-15's `app.version`) takes the existing two-word emit_str_assign
  ## path instead of bare emit_gas, whose deliberate scalar StrLit arm carries only the pointer word.
  match deref(v) {
    Expr::Field(base, fs, fl) => {
      cv := const_struct_field(base, fs, fl, cx.decls, cx.src, a)
      if unchecked bitcast(usize, cv) != 0 { v = cv }
    }
    _ => {}
  }
  rqa := require_agg_parts(v, cx.decls, cx.src, a)
  ## (TYP-6 / D69) the ANNOTATED-scalar-local (`x : u64 = s`) and scalar-RE-ASSIGN (`G = s` / `x = s`)
  ## aggregate-into-scalar soundness nets moved UP into `sema::check_program` (build-path gate).
  si := struct_lit_info(v)
  ei := enum_lit_info(v)
  ti := str_lit_info(v)
  ai := array_lit_info(v)
  if is_module_mut_global(cx.decls, cx.src, ns, nl2) {
    ## a write to a MUTABLE module GLOBAL. A multi-word AGGREGATE global (`G = S(…)` / `E.V(…)` /
    ## `"…"` / `[…]`) copies ALL its words via `emit_mut_global_whole_assign` (else a scalar store
    ## would silently drop every word past word 0 — a §Priority-1 miscompile); a NON-literal
    ## aggregate RHS fails loud there. A SCALAR global (`COUNTER = <scalar>`) takes the fast path
    ## below: `<eval v>; popq %rax; movq %rax, LABEL(%rip)`.
    if not emit_mut_global_whole_assign(ns, nl2, v, sb, cx, a, nl) {
      emit_gas(v, sb, cx, a, nl)
      push_str(sb, "  popq %rax\n  movq %rax, ")
      emit_global_label(sb, cx.decls, cx.src, ns, nl2)
      push_str(sb, "(%rip)\n")
    }
  } else if deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, ns, nl2))).ek == 12 {
    ## FN-11: a static-closure STORE `s := fn(…){…}` (lifted to FnRef) whose env holds the captures —
    ## store each captured outer local's CURRENT value into `s`'s env words. The captures are the
    ## lifted lambda's LAST `ncap` params (in append order = env word order); env word `j` lives at
    ## slot `sslot + j` (byte `-(sslot+1+j)*8`).
    sent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, ns, nl2)))
    sslot := i64(sent.off)
    ncap := usize(sent.eek)
    lidx := lam_idx_by_fnpos(cx.decls, sent.sns)
    larity := deref(decl_get(cx.decls, usize(lidx))).arity
    for j in 0..ncap {
      capsp := lam_param_span_at(cx.decls, usize(lidx), larity - ncap + j)
      capslot := slot_of(cx.slots, cx.src, capsp.s, capsp.n)
      push_str(sb, "  movq -")
      push_int(sb, (capslot + 1) * 8)
      push_str(sb, "(%rbp), %rax\n  movq %rax, -")
      push_int(sb, (sslot + 1 + i64(j)) * 8)
      push_str(sb, "(%rbp)\n")
    }
  } else if deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, ns, nl2))).ek == 11 {
    ## FN-11: `d : dyn fn(…)->R = dyn_over(ptr(mut store))` — build the two-word {code, env} fat pair.
    ## `env` = the address of `store`'s slot (which holds the captures). `code` = a compiler-synthesized
    ## monomorphic adapter emitted INLINE here (skipped by a `jmp` at runtime): it takes (env, user
    ## args…), SAVES env (%rdi) into %r11 (survives the arg-register shift, it is not a SysV arg reg),
    ## shifts the user args down one register (freeing the leading slot the env rode in), then appends
    ## ALL `ncap` captures loaded from env words (word `j` at `-j*8(%r11)`), and tail-jumps to the
    ## lifted lambda body `<mod>__lam<fnpos>(users…, cap0, …, cap(ncap-1))`.
    sv := dyn_over_store_span(v, a)
    sent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, sv.s, sv.n)))
    sslot := i64(sent.off)
    fnpos := sent.sns
    fms := sent.snl
    fml := sent.estride
    lidx := lam_idx_by_fnpos(cx.decls, fnpos)
    larity := deref(decl_get(cx.decls, usize(lidx))).arity
    lts := local_type_span(cx.src, ns, nl2)
    nuser := dyn_type_nuser(cx.src, lts.s, lts.n)
    if larity < nuser or (larity - nuser) < 1 { panic("selfhost: FN-11 — a `dyn` closure needs at least one capture (a zero-capture closure is a plain fn value)") }
    ncap := larity - nuser
    ## FLOAT USER ARGUMENTS (FN-6 / SysV): an `f64`/`f32` user argument rides an SSE register
    ## (%xmm0..), which the leading environment pointer never occupies — so it needs NO shift and
    ## consumes NO integer slot. Only the INTEGER user args shift down one register, and the
    ## captures follow them at integer index `nint`. For an all-integer `dyn` type `nint == nuser`
    ## and every instruction below is byte-identical to the former unconditional shift.
    dftp := fnval_ty_pos(ns, nl2, cx.src, a)
    mut nint := 0
    for i in 0..nuser {
      if dyn_user_arg_is_float(cx, dftp, i) == false { nint = nint + 1 }
    }
    ## A float-class CAPTURE parameter would be read from an %xmm the adapter never writes (it
    ## loads env words with `movq` into integer registers) — fail loud, never a silent wrong value.
    if lam_cap_is_float(cx.decls, cx.src, usize(lidx), larity, ncap) { panic("selfhost: FN-11 — a `dyn` closure capturing an `f64`/`f32`-TYPED value is unsupported (the adapter passes captures in the integer registers); leave the captured binding untyped or call the static closure directly") }
    if nint + ncap > 6 { panic("selfhost: FN-11 — a `dyn` closure with user-args + captures exceeding 6 integer registers is unsupported (stack passing not modelled)") }
    k := nl
    nl = nl + 1
    push_str(sb, "  jmp .Ldynend")
    push_int(sb, i64(k))
    push_str(sb, "\n.Ldynad")
    push_int(sb, i64(k))
    push_str(sb, ":\n  movq %rdi, %r11\n")
    mut mi := 0
    for i in 0..nuser {
      if dyn_user_arg_is_float(cx, dftp, i) == false {
        push_str(sb, "  movq ")
        emit_argreg(sb, mi + 1)
        push_str(sb, ", ")
        emit_argreg(sb, mi)
        push_str(sb, "\n")
        mi = mi + 1
      }
    }
    for j in 0..ncap {
      push_str(sb, "  movq ")
      push_int(sb, 0 - i64(j * 8))
      push_str(sb, "(%r11), ")
      emit_argreg(sb, nint + j)
      push_str(sb, "\n")
    }
    push_str(sb, "  jmp ")
    emit_mangled_def(sb, cx.src, fms, fml, fnpos, 0)
    push_str(sb, "\n.Ldynend")
    push_int(sb, i64(k))
    push_str(sb, ":\n")
    dbase := slot_of(cx.slots, cx.src, ns, nl2)
    push_str(sb, "  leaq .Ldynad")
    push_int(sb, i64(k))
    push_str(sb, "(%rip), %rax\n  movq %rax, -")
    push_int(sb, (dbase + 1) * 8)
    push_str(sb, "(%rbp)\n  leaq -")
    push_int(sb, (sslot + 1) * 8)
    push_str(sb, "(%rbp), %rax\n  movq %rax, -")
    push_int(sb, dbase * 8)
    push_str(sb, "(%rbp)\n")
  } else if rqa.ok {
    ## A require constructor is a complete aggregate value, not a scalar conversion. Its source is
    ## evaluated once into the destination local; the checked predicate receives a separate copy.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_require_agg_assign(v, base, sb, cx, a, nl)
  } else if si.is_s {
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_struct_assign(v, base, sb, cx, a, nl)
  } else if ei.is_e {
    base := slot_of(cx.slots, cx.src, ns, nl2)
    ## §8 `@niche`: a NICHE-FOLDED `Option(ptr(T))` destination stores ONE word (no disc). Detect
    ## via the SLOT's recorded type span (set folded in collect_slots) so both a fresh binding and
    ## a later `s = …` reassignment route to the folded construct; any other enum → the 2-word path.
    ## RAW UNION write `u := U.m(value)` (spec Types §6.3) — store the payload at OFFSET 0, NO disc
    ## word (untagged). Detected by the enum-lit type resolving to a union decl (source-scan). Placed
    ## before the enum/niche paths; dormant for the self-host build (no union in `src/`+`lib/`).
    fent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, ns, nl2)))
    if is_union_decl(cx.decls, cx.src, ei.es, ei.el) {
      emit_union_assign(v, base, sb, cx, a, nl)
    } else {
      if fent.ek == 3 and is_niche_folded(cx.src, fent.sns, fent.snl) {
        emit_folded_option_assign(v, base, sb, cx, a, nl)
      } else {
        emit_enum_assign(v, base, sb, cx, a, nl)
      }
    }
  } else if ti.is_s and fixed_array_byte_eek(cx.src, ns, nl2) != 0 {
    ## The parser keeps `embed(...)` as a StrLit. An explicit byte-array annotation changes its
    ## storage class, so initialize the packed bytes rather than the two-word str pair.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    lts := local_type_span(cx.src, ns, nl2)
    emit_embed_byte_assign(v, base, parse_arr_len(cx.src, lts.s, lts.n), sb)
  } else if ti.is_s {
    ## a `name := "…"` binding stores the {ptr, len} pair into the str local's slots
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_str_assign(v, base, sb)
  } else if is_strat_call(v, cx.src) {
    ## a `name := str_at(base, len)` binding materializes the view's {ptr, len} pair and stores
    ## it into the str local's slots (the same layout as a literal / `sub` binding).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_strat_assign(v, base, sb, cx, a, nl)
  } else if is_slice_expr(v) and slice_arr_stride(v, cx.slots, cx.src) != 0 {
    ## a `s := arr[lo..hi]` TYPED array-slice binding: store the element-stride-aware {ptr, len}
    ## into the slice local's two words (the base is a raw scalar/float array, not a str).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_array_slice_assign(v, base, sb, cx, a, nl)
  } else if is_slice_expr(v) {
    ## a `name := base[lo..hi]` range-slice binding materializes the view's {ptr, len} pair
    ## and stores it into the str local's slots (the same layout as a `sub` binding).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_slice_assign(v, base, sb, cx, a, nl)
  } else if is_sub_call(v, cx.src) {
    ## a `name := sub(s, start, len)` binding materializes the view's {ptr, len} pair and
    ## stores it into the str local's slots (the same layout as a literal binding).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_sub_assign(v, base, sb, cx, a, nl)
  } else if is_bytes_call(v, cx.src) {
    ## a `name := bytes(x)` binding — the str→`[u8]` view (identical `{ptr, len}` repr).
    ## `emit_str_pair` emits `x`'s pair (it recognizes `bytes`); store it into the str
    ## local's slots (len at base+1, ptr at base — the same layout as a `sub` binding).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_str_pair(v, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n  movq %rax, -")
    push_int(sb, base * 8)
    push_str(sb, "(%rbp)\n  popq %rax\n  movq %rax, -")
    push_int(sb, (base + 1) * 8)
    push_str(sb, "(%rbp)\n")
  } else if ai.is_a {
    ## a `name := [e0, …]` binding stores each element into the array local's slots
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_array_assign(v, base, sb, cx, nl)
  } else if fixed_array_byte_return_len(v, cx.decls, cx.src, a) >= 1 {
    ## P1-BYTES: the bounded `[u8; N]` return is one packed word in %rax. The byte-array local's
    ## data block begins at `-(base*8)(%rbp)` (the filler below its metadata slot), exactly the
    ## address used by `emit_index_addr`/`emit_array_assign`; store the whole returned word there.
    ## No other array return reaches this arm, so unsupported shapes retain their old rejects.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_gas(v, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n  movq %rax, -")
    push_int(sb, base * 8)
    push_str(sb, "(%rbp)\n")
  } else if str_ret_call(v, cx.decls, cx.src, deref(cx.mar)) or generic_inferred_str_ret(v, cx, a) {
    ## a `name := f(…)` where `f` returns a `str`: the call leaves ptr/%rax, len/%rdx
    ## (emit_struct_value's Call arm emits the call); store ptr at the base slot, len at base+1
    ## (the str-local {ptr,len} layout, same as emit_str_assign / a `sub` binding).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_struct_value(v, sb, cx, a, nl)
    push_str(sb, "  movq %rax, -")
    push_int(sb, (base + 1) * 8)
    push_str(sb, "(%rbp)\n  movq %rdx, -")
    push_int(sb, base * 8)
    push_str(sb, "(%rbp)\n")
  } else if abi_c_ret_mem_call(v, cx.decls, cx.src, a) {
    ## a `q := f(…)` where `f` is an @abi(c) callee returning a MEMORY struct (> 16 bytes, SysV
    ## sret): `q`'s slots (bound by `struct_ret_call` in collect_slots) are the destination —
    ## publish `q`'s base on `cx.sret_call` so `emit_abi_c_call_args` passes its ADDRESS as the
    ## hidden %rdi; the C callee writes the whole struct through that pointer straight into `q`'s
    ## slots (nothing to copy afterwards). Checked BEFORE `struct_ret_call` (a 3..7-word MEMORY
    ## return would otherwise take the register read-back path, which the C callee never fills).
    ## Gated on `@abi(c)` (src/ declares none) → fixpoint-neutral.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    ov_sc := cx.sret_call
    cx.sret_call = base
    emit_struct_value(v, sb, cx, a, nl)
    cx.sret_call = ov_sc
  } else if sret_ret_call(v, cx.decls, cx.src, a) {
    ## a `name := f(…)` where `f` returns a struct > 7 words (SRET): allocate `name`'s slots as
    ## the destination, publish its slot base on `cx.sret_call` so `emit_call_args` passes its
    ## ADDRESS as the hidden %rdi, then emit the call. The callee writes the whole struct through
    ## that pointer directly into `name`'s slots — so nothing to copy afterwards.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    ov_sc := cx.sret_call
    cx.sret_call = base
    emit_struct_value(v, sb, cx, a, nl)
    cx.sret_call = ov_sc
  } else if gen_ret_sret_span(v, cx.decls, cx.src, a).n != 0 {
    ## a `c := mk(S, …)` where a GENERIC fn returns its type param substituted to a struct > 7
    ## words: the SAME sret path as the concrete branch above — publish `c`'s slot base on
    ## `cx.sret_call` so `emit_call_args` hands the instance `c`'s ADDRESS in the hidden %rdi, and
    ## the instance (whose `d_is_sret` now also resolves through the substitution) writes the whole
    ## struct into `c`'s slots. Nothing to read back from the return registers.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    ov_sc := cx.sret_call
    cx.sret_call = base
    emit_struct_value(v, sb, cx, a, nl)
    cx.sret_call = ov_sc
  } else if ufcs_ret_struct_span(v, cx.slots, cx.decls, cx.src, a).n != 0 {
    ## Hunk C: an implicit-UFCS `r := o.unwrap()` / `o.expect(m)` returning a MULTI-WORD struct
    ## payload (recovered from the receiver's slot type). Same register read-back as
    ## `gen_ret_struct_span`, but the return-struct span comes from the receiver, not an explicit
    ## type-arg. Placed BEFORE `gen_ret_struct_span` (which reads the receiver Var as a bogus arg-0).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_struct_value(v, sb, cx, a, nl)
    ucsp2 := ufcs_ret_struct_span(v, cx.slots, cx.decls, cx.src, a)
    rw := struct_words(cx.decls, cx.src, ucsp2.s, ucsp2.n, deref(cx.mar))
    for k in 0..rw {
      push_str(sb, "  movq ")
      emit_retreg(sb, k)
      push_str(sb, ", -")
      push_int(sb, (base - i64(k) + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
  } else if gen_ret_struct_span(v, cx.decls, cx.src, a).n != 0 {
    ## `p := id(P, …)` — a generic fn returning its type param (struct P): the instance leaves
    ## field k in emit_retreg(k); store each into p's slots (same as struct_ret_call, but the
    ## return-struct span comes from the substituted type-arg).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_struct_value(v, sb, cx, a, nl)
    gcsp2 := gen_ret_struct_span(v, cx.decls, cx.src, a)
    rw := struct_words(cx.decls, cx.src, gcsp2.s, gcsp2.n, deref(cx.mar))
    for k in 0..rw {
      push_str(sb, "  movq ")
      emit_retreg(sb, k)
      push_str(sb, ", -")
      push_int(sb, (base - i64(k) + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
  } else if struct_ret_call(v, cx.decls, cx.src, a) {
    ## a `name := f(…)` where `f` returns a 2..7-word struct: the call leaves field k in
    ## `emit_retreg(k)` (%rax:%rdx:%rcx:%r8:%r9:%r10:%r11); store each into the local's slots.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_struct_value(v, sb, cx, a, nl)
    ## Types §9.4 — a GENERIC `-> Box(T)` return at an AGGREGATE type-arg stages the RESOLVED
    ## `Box(P)` width (the raw `Box(T)` sizes to one word); 0/0 for every other call → unchanged.
    csp2 := call_ret_struct_span(v, cx.decls, cx.src, deref(cx.mar))
    gcs2 := subst_gen_struct_ret_span(v, cx.decls, cx.src, deref(cx.mar), cx.mar)
    mut rws := csp2.s
    mut rwn := csp2.n
    if gcs2.n != 0 { rws = gcs2.s ; rwn = gcs2.n }
    rw := struct_words(cx.decls, cx.src, rws, rwn, deref(cx.mar))
    for k in 0..rw {
      push_str(sb, "  movq ")
      emit_retreg(sb, k)
      push_str(sb, ", -")
      push_int(sb, (base - i64(k) + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
  } else if slice_ret_call(v, cx.decls, cx.src, a) {
    ## a `r := f(…)` where `f` returns `Slice(T)` by value: the call leaves ptr in `emit_retreg(0)`
    ## (%rax) and len in `emit_retreg(1)` (%rdx). Store ptr into word 0 (`(base+1)*8`) and len into
    ## word 1 (`base*8`) — the same {ptr, len} slot layout `emit_array_slice_assign` writes for a
    ## `s := arr[lo..hi]` view, so every ek-5 slice read path applies unchanged.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_struct_value(v, sb, cx, a, nl)
    push_str(sb, "  movq %rax, -")
    push_int(sb, (base + 1) * 8)
    push_str(sb, "(%rbp)\n  movq %rdx, -")
    push_int(sb, base * 8)
    push_str(sb, "(%rbp)\n")
  } else if is_cas_call(v, cx.src) {
    ## `r := atomic::cas_*(p, expected, new, ok, fail)` — atomic compare-and-swap. On x86_64 a
    ## single `lock cmpxchgq` (cas_weak == cas_strong — no spurious failure): expected in %rax,
    ## new in %rbx, p in %rcx. After: %rax = the CURRENT (old) value, ZF = swapped?. Store
    ## current → `r.0`, succeeded (`setz`) → `r.1` (the 2-word tuple slot bound in collect_slots).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    cp := call_parts(v)
    emit_gas(arg_expr_at(cp.ah, 1, a), sb, cx, a, nl)   ## expected → %rax
    emit_gas(arg_expr_at(cp.ah, 2, a), sb, cx, a, nl)   ## new → %rbx
    emit_gas(arg_expr_at(cp.ah, 0, a), sb, cx, a, nl)   ## p → %rcx (stack top)
    push_str(sb, "  popq %rcx\n  popq %rbx\n  popq %rax\n  lock cmpxchgq %rbx, (%rcx)\n  setz %dl\n  movzbq %dl, %rdx\n")
    push_str(sb, "  movq %rax, -")
    push_int(sb, (base + 1) * 8)
    push_str(sb, "(%rbp)\n  movq %rdx, -")
    push_int(sb, base * 8)
    push_str(sb, "(%rbp)\n")
  } else if tuple_ret_call(v, cx.decls, cx.src, a) {
    ## a `name := f(…)` where `f` returns a TUPLE `(…)`: the call leaves component k in
    ## `emit_retreg(k)` (%rax:%rdx:…); store each into the local's N array slots. `t.0`/`t.1`
    ## then read them via the array-element path (same as a tuple LITERAL binding).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    rw := call_ret_tuple_words(v, cx.decls, cx.src, a)
    if rw >= 8 {
      ## a WIDE (>= 8-component) tuple return rides SRET: pass `name`'s ADDRESS as the hidden
      ## %rdi and let the callee write every component through it — no register read-back (the
      ## `emit_retreg` loop below tops out at %r11 = 7 words, so components 7.. used to come back
      ## as whatever those registers held: a SILENT garbage tail). The tuple dual of the wide-
      ## struct / wide-enum sret callers. `name`'s N slots were reserved by `tuple_ret_call` in
      ## collect_slots (unchanged) and use the same word layout the callee writes.
      ov_tsc := cx.sret_call
      cx.sret_call = base
      emit_struct_value(v, sb, cx, a, nl)
      cx.sret_call = ov_tsc
    } else {
    emit_struct_value(v, sb, cx, a, nl)
    for k in 0..rw {
      push_str(sb, "  movq ")
      emit_retreg(sb, k)
      push_str(sb, ", -")
      push_int(sb, (base - i64(k) + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
    }
  } else if enum_sret_ret_call(v, cx.decls, cx.src, a) {
    ## a `name := f(…)` where `f` returns a WIDE enum (SRET): pass `name`'s ADDRESS as the hidden
    ## %rdi, the callee writes the whole enum through it — no register read-back. The enum dual of
    ## the wide-struct sret caller above. `name`'s enum slots were reserved by `enum_ret_call_d`
    ## in collect_slots (that binding is unchanged; only the emit switches to the pointer path).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    ov_sc := cx.sret_call
    cx.sret_call = base
    emit_enum_value(v, sb, cx, a, nl)
    cx.sret_call = ov_sc
  } else if gen_ret_enum_span(v, cx.decls, cx.src, a).n != 0 {
    ## `o := id(Opt, …)` — a generic fn returning its type param (enum Opt): the instance leaves
    ## disc/%rax + payload/%rdx…; store each word into o's slots (like enum_ret_call, the enum
    ## span comes from the recorded slot / substituted type-arg).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    eent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, ns, nl2)))
    etw := 1 + enum_inst_words(cx.decls, cx.src, eent.sns, eent.snl, a)
    emit_enum_value(v, sb, cx, a, nl)
    for k in 0..etw {
      push_str(sb, "  movq ")
      emit_retreg(sb, k)
      push_str(sb, ", -")
      push_int(sb, (base - i64(k) + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
  } else if enum_ret_call_d(v, cx.decls, cx.src, deref(cx.mar)) {
    ## a `name := f(…)` where `f` returns an ENUM: the call leaves disc in %rax and payload
    ## word i in `emit_retreg(i+1)` (%rdx, %rcx, …). Store word k at slot `base+k` (disc at
    ## base, payload[i] at base+1+i — the layout `bind_enum_slot` reserves). A single-payload
    ## enum stores exactly %rax + %rdx (byte-identical); a wider payload (`Option(Pt)`) copies
    ## the extra registers so a multi-word struct value is not truncated.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    ## Read the RECORDED slot span (collect_slots stored the SUBSTITUTED `Enum(concrete)` for a
    ## generic return whose payload was a callee type-param), so a wide struct payload is staged
    ## whole. For a concrete-return call the slot span == the declared span → byte-identical.
    eent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, ns, nl2)))
    etw := 1 + enum_inst_words(cx.decls, cx.src, eent.sns, eent.snl, a)
    emit_enum_value(v, sb, cx, a, nl)
    for k in 0..etw {
      push_str(sb, "  movq ")
      emit_retreg(sb, k)
      push_str(sb, ", -")
      push_int(sb, (base - i64(k) + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
  } else if deref_struct_span(v, cx.slots, cx.src).n != 0 {
    ## a `s := deref(p)` where p is a pointer-to-struct: load p's value (the pointee word-0
    ## address) into %rax, then copy each pointee word from `-(k*8)(%rax)` into s's slots
    ## (the read dual of the multi-word store; down-growing pointee layout).
    dsp := deref_struct_span(v, cx.slots, cx.src)
    nf := struct_words(cx.decls, cx.src, dsp.s, dsp.n, a)
    dst := slot_of(cx.slots, cx.src, ns, nl2)
    pv := deref_var_span(v)
    pent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, pv.s, pv.n)))
    push_str(sb, "  movq -")
    push_int(sb, (pent.off + 1) * 8)
    push_str(sb, "(%rbp), %rax\n")
    for k in 0..nf {
      push_str(sb, "  movq ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((dst - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
  } else if deref_field_struct_span(v, cx.slots, cx.decls, cx.src, a).n != 0 {
    ## an `ab := deref(v.arena)`: lower the inner `v.arena` FIELD read (its value — the pointer —
    ## lands on the stack), pop it into %rax, then copy each pointee word from `-(k*8)(%rax)` into
    ## ab's slots (identical to the `deref(<call>)` copy; the field read supplies the pointer).
    dfs := deref_field_struct_span(v, cx.slots, cx.decls, cx.src, a)
    nf := struct_words(cx.decls, cx.src, dfs.s, dfs.n, a)
    dst := slot_of(cx.slots, cx.src, ns, nl2)
    inner := deref_inner_expr(v)
    emit_gas(inner, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n")
    for k in 0..nf {
      push_str(sb, "  movq ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((dst - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
  } else if deref_call_struct_span(v, cx.decls, cx.src, a).n != 0 {
    ## a `s := deref(get(T, …))`: lower the pointer-producing call (its result is the
    ## pointee word-0 address in %rax), then copy each word from `-(k*8)(%rax)` into s's slots.
    dcs := deref_call_struct_span(v, cx.decls, cx.src, a)
    nf := struct_words(cx.decls, cx.src, dcs.s, dcs.n, a)
    dst := slot_of(cx.slots, cx.src, ns, nl2)
    inner := deref_inner_expr(v)
    emit_gas(inner, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n")
    for k in 0..nf {
      push_str(sb, "  movq ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((dst - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
  } else if deref_call_ret_struct_span(v, cx.decls, cx.src, a, cx.gp_s, cx.gp_l, cx.it_s, cx.it_l, cx.gp2_s, cx.gp2_l, cx.it2_s, cx.it2_l).n != 0 {
    ## a `existing := deref(key_at(K, …))` inside an INSTANCE: resolve K via the return type +
    ## the enclosing instance substitution, copy the struct's words from the pointee into
    ## `existing`'s slots (the emit dual of the collect_slots reservation above).
    drs := deref_call_ret_struct_span(v, cx.decls, cx.src, a, cx.gp_s, cx.gp_l, cx.it_s, cx.it_l, cx.gp2_s, cx.gp2_l, cx.it2_s, cx.it2_l)
    nf := struct_words(cx.decls, cx.src, drs.s, drs.n, a)
    dst := slot_of(cx.slots, cx.src, ns, nl2)
    inner := deref_inner_expr(v)
    emit_gas(inner, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n")
    for k in 0..nf {
      push_str(sb, "  movq ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((dst - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
  } else if deref_call_enum_span(v, cx.decls, cx.src, a).n != 0 {
    ## a `st := deref(node_ptr(E, …))`: lower the pointer-producing call (its result is the
    ## pointee word-0 address in %rax), then copy each of the enum's `1 + max_arity` words
    ## from `-(k*8)(%rax)` into st's slots (disc at slot dst, payload i at dst+1+i) — the
    ## enum dual of the deref-struct copy, so a following `match st` reads valid words.
    dce := deref_call_enum_span(v, cx.decls, cx.src, a)
    nf := 1 + enum_inst_words(cx.decls, cx.src, dce.s, dce.n, a)
    dst := slot_of(cx.slots, cx.src, ns, nl2)
    inner := deref_inner_expr(v)
    emit_gas(inner, sb, cx, a, nl)
    push_str(sb, "  popq %rax\n")
    for k in 0..nf {
      push_str(sb, "  movq ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((dst - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
  } else if is_mut_struct_global_var(v, cx.decls, cx.src) {
    ## `p := STATE` — snapshot a mutable STRUCT global: copy its CURRENT `.data` words (ascending
    ## `LABEL + k*8`) into `p`'s down-growing frame slots. `leaq LABEL(%rip)` (PIE-safe base), then
    ## word k → `-(dst + k + 1)*8(%rbp)`. A runtime copy — `p` is thereafter independent.
    gvn := var_name_span(v)
    gmgv := mut_global_value(cx.decls, cx.src, gvn.s, gvn.n)
    gsli := struct_lit_info(gmgv)
    nfg := struct_words(cx.decls, cx.src, gsli.ss, gsli.sl, a)
    dstg := slot_of(cx.slots, cx.src, ns, nl2)
    push_str(sb, "  leaq ")
    emit_global_label(sb, cx.decls, cx.src, gvn.s, gvn.n)
    push_str(sb, "(%rip), %rax\n")
    for k in 0..nfg {
      push_str(sb, "  movq ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((dstg - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
  } else if is_mut_enum_global_var(v, cx.decls, cx.src) {
    ## `s := STATE` — snapshot a mutable ENUM global: copy its `1 + max_arity` `.data` words
    ## (ascending `[disc, payload…]` at LABEL + k*8) into `s`'s enum slots (word k at
    ## `-(dst+k+1)*8` — the same flat layout as a struct snapshot).
    evn := var_name_span(v)
    egli := enum_lit_info(mut_global_value(cx.decls, cx.src, evn.s, evn.n))
    enw := 1 + enum_inst_words(cx.decls, cx.src, egli.es, egli.el, a)
    edst := slot_of(cx.slots, cx.src, ns, nl2)
    push_str(sb, "  leaq ")
    emit_global_label(sb, cx.decls, cx.src, evn.s, evn.n)
    push_str(sb, "(%rip), %rax\n")
    for k in 0..enw {
      push_str(sb, "  movq ")
      push_int(sb, i64(k * 8))
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((edst - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
  } else if bin_operator_ret_struct(v, cx.decls, cx.src, cx.slots, a).n != 0 {
    ## `r := a <op> b` where `<op>` is a user operator RETURNING a struct (`@inline` or the
    ## non-inline fallback): the routed Bin (`emit_gas` → the operator path) leaves the result's
    ## `rw` words on the stack (word 0 at the bottom, word rw-1 on top). Pop them into `r`'s
    ## slots (word rw-1 first → slot base+rw-1).
    ## `r` was sized as that struct by `bin_operator_ret_struct` in collect_slots, so `r.field`
    ## resolves. A 1-word result pops exactly one word (like a scalar store).
    brs := bin_operator_ret_struct(v, cx.decls, cx.src, cx.slots, a)
    rw := struct_words(cx.decls, cx.src, brs.s, brs.n, deref(cx.mar))
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_gas(v, sb, cx, a, nl)
    for j in 0..rw {
      k := rw - 1 - j
      push_str(sb, "  popq %rax\n  movq %rax, -")
      push_int(sb, (base - i64(k) + 1) * 8)
      push_str(sb, "(%rbp)\n")
    }
  } else if bitcast_struct_target(v, cx.decls, cx.src).n != 0 {
    ## `y := bitcast(<UserStruct>, x)` — the parser-preserved aggregate reinterpret. `y` was
    ## reserved as the TARGET struct by collect_slots; copy the SOURCE aggregate `x`'s words into
    ## `y`'s slots (bit-identical, same size). The source must be a struct VAR of the SAME word
    ## count — else the reinterpret's size contract is violated; fail loud (never a silent copy).
    btsc := bitcast_struct_target(v, cx.decls, cx.src)
    inner := bitcast_inner_expr(v)
    nfbc := struct_words(cx.decls, cx.src, btsc.s, btsc.n, a)
    iva := var_agg_info(inner, cx.slots, cx.src)
    if iva.ek != 2 { panic("selfhost: bitcast to a struct expects a struct VARIABLE source (bitcast of a call/expression result to a struct is not lowered — bind the source to a local first)") }
    if struct_words(cx.decls, cx.src, iva.s, iva.n, a) != nfbc { panic("selfhost: aggregate bitcast between structs of different word size (bitcast requires same-size types)") }
    dstbc := slot_of(cx.slots, cx.src, ns, nl2)
    isvc := var_name_span(inner)
    isentc := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, isvc.s, isvc.n)))
    if isentc.is_ref {
      push_str(sb, "  movq -")
      push_int(sb, i64((isentc.off + 1) * 8))
      push_str(sb, "(%rbp), %rax\n")
      for k in 0..nfbc {
        push_str(sb, "  movq ")
        push_int(sb, i64(k * 8))
        push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
        push_int(sb, i64((dstbc - k + 1) * 8))
        push_str(sb, "(%rbp)\n")
      }
    } else {
      for k in 0..nfbc {
        push_str(sb, "  movq -")
        push_frame_word(sb, isentc.off, k)
        push_str(sb, "(%rbp), %rcx\n  movq %rcx, -")
        push_int(sb, i64((dstbc - k + 1) * 8))
        push_str(sb, "(%rbp)\n")
      }
    }
  } else if var_agg_info(v, cx.slots, cx.src).ek != 0 {
    ## `x := <struct/enum var>` — COPY the source aggregate's words into `x`'s fresh slots. A
    ## LOCAL source keeps word k at slot `off+k`; a by-REF PARAM (`is_ref`) holds a POINTER at
    ## its slot with word k at `-(k*8)(ptr)` (down-growing pointee). Struct = `nf` words; enum =
    ## `1 + payload` words (disc + payload).
    va := var_agg_info(v, cx.slots, cx.src)
    mut nfc := 0
    if va.ek == 2 { nfc = aggregate_words(cx.decls, cx.src, va.s, va.n, a) }
    else { nfc = 1 + enum_inst_words(cx.decls, cx.src, va.s, va.n, a) }
    dstc := slot_of(cx.slots, cx.src, ns, nl2)
    svc := var_name_span(v)
    sentc := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, svc.s, svc.n)))
    if sentc.is_ref {
      push_str(sb, "  movq -")
      push_int(sb, i64((sentc.off + 1) * 8))
      push_str(sb, "(%rbp), %rax\n")
      for k in 0..nfc {
        push_str(sb, "  movq ")
        push_int(sb, i64(k * 8))
        push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
        push_int(sb, i64((dstc - k + 1) * 8))
        push_str(sb, "(%rbp)\n")
      }
    } else {
      for k in 0..nfc {
        push_str(sb, "  movq -")
        push_frame_word(sb, sentc.off, k)
        push_str(sb, "(%rbp), %rcx\n  movq %rcx, -")
        push_int(sb, i64((dstc - k + 1) * 8))
        push_str(sb, "(%rbp)\n")
      }
    }
  } else if deref_view_span_cx(v, cx).n != 0 and view_dest_is_local(cx.slots, cx.src, ns, nl2) {
    ## P1-CLAYOUT S3(b) — `t := deref(<pointer to a §7 VIEW>)`: the pointee IS the two-word
    ## `{ptr, len}` pair. `emit_str_pair`'s `Deref` arm reads BOTH words at the ascending
    ## pointee offsets and `emit_pair_field_store` pops them into the destination's word 0 / 1
    ## — the same landing the `t := <str var>` copy below uses. Gated on the destination being
    ## a DIRECT 2-word view local (`bind_str_slot` bound it as one).
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_pair_field_store(v, base, sb, cx, a, nl)
  } else if view_var_kind(v, cx.slots, cx.src) != 0 and view_dest_is_local(cx.slots, cx.src, ns, nl2) {
    ## Types §9.4 / §7.2 — `t := <str/Slice(T) var>`: a plain Var-to-Var copy of a 2-word
    ## `{ptr, len}` VIEW. `emit_str_pair` already materializes the pair for every source shape
    ## (a str LOCAL's two frame words, a str/slice PARAM's pointer to the caller's pair, a slice
    ## view local's direct words), and `emit_pair_field_store` pops it into the destination's
    ## word 0 / word 1 — the same layout `emit_str_assign` / `emit_array_slice_assign` write, so
    ## every `.len` / `.ptr` / `t[i]` / `for x in t` read applies unchanged. Before this the copy
    ## fell to the generic SCALAR store below: ONE word survived, so `t.len` read 0 and a PARAM
    ## source stored the caller's pair ADDRESS instead of the data pointer — both SILENT.
    ## Gated on the destination being a DIRECT 2-word view local (`view_dest_is_local`), so a
    ## by-ref (param) destination keeps its previous lowering rather than clobbering its pointer.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_pair_field_store(v, base, sb, cx, a, nl)
  } else if field_read_agg(v, cx.slots, cx.decls, cx.src, a).kind != 0 {
    ## `x := s.f` (f a struct/enum field of a LOCAL struct) — copy the field's words from the base
    ## struct (word k at slot `boff + fwo + k`) into `x`'s fresh slots. The aggregate-field extract
    ## the scalar store dropped (it delivered only word 0 → a silent 0/garbage).
    fra := field_read_agg(v, cx.slots, cx.decls, cx.src, a)
    mut nfr := 0
    if fra.kind == 2 { nfr = aggregate_words(cx.decls, cx.src, fra.s, fra.n, a) }
    ## kind 4 = a `str` field: exactly 2 words ({ptr, len}) — the destination is a str local
    ## (`bind_str_slot`), whose word 0/1 slots descend the same way the copy loop below writes.
    else if fra.kind == 4 { nfr = 2 }
    else { nfr = 1 + enum_inst_words(cx.decls, cx.src, fra.s, fra.n, a) }
    dstr := slot_of(cx.slots, cx.src, ns, nl2)
    ## P1-CLAYOUT S3(c) — THE BYTE-PRECISE WHOLE-VALUE COPY. When the source is a nested child of a
    ## standard byte-layout root whose §6.1 image is NOT its word image, the word loop below copies
    ## whole words out of (say) a 4-byte child into a destination read back at word offsets: measured
    ## exit 1 on all three cross backends with S3(b)'s writer in and its fence out. `std_copy_kind`
    ## decides — once, in `lower_layout`, for all four backends — whether such a child has a
    ## byte-precise copy and of which shape, and `emit_standard_copy` spells the moves. A
    ## WORD-GRANULAR child is deliberately NOT routed here: for it the word copy IS the byte copy
    ## (audit §5's staging principle), so every shape that worked before keeps its exact emission.
    ## `standard_field_path` is re-walked rather than threaded through `FieldAgg`, so the byte offset
    ## comes from the same query the READERS use instead of a second copy of the sum.
    s3cp := standard_field_path(v, cx.slots, cx.decls, cx.src, a)
    mut s3cok := false
    if s3cp.ok and fra.kind == 2 and not fra.isr and not std_struct_is_word_granular(cx.decls, cx.src, s3cp.ts, s3cp.tl, a) {
      if std_copy_kind(cx.decls, cx.src, s3cp.ts, s3cp.tl, a) != 0 { s3cok = true }
    }
    if s3cok { emit_standard_copy(s3cp.ts, s3cp.tl, s3cp.root, s3cp.bo, dstr, sb, cx, a) }
    if (not s3cok) and fra.isr {
      ## a BY-REFERENCE struct base (`f(g : G) { c := g.inner }`): the slot holds a POINTER to the
      ## caller's word 0 and the pointee's words ASCEND (`+k*8`), so the field's word k is at
      ## `(fwo + k)*8(%rax)`. The frame formula below treated the pointer slot as the struct itself
      ## and computed an offset off the end of the frame — the compiler's own checked arithmetic
      ## then trapped (`ud2`, a bare SIGILL with NO diagnostic) instead of emitting anything.
      push_str(sb, "  movq -")
      push_int(sb, i64((fra.boff + 1) * 8))
      push_str(sb, "(%rbp), %rax\n")
      for k in 0..nfr {
        push_str(sb, "  movq ")
        push_int(sb, (fra.fwo + i64(k)) * 8)
        push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
        push_int(sb, i64((dstr - k + 1) * 8))
        push_str(sb, "(%rbp)\n")
      }
    }
    if (not s3cok) and (not fra.isr) {
    ## DEFENSIVE (I11): the copier arm above OWNS every byte-tier child whose §6.1 image is not its word
    ## image, and `field_read_agg` reports `fwo = 0` for exactly those — so if one ever reached this word
    ## loop it would copy from word 0 and produce a wrong value silently. The two predicates are the same
    ## pair `field_read_agg` used, so this cannot fire today; it is here so that a future divergence
    ## between the resolver's claim and this emit is a trap rather than a miscompile.
    if s3cp.ok and fra.kind == 2 and not std_struct_is_word_granular(cx.decls, cx.src, s3cp.ts, s3cp.tl, a) {
      panic("selfhost: a byte-precise whole-value copy reached the WORD extract — `field_read_agg` claimed it for the copier (fwo = 0) but the emit did not route it there; the two gates have diverged")
    }
    for k in 0..nfr {
      push_str(sb, "  movq -")
      push_int(sb, (i64(fra.boff) - fra.fwo - i64(k) + 1) * 8)
      push_str(sb, "(%rbp), %rcx\n  movq %rcx, -")
      push_int(sb, i64((dstr - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
    }
  } else if global_field_agg(v, cx.decls, cx.src, a).kind != 0 {
    ## `x := STATE.f` (f a struct/enum field of a GLOBAL struct) — copy the field's words from
    ## `.data` (ASCENDING: `LABEL + (fwo+k)*8`) into x's slots.
    gfa := global_field_agg(v, cx.decls, cx.src, a)
    mut ngf := 0
    if gfa.kind == 2 { ngf = aggregate_words(cx.decls, cx.src, gfa.s, gfa.n, a) }
    else { ngf = 1 + enum_inst_words(cx.decls, cx.src, gfa.s, gfa.n, a) }
    dstg := slot_of(cx.slots, cx.src, ns, nl2)
    push_str(sb, "  leaq ")
    emit_global_label(sb, cx.decls, cx.src, gfa.gs, gfa.gn)
    push_str(sb, "(%rip), %rax\n")
    for k in 0..ngf {
      push_str(sb, "  movq ")
      push_int(sb, (gfa.fwo + i64(k)) * 8)
      push_str(sb, "(%rax), %rcx\n  movq %rcx, -")
      push_int(sb, i64((dstg - k + 1) * 8))
      push_str(sb, "(%rbp)\n")
    }
  } else if match_if_agg_kind(v, cx.decls, cx.src, a).kind != 0 {
    ## a `name := match/if { … => <agg/str> }` whose value is a struct/enum/tuple/str — deliver
    ## each arm/branch's value into the local's slots (aggregates + strs do not materialize on
    ## the stack in bare expr position, so the generic scalar store would truncate them). The
    ## local-binding dual of the aggregate/str value delivery via match/if in a return.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    smi := match_info(v)
    if smi.is_m {
      emit_val_match_to_local(smi.scrut, smi.head, base, sb, cx, a, nl)
    } else {
      sii := if_info(v)
      emit_val_if_to_local(sii.cond, sii.then_e, sii.else_e, base, sb, cx, a, nl)
    }
  } else if direct_num_float_target(v, cx.src, ns, nl2) != 0 {
    ## TYP-13: only the direct Num + explicit f32/f64 binding shape uses the conversion seam;
    ## explicit FloatLit values and ordinary integer locals retain their existing emit_gas path.
    base := slot_of(cx.slots, cx.src, ns, nl2)
    emit_direct_num_float_assign(v, direct_num_float_target(v, cx.src, ns, nl2), base, sb, cx, a, nl)
  } else {
    ## a `name := arr[i]` of an AGGREGATE-element array is a WHOLE-ELEMENT copy into the
    ## local's reserved aggregate slots (the local was bound as that struct/enum); any
    ## other value is a scalar — lower it and pop into the name's single slot.
    ivl := index_value_layout(v, cx.slots, cx.src, cx.decls, a)
    if ivl.is_agg {
      dst := slot_of(cx.slots, cx.src, ns, nl2)
      emit_elem_copy_in(ivl.arr, ivl.idx, dst, sb, cx, nl)
    } else {
      emit_gas(v, sb, cx, a, nl)
      tent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, ns, nl2)))
      if tent.ek == 8 {
        ## OUT-SCALAR param target `r = v`: load the slot's POINTER and store the value
        ## THROUGH it — the write is visible to the caller (the dual of the ek-8 Var read).
        push_str(sb, "  popq %rbx\n  movq -")
        push_int(sb, (tent.off + 1) * 8)
        push_str(sb, "(%rbp), %rax\n  movq %rbx, (%rax)\n")
      } else {
        push_str(sb, "  popq %rax\n  movq %rax, -")
        push_int(sb, (tent.off + 1) * 8)
        push_str(sb, "(%rbp)\n")
      }
    }
  }
}
