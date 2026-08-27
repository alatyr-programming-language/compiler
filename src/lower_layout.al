## selfhost::lower_layout — pure decl-layout queries for the lowering pass.
##
## Extracted from `lower.al` (which had grown past 3000 lines): these functions read the
## `Decl` vector + source bytes and return **scalar** layout facts — a struct/enum's decl
## index, field/variant indices, word sizes/offsets, payload arity. They touch no codegen
## state (`LCtx`/`StrBuf`/`SlotEntry`), so they factor out cleanly and `lower.al` calls them
## by the qualified path `lower_layout::<fn>` (Modules §4.1). This split also exercises the
## self-host cross-module surface (a sibling submodule of the `selfhost` package root,
## reached by `::`), the same machinery `driver` uses for `lexer`/`parser`/`lower`.
vec := alloc::vec
(Arg, Bind, Decl, Expr, FieldDecl, Param, Stmt) := ast
(bnd_ns, bnd_nl, bnd_next) := ast
stmt_p := ast::stmt_p
(int_lit_err, dec_val) := lexrt
fld_p := ast::fld_p
param_p := ast::param_p
arg_p := ast::arg_p

## Do two source spans denote the same name (content equality), mirroring nameres/sema.
## (Duplicated from `lower.al` — a 4-line leaf so the module is self-contained; cross-module
## constant churn is avoided.)
streq := fn(src : ptr(u8), a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool {
  ## PERF: length-first fast reject — most scan comparisons are against a different-length name, and this
  ## skips constructing both str views + the byte compare. Byte-neutral.
  if a_n != b_n { return false }
  ## `src + a_s` is POINTER arithmetic (`a_s`/`b_s` may be a REBASED handle for a comptime-synthesized
  ## name), so route through `rt::addr` — address arithmetic, not a checked integer `+` (I11 / CG-8).
  wa := str_at((src + a_s), a_n)
  wb := str_at((src + b_s), b_n)
  wa == wb
}

## Find the first top-level declaration assignment for local `[ns,nl)` in a statement list.
## Every non-declaring statement advances through its `next` link; this is deliberately FLAT —
## callers that need nested-scope discovery use their own recursive slot/handle walkers. Keeping
## this one `Stmt` dispatch here prevents backend-local type recovery from growing five subtly
## different variant lists (notably, `IndexAssign` must not hide a declaration that follows it).
pub local_decl_assign := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize) -> ptr(mut Stmt) {
  mut s := head
  mut r := unchecked bitcast(ptr(mut Stmt), 0)
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) { r = s ; done = true }
        s = nx
      }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::Match(c, ah, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::DerefAssign(dpe, dval, nx) => { s = nx }
      Stmt::IndexAssign(iab, iai, iav, nx) => { s = nx }
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, nx) => { s = nx }
      Stmt::Loop(lb, nx) => { s = nx }
      Stmt::Break(bv, bd, nx) => { s = nx }
      Stmt::Continue(cd, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::CompIf(cc, th, el, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, cb, nx) => { s = nx }
      Stmt::CompMatch(cm, ah, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::Unchecked(ub, nx) => { s = nx }
      Stmt::AllocWith(aa, ab, nx) => { s = nx }
      _ => { s = 0 }
    }
  }
  r
}

## A typed pointer to the `Decl` record at rt-arena address `h` (the decls handle = the
## down-growing top-of-block slot `dnode` returns). Mirrors `lower::decl_at` (a 1-line leaf
## duplicated so this module is self-contained, like `streq` above). The decls vector now holds
## rt HANDLES (addresses), not inline `Decl`s, so a lookup maps an index through `rt::vec_get`
## to its handle, then `deref(decl_at(...))` copies the record in.
decl_at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
## a direct typed accessor for decl `i` (encapsulates the usize-handle recovery).
decl_get := fn(decls : ptr(rt::Vec), i : usize) -> ptr(Decl) { hh := rt::vec_get(deref(decls), i) ; return decl_at(Decl, hh) }
## A typed pointer to the AST node at arena OFFSET `h` (lean replacement for `get`; mirrors
## `parser::node_ptr`). Used to read `FieldDecl`s when walking a struct/enum's field list.
node_ptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}

## Shared logical enum/union layout contract for the current word-granular representation. Byte
## offsets are intentional: ordinary enums place the tag at 0 and payload at 8; raw unions overlap
## their payload at 0. `tag_size` is the current storage slot width (8); @repr tag-width and
## variant-level byte layout are deliberately not inferred here yet. No storage direction is stored:
## frame, global, and ABI copies use these logical offsets with their own traversal direction.
EnumLayout := struct {
  tag_offset : usize, tag_size : usize, tag_align : usize,
  payload_offset : usize, payload_size : usize, payload_align : usize,
  payload_words : usize, size : usize, align : usize, is_union : bool,
}

pub enum_layout := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> EnumLayout {
  ebn := base_type_name(src, s, n)
  if enum_decl_of(decls, src, ebn.s, ebn.n) < 0 {
    return EnumLayout(tag_offset = 0, tag_size = 0, tag_align = 0, payload_offset = 0, payload_size = 0, payload_align = 0, payload_words = 0, size = 0, align = 0, is_union = false)
  }
  if is_union_decl(decls, src, ebn.s, ebn.n) {
    pw := union_words(decls, src, ebn.s, ebn.n, a)
    return EnumLayout(tag_offset = 0, tag_size = 0, tag_align = 1, payload_offset = 0, payload_size = pw * 8, payload_align = 8, payload_words = pw, size = pw * 8, align = 8, is_union = true)
  }
  pw := enum_inst_words(decls, src, s, n, a)
  EnumLayout(tag_offset = 0, tag_size = 8, tag_align = 8, payload_offset = 8, payload_size = pw * 8, payload_align = 8, payload_words = pw, size = (1 + pw) * 8, align = 8, is_union = false)
}

pub enum_layout_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  l := enum_layout(decls, src, s, n, a)
  if l.size == 0 { return 0 }
  l.size / 8
}

## Strip a `mod::` qualifier from a TYPE-name span `[s, s+n)` → the bare type name span. A
## cross-module qualified type reference (`m0::P`, the shape `main` uses to construct a struct
## defined in another module) must resolve to the decl by its TAIL name `P` (mirroring nameres +
## `lower::generic_decl_of`). Returns `[s, s+n)` unchanged when unqualified. Scans for the first
## `:` byte (the `::` separator); the head length is its offset, the tail starts after `::`.
LSpan := struct { s : usize, n : usize }

pub name_tail := fn(src : ptr(u8), s : usize, n : usize) -> LSpan {
  mut i := 0
  mut cp := -1
  while i < n {
    ## `src + s + i` is POINTER arithmetic: `s` may be a REBASED handle (`s = name_ptr - src`) for a
    ## comptime-SYNTHESIZED type name, so `src + s` modularly reconstructs `name_ptr`. Route through
    ## `rt::addr` (address arithmetic), not a checked integer `+` (I11 / CG-8).
    if str_at(((src + s) + i), 1) == ":" { cp = i64(i); i = n } else { i = i + 1 }
  }
  if cp >= 0 {
    hl := usize(cp)
    return LSpan(s = (s + hl + 2), n = n - hl - 2)
  }
  LSpan(s = s, n = n)
}

## The module head of a qualified TYPE path (`a::b::T` -> `a::b`), or 0/0 for a bare type.
## Kept separate from `name_tail` so declaration lookup can enforce nominal module identity instead
## of using a same-tail declaration from whichever module happened to be scanned last. `p_factor`
## stores a qualified VALUE path as only its tail (`Var(T)`); when such a span reaches a type-shaped
## consumer, recover the head from the adjacent source `::` exactly as the global-reference resolver
## does. This keeps `codec::Error` nominal without rejecting the legal generic-call form.
type_path_head := fn(src : ptr(u8), s : usize, n : usize) -> LSpan {
  mut i := 0
  mut cp := -1
  while i + 1 < n {
    if str_at(((src + s) + i), 2) == "::" { cp = i64(i); i = i + 2 } else { i = i + 1 }
  }
  if cp >= 0 { return LSpan(s = s, n = usize(cp)) }
  if s < 2 or str_at((src + s - 2), 2) != "::" { return LSpan(s = 0, n = 0) }
  he := s - 2
  mut p := he
  mut scanning := true
  while scanning {
    mut q := p
    while q > 0 and ll_ident_byte(src, q - 1) { q = q - 1 }
    if q == p { return LSpan(s = 0, n = 0) }
    p = q
    if p >= 2 and str_at((src + p - 2), 2) == "::" { p = p - 2 }
    else { scanning = false }
  }
  LSpan(s = p, n = he - p)
}

## Compare a source module path (`a::b`) with the parser's declaration module (`a__b`). Both
## separators are two bytes; ordinary identifier bytes must match exactly. This is the lower-layout
## twin of lower::mod_seg_eq, local here to keep the dependency edge lower -> lower_layout acyclic.
type_module_eq := fn(src : ptr(u8), ds : usize, dn : usize, qs : usize, qn : usize) -> bool {
  if dn != qn { return false }
  mut i := 0
  while i < dn {
    dc := str_at((src + ds + i), 1)
    qc := str_at((src + qs + i), 1)
    if dc != qc {
      dsep := dc == "_" or dc == ":"
      qsep := qc == "_" or qc == ":"
      if not (dsep and qsep) { return false }
    }
    i += 1
  }
  true
}

## ---------------------------------------------------------------------------------------------
## Modules §3 for a BARE TYPE NAME (TYPE-ANCESTOR) — the type-shaped twin of `lower`'s
## `callee_mod_rank`. `struct_decl_of`/`enum_decl_of` used to take NO naming module at all and
## settle same-named candidates by declaration order (the LAST one won — the opposite tie-break of
## the callee fallback, which was FIRST-wins). Measured before this: with `Box := struct { a, b }` in
## a later-sorting SIBLING and `Box := struct { a }` in the ANCESTOR, a child's `Box.size() + 34`
## returned 50 instead of 42 — it sized the sibling's struct, which §3 makes unnameable from there.
##
## The naming module is PUBLISHED here rather than threaded through ~140 call sites, exactly as
## `lower::set_global_ref_module` publishes it for a module GLOBAL: every consumer of a type name
## (the x86 lower, the three other backends, the check pass) already establishes a per-function
## module identity, so one publisher per emit loop covers every type query underneath it. Not set
## (an early pass with no active module) ⇒ rank -1 everywhere ⇒ the historical answer, unchanged.
mut TRM_S : usize = 0
mut TRM_L : usize = 0
mut TRM_SET : bool = false
## The ANONYMOUS PACKAGE ROOT's module span, published with the naming module so the rank below can
## give the root rank 0 (below every named ancestor) — the `lower::is_root_mod` fact, which lives in
## `lower` and cannot be imported back into this base module.
mut TRM_RS : usize = 0
mut TRM_RL : usize = 0
pub set_type_ref_module := fn(s : usize, l : usize, rs : usize, rl : usize) {
  TRM_S = s ; TRM_L = l ; TRM_SET = true ; TRM_RS = rs ; TRM_RL = rl
}
pub clear_type_ref_module := fn() { TRM_SET = false }
## Read the published pair. `lower`'s `@convert` scope rank needs it because that resolution runs BOTH
## from `emit_fn` and from the DCE mark walk, and only this pair is published in both.
pub type_ref_mod_on := fn() -> bool { TRM_SET }
pub type_ref_mod_s := fn() -> usize { TRM_S }
pub type_ref_mod_l := fn() -> usize { TRM_L }

## Does the candidate module `[as_, al)` match the naming module `[ms, ml)` outright — a full
## segment-aware match, OR the naming module equalling the candidate's LAST SEGMENT (a BARE lib
## reference: module `strbuf` reaching `alloc__strbuf`'s own declarations)? This is the type twin of
## `lower::mod_head_matches`, INCLUDING that last-segment leniency, which is PRESERVED DELIBERATELY:
## the tree leans on it for every `m := path` binding, and narrowing it is its own decision.
type_mod_head_matches := fn(src : ptr(u8), as_ : usize, al : usize, ms : usize, ml : usize) -> bool {
  if type_module_eq(src, as_, al, ms, ml) { return true }
  mut ls := 0
  mut k := 0
  while k + 1 < al {
    ca := str_at((src + as_ + k), 1)
    cb := str_at((src + as_ + k + 1), 1)
    if (ca == "_" and cb == "_") or (ca == ":" and cb == ":") { ls = k + 2 }
    k = k + 1
  }
  if ls == 0 { return false }
  streq(src, as_ + ls, al - ls, ms, ml)
}

## The §3 ANCESTOR rank of a candidate module `[ms, ml)` seen from the naming module `[cs, cl)`: an
## ancestor is a SEGMENT-ALIGNED PREFIX of the naming path, and the rank is the ancestor's own path
## LENGTH — which grows with depth, so the chain is ordered farthest-to-nearest and no two ancestors
## can tie. The anonymous package root ranks 0, below every named module. -1 = not on the chain (a
## sibling, a descendant, an unrelated module), which §3 makes unnameable without a path.
type_anc_rank_from := fn(src : ptr(u8), ms : usize, ml : usize, cs : usize, cl : usize) -> i64 {
  if ml == cl and type_module_eq(src, ms, ml, cs, cl) { return i64(ml) }
  if TRM_RL != 0 and ml == TRM_RL and ms == TRM_RS { return 0 }
  if ml == 0 { return -1 }
  if ml + 2 >= cl { return -1 }
  sep := str_at((src + cs + ml), 2)
  if sep != "__" and sep != "::" { return -1 }
  if type_module_eq(src, ms, ml, cs, ml) == false { return -1 }
  i64(ml)
}

## The rank of a candidate TYPE declaration's module as seen from the published naming module — the
## own-module/lib-path head match ABOVE the whole ancestor chain (ranks are path LENGTHS, so
## `TRM_L + 1` outranks every ancestor), then the §3 chain nearest-first. -1 = §3 makes it
## unnameable from here. One helper so struct, enum, union, alias, brand and `@require` order their
## candidates by exactly the same rule.
pub type_mod_rank := fn(src : ptr(u8), as_ : usize, al : usize) -> i64 {
  if TRM_SET == false { return -1 }
  type_mod_rank_from(src, as_, al, TRM_S, TRM_L)
}

## The same rank against an EXPLICIT naming module — for the one consumer that knows its module
## outright rather than reading the published one: the PARSER's struct field-order table, which
## resolves a struct literal's `f = v` names while `pc.mod_s`/`pc.mod_l` name the module being parsed.
## Published so the ranking rule lives in exactly ONE place across the whole compiler.
pub type_mod_rank_from := fn(src : ptr(u8), as_ : usize, al : usize, ms : usize, ml : usize) -> i64 {
  if type_mod_head_matches(src, as_, al, ms, ml) { return i64(ml) + 1 }
  type_anc_rank_from(src, as_, al, ms, ml)
}

## Write the SOURCE LINE containing byte offset `off` to stderr, then a span / a literal — the
## located-diagnostic trio `lower` has (`lower_show_src_line` / `vis_show_span` / `vis_show_str`),
## duplicated here because this base module cannot import `lower` back (the cycle `lower_ctx.al`
## exists to avoid). A type-name ambiguity is rejected AT THE RESOLVER, so it cannot be bypassed by
## a consumer that forgot to ask.
ll_show_src_line := fn(src : ptr(u8), off : usize) {
  mut lo : usize = 0
  if off > 4096 { lo = off - 4096 }
  mut s := off
  while s > lo and str_at((src + (s - 1)), 1) != "\n" { s = s - 1 }
  hi := off + 4096
  mut e := off
  while e < hi and str_at((src + e), 1) != "\n" { e = e + 1 }
  mut n := e - s
  if e < hi { n = n + 1 }
  w := rt::sys_write(1, 2, unchecked bitcast(usize, rt::addr(src, s)), n)
}
ll_show_span := fn(src : ptr(u8), s : usize, n : usize) {
  w := rt::sys_write(1, 2, unchecked bitcast(usize, rt::addr(src, s)), n)
}
ll_show_str := fn(m : str) {
  w := rt::sys_write(1, 2, unchecked bitcast(usize, m.ptr), m.len)
}

## The LOCATED reject for a bare type name that names a declaration in MORE THAN ONE module and none
## of them on this module's §3 chain. Picking one by declaration order is what produced the measured
## wrong LAYOUT (a sibling's struct sized instead of the ancestor's), so the ambiguity is rejected
## rather than guessed — Types §4.1: a named declaration is NOMINAL, its identity is the declaration.
reject_type_ambiguous := fn(src : ptr(u8), s : usize, n : usize, what : str) {
  ll_show_src_line(src, s)
  ll_show_str("selfhost: the bare type name `")
  ll_show_span(src, s, n)
  ll_show_str("` on the source line above names a ")
  ll_show_str(what)
  ll_show_str(" declared in MORE THAN ONE module, and Modules §3 lets module `")
  ll_show_span(src, TRM_S, TRM_L)
  ll_show_str("` name none of them.\n")
  panic("selfhost: Modules §3 — a bare type name resolves in the naming module and then UP its ancestor chain, nearest first; a sibling's, a descendant's or an unrelated module's declaration is reachable only through a path, and only when it is `pub`. Types §4.1 makes a named declaration NOMINAL, so picking the first or the last declaration in declaration order would give this reference a DIFFERENT type's layout (a silent wrong size, offset or variant tag): qualify the type with the module path it means.")
}

## Resolve ONE existing module-alias binding (`ser := std::serialize`) used as the head of a

## qualified type path. Different declarations of the same short alias may coexist only when they
## name the same module; conflicting targets are ambiguous and stay unresolved. The returned RHS is
## consumed as a literal module path, never followed again, so alias-of-alias remains unsupported.
qualified_module_alias := fn(decls : ptr(rt::Vec), src : ptr(u8), hs : usize, hn : usize) -> LSpan {
  if type_path_head(src, hs, hn).n != 0 { return LSpan(s = 0, n = 0) }
  cnt := rt::vec_len(deref(decls))
  mut rs := 0
  mut rn := 0
  mut ambiguous := false
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 0 and d.arity == 0 and d.ret_tl != 0
       and streq(src, d.name_start, d.name_len, hs, hn) {
      if rn == 0 { rs = d.ret_ts; rn = d.ret_tl }
      else if not streq(src, rs, rn, d.ret_ts, d.ret_tl) { ambiguous = true }
    }
    i += 1
  }
  if ambiguous { return LSpan(s = 0, n = 0) }
  LSpan(s = rs, n = rn)
}

## PERF: a direct-mapped name-text → decl-index CACHE for the struct/enum decl lookups (the profile's
## hottest scans — O(n_decls) per call, called O(n_fields·n_accesses) times during emit). 512 buckets,
## keyed by the NAME TEXT (a cheap length+first+last-byte hash; a full streq confirms on hit, so a
## collision just rescans). `src` and the naming module remain in each entry; a declaration-vector
## backing address/count switch invalidates both tables before lookup, so a fresh compile or a pruned
## vector cannot read a stale index. Byte-neutral
## (returns the same index the linear scan would). Uses mut-global ARRAYS (`[0; 512]` repeat-init —
## verified to work; no-init/containers do not). Bucket empty ⇔ stored name-len 0 (a real name has n>0).
_NCB := 512
_name_hash := fn(src : ptr(u8), s : usize, n : usize) -> usize {
  if n == 0 { return 0 }
  bs := bytes(str_at((src + s), n))
  h := unchecked { n * 131 + usize(bs[0]) * 7 + usize(bs[n - 1]) }
  h & 511
}
## RE-KEYED BY THE NAMING MODULE (TYPE-ANCESTOR). The answer now depends on WHO is asking, so a
## bucket keyed by the name text alone would hand one module's answer to another — the exact shape
## `lower::module_const_value` already guards against with its `_mcv_ms`/`_mcv_ml`/`_mcv_ctx` triple,
## copied here. The memoization itself is PRESERVED: these are the profile's hottest scans (O(n_decls)
## per call, O(n_fields x n_accesses) calls per emit), and a linear rescan per query would be a real
## regression on the ~3.5 s `check`. Within one function the naming module is constant, so the hit
## rate is unchanged; only a module SWITCH invalidates the entries of names declared elsewhere.
mut _sdc_s : [usize; 512] = [0; 512]
mut _sdc_n : [usize; 512] = [0; 512]
mut _sdc_src : [usize; 512] = [0; 512]
mut _sdc_i : [i64; 512] = [0; 512]
mut _sdc_ms : [usize; 512] = [0; 512]
mut _sdc_ml : [usize; 512] = [0; 512]
mut _sdc_ctx : [bool; 512] = [false; 512]
mut _edc_s : [usize; 512] = [0; 512]
mut _edc_n : [usize; 512] = [0; 512]
mut _edc_src : [usize; 512] = [0; 512]
mut _edc_i : [i64; 512] = [0; 512]
mut _edc_ms : [usize; 512] = [0; 512]
mut _edc_ml : [usize; 512] = [0; 512]
mut _edc_ctx : [bool; 512] = [false; 512]

## The two direct-mapped memo tables above answer different kinds, but both answers are indices into
## ONE declaration vector. A vector replacement therefore invalidates BOTH tables as one generation;
## clearing only the stored name lengths is enough to make every old bucket miss. The 512-word clear is
## paid once per vector switch, while repeated lookups on the same vector keep their O(1) hit path. This
## is deliberately one shared invalidation decision, not a second pair of per-entry vector-key tables.
mut _layout_cache_d : usize = 0
mut _layout_cache_dc : usize = 0
layout_cache_use := fn(decls : ptr(rt::Vec), cnt : usize) {
  dkey := unchecked bitcast(usize, deref(decls).data)
  if _layout_cache_d == dkey and _layout_cache_dc == cnt { return }
  mut i := 0
  while i < 512 {
    _sdc_n[i] = 0
    _edc_n[i] = 0
    i += 1
  }
  _layout_cache_d = dkey
  _layout_cache_dc = cnt
}

## PERF (name→decl INDEX, perf 2026-08-15): the 512-bucket caches above answer a REPEATED lookup O(1),
## but every distinct name still pays one full O(decls) scan — and `brand_underlying` / `alias_rhs` /
## `require_pred` have no cache at all (`brand_underlying` alone was 4.1% of self-build flat time, plus
## its share of `decl_get`/`vec_get`). `LNI` is this module's own copy of the lower's `DNI`: a bucketed
## (CSR) map from a decl-NAME hash to the decl indices carrying it, built once alongside the lower's.
## `LNI_B` holds `LNI_NB + 1` bucket boundaries, `LNI_L` the `LNI_N` decl indices grouped by bucket and
## kept in INCREASING order within a bucket, so a candidate walk visits the same decls in the same ORDER
## as the full scan (last-match resolution unchanged). `streq` stays the ARBITER — the index only NARROWS
## the candidate set, so a bucket collision costs a wasted candidate and nothing else. When the index is
## not live (`LNI_N != cnt` or its declaration-vector backing address differs) the cursors degrade to
## `[0, cnt)` and `lni_at` is the identity: the original full scan. The module keeps its OWN hash +
## arrays (rather than importing the lower's) because the import edge runs lower → lower_layout, and a
## stale/foreign hash would be a correctness hazard.
mut LNH : usize = 0
mut LNI_B : usize = 0
mut LNI_L : usize = 0
mut LNI_NB : usize = 0
mut LNI_N : usize = 0
mut LNI_D : usize = 0
## FNV-1a of the name text — the STRONG hash the index buckets on (the 512-bucket caches above keep
## their own cheap length+first+last-byte hash, which is far too weak to bucket a whole decl table).
_fnv_name := fn(src : ptr(u8), s : usize, n : usize) -> usize {
  w := str_at((src + s), n)
  mut h := 1469598103934665603
  mut i := 0
  while i < n {
    unchecked { h = (h ^ usize(bytes(w)[i])) * 1099511628211 }
    i = i + 1
  }
  h
}
lni_live := fn(decls : ptr(rt::Vec), cnt : usize) -> bool {
LNI_B != 0 and LNI_N == cnt and LNI_D == unchecked bitcast(usize, deref(decls).data)
}
pub lni_lo := fn(decls : ptr(rt::Vec), cnt : usize, th : usize) -> usize {
if lni_live(decls, cnt) == false { return 0 }
rt::rec_get(unchecked bitcast(ptr(mut u8), LNI_B), th & (LNI_NB - 1))
}
pub lni_hi := fn(decls : ptr(rt::Vec), cnt : usize, th : usize) -> usize {
if lni_live(decls, cnt) == false { return cnt }
rt::rec_get(unchecked bitcast(ptr(mut u8), LNI_B), (th & (LNI_NB - 1)) + 1)
}
pub lni_at := fn(decls : ptr(rt::Vec), cnt : usize, j : usize) -> usize {
if lni_live(decls, cnt) == false { return j }
rt::rec_get(unchecked bitcast(ptr(mut u8), LNI_L), j)
}
## true → decl `i` CANNOT carry the target name hash `th` (a bucket collision, or a stale/absent index),
## so the caller may skip it without `decl_get`/`streq`. Conservative: false whenever the index is not
## live, so a real candidate is never hidden.
lni_skip := fn(decls : ptr(rt::Vec), cnt : usize, i : usize, th : usize) -> bool {
if lni_live(decls, cnt) == false { return false }
rt::rec_get(unchecked bitcast(ptr(mut u8), LNH), i) != th
}
## Build `LNH` + the `LNI` buckets over `decls`. Called from `lower::decl_index::build_decl_name_hash` (once per
## `emit_program`, after lambda lifting finalizes `decls`) so both indexes cover the same decl vector.
pub build_layout_name_index := fn(decls : ptr(rt::Vec), src : ptr(u8), in out mar : rt::Arena) {
  cnt := rt::vec_len(deref(decls))
  base := rt::bump(mar, cnt * 8 + 8)
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    rt::rec_set(unchecked bitcast(ptr(mut u8), base), i, _fnv_name(src, d.name_start, d.name_len))
    i = i + 1
  }
  mut nb := 64
  while nb < cnt * 2 { nb = nb * 2 }
  bb := rt::bump(mar, nb * 8 + 16)
  cur := rt::bump(mar, nb * 8 + 16)
  lb := rt::bump(mar, cnt * 8 + 8)
  mut b := 0
  while b < nb + 1 {
    rt::rec_set(unchecked bitcast(ptr(mut u8), bb), b, 0)
    rt::rec_set(unchecked bitcast(ptr(mut u8), cur), b, 0)
    b = b + 1
  }
  i = 0
  while i < cnt {
    h := rt::rec_get(unchecked bitcast(ptr(mut u8), base), i) & (nb - 1)
    rt::rec_set(unchecked bitcast(ptr(mut u8), bb), h + 1, rt::rec_get(unchecked bitcast(ptr(mut u8), bb), h + 1) + 1)
    i = i + 1
  }
  b = 1
  while b < nb + 1 {
    rt::rec_set(unchecked bitcast(ptr(mut u8), bb), b, rt::rec_get(unchecked bitcast(ptr(mut u8), bb), b) + rt::rec_get(unchecked bitcast(ptr(mut u8), bb), b - 1))
    b = b + 1
  }
  i = 0
  while i < cnt {
    h := rt::rec_get(unchecked bitcast(ptr(mut u8), base), i) & (nb - 1)
    p := rt::rec_get(unchecked bitcast(ptr(mut u8), bb), h) + rt::rec_get(unchecked bitcast(ptr(mut u8), cur), h)
    rt::rec_set(unchecked bitcast(ptr(mut u8), lb), p, i)
    rt::rec_set(unchecked bitcast(ptr(mut u8), cur), h, rt::rec_get(unchecked bitcast(ptr(mut u8), cur), h) + 1)
    i = i + 1
  }
  LNH = base
LNI_B = bb
LNI_L = lb
LNI_NB = nb
LNI_N = cnt
LNI_D = unchecked bitcast(usize, deref(decls).data)
}

## ---- the shared RANKED selector ----------------------------------------------------------------
## The declaration of kind `k` (2 = struct, 3 = enum OR raw union) whose TYPE tail-name matches, as
## seen from the PUBLISHED naming module. Preference order, applied once for every type-shaped query
## so struct, enum, union, alias, brand and `@require` cannot disagree with one another:
##
##   (1) a QUALIFIED spelling names its module outright (Modules §2) — nominal identity beats every
##       rank, and it is what keeps `rt::Arena` off `base::alloc`'s same-named struct;
##   (2) the §3 chain — this module, then its ancestors NEAREST-first (`type_mod_rank`), which
##       includes the own-module / last-segment lib-path head match above the chain;
##   (3) no naming module published (an early pass) OR the name has exactly ONE declaration in the
##       whole program: the historical answer stands. Both are PRESERVED DELIBERATELY — the second is
##       the unique-declaration leniency the tree leans on for every ambient prelude type;
##   (4) a qualified head that is a one-level module ALIAS (`strbuf := rt` -> `strbuf::StrBuf`);
##   (5) the naming module SAID which module it means (Modules §4.1.1: `(A, B) := M`, `T := M::T`);
##   (6) otherwise the reference is genuinely unanswerable -> LOCATED REJECT, never "pick one".
type_decl_ranked := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, k : usize, what : str) -> i64 {
  cnt := rt::vec_len(deref(decls))
  nm := name_tail(src, s, n)
  qh := type_path_head(src, s, n)
  mut res := 0 - 1
  mut hits := 0
  mut best := 0 - 1
  mut besti := 0 - 1
  mut qi := 0 - 1
  mut anypub := false
  th := _fnv_name(src, nm.s, nm.n)
  mut jc := lni_lo(decls, cnt, th)
  jce := lni_hi(decls, cnt, th)
  mut i := 0
  while jc < jce {
    i = lni_at(decls, cnt, jc)
    jc = jc + 1
    if lni_skip(decls, cnt, i, th) == false {
      d := deref(decl_get(decls, i))
      if d.kind == k and streq(src, d.name_start, d.name_len, nm.s, nm.n) {
        res = i64(i)
        hits = hits + 1
        r := type_mod_rank(src, d.mod_start, d.mod_len)
        if r > best { best = r ; besti = i64(i) }
        if qh.n != 0 and type_module_eq(src, d.mod_start, d.mod_len, qh.s, qh.n) { qi = i64(i) }
        if lower_attrs::decl_is_pub(src, d.name_start) { anypub = true }
      }
    }
  }
  if qi >= 0 { return qi }
  if besti >= 0 { return besti }
  if TRM_SET == false { return res }
  if hits <= 1 { return res }
  if qh.n != 0 {
    ah := qualified_module_alias(decls, src, qh.s, qh.n)
    if ah.n != 0 {
      ai := type_decl_in_module(decls, src, nm.s, nm.n, k, ah.s, ah.n)
      if ai >= 0 { return ai }
    }
  }
  bi := binding_type_idx(decls, src, nm.s, nm.n, k)
  if bi >= 0 { return bi }
  ## (6) At least one candidate is `pub`. §3 makes a `pub` declaration reachable from anywhere
  ## THROUGH A PATH, so a reference that reaches here MAY be a legitimate qualified one whose head
  ## was lost before the query: the parser keeps only the last segment of a qualified VALUE path, and
  ## `qualified_enum_decl_of`s own header records that carrying the head through every qualified
  ## annotation is a broader namespace migration than this lane. Rejecting here would refuse
  ## `Result(usize, codec::Error)` in a program that ALSO declares a `pub Error` elsewhere — a legal
  ## program (e2e `qualified_generic_package`, measured 42 before and 1 after a hard reject). So the
  ## historical tail-only answer stands and `scripts/type_module_check.sh` REPORTS the pair instead.
  if anypub { return res }
  ## (7) Every candidate is NON-`pub`: §3 makes each one unnameable from here in ANY spelling, so no
  ## path could have meant it and no head can have been lost. The reference is unanswerable.
  reject_type_ambiguous(src, s, n, what)
  0 - 1
}

## The kind-`k` declaration of tail name `[ns, nl)` in a NAMED module `[hs, hl)`, or -1. Used by the
## qualified-alias and binding fallbacks above; module comparison is segment-aware plus the same
## last-segment lib-path leniency, so a bound short head still reaches the mangled module.
type_decl_in_module := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, k : usize, hs : usize, hl : usize) -> i64 {
  if nl == 0 { return 0 - 1 }
  if hl == 0 { return 0 - 1 }
  cnt := rt::vec_len(deref(decls))
  th := _fnv_name(src, ns, nl)
  mut res := 0 - 1
  mut jc := lni_lo(decls, cnt, th)
  jce := lni_hi(decls, cnt, th)
  mut i := 0
  while jc < jce {
    i = lni_at(decls, cnt, jc)
    jc = jc + 1
    if lni_skip(decls, cnt, i, th) == false {
      d := deref(decl_get(decls, i))
      if d.kind == k and streq(src, d.name_start, d.name_len, ns, nl)
         and type_mod_head_matches(src, d.mod_start, d.mod_len, hs, hl) { res = i64(i) }
    }
  }
  res
}

## Is byte `i` an identifier byte? (the projection-list scan below needs it)
ll_ident_byte := fn(src : ptr(u8), i : usize) -> bool {
  b := bytes(str_at((src + i), 1))[0]
  (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
}

## The module-path HEAD a listed member projection `(A, B, ...) := M` (the verbatim span `[rs, rl)`)
## gives the name `[ns, nl)`, or 0/0 when the list does not contain it. The type twin of
## `lower::projection_head_for`, local here to keep the lower -> lower_layout edge acyclic.
ll_projection_head_for := fn(src : ptr(u8), rs : usize, rl : usize, ns : usize, nl : usize) -> LSpan {
  z := LSpan(s = 0, n = 0)
  if rl < 4 { return z }
  if str_at((src + rs), 1) != "(" { return z }
  mut e := rs + 1
  ende := rs + rl
  while e < ende and str_at((src + e), 1) != ")" { e = e + 1 }
  if e >= ende { return z }
  mut p := e + 1
  while p < ende and str_at((src + p), 1) != "=" { p = p + 1 }
  if p >= ende { return z }
  p = p + 1
  while p < ende and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n"
                      or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") { p = p + 1 }
  if p >= ende { return z }
  hs := p
  hl := ende - p
  if hl == 0 { return z }
  mut q := rs + 1
  mut hit := false
  while q < e {
    while q < e and (str_at((src + q), 1) == " " or str_at((src + q), 1) == ","
                     or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t"
                     or str_at((src + q), 1) == "\r") { q = q + 1 }
    mut r := q
    while r < e and ll_ident_byte(src, r) { r = r + 1 }
    if r == q { q = q + 1 }
    else {
      if streq(src, q, r - q, ns, nl) { hit = true }
      q = r
    }
  }
  if hit == false { return z }
  LSpan(s = hs, n = hl)
}

## Modules §4.1/§4.1.1 — the declaration a BINDING in the PUBLISHED naming module gives the bare type
## name `[ns, nl)`, or -1. Two spellings bind a NAME: a listed member projection `(A, B, ...) := M`
## (the parser's nameless kind-0 marker whose `ret` span is the verbatim source) and a single alias
## `T := M::T` (a named kind-0 decl whose `ret` span is the qualified RHS path). This is what makes
## `lower_layout`'s `(Decl, Expr, FieldDecl, Param) := ast` mean `ast`'s declarations rather than a
## declaration-order lottery. Consulted ONLY after the §3 ranking found nothing AND the name is
## declared in more than one module, i.e. only on the path that used to guess.
binding_type_idx := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, k : usize) -> i64 {
  if nl == 0 { return 0 - 1 }
  if TRM_SET == false { return 0 - 1 }
  if TRM_L == 0 { return 0 - 1 }
  cnt := rt::vec_len(deref(decls))
  mut hs := 0
  mut hl := 0
  mut ts := ns
  mut tl := nl
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.ret_tl != 0
       and type_module_eq(src, d.mod_start, d.mod_len, TRM_S, TRM_L) {
      if d.name_len == 0 {
        pr := ll_projection_head_for(src, d.ret_ts, d.ret_tl, ns, nl)
        if pr.n != 0 { hs = pr.s; hl = pr.n; ts = ns; tl = nl }
      } else {
        if streq(src, d.name_start, d.name_len, ns, nl) {
          qhh := type_path_head(src, d.ret_ts, d.ret_tl)
          if qhh.n != 0 {
            rt2 := name_tail(src, d.ret_ts, d.ret_tl)
            hs = qhh.s; hl = qhh.n; ts = rt2.s; tl = rt2.n
          }
        }
      }
    }
    i += 1
  }
  if hl == 0 { return 0 - 1 }
  type_decl_in_module(decls, src, ts, tl, k, hs, hl)
}

## A bare ENUM reference is unsafe when more than one same-named nominal enum exists and none is
## reachable from the naming module's §3 chain. `type_decl_ranked` historically keeps the last
## public candidate for a qualified generic annotation whose head was lost by the parser; that
## compatibility fallback is not safe for a VARIANT lookup, because an absent variant becomes -1
## and is emitted as a real discriminant. Keep the broad resolver unchanged, but make this seam
## fail-loud before `variant_index` can turn the ambiguity into a value. A module-qualified span,
## an in-scope candidate, or a §4.1 binding is already enough identity and stays accepted.
enum_ref_ambiguous := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  if type_path_head(src, s, n).n != 0 { return false }
  if TRM_SET == false { return false }
  nm := name_tail(src, s, n)
  cnt := rt::vec_len(deref(decls))
  th := _fnv_name(src, nm.s, nm.n)
  mut hits := 0
  mut best := 0 - 1
  mut j := lni_lo(decls, cnt, th)
  je := lni_hi(decls, cnt, th)
  while j < je {
    i := lni_at(decls, cnt, j)
    j = j + 1
    if lni_skip(decls, cnt, i, th) == false {
      d := deref(decl_get(decls, i))
      if d.kind == 3 and streq(src, d.name_start, d.name_len, nm.s, nm.n) {
        hits = hits + 1
        r := type_mod_rank(src, d.mod_start, d.mod_len)
        if r > best { best = r }
      }
    }
  }
  if hits <= 1 or best >= 0 { return false }
  binding_type_idx(decls, src, nm.s, nm.n, 3) < 0
}

## Find the kind-2 (struct) `Decl` whose TYPE name matches `[s, s+n)` (by tail name, so a
## qualified `mod::P` resolves to struct `P`); returns its index in the decl vector, or -1 if
## none. Used to resolve a struct local's layout (field list). Candidates are ordered by
## `type_decl_ranked` (Modules §3), so a SIBLING's same-named struct can no longer win by sorting
## last in declaration order.
pub struct_decl_of := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> i64 {
  h := _name_hash(src, s, n)
  cnt := rt::vec_len(deref(decls))
  layout_cache_use(decls, cnt)
  if _sdc_n[h] == n and _sdc_src[h] == src and _sdc_ctx[h] == TRM_SET
     and _sdc_ml[h] == TRM_L and streq(src, _sdc_ms[h], _sdc_ml[h], TRM_S, TRM_L)
     and streq(src, _sdc_s[h], _sdc_n[h], s, n) { return _sdc_i[h] }
  nm := name_tail(src, s, n)
  mut res := type_decl_ranked(decls, src, s, n, 2, "struct")
  mut alias_ts := 0
  mut alias_tl := 0
  mut a_best := 0 - 1
  th := _fnv_name(src, nm.s, nm.n)
  mut jc := lni_lo(decls, cnt, th)
  jce := lni_hi(decls, cnt, th)
  mut i := 0
  while jc < jce {
    i = lni_at(decls, cnt, jc)
    jc = jc + 1
    if lni_skip(decls, cnt, i, th) == false {
    d := deref(decl_get(decls, i))
    ## a TYPE ALIAS (kind 0 with a recorded RHS path, `String := strbuf::StrBuf`) — remember its
    ## target so an unmatched name can be followed to the aliased struct (one level, below). The
    ## alias declarations are ranked by the SAME §3 rule as the struct itself: an ancestor's alias
    ## shadows an unrelated module's same-named one instead of losing to declaration order.
    if d.kind == 0 and d.ret_tl != 0 and streq(src, d.name_start, d.name_len, nm.s, nm.n) {
      ar := type_mod_rank(src, d.mod_start, d.mod_len)
      if ar >= a_best { a_best = ar; alias_ts = d.ret_ts; alias_tl = d.ret_tl }
    }
    ## a GENERIC-INSTANCE type alias (TYP-10 slice C, `u128 := uint(128)`, Types §7) — the same
    ## one-level follow, keyed on the parser-recorded alias span: its BASE HEAD names the aliased
    ## generic struct (`uint`). (`alias_rhs` below recovers the FULL span, value args included.)
    if d.kind == 0 and d.alias_tl != 0 and streq(src, d.name_start, d.name_len, nm.s, nm.n) {
      ar2 := type_mod_rank(src, d.mod_start, d.mod_len)
      if ar2 >= a_best {
        abh := base_type_name(src, d.alias_ts, d.alias_tl)
        a_best = ar2; alias_ts = abh.s; alias_tl = abh.n
      }
    }
    }
  }
  ## no direct struct of this name, but the name is a type alias -> resolve its RHS (tail name).
  if res < 0 and alias_tl != 0 { res = type_decl_ranked(decls, src, alias_ts, alias_tl, 2, "struct") }
  _sdc_s[h] = s; _sdc_n[h] = n; _sdc_src[h] = src; _sdc_i[h] = res
  _sdc_ms[h] = TRM_S; _sdc_ml[h] = TRM_L; _sdc_ctx[h] = TRM_SET
  res
}

## The GENERIC-INSTANCE span a TYPE-ALIAS name `[s, s+n)` stands for (TYP-10 slice C, Types §7:
## `u128 ≡ uint(128)`), or `[s, s+n)` UNCHANGED when the name is not such an alias. The parser
## records the RHS span of a `Name := ident(…)` value decl in `alias_ts`/`alias_tl`; this resolver
## fires ONLY when the RHS's base head resolves to a GENERIC struct type-function — so the span a
## plain `x := f(1)` global also records is inert (its head is no struct). Unlike `struct_decl_of`'s
## one-level follow (which yields the aliased DECL), this returns the alias's FULL source span —
## `uint(128)` — so a comptime VALUE argument is recoverable from it by `typearg_at` (a bare
## use-site `u128` carries no `(128)`). Consulted at every point a comptime-value-generic instance
## span is consumed: `ct_arr_len` (layout) and the lower's generic-operator route (operand head +
## comptime binding). One level only — an alias-of-alias is out of scope.
pub alias_rhs := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> LSpan {
  cnt := rt::vec_len(deref(decls))
  nm := name_tail(src, s, n)
  mut rs := s
  mut rn := n
  ## Modules §3: the alias declarations of one name are ranked, so an unrelated module's same-named
  ## generic alias cannot supply the RHS by sorting last. `>=` keeps the last of EQUAL-rank
  ## candidates, which is the historical last-wins answer whenever no naming module is published.
  mut a_best := 0 - 1
  th := _fnv_name(src, nm.s, nm.n)
  mut jc := lni_lo(decls, cnt, th)
  jce := lni_hi(decls, cnt, th)
  mut i := 0
  while jc < jce {
    i = lni_at(decls, cnt, jc)
    jc = jc + 1
    d := deref(decl_get(decls, i))
    if d.kind == 0 and d.alias_tl != 0 and streq(src, d.name_start, d.name_len, nm.s, nm.n)
       and type_mod_rank(src, d.mod_start, d.mod_len) >= a_best {
      a_best = type_mod_rank(src, d.mod_start, d.mod_len)
      bh := base_type_name(src, d.alias_ts, d.alias_tl)
      sdi := struct_decl_of(decls, src, bh.s, bh.n)
      edi := enum_decl_of(decls, src, bh.s, bh.n)
      mut generic_target := false
      if sdi >= 0 {
        sdd := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(sdi))))
        if sdd.is_generic { generic_target = true }
      }
      if edi >= 0 {
        edd := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(edi))))
        if edd.is_generic { generic_target = true }
      }
      ## A generic enum alias keeps the full RHS just like a generic struct alias. Without this,
      ## `R := Result(u64, E)` loses the comptime arguments at every bare `R` use site.
      if generic_target { rs = d.alias_ts; rn = d.alias_tl }
    }
    i += 1
  }
  LSpan(s = rs, n = rn)
}

## Resolve a NOMINAL BRAND name `[s, s+n)` (`Id := brand(U)`, parsed as a kind-0 decl MARKED by
## `arity == 1`, its underlying type span in ret_ts/ret_tl) to its underlying type span `U`.
## Returns `{0, 0}` if the name is not a brand. So the lower can peel `Id(v)` construction and a
## scalar conversion `u64(id)` to the underlying — the brand is a compile-time nominal wrapper with
## the underlying's exact runtime representation. Resolved by tail name (a qualified
## `mod::Id` still finds the brand decl).
pub brand_underlying := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> LSpan {
  cnt := rt::vec_len(deref(decls))
  nm := name_tail(src, s, n)
  mut best := 0 - 1
  mut found := false
  mut rs := 0
  mut rn := 0
  th := _fnv_name(src, nm.s, nm.n)
  mut jc := lni_lo(decls, cnt, th)
  jce := lni_hi(decls, cnt, th)
  mut i := 0
  while jc < jce {
    i = lni_at(decls, cnt, jc)
    jc = jc + 1
    if lni_skip(decls, cnt, i, th) == false {
      d := deref(decl_get(decls, i))
      ## Modules §3: rank the candidates instead of taking the FIRST in declaration order. A brand
      ## is a nominal wrapper, so an unrelated module's same-named brand must not supply
      ## the underlying type. `>=` keeps the last of equal-rank candidates, i.e. the historical
      ## answer (the FIRST match) whenever no naming module is published (every rank -1).
      if d.kind == 0 and d.arity == 1 and d.ret_tl != 0 and streq(src, d.name_start, d.name_len, nm.s, nm.n) {
        r := type_mod_rank(src, d.mod_start, d.mod_len)
        if r > best or found == false { best = r; found = true; rs = d.ret_ts; rn = d.ret_tl }
      }
    }
  }
  if found { return LSpan(s = rs, n = rn) }
  LSpan(s = 0, n = 0)
}

## Count the fields of a struct (length of its arena-linked `FieldDecl` list).
pub struct_nfields := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut cnt := 0
  while f != 0 {
    fd := deref(fld_p(f))
    cnt += 1
    f = fd.next
  }
  cnt
}

## Resolve a field NAME span to its declaration-order index within struct `[s, s+n)`
## (0-based; -1 if not found). The byte offset of the field is `index * 8` (the word-sized
## layout simplification), so `p.f` lives at slot `base_off + index`.
pub field_index := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return -1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut idx := 0
  mut res := -1
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, fs, fl) { res = idx }
    idx += 1
    f = fd.next
  }
  res
}

## STRUCT-WITH-ARRAY-FIELD tier — the total SIZE IN WORDS of struct `[s, s+n)` (the sum of
## every field's `wsize`: 1 for a scalar field, N for a `[T; N]` array field). This is the
## number of contiguous frame words a struct value occupies (replacing the old `nfields`
## sizing, which assumed every field was one word). A scalar-only struct sums to `nfields` —
## byte-identical to the old layout.
## The true word-width of a field with declared type `[ts, ts+tl)` and parser `wsize`. A scalar is 1
## and an array field keeps its `wsize` (= the element count), but a STRUCT-TYPED field occupies its
## struct's FULL word count — the parser defaults its `wsize` to 1 (it cannot size a struct at parse
## time), so resolve it here (recursively, so `o : O { i : I, … }` lays `I` out by `struct_words(I)`).
## A `str` field is a 2-word `{ptr, len}` value (Memory §3.5), so it occupies 2 words — the field
## offsets of later fields shift accordingly and `s.field.len` reads the len at `offset + 1`.
## The ELEMENT-TYPE span of an ARRAY field type `[T; N]` — the text between the opening `[` and the
## `;` (or the closing `]` for the `[]` form), trimmed of surrounding spaces (`[Cell; 3]` → `Cell`).
## `{0,0}` when the span is not an array type (no leading `[`). The layout dual of `lower::array_elem_span`
## (duplicated here so `lower_layout` stays self-contained — a leaf like `streq`/`decl_at`). Drives the
## `[T; N]` field-width fold in `field_words`/`field_word_offset` below.
arr_field_elem_span := fn(src : ptr(u8), ts : usize, tl : usize) -> LSpan {
  if tl < 2 { return LSpan(s = 0, n = 0) }
  if str_at((src + ts), 1) != "[" { return LSpan(s = 0, n = 0) }
  mut es := ts + 1
  while es < ts + tl and str_at((src + es), 1) == " " { es = es + 1 }
  mut ee := es
  while ee < ts + tl and str_at((src + ee), 1) != ";" and str_at((src + ee), 1) != "]" { ee = ee + 1 }
  mut et := ee
  while et > es and str_at((src + et - 1), 1) == " " { et = et - 1 }
  LSpan(s = es, n = et - es)
}

## The explicitly byte-sized scalar element types accepted by the packed-field byte layout.
## Keep this local to the layout module: the ordinary word-model layout still treats byte arrays
## as word arrays until its own slice is proven.
layout_byte_type_eek := fn(src : ptr(u8), ts : usize, tl : usize) -> u8 {
  if tl == 2 and str_at((src + ts), 2) == "u8" { return 8 }
  if tl == 2 and str_at((src + ts), 2) == "i8" { return 10 }
  if tl == 5 and str_at((src + ts), 5) == "bits8" { return 11 }
  0
}

## The scalar widths admitted by the first ordinary §6.1 byte-layout slice.  Keep the admission list
## closed: `scalar_byte_size` intentionally returns 8 for unresolved/brand names, but treating such a
## name as a known byte-layout field would make a later semantic error observable as a layout change.
## A struct enters this slice only when EVERY field is a known direct scalar and at least one is narrow;
## word-only structs retain the word model.
std_direct_scalar_byte_width := fn(src : ptr(u8), ts : usize, tl : usize) -> usize {
  sw := scalar_width::subword_bytes(src, ts, tl)
  if sw != 0 { return sw }
  if tl == 2 and str_at((src + ts), 2) == "u64" { return 8 }
  if tl == 2 and str_at((src + ts), 2) == "i64" { return 8 }
  if tl == 5 and str_at((src + ts), 5) == "usize" { return 8 }
  if tl == 5 and str_at((src + ts), 5) == "isize" { return 8 }
  if tl == 4 and str_at((src + ts), 4) == "f64" { return 8 }
  if tl == 5 and str_at((src + ts), 5) == "bits64" { return 8 }
  if tl >= 3 and str_at((src + ts), 3) == "ptr" {
    c := str_at((src + ts + 3), 1)
    if c == "(" or c == " " or c == "\n" or c == "\t" or c == "\r" { return 8 }
  }
  if tl >= 2 and str_at((src + ts), 2) == "fn" {
    c := str_at((src + ts + 2), 1)
    if c == "(" or c == " " or c == "\n" or c == "\t" or c == "\r" { return 8 }
  }
  0
}

## STANDARD BYTE LAYOUT TIER — the first shared implementation of Types §6.1/§6.4 for an
## ordinary struct that contains either an explicitly byte-typed fixed array or only supported scalar
## fields (with at least one sub-word leaf), closing the scalar branch over nested ordinary structs.
## The historical lowering reserves whole words and is still the default for every type that does not
## reach this predicate; this tier is therefore opt-in by representation, not a second interpretation
## of existing values.
##
## The helpers deliberately live here, beside `field_words`/`field_word_offset`, so local slots,
## aggregate parameters, globals, and ABI sizing can consume one layout vocabulary.  The consumer
## slice handles scalar fields, recursively supported nested structs, plus `[u8|i8|bits8; N]` fields.
## Unsupported aggregate consumers still fail-loud until their byte-copy/ABI paths are wired to the
## same offsets.
pub std_struct_has_direct_byte_layout := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut found_array := false
  mut found_subword := false
  mut scalar_only := true
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    es := arr_field_elem_span(src, eff.s, eff.n)
    if es.n != 0 {
      ## Preserve the established direct-byte-array admission exactly.  A later non-byte field
      ## remains the existing fail-loud boundary in its consumer; this predicate must not turn an
      ## already-supported byte-array shape into a different classification while widening the
      ## scalar-only branch below.
      if layout_byte_type_eek(src, es.s, es.n) != 0 { found_array = true }
      else { scalar_only = false }
    } else {
      ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
      sbn := base_type_name(src, eff.s, eff.n)
      mut nested_byte := false
      if ew == 1 and struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 and not is_packed(decls, src, eff.s, eff.n) and not is_union_decl(decls, src, eff.s, eff.n) {
        ## Close the scalar tier under a nested direct-scalar child.  Without this, S4 makes
        ## `Small` byte-laid out while `Deep { inner : Small }` remains word-laid out, so the
        ## parent writer and the standalone child copy speak different representations.
        nested_byte = std_struct_has_direct_byte_layout(decls, src, eff.s, eff.n, a)
      }
      if nested_byte { found_subword = true }
      else {
        sw := std_direct_scalar_byte_width(src, eff.s, eff.n)
        if ew != 1 or sw == 0 { scalar_only = false }
        else if sw < 8 { found_subword = true }
      }
    }
    f = fd.next
  }
  if found_array { return true }
  scalar_only and found_subword
}

## Exact two-byte scalar shape shared by the C and native ABI classifiers. This is only the field
## shape; callers still decide whether the surrounding layout is the standard byte tier and whether
## a plain (non-generic) declaration is required. Keeping the shape here prevents the three native
## emitters from drifting away from the already-landed C ABI seam.
pub std_struct_is_u8_pair := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut nf := 0
  mut ok := true
  while f != 0 {
    fd := deref(fld_p(f))
    if str_at((src + fd.ts), fd.tl) != "u8" { ok = false }
    nf += 1
    f = fd.next
  }
  ok and nf == 2
}

std_type_has_byte_layout := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, wsize : usize, a : rt::Arena) -> bool {
  es := arr_field_elem_span(src, ts, tl)
  if es.n != 0 and layout_byte_type_eek(src, es.s, es.n) != 0 { return true }
  if wsize == 1 {
    sbn := base_type_name(src, ts, tl)
    if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { return std_struct_has_byte_layout(decls, src, ts, tl, a) }
  }
  false
}

pub std_struct_has_byte_layout := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut found := false
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
    if std_type_has_byte_layout(decls, src, eff.s, eff.n, ew, a) { found = true }
    f = fd.next
  }
  found
}

## ─── THE LAYOUT ORACLE (spec Types §6.1/§8) ───────────────────────────────────────────────────────
## `layout_kind` is the SINGLE decision of which representation an aggregate type uses. The same
## three-way ladder used to be spelled out at every consumer — `typeinfo(T).fields[i].offset` in all
## four emitters (`lower`/`aarch64`/`riscv64`/`wat`), the `size(T)`/`align(T)` comptime folds, the
## slot-reservation query `struct_words`, and the interface layout hash — so a tier decision could
## drift between them silently. They now all ask HERE.
##
## Precedence is the VALUE paths' precedence, and it is normative for every consumer:
##   1 PACKED — `@packed` (§8): a byte cursor plus the `@offset`/`@align`/`@endian` field levers.
##   2 BYTE   — the standard byte-precise §6.1 tier (declaration order, natural alignment, standard
##              padding). Currently GATED on the struct carrying a direct `[u8|i8|bits8; N]` field:
##              including recursively supported direct-scalar children. Unsupported aggregate shapes
##              remain outside the predicate and keep their existing fail-loud fences.
##   3 WORD   — the historical word-granular model (one machine word per field). This is the tier
##              that spec §6.1 says must go away; widening the byte tier is a change to THIS
##              function alone (CLAYOUT S4), which is the point of the oracle.
## A non-struct name (scalar, unknown, enum, union) answers WORD — callers keep their own
## enum/union/scalar arms, exactly as before.
pub layout_kind := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  if is_packed(decls, src, s, n) { return 1 }
  if std_struct_has_direct_byte_layout(decls, src, s, n, a) { return 2 }
  3
}
## Readers for a `layout_kind` code, so no call site spells the tier numbers.
pub layout_kind_is_packed := fn(k : usize) -> bool { k == 1 }
pub layout_kind_is_byte := fn(k : usize) -> bool { k == 2 }

## ─── THE PER-HOP HALF OF THE ORACLE ──────────────────────────────────────────────────────────────
## `layout_kind` decides the tier of ONE type. A field PATH (`o.inner.tail`) walks a CHAIN of types,
## and each link must be read in ITS OWN tier, because each tier is written by a different emitter:
##   BYTE   → the §6.1 byte offsets, which is exactly what `emit_standard_assign` writes;
##   WORD   → §6.1 byte offsets when the type is in the byte-precise whole-value writer's domain
##            (`std_struct_is_byte_writable`, CLAYOUT S3(b)); otherwise the historical
##            `field_word_offset * 8`, which is what `emit_struct_assign`'s word loop writes (it
##            accumulates `field_words`, the same sum `field_word_offset` computes), and which is
##            answerable only for a WORD-GRANULAR type, where the two models coincide;
##   PACKED → no answer: `@packed` has its own byte cursor (`packed_field_byte_offset`) and its own
##            emitter, so a standard-layout consumer must never claim one.
## Reading a link at offsets nobody WROTE it at is the defect this function exists to prevent. Under
## S3(a) that made every non-word-granular WORD-tier child unanswerable: `struct { a : u16, b : u16 }`
## nested in a byte-layout struct was WRITTEN at child words 0/1 (bytes 0 and 8) by x86_64 while its
## §6.1 offsets are 0 and 2, so the two agreed only for a child every one of whose fields is 8 bytes
## wide and 8-aligned. S3(b) removed the cause rather than the check: `std_struct_is_byte_writable`
## names the children the ONE byte-precise whole-value writer builds on all four backends, and those
## are answered at their §6.1 offsets. -1 still means "this slice has no addressable offset here",
## and every caller must keep the fail-loud contract rather than substitute a word offset.
pub layout_field_offset_bytes := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return -1 }
  lk := layout_kind(decls, src, s, n, a)
  if layout_kind_is_packed(lk) { return -1 }
  if layout_kind_is_byte(lk) { return standard_field_byte_offset(decls, src, s, n, fs, fl, a) }
  ## A WORD-tier child has an offset a byte-layout consumer may use exactly when what WROTE it and
  ## what READS it agree, and there are now two independent ways that holds.
  ##   (1) WORD-GRANULAR — the two models coincide, and then `standard_field_byte_offset` IS
  ##       `field_word_offset * 8`, which is why one expression serves both tiers.
  ##   (2) CLAYOUT S3(b) — BYTE-WRITABLE: the ONE byte-precise whole-value writer is now what every
  ##       backend uses for a nested child (x86's `emit_standard_assign` recursion, aarch64/riscv64/
  ##       wat's `*_std_store_struct`), so a child in its domain is WRITTEN at its §6.1 offsets on all
  ##       four and is therefore READ at them.
  ## The two are not competing answers: a child that is BOTH returns the SAME number either way, by
  ## the definition of word-granular. What still has NO answer is a child neither covers — one carrying
  ## a `str`, an enum, a union, a tuple or a non-byte array — because there the byte-precise writer has
  ## no store and the word constructor's image is not the §6.1 image.
  if std_struct_is_word_granular(decls, src, s, n, a) { return standard_field_byte_offset(decls, src, s, n, fs, fl, a) }
  if not std_struct_is_byte_writable(decls, src, s, n, a) { return -1 }
  standard_field_byte_offset(decls, src, s, n, fs, fl, a)
}

## ─── THE ONE BYTE-PRECISE WHOLE-VALUE WRITER'S DOMAIN (CLAYOUT S3(b)) ──────────────────────────
## Can the byte-precise whole-value writer materialize a value of this struct type at an ARBITRARY
## byte offset? That writer is one algorithm with four spellings — `emit_standard_assign`'s recursion
## on x86_64 and `a64_std_store_struct` / `rv_std_store_struct` / `wat_std_store_struct` on the three
## cross backends — and all four take every offset from `standard_field_byte_offset`, so this
## predicate is the SINGLE definition of what they can express. Its answer is what makes the four
## memory images identical, which is what `layout_field_offset_bytes` then relies on to hand every
## reader the same offsets.
##
## The domain is exactly the stores the four writers have: a SCALAR field (a sized `movb|movw|movl|
## movq` / `strb|strh|str` / `i32.store8…` at its §6.1 offset), an explicitly byte-typed fixed ARRAY
## field of statically known length (element-wise byte stores), and a nested STRUCT field that is
## itself in the domain (the recursion). Everything else is OUT, and out means the caller keeps its
## fail-loud fence rather than substituting a word offset (I11):
##   `@packed`      — its own byte cursor and its own emitter (`emit_packed_assign`);
##   a `str` / `[T]` view field, an enum field, a union field — multi-word values with their own
##                    delivery convention, and none of the four writers stores one;
##   a tuple field, a NON-byte array field — no byte-precise element store exists yet (audit S3(c));
##   a field whose array length is not statically known — `standard_type_byte_size` panics on it.
## NOTE the deliberate overlap with `std_struct_is_word_granular`: a child of all-`u64` fields is in
## BOTH, and that is safe precisely because the two models coincide there (the audit §5 staging
## principle). A child carrying a `[u64; 3]` field is word-granular but NOT in this domain, so it
## keeps the word constructor on x86_64 and stays a trap on the three cross backends — unchanged.
pub std_struct_is_byte_writable := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  if is_packed(decls, src, s, n) { return false }
  if is_union_decl(decls, src, s, n) { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut ok := true
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
    aes := arr_field_elem_span(src, eff.s, eff.n)
    if aes.n != 0 {
      ## An ARRAY field is in the domain only as an explicitly byte-typed one of statically known
      ## length: that is the single array shape all four writers store element-by-element.
      if layout_byte_type_eek(src, aes.s, aes.n) == 0 { ok = false }
      if ew == 0 { ok = false }
    } else {
      sbn := base_type_name(src, eff.s, eff.n)
      if ew != 1 { ok = false }                                        ## a multi-word non-array field
      else if is_union_decl(decls, src, sbn.s, sbn.n) { ok = false }
      else if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 {
        if not std_struct_is_byte_writable(decls, src, eff.s, eff.n, a) { ok = false }
      }
      else if enum_decl_of(decls, src, sbn.s, sbn.n) >= 0 { ok = false }
      else if is_view_type(src, eff.s, eff.n) { ok = false }
      else if str_at((src + eff.s), 1) == "(" { ok = false }            ## a TUPLE field
      else if standard_type_byte_size(decls, src, eff.s, eff.n, ew, a) != scalar_byte_size(src, eff.s, eff.n) { ok = false }
    }
    ## Every field must also HAVE a §6.1 offset — the writer stores at that number and nowhere else.
    if standard_field_byte_offset(decls, src, s, n, fd.ns, fd.nl, a) < 0 { ok = false }
    f = fd.next
  }
  ok
}

## ─── THE ONE BYTE-PRECISE WHOLE-VALUE COPIER (CLAYOUT S3(c)) ───────────────────────────────────
## S3(b) gave the four backends ONE byte-precise whole-value WRITER; this is its mirror on the READ
## side, and it exists for the same reason. `copy := o.inner` binds a nested child of a byte-layout
## root to a STANDALONE local, and the two sides of that copy speak different layouts:
##   the SOURCE is the child's §6.1 byte image inside the root (what the one writer wrote, and what
##     `layout_field_offset_bytes` hands every reader);
##   the DESTINATION is a fresh local of the child's own type, read in the tier `layout_kind` gives
##     THAT type on its own — §6.1 bytes when it is BYTE, one machine word per field when it is WORD.
## A whole-WORD copy is therefore right only when the two coincide (`std_struct_is_word_granular`,
## the audit §5 staging principle). For `struct { a : u16, b : u16 }` they do not: the source holds
## `b` at byte 2 and the destination reads it at word 1 = byte 8, so the word copy delivered `a` twice
## and 0 — measured exit 1 on a64/rv64/wasm with S3(b)'s writer in and the fence out, where the base
## had TRAPPED. That is why S3(b) had to fence it (I11) and why this is S3(c).
##
## `std_copy_kind` is the SINGLE decision of how such a copy is expressed, asked by all four backends
## so none of them invents a fifth way to compute an offset:
##   0 OUT   — no byte-precise copy exists for this type; the caller keeps its fail-loud fence.
##   1 IMAGE — the destination's own tier is BYTE, so it is read at exactly the source's §6.1 offsets:
##             copy `standard_struct_bytes` bytes VERBATIM. (`struct { lead : u16, raw : [u8;2],
##             tail : u16 }` — a child that carries its own byte array is always this case, because a
##             direct byte-typed array field is what `layout_kind` calls BYTE.)
##   2 GATHER — the destination's own tier is WORD, so every field is read at `field_word_offset * 8`:
##             move each SCALAR LEAF from its §6.1 source byte to its destination WORD, sign- or
##             zero-extended from the field's own width. The plan below is that leaf list.
## The domain is the WRITER's domain (`std_struct_is_byte_writable`) intersected with "the destination
## has word offsets all the way down", so a child carrying a `str`, an enum, a union, a tuple or a
## non-byte array is OUT, and out means the caller traps rather than substituting a word offset.
pub std_copy_kind := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  if is_packed(decls, src, s, n) { return 0 }
  if is_union_decl(decls, src, s, n) { return 0 }
  if not std_struct_is_byte_writable(decls, src, s, n, a) { return 0 }
  if layout_kind_is_byte(layout_kind(decls, src, s, n, a)) { return 1 }
  if std_copy_dest_word_ok(decls, src, s, n, a) { return 2 }
  0
}

## The GATHER destination's precondition: every field of this WORD-tier struct has a word offset, and
## every nested struct field is itself WORD-tier with the same property — so `field_word_offset` names
## a real destination slot for each scalar leaf. A nested BYTE-tier field would be read at §6.1 offsets
## INSIDE a word-offset parent, which no writer produces; that shape stays OUT (kind 0) rather than
## being copied to a place nobody reads.
pub std_copy_dest_word_ok := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  if is_packed(decls, src, s, n) { return false }
  if layout_kind_is_byte(layout_kind(decls, src, s, n, a)) { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut ok := true
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    bo := standard_field_byte_offset(decls, src, s, n, fd.ns, fd.nl, a)
    wo := field_word_offset(decls, src, s, n, fd.ns, fd.nl, a)
    if bo < 0 { ok = false }
    if wo < 0 { ok = false }
    aes := arr_field_elem_span(src, eff.s, eff.n)
    mut nested := false
    if aes.n == 0 {
      sbn := base_type_name(src, eff.s, eff.n)
      if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { nested = true }
    }
    ## An ARRAY field cannot reach here: a byte-typed one makes the struct BYTE-tier (rejected above)
    ## and any other kind is outside the writer's domain. Refuse it explicitly all the same, so this
    ## predicate stays sound on its own rather than by a caller's ordering.
    if aes.n != 0 { ok = false }
    if nested and not std_copy_dest_word_ok(decls, src, eff.s, eff.n, a) { ok = false }
    if not nested and aes.n == 0 {
      sz := scalar_byte_size(src, eff.s, eff.n)
      if sz != 1 and sz != 2 and sz != 4 and sz != 8 { ok = false }
    }
    f = fd.next
  }
  ok
}

## The number of bytes an IMAGE copy (`std_copy_kind` 1) moves: the child's own §6.1 size, which is
## exactly what its destination local is read at.
pub std_copy_image_bytes := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  standard_struct_bytes(decls, src, s, n, a)
}

## ONE STEP of the GATHER plan (`std_copy_kind` 2): move `sz` bytes from the source's §6.1 byte offset
## `sbo` (relative to the child's own start) into the destination's WORD `dwo` (relative to the
## destination local's word 0), sign-extending iff `signed`. `found` is false past the end of the plan.
## `seen` is the running leaf count — it is what lets one recursive walk answer both "how many steps"
## and "what is step i" without a second traversal, and without an `in out` accumulator threaded
## through a recursion.
LCopyStep := struct { found : bool, seen : usize, sbo : i64, dwo : i64, sz : usize, signed : bool }

## The recursive walk. `want` is the step index to report (a NEGATIVE `want` reports none, which is how
## `layout_copy_nsteps` counts). `sbias` is the accumulated §6.1 byte offset of this struct inside the
## copy's source, `dbias` the accumulated WORD offset of the matching place inside the destination —
## the two layouts walked side by side, each read from the query that OWNS it
## (`standard_field_byte_offset` and `field_word_offset`), which is the whole point of doing this once.
_copy_walk := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, sbias : i64, dbias : i64, want : i64, seen0 : usize, a : rt::Arena) -> LCopyStep {
  mut r := LCopyStep(found = false, seen = seen0, sbo = 0, dwo = 0, sz = 0, signed = false)
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return r }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    bo := standard_field_byte_offset(decls, src, s, n, fd.ns, fd.nl, a)
    wo := field_word_offset(decls, src, s, n, fd.ns, fd.nl, a)
    aes := arr_field_elem_span(src, eff.s, eff.n)
    mut nested := false
    if aes.n == 0 {
      sbn := base_type_name(src, eff.s, eff.n)
      if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { nested = true }
    }
    if nested {
      sub := _copy_walk(decls, src, eff.s, eff.n, sbias + bo, dbias + wo, want, r.seen, a)
      mut take := false
      if sub.found and (not r.found) { take = true }
      if take { r = LCopyStep(found = true, seen = sub.seen, sbo = sub.sbo, dwo = sub.dwo, sz = sub.sz, signed = sub.signed) }
      if not take { r = LCopyStep(found = r.found, seen = sub.seen, sbo = r.sbo, dwo = r.dwo, sz = r.sz, signed = r.signed) }
    }
    if not nested {
      mut hit := false
      if (not r.found) and i64(r.seen) == want { hit = true }
      if hit { r = LCopyStep(found = true, seen = r.seen + 1, sbo = sbias + bo, dwo = dbias + wo, sz = scalar_byte_size(src, eff.s, eff.n), signed = eff.n != 0 and str_at((src + eff.s), 1) == "i") }
      if not hit { r = LCopyStep(found = r.found, seen = r.seen + 1, sbo = r.sbo, dwo = r.dwo, sz = r.sz, signed = r.signed) }
    }
    f = fd.next
  }
  r
}

## How many scalar leaves a GATHER copy of this type moves.
pub layout_copy_nsteps := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  _copy_walk(decls, src, s, n, 0, 0, 0 - 1, 0, a).seen
}

## Step `want` of the GATHER plan (0-based). `found` false means `want` is past the end.
pub layout_copy_step := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, want : i64, a : rt::Arena) -> LCopyStep {
  _copy_walk(decls, src, s, n, 0, 0, want, 0, a)
}

## ─── THE ARRAY-ELEMENT TIER (CLAYOUT S3(d)) ────────────────────────────────────────────────────
## `layout_elem_stride_bytes` is THE element stride, and it is spec Types §6.4 read literally:
## *"arrays are contiguous, stride = size rounded to align, element i at base + i*stride"*. Every
## backend's element addressing must multiply the index by THIS number and nothing else — that is the
## whole point of putting it here rather than spelling `struct_words * 8` at each site again.
##
## It agrees with the historical `struct_words * 8` for exactly the types where the two layouts
## coincide (the audit §5 staging principle: a struct whose every field is 8 bytes wide and 8-aligned),
## which is why routing a WORD-granular element through it is byte-identical. It DISAGREES the moment
## the element's §6.1 size is not a multiple of 8: `struct { data : [u8;3], inner : { lead : u16,
## raw : [u8;2], tail : u16 } }` is 10 bytes with alignment 2 → stride 10, where `struct_words * 8`
## says 16 and every element past the first lands 6 bytes into the padding.
pub layout_elem_stride_bytes := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, a : rt::Arena) -> usize {
  round_up_to(standard_type_byte_size(decls, src, ts, tl, 1, a), standard_type_byte_align(decls, src, ts, tl, 1, a))
}

## The ARRAY-ELEMENT tier's DOMAIN — the single predicate that decides whether an array of this element
## type is addressed byte-precisely (§6.1 offsets, §6.4 stride) instead of word-granularly. It is the
## intersection of the two decisions that already exist, because the element tier is nothing more than
## those two applied at `base + i*stride`:
##   * the element must BE a byte-tier struct (`layout_kind` = BYTE): that is what makes its
##     construction go through the ONE byte-precise whole-value writer (S3(b)) rather than the
##     word-per-field constructor, and what makes a whole-element copy an IMAGE copy (S3(c) kind 1);
##   * the element must be IN that writer's domain (`std_struct_is_byte_writable`), so every leaf it
##     contains is stored at a `standard_field_byte_offset` some reader can name.
## Everything else answers false and keeps its fence: a `@packed` element (its own byte cursor and its
## own emitter), a WORD-tier element (unchanged, byte-identical), and a byte-tier element carrying a
## `str`, an enum, a union, a tuple or a non-byte array (no byte-precise store exists for it).
pub std_array_elem_byte_tier := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, a : rt::Arena) -> bool {
  bn := base_type_name(src, ts, tl)
  if struct_decl_of(decls, src, bn.s, bn.n) < 0 { return false }
  if is_packed(decls, src, bn.s, bn.n) { return false }
  if is_union_decl(decls, src, bn.s, bn.n) { return false }
  if not layout_kind_is_byte(layout_kind(decls, src, bn.s, bn.n, a)) { return false }
  if not std_struct_is_byte_writable(decls, src, ts, tl, a) { return false }
  true
}

## The frame/linear-memory reservation for one ARRAY ELEMENT. `SlotEntry.estride` and the three
## cross-backend scanners are denominated in WORDS, while Types §6.4 addresses a byte-tier element at
## its real byte stride. Reserve enough words for the byte image (never less than its ceil-to-word
## footprint), but keep the old `struct_words` answer for every other element kind. The reservation is
## deliberately separate from `layout_elem_stride_bytes`: an unaligned 10-byte element reserves 2 words
## per slot while the next element still starts 10 bytes after the previous one.
pub array_elem_word_reservation := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, a : rt::Arena) -> usize {
  if std_array_elem_byte_tier(decls, src, ts, tl, a) {
    return round_up_to(layout_elem_stride_bytes(decls, src, ts, tl, a), 8) / 8
  }
  struct_words(decls, src, ts, tl, a)
}

## ─── THE ARRAY-ELEMENT FENCE (CLAYOUT S3(c)) ───────────────────────────────────────────────────
## An ARRAY whose element is a standard byte-layout struct has no byte-precise tier yet: the element
## STRIDE is `struct_words * 8` while the element is written and read by two different models, so
## `xs[i]` and `xs[i].f` name places nothing wrote. On x86_64 that is already fenced twice
## (`arr_elem_info` for the array-literal form, `resolve_idx_field_place` for the field place). The
## three cross backends had NO such fence and were measured WRONG, not trapping:
##   `[Elem; 2]` with `Elem = struct { data : [u8;8], inner : struct { a : u16, b : u16 } }`,
##   `xs[0].inner.b` → exit 1 on aarch64, riscv64 AND wasm (x86_64: a located reject), because each
##   element is written one machine WORD per field (ten words = 80 bytes) into a 24-byte stride, so
##   element 1's write walks over element 0's fields.
## That is the one I11 violation this family had left — a wrong value where the forbidden outcome is
## exactly a wrong value — so the three cross backends refuse it here, at the ONE query each of them
## funnels every array element width through. Giving the array-element tier a byte-precise stride and
## place resolver is the next slice; a trap is acceptable until then, a wrong value never.
pub require_no_byte_layout_array_elem := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, a : rt::Arena) {
  bn := base_type_name(src, ts, tl)
  if struct_decl_of(decls, src, bn.s, bn.n) < 0 { return }
  if is_packed(decls, src, bn.s, bn.n) {
    panic("selfhost: an array whose element is a @packed struct is not supported by the word-granular array tier; byte-precise element stride and packed field offsets are a deferred slice; rejected rather than silently miscompiled")
  }
  if std_struct_has_byte_layout(decls, src, ts, tl, a) {
    panic("selfhost: an array whose ELEMENT is a standard byte-layout struct (one carrying a `[u8|i8|bits8; N]` field, directly or through a nested struct) has no byte-precise element tier on this backend — the element is written at its §6.1 byte offsets while the array addresses it at `struct_words * 8`, so `xs[i]` and `xs[i].field` name bytes nothing wrote (measured: exit 1 on aarch64/riscv64/wasm before this fence). Rejected rather than silently miscompiled; bind the element's scalar fields through a non-array local instead.")
  }
}

## Does this struct declare a field whose type is an AGGREGATE — a struct, an enum/union, or a `str`
## view — as opposed to a scalar or an explicitly byte-typed fixed array? The standard-byte tier's
## PARAMETER path is byte-aware for the scalar and byte-array fields (that is what
## `test/standard_byte_array_field.al` locks: `sum := fn(s : S)` over `struct { data : [u8;4],
## tail : u16 }` reads both correctly through the by-reference param), but a nested AGGREGATE field of
## a by-ref param is resolved with `field_word_offset`, which counts the byte array as N WORDS. This
## predicate is the exact line between the two, so the fence rejects only what is broken.
pub std_struct_has_aggregate_field := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut found := false
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    es := arr_field_elem_span(src, eff.s, eff.n)
    if es.n == 0 {
      sbn := base_type_name(src, eff.s, eff.n)
      if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { found = true }
      if enum_decl_of(decls, src, sbn.s, sbn.n) >= 0 { found = true }
      if str_at((src + eff.s), eff.n) == "str" { found = true }
    }
    f = fd.next
  }
  found
}

## Does this struct's §6.1 BYTE layout land every field at exactly the word-model position — field at
## `field_word_offset * 8`, total size `struct_words * 8` — recursively through its struct fields?
## This is the audit's staging principle made checkable: "for a struct whose every field is 8 bytes
## wide and 8-aligned, the word offsets already ARE the C offsets". Such a child can be written by the
## word constructor and read at §6.1 offsets, or vice versa, with the same result on all four
## backends; anything else is written by one emitter and read by another. `@packed` (its own byte
## cursor), the BYTE tier itself, and a word-tier struct carrying a byte-layout aggregate all answer
## false — each needs its own consumer, not this one.
pub std_struct_is_word_granular := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  if is_packed(decls, src, s, n) { return false }
  if std_struct_has_byte_layout(decls, src, s, n, a) { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  ## PASS 1 — a field whose array length is not statically known has no standard byte size at all
  ## (`standard_type_byte_size` panics on `wsize == 0`), so answer false BEFORE any query runs.
  mut f0 := d.fields_head
  mut sized := true
  while f0 != 0 {
    fd0 := deref(fld_p(f0))
    eff0 := subst_field_ty(decls, src, s, n, fd0.ts, fd0.tl, a)
    ew0 := eff_field_wsize(decls, src, s, n, fd0.ts, fd0.tl, fd0.wsize, a)
    aes0 := arr_field_elem_span(src, eff0.s, eff0.n)
    if ew0 == 0 and aes0.n != 0 { sized = false }
    f0 = fd0.next
  }
  if not sized { return false }
  ## PASS 2 — every field's two offsets must coincide, and a struct-typed field must itself qualify.
  mut f := d.fields_head
  mut ok := true
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
    bo := standard_field_byte_offset(decls, src, s, n, fd.ns, fd.nl, a)
    wo := field_word_offset(decls, src, s, n, fd.ns, fd.nl, a)
    if bo < 0 or wo < 0 { ok = false }
    if bo != wo * 8 { ok = false }
    sbn := base_type_name(src, eff.s, eff.n)
    if ew == 1 and struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 {
      if not std_struct_is_word_granular(decls, src, eff.s, eff.n, a) { ok = false }
    }
    f = fd.next
  }
  if standard_struct_bytes(decls, src, s, n, a) != struct_words(decls, src, s, n, a) * 8 { ok = false }
  ok
}

## Is this struct WRITTEN by `emit_struct_assign`'s WORD loop (one machine word per `field_words`)?
## That is the only child representation a containing byte-layout struct can construct in S3(a): the
## outer places such a child at a byte offset that is always a multiple of 8 (its
## `standard_type_byte_align` is 8) and then addresses the child's fields as words. A `@packed`
## child, a BYTE-tier child, and a word-tier child that contains a byte-layout aggregate each need a
## different writer, so they stay fail-loud until their own consumer lands.
pub layout_struct_is_word_stored := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  lk := layout_kind(decls, src, s, n, a)
  if layout_kind_is_packed(lk) { return false }
  if layout_kind_is_byte(lk) { return false }
  if std_struct_has_byte_layout(decls, src, s, n, a) { return false }
  ## WORD-GRANULAR is the load-bearing half: x86 writes such a child with `emit_struct_assign` (word
  ## per field) and the three cross backends write it with their own byte-precise recursion, so only a
  ## child whose two images COINCIDE can be constructed identically on all four.
  std_struct_is_word_granular(decls, src, s, n, a)
}

## The natural ALIGNMENT of a type in the standard byte-layout tier.  Native scalar widths use the
## matching byte alignment; ordinary word-model aggregates stay word-aligned.  An explicit `@align`
## on a field is applied by the struct cursor, not in this type query.
pub standard_type_byte_align := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, wsize : usize, a : rt::Arena) -> usize {
  es := arr_field_elem_span(src, ts, tl)
  if es.n != 0 {
    if layout_byte_type_eek(src, es.s, es.n) != 0 { return 1 }
    if wsize == 0 { panic("selfhost: a computed array length has no standard byte layout in this slice") }
    return standard_type_byte_align(decls, src, es.s, es.n, 1, a)
  }
  if wsize == 1 {
    sbn := base_type_name(src, ts, tl)
    if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 {
      if layout_kind_is_byte(layout_kind(decls, src, ts, tl, a)) { return standard_struct_align(decls, src, ts, tl, a) }
      return 8
    }
    if enum_decl_of(decls, src, ts, tl) >= 0 {
      el := enum_layout(decls, src, ts, tl, a)
      return el.align
    }
    if str_at((src + ts), tl) == "str" { return 8 }
  }
  scalar_byte_size(src, ts, tl)
}

## The SIZE of a type in bytes for the same tier. Arrays use the normative stride rule (size rounded
  ## up to alignment), byte arrays consequently have stride 1, and a WORD-tier aggregate retains its
  ## established word size until that aggregate itself opts into the standard byte tier.
pub standard_type_byte_size := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, wsize : usize, a : rt::Arena) -> usize {
  es := arr_field_elem_span(src, ts, tl)
  if es.n != 0 {
    if wsize == 0 { panic("selfhost: a computed array length has no standard byte layout in this slice") }
    stride := round_up_to(standard_type_byte_size(decls, src, es.s, es.n, 1, a), standard_type_byte_align(decls, src, es.s, es.n, 1, a))
    return wsize * stride
  }
  if wsize == 1 {
    sbn := base_type_name(src, ts, tl)
    if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 {
      if layout_kind_is_byte(layout_kind(decls, src, ts, tl, a)) { return standard_struct_bytes(decls, src, ts, tl, a) }
      return struct_words(decls, src, ts, tl, a) * 8
    }
    if enum_decl_of(decls, src, ts, tl) >= 0 { return enum_layout(decls, src, ts, tl, a).size }
    if str_at((src + ts), tl) == "str" { return 16 }
  }
  scalar_byte_size(src, ts, tl)
}

## The leftmost source position of a tuple type-expression element. Keep this as a separate helper:
## the self-host seed has a known nested-match lowering scar, while the mono path's equivalent helper
## is deliberately a single match.
layout_tuple_first_start := fn(e : ptr(Expr)) -> usize {
  match deref(e) {
    Expr::Var(s, n) => { s }
    Expr::Call(cs, cl, na, ah) => { cs }
    _ => { 0 }
  }
}

## Recover the source span of a tuple type argument. The parser represents `(T0, T1, …)` as an
## `ArrayLit`, so the AST carries the elements but not the opening/closing delimiters. This is the
## layout-side twin of lower's mono recovery; keeping it here lets sema collect the same concrete type
## span for a `when size(T)` guard without importing the emitter.
pub tuple_typearg_span := fn(e : ptr(Expr), src : ptr(u8)) -> LSpan {
  if unchecked bitcast(usize, e) == 0 { return LSpan(s = 0, n = 0) }
  match deref(e) {
    Expr::ArrayLit(nel, ehead) => {
      if nel == 0 or unchecked bitcast(usize, ehead) == 0 { return LSpan(s = 0, n = 0) }
      e0 := deref(arg_p(ehead)).e
      s0 := layout_tuple_first_start(e0)
      if s0 == 0 { return LSpan(s = 0, n = 0) }
      mut op := s0
      mut back := true
      while back and op > 0 {
        op -= 1
        c := str_at((src + op), 1)
        if c == "(" { back = false }
        else if c == "[" { return LSpan(s = 0, n = 0) }
      }
      if back { return LSpan(s = 0, n = 0) }
      mut depth := 0
      mut i := op
      mut cl := op
      mut fwd := true
      while fwd {
        c := str_at((src + i), 1)
        if c == "(" { depth += 1 }
        else if c == ")" {
          depth -= 1
          if depth == 0 { cl = i ; fwd = false }
        }
        i += 1
      }
      if fwd { return LSpan(s = 0, n = 0) }
      LSpan(s = op, n = cl - op + 1)
    }
    _ => { LSpan(s = 0, n = 0) }
  }
}

## The byte size of a tuple type span. Components are laid out in declaration order with natural
## alignment and tail padding, exactly Types §6.1. `standard_type_*` already preserves the established
## word size for aggregate components, so this is byte-precise for the S2 mixed scalar shape while
## remaining neutral for the existing all-word tuple forms.
pub tuple_type_size_bytes := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, a : rt::Arena) -> usize {
  if tl == 0 or str_at((src + ts), 1) != "(" { return 0 }
  mut off := 0
  mut al := 1
  mut i := 0
  mut scanning := true
  while scanning {
    cs := typearg_at(src, ts, 0, usize(i))
    if cs.n == 0 { scanning = false } else {
      ca := standard_type_byte_align(decls, src, cs.s, cs.n, 1, a)
      if ca > al { al = ca }
      off = round_up_to(off, ca)
      off += standard_type_byte_size(decls, src, cs.s, cs.n, 1, a)
      i += 1
    }
  }
  round_up_to(off, al)
}

## The single byte-size ladder used by both the lower's `when` fold and sema's located mirror. The
## layout tier is selected before converting to words: a packed/standard-byte struct reports its exact
## byte size, while the historical word tier retains its rounded word size. Tuple type arguments use
## the same standard product calculator. Unknown names retain the scalar fallback for the lower's
## conservative fold; sema gates that fallback on a known concrete type.
pub layout_type_size_bytes := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, a : rt::Arena) -> usize {
  if tl != 0 and str_at((src + ts), 1) == "(" { return tuple_type_size_bytes(decls, src, ts, tl, a) }
  if is_niche_folded(src, ts, tl) { return 8 }
  sbn := base_type_name(src, ts, tl)
  sdi := struct_decl_of(decls, src, sbn.s, sbn.n)
  if sdi >= 0 {
    lk := layout_kind(decls, src, ts, tl, a)
    if layout_kind_is_packed(lk) { return packed_struct_bytes(decls, src, ts, tl, a) }
    if layout_kind_is_byte(lk) { return standard_struct_bytes(decls, src, ts, tl, a) }
    sw := struct_words(decls, src, ts, tl, a)
    if sw == 0 { return 0 }
    mut bytes := sw * 8
    sa := struct_align_attr(decls, src, ts, tl)
    if sa >= 1 { bytes = round_up_to(bytes, usize(sa)) }
    return bytes
  }
  if is_union_decl(decls, src, ts, tl) { return union_words(decls, src, ts, tl, a) * 8 }
  if enum_decl_of(decls, src, sbn.s, sbn.n) >= 0 { return enum_layout(decls, src, ts, tl, a).size }
  type_byte_size(src, ts, tl)
}

## The standard byte offset of a field and the total byte size/alignment of the containing struct.
## Declaration order and padding are exactly Types §6.1.  Unknown fields return -1; all callers must
## keep the existing fail-loud contract rather than falling back to a word offset.
pub standard_struct_align := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut mx := 1
  sa := struct_align_attr(decls, src, s, n)
  if sa >= 1 { mx = usize(sa) }
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
    mut fa := standard_type_byte_align(decls, src, eff.s, eff.n, ew, a)
    ea := field_align_attr(src, fd.ns)
    if ea >= 1 and usize(ea) > fa { fa = usize(ea) }
    if fa > mx { mx = fa }
    f = fd.next
  }
  mx
}

pub standard_field_byte_offset := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return -1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut off := 0
  mut res : i64 = -1
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
    mut fa := standard_type_byte_align(decls, src, eff.s, eff.n, ew, a)
    ea := field_align_attr(src, fd.ns)
    if ea >= 1 and usize(ea) > fa { fa = usize(ea) }
    off = round_up_to(off, fa)
    if streq(src, fd.ns, fd.nl, fs, fl) { res = i64(off) }
    off += standard_type_byte_size(decls, src, eff.s, eff.n, ew, a)
    f = fd.next
  }
  res
}

pub standard_struct_bytes := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut off := 0
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
    mut fa := standard_type_byte_align(decls, src, eff.s, eff.n, ew, a)
    ea := field_align_attr(src, fd.ns)
    if ea >= 1 and usize(ea) > fa { fa = usize(ea) }
    off = round_up_to(off, fa)
    off += standard_type_byte_size(decls, src, eff.s, eff.n, ew, a)
    f = fd.next
  }
  round_up_to(off, standard_struct_align(decls, src, s, n, a))
}

pub field_words := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, wsize : usize, a : rt::Arena) -> usize {
  if wsize == 1 {
    ## STRIP any `(…)` type-args for the struct-decl LOOKUP (a generic-struct field type
    ## `Slice(u8)` streqs the WHOLE name and would miss the `Slice` decl, so a 2-word field would
    ## size as 1 → the next field overwrites it, a silent struct-with-generic-struct-field
    ## miscompile), but pass the FULL span `[ts,tl)` on to `struct_words` so it can recover the
    ## instance's type-args (`subst_field_ty`) when sizing.
    sbn := base_type_name(src, ts, tl)
    if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { return struct_words(decls, src, ts, tl, a) }
    ## an ENUM-typed field occupies `1 (discriminant) + max payload arity` words — the parser defaults
    ## its `wsize` to 1, which would let the NEXT field overwrite the enum's payload (a silent
    ## struct-with-enum-field miscompile). Count it like an enum local/element slot.
    if enum_decl_of(decls, src, ts, tl) >= 0 {
      ## RAW UNION fields overlap at offset 0 and reserve only the maximum member width, with no
      ## discriminant word. A union is represented by the existing kind-3 decl shape, so this
      ## distinction must happen before the ordinary enum `1 + payload` sizing or a following
      ## struct field would be displaced by one word.
      if is_union_decl(decls, src, ts, tl) { return union_words(decls, src, ts, tl, a) }
      return 1 + enum_inst_words(decls, src, ts, tl, a)
    }
    if str_at((src + ts), tl) == "str" { return 2 }
  }
  ## ARRAY field `[T; N]` (`wsize` = N, the element COUNT — the parser's fixed-array width, or the
  ## comptime-folded `eff_field_wsize` for `[T; <expr>]`; a `[T; 1]` array keeps `wsize == 1` and so
  ## reaches here after the scalar/struct/enum/str probes above miss its bracketed span). Each element
  ## occupies `field_words(T, 1)` words — 1 for a scalar/word element (byte-identical to the old `N`
  ## sizing), `struct_words(T)` for a STRUCT element, `1 + arity` for an ENUM element, 2 for a `str`.
  ## So the field's true word width is `N * per_element_words`; the old code returned bare `N`, which
  ## UNDER-reserved a `[Struct; N]` field's frame block so element stores overran into adjacent slots /
  ## the saved `%rbp` (a SIGILL / silent miscompile — Types §9.4). A non-array span (a tuple `(…)`, or a
  ## scalar with `wsize == 1`) has no leading `[` → `es.n == 0` → `wsize` unchanged (fixpoint-neutral).
  es := arr_field_elem_span(src, ts, tl)
  if es.n != 0 { return wsize * field_words(decls, src, es.s, es.n, 1, a) }
  wsize
}

pub struct_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  ## STRIP `(…)` type-args for the struct-decl LOOKUP so a parenthesized generic-struct instance
  ## span (`Slice(u8)`) resolves its `Slice` decl; the FULL span `[s,s+n)` is kept below for the
  ## per-field `subst_field_ty`/`eff_field_wsize` reads (they re-read the `(…)` args to substitute
  ## an aggregate type-arg into a type-param field).
  sbn := base_type_name(src, s, n)
  di := struct_decl_of(decls, src, sbn.s, sbn.n)
  if di < 0 { return 0 }
  ## THE ORACLE decides the tier once for this whole function (`layout_kind`). A BYTE-tier struct's
  ## reservation must cover its exact byte image, including the scalar shape admitted by CLAYOUT S4
  ## and its recursively supported nested children. A remaining plain struct that only contains an
  ## unsupported byte-layout aggregate is rejected below until all of its consumers share the offsets.
  lk := layout_kind(decls, src, s, n, a)
  if layout_kind_is_byte(lk) {
    return (standard_struct_bytes(decls, src, s, n, a) + 7) / 8
  }
  if not layout_kind_is_packed(lk) and std_struct_has_byte_layout(decls, src, s, n, a) {
    panic("selfhost: a plain struct containing a byte-layout aggregate field is not yet supported by all aggregate consumers — bind the inner value separately or use @packed")
  }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut tot := 0
  while f != 0 {
    fd := deref(fld_p(f))
    ## NESTED-GENERIC: a type-PARAM field of a generic INSTANCE (`v : T` in `Box(Pair(u64))`) is sized
    ## as the instance's type-arg (`Pair` → 2 words); gated to aggregate type-args, so a scalar-arg
    ## instance (`Box(u64)`) sizes byte-identically to the un-substituted param `T` (1 word).
    ## COMPTIME-VALUE-GENERIC: a `[T; <expr>]` field (parser `wsize` 0) folds its length against the
    ## instance's comptime-value bindings (`uint(192)` → `[u64; 3]` = 3 words).
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    ## The default struct layout is still word-granular. An explicitly byte-typed array field would
    ## therefore be accepted but laid out at an element stride of 8, while Types §6.4 requires stride
    ## 1 for `[u8|i8|bits8; N]`. Keep the correct-or-trap invariant until the shared byte-layout path
    ## exists: `@packed` fields already have a separate byte emitter and remain supported here.
    ## `ew` (the effective field WORD size) is bound BEFORE the fences below: the second fence reads it,
    ## and `:=` locals are function-scoped, so binding it after the read made that fence consult an unset
    ## slot on the first iteration and the PREVIOUS field's `wsize` afterwards. The fence is redundant
    ## today (the `layout_kind` gate above catches the same shape first) but it must be correct before
    ## that gate widens (CLAYOUT S4).
    ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
    if not layout_kind_is_packed(lk) {
      aes := arr_field_elem_span(src, eff.s, eff.n)
      if aes.n != 0 and layout_byte_type_eek(src, aes.s, aes.n) != 0 { panic("selfhost: a plain struct with a byte fixed-array field is not yet supported by the word-granular aggregate layout; use @packed or wait for the shared byte-layout implementation") }
      if std_type_has_byte_layout(decls, src, eff.s, eff.n, ew, a) { panic("selfhost: a plain struct containing a byte-layout aggregate field is not yet supported by all aggregate consumers — bind the inner value separately or use @packed") }
    }
    tot += field_words(decls, src, eff.s, eff.n, ew, a)
    f = fd.next
  }
  ## §8 `@packed`: the SLOT reservation (this WORD count) must cover the byte-precise layout — an
  ## `@offset(N)` field can push the highest byte END past the field-count words, so reserve at least
  ## `ceil(packed_bytes/8)` words (else a large-offset packed local would store past its frame block).
  ## Gated on `is_packed` → NEUTRAL for the whole word-layout corpus; for an offset-free packed struct
  ## `tot` (one word per scalar field) already dominates, so this only grows genuinely sparse layouts.
  if layout_kind_is_packed(lk) {
    pw := (packed_struct_bytes(decls, src, s, n, a) + 7) / 8
    if pw > tot { tot = pw }
  }
  tot
}

## STRUCT-WITH-ARRAY-FIELD tier — the CUMULATIVE word offset of field `[fs, fs+fl)` within
## struct `[s, s+n)`: the sum of the `wsize`s of every field declared BEFORE it (-1 if not
## found). So field `f` lives at slot `base_off + field_word_offset` (byte
## `-(base_off + offset + 1) * 8(%rbp)`). For a scalar-only struct each prior field is one
## word, so this equals the declaration index — the pre-existing word-sized layout, identical.
## A struct `{ buf : [u64; 8], len : u64 }` puts `buf` at word 0 and `len` at word 8.
pub field_word_offset := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> i64 {
  ## RAW UNION (spec Types §6.3): every member starts at offset 0 (untagged overlap), so a member read
  ## `u.m` resolves to word 0 for ANY member `m`. Gated on `is_union_decl` → an enum/struct is untouched
  ## (byte-identical, fixpoint-neutral). Returns 0 when `m` is a real member, else -1 (unknown member).
  if is_union_decl(decls, src, s, n) {
    if union_member_ty(decls, src, s, n, fs, fl).n != 0 { return 0 }
    return -1
  }
  ## STRIP `(…)` type-args for the struct-decl LOOKUP so a parenthesized generic-struct instance
  ## span (`Slice(u8)`) resolves its `Slice` decl (else field offsets come back -1 and a nested
  ## `h.s.len` reads the wrong slot); FULL span `[s,s+n)` kept for the per-field subst reads.
  sbn := base_type_name(src, s, n)
  di := struct_decl_of(decls, src, sbn.s, sbn.n)
  if di < 0 { return -1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut off := 0
  mut res := -1
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, fs, fl) { res = i64(off) }
    ## NESTED-GENERIC: advance by the substituted field width (a `Pair`-typed param field is 2 words),
    ## so a later field's offset — and the READ side that funnels through here — stays consistent with
    ## `struct_words`. Gated to aggregate type-args (scalar-arg instances are byte-identical).
    ## COMPTIME-VALUE-GENERIC: a `[T; <expr>]` field advances by its folded length (see `struct_words`).
    eff := subst_field_ty(decls, src, s, n, fd.ts, fd.tl, a)
    ew := eff_field_wsize(decls, src, s, n, fd.ts, fd.tl, fd.wsize, a)
    off += field_words(decls, src, eff.s, eff.n, ew, a)
    f = fd.next
  }
  res
}

## Is field `[fs,fl)` of struct type `[s,s+n)` a FLOAT (`f64`/`f32`)? The native backends' float
## detectors call this (the shared dual of `lower::field_type_span`). False if struct/field unknown.
pub field_type_is_float := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut r := false
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, fs, fl) { if fd.tl != 0 { tn := str_at((src + fd.ts), fd.tl) ; if tn == "f64" { r = true } ; if tn == "f32" { r = true } } }
    f = fd.next
  }
  r
}

## §8 BYTE-PRECISE LAYOUT — the `@packed` lever (spec Types §8). The default layout is the word-sized
## model (I6): every field ≥1 whole word, `struct_words`/`field_word_offset` above. A struct carrying
## the `@packed` attribute overrides that with a BYTE-precise layout: fields at their natural byte
## offsets, alignment 1, NO padding, size = sum of the field byte sizes. These siblings compute that
## byte layout; they fire ONLY for an attributed struct (see `is_packed`), so an un-attributed struct
## keeps the word-sized path BYTE-IDENTICALLY — the change is fixpoint-neutral (`src/`+`lib/` declare no
## `@packed` struct) and full-e2e-safe (the whole existing corpus is unchanged).
##
## Is the struct named `[s, s+n)` declared `@packed`? Resolve its decl (by tail name), then SOURCE-SCAN
## forward from the DECL's own name over `:=` + whitespace for the `@packed` marker — a VALUE-position
## prefix attribute (`Name := @packed struct {…}`, the spec's `@align(N) T` prefix surface). Mirrors the
## `lower::extern_symbol` source-scan discipline: the parser consumes+discards `@packed`, so the lower
## recovers it here (no `Decl` field — AST-neutral, so the fixpoint stays stable). Scanning from the
## resolved DECL name (not the use-site span) means a use anywhere (`size(P)`, a slot's stored type span)
## resolves the attribute correctly. False for every non-packed / unresolved type.
pub is_packed := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  ## the DECLARATION-PREFIX spelling `@packed Pk := struct {…}` (Declarations §2.3 / Grammar §3.2) is
  ## the same declaration as the value-position one and gets the same layout — it used to be parsed
  ## and then silently discarded (a `@packed` struct laid out unpacked, with no diagnostic).
  if _decl_prefix_attr(src, d.name_start, "packed").s != 0 { return true }
  mut p := d.name_start + d.name_len
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return false }
  p = p + 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 7) != "@packed" { return false }
  ## boundary: `@packed` must be a whole attribute (the next byte is whitespace before `struct`), not the
  ## prefix of a longer ident — mirrors `extern_symbol`'s whole-attribute check.
  bc := str_at((src + p + 7), 1)
  if bc == " " or bc == "\n" or bc == "\t" or bc == "\r" { return true }
  false
}

## §8.1 `@require(pred) T` VALIDITY CONTRACT — the PREDICATE span of a require-typed alias `[s, s+n)`.
## A require type is recorded (parser) as a BRAND-SHAPED decl (kind 0, arity 1, ret_ts/ret_tl = the
## underlying scalar T) so `Name(v)` resolves/converts to T; the `@require(pred)` marker text stays in
## `src`. This SOURCE-SCAN (the `is_packed`/`enum_repr_ty` discipline — no AST field) finds that decl
## by tail name, walks its RHS `:= @require( <pred> )`, and returns the balanced inner `<pred>` span
## (whitespace-trimmed) — for a NAMED-fn predicate the bare fn ident. Returns `{0,0}` when the type
## carries no require contract (a plain brand / any other decl / a malformed RHS), so the construction-
## site check is DORMANT for every non-require type — the self-host build (no `@require` in src/lib)
## stays byte-identical (the TOOL-1 fixpoint holds). The parser guarantees the `( … )` is balanced, so
## the scan terminates at the matching `)`.
## The best-ranked (Modules §3) declaration of the UNARY type-wrapper shape a brand and an
## `@require` contract share (kind 0, `arity == 1`, an underlying type in `ret_ts/ret_tl`), or -1.
## Extracted so `require_pred`'s single-pass source scan can SKIP the candidates §3 makes unnameable
## without being restructured: it had taken the FIRST match, which is why a decoy `Nz := @require(bad)
## u64` sorting BEFORE the ancestor's ran the WRONG predicate (measured: a trap instead of 42).
unary_type_decl_ranked := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> i64 {
  cnt := rt::vec_len(deref(decls))
  mut best := 0 - 1
  mut besti := 0 - 1
  th := _fnv_name(src, ns, nl)
  mut jc := lni_lo(decls, cnt, th)
  jce := lni_hi(decls, cnt, th)
  mut i := 0
  while jc < jce {
    i = lni_at(decls, cnt, jc)
    jc = jc + 1
    if lni_skip(decls, cnt, i, th) == false {
      d := deref(decl_get(decls, i))
      if d.kind == 0 and d.arity == 1 and d.ret_tl != 0 and streq(src, d.name_start, d.name_len, ns, nl) {
        r := type_mod_rank(src, d.mod_start, d.mod_len)
        if r >= 0 and r > best { best = r; besti = i64(i) }
      }
    }
  }
  besti
}

pub require_pred := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> LSpan {
  cnt := rt::vec_len(deref(decls))
  nm := name_tail(src, s, n)
  ## -1 = no candidate is nameable from here (or no naming module is published) -> every candidate
  ## stays admissible and the historical first-match answer is preserved.
  win := unary_type_decl_ranked(decls, src, nm.s, nm.n)
  th := _fnv_name(src, nm.s, nm.n)
  mut jc := lni_lo(decls, cnt, th)
  jce := lni_hi(decls, cnt, th)
  mut i := 0
  while jc < jce {
    i = lni_at(decls, cnt, jc)
    jc = jc + 1
    d := deref(decl_get(decls, i))
    if d.kind == 0 and d.arity == 1 and d.ret_tl != 0 and streq(src, d.name_start, d.name_len, nm.s, nm.n)
       and (win < 0 or i64(i) == win) {
      mut p := d.name_start + d.name_len
      while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
      if str_at((src + p), 2) != ":=" { return LSpan(s = 0, n = 0) }
      p = p + 2
      while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
      ## Both normative surfaces are accepted: `@require(pred) T` and `T.require(pred)`.
      ## The parser has already recorded the underlying type in `ret_ts/ret_tl`; for the UFCS form,
      ## verify that the source's receiver is that same bare type so an ordinary `value.require(...)`
      ## binding can never acquire a validity contract by accident.
      if str_at((src + p), 8) == "@require" {
        p = p + 8
      } else {
        bs := p
        while str_at((src + p), 1) != " " and str_at((src + p), 1) != "\n" and str_at((src + p), 1) != "\t" and str_at((src + p), 1) != "\r" and str_at((src + p), 1) != "." { p = p + 1 }
        be := p
        while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
        if str_at((src + p), 1) != "." { return LSpan(s = 0, n = 0) }
        p = p + 1
        while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
        if str_at((src + p), 7) != "require" or not streq(src, d.ret_ts, d.ret_tl, bs, be - bs) { return LSpan(s = 0, n = 0) }
        p = p + 7
      }
      while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
      if str_at((src + p), 1) != "(" { return LSpan(s = 0, n = 0) }
      p = p + 1
      mut depth := 1
      ps := p
      while depth != 0 {
        c := str_at((src + p), 1)
        if c == "(" { depth = depth + 1 }
        else if c == ")" { depth = depth - 1 }
        if depth != 0 { p = p + 1 }
      }
      mut a0 := ps
      mut b0 := p
      while a0 < b0 and (str_at((src + a0), 1) == " " or str_at((src + a0), 1) == "\n" or str_at((src + a0), 1) == "\t" or str_at((src + a0), 1) == "\r") { a0 = a0 + 1 }
      while b0 > a0 and (str_at((src + (b0 - 1)), 1) == " " or str_at((src + (b0 - 1)), 1) == "\n" or str_at((src + (b0 - 1)), 1) == "\t" or str_at((src + (b0 - 1)), 1) == "\r") { b0 = b0 - 1 }
      return LSpan(s = a0, n = b0 - a0)
    }
    i += 1
  }
  LSpan(s = 0, n = 0)
}

## The BYTE size of a SCALAR field type `[ts, ts+tl)` for the packed layout (spec §8 / the machine
## model). The canonical sub-word rows live in `scalar_width`; this wrapper retains the public query's
## established 8-byte answer for word-sized, aggregate, and unresolved names. A `@packed` struct in
## this increment carries SCALAR fields only; a non-scalar field would size as 8 here (the word default).
pub scalar_byte_size := fn(src : ptr(u8), ts : usize, tl : usize) -> usize {
  w := scalar_width::subword_bytes(src, ts, tl)
  if w != 0 { return w }
  8
}

## ─── The scalar TYPE-NAME decisions, shared by every backend ───────────────
##
## `src/aarch64.al`, `src/riscv64.al` and `src/wat.al` each carried its own private copy of the six
## predicates below, byte-for-byte identical in all three. They answer ONE question each — "is this
## type name signed / unsigned / float / narrow / an integer conversion", and "does this byte end a
## type token" — and none of them has a target-dependent answer: the language decides them, not the
## machine. Three copies of a glyph list is the exact shape that produced the `op=` defect (three
## source scans listing different operator subsets rejected a valid program AND accepted a write to
## an immutable binding), and the same shape is live here today: `src_ann_float` on aarch64 and wat
## scanned with an INLINE stop set while riscv64 routed through `tok_stop`, so the three disagreed
## about where a type token ends. One home, one answer.
##
## The x86_64 lower keeps its own fourth copies (`src/lower.al`) — a different lane owns that file,
## so routing it here is a follow-up, not this change.

## Does byte `c` TERMINATE a type token in an annotation scan? The whitespace/assignment/statement
## separators plus the two closers that end a parenthesised or argument-list type.
pub ann_tok_stop := fn(c : str) -> bool {
  c == " " or c == "=" or c == "\n" or c == "\t" or c == "" or c == ";" or c == "," or c == ")"
}

## Is the type name `[ts, ts+tl)` a SIGNED integer? (Types §4 — the `i*` family plus `isize`.)
pub scalar_name_is_signed := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  tx := str_at((src + ts), tl)
  tx == "i8" or tx == "i16" or tx == "i32" or tx == "i64" or tx == "isize"
}

## Is the type name `[ts, ts+tl)` an UNSIGNED integer? (The `u*` family plus `usize`.)
pub scalar_name_is_unsigned := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  tx := str_at((src + ts), tl)
  tx == "u8" or tx == "u16" or tx == "u32" or tx == "u64" or tx == "usize"
}

## Is the type name `[ts, ts+tl)` a FLOAT? An EMPTY span is not a float — a failed annotation scan
## returns `tl == 0` and must not be read as `f64`.
pub scalar_name_is_float := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  if tl == 0 { return false }
  nm := str_at((src + ts), tl)
  nm == "f64" or nm == "f32"
}

## The SUB-WORD integer name in `[ts, ts+tl)`, or `""` when the type is word-width (or not an
## integer). The caller uses the returned name to pick its own narrowing instruction, so the NAME is
## shared and the encoding stays per-target.
pub scalar_name_narrow := fn(src : ptr(u8), ts : usize, tl : usize) -> str {
  tx := str_at((src + ts), tl)
  if tx == "u8" or tx == "u16" or tx == "u32" or tx == "i8" or tx == "i16" or tx == "i32" { return tx }
  ""
}

## Is `name` one of the integer CONVERSION built-ins (`u8(x)` … `isize(x)`)? A call to one of these
## is a width/signedness cast, not a user function call.
pub scalar_name_is_int_conv := fn(name : str) -> bool {
  name == "u8" or name == "u16" or name == "u32" or name == "u64" or name == "usize" or name == "i8" or name == "i16" or name == "i32" or name == "i64" or name == "isize"
}

## ─── The ANNOTATION SOURCE SCAN, shared by every backend ───────────────────
##
## One scan, three questions. Given a position just past a NAME in the source (a local binding's
## name, a global decl's name), each of these skips blanks, requires a `:`, refuses `:=` (an
## INFERRED binding carries no annotation), then reads the type token up to `ann_tok_stop` and asks
## its own predicate of it. The three backends each carried its own copy of all three — nine copies
## of one scan — and they were byte-for-byte identical, which is exactly why they must stop being
## nine: the `op=` defect was three copies of a source scan that had drifted apart.
##
## The scan is a RECOVERY, not the parser: the annotation is read back out of the source because
## `Stmt::Assign` does not carry it. Its answers are one-directional — a failed scan returns
## "unknown" (false / ""), never a wrong type — so a caller that misses an annotation falls back to
## the conservative default rather than to a wrong width.

## The shared prefix: skip blanks, require `:`, refuse `:=`, and return the type token's span.
## `n == 0` means "no annotation here" and every caller must read it that way.
ann_scan_span := fn(src : ptr(u8), pos : usize) -> LSpan {
  mut i := pos
  mut go := true
  while go { if str_at((src + i), 1) == " " { i = i + 1 } else { go = false } }
  if str_at((src + i), 1) != ":" { return LSpan(s = 0, n = 0) }
  i = i + 1
  go = true
  while go { if str_at((src + i), 1) == " " { i = i + 1 } else { go = false } }
  if str_at((src + i), 1) == "=" { return LSpan(s = 0, n = 0) }   ## `:=` — inferred, no annotation
  tstart := i
  go = true
  while go { if ann_tok_stop(str_at((src + i), 1)) { go = false } else { i = i + 1 } }
  LSpan(s = tstart, n = i - tstart)
}

## Is the annotation at `pos` a SIGNED integer type?
pub ann_scan_signed := fn(src : ptr(u8), pos : usize) -> bool {
  sp := ann_scan_span(src, pos)
  if sp.n == 0 { return false }
  scalar_name_is_signed(src, sp.s, sp.n)
}

## Is the annotation at `pos` an UNSIGNED integer type?
pub ann_scan_unsigned := fn(src : ptr(u8), pos : usize) -> bool {
  sp := ann_scan_span(src, pos)
  if sp.n == 0 { return false }
  scalar_name_is_unsigned(src, sp.s, sp.n)
}

## Is the annotation at `pos` a FLOAT type?
##
## THE ONE MEMBER OF THIS FAMILY THAT HAD DRIFTED. `aarch64` and `wat` scanned the type token with
## an INLINE stop set (`" "`, `"="`, `"\n"`, `""`) while `riscv64` routed through `tok_stop`, which
## also stops at `"\t"`, `";"`, `","` and `")"`. So the three answered differently for the same
## source: `x :\tf64\t= 1.0` yields the token `f64\t` on aarch64/wat (NOT a float -> the value is
## handled as an integer, a normal exit with a wrong value) and `f64` on riscv64. aarch64 also
## omitted the `:=` guard the other two had; that one was harmless, because `"="` is in its inline
## stop set too, so the token came back empty and empty is not a float.
##
## Unified onto `ann_scan_span` — the stop set that all three backends ALREADY used for the signed,
## unsigned and narrow scans of the very same annotation. The alternative (making riscv64 match the
## other two) would have taken the answer that is wrong on a tab.
pub ann_scan_float := fn(src : ptr(u8), pos : usize) -> bool {
  sp := ann_scan_span(src, pos)
  if sp.n == 0 { return false }
  scalar_name_is_float(src, sp.s, sp.n)
}

## The SUB-WORD integer name in the annotation at `pos`, or `""`.
pub ann_scan_narrow := fn(src : ptr(u8), pos : usize) -> str {
  sp := ann_scan_span(src, pos)
  if sp.n == 0 { return "" }
  scalar_name_narrow(src, sp.s, sp.n)
}

## ─── The NAMED-PARAMETER annotation lookup, shared by every backend ────────
##
## "Walk the parameter list, match on the DECLARED name, ask one predicate of the declared type."
## Three questions, three backends, twelve identical copies. The predicate is the only part that
## differed, so the walk is shared and the question stays a one-line call — the same treatment as
## `ann_scan_span`.
##
## The walk deliberately does NOT stop at the first match, and the result is STICKY-true: if any
## parameter with this name has the queried type, the answer is yes. That is the behaviour all twelve
## copies had, and it is preserved verbatim rather than "improved" into a first-match lookup, because
## a first-match lookup would answer differently for a shadowed name.

## Is the parameter named `[ns, ns+nl)` declared with a SIGNED integer type?
pub param_ann_signed := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  mut p := params_head
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { if scalar_name_is_signed(src, pm.ts, pm.tl) { r = true } }
    p = pm.next
  }
  r
}

## Is the parameter named `[ns, ns+nl)` declared with an UNSIGNED integer type?
pub param_ann_unsigned := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  mut p := params_head
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { if scalar_name_is_unsigned(src, pm.ts, pm.tl) { r = true } }
    p = pm.next
  }
  r
}

## Is the parameter named `[ns, ns+nl)` declared with a FLOAT type?
pub named_param_is_float := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  mut p := params_head
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { if scalar_name_is_float(src, pm.ts, pm.tl) { r = true } }
    p = pm.next
  }
  r
}

## Does the function named `[cs, cs+cl)` RETURN a float? Scans the decl vector by name (the backends
## resolve a callee by name, not by index — `lower`'s same-named helper takes an index instead, which
## is why this one is spelled differently). Sticky-true, like the three above.
pub callee_ret_is_float := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut r := false
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    if d.is_fn and d.name_len != 0 { if streq(src, d.name_start, d.name_len, cs, cl) { if scalar_name_is_float(src, d.ret_ts, d.ret_tl) { r = true } } }
    i += 1
  }
  r
}

## ─── The TYPE-CLASSIFICATION tables, shared by every backend ────────────────
##
## Seven questions about what KIND of thing a type name denotes, each answered identically by all
## three backends and each a pure language decision — the comptime `TypeInfo` kind codes, the
## numeric-kind codes, "is this an aggregate", "is this a plain struct", "is this a scalar". 21
## copies become 7. The kind CODES are a wire format shared with the x86_64 lower and with
## `comptime`, so a copy that drifts by one integer is a silently wrong `TypeInfo` answer, not a
## build failure — which is exactly why they must not be copies.
##
## Named `ct_*` (matching this module's existing `ct_bind_push`/`ct_bound_value`) rather than
## `comptime_*`, and `ty_is_scalar` rather than `type_is_scalar`, because `lower`, `lower/ctfold` and
## `lower/mono` already declare those spellings. Two same-named declarations in sibling modules turn
## a BARE call somewhere else in the tree from "unique, therefore lenient" into something else; a
## distinct name removes that whole question.

## The comptime `TypeInfo.kind` code for the VARIANT NAME `[vs, vs+vl)` (`Struct` -> 2, `Enum` -> 3,
## `Array` -> 5, `Scalar` -> 0, `Brand` -> 6, `Tuple` -> 7), or -1 when the name is not one of them.
pub ct_kind_of_name := fn(src : ptr(u8), vs : usize, vl : usize) -> i64 {
  nm := str_at((src + vs), vl)
  if nm == "Struct" { return 2 }
  if nm == "Enum" { return 3 }
  if nm == "Array" { return 5 }
  if nm == "Scalar" { return 0 }
  if nm == "Brand" { return 6 }
  if nm == "Tuple" { return 7 }
  return 0 - 1
}

## The comptime NUMERIC-kind code for the variant name `[vs, vs+vl)` (`Bool` -> 1, `Char` -> 2,
## `Int` -> 3, `Float` -> 4), or -1.
pub ct_num_kind_of_name := fn(src : ptr(u8), vs : usize, vl : usize) -> i64 {
  nm := str_at((src + vs), vl)
  if nm == "Bool" { return 1 }
  if nm == "Char" { return 2 }
  if nm == "Int" { return 3 }
  if nm == "Float" { return 4 }
  return 0 - 1
}

## The comptime NUMERIC-kind code of the SCALAR type named `[its, its+itl)`: `bool` -> 1,
## `char` -> 2, a signed integer -> 3, a float -> 4, anything else (including the empty span) -> 0.
pub ct_scalar_num_kind := fn(its : usize, itl : usize, src : ptr(u8)) -> i64 {
  if itl == 0 { return 0 }
  nm := str_at((src + its), itl)
  if nm == "bool" { return 1 }
  if nm == "char" { return 2 }
  if nm == "i8" or nm == "i16" or nm == "i32" or nm == "i64" or nm == "isize" { return 3 }
  if nm == "f32" or nm == "f64" { return 4 }
  return 0
}

## The comptime `TypeInfo.kind` code of the TYPE TEXT `[its, its+itl)`: a leading `[` is an array
## (5), a leading `(` a tuple (7), a declared struct 2, a declared enum 3, anything else scalar (0);
## an empty span is -1 ("unknown"), never 0.
pub ct_type_kind := fn(its : usize, itl : usize, decls : ptr(rt::Vec), src : ptr(u8)) -> i64 {
  if itl == 0 { return 0 - 1 }
  if str_at((src + its), 1) == "[" { return 5 }
  if str_at((src + its), 1) == "(" { return 7 }
  bn := base_type_name(src, its, itl)
  if struct_decl_of(decls, src, bn.s, bn.n) >= 0 { return 2 }
  if enum_decl_of(decls, src, bn.s, bn.n) >= 0 { return 3 }
  return 0
}

## Is the type text `[ts, ts+tl)` an AGGREGATE — an array, a tuple, `str`, or a declared struct/enum?
pub std_ty_aggregate := fn(ts : usize, tl : usize, decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  if tl == 0 { return false }
  if str_at((src + ts), 1) == "[" or str_at((src + ts), 1) == "(" or str_at((src + ts), tl) == "str" { return true }
  bn := base_type_name(src, ts, tl)
  struct_decl_of(decls, src, bn.s, bn.n) >= 0 or enum_decl_of(decls, src, bn.s, bn.n) >= 0
}

## Is `[s, s+n)` a struct declared with NO type parameters (a "plain" struct — not a generic one)?
pub struct_plain := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  unchecked bitcast(usize, d.params_head) == 0
}

## The bounded native-ABI shape admitted by #169: a plain standard-byte struct with exactly two direct
## `u8` fields. Wider, nested, generic, packed, and otherwise unsupported byte layouts stay outside this
## predicate so their existing fail-loud boundary remains intact on every native backend.
pub std_struct_is_native_u8_pair := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  if not struct_plain(decls, src, s, n) { return false }
  if not layout_kind_is_byte(layout_kind(decls, src, s, n, a)) { return false }
  std_struct_is_u8_pair(decls, src, s, n)
}

## Is `[ts, ts+tl)` a SCALAR type — i.e. NOT a declared enum, NOT a declared struct, and not `str`?
## Note this is deliberately a NEGATIVE test: an unresolved name answers "scalar". An EMPTY span is
## not scalar, so a failed span recovery does not become a word-sized answer by accident.
pub ty_is_scalar := fn(ts : usize, tl : usize, decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  if tl == 0 { return false }
  if enum_decl_of(decls, src, ts, tl) >= 0 { return false }
  if struct_decl_of(decls, src, ts, tl) >= 0 { return false }
  if str_at((src + ts), tl) == "str" { return false }
  true
}

## ─── The GENERIC / TUPLE-PARAMETER probes and the Expr shape tests ──────────
##
## The last block of decisions the three backends held in triplicate with byte-identical bodies:
## how many type parameters a decl has and where they are, whether a generic call is one this
## increment supports, where a tuple parameter's type text opens, how many elements an array type
## declares, and six one-line probes of an `Expr`'s shape. None is target-dependent.
##
## `decl_*` / `ex_*` / `arg_list_count` / `param_tuple_open_at` rather than the backends' own
## spellings: `tparam_count`, `param_tuple_open`, `expr_is_int_lit`, `expr_is_zero` and `argc` are
## already declared in `lower`, `lower/mono`, `lower/ir`, `cli` or `lib/std/process`, and a second
## declaration of one of those names would change what a BARE call elsewhere in the tree resolves
## against. `ex_is_index`/`ex_is_field` also avoid `parser`'s `expr_is_index`/`expr_is_field`.

## How many of `d`'s parameters are `: type` (compile-time type parameters), anywhere in the list.
pub decl_tparam_count := fn(d : Decl, src : ptr(u8)) -> i64 {
  mut p := d.params_head
  mut n := 0
  while p != 0 { pm := deref(param_p(p)) ; if str_at((src + pm.ts), pm.tl) == "type" { n = n + 1 } ; p = pm.next }
  i64(n)
}

## The position of the FIRST `: type` parameter in `d`'s list, or -1 when there is none.
pub decl_tparam_pos := fn(d : Decl, src : ptr(u8)) -> i64 {
  mut p := d.params_head
  mut idx := 0
  mut r := 0 - 1
  while p != 0 { pm := deref(param_p(p)) ; if r < 0 and str_at((src + pm.ts), pm.tl) == "type" { r = i64(idx) } ; idx = idx + 1 ; p = pm.next }
  r
}

## How many `: type` parameters `d` declares BEFORE its first value parameter. Equal to
## `decl_tparam_count` exactly when every type parameter leads — which is the shape the generic call
## path supports; a `type` parameter after a value parameter makes the two disagree.
pub decl_leading_tparam_run := fn(d : Decl, src : ptr(u8)) -> i64 {
  mut p := d.params_head
  mut n := 0
  mut go := true
  while p != 0 and go {
    pm := deref(param_p(p))
    if str_at((src + pm.ts), pm.tl) == "type" { n = n + 1 } else { go = false }
    p = pm.next
  }
  i64(n)
}

## The decl index of the GENERIC function named `[cs, cs+cl)`, or -1. Last match wins, as in all
## three copies this replaces.
pub generic_gi := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) -> i64 {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut r := 0 - 1
  while i < cnt { d := deref(decl_get(decls, i)) ; if d.kind == 1 and d.is_generic and streq(src, d.name_start, d.name_len, cs, cl) { r = i64(i) } ; i = i + 1 }
  r
}

## Is a call to the generic named `[cs, cs+cl)` one the cross backends can lower? 1 to 3 type
## parameters, and with more than one they must ALL lead. This is a SHAPE FENCE, not a target
## capability: the three backends agreed on it exactly, so it is the language-level limit of the
## current generic-instance path and belongs in one place.
pub gen_call_ok := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) -> bool {
  gi := generic_gi(decls, src, cs, cl)
  if gi < 0 { return false }
  gd := deref(decl_get(decls, usize(gi)))
  cnt := decl_tparam_count(gd, src)
  lead := decl_leading_tparam_run(gd, src)
  if cnt < 1 or cnt > 3 { return false }
  if cnt == 1 { return true }
  cnt == lead
}

## The offset of the `(` that opens the TUPLE type of the parameter declared at `[ns, ns+nl)`, or -1
## when the annotation is absent, inferred, or not a tuple.
pub param_tuple_open_at := fn(src : ptr(u8), ns : usize, nl : usize) -> i64 {
  mut i := ns + nl
  mut go := true
  while go { if str_at((src + i), 1) == " " { i = i + 1 } else { go = false } }
  if str_at((src + i), 1) != ":" { return 0 - 1 }
  i = i + 1
  go = true
  while go { if str_at((src + i), 1) == " " { i = i + 1 } else { go = false } }
  if str_at((src + i), 1) == "(" { return i64(i) }
  0 - 1
}

## How many elements the tuple type of the parameter named `[ns, ns+nl)` has, PROVIDED every element
## is a scalar; 0 otherwise (no such parameter, not a tuple, or any struct/enum element).
pub param_tuple_allscalar_n := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec), a : rt::Arena) -> i64 {
  ## Match the param by name and scan from its DECLARATION span (`pm.ns/pm.nl`) — the usage-site
  ## `ns/nl` is followed by `.N`, not by the `: (…)` type text.
  mut p := params_head
  mut res := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      open := param_tuple_open_at(src, pm.ns, pm.nl)
      if open >= 0 {
        mut k := 0
        mut allscalar := true
        mut go := true
        while go {
          cs := typearg_at(src, usize(open), 0, usize(k))
          if cs.n == 0 { go = false } else {
            bn := base_type_name(src, cs.s, cs.n)
            if struct_decl_of(decls, src, bn.s, bn.n) >= 0 { allscalar = false }
            if enum_decl_of(decls, src, bn.s, bn.n) >= 0 { allscalar = false }
            k = k + 1
          }
        }
        if allscalar { res = k }
      }
    }
    p = pm.next
  }
  res
}

## The offset of the `;` that separates element type from length in the ARRAY type `[T; N]` spelled
## at `[ts, ts+tl)`, or 0 when there is none. Depth-aware, so the `;` inside a nested `[…]`/`(…)`
## does not win.
pub arrty_semi := fn(src : ptr(u8), ts : usize, tl : usize) -> usize {
  if tl < 4 { return 0 }
  if str_at((src + ts), 1) != "[" { return 0 }
  mut p := ts + 1
  lim := ts + tl
  mut depth := 0
  mut res := 0
  while p < lim and res == 0 {
    c := str_at((src + p), 1)
    if c == "(" or c == "[" { depth = depth + 1 }
    if c == ")" or c == "]" { if depth > 0 { depth = depth - 1 } }
    if depth == 0 and c == ";" { res = p } else { p = p + 1 }
  }
  res
}

## How many arguments a call's argument list holds.
pub arg_list_count := fn(args_head : ptr(mut Arg), a : rt::Arena) -> i64 {
  mut g := args_head
  mut n := 0
  while g != 0 { ga := deref(arg_p(g)) ; n = n + 1 ; g = ga.next }
  n
}

## The six `Expr` SHAPE probes. Each was three identical one-liners.
pub ex_is_index := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::Index(ib, ii) => { r = true } _ => {} }
  r
}
pub ex_index_base := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(e) { Expr::Index(ib, ii) => { r = ib } _ => {} }
  r
}
pub ex_index_idx := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(e) { Expr::Index(ib, ii) => { r = ii } _ => {} }
  r
}
pub ex_is_field := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::Field(fb, ffs, ffl) => { r = true } _ => {} }
  r
}
pub ex_is_num_lit := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::Num(v, s, n) => { r = true } _ => {} }
  r
}
pub ex_is_zero_lit := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::Num(v, s, n) => { if v == 0 { r = true } } _ => {} }
  r
}

## ─── The Expr ACCESSORS and the two byte tables ─────────────────────────────
##
## The last identical triplicates, and the ones a NAME-based duplicate scan misses entirely: these
## carry a different STEM in each backend (`a64_var_ns` / `rv_var_ns` / `expr_var_ns`,
## `a64_is_alit` / `rv_is_alit` / `is_array_lit`), so only a body comparison finds them. Each is a
## one-shape projection out of an `Expr` variant, or a fixed byte table, and none has a
## target-dependent answer. 51 definitions become 17.
##
## They are spelled `ex_*` for the projections so a reader can see at a glance that the argument is
## an `Expr` and the result is a field of ONE variant, with the documented default when the shape
## does not match (0 / a null pointer / false) rather than a trap: every caller tests the default.

pub ex_var_ns := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::Var(vs, vn) => { r = vs } _ => {} }
  r
}
pub ex_var_nl := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::Var(vs, vn) => { r = vn } _ => {} }
  r
}
pub ex_call_argh := fn(e : ptr(Expr)) -> ptr(mut Arg) { mut r := unchecked bitcast(ptr(mut Arg), 0) ; match deref(e) { Expr::Call(cs, cl, n, ah) => { r = ah } _ => {} } ; r }
pub ex_struct_lit_args := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::StructLit(ss, sn, nf, ah) => { r = ah } _ => {} }
  r
}
pub ex_enum_lit_args := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::EnumLit(es, en, vs, vn, nf, ah) => { r = ah } _ => {} }
  r
}
pub ex_is_array_lit := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) { Expr::ArrayLit(al_n, al_e) => { r = true } _ => {} }
  r
}
pub ex_array_lit_ehead := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::ArrayLit(al_n, al_e) => { r = al_e } _ => {} }
  r
}
pub ex_is_slice := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) { Expr::Slice(sb, slo, shi) => { r = true } _ => {} }
  r
}
pub ex_slice_base := fn(v : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(v) { Expr::Slice(sb, slo, shi) => { r = sb } _ => {} }
  r
}
pub ex_slice_lo := fn(v : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(v) { Expr::Slice(sb, slo, shi) => { r = slo } _ => {} }
  r
}
pub ex_slice_hi := fn(v : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(v) { Expr::Slice(sb, slo, shi) => { r = shi } _ => {} }
  r
}
## Is `v` a compile-time SCALAR literal (a number or a bool), and what is its value? The two are
## separate because a value of 0 is indistinguishable from "not a literal" in the second answer.
pub ex_value_is_scalar := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Expr::Num(x, s, n) => { r = true }
    Expr::BoolLit(x) => { r = true }
    _ => {}
  }
  r
}
pub ex_value_init := fn(v : ptr(Expr)) -> i64 {
  mut r := 0
  match deref(v) {
    Expr::Num(x, s, n) => { r = i64(x) }
    Expr::BoolLit(x) => { r = i64(x) }
    _ => {}
  }
  r
}
## The COMPARISON binary operators (`== < <= > >= !=`) — the set that yields `bool` rather than the
## operand type, which is why the signedness proof in `operand_unsigned` excludes them.
pub ex_is_cmp_op := fn(op : u8) -> bool { op == 20 or op == 24 or op == 25 or op == 26 or op == 27 or op == 28 }
## The synthetic "no tail expression" marker the backends encode as `Expr::Num(-1)` with an empty span.
pub ex_is_no_tail := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::Num(v, s, n) => { if v == 0 - 1 and n == 0 { r = true } } _ => {} }
  r
}
## The byte an escape sequence `\<c>` denotes; an unknown escape is the byte itself.
pub str_esc_byte := fn(c : u8) -> u8 {
  if c == 110 { return 10 }
  if c == 116 { return 9 }
  if c == 114 { return 13 }
  if c == 48 { return 0 }
  if c == 92 { return 92 }
  if c == 34 { return 34 }
  return c
}
## The value of a decimal digit, or -1 when the byte is not one.
pub dec_digit_val := fn(c : str) -> i64 {
  if c == "0" { return 0 }
  if c == "1" { return 1 }
  if c == "2" { return 2 }
  if c == "3" { return 3 }
  if c == "4" { return 4 }
  if c == "5" { return 5 }
  if c == "6" { return 6 }
  if c == "7" { return 7 }
  if c == "8" { return 8 }
  if c == "9" { return 9 }
  return 0 - 1
}
## The position of the destructuring binding named `[ns, ns+nl)` in `bind_head`, or -1.
pub bind_list_index := fn(bind_head : ptr(mut Bind), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> i64 {
  mut b := bind_head
  mut idx := 0
  while unchecked bitcast(usize, b) != 0 {
    if streq(src, bnd_ns(b), bnd_nl(b), ns, nl) { return i64(idx) }
    idx += 1
    b = bnd_next(b)
  }
  return -1
}

## ─── The `when` ARCH GUARD, shared shape with the target part left per-target ────────────────────
##
## Tooling §2.7's `when target.arch == Arch.<name>` guard. All three backends folded it with a
## BYTE-IDENTICAL 32-line recursive evaluator (`==`, `!=`, `not`, `and`, `or` over `Arch.<name>`),
## then rewrote every guarded-out decl into an inert one with a byte-identical 18-line pass. The ONLY
## thing that differed was the arch NAME each compared against — which is genuinely per-target.
##
## So the shape moves and the target part stays a parameter: `arch` is passed in, and each backend
## keeps its own `target_arch()`. A shared function that picked one target's arch for all three would
## be exactly the defect this extraction exists to prevent.
##
## NOTE, not fixed here: those three `target_arch()` answers are `"aarch64"`, `"riscv64"` and
## `"<none>"` — and each backend's `target.arch` FOLD still reports `x86_64` (
## `ARCH-IDENTITY`). Passing the name in makes that inconsistency a one-line difference between the
## three call sites instead of something buried in three copies of an evaluator.

## The `Arch.<name>` right-hand side of a guard comparison, or 0/0 when `e` is not one.
pub arch_rhs_span := fn(e : ptr(Expr), src : ptr(u8)) -> LSpan {
  mut r := LSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Field(b, fs, fl) => {
      if ex_var_nl(b) != 0 and str_at((src + ex_var_ns(b)), ex_var_nl(b)) == "Arch" { r = LSpan(s = fs, n = fl) }
    }
    _ => {}
  }
  r
}

## Fold a `when` condition against the arch name `arch`: 1 = the decl is KEPT, 0 = guarded out,
## -1 = not foldable (also "kept", by every caller's reading). Ops: 20 `==`, 28 `!=`, 42 `not`,
## 40 `and`, 41 `or`.
pub arch_guard_fold := fn(cond : ptr(Expr), src : ptr(u8), arch : str) -> i64 {
  mut r := 0 - 1
  match deref(cond) {
    Expr::Bin(op, l, rr) => {
      an := arch_rhs_span(rr, src)
      if an.n != 0 {
        eq := str_at((src + an.s), an.n) == arch
        if op == 20 { if eq { r = 1 } else { r = 0 } }
        if op == 28 { if eq { r = 0 } else { r = 1 } }
      }
      if an.n == 0 and op == 42 {
        lv := arch_guard_fold(l, src, arch)
        if lv == 1 { r = 0 }
        if lv == 0 { r = 1 }
      }
      if an.n == 0 and op == 40 {
        lv := arch_guard_fold(l, src, arch)
        rv := arch_guard_fold(rr, src, arch)
        if lv == 0 or rv == 0 { r = 0 }
        if lv == 1 and rv == 1 { r = 1 }
      }
      if an.n == 0 and op == 41 {
        lv := arch_guard_fold(l, src, arch)
        rv := arch_guard_fold(rr, src, arch)
        if lv == 1 or rv == 1 { r = 1 }
        if lv == 0 and rv == 0 { r = 0 }
      }
    }
    _ => {}
  }
  r
}

## Apply every decl's `when` guard for the arch `arch`: a decl that folds to 0 is REWRITTEN in place
## into an inert record (`name_len = 0`, no params, no body), which is how the backends make it
## invisible to name lookup without moving the vector.
pub apply_when_guards := fn(decls : ptr(rt::Vec), src : ptr(u8), arch : str) {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    dg := deref(decl_get(decls, i))
    if unchecked bitcast(usize, dg.when_cond) != 0 {
      if arch_guard_fold(dg.when_cond, src, arch) == 0 {
        gh := rt::vec_get(deref(decls), i)
        gdp : ptr(mut Decl) = unchecked bitcast(ptr(mut Decl), gh)
        deref(gdp) = Decl(name_start = dg.name_start, name_len = 0, value = dg.value,
          is_fn = false, kind = 0, arity = 0, is_generic = false, params_head = 0,
          body_stmts = 0, fields_head = 0, ret_ts = 0, ret_tl = 0,
          mod_start = dg.mod_start, mod_len = dg.mod_len, when_cond = 0, alias_ts = 0, alias_tl = 0)
      }
    }
    i += 1
  }
}

## Is `[ts, ts+tl)` a §7 VIEW type — `str`, or a bare slice `[T]` (NO `; N`, which would make it a
## fixed array)? Spec Types §7 is explicit: "a `[T]` or `str` binding, field, parameter, return value
## or array element holds the **two-word pair itself** (pointer + length — 16 bytes on a 64-bit
## target, aligned as a pointer), and `[T].size()` / `str.size()` report **that pair**". So a view has
## the same size WHEREVER it appears, and 8 (the pointer alone) is never one of its answers.
pub is_view_type := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  if tl == 0 { return false }
  if str_at((src + ts), tl) == "str" { return true }
  ## a bare slice `[T]`: an opening `[` with NO `;` inside the span (`[u8; 4]` is a fixed array).
  if str_at((src + ts), 1) != "[" { return false }
  mut i := ts + 1
  while i < ts + tl {
    if str_at((src + i), 1) == ";" { return false }
    i = i + 1
  }
  true
}

## The BYTE SIZE of a TYPE spelled `[ts, ts+tl)` — the scalar widths PLUS the §7 view pair (16).
##
## This is the query every `size(T)`-shaped fold wants; `scalar_byte_size` above is deliberately NOT
## it. That one is also the MACHINE OPERAND WIDTH the packed/standard byte emitters feed to
## `emit_packed_load`/`emit_packed_store`/`movb|movw|movl|movq`, where 1/2/4/8 are the only legal
## answers — 16 is not a mov width. Keeping the two apart is what lets the view pair be honest here
## without handing an impossible width to a byte emitter.
pub type_byte_size := fn(src : ptr(u8), ts : usize, tl : usize) -> usize {
  if is_view_type(src, ts, tl) { return 16 }
  scalar_byte_size(src, ts, tl)
}

## The natural ALIGNMENT of a TYPE spelled `[ts, ts+tl)` — the scalar widths, and POINTER alignment
## for a §7 view ("aligned as a pointer"): a `str`/`[T]` is 16 bytes but 8-ALIGNED, so its alignment
## is NOT its size and `scalar_byte_size` cannot answer both.
pub type_byte_align := fn(src : ptr(u8), ts : usize, tl : usize) -> usize {
  if is_view_type(src, ts, tl) { return 8 }
  scalar_byte_size(src, ts, tl)
}

## The bare-`Var` name span of an expression (`{0,0}` for any other node) — the element check of
## `array_type_lit`.
at_var_span := fn(e : ptr(Expr)) -> LSpan {
  match deref(e) {
    Expr::Var(s, n) => { LSpan(s = s, n = n) }
    _ => { LSpan(s = 0, n = 0) }
  }
}

## Is `[s, s+n)` a KNOWN TYPE name — a scalar/str width spelling (the built-in names) or a declared
## struct/enum/union type? Drives `array_type_lit`'s "this is a TYPE literal, not a value array" gate
## (a value array `[x, x]` of locals must NOT fold as `[T; N]`). CACHE-FREE on purpose: it scans the
## decls directly and NEVER calls the memoizing `struct_decl_of`/`enum_decl_of` — a CHECK-side call
## (sema-on-build) would populate those name caches BEFORE `emit_program`'s when-guard neutering, and
## the emit's later lookup would read the STALE pre-drop index → a silent wrong layout (found via
## when_guard_struct: a when-guarded duplicate `Cfg` folded `Cfg.size()` to 0 instead of 16).
pub type_name_known := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return false }
  t := str_at((src + s), n)
  if t == "u8" or t == "i8" or t == "u16" or t == "i16" or t == "u32" or t == "i32"
      or t == "u64" or t == "i64" or t == "usize" or t == "isize"
      or t == "f32" or t == "f64" or t == "bool" or t == "char" or t == "str" { return true }
  cnt := rt::vec_len(deref(decls))
  nm := name_tail(src, s, n)
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    ## kind 2 = struct, kind 3 = enum OR union (a union is a kind-3 decl too).
    if (d.kind == 2 or d.kind == 3) and streq(src, d.name_start, d.name_len, s, n) { return true }
    ## Follow one ordinary alias hop to a direct aggregate declaration. The bounded follow is
    ## intentional: alias chains are outside this slice and must not be guessed here.
    if d.kind == 0 and streq(src, d.name_start, d.name_len, s, n) {
      mut ats := 0
      mut atl := 0
      if d.ret_tl != 0 { ats = d.ret_ts; atl = d.ret_tl }
      else if d.alias_tl != 0 {
        abh := base_type_name(src, d.alias_ts, d.alias_tl)
        ats = abh.s; atl = abh.n
      }
      if atl != 0 {
        at := name_tail(src, ats, atl)
        mut j := 0
        while j < cnt {
          td := deref(decl_get(decls, j))
          if (td.kind == 2 or td.kind == 3) and streq(src, td.name_start, td.name_len, at.s, at.n) { return true }
          j += 1
        }
      }
    }
    i += 1
  }
  false
}

## The ARRAY-TYPE literal shape of an expression: an `ArrayLit` whose elements are ALL the same bare
## Var naming a KNOWN TYPE — the `[T; N]` fill form and the `[T, T, …, T]` comma form — or an EMPTY
## `[]` / `[T; 0]` literal. Returns the element count (>= 0) and, for count >= 1, fills `es`/`en` with
## the element TYPE-NAME span (left untouched for the empty form, whose size is 0 regardless); -1 = NOT
## an array-type literal (a value array with non-type or mixed elements). Drives the comptime
## `size([T; N])` fold (Types §6.4) in both `lower` and `sema`. SCALAR return + in-out spans — no
## aggregate return (the bootstrap seed mis-lowers a multi-word struct return in this hot path).
pub array_type_lit := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), in out es : usize, in out en : usize) -> i64 {
  mut r : i64 = 0 - 1
  match deref(e) {
    Expr::ArrayLit(nel, ah) => {
      if nel == 0 {
        r = 0
      } else {
        first := deref(arg_p(ah))
        ev := at_var_span(first.e)
        if ev.n != 0 and type_name_known(decls, src, ev.s, ev.n) {
          mut cnt : i64 = 0
          mut same := true
          mut g := ah
          while unchecked bitcast(usize, g) != 0 {
            ga := deref(arg_p(g))
            gv := at_var_span(ga.e)
            if gv.n != ev.n or not streq(src, gv.s, gv.n, ev.s, ev.n) { same = false }
            cnt += 1
            g = ga.next
          }
          if same { r = cnt; es = ev.s; en = ev.n }
        }
      }
    }
    _ => {}
  }
  r
}

## Is source byte `src[i]` ASCII whitespace? Small leaf for the backward attribute scan below.
_ws1 := fn(src : ptr(u8), i : usize) -> bool {
  w := str_at((src + i), 1)
  w == " " or w == "\n" or w == "\t" or w == "\r"
}
## Is source byte `src[i]` an ASCII letter (an ident char for the attribute keyword)?
_alpha1 := fn(src : ptr(u8), i : usize) -> bool {
  c := bytes(str_at((src + i), 1))[0]
  (c >= 97 and c <= 122) or (c >= 65 and c <= 90)
}

## Is source byte `src[i]` a character the integer lexer keeps inside a literal token?
_lit_char := fn(src : ptr(u8), i : usize) -> bool {
  c := bytes(str_at((src + i), 1))[0]
  (c >= 48 and c <= 57) or _alpha1(src, i) or c == 95
}

## §8 field-attribute CHAIN walker — the shared backward scan for the per-field layout levers
## `@offset(N)` / `@align(N)` / `@endian(big|little)` (spec Types §8). From the field NAME at source
## index `ns`, walk BACKWARD over the field's PREFIX CHAIN of adjacent `@ident(arg)` attributes and
## return the ARGUMENT span `[open+1, close-1]` of the one named `want`, or `{0,0}` if `want` is not
## in the chain. Each link is `@ ident ( paren-free-arg )`; the walk SKIPS a non-`want` attribute and
## continues, so a field carrying BOTH `@endian(big)` AND `@offset(N)` (in EITHER order) reports both —
## the former single-adjacent scanners found only the attribute IMMEDIATELY before the name and missed
## the other. Stops (→ `{0,0}`) at the first token that is not an `@ident(arg)` link (a `,`/`{`/`}`
## separator, or a preceding aggregate field's `)` whose ident is not one of ours / lacks the `@`), so
## it reads THIS field's own prefix only (the parser restricts field attrs to offset/align/endian, all
## paren-free-arg, so the inner scan-back-to-`(` is exact). AST-neutral — the marker text is in `src`.
_field_attr_arg := fn(src : ptr(u8), ns : usize, want : str) -> LSpan {
  if ns == 0 { return LSpan(s = 0, n = 0) }
  mut p := ns - 1
  mut go := true
  mut rs := 0
  mut rn := 0
  while go {
    while p > 0 and _ws1(src, p) { p = p - 1 }
    ## a chain link closes with ')'; anything else ends the chain (no more attributes)
    if str_at((src + p), 1) != ")" { go = false }
    else {
      close := p
      while p > 0 and str_at((src + p), 1) != "(" { p = p - 1 }
      if str_at((src + p), 1) != "(" { go = false }
      else {
        open := p
        if open == 0 { go = false }
        else {
          mut e := open - 1
          while e > 0 and _ws1(src, e) { e = e - 1 }
          if _alpha1(src, e) == false { go = false }
          else {
            mut b := e
            while b > 0 and _alpha1(src, b) { b = b - 1 }
            mut istart := b
            if _alpha1(src, b) == false { istart = b + 1 }
            ilen := (e - istart) + 1
            ## the `@` sigil must immediately precede the ident, else this is not an attribute link
            if istart == 0 or str_at((src + (istart - 1)), 1) != "@" { go = false }
            else if str_at((src + istart), ilen) == want {
              rs = open + 1
              rn = (close - open) - 1
              go = false
            }
            ## a non-`want` attribute — skip it and continue at the char before its `@` (index istart-2)
            else if istart < 2 { go = false }
            else { p = istart - 2 }
          }
        }
      }
    }
  }
  LSpan(s = rs, n = rn)
}

## DECLARATION-PREFIX attribute chain — the sibling of `_field_attr_arg` for the OTHER position a
## layout attribute may be written in. Declarations §2.3: "a declaration MAY carry … `@`-attributes …
## always in prefix position (the attribute precedes what it modifies)", and Grammar §3.2 spells it
## `declaration ::= { modifier } binding` with `modifier ::= "pub" | "mut" | "comptime" | attribute`.
## So `@packed Pk := struct {…}` is the same declaration as `Pk := @packed struct {…}` and must get
## the same layout — before this the prefix spelling was ACCEPTED and the declared layout thrown away
## without a word (a `@packed` struct silently laid out as 24 bytes instead of 7).
##
## From the DECL NAME at source index `ns`, walk BACKWARD over bare modifiers (`pub`, `mut`, or
## `comptime`) and then over the chain of adjacent `@ident` / `@ident(args)` links, and report the one
## named `want`:
##   `s` = the ARGUMENT start (`(`+1) — or the attribute name's own start when it is bare, so `s`
##         is NEVER 0 for a hit and `s == 0` is exactly "not in the chain";
##   `n` = the argument length (0 for a bare attribute like `@packed`).
## The chain walk means a STACKED prefix (`@packed` then `@align(8)`) reports both, mirroring the
## field-level walker. It stops at the first token that is not an `@ident[(…)]` link, so a preceding
## declaration's tail (`}`, `)`, a bare ident) ends it and it never reads past this declaration's own
## prefix. AST-neutral, like every scan in this file: the parser consumes the marker and leaves the
## text in `src`.
_decl_prefix_attr := fn(src : ptr(u8), ns : usize, want : str) -> LSpan {
  if ns == 0 { return LSpan(s = 0, n = 0) }
  mut p := ns - 1
  while p > 0 and _ws1(src, p) { p = p - 1 }
  ## Any bare declaration modifier may sit between the attribute chain and the name. The grammar
  ## makes modifier order free (`{ modifier } binding`), so stopping at `mut`/`comptime` would make
  ## a legal `@packed mut P := struct { … }` silently lose its layout exactly like the old prefix
  ## bug. Require a token boundary before each keyword so an identifier such as `computime` is not
  ## mistaken for a modifier by this source scan.
  mut mods := true
  while mods {
    mods = false
    while p > 0 and _ws1(src, p) { p = p - 1 }
    if p >= 2 and str_at((src + (p - 2)), 3) == "pub" and (p < 3 or not _alpha1(src, p - 3)) {
      p = p - 3
      mods = true
    } else if p >= 2 and str_at((src + (p - 2)), 3) == "mut" and (p < 3 or not _alpha1(src, p - 3)) {
      p = p - 3
      mods = true
    } else if p >= 7 and str_at((src + (p - 7)), 8) == "comptime" and (p < 8 or not _alpha1(src, p - 8)) {
      p = p - 8
      mods = true
    }
  }
  mut go := true
  mut rs := 0
  mut rn := 0
  while go {
    while p > 0 and _ws1(src, p) { p = p - 1 }
    mut e := p
    mut astart := 0
    mut alen := 0
    ## an optional argument list `( … )` — walk back to its `(`
    if str_at((src + e), 1) == ")" {
      close := e
      while e > 0 and str_at((src + e), 1) != "(" { e = e - 1 }
      if str_at((src + e), 1) != "(" { return LSpan(s = 0, n = 0) }
      if e == 0 { return LSpan(s = 0, n = 0) }
      astart = e + 1
      alen = (close - e) - 1
      e = e - 1
      while e > 0 and _ws1(src, e) { e = e - 1 }
    }
    if _alpha1(src, e) == false { go = false }
    else {
      mut b := e
      while b > 0 and _alpha1(src, b) { b = b - 1 }
      mut istart := b
      if _alpha1(src, b) == false { istart = b + 1 }
      ilen := (e - istart) + 1
      ## the `@` sigil must immediately precede the ident, else this is not an attribute link
      if istart == 0 { go = false }
      else if str_at((src + (istart - 1)), 1) != "@" { go = false }
      else if str_at((src + istart), ilen) == want {
        if alen == 0 { rs = istart } else { rs = astart }
        rn = alen
        go = false
      }
      ## a non-`want` attribute — skip it and continue at the char before its `@`
      else if istart < 2 { go = false }
      else { p = istart - 2 }
    }
  }
  LSpan(s = rs, n = rn)
}

## Trim an attribute ARGUMENT span down to its first whitespace-free token — `@repr( u8 )` -> `u8`.
## The forward `:=`-position scans build their span that way already; the backward chain walker
## returns the raw `( … )` interior, so this brings the two spellings to the same answer.
_attr_arg_token := fn(src : ptr(u8), sp : LSpan) -> LSpan {
  if sp.n == 0 { return LSpan(s = 0, n = 0) }
  mut p := sp.s
  end := sp.s + sp.n
  while p < end and _ws1(src, p) { p = p + 1 }
  ts := p
  while p < end and _ws1(src, p) == false { p = p + 1 }
  if p == ts { return LSpan(s = 0, n = 0) }
  LSpan(s = ts, n = p - ts)
}

## Parse the DECIMAL argument of a `@offset(N)`/`@align(N)` link found by `_field_attr_arg` — the arg
## span `[s, n)`. Returns N (≥0) or -1 for absent / non-digit content. Shared by both numeric levers.
_attr_decimal := fn(src : ptr(u8), sp : LSpan) -> i64 {
  if sp.n == 0 { return -1 }
  mut val := 0
  mut k := sp.s
  mut end := sp.s + sp.n
  while k < end {
    c := bytes(str_at((src + k), 1))[0]
    if c < 48 or c > 57 { return -1 }
    val = val * 10 + usize(c - 48)
    k = k + 1
  }
  i64(val)
}

## §8 `@offset(N)` — the explicit-byte-offset lever (spec Types §8; MMIO / register maps). The field
## whose NAME starts at source index `ns` carries an explicit offset iff its prefix chain includes
## `@offset(N)` (N decimal); found via `_field_attr_arg` so it is seen EVEN behind another attribute
## (`@endian(big) @offset(0) v`). Returns N (≥0) or -1 for "no explicit offset". AST-neutral (the parser
## consumed+discarded the marker, the text stays in `src`).
pub field_offset_attr := fn(src : ptr(u8), ns : usize) -> i64 {
  _attr_decimal(src, _field_attr_arg(src, ns, "offset"))
}

## §8 `@align(N)` — the raise-alignment lever (spec Types §8: raise a field's alignment ABOVE natural).
## Found via `_field_attr_arg`, so it is seen even behind another attribute in the chain. Returns N (≥1)
## or -1 for "no explicit alignment". Placement rounds the running byte cursor UP to a multiple of N
## before the field (`packed_field_byte_offset`/`emit_packed_assign`); the struct size rounds up to the
## max field alignment (`packed_struct_align`).
pub field_align_attr := fn(src : ptr(u8), ns : usize) -> i64 {
  _attr_decimal(src, _field_attr_arg(src, ns, "align"))
}

## §8 `@endian(big)` / `@endian(little)` — the per-field endianness lever (spec Types §8; wire formats).
## Found via `_field_attr_arg`, so it is seen even behind another attribute in the chain (`@offset(0)
## @endian(big) v` — the case the former single-adjacent scan missed). The argument is an `Endian` IDENT
## (`big`/`little`), not digits. Returns 1 (big — byte-reversed store/load), 0 (little — native, no swap),
## or -1 for "no explicit endianness" (also native).
pub field_endian_attr := fn(src : ptr(u8), ns : usize) -> i64 {
  sp := _field_attr_arg(src, ns, "endian")
  if sp.n == 0 { return -1 }
  arg := str_at((src + sp.s), sp.n)
  if arg == "big" { return 1 }
  if arg == "little" { return 0 }
  -1
}

## The endianness of field `[fs, fs+fl)` within `@packed` struct `[s, s+n)`: 1 = big (byte-reversed),
## 0/-1 = little/native. Walks the struct's `FieldDecl` list to find the field's declaration-site name
## span, then reads its `@endian(...)` marker via `field_endian_attr` — the READ side (`p.f`) only has the
## USE-site field name, so this resolves the decl-site `fd.ns` the scanner needs (mirrors the walk in
## `packed_field_byte_offset`). -1 if the field/struct is unknown.
pub packed_field_endian := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return -1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut res := -1
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, fs, fl) { res = field_endian_attr(src, fd.ns) }
    f = fd.next
  }
  res
}

## Round `x` UP to the next multiple of `n` (`n ≤ 1` is a no-op). The §8 alignment primitive shared by
## the packed byte-layout: an `@align(N)` field rounds the running cursor to a multiple of N; the packed
## struct size rounds up to the struct alignment.
pub round_up_to := fn(x : usize, n : usize) -> usize {
  if n <= 1 { return x }
  r := x % n
  if r == 0 { return x }
  x + (n - r)
}

## §8 STRUCT-LEVEL `@align(N) struct { … }` — the struct's OWN alignment lever (spec Types §8: "raise
## alignment above the natural alignment"; §6.1: "the struct's size is rounded up to its alignment").
## SOURCE-SCANS the struct decl's `:= @align(<N>) struct` VALUE-position prefix (the parser consumes+
## discards it, leaving the text in `src`) — exactly the `enum_repr_ty`/`is_packed` discipline, so no
## `Decl` field grows and the fixpoint holds. Returns N (≥1) or -1 when the struct carries no struct-level
## `@align` (so the whole no-`@align` corpus keeps size == words*8 / alignment 8 BYTE-IDENTICALLY →
## fixpoint-neutral). DISTINCT from the FIELD-level `@align` (`field_align_attr`, a backward scan from a
## field name): this scans FORWARD from the DECL name over `:= @align(` like `is_packed` scans for
## `@packed`. A `@packed struct` (prefix `@packed`, not `@align`) does not match → the two are separate.
pub struct_align_attr := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return -1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  ## the DECLARATION-PREFIX spelling `@align(16) S := struct {…}` — same declaration, same lever
  ## (Declarations §2.3); it used to be consumed and dropped, leaving the natural alignment.
  pfa := _attr_arg_token(src, _decl_prefix_attr(src, d.name_start, "align"))
  if pfa.n != 0 { return _attr_decimal(src, pfa) }
  mut p := d.name_start + d.name_len
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return -1 }
  p = p + 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 6) != "@align" { return -1 }
  p = p + 6
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 1) != "(" { return -1 }
  p = p + 1
  while str_at((src + p), 1) == " " { p = p + 1 }
  mut val := 0
  mut any := false
  mut go := true
  while go {
    c := bytes(str_at((src + p), 1))[0]
    if c >= 48 and c <= 57 { val = val * 10 + usize(c - 48); any = true; p = p + 1 }
    else { go = false }
  }
  if any == false { return -1 }
  if val == 0 { return -1 }
  i64(val)
}

## The alignment of `@packed` struct `[s, s+n)` — the MAX of its fields' `@align(N)` (spec §8: the
## struct's alignment is the max of its fields' alignments), floored at 1 (a plain packed struct is
## alignment 1, so a struct with no `@align` field keeps size == `packed_struct_bytes` byte-identically).
pub packed_struct_align := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> usize {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut mx := 1
  while f != 0 {
    fd := deref(fld_p(f))
    ea := field_align_attr(src, fd.ns)
    if ea >= 1 and usize(ea) > mx { mx = usize(ea) }
    f = fd.next
  }
  mx
}

## §8 the packed BYTE size of a struct field of declared type `[ts,tl)` (parser `wsize`). A SCALAR is
## `scalar_byte_size`; a `str` is 16 (a 2-word {ptr,len}); a nested STRUCT is its full byte size (a
## nested `@packed` struct → `packed_struct_bytes`, else the word-model `struct_words*8`); an ENUM is
## `(1 + enum_inst_words)*8`; an ARRAY / tuple field (`wsize > 1`) is `wsize*8` (a word-model element
## blob). An AGGREGATE field keeps its natural 8-byte alignment inside the packed struct (the store reuses
## the word-model emitters via a byte→slot translation, `emit_packed_assign`), so a packed struct that
## would place one at an UNALIGNED byte offset fails LOUD there rather than emit an unaligned multi-word
## copy (deferred). A SCALAR field returns exactly `scalar_byte_size` → the pre-existing scalar-only packed
## layout is BYTE-IDENTICAL (fixpoint-neutral). Mutually recursive with `packed_struct_bytes` for a nested
## packed struct field (terminates: type defs are a finite DAG; self-reference is only through `ptr`, a
## scalar 1-word field).
pub field_byte_size := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, wsize : usize, a : rt::Arena) -> usize {
  ## TYP-10 slice A: a computed-length `[T; <expr>]` field (the `wsize == 0` sentinel) has no
  ## byte size on the packed path — folding it needs the INSTANCE reference, which this
  ## signature does not carry; fail LOUD rather than lay out 0 bytes (a wrong-layout miscompile).
  if wsize == 0 { panic("selfhost: a computed `[T; <expr>]` array length (comptime value parameter) is not supported in a @packed struct in this slice") }
  ## An explicit byte array is a byte blob in a packed struct, including the N == 1 case where the
  ## parser's wsize is indistinguishable from a scalar without inspecting the declared type span.
  es := arr_field_elem_span(src, ts, tl)
  if es.n != 0 and layout_byte_type_eek(src, es.s, es.n) != 0 { return wsize }
  if wsize == 1 {
    if str_at((src + ts), tl) == "str" { return 16 }
    if struct_decl_of(decls, src, ts, tl) >= 0 {
      if is_packed(decls, src, ts, tl) { return packed_struct_bytes(decls, src, ts, tl, a) }
      return struct_words(decls, src, ts, tl, a) * 8
    }
    if enum_decl_of(decls, src, ts, tl) >= 0 {
      ## Packed structs use the same union overlap width as the word-layout path. The union's
      ## member bytes are still emitted by the word-model aggregate store at an 8-byte boundary.
      if is_union_decl(decls, src, ts, tl) { return union_words(decls, src, ts, tl, a) * 8 }
      return (1 + enum_inst_words(decls, src, ts, tl, a)) * 8
    }
    return scalar_byte_size(src, ts, tl)
  }
  wsize * 8
}

## Is field type `[ts,tl)` (parser `wsize`) a multi-word AGGREGATE (str / struct / enum / array / tuple)
## inside a packed struct — stored via the word-model emitters at an 8-aligned offset, not a scalar sized
## load/store? Drives `emit_packed_assign`'s dispatch + its 8-alignment enforcement. A scalar (incl. a
## `bitsN`/brand name unknown to the decl tables) is false → the scalar byte path, byte-identical.
pub is_packed_aggregate := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, wsize : usize) -> bool {
  if wsize > 1 { return true }
  if str_at((src + ts), tl) == "str" { return true }
  if struct_decl_of(decls, src, ts, tl) >= 0 { return true }
  if enum_decl_of(decls, src, ts, tl) >= 0 { return true }
  false
}

## The BYTE offset of field `[fs, fs+fl)` within `@packed` struct `[s, s+n)`. Fields pack with no
## padding (alignment 1) at a RUNNING byte cursor; a field carrying `@offset(N)` (spec §8) sits at N
## instead and the cursor CONTINUES after it (overlap is allowed, union-like / unchecked-flavored).
## -1 if the field/struct is unknown. The packed dual of `field_word_offset`. An AGGREGATE field advances
## the cursor by its FULL byte size (`field_byte_size` — a `str` is 16, a nested struct its bytes, …), so
## a scalar field placed AFTER it reads the right byte (the former `scalar_byte_size` assumed 8, which
## truncated a str/struct field and mis-placed everything after it).
pub packed_field_byte_offset := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return -1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut off := 0
  mut res := -1
  while f != 0 {
    fd := deref(fld_p(f))
    eo := field_offset_attr(src, fd.ns)
    ea := field_align_attr(src, fd.ns)            ## §8 @align(N) on this field, or -1
    mut cur := off
    ## `@align(N)` raises the cursor to a multiple of N; an explicit `@offset(N)` (absolute) overrides.
    if ea >= 1 { cur = round_up_to(cur, usize(ea)) }
    if eo >= 0 { cur = usize(eo) }
    if streq(src, fd.ns, fd.nl, fs, fl) { res = i64(cur) }
    off = cur + field_byte_size(decls, src, fd.ts, fd.tl, fd.wsize, a)
    f = fd.next
  }
  res
}

## The total BYTE size of `@packed` struct `[s, s+n)` — the highest field END (offset + byte size)
## across all fields (spec §8: no trailing pad; an `@offset(N)` field extends the size to cover N + its
## width). For an offset-free packed struct this equals the sum of the field byte sizes. Drives
## `T.size()` for a packed type; the packed dual of `struct_words`*8. An AGGREGATE field ends at its FULL
## byte size (`field_byte_size`).
pub packed_struct_bytes := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut off := 0
  mut maxend := 0
  while f != 0 {
    fd := deref(fld_p(f))
    eo := field_offset_attr(src, fd.ns)
    ea := field_align_attr(src, fd.ns)            ## §8 @align(N) on this field, or -1
    mut cur := off
    if ea >= 1 { cur = round_up_to(cur, usize(ea)) }
    if eo >= 0 { cur = usize(eo) }
    endb := cur + field_byte_size(decls, src, fd.ts, fd.tl, fd.wsize, a)
    if endb > maxend { maxend = endb }
    off = endb
    f = fd.next
  }
  ## §8: the struct size rounds up to the struct's alignment (max field alignment). A plain packed
  ## struct is alignment 1 → no rounding → byte-identical to the pre-`@align` behavior.
  round_up_to(maxend, packed_struct_align(decls, src, s, n))
}

## Find the kind-3 (enum) `Decl` whose TYPE name matches `[s, s+n)` (by tail name, so a
## qualified `mod::E` resolves to enum `E`); returns its index in the decl vector, or -1 if none.
## Used to resolve an enum local's layout (variant list).
## Candidates are ordered by `type_decl_ranked` (Modules §3), the SAME rule `struct_decl_of` uses —
## an enum resolver that disagreed with the struct resolver about which module a name means would be
## a second, independent lottery (a raw `union` parses to a kind-3 decl too, so this covers it).
pub enum_decl_of := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> i64 {
  h := _name_hash(src, s, n)
  cnt := rt::vec_len(deref(decls))
  layout_cache_use(decls, cnt)
  if _edc_n[h] == n and _edc_src[h] == src and _edc_ctx[h] == TRM_SET
     and _edc_ml[h] == TRM_L and streq(src, _edc_ms[h], _edc_ml[h], TRM_S, TRM_L)
     and streq(src, _edc_s[h], _edc_n[h], s, n) { return _edc_i[h] }
  nm := name_tail(src, s, n)
  mut res := type_decl_ranked(decls, src, s, n, 3, "enum or union")
  mut alias_ts := 0
  mut alias_tl := 0
  mut a_best := 0 - 1
  th := _fnv_name(src, nm.s, nm.n)
  mut jc := lni_lo(decls, cnt, th)
  jce := lni_hi(decls, cnt, th)
  while jc < jce {
    i := lni_at(decls, cnt, jc)
    jc = jc + 1
    if lni_skip(decls, cnt, i, th) == false {
      d := deref(decl_get(decls, i))
      if d.kind == 0 and streq(src, d.name_start, d.name_len, nm.s, nm.n) {
        ar := type_mod_rank(src, d.mod_start, d.mod_len)
        if ar >= a_best {
          if d.ret_tl != 0 { a_best = ar; alias_ts = d.ret_ts; alias_tl = d.ret_tl }
          else if d.alias_tl != 0 {
            abh := base_type_name(src, d.alias_ts, d.alias_tl)
            a_best = ar; alias_ts = abh.s; alias_tl = abh.n
          }
        }
      }
    }
  }
  ## Follow exactly one type-alias hop. The resolved declaration is still the nominal target;
  ## generic callers recover the full RHS through alias_rhs below.
  if res < 0 and alias_tl != 0 { res = type_decl_ranked(decls, src, alias_ts, alias_tl, 3, "enum or union") }
  _edc_s[h] = s; _edc_n[h] = n; _edc_src[h] = src; _edc_i[h] = res
  _edc_ms[h] = TRM_S; _edc_ml[h] = TRM_L; _edc_ctx[h] = TRM_SET
  res
}

## Module-exact enum lookup for a qualified generic TYPE ARGUMENT. This is intentionally separate
## from the legacy tail-only `enum_decl_of`: changing every qualified annotation in the self-host
## tree is a broader namespace migration. The generic substitution path calls this helper only for
## the concrete argument span recovered by `typearg_at`, so `Result(usize, codec::Error)` keeps the
## declaration identity and layout of codec::Error even when another module declares `Error`.
pub qualified_enum_decl_of := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> i64 {
  qh := type_path_head(src, s, n)
  if qh.n == 0 { return enum_decl_of(decls, src, s, n) }
  nm := name_tail(src, s, n)
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 3 and streq(src, d.name_start, d.name_len, nm.s, nm.n)
       and type_module_eq(src, d.mod_start, d.mod_len, qh.s, qh.n) { return i64(i) }
    i += 1
  }
  ## Preserve the language's existing one-level renamed-module form (`ser::SerError`). Direct module
  ## identity above has priority; only an otherwise-unresolved short head is expanded once.
  ah := qualified_module_alias(decls, src, qh.s, qh.n)
  if ah.n != 0 {
    i = 0
    while i < cnt {
      d := deref(decl_get(decls, i))
      if d.kind == 3 and streq(src, d.name_start, d.name_len, nm.s, nm.n)
         and type_module_eq(src, d.mod_start, d.mod_len, ah.s, ah.n) { return i64(i) }
      i += 1
    }
  }
  -1
}

## Check-side counterpart of the resolver above; cache-free so sema cannot seed an emit-time lookup
## cache before when-guard filtering. Struct/union declarations are admitted as known qualified type
## values too; this slice changes enum payload layout only, while unsupported consumers stay fail-loud.
pub qualified_type_name_known := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  qh := type_path_head(src, s, n)
  if qh.n == 0 { return type_name_known(decls, src, s, n) }
  nm := name_tail(src, s, n)
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if (d.kind == 2 or d.kind == 3) and streq(src, d.name_start, d.name_len, nm.s, nm.n)
       and type_module_eq(src, d.mod_start, d.mod_len, qh.s, qh.n) { return true }
    i += 1
  }
  ah := qualified_module_alias(decls, src, qh.s, qh.n)
  if ah.n != 0 {
    i = 0
    while i < cnt {
      d := deref(decl_get(decls, i))
      if (d.kind == 2 or d.kind == 3) and streq(src, d.name_start, d.name_len, nm.s, nm.n)
         and type_module_eq(src, d.mod_start, d.mod_len, ah.s, ah.n) { return true }
      i += 1
    }
  }
  false
}

## RAW UNION discrimination (spec Types §6.3). A `union { m(T), … }` parses into the SAME kind-3
## variant-shaped decl as an `enum` (parser: no new AST kind), so `enum_decl_of` resolves BOTH. This
## SOURCE-SCANS the decl's own `:= union` prefix to tell a union from an enum — AST-neutral, exactly the
## `is_packed`/`enum_repr_ty` discipline (the parser recorded no flag; the keyword text stays in `src`,
## so the lower recovers it here → no `Decl` field grows and the fixpoint holds). Scans from the resolved
## DECL name so a USE anywhere (`u.m`, `size(U)`, a slot's stored type span) classifies correctly. FALSE
## for every enum/struct/unresolved type → the whole existing corpus is byte-identical (fixpoint-neutral).
pub is_union_decl := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  di := enum_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut p := d.name_start + d.name_len
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return false }
  p = p + 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  ## skip an optional value-position prefix attribute (`@owning`/`@packed`) — not v1 for a union, but
  ## harmless to tolerate; the `union` keyword must follow. src/+lib declare none → dormant.
  if str_at((src + p), 6) != "union " and str_at((src + p), 6) != "union{" and str_at((src + p), 6) != "union\n" and str_at((src + p), 6) != "union\t" { return false }
  true
}

## A raw union member's PAYLOAD TYPE span — its variant's single payload type (`m(T)` → `T`). A union
## member's type IS its variant's single payload type (§6.3; multi-payload is additive). `{0,0}` if the
## type is not a union or `m` is not a member. Reused by `field_word_offset`/`field_type_span` so a read
## `u.m` types + sizes as `T`. (A nullary/payloadless member → `{0,0}` → treated as unknown; §6.3's core
## is single-payload members.)
pub union_member_ty := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize) -> LSpan {
  di := enum_decl_of(decls, src, s, n)
  if di < 0 { return LSpan(s = 0, n = 0) }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut rs := 0
  mut rn := 0
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, fs, fl) { rs = fd.ts; rn = fd.tl }
    f = fd.next
  }
  LSpan(s = rs, n = rn)
}

## The word SIZE of a raw union (spec Types §6.3): the MAX member payload word count (members overlap at
## offset 0, so size = the widest member, with NO discriminant word — contrast an enum's `1 + max_arity`).
## `enum_max_arity` already computes the max payload words over the variants (scalar/str/struct/enum
## payloads sized truly); a union drops the `+1`. Floored at 1 (a union always occupies ≥ one word).
pub union_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  mx := enum_max_arity(decls, src, s, n, a)
  if mx < 1 { return 1 }
  mx
}

## §8 `@repr(T)` — the enum-tag representation lever (spec Types §8). An enum declared
## `Name := @repr(T) enum {…}` pins its discriminant (tag) to the integer type `T` (`uN`/`iN`/`bitsN`),
## overriding the §6.2 word-sized default. This SOURCE-SCANS the enum decl's own `:= @repr(<T>) enum`
## prefix and returns T's span — AST-neutral, exactly the `is_packed` discipline (the parser consumes+
## discards the marker; the lower recovers it here, so no `Decl` field grows and the fixpoint holds).
## `{0,0}` when the enum carries no `@repr` (so the whole no-`@repr` corpus keeps the word-sized tag
## BYTE-IDENTICALLY → fixpoint-neutral). Scans from the resolved DECL name so a use anywhere resolves it.
pub enum_repr_ty := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> LSpan {
  di := enum_decl_of(decls, src, s, n)
  if di < 0 { return LSpan(s = 0, n = 0) }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  ## the DECLARATION-PREFIX spelling `@repr(u8) E := enum {…}` — same declaration, same tag type
  ## (Declarations §2.3); it used to be consumed and dropped, so the tag silently stayed word-wide
  ## and the §8 representability check never ran on it.
  pfr := _attr_arg_token(src, _decl_prefix_attr(src, d.name_start, "repr"))
  if pfr.n != 0 { return pfr }
  mut p := d.name_start + d.name_len
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return LSpan(s = 0, n = 0) }
  p = p + 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 5) != "@repr" { return LSpan(s = 0, n = 0) }
  p = p + 5
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 1) != "(" { return LSpan(s = 0, n = 0) }
  p = p + 1
  while str_at((src + p), 1) == " " { p = p + 1 }
  ts := p
  while str_at((src + p), 1) != ")" and str_at((src + p), 1) != " " and str_at((src + p), 1) != "\n" and p < (ts + 64) { p = p + 1 }
  LSpan(s = ts, n = p - ts)
}

## Classify a `@repr(T)` tag type `[ts, ts+tl)` for the match-dispatch LOAD width (spec §8: "the tag
## is emitted as T's width … each discriminant encoded in T"). Returns a small code:
##   0 = word (`u64`/`i64`/`usize`/`bits64`/unknown) — load `movq` (the default, byte-identical);
##   1 = i8 (movsbl)   2 = u8 (movzbl)   3 = i16 (movswl)  4 = u16 (movzwl)
##   5 = i32 (movslq)  6 = u32 (movl)
## Widths < a word sign/zero-extend on load per T's signedness; ≥64-bit types are word-sized (code 0).
pub repr_tag_code := fn(src : ptr(u8), ts : usize, tl : usize) -> usize {
  if tl == 0 { return 0 }
  t := str_at((src + ts), tl)
  if t == "i8" { return 1 }
  if t == "u8" { return 2 }
  if t == "i16" { return 3 }
  if t == "u16" { return 4 }
  if t == "i32" { return 5 }
  if t == "u32" { return 6 }
  0
}

## Is `[ts, ts+tl)` a valid `@repr(T)` tag type — an integer type `uN`/`iN`/`usize` or a `bitsN`
## brand (spec §8: "T is an integer type")? A non-integer T (`bool`/`char`/`f32`/`f64`/`str`/a
## struct/enum) is rejected by the build-time representability check. Accepts the native + narrow
## widths the model knows; a `bitsN` brand name (`bits8`…`bits64`) also passes.
pub repr_ty_is_integer := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  if tl == 0 { return false }
  t := str_at((src + ts), tl)
  if t == "u8" or t == "i8" or t == "u16" or t == "i16" or t == "u32" or t == "i32" { return true }
  if t == "u64" or t == "i64" or t == "usize" { return true }
  if t == "bits8" or t == "bits16" or t == "bits32" or t == "bits64" { return true }
  false
}

## The number of DISTINCT NON-NEGATIVE discriminant values a `@repr(T)` tag type `[ts, ts+tl)` can
## represent (spec §8: T "MUST represent every discriminant value" 0..variant_count-1). u8 → 256,
## i8 → 128 (0..127), u16 → 65536, i16 → 32768, u32 → the 32-bit cap. Returns 0 for a ≥32-bit-signed /
## ≥64-bit type (`i32`/`u64`/`i64`/`usize`/`bitsN`), meaning "practically unbounded — do not bound-check"
## (no test-sized enum reaches billions of variants). Drives the narrow-T representability rejection.
pub repr_ty_capacity := fn(src : ptr(u8), ts : usize, tl : usize) -> usize {
  if tl == 0 { return 0 }
  t := str_at((src + ts), tl)
  if t == "u8" { return 256 }
  if t == "i8" { return 128 }
  if t == "u16" { return 65536 }
  if t == "i16" { return 32768 }
  if t == "u32" { return 4294967296 }
  0
}

## The max payload WORD count over an enum's variants — the number of payload words in the enum's
## fixed layout (size = (1 + max_words) * 8 bytes). A variant with N>1 payload fields is sized N
## (each field word-sized — the parser only captures the FIRST payload type span, so a multi-field
## variant is assumed scalar-fielded, as `Bin(u8, usize, usize)` = 3). A SINGLE-payload variant is
## sized by its payload's TRUE word count: a STRUCT payload → `struct_words` (`Ok(Ty)`, Ty=3 words),
## an ENUM payload → `1 + enum_max_arity` recursively (`Err(CheckErr)`, CheckErr=3). This fixes the
## former field-COUNT sizing that truncated a multi-word aggregate payload to one word (crashing
## `check`/sema when the truncated `Ty` was passed by-reference). Recursion terminates: a
## self-referential enum recurses only through `ptr(E)` (a 1-word pointer, not a struct/enum decl
## match), never inline. Changes the layout of `src/`'s own aggregate-payload enums, so the frozen
## seed is rebuilt in lockstep (bumped `seed/VERSION`).
pub enum_max_arity := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  di := enum_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut mx := 0
  while f != 0 {
    fd := deref(fld_p(f))
    mut pw := fd.arity
    if fd.arity == 1 {
      if struct_decl_of(decls, src, fd.ts, fd.tl) >= 0 {
        pw = struct_words(decls, src, fd.ts, fd.tl, a)
      } else if enum_decl_of(decls, src, fd.ts, fd.tl) >= 0 {
        pw = 1 + enum_max_arity(decls, src, fd.ts, fd.tl, a)
      } else if str_at((src + fd.ts), fd.tl) == "str" {
        pw = 2                                   ## a `str` payload is a 2-word {ptr, len}
      }
    }
    if pw > mx { mx = pw }
    f = fd.next
  }
  mx
}

## The same payload-width fold when the caller has ALREADY resolved the enum declaration identity.
## This avoids throwing a qualified generic argument back through the legacy tail-only name lookup:
## `codec::Error` must keep `codec`'s declaration even when another module also declares `Error`.
## Payload members retain the established resolver here; widening nested/alias forms is explicitly
## outside this slice.
enum_max_arity_of_decl := fn(decls : ptr(rt::Vec), src : ptr(u8), di : usize, a : rt::Arena) -> usize {
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), di)))
  mut f := d.fields_head
  mut mx := 0
  while f != 0 {
    fd := deref(fld_p(f))
    mut pw := fd.arity
    if fd.arity == 1 {
      if struct_decl_of(decls, src, fd.ts, fd.tl) >= 0 {
        pw = struct_words(decls, src, fd.ts, fd.tl, a)
      } else if enum_decl_of(decls, src, fd.ts, fd.tl) >= 0 {
        pw = 1 + enum_max_arity(decls, src, fd.ts, fd.tl, a)
      } else if str_at((src + fd.ts), fd.tl) == "str" {
        pw = 2
      }
    }
    if pw > mx { mx = pw }
    f = fd.next
  }
  mx
}

## The word size of a bare TYPE-name span `[s, s+n)`: a struct → its `struct_words`, an enum →
## `1 + enum_max_arity` (disc + widest payload), else a scalar/pointer/unresolved → 1. The leaf
## sizer used by `enum_inst_words` when a generic variant's payload is a concrete type-arg.
pub agg_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  ## A generic struct INSTANCE (`Slice(u8)`, `Pair(T)`, …) carries type arguments in the
  ## source span, while decl lookup is by its base head. Looking up the full span directly
  ## misclassified the instance as a scalar, so `Option(Slice(u8))` reserved one payload
  ## word even though the view is `{ptr,len}`. Keep the full span for `struct_words`, which
  ## substitutes the instance arguments after the base lookup.
  sbn := base_type_name(src, s, n)
  if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { return struct_words(decls, src, s, n, a) }
  ## STRIP any `(…)` type-args for the enum-decl lookup (a nested type-arg `Option(u64)` streqs the
  ## WHOLE name and would miss the `Option` decl), but size the INSTANCE (`enum_inst_words`, full
  ## span) so a substituted aggregate payload is counted — not `enum_max_arity` (the param-generic
  ## sizer). Mutual recursion agg_words↔enum_inst_words terminates for non-recursive types.
  ebn := base_type_name(src, s, n)
  if qualified_enum_decl_of(decls, src, ebn.s, ebn.n) >= 0 { return 1 + enum_inst_words(decls, src, s, n, a) }
  if str_at((src + s), n) == "str" { return 2 }   ## a `str` value is a 2-word {ptr, len}
  1
}

## The `idx`-th (0-based) TOP-LEVEL type-argument span of a generic-type reference whose HEAD name
## span is `[hs, hs+hn)` — read by RE-PARSING the source text immediately after the head. A generic
## instance `Result(Ty, CheckErr)` keeps the head span `Result` (6 bytes); the `(Ty, CheckErr)` list
## is intact in `src` right after it (the parser did not fold the args into the span). So this reads
## `src[hs+hn]`: if `(`, it scans comma-separated args at paren depth 0 (a nested `G(A,B)` arg stays
## one top-level arg), trims surrounding spaces, and returns the `idx`-th. `{0,0}` if absent. This
## lets the lower recover an instantiation's type-args without new AST fields (Decl/SlotEntry growth).
pub typearg_at := fn(src : ptr(u8), hs : usize, hn : usize, idx : usize) -> LSpan {
  ## `hs` may be a REBASED handle for a comptime-synthesized generic head, so every `src + off` here is
  ## POINTER arithmetic — route through `rt::addr` (I11 / CG-8), not a checked integer `+`.
  mut p := (hs + hn)
  if str_at((src + p), 1) != "(" { return LSpan(s = 0, n = 0) }
  p += 1
  mut depth := 0
  mut ai := 0
  mut start := p
  ## accumulate the result span as SCALARS (`rs`/`rn`), NOT a `mut res : LSpan` reassigned inside
  ## the loop — a struct-local reassigned in a loop is a known lean-lower miscompile (the P1a `Token`
  ## landmine: the write silently doesn't take), which made a ≥2-char type-arg span read back wrong
  ## and mis-bound the match payload as a scalar (the check/sema crash). Build the `LSpan` at return.
  mut rs := 0
  mut rn := 0
  mut go := true
  while go {
    c := str_at((src + p), 1)
    mut boundary := false
    mut ended := false
    if c == "(" { depth = depth + 1 }
    else if c == ")" {
      if depth == 0 { boundary = true; ended = true } else { depth = depth - 1 }
    } else if c == "," and depth == 0 { boundary = true }
    if boundary {
      if ai == idx {
        ## trim leading + trailing spaces of [start, p)
        mut ts := start
        while ts < p and str_at((src + ts), 1) == " " { ts = ts + 1 }
        mut te := p
        while te > ts and str_at((src + te - 1), 1) == " " { te = te - 1 }
        rs = ts
        rn = te - ts
        go = false
      }
      ai += 1
      start = p + 1
    }
    if ended { go = false }
    p += 1
  }
  LSpan(s = rs, n = rn)
}

## Find the position (0-based) of the type-PARAMETER named `[ts, ts+tl)` in the generic decl at
## index `di`'s `params_head` (a desugared `Result := fn(T,E)->type{…}` keeps its params `[T,E]`),
## so a variant payload of type `T` maps to instantiation type-arg 0. -1 if the name is not a param
## (a concrete payload type). Walks the `Param` list comparing each param's NAME span.
pub param_pos := fn(decls : ptr(rt::Vec), di : usize, src : ptr(u8), ts : usize, tl : usize, a : rt::Arena) -> i64 {
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), di)))
  mut p := d.params_head
  mut i := 0
  mut res := -1
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ts, tl) { res = i }
    i += 1
    p = pm.next
  }
  res
}

## The BASE type-NAME span of a possibly-parenthesized type reference `[s, s+n)` — the head up to
## the FIRST top-level `(` (a generic-instance `Pair(u64)` → `Pair`; `Box(Pair(u64))` → `Box`; a
## bare `u64` unchanged). The stripped head STILL points at the same source offset, so `typearg_at`
## on it re-reads the `(…)` type-args that follow in `src` (the proven bare-span recovery). Used so
## a generic-instance type-arg resolves to its base decl WITHOUT a global strip in `struct_decl_of`.
pub base_type_name := fn(src : ptr(u8), s : usize, n : usize) -> LSpan {
  mut i := 0
  while i < n {
    if str_at(((src + s) + i), 1) == "(" { return LSpan(s = s, n = i) }
    i += 1
  }
  LSpan(s = s, n = n)
}

## §8 `@niche` — is the type span `[s, s+n)` a NICHE-FOLDED `Option(ptr(T))`? The spec-flagship folded
## enum (Types §6.2/§8, Memory §4.2): `Option(T)` adds one `None` variant and folds it into the
## payload's null niche IFF `T` provides one; a `ptr(T)` provides the all-zero (null) pattern
## (MEM-8, non-null pointer). So `Option(ptr(T))` is exactly POINTER-WIDTH — ONE word, no
## discriminant: `None` = 0, `Some(p)` = the pointer `p`, and a `match` tests `word == 0` for `None`.
## True ONLY when the base name is `Option` AND its first type-argument's base name is `ptr`. EVERY
## other enum — including `Option(u64)` / `Option(str)` — stays the ordinary `[disc, payload]` layout,
## byte-identical. Keyed off a FULL span carrying the parenthesized arg (`Option(ptr(u64))`, e.g. a
## local's source-recovered declared type via `local_type_span`, or a `size(...)` type expr). A BARE
## `Option` span (as an enum LITERAL `Option.Some(...)` carries — the base is followed by `.`, not
## `(`) has no top-level type-arg → `typearg_at` returns `{0,0}` → false, so a non-folded enum local's
## slot span (bare `Option`) is never mistaken for folded. This is ONE general layout rule (§6.2),
## `Option` unprivileged — the folding is read from the payload's declared niche, no compiler run.
pub is_niche_folded := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  bn := base_type_name(src, s, n)
  if bn.n == 0 { return false }
  if str_at((src + bn.s), bn.n) != "Option" { return false }
  ta := typearg_at(src, bn.s, bn.n, 0)
  if ta.n == 0 { return false }
  tab := base_type_name(src, ta.s, ta.n)
  if tab.n == 0 { return false }
  str_at((src + tab.s), tab.n) == "ptr"
}

## S2 boundary for the prelude bool niche. The constructive `@niche` producer is S6; until then a
## size fold over `Option(bool)` must reject rather than report the ordinary tag+payload word fallback.
pub is_bool_niche_pending := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  bn := base_type_name(src, s, n)
  if bn.n == 0 or str_at((src + bn.s), bn.n) != "Option" { return false }
  ta := typearg_at(src, bn.s, bn.n, 0)
  if ta.n == 0 { return false }
  tb := base_type_name(src, ta.s, ta.n)
  tb.n != 0 and str_at((src + tb.s), tb.n) == "bool"
}

## NESTED-GENERIC-STRUCT tier — the EFFECTIVE (substituted) type span of a field `[fdts, fdtl)` of a
## struct INSTANCE whose type reference is `[sns, snl)`. When the struct is a GENERIC decl and the
## field's declared type is one of its type-PARAMETERS (`v : T`), substitute the instance's matching
## type-argument (re-parsed from `src` after the base head via `typearg_at`, the same recovery the
## enum path uses). Returns the field's OWN declared type unchanged when: the struct is not generic,
## the field is not a param, there are no type-args in source (a bare-name reference — a declaration
## context, `max_agg_words_all`, etc.), OR — the GATE — the type-arg is a SCALAR. The scalar gate is
## what keeps single-level generic aggregate layout (`Box(u64)`, `Vec(u64)`, `Slice(u64)`)
## BYTE-IDENTICAL: a scalar type-arg sizes as one word exactly like the unsubstituted param `T`, so
## leaving it unsubstituted is a no-op for layout. Only an AGGREGATE type-arg (struct/enum/str) —
## which sizes to >1 words — changes the answer, and only there does the nested-generic layout need
## the substitution. The returned span is the type-arg's BASE name (points into `src` at the arg, so
## a further nested substitution reads ITS args), so downstream `struct_decl_of` resolves it directly.
pub subst_field_ty := fn(decls : ptr(rt::Vec), src : ptr(u8), sns : usize, snl : usize, fdts : usize, fdtl : usize, a : rt::Arena) -> LSpan {
  ## STRIP `(…)` type-args for the instance-decl LOOKUP so a parenthesized generic-struct span
  ## (`Slice(u8)`, reached recursively when sizing a generic-struct FIELD) resolves its decl and its
  ## generic-ness — the FULL span is kept below (`base_type_name` at the `typearg_at` read) to
  ## recover the instance's own type-args.
  sbn0 := base_type_name(src, sns, snl)
  di := struct_decl_of(decls, src, sbn0.s, sbn0.n)
  if di < 0 { return LSpan(s = fdts, n = fdtl) }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  if d.is_generic == false { return LSpan(s = fdts, n = fdtl) }
  pos := param_pos(decls, usize(di), src, fdts, fdtl, a)
  if pos < 0 { return LSpan(s = fdts, n = fdtl) }
  base := base_type_name(src, sns, snl)
  ta := typearg_at(src, base.s, base.n, usize(pos))
  if ta.n == 0 { return LSpan(s = fdts, n = fdtl) }
  bta := base_type_name(src, ta.s, ta.n)
  ## GATE (see doc): only an AGGREGATE type-arg changes layout; a scalar stays the un-substituted param.
  if struct_decl_of(decls, src, bta.s, bta.n) >= 0 { return LSpan(s = bta.s, n = bta.n) }
  if enum_decl_of(decls, src, bta.s, bta.n) >= 0 { return LSpan(s = bta.s, n = bta.n) }
  if str_at((src + bta.s), bta.n) == "str" { return LSpan(s = bta.s, n = bta.n) }
  LSpan(s = fdts, n = fdtl)
}

## COMPTIME-VALUE-GENERIC tier (TYP-10 slice A; Comptime §10 `comptime param`, §1 "an array
## length") — the array field `[T; <expr>]` of a generic type-FUNCTION (`uint := fn(comptime N :
## u64) -> type { struct { words : [u64; N/64] } }`) carries a length EXPRESSION referencing the
## comptime VALUE parameter, which the parser marks with `wsize == 0` (the computed-length
## sentinel; an int-literal length keeps its value, so every pre-existing field is unchanged).
## `ct_arr_len` folds that expression against the INSTANCE's comptime-value bindings: a parameter
## name maps (by `param_pos` over the desugared decl's `Param` list) to the instantiation's value
## argument, re-read from the source right after the instance head (`uint(192)` → `192`, the
## proven `typearg_at` recovery). Supported shape, kept tightly scoped: term (op term)* with
## left-to-right `+ - * / %`, a term being a decimal literal or a parameter name. Returns 0 when
## the field type span holds no `; <expr>` (not an array field). Fail-LOUD, never silently wrong:
## an unknown parameter name, a missing / non-literal value argument (`uint(n)` with a variable),
## a zero divisor, and a non-positive result (`uint(0)`) are compile-time panics.
##
## COMPTIME-VALUE BINDING for a generic-OPERATOR expansion (TYP-10 slice B; Comptime §10).
## While a routed generic operator's body expands at a call site (`a + b` over `uint(192)`),
## the operator's comptime VALUE parameter (`N` in
## `@inline + := fn(comptime N : u64, a : uint(N), b : uint(N)) -> uint(N)`) is BOUND to the
## operand instance's value argument (`192`), so layout reads of the operator's OWN source
## spans (`uint(N)` — a NON-literal value argument, which alone would be the slice-A
## "must be an integer literal" panic) fold against it: the param words of `a : uint(N)`,
## a body local `r : uint(N)`, the `-> uint(N)` return, all size as `uint(192)`. A small
## explicit STACK (a nested generic-operator expansion re-binds) pushed/popped around each
## expansion; depth 0 outside, so every pre-existing (slice-A) read is byte-identical.
mut _ctb_ns : [usize; 8] = [0; 8]
mut _ctb_nl : [usize; 8] = [0; 8]
mut _ctb_val : [usize; 8] = [0; 8]
mut _ctb_depth : usize = 0

pub ct_bind_push := fn(ns : usize, nl : usize, val : usize) {
  if _ctb_depth >= 8 { panic("selfhost: generic-operator comptime binding stack overflow (nesting deeper than 8)") }
  _ctb_ns[_ctb_depth] = ns
  _ctb_nl[_ctb_depth] = nl
  _ctb_val[_ctb_depth] = val
  _ctb_depth += 1
}
pub ct_bind_pop := fn() {
  if _ctb_depth > 0 { _ctb_depth -= 1 }
}
pub ct_bind_depth := fn() -> usize { _ctb_depth }
## The value the INNERMOST active binding gives the comptime parameter named `[ids, ids+idn)`,
## else -1 (no active binding, or a different parameter name).
pub ct_bound_value := fn(src : ptr(u8), ids : usize, idn : usize) -> i64 {
  if _ctb_depth == 0 { return -1 }
  bd := _ctb_depth - 1
  if streq(src, _ctb_ns[bd], _ctb_nl[bd], ids, idn) { return i64(_ctb_val[bd]) }
  -1
}

## Resolve ONE comptime-parameter name `[ids, ids+idn)` (a term of a computed array-length
## expression) to its VALUE under the instance `[base_s, base_n)`'s comptime-value argument (the
## instantiation's argument re-read from the source right after the head, via `typearg_at`).
## Returns -1 for a BARE-name reference (the declaration context — `max_agg_words_all` sizes every
## struct decl, including the generic one itself, whose head has no `(args)` after it in source;
## mirrors `subst_field_ty`'s bare-name fallthrough — the field then contributes 0 words). Fail-
## LOUD on an unknown parameter name / a non-literal argument (`uint(n)` with a variable).
## Factored out of `ct_arr_len` so the panics + the early return sit at SHALLOW depth — a
## control-flow exit nested inside the evaluator's loop is not a lowerable shape under the
## self-host lower (it hung the build).
pub ct_param_value := fn(decls : ptr(rt::Vec), src : ptr(u8), di : i64, base_s : usize, base_n : usize, ids : usize, idn : usize, a : rt::Arena) -> i64 {
  if di < 0 { panic("selfhost: a computed array length `[T; <expr>]` names a comptime parameter, but the enclosing type is not a resolved struct decl") }
  pos := param_pos(decls, usize(di), src, ids, idn, a)
  if pos < 0 { panic("selfhost: an array-length expression may only name a `comptime` parameter of the enclosing type-function (e.g. `[u64; N/64]` with `comptime N : u64`)") }
  ta := typearg_at(src, base_s, base_n, usize(pos))
  if ta.n == 0 { return -1 }              ## declaration context: no value argument to bind
  tb := bytes(str_at((src + ta.s), ta.n))
  mut k := 0
  mut v := 0
  mut badarg := false
  while k < ta.n {
    db := tb[k]
    if db >= 48 and db <= 57 { v = v * 10 + usize(db - 48) }
    if db < 48 or db > 57 { badarg = true }
    k += 1
  }
  if badarg {
    ## TYP-10 slice B: the value argument is not a literal — inside a GENERIC-OPERATOR expansion
    ## it may BE the bound comptime parameter itself (the operator's own `uint(N)` spans). Resolve
    ## it against the innermost active binding; anything else stays the slice-A loud reject.
    bv := ct_bound_value(src, ta.s, ta.n)
    if bv >= 0 { return bv }
    panic("selfhost: a comptime VALUE argument must be an integer literal (`uint(192)`, not `uint(n)`)")
  }
  i64(v)
}

pub ct_arr_len := fn(decls : ptr(rt::Vec), src : ptr(u8), sns : usize, snl : usize, fdts : usize, fdtl : usize, a : rt::Arena) -> usize {
  ## Read via `bytes(str)[i]` (a Slice(u8) byte view) — the same idiom as `parse_arr_len`.
  bs := bytes(str_at((src + fdts), fdtl))
  ## locate the `;` (byte 59) opening the length expression, and the `]` (byte 93) closing it
  mut i := 0
  mut sp := 0
  mut found := false
  while i < fdtl {
    if bs[i] == 59 { sp = i + 1; found = true }
    i += 1
  }
  if found == false { return 0 }
  mut e := fdtl
  mut j := sp
  mut escan := true
  while escan and j < fdtl {
    if bs[j] == 93 { e = j; escan = false } else { j += 1 }
  }
  ## TYP-10 slice C: canonicalize a TYPE-ALIAS instance span (`u128`) to the alias's full RHS span
  ## (`uint(128)`) BEFORE the base-head / value-argument reads — a bare use-site alias name carries
  ## no `(args)`, so `typearg_at` (inside `ct_param_value`) must point at the alias decl's RHS.
  inst := alias_rhs(decls, src, sns, snl)
  base := base_type_name(src, inst.s, inst.n)
  di := struct_decl_of(decls, src, base.s, base.n)
  mut p := sp
  mut acc := 0
  mut op : u8 = 43                        ## the pending operator ('+' folds the first term)
  mut any := false
  mut bare := false                       ## a declaration-context reference (field → 0 words)
  mut divided := false                    ## a `/`-fold occurred → the `uint(N)` = `[u64; N/64]` decomposition
  mut err := 0                            ## 1 malformed term, 2 non-positive, 3 zero divisor, 4 malformed operator, 5 inexact division
  mut scanning := true
  ## every dispatch below is an INDEPENDENT `if` (guard-then-act, no `else`), and every error /
  ## early exit is a FLAG folded after the loop — a control-flow exit nested inside the loop is
  ## not a lowerable shape under the self-host lower (see `ct_param_value`).
  while scanning {
    while p < e and bs[p] == 32 { p += 1 }
    if p >= e { scanning = false }
    if p < e {
      cb := bs[p]
      mut tval := 0
      mut isid := false
      if cb >= 48 and cb <= 57 {
        while p < e and bs[p] >= 48 and bs[p] <= 57 { tval = tval * 10 + usize(bs[p] - 48); p += 1 }
      }
      if (cb >= 65 and cb <= 90) or (cb >= 97 and cb <= 122) or cb == 95 { isid = true }
      if isid == false and (cb < 48 or cb > 57) { err = 1; scanning = false }
      if isid {
        ids := p
        mut adv := true
        while adv {
          if p >= e { adv = false }
          if p < e {
            ib := bs[p]
            mut idc := false
            if (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or (ib >= 48 and ib <= 57) or ib == 95 { idc = true }
            if idc { p += 1 }
            if idc == false { adv = false }
          }
        }
        idn := p - ids
        pv := ct_param_value(decls, src, di, base.s, base.n, fdts + ids, idn, a)
        if pv < 0 { bare = true; scanning = false }
        if pv >= 0 { tval = usize(pv) }
      }
      if err == 0 and bare == false {
        if op == 43 { acc = unchecked (acc + tval) }
        if op == 45 { if tval > acc { err = 2 } }
        if op == 45 and err == 0 { acc = acc - tval }
        if op == 42 { acc = unchecked (acc * tval) }
        if op == 47 { if tval == 0 { err = 3 } }
        ## TYP-10 ADMISSIBILITY (slice C): an INEXACT comptime division (`N/64` with N = 100) must
        ## fail LOUD — silently laying out trunc(N/64) words would mint a narrower type
        ## masquerading as N bits (a silent miscompile).
        if op == 47 and err == 0 { if acc % tval != 0 { err = 5 } }
        if op == 47 and err == 0 { acc = acc / tval; divided = true }
        if op == 37 { if tval == 0 { err = 3 } }
        if op == 37 and err == 0 { acc = acc % tval }
        if err != 0 { scanning = false }
        any = true
      }
      if err == 0 and bare == false {
        while p < e and bs[p] == 32 { p += 1 }
        if p >= e { scanning = false }
        if p < e {
          ob := bs[p]
          op = ob
          p += 1
          if ob != 43 and ob != 45 and ob != 42 and ob != 47 and ob != 37 { err = 4; scanning = false }
        }
      }
    }
  }
  if err == 1 { panic("selfhost: malformed comptime array-length expression in `[T; <expr>]` — a term is an integer literal or a comptime parameter name") }
  if err == 2 { panic("selfhost: a comptime array length must be POSITIVE") }
  if err == 3 { panic("selfhost: division by zero in a comptime array-length expression") }
  if err == 4 { panic("selfhost: malformed comptime array-length expression in `[T; <expr>]` — expected one of `+ - * / %` between terms") }
  if err == 5 { panic("selfhost: inexact division in a comptime array-length expression — `uint(N)` admits only a POSITIVE MULTIPLE OF 64 (`uint(100)` would truncate to 1 word, a narrower type masquerading as N bits)") }
  if bare { return 0 }
  ## TYP-10 ADMISSIBILITY: `uint(N)` decomposes to `[u64; N/64]`; `uint(0)` folds `0/64` to 0 — NOT a
  ## valid width (a POSITIVE multiple of 64 is required) — so a DIVISION that yields 0 must FAIL LOUD.
  ## A ZERO-length array `[T; 0]` (spec Types §6.5), by contrast, folds a bare literal `0` (no division)
  ## and is a spec-legal zero-sized type (size 0, 0 words). Gating the positivity reject on `divided`
  ## keeps `uint(0)` loud while admitting `[T; 0]`. NEUTRAL: no `src/`/`lib/` field folds to 0 either way.
  if any and acc == 0 and divided { panic("selfhost: a comptime array length must be POSITIVE (`uint(0)` or a zero-valued expression is not a valid fixed-array length)") }
  acc
}

## The EFFECTIVE word-size of a struct field with parser `wsize`: the `wsize` itself, or — when it
## is 0 (the computed-length sentinel above) — the `[T; <expr>]` length folded against the
## INSTANCE's comptime-value bindings. `sns`/`snl` is the instance type reference (its value
## arguments sit in the source right after the head). Drop-in at every `fd.wsize` layout read.
pub eff_field_wsize := fn(decls : ptr(rt::Vec), src : ptr(u8), sns : usize, snl : usize, fdts : usize, fdtl : usize, wsize : usize, a : rt::Arena) -> usize {
  if wsize != 0 { return wsize }
  ct_arr_len(decls, src, sns, snl, fdts, fdtl, a)
}

## The payload WORD count of an enum INSTANCE whose head span is `[s, s+n)` — the generic-aware
## dual of `enum_max_arity`. For a NON-generic enum it is exactly `enum_max_arity` (drop-in). For a
## GENERIC enum (`Result := fn(T,E)->type{enum{Ok(T),Err(E)}}`) it SUBSTITUTES the instance's
## type-args (re-parsed from the source after the head via `typearg_at`) for the variant payload
## params: a single payload of type `T` at param position `k` is sized as the k-th type-arg's words
## (`Ok(Ty)` → `struct_words(Ty)=3`), fixing the field-COUNT sizing that truncated it (the
## `check`/sema crash). A concrete (non-param) payload keeps its own `agg_words`. `{s,n}` is the
## HEAD only (`Result`), so `enum_decl_of` resolves normally; the args live in `src` after it.
pub enum_inst_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> usize {
  ## STRIP `(…)` type-args for the decl lookup so a nested type-arg `Option(u64)` resolves the
  ## `Option` decl. `typearg_at` consumes the HEAD span, so normalize a recursively returned full
  ## type-argument (`Result(u64, E)`) back to `ebn.n` before reading its own `(…)` list; otherwise
  ## the nested instance silently falls back to the generic parameter arity and loses payload words.
  ## A bare alias name carries no `(T, E)` suffix at the use site. Recover the recorded generic
  ## RHS before reading type arguments, so `R := Result(u64, E)` sizes like `Result(u64, E)`.
  ## The recovered span is then resolved QUALIFIED: an alias may name `mod::Result`, and matching by
  ## tail name alone would pick whichever same-named decl came first.
  ar := alias_rhs(decls, src, s, n)
  mut inst_s := s
  mut inst_n := n
  if ar.n != 0 { inst_s = ar.s; inst_n = ar.n }
  ebn := base_type_name(src, inst_s, inst_n)
  di := qualified_enum_decl_of(decls, src, ebn.s, ebn.n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  if d.is_generic == false { return enum_max_arity_of_decl(decls, src, usize(di), a) }
  mut f := d.fields_head
  mut mx := 0
  while f != 0 {
    fd := deref(fld_p(f))
    mut pw := fd.arity
    if fd.arity == 1 {
      pos := param_pos(decls, usize(di), src, fd.ts, fd.tl, a)
      if pos >= 0 {
        ta := typearg_at(src, ebn.s, ebn.n, usize(pos))
        if ta.n > 0 { pw = agg_words(decls, src, ta.s, ta.n, a) }
      } else {
        pw = agg_words(decls, src, fd.ts, fd.tl, a)
      }
    }
    if pw > mx { mx = pw }
    f = fd.next
  }
  mx
}

## The (substituted) TYPE-name span of the FIRST payload of variant `[vs, vn)` of the enum whose
## head span is `[es, en)`; `{0,0}` for a nullary variant / unknown. For a GENERIC enum a payload
## of a type-PARAM (`Ok(T)`) resolves to the instance's corresponding type-arg (`Ty`, via
## `typearg_at`). The match-binding uses this to decide a payload's kind: a struct/enum result →
## bind the payload BY-REFERENCE (an aggregate), a scalar → by value. (Only the first payload is
## captured by the parser, so multi-payload variants report their first — fine for the
## single-aggregate-payload case this targets; a multi-scalar variant like `Bin(u8,…)` is a scalar.)
pub variant_payload_type := fn(decls : ptr(rt::Vec), src : ptr(u8), es : usize, en : usize, vs : usize, vn : usize, a : rt::Arena) -> LSpan {
  ## STRIP `(…)` type-args for the decl lookup so a parenthesized instance span (`Option(u64)`, or the
  ## nested `Option(Option(u64))`) resolves its enum decl; keep the FULL span for `typearg_at`.
  ar := alias_rhs(decls, src, es, en)
  mut inst_s := es
  mut inst_n := en
  if ar.n != 0 { inst_s = ar.s; inst_n = ar.n }
  ebn := base_type_name(src, inst_s, inst_n)
  di := enum_decl_of(decls, src, ebn.s, ebn.n)
  if di < 0 { return LSpan(s = 0, n = 0) }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  ## SCALAR accumulators (not a `mut res : LSpan` reassigned in the loop — the lean-lower
  ## struct-local-in-loop miscompile; see `typearg_at`). Build the `LSpan` once at return.
  mut rs := 0
  mut rn := 0
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, vs, vn) and fd.arity >= 1 {
      rs = fd.ts
      rn = fd.tl
      if d.is_generic {
        pos := param_pos(decls, usize(di), src, fd.ts, fd.tl, a)
        if pos >= 0 {
          ta := typearg_at(src, ebn.s, ebn.n, usize(pos))
          if ta.n > 0 { rs = ta.s; rn = ta.n }
        }
      }
    }
    f = fd.next
  }
  LSpan(s = rs, n = rn)
}

## The payload type as seen by a SINGLE binding `p` (`match e { E::V(p) => … }` / `display`'s
## `T.(var)(p)`): for a 1-component variant, the component type (`variant_payload_type`); for a
## MULTI-component variant `V(T0, T1, …)`, the whole balanced `(T0, T1, …)` list as a TUPLE span
## (recovered from source right after the variant name). Binding `p` to the tuple span lets a
## multi-component payload render/route through the tuple machinery (a tuple type-arg). Generic
## multi-component variants are not substituted here (the common non-generic case is covered).
pub variant_payload_span := fn(decls : ptr(rt::Vec), src : ptr(u8), es : usize, en : usize, vs : usize, vn : usize, a : rt::Arena) -> LSpan {
  ## STRIP `(…)` type-args for the decl lookup (a parenthesized instance span resolves its enum decl).
  ebns := base_type_name(src, es, en)
  di := enum_decl_of(decls, src, ebns.s, ebns.n)
  if di < 0 { return LSpan(s = 0, n = 0) }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut rs := 0
  mut rn := 0
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, vs, vn) and fd.arity >= 2 {
      ## MULTI-component `V(T0, …, TN)` — the `(…)` list sits right after the variant name; capture
      ## the balanced-paren span as a TUPLE type. Scan to `(`, then forward at paren depth to the `)`.
      mut p := (fd.ns + fd.nl)
      while str_at((src + p), 1) != "(" { p = p + 1 }
      op := p
      mut depth := 0
      mut i := p
      mut cl := p
      mut go := true
      while go {
        c := str_at((src + i), 1)
        if c == "(" { depth = depth + 1 }
        else if c == ")" {
          depth = depth - 1
          if depth == 0 { cl = i; go = false }
        }
        i += 1
      }
      rs = op
      rn = cl - op + 1
    }
    f = fd.next
  }
  if rn != 0 { return LSpan(s = rs, n = rn) }
  ## 1-component (or unit): fall back to the single-type view (handles the generic substitution).
  variant_payload_type(decls, src, es, en, vs, vn, a)
}

## The max payload arity over **all** enum decls in the program. Sizes the enum-materialization
## scratch (`emit_fn`'s `tslot` region) so a by-ref / `deref(ptr)` enum `match` can copy a wide
## payload (disc + N payload words, e.g. `Bin(op, ptr, ptr)` = 3).
pub max_enum_arity_all := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> usize {
  cnt := rt::vec_len(deref(decls))
  mut mx := 0
  ## A WHOLE-PROGRAM pass asks about a declaration it already HAS, by that declaration's own name —
  ## so the naming module for the query is the DECLARATION's module, never whichever module happened
  ## to be published when the pass ran. Without this the query is answered from (say) `main`, where a
  ## name declared in two unrelated modules is nameable from neither: the §3 ranking would report a
  ## spurious ambiguity for a program that has none. Saved/restored so the caller's module survives.
  ss := TRM_S
  sl := TRM_L
  so := TRM_SET
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 3 {
      TRM_S = d.mod_start ; TRM_L = d.mod_len ; TRM_SET = true
      ar := enum_max_arity(decls, src, d.name_start, d.name_len, a)
      if ar > mx { mx = ar }
    }
  }
  TRM_S = ss ; TRM_L = sl ; TRM_SET = so
  mx
}

## The widest AGGREGATE word count over all decls — the max of every struct's `struct_words` and
## every enum's `1 + enum_max_arity` (the disc + widest payload). An upper bound on the words of
## any struct/enum CONSTRUCTOR argument, so `emit_fn` can reserve one agg-arg materialization block
## of this size (over-sizing is harmless frame padding). At least 1.
pub max_agg_words_all := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> usize {
  cnt := rt::vec_len(deref(decls))
  mut mx := 1
  ## same whole-program discipline as `max_enum_arity_all` above: each declaration is measured in ITS
  ## OWN module, so the §3 ranking resolves the name to the declaration the pass is standing on.
  ss := TRM_S
  sl := TRM_L
  so := TRM_SET
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 2 {
      TRM_S = d.mod_start ; TRM_L = d.mod_len ; TRM_SET = true
      w := struct_words(decls, src, d.name_start, d.name_len, a)
      if w > mx { mx = w }
    } else if d.kind == 3 {
      TRM_S = d.mod_start ; TRM_L = d.mod_len ; TRM_SET = true
      w := 1 + enum_max_arity(decls, src, d.name_start, d.name_len, a)
      if w > mx { mx = w }
    }
  }
  TRM_S = ss ; TRM_L = sl ; TRM_SET = so
  mx
}

## Recover an enum variant's discriminant PIN (spec Types §6.2: a variant MAY pin an explicit value with
## `= N`, N a comptime integer, after which following unassigned variants continue from `N + 1`).
## SOURCE-SCANS the raw text right after the variant NAME `[ns, ns+nl)` — skipping an optional payload
## `(…)` — for a `= N`, mirroring the `@repr`/`@offset` source-scan discipline: the parser CONSUMES the
## `= N` tokens (so no `FieldDecl` field grows), and the value is recovered here — AST-neutral. Returns
## the pinned NON-NEGATIVE integer (the complete Grammar §2.4 integer literal), or `-1` when the variant carries no pin.
## `src/`+`lib/` pin NOTHING → every variant returns `-1` → the running discriminant equals the
## positional index → BYTE-IDENTICAL → the TOOL-1 fixpoint holds.
variant_pin := fn(src : ptr(u8), ns : usize, nl : usize) -> i64 {
  mut p := ns + nl
  while _ws1(src, p) { p = p + 1 }
  ## skip a balanced payload `(…)` (`V(T, …) = N`) — bounded so malformed source cannot spin forever.
  if str_at((src + p), 1) == "(" {
    mut dpt := 0
    mut go := true
    mut guard := 0
    while go and guard < 65536 {
      c := str_at((src + p), 1)
      if c == "(" { dpt = dpt + 1 }
      else if c == ")" { dpt = dpt - 1 ; if dpt == 0 { go = false } }
      p = p + 1
      guard = guard + 1
    }
    while _ws1(src, p) { p = p + 1 }
  }
  if str_at((src + p), 1) != "=" { return -1 }
  if str_at((src + p + 1), 1) == "=" { return -1 }   ## `==` is not a pin (defensive; never in a variant)
  p = p + 1
  while _ws1(src, p) { p = p + 1 }
  ## The parser's located lit_val_at already rejects malformed pins. Re-run the SAME pure
  ## validator here before decoding so this source scan can never silently truncate or wrap.
  start := p
  while _lit_char(src, p) { p = p + 1 }
  sp := str_at((src + start), p - start)
  if int_lit_err(sp) != 0 { panic("selfhost: enum discriminant pin is not a valid integer literal") }
  i64(dec_val(sp))
}

## The effective discriminant of the variant at 0-based INDEX `target` in variant list `fields_head`
## (spec Types §6.2: first `0`, each subsequent previous `+1`, a `= N` pin overrides and the run
## continues from `N + 1`). Shared by `variant_index` and `enum_dup_disc`. An un-pinned list resolves to
## `0,1,2,…` == the positional index → byte-identical to the former positional behaviour.
eff_disc_at := fn(src : ptr(u8), fields_head : ptr(mut FieldDecl), target : usize) -> i64 {
  mut f := fields_head
  mut running := 0
  mut idx := 0
  mut res := -1
  while f != 0 {
    fd := deref(fld_p(f))
    pin := variant_pin(src, fd.ns, fd.nl)
    mut disc := running
    if pin >= 0 { disc = pin }
    if idx == target { res = disc }
    running = disc + 1
    idx = idx + 1
    f = fd.next
  }
  res
}

## The first DUPLICATED effective discriminant in enum `fields_head`, or `-1` when every variant resolves
## to a distinct value (spec Types §6.2: "Two variants resolving to the same value are ill-formed").
## All-pairs over the variants (enums are small); an un-pinned enum resolves to `0,1,2,…` (always
## distinct) → `-1` → no rejection → fixpoint-neutral.
pub enum_dup_disc := fn(src : ptr(u8), fields_head : ptr(mut FieldDecl)) -> i64 {
  mut fi := fields_head
  mut i := 0
  while fi != 0 {
    di := eff_disc_at(src, fields_head, i)
    mut j := 0
    while j < i {
      if eff_disc_at(src, fields_head, j) == di { return di }
      j = j + 1
    }
    fdi := deref(fld_p(fi))
    fi = fdi.next
    i = i + 1
  }
  -1
}

## Resolve a variant NAME span to its DISCRIMINANT value within enum `[s, s+n)` (spec Types §6.2: the
## pin `= N` else previous `+1`, first `0`); `-1` if not found. The enum's variants are its arena-linked
## `FieldDecl` list, in source order. For an un-pinned enum this is the declaration-order index — the
## former positional behaviour, byte-identical. Enum construction (tag store), `match` dispatch, and any
## enum→int read all flow through here, so the pinned value is honoured consistently by one fix.
pub variant_index := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, vs : usize, vl : usize, a : rt::Arena) -> i64 {
  ## STRIP `(…)` type-args so a parenthesized enum-instance span (`Option(u64)`) resolves the decl.
  ebn := base_type_name(src, s, n)
  if enum_ref_ambiguous(decls, src, ebn.s, ebn.n) {
    reject_type_ambiguous(src, ebn.s, ebn.n, "enum")
  }
  di := enum_decl_of(decls, src, ebn.s, ebn.n)
  if di < 0 { return -1 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut running := 0
  mut res := -1
  while f != 0 {
    fd := deref(fld_p(f))
    pin := variant_pin(src, fd.ns, fd.nl)
    mut disc := running
    if pin >= 0 { disc = pin }
    if streq(src, fd.ns, fd.nl, vs, vl) { res = disc }
    running = disc + 1
    f = fd.next
  }
  res
}
