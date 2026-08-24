## selfhost::iface — deterministic module-interface/layout summary (TOOL-6).
##
## This is deliberately a scalar/span-oriented seam. The emitter still consumes the flat Decl
## vector, while this module records facts a dependent can observe at an exported boundary. It is
## output-neutral substrate for the future emit cache; it does not change name resolution or codegen.
(push_str, push_byte, vec_get, vec_len) := rt
(Decl, FieldDecl, Param) := ast
fld_p := ast::fld_p
param_p := ast::param_p
(fn_is_inline, decl_is_pub, param_is_comptime, type_is_variadic_rest, decl_is_variadic, decl_is_slice_variadic) := lower_attrs
(layout_kind, layout_kind_is_packed, layout_kind_is_byte, struct_words, field_words, field_word_offset, packed_struct_bytes, packed_struct_align, field_offset_attr, field_align_attr, field_endian_attr, struct_align_attr, field_byte_size, packed_field_byte_offset, standard_field_byte_offset, standard_struct_bytes, standard_struct_align, enum_layout, enum_repr_ty, repr_tag_code, enum_inst_words, enum_max_arity, variant_index, variant_payload_span, is_union_decl, union_words, is_niche_folded, round_up_to) := lower_layout
mut SUMMARY_P : usize = 0
mut SUMMARY_N : usize = 0

pub summary_ptr := fn() -> usize { SUMMARY_P }
pub summary_len := fn() -> usize { SUMMARY_N }

## FNV-1a helpers. Deliberate usize overflow is the hash operation, not language arithmetic.
iface_hash_byte := fn(h : usize, b : usize) -> usize {
  unchecked { return (h ^ b) * 1099511628211 }
}
iface_hash_uint := fn(h : usize, n : usize) -> usize {
  mut r := h
  mut v := n
  mut i := 0
  while i < 8 {
    r = iface_hash_byte(r, v % 256)
    v = v / 256
    i += 1
  }
  r
}
iface_hash_int := fn(h : usize, n : i64) -> usize {
  iface_hash_uint(h, unchecked bitcast(usize, n))
}
iface_hash_span := fn(h : usize, src : ptr(u8), s : usize, n : usize) -> usize {
  mut r := iface_hash_uint(h, n)
  mut i := 0
  while i < n {
    r = iface_hash_byte(r, usize(bytes(str_at((src + s), n))[i]))
    i += 1
  }
  r
}

## The runtime's signed renderer is not safe for arbitrary usize hashes, so print unsigned decimal.
iface_push_uint := fn(in out b : rt::StrBuf, n : usize) {
  q := n / 10
  if q != 0 { iface_push_uint(b, q) }
  push_byte(b, u8(n % 10 + 48))
}
iface_push_int := fn(in out b : rt::StrBuf, n : i64) {
  if n < 0 {
    push_byte(b, 45)
    iface_push_uint(b, unchecked bitcast(usize, 0 - n))
  } else {
    iface_push_uint(b, unchecked bitcast(usize, n))
  }
}
iface_push_bool := fn(in out b : rt::StrBuf, v : bool) {
  if v { push_str(b, "1") } else { push_str(b, "0") }
}
iface_push_span := fn(in out b : rt::StrBuf, src : ptr(u8), s : usize, n : usize) {
  if n == 0 { push_str(b, "-") } else { push_str(b, str_at((src + s), n)) }
}

iface_ws := fn(src : ptr(u8), p : usize) -> bool {
  c := str_at((src + p), 1)
  c == " " or c == "\n" or c == "\t" or c == "\r"
}
iface_ident := fn(c : str) -> bool {
  (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"
}

## Skip one source-level effector beginning at `@p`; returns the first byte after its optional args.
iface_skip_attr := fn(src : ptr(u8), p0 : usize) -> usize {
  mut p := p0
  if str_at((src + p), 1) == "@" { p += 1 }
  while iface_ident(str_at((src + p), 1)) { p += 1 }
  if str_at((src + p), 1) == "(" {
    mut depth := 1
    p += 1
    while depth > 0 {
      c := str_at((src + p), 1)
      if c == "\"" {
        p += 1
        while str_at((src + p), 1) != "\"" { p += 1 }
        p += 1
      } else if c == "(" { depth += 1 ; p += 1 }
      else if c == ")" { depth -= 1 ; p += 1 }
      else { p += 1 }
    }
  }
  p
}

## The parser consumes declaration attributes. Check both `name := @attr …` and prefix forms.
iface_has_attr := fn(src : ptr(u8), name_s : usize, name_l : usize, marker : str) -> bool {
  mut p := name_s + name_l
  while iface_ws(src, p) { p += 1 }
  if str_at((src + p), 2) == ":=" {
    p += 2
    while iface_ws(src, p) { p += 1 }
    mut scanning := true
    while scanning and str_at((src + p), 1) == "@" {
      if str_at((src + p), marker.len) == marker { return true }
      p = iface_skip_attr(src, p)
      while iface_ws(src, p) { p += 1 }
    }
  }
  mut start := name_s
  mut steps := 0
  while start > 0 and steps < 2048 {
    c := str_at((src + start - 1), 1)
    if c == "}" or c == ";" { break }
    start -= 1
    steps += 1
  }
  p = start
  while p < name_s {
    if str_at((src + p), marker.len) == marker {
      before := if p == start { " " } else { str_at((src + p - 1), 1) }
      after := str_at((src + p + marker.len), 1)
      if (before == " " or before == "\n" or before == "\t" or before == "\r" or before == "@") and not iface_ident(after) { return true }
    }
    p += 1
  }
  false
}

iface_visible := fn(src : ptr(u8), name_s : usize, name_n : usize) -> bool {
  decl_is_pub(src, name_s) or iface_has_attr(src, name_s, name_n, "@export")
}
iface_kind := fn(k : u8) -> str {
  if k == 0 { return "value" }
  if k == 1 { return "fn" }
  if k == 2 { return "struct" }
  if k == 3 { return "enum" }
  if k == 4 { return "syscall" }
  if k == 5 { return "test" }
  "unknown"
}

iface_decl_at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
iface_decl_get := fn(decls : ptr(rt::Vec), i : usize) -> ptr(Decl) {
  return iface_decl_at(Decl, vec_get(deref(decls), i))
}
iface_streq := fn(src : ptr(u8), as : usize, an : usize, bs : usize, bn : usize) -> bool {
  if an != bn { return false }
  str_at((src + as), an) == str_at((src + bs), bn)
}
iface_overloads := fn(decls : ptr(rt::Vec), src : ptr(u8), name_s : usize, name_n : usize, arity : usize, is_fn : bool) -> usize {
  mut n := 0
  mut i := 0
  while i < vec_len(deref(decls)) {
    qp := iface_decl_get(decls, i)
    if deref(qp).is_fn and is_fn and deref(qp).arity == arity and iface_streq(src, deref(qp).name_start, deref(qp).name_len, name_s, name_n) { n += 1 }
    i += 1
  }
  n
}

iface_emit_struct := fn(in out b : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), dp : ptr(Decl), a : rt::Arena) -> usize {
  ns := deref(dp).name_start
  nn := deref(dp).name_len
  generic := deref(dp).is_generic
  ## THE ORACLE (`lower_layout::layout_kind`) picks the tier, the same decision the value paths and the
  ## `size`/`align` folds make. The hash records the tier (`packed`/`byte_layout`) as well as the sizes,
  ## so a partially migrated layout shows up as a cross-module interface mismatch, by design.
  lk := layout_kind(decls, src, ns, nn, a)
  mut packed := layout_kind_is_packed(lk)
  mut byte_layout := false
  mut words := usize(0)
  mut size := usize(0)
  mut align := usize(0)
  if packed {
    size = packed_struct_bytes(decls, src, ns, nn, a)
    align = packed_struct_align(decls, src, ns, nn)
  } else if layout_kind_is_byte(lk) {
    byte_layout = true
    size = standard_struct_bytes(decls, src, ns, nn, a)
    align = standard_struct_align(decls, src, ns, nn, a)
  } else {
    words = struct_words(decls, src, ns, nn, a)
    size = words * 8
    sa := struct_align_attr(decls, src, ns, nn)
    if sa >= 1 { align = usize(sa) } else { align = 8 }
    size = round_up_to(size, align)
  }
  niche := is_niche_folded(src, ns, nn)
  mut h := usize(1469598103934665603)
  h = iface_hash_uint(h, 2)
  h = iface_hash_span(h, src, ns, nn)
  h = iface_hash_uint(h, size)
  h = iface_hash_uint(h, align)
  h = iface_hash_uint(h, words)
  h = iface_hash_uint(h, usize(packed))
  h = iface_hash_uint(h, usize(byte_layout))
  h = iface_hash_uint(h, 0)
  h = iface_hash_uint(h, 0)
  h = iface_hash_uint(h, usize(niche))
  push_str(b, "decl kind=struct name=")
  iface_push_span(b, src, ns, nn)
  push_str(b, " public=")
  iface_push_bool(b, iface_visible(src, ns, nn))
  push_str(b, " generic=")
  iface_push_bool(b, generic)
  push_str(b, " packed=")
  iface_push_bool(b, packed)
  push_str(b, " byte_layout=")
  iface_push_bool(b, byte_layout)
  push_str(b, " size=")
  iface_push_uint(b, size)
  push_str(b, " align=")
  iface_push_uint(b, align)
  push_str(b, " niche=")
  iface_push_bool(b, niche)
  push_str(b, " layout_hash=")
  mut field := deref(dp).fields_head
  while field != 0 {
    fd := deref(fld_p(field))
    fw := fd.wsize
    mut fwords := usize(0)
    if fw != 0 { fwords = field_words(decls, src, fd.ts, fd.tl, fw, a) }
    mut off : i64 = -1
    if packed { off = packed_field_byte_offset(decls, src, ns, nn, fd.ns, fd.nl, a) }
    else if byte_layout { off = standard_field_byte_offset(decls, src, ns, nn, fd.ns, fd.nl, a) }
    else { off = i64(field_word_offset(decls, src, ns, nn, fd.ns, fd.nl, a)) * 8 }
    mut sz := usize(0)
    if fw != 0 { sz = field_byte_size(decls, src, fd.ts, fd.tl, fw, a) }
    fa := field_align_attr(src, fd.ns)
    fe := field_endian_attr(src, fd.ns)
    fo := field_offset_attr(src, fd.ns)
    h = iface_hash_span(h, src, fd.ns, fd.nl)
    h = iface_hash_span(h, src, fd.ts, fd.tl)
    h = iface_hash_uint(h, fw)
    h = iface_hash_uint(h, fwords)
    h = iface_hash_int(h, off)
    h = iface_hash_uint(h, sz)
    h = iface_hash_int(h, fa)
    h = iface_hash_int(h, fe)
    h = iface_hash_int(h, fo)
    field = fd.next
  }
  iface_push_uint(b, h)
  push_byte(b, 10)
  field = deref(dp).fields_head
  while field != 0 {
    fd := deref(fld_p(field))
    fw := fd.wsize
    mut fwords := usize(0)
    if fw != 0 { fwords = field_words(decls, src, fd.ts, fd.tl, fw, a) }
    mut off : i64 = -1
    if packed { off = packed_field_byte_offset(decls, src, ns, nn, fd.ns, fd.nl, a) }
    else if byte_layout { off = standard_field_byte_offset(decls, src, ns, nn, fd.ns, fd.nl, a) }
    else { off = i64(field_word_offset(decls, src, ns, nn, fd.ns, fd.nl, a)) * 8 }
    mut sz := usize(0)
    if fw != 0 { sz = field_byte_size(decls, src, fd.ts, fd.tl, fw, a) }
    push_str(b, "field name=")
    iface_push_span(b, src, fd.ns, fd.nl)
    push_str(b, " type=")
    iface_push_span(b, src, fd.ts, fd.tl)
    push_str(b, " wsize=")
    iface_push_uint(b, fw)
    push_str(b, " words=")
    iface_push_uint(b, fwords)
    push_str(b, " offset=")
    iface_push_int(b, off)
    push_str(b, " size=")
    iface_push_uint(b, sz)
    push_str(b, " align_attr=")
    iface_push_int(b, field_align_attr(src, fd.ns))
    push_str(b, " offset_attr=")
    iface_push_int(b, field_offset_attr(src, fd.ns))
    push_str(b, " endian=")
    iface_push_int(b, field_endian_attr(src, fd.ns))
    push_byte(b, 10)
    field = fd.next
  }
  h
}

iface_emit_enum := fn(in out b : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), dp : ptr(Decl), a : rt::Arena) -> usize {
  ns := deref(dp).name_start
  nn := deref(dp).name_len
  generic := deref(dp).is_generic
  el := enum_layout(decls, src, ns, nn, a)
  rp := enum_repr_ty(decls, src, ns, nn)
  mut repr_code := usize(0)
  if rp.n != 0 { repr_code = repr_tag_code(src, rp.s, rp.n) }
  niche := is_niche_folded(src, ns, nn)
  mut h := usize(1469598103934665603)
  h = iface_hash_uint(h, 3)
  h = iface_hash_span(h, src, ns, nn)
  h = iface_hash_uint(h, el.size)
  h = iface_hash_uint(h, el.align)
  h = iface_hash_uint(h, el.payload_words)
  h = iface_hash_uint(h, 0)
  h = iface_hash_uint(h, 0)
  h = iface_hash_uint(h, usize(el.is_union))
  h = iface_hash_uint(h, repr_code)
  h = iface_hash_uint(h, usize(niche))
  h = iface_hash_span(h, src, rp.s, rp.n)
  h = iface_hash_uint(h, enum_max_arity(decls, src, ns, nn, a))
  h = iface_hash_uint(h, enum_inst_words(decls, src, ns, nn, a))
  push_str(b, "decl kind=enum name=")
  iface_push_span(b, src, ns, nn)
  push_str(b, " public=")
  iface_push_bool(b, iface_visible(src, ns, nn))
  push_str(b, " generic=")
  iface_push_bool(b, generic)
  push_str(b, " union=")
  iface_push_bool(b, el.is_union)
  push_str(b, " size=")
  iface_push_uint(b, el.size)
  push_str(b, " align=")
  iface_push_uint(b, el.align)
  push_str(b, " repr_code=")
  iface_push_uint(b, repr_code)
  push_str(b, " repr=")
  iface_push_span(b, src, rp.s, rp.n)
  push_str(b, " niche=")
  iface_push_bool(b, niche)
  push_str(b, " layout_hash=")
  mut field := deref(dp).fields_head
  while field != 0 {
    fd := deref(fld_p(field))
    vi := variant_index(decls, src, ns, nn, fd.ns, fd.nl, a)
    ps := variant_payload_span(decls, src, ns, nn, fd.ns, fd.nl, a)
    h = iface_hash_span(h, src, fd.ns, fd.nl)
    h = iface_hash_uint(h, fd.arity)
    h = iface_hash_span(h, src, fd.ts, fd.tl)
    h = iface_hash_int(h, vi)
    h = iface_hash_span(h, src, ps.s, ps.n)
    field = fd.next
  }
  iface_push_uint(b, h)
  push_byte(b, 10)
  field = deref(dp).fields_head
  while field != 0 {
    fd := deref(fld_p(field))
    vi := variant_index(decls, src, ns, nn, fd.ns, fd.nl, a)
    ps := variant_payload_span(decls, src, ns, nn, fd.ns, fd.nl, a)
    push_str(b, "variant name=")
    iface_push_span(b, src, fd.ns, fd.nl)
    push_str(b, " index=")
    iface_push_int(b, vi)
    push_str(b, " arity=")
    iface_push_uint(b, fd.arity)
    push_str(b, " type=")
    iface_push_span(b, src, ps.s, ps.n)
    push_byte(b, 10)
    field = fd.next
  }
  h
}

iface_emit_fn := fn(in out b : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), dp : ptr(Decl), a : rt::Arena) -> usize {
  ns := deref(dp).name_start
  nn := deref(dp).name_len
  arity := deref(dp).arity
  inline := fn_is_inline(src, ns, nn)
  exported := iface_has_attr(src, ns, nn, "@export")
  externed := iface_has_attr(src, ns, nn, "@extern")
  converted := iface_has_attr(src, ns, nn, "@convert")
  abi := iface_has_attr(src, ns, nn, "@abi")
  mut h := usize(1469598103934665603)
  h = iface_hash_uint(h, 1)
  h = iface_hash_span(h, src, ns, nn)
  h = iface_hash_uint(h, arity)
  h = iface_hash_uint(h, usize(deref(dp).is_generic))
  h = iface_hash_uint(h, usize(inline))
  h = iface_hash_uint(h, usize(exported))
  h = iface_hash_uint(h, usize(externed))
  h = iface_hash_uint(h, usize(converted))
  h = iface_hash_uint(h, usize(abi))
  h = iface_hash_span(h, src, deref(dp).ret_ts, deref(dp).ret_tl)
  mut variadic := false
  mut slice_variadic := false
  mut p := deref(dp).params_head
  mut pi := 0
  while p != 0 {
    pm := deref(param_p(p))
    h = iface_hash_uint(h, usize(pi))
    h = iface_hash_uint(h, usize(pm.pmode))
    h = iface_hash_uint(h, usize(param_is_comptime(src, pm.ns)))
    h = iface_hash_span(h, src, pm.ts, pm.tl)
    h = iface_hash_span(h, src, pm.pps, pm.ppl)
    if pm.next == 0 {
      variadic = type_is_variadic_rest(src, pm.ts, pm.tl)
      slice_variadic = pm.pmode == 3
    }
    p = pm.next
    pi += 1
  }
  push_str(b, "decl kind=")
  push_str(b, iface_kind(deref(dp).kind))
  push_str(b, " name=")
  iface_push_span(b, src, ns, nn)
  push_str(b, " public=")
  iface_push_bool(b, iface_visible(src, ns, nn))
  push_str(b, " generic=")
  iface_push_bool(b, deref(dp).is_generic)
  push_str(b, " arity=")
  iface_push_uint(b, arity)
  push_str(b, " overloads=")
  iface_push_uint(b, iface_overloads(decls, src, ns, nn, arity, deref(dp).is_fn))
  push_str(b, " export=")
  iface_push_bool(b, exported)
  push_str(b, " extern=")
  iface_push_bool(b, externed)
  push_str(b, " convert=")
  iface_push_bool(b, converted)
  push_str(b, " abi=")
  iface_push_bool(b, abi)
  push_str(b, " inline=")
  iface_push_bool(b, inline)
  push_str(b, " variadic=")
  iface_push_bool(b, variadic)
  push_str(b, " slice_variadic=")
  iface_push_bool(b, slice_variadic)
  push_str(b, " ret=")
  iface_push_span(b, src, deref(dp).ret_ts, deref(dp).ret_tl)
  push_str(b, " signature_hash=")
  iface_push_uint(b, h)
  push_byte(b, 10)
  p = deref(dp).params_head
  pi = 0
  while p != 0 {
    pm := deref(param_p(p))
    push_str(b, "param index=")
    iface_push_uint(b, pi)
    push_str(b, " mode=")
    iface_push_uint(b, usize(pm.pmode))
    push_str(b, " comptime=")
    iface_push_bool(b, param_is_comptime(src, pm.ns))
    push_str(b, " type=")
    iface_push_span(b, src, pm.ts, pm.tl)
    push_str(b, " pointee=")
    iface_push_span(b, src, pm.pps, pm.ppl)
    push_byte(b, 10)
    p = pm.next
    pi += 1
  }
  h
}

iface_emit_value := fn(in out b : rt::StrBuf, src : ptr(u8), dp : ptr(Decl)) -> usize {
  ns := deref(dp).name_start
  nn := deref(dp).name_len
  mut h := usize(1469598103934665603)
  h = iface_hash_uint(h, usize(deref(dp).kind))
  h = iface_hash_span(h, src, ns, nn)
  h = iface_hash_uint(h, deref(dp).arity)
  h = iface_hash_span(h, src, deref(dp).alias_ts, deref(dp).alias_tl)
  push_str(b, "decl kind=")
  push_str(b, iface_kind(deref(dp).kind))
  push_str(b, " name=")
  iface_push_span(b, src, ns, nn)
  push_str(b, " public=")
  iface_push_bool(b, iface_visible(src, ns, nn))
  push_str(b, " generic=")
  iface_push_bool(b, deref(dp).is_generic)
  push_str(b, " type=")
  iface_push_span(b, src, deref(dp).alias_ts, deref(dp).alias_tl)
  push_str(b, " value_hash=")
  iface_push_uint(b, h)
  push_byte(b, 10)
  h
}

iface_emit_decl := fn(in out b : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), dp : ptr(Decl), a : rt::Arena) -> usize {
  if deref(dp).kind == 2 { return iface_emit_struct(b, decls, src, dp, a) }
  if deref(dp).kind == 3 { return iface_emit_enum(b, decls, src, dp, a) }
  if deref(dp).is_fn or deref(dp).kind == 4 { return iface_emit_fn(b, decls, src, dp, a) }
  iface_emit_value(b, src, dp)
}

## Return the end of the contiguous decl run owned by the same module as `i`. The parser/driver
## currently append each source module as one run; retaining the exact (start,len) comparison makes
## a future non-contiguous decl source split surface as two deterministic runs rather than silently
## merging unrelated declarations.
iface_module_end := fn(decls : ptr(rt::Vec), i : usize) -> usize {
  cnt := vec_len(deref(decls))
  if i >= cnt { return i }
  first := iface_decl_get(decls, i)
  ms := deref(first).mod_start
  ml := deref(first).mod_len
  mut j := i + 1
  mut go := true
  while go {
    mut same := false
    if j < cnt {
      next := iface_decl_get(decls, j)
      if deref(next).mod_start == ms and deref(next).mod_len == ml { same = true }
    }
    if same == false { go = false }
    if same { j += 1 }
  }
  j
}

## A split build may append bookkeeping/monomorphized decl runs carrying the same module span as a
## source module. They are not part of the exported interface when the run has no visible decls;
## omit the whole run so module_count, per-module hashes, and the serialized module list describe
## only deterministic source-visible interface facts.
iface_module_has_visible := fn(decls : ptr(rt::Vec), src : ptr(u8), i : usize, j : usize) -> bool {
  mut k := i
  while k < j {
    kp := iface_decl_get(decls, k)
    if deref(kp).name_len != 0 and iface_visible(src, deref(kp).name_start, deref(kp).name_len) { return true }
    k += 1
  }
  false
}

## Build and retain the sidecar in the caller's arena. The pointer remains valid until the current
## compilation returns, which is exactly when cli writes `<output>.interface`.
pub emit_interface_summary := fn(decls : ptr(rt::Vec), src : ptr(u8), b : ptr(rt::StrBuf), a : rt::Arena) -> i64 {
  SUMMARY_P = 0
  SUMMARY_N = 0
  mut out := deref(b)
  push_str(out, "format=alatyr-interface-summary\nversion=1\nhash=fnv1a64\n")
  mut count := 0
  mut i := 0
  while i < vec_len(deref(decls)) {
    dp := iface_decl_get(decls, i)
    if deref(dp).name_len != 0 and iface_visible(src, deref(dp).name_start, deref(dp).name_len) { count += 1 }
    i += 1
  }
  push_str(out, "decl_count=")
  iface_push_uint(out, count)
  push_byte(out, 10)
  mut module_count := 0
  i = 0
  while i < vec_len(deref(decls)) {
    j := iface_module_end(decls, i)
    if iface_module_has_visible(decls, src, i, j) { module_count += 1 }
    i = j
  }
  push_str(out, "module_count=")
  iface_push_uint(out, module_count)
  push_byte(out, 10)
  mut overall := usize(1469598103934665603)
  i = 0
  while i < vec_len(deref(decls)) {
    j := iface_module_end(decls, i)
    if iface_module_has_visible(decls, src, i, j) {
      dp := iface_decl_get(decls, i)
      push_str(out, "module=")
      if deref(dp).mod_len == 0 { push_str(out, "<default>") } else { iface_push_span(out, src, deref(dp).mod_start, deref(dp).mod_len) }
      push_byte(out, 10)
      mut module_hash := usize(1469598103934665603)
      module_hash = iface_hash_span(module_hash, src, deref(dp).mod_start, deref(dp).mod_len)
      mut k := i
      while k < j {
        kp := iface_decl_get(decls, k)
        if deref(kp).name_len != 0 and iface_visible(src, deref(kp).name_start, deref(kp).name_len) {
          dh := iface_emit_decl(out, decls, src, kp, a)
          module_hash = iface_hash_uint(module_hash, dh)
        }
        k += 1
      }
      push_str(out, "module_interface_hash=")
      iface_push_uint(out, module_hash)
      push_byte(out, 10)
      overall = iface_hash_uint(overall, module_hash)
    }
    i = j
  }
  push_str(out, "interface_hash=")
  iface_push_uint(out, overall)
  push_byte(out, 10)
  SUMMARY_P = unchecked bitcast(usize, out.data)
  SUMMARY_N = out.len
  deref(b) = out
  0
}
