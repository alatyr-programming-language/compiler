## selfhost::sema — a fallible TYPE-checker pass over the AST.
##
## The fourth promoted pass. It does two things in one AST walk: (1) **name resolution** —
## every identifier reference (`Var`) must resolve to a binding declared **earlier** in the
## program (`decls[0..i]`) or to a fn-local (param / prior body binding); and (2) **real
## type-checking** — it synthesizes a `Ty` for every expression and rejects ill-typed programs:
## arithmetic on a non-int, a
## comparison of mismatched operands, a call argument whose type ≠ the parameter's declared
## type, a struct field value whose type ≠ the field's declared type, a `Field` access on a
## non-struct, an `if`/`match` whose branches disagree, and a fn body whose returned type ≠ the
## declared return type. A well-typed program checks Ok unchanged; both error kinds thread out
## with `?` (the `selfhost_frontend` fallible shape).
##
## TYPE REPRESENTATION (`Ty`): a small tag + an optional name span. tag 0 = unknown/error
## (poison-tolerant — a mismatch only fires when BOTH operands are *known* and differ, so an
## unresolved name never cascades a spurious type error), 1 = int (u64/usize/i64/…), 2 = bool,
## 3 = struct (the struct name span), 4 = enum (the enum name span). A local (param or `:=`
## binding) records its `Ty` so a `Var` reference synthesizes it.
##
## The AST types are shared from `selfhost::ast` (sibling submodule) via local comptime
## aliases (Modules §4.1) — the checker walks the SAME `Expr`/`Decl`/`Stmt` the parser
## produced. DEFERRED (the toy grammar does not need them yet): enum-variant payload *type*
## checking (only the first payload type span is captured), generic type expressions (`Vec(T)`),
## and unifying a `Var` that resolves to a top-level value binding (treated as unknown).
vec := alloc::vec
(Arg, Arm, Bind, Decl, Expr, FieldDecl, Param, Stmt, local_type_span, local_is_uninit, local_is_mut, assign_is_reassign) := ast
(bnd_ns, bnd_nl, bnd_next) := ast
ecallee_is := ast::ecallee_is
fld_p := ast::fld_p
param_p := ast::param_p
arm_p := ast::arm_p
arg_p := ast::arg_p
stmt_p := ast::stmt_p
## Decl-layout primitives (shared with `lower`) for the generic when-GUARD located reject: sema folds a
## `size(T)`/is-KIND/field-COUNT/named-predicate guard against a concrete type-arg using the SAME functions
## `lower::guard_*` use, so `check` and `build` agree to the byte / kind / count (CT-4/CT-5). `lower_layout`
## does not depend on sema → no import cycle. (`struct_decl_of`/`base_type_name`/`brand_underlying` added
## for the is-KIND + field-COUNT fold — they classify the resolved type exactly as the lower's own fold.)
(struct_words, struct_decl_of, enum_decl_of, enum_inst_words, base_type_name, name_tail, brand_underlying, type_name_known, qualified_type_name_known, array_type_lit, typearg_at, tuple_typearg_span, layout_type_size_bytes, is_bool_niche_pending, is_view_type, layout_kind, layout_kind_is_byte, is_packed, std_struct_has_byte_layout, std_struct_has_aggregate_field, subst_field_ty, array_type_has_array_element) := lower_layout
## §8 `@repr(T)` tag-type primitives (shared with `lower::validate_repr`) for the LOCATED @repr reject:
## sema classifies an enum's `@repr(T)` tag exactly as the build's `validate_repr` does (same span
## extraction, same integer/capacity classification), so `check` and `build` agree byte-for-byte on
## which enum is rejected.
(enum_repr_ty, repr_ty_is_integer, repr_ty_capacity) := lower_layout
## Module visibility is source metadata consumed by more than the lowerer.  Keep the single
## `pub` reader shared with the build-side Modules §3 pass; the sema pass must not grow a second
## spelling table for `pub mut` / first-line declarations.
(decl_is_pub, param_is_comptime) := lower_attrs

## Internal semantic errors use one word: kind in the low two bits, source start in the rest.
## The lean lower cannot yet carry a nested `CheckErr` enum reliably as generic `Result`'s error
## payload. The public checker returns only a scalar verdict; diagnostics can decode this code.
pub CheckErr := usize
unbound_err := fn(s : usize, n : usize) -> CheckErr { 1 + s * 4 }
mismatch_err := fn(s : usize, n : usize) -> CheckErr { 2 + s * 4 }
## A LOCATED error of no specific kind (kind 0 → the driver renders "invalid at line N"): used for a
## structural rejection (a break/continue outside a loop, a missing result) that has a source
## location but no unbound/mismatch classification. The span `s` must be nonzero (else it reads as 0
## = accepted); `s * 4` keeps the kind bits clear.
located_err := fn(s : usize) -> CheckErr { s * 4 }
## A distinct diagnostic class without widening the bootstrap-sensitive low-two-bit CheckErr layout.
## The high marker is stripped by both public renderers before decoding the ordinary source offset.
## Source buffers are necessarily far smaller than 2^62 bytes, so the marker cannot collide with an
## existing encoded location. This keeps every existing kind/value byte-for-byte unchanged.
ambiguous_err := fn(s : usize) -> CheckErr { 4611686018427387904 + s * 4 }
## A distinct located diagnostic for a struct-construction-shaped expression whose head is neither a
## declared aggregate/type alias nor a declared generic type constructor. Keep it between ambiguous
## calls and scalar conversions so every older CheckErr range remains byte-identical.
UNKNOWN_TYPE_CONSTRUCTOR_DIAG_MARKER := 5188146770730811392
unknown_type_ctor_err := fn(s : usize) -> CheckErr { UNKNOWN_TYPE_CONSTRUCTOR_DIAG_MARKER + s * 4 }
## TOOL-17 / Tooling §2.7 — `Package` and `Target` are manifest-only structures. Keep their ordinary
## source-construction rejection distinct from the generic unknown-constructor class so check/build can
## report the configuration-prelude boundary without changing older diagnostic ranges.
MANIFEST_VALUE_DIAG_MARKER := 5476377146882523136
manifest_value_err := fn(s : usize) -> CheckErr { MANIFEST_VALUE_DIAG_MARKER + s * 4 }
## A distinct located diagnostic for the Declarations §3.1 / Memory §1.6 rule that an existing
## binding must be declared `mut` before a write. Keep the marker above the comptime class and below
## 2^63 so the existing unsigned CheckErr representation remains bootstrap-safe; the driver strips it
## before decoding the ordinary source offset.
IMMUTABLE_DIAG_MARKER := 8070450532247928832
immutable_err := fn(s : usize) -> CheckErr { IMMUTABLE_DIAG_MARKER + s * 4 }
## A distinct diagnostic class for the orthogonal `@limits` contract. The payload uses eight-byte
## slots so the low three bits carry the violated limit kind while the remaining value carries the
## source offset. The driver strips this marker before rendering a named limit; ordinary CheckErr
## values above remain byte-identical.
LIMIT_DIAG_MARKER := 2305843009213693952
limit_err := fn(s : usize, kind : usize) -> CheckErr { LIMIT_DIAG_MARKER + s * 8 + kind }
## A distinct located diagnostic for the Types §4.6 scalar/brand conversion constructor arity rule.
## Keep it between the existing ambiguous-call and comptime markers so every older CheckErr range
## remains unchanged while check/build/emit surfaces can preserve the lower's established wording.
SCALAR_CONVERSION_DIAG_MARKER := 5764607523034234880
scalar_conversion_err := fn(s : usize) -> CheckErr { SCALAR_CONVERSION_DIAG_MARKER + s * 4 }
## A distinct located diagnostic for the unsupported non-literal mutable-struct-global assignment
## fence. Keep it between the scalar-conversion and comptime classes so older CheckErr ranges remain
## byte-identical while every CLI renderer can retain the existing lower's useful wording.
GLOBAL_AGG_DIAG_MARKER := 6341068275337658368
global_agg_err := fn(s : usize) -> CheckErr { GLOBAL_AGG_DIAG_MARKER + s * 4 }
## A distinct located diagnostic for a CONST module-level aggregate runtime-call initializer. Keep it
## between the mutable-global and standard-byte-tuple classes so older CheckErr ranges remain byte-for-
## byte unchanged while check/build/emit surfaces can name the same pre-emission rule.
GLOBAL_INIT_CALL_DIAG_MARKER := 6485183463413514240
global_init_call_err := fn(s : usize) -> CheckErr { GLOBAL_INIT_CALL_DIAG_MARKER + s * 4 }
## A distinct located diagnostic for the unsupported standard-byte tuple global ABI boundary. Keep it
## above the non-literal aggregate-global class and below comptime so every older CheckErr range stays
## byte-identical while check/build/emit surfaces can share the lower's established wording.
STANDARD_TUPLE_GLOBAL_DIAG_MARKER := 6629298651489350912
standard_tuple_global_err := fn(s : usize) -> CheckErr { STANDARD_TUPLE_GLOBAL_DIAG_MARKER + s * 4 }
## A distinct located diagnostic for an ENUM-element ARRAY GLOBAL element consumed as a value. Keep it
## between the standard-tuple-global and comptime classes so every older CheckErr range remains stable
## while check/build/emit surfaces can reject the width-blind generic value load consistently.
ENUM_GLOBAL_ARRAY_DIAG_MARKER := 6773413839565216384
enum_global_array_err := fn(s : usize) -> CheckErr { ENUM_GLOBAL_ARRAY_DIAG_MARKER + s * 4 }

## A distinct located diagnostic for an initialized local array literal whose element is a @packed
## struct. Keep it between the enum-array and comptime classes so the common sema/pre-emission path
## rejects the exact deferred array shape without changing any older CheckErr range.
PACKED_ARRAY_DIAG_MARKER := 6845468423603140608
packed_array_err := fn(s : usize) -> CheckErr { PACKED_ARRAY_DIAG_MARKER + s * 4 }
## A distinct located diagnostic for the bounded local 2D fixed-array slice. Keep it between the packed
## array and comptime classes so every older CheckErr range remains stable while check/build/emit surfaces
## share one pre-emission refusal for the exact shapes whose nested lowering is not yet safe.
LOCAL_MULTIDIM_ARRAY_DIAG_MARKER := 6880000000000000000
local_multidim_array_err := fn(s : usize) -> CheckErr { LOCAL_MULTIDIM_ARRAY_DIAG_MARKER + s * 4 }
## Issue #214 — a direct multidimensional fixed-array STRUCT FIELD has no composed nested address
## model in the current lower. Keep this class distinct from the bounded local-array fence so both
## public entry points can report the established field-specific wording and source location.
MULTIDIM_ARRAY_FIELD_DIAG_MARKER := 6890000000000000000
multidim_array_field_err := fn(s : usize) -> CheckErr { MULTIDIM_ARRAY_FIELD_DIAG_MARKER + s * 4 }

## A distinct located diagnostic for a `comptime if` whose condition reads a runtime local. Keep it
## between the CT-12 guard class and immutable bindings so every older CheckErr range remains stable;
## the four-byte payload carries the offending local's source offset.
COMPTIME_COND_DIAG_MARKER := 7493989779944505344
comptime_cond_err := fn(s : usize) -> CheckErr { COMPTIME_COND_DIAG_MARKER + s * 4 }

## A synthesized type: a tag (0 unknown/error, 1 int, 2 bool, 3 struct, 4 enum, 5 pointer,
## 6 str, 7 array) and, for a struct/enum, the type's name span `[ns, ns+nl)`.
pub Ty := struct { tag : u8, ns : usize, nl : usize }

## Are two types compatible? Unknown (tag 0) is compatible with anything (poison-tolerant —
## an unresolved sub-expression must not cascade a spurious mismatch). Two known scalar types
## match iff their tags are equal. Aggregate aliases are canonicalized by `resolve_ty` and the
## layout helpers, so a proven one-hop `C`/`R` alias carries the target's identity through the
## constructor and return-type paths without widening the checker to an unproven global nominal
## rejection rule.
## Are two type TAGS compatible? Unknown (0) is compatible with anything (poison-tolerant). Equal
## tags match. The int(1)↔pointer(5) pair is compatible in BOTH directions: the self-host models an
## AST/allocator HANDLE as a bare `usize` in some signatures (`stmt_p(Stmt, h : usize)`,
## `d_next_stmt(h : usize, …) -> usize`) and a typed `ptr(T)` in others (`head : ptr(mut Stmt)`), and
## flows one into the other freely — the usize↔ptr seam the lower already lowers identically (MEM-7/8,
## I11, D-usize→ptr). Accepting it here is monotonic (teaches `check` to accept what `build` compiles);
## the `ptr(X)`-vs-`ptr(Y)` pointee discrimination (two tag-5 with distinct known pointees) is UNAFFECTED
## — that lives in `ty_compat`, keyed on both tags being 5.
tag_compat := fn(x : u8, y : u8) -> bool {
  if x == 0 { return true }
  if y == 0 { return true }
  if x == y { return true }
  if x == 1 and y == 5 { return true }
  if x == 5 and y == 1 { return true }
  false
}
ty_eq := fn(a : Ty, b : Ty) -> bool {
  tag_compat(a.tag, b.tag)
}

## `ty_eq` PLUS pointer-target discrimination (the dogfood of `ptr(T)` typing). `ty_compat`
## additionally requires: when BOTH sides are
## pointers (tag 5) whose pointee resolved to a KNOWN struct/enum name (`resolve_ty` records it in
## ns/nl; a generic `T`, a scalar `usize`, or a qualified pointee stays {0,0} = unknown), the pointee
## NAMES must match. Poison-tolerant and conservative: an unknown pointee on either side, or a
## non-pointer, falls back to `ty_eq` — so the check fires ONLY on two clearly-distinct named
## aggregates and never FALSE-rejects (I11: correct-or-reject, never a spurious reject).
ty_compat := fn(a : Ty, b : Ty, src : ptr(u8)) -> bool {
  if a.tag == 0 { return true }
  if b.tag == 0 { return true }
  if not tag_compat(a.tag, b.tag) { return false }
  ## pointee discrimination applies ONLY when BOTH sides are pointers (tag 5); an int↔ptr pair (the
  ## handle seam) is accepted above and must NOT reach the pointee-name compare (an int's ns/nl is its
  ## own scalar-type-name span, which would spuriously fail the `streq`).
  bothptr := a.tag == 5 and b.tag == 5 and a.nl != 0 and b.nl != 0
  if bothptr { return streq(src, a.ns, a.nl, b.ns, b.nl) }
  return true
}

## Do two source spans denote the same name (content equality)?
streq := fn(src : ptr(u8), a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool {
  ## `src + a_s`/`src + b_s` are POINTER arithmetic (a span start may be a REBASED handle for a
  ## comptime-synthesized name) → route through `rt::addr`, not a checked integer `+` (I11 / CG-8).
  wa := str_at((src + a_s), a_n)
  wb := str_at((src + b_s), b_n)
  wa == wb
}

## Typed pointer to the `T`-record at decl handle `h` (arg0=T → deref-copy on read).
decl_at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
## a DIRECT typed accessor for decl `i` — `ptr(Decl)` in one expression, replacing the
## nested helper-recovery `decl_get(decls, i)` at every use site (the
## opaque-usize→typed-ptr dogfood: the bitcast is encapsulated here, not repeated at each caller).
decl_get := fn(decls : ptr(rt::Vec), i : usize) -> ptr(Decl) { return decl_at(Decl, rt::vec_get(deref(decls), i)) }
## A typed pointer to the AST node at arena OFFSET `h` (lean replacement for `get`; mirrors
## `parser::node_ptr`).
node_ptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}
## 8-aligned bump over the arena (returns the new region's OFFSET) — the lean replacement for the
## generic `allocate`, used by `LVec` (the locals table). Mirrors `parser::node_alloc`.
node_alloc := fn(in out a : rt::Arena, sz : usize) -> usize {
  rem := a.off % 8
  mut aligned := a.off
  if rem != 0 { aligned = a.off + (8 - rem) }
  if aligned + sz > a.cap { panic("sema: out of memory") }
  a.off = aligned + sz
  return aligned
}

## `LVec` — a `Local` vector backed by a bump arena (the lean replacement for the generic
## `alloc::vec` locals table fixpoint), mirroring `lower::SVec`. The check pass's
## locals table; growth doubles `cap` with a word-granular copy (element stride word-aligned).
## `fspan` points at a frame word recording the FIRST located `mark_failed` poison as a `CheckErr`
## code (kind in the low 2 bits, source start in the rest — the `CheckErr` encoding), 0 = unset. It
## lets a poison-only failure (one that never propagated through the `Err` channel) still carry a
## source location into the diagnostic (§5). Distinct from `failed` (which holds
## the sticky flag + the declared return tag), so recording a span never disturbs the return-tag bits.
## `mod_s`/`mod_l` identify the function's owning module, so call diagnostics can inspect only the
## overload set the lower will actually route. `pbase`/`pcnt`/`pcap`: a function-wide REMEMBERED
## name-span list (2 words per entry: ns, nl) that
## `lvec_remember` appends every `:=` body binding / for-var / param to and that arm/branch truncation
## NEVER touches. Alatyr `:=` locals leak function-scoped, so `expr_has_unbound` resolves against this
## set as a fallback beyond the per-block `len` window (fixes a false "unbound" on a leaked local
## referenced from a sibling/else-if branch the checker walks past the binding's live window).
LVec := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena), failed : ptr(mut usize), fspan : ptr(mut usize), mod_s : usize, mod_l : usize, pbase : usize, pcnt : usize, pcap : usize }
lvec_stride := fn() -> usize {
  sz := size(Local)
  r := sz % 8
  if r == 0 { return sz }
  return sz + (8 - r)
}
lvec_new := fn(a : ptr(mut rt::Arena), cap : usize, failed : ptr(mut usize), fspan : ptr(mut usize), mod_s : usize, mod_l : usize) -> LVec {
  off := node_alloc(deref(a), cap * lvec_stride())
  base_abs := unchecked bitcast(usize, deref(a).base) + off
  poff := node_alloc(deref(a), 32 * 16)
  pbase_abs := unchecked bitcast(usize, deref(a).base) + poff
  return LVec(base = base_abs, len = 0, cap = cap, arena = a, failed = failed, fspan = fspan, mod_s = mod_s, mod_l = mod_l, pbase = pbase_abs, pcnt = 0, pcap = 32)
}
## Append name span `[ns, ns+nl)` to the function-wide remembered set (grows by doubling, word-copy).
lvec_remember := fn(in out v : LVec, ns : usize, nl : usize) {
  if v.pcnt >= v.pcap {
    new_cap := v.pcap * 2
    noff := node_alloc(deref(v.arena), new_cap * 16)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    mut k := 0
    while k < v.pcnt * 2 {
      sp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.pbase + k * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), nbase + k * 8)
      deref(dp) = deref(sp)
      k += 1
    }
    v.pbase = nbase
    v.pcap = new_cap
  }
  ep : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.pbase + v.pcnt * 16)
  deref(ep) = ns
  ep2 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.pbase + v.pcnt * 16 + 8)
  deref(ep2) = nl
  v.pcnt = v.pcnt + 1
}
## Is name `[s, s+n)` in the function-wide remembered set? (content compare via `streq`).
remembered := fn(locals : ptr(LVec), src : ptr(u8), s : usize, n : usize) -> bool {
  lv := deref(locals)
  mut i := 0
  while i < lv.pcnt {
    rns : ptr(usize) = unchecked bitcast(ptr(usize), lv.pbase + i * 16)
    rnl : ptr(usize) = unchecked bitcast(ptr(usize), lv.pbase + i * 16 + 8)
    if streq(src, deref(rns), deref(rnl), s, n) { return true }
    i += 1
  }
  false
}

## A separate definite-assignment set. Local's layout is bootstrap-sensitive and already carries type,
## mutability, and leak-tracking state, so initialization is kept in this source-span table instead of
## widening the AST or Local record. This first slice is intentionally linear-flow; control-flow joins,
## field paths, and comptime-constant array elements are the next roadmap slices.
DVec := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena) }
dvec_new := fn(a : ptr(mut rt::Arena), cap : usize) -> DVec {
  off := node_alloc(deref(a), cap * 16)
  base := unchecked bitcast(usize, deref(a).base) + off
  DVec(base = base, len = 0, cap = cap, arena = a)
}
dvec_has := fn(dv : ptr(DVec), src : ptr(u8), s : usize, n : usize) -> bool {
  v := deref(dv)
  mut i := 0
  while i < v.len {
    sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 16)
    np : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 16 + 8)
    if streq(src, deref(sp), deref(np), s, n) { return true }
    i += 1
  }
  false
}
## Keep a direct append helper for the first linear slice; callers only add each binding once.
dvec_push := fn(in out v : DVec, s : usize, n : usize) {
  if v.len >= v.cap {
    new_cap := v.cap * 2
    noff := node_alloc(deref(v.arena), new_cap * 16)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    mut i := 0
    while i < v.len * 2 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 8)
      dp : ptr(usize) = unchecked bitcast(ptr(usize), nbase + i * 8)
      deref(dp) = deref(sp)
      i += 1
    }
    v.base = nbase
    v.cap = new_cap
  }
  sp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 16)
  np : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 16 + 8)
  deref(sp) = s
  deref(np) = n
  v.len += 1
}
dvec_remove := fn(in out v : DVec, src : ptr(u8), s : usize, n : usize) {
  mut i := 0
  mut found := false
  while i < v.len {
    sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 16)
    np : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 16 + 8)
    if streq(src, deref(sp), deref(np), s, n) { found = true; break }
    i += 1
  }
  if found == false { return }
  mut j := i + 1
  while j < v.len {
    sp2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 16)
    np2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 16 + 8)
    dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 16)
    dp2 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 16 + 8)
    deref(dp) = deref(sp2)
    deref(dp2) = deref(np2)
    j += 1
  }
  v.len -= 1
}

## Copy an uninitialized-place state for an independent structured branch. The first DA slice stored only
## root names, so a join is the union of names still unreadied in either non-diverging branch (equivalent
## to intersection of definitely-assigned names). Branch vectors share the function arena but own their
## logical lengths, so checking one branch cannot mutate the other branch's incoming state.
dvec_copy := fn(sv : ptr(DVec)) -> DVec {
  srcv := deref(sv)
  mut dst := dvec_new(srcv.arena, srcv.cap)
  mut i := 0
  while i < srcv.len {
    sp : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 16)
    np : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 16 + 8)
    dvec_push(dst, deref(sp), deref(np))
    i += 1
  }
  dst
}
dvec_union_src := fn(left : ptr(DVec), right : ptr(DVec), src : ptr(u8)) -> DVec {
  lv := deref(left)
  rv := deref(right)
  mut dst := dvec_new(lv.arena, lv.cap + rv.cap)
  mut i := 0
  while i < lv.len {
    sp : ptr(usize) = unchecked bitcast(ptr(usize), lv.base + i * 16)
    np : ptr(usize) = unchecked bitcast(ptr(usize), lv.base + i * 16 + 8)
    dvec_push(dst, deref(sp), deref(np))
    i += 1
  }
  i = 0
  while i < rv.len {
    sp2 : ptr(usize) = unchecked bitcast(ptr(usize), rv.base + i * 16)
    np2 : ptr(usize) = unchecked bitcast(ptr(usize), rv.base + i * 16 + 8)
    if not dvec_has(ptr(dst), src, deref(sp2), deref(np2)) { dvec_push(dst, deref(sp2), deref(np2)) }
    i += 1
  }
  dst
}
dvec_assign := fn(in out dst : DVec, src : DVec) {
  dst.base = src.base
  dst.len = src.len
  dst.cap = src.cap
  dst.arena = src.arena
}

## Field-sensitive definite-assignment state is kept in a separate four-word place table. The root DVec
## remains byte-for-byte stable because it is already threaded through the self-hosted checker and copied
## by value in branch snapshots. Entries are (root span, field span), and represent fields still unreadied.
FVec := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena) }
fvec_new := fn(a : ptr(mut rt::Arena), cap : usize) -> FVec {
  off := node_alloc(deref(a), cap * 32)
  base := unchecked bitcast(usize, deref(a).base) + off
  FVec(base = base, len = 0, cap = cap, arena = a)
}
fvec_has := fn(v : ptr(FVec), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) -> bool {
  fv := deref(v)
  mut i := 0
  while i < fv.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), fv.base + i * 32)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), fv.base + i * 32 + 8)
    f0 : ptr(usize) = unchecked bitcast(ptr(usize), fv.base + i * 32 + 16)
    f1 : ptr(usize) = unchecked bitcast(ptr(usize), fv.base + i * 32 + 24)
    if streq(src, deref(r0), deref(r1), rs, rn) and streq(src, deref(f0), deref(f1), fs, fln) { return true }
    i += 1
  }
  false
}
fvec_has_root := fn(v : ptr(FVec), src : ptr(u8), rs : usize, rn : usize) -> bool {
  fv := deref(v)
  mut i := 0
  while i < fv.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), fv.base + i * 32)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), fv.base + i * 32 + 8)
    if streq(src, deref(r0), deref(r1), rs, rn) { return true }
    i += 1
  }
  false
}
fvec_push := fn(in out v : FVec, rs : usize, rn : usize, fs : usize, fln : usize) {
  if v.len >= v.cap {
    new_cap := v.cap * 2
    noff := node_alloc(deref(v.arena), new_cap * 32)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    mut i := 0
    while i < v.len * 4 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 8)
      dp : ptr(usize) = unchecked bitcast(ptr(usize), nbase + i * 8)
      deref(dp) = deref(sp)
      i += 1
    }
    v.base = nbase
    v.cap = new_cap
  }
  r0 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 32)
  r1 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 32 + 8)
  f0 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 32 + 16)
  f1 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 32 + 24)
  deref(r0) = rs
  deref(r1) = rn
  deref(f0) = fs
  deref(f1) = fln
  v.len += 1
}
fvec_remove := fn(in out v : FVec, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) {
  mut i := 0
  mut found := false
  while i < v.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 32)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 32 + 8)
    f0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 32 + 16)
    f1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 32 + 24)
    if streq(src, deref(r0), deref(r1), rs, rn) and streq(src, deref(f0), deref(f1), fs, fln) { found = true; break }
    i += 1
  }
  if found == false { return }
  mut j := i + 1
  while j < v.len {
    mut k := 0
    while k < 4 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 32 + k * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 32 + k * 8)
      deref(dp) = deref(sp)
      k += 1
    }
    j += 1
  }
  v.len -= 1
}
fvec_remove_root := fn(in out v : FVec, src : ptr(u8), rs : usize, rn : usize) {
  mut i := 0
  while i < v.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 32)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 32 + 8)
    if streq(src, deref(r0), deref(r1), rs, rn) {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 4 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 32 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 32 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else {
      i += 1
    }
  }
}
fvec_copy := fn(sv : ptr(FVec)) -> FVec {
  srcv := deref(sv)
  mut dst := fvec_new(srcv.arena, srcv.cap)
  mut i := 0
  while i < srcv.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 32)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 32 + 8)
    f0 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 32 + 16)
    f1 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 32 + 24)
    fvec_push(dst, deref(r0), deref(r1), deref(f0), deref(f1))
    i += 1
  }
  dst
}
fvec_union_src := fn(left : ptr(FVec), right : ptr(FVec), src : ptr(u8)) -> FVec {
  lv := deref(left)
  rv := deref(right)
  mut dst := fvec_new(lv.arena, lv.cap + rv.cap)
  mut i := 0
  while i < lv.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), lv.base + i * 32)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), lv.base + i * 32 + 8)
    f0 : ptr(usize) = unchecked bitcast(ptr(usize), lv.base + i * 32 + 16)
    f1 : ptr(usize) = unchecked bitcast(ptr(usize), lv.base + i * 32 + 24)
    fvec_push(dst, deref(r0), deref(r1), deref(f0), deref(f1))
    i += 1
  }
  i = 0
  while i < rv.len {
    r2 : ptr(usize) = unchecked bitcast(ptr(usize), rv.base + i * 32)
    r3 : ptr(usize) = unchecked bitcast(ptr(usize), rv.base + i * 32 + 8)
    f2 : ptr(usize) = unchecked bitcast(ptr(usize), rv.base + i * 32 + 16)
    f3 : ptr(usize) = unchecked bitcast(ptr(usize), rv.base + i * 32 + 24)
    if not fvec_has(ptr(dst), src, deref(r2), deref(r3), deref(f2), deref(f3)) { fvec_push(dst, deref(r2), deref(r3), deref(f2), deref(f3)) }
    i += 1
  }
  dst
}

## A bounded nested-place table for aggregate paths `root.field.subfield`. Entries are six source spans
## (root, first field, second field). Keeping this separate from FVec preserves the existing direct-field
## representation and makes branch snapshots/joins copy the complete unreadied-place state.
PVec := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena) }
pvec_new := fn(a : ptr(mut rt::Arena), cap : usize) -> PVec {
  off := node_alloc(deref(a), cap * 48)
  base := unchecked bitcast(usize, deref(a).base) + off
  PVec(base = base, len = 0, cap = cap, arena = a)
}
pvec_has := fn(v : ptr(PVec), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize) -> bool {
  pv := deref(v)
  mut i := 0
  while i < pv.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 32)
    p5 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 40)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) and streq(src, deref(p4), deref(p5), ss, sln) { return true }
    i += 1
  }
  false
}
pvec_has_prefix := fn(v : ptr(PVec), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) -> bool {
  pv := deref(v)
  mut i := 0
  while i < pv.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 24)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) { return true }
    i += 1
  }
  false
}
pvec_has_root := fn(v : ptr(PVec), src : ptr(u8), rs : usize, rn : usize) -> bool {
  pv := deref(v)
  mut i := 0
  while i < pv.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 48 + 8)
    if streq(src, deref(p0), deref(p1), rs, rn) { return true }
    i += 1
  }
  false
}
pvec_push := fn(in out v : PVec, rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize) {
  if v.len >= v.cap {
    new_cap := v.cap * 2
    noff := node_alloc(deref(v.arena), new_cap * 48)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    mut i := 0
    while i < v.len * 6 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), nbase + i * 8)
      deref(dp) = deref(sp)
      i += 1
    }
    v.base = nbase
    v.cap = new_cap
  }
  p0 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 48)
  p1 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 48 + 8)
  p2 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 48 + 16)
  p3 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 48 + 24)
  p4 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 48 + 32)
  p5 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 48 + 40)
  deref(p0) = rs
  deref(p1) = rn
  deref(p2) = fs
  deref(p3) = fln
  deref(p4) = ss
  deref(p5) = sln
  v.len += 1
}
pvec_remove := fn(in out v : PVec, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize) {
  mut i := 0
  mut found := false
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 32)
    p5 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 40)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) and streq(src, deref(p4), deref(p5), ss, sln) { found = true; break }
    i += 1
  }
  if found == false { return }
  mut j := i + 1
  while j < v.len {
    mut k := 0
    while k < 6 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 48 + k * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 48 + k * 8)
      deref(dp) = deref(sp)
      k += 1
    }
    j += 1
  }
  v.len -= 1
}
pvec_remove_prefix := fn(in out v : PVec, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) {
  mut i := 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 24)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 6 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 48 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 48 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else {
      i += 1
    }
  }
}
pvec_remove_root := fn(in out v : PVec, src : ptr(u8), rs : usize, rn : usize) {
  mut i := 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 48 + 8)
    if streq(src, deref(p0), deref(p1), rs, rn) {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 6 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 48 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 48 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else {
      i += 1
    }
  }
}
pvec_copy := fn(sv : ptr(PVec)) -> PVec {
  srcv := deref(sv)
  mut dst := pvec_new(srcv.arena, srcv.cap)
  mut i := 0
  while i < srcv.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 48 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 48 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 48 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 48 + 32)
    p5 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 48 + 40)
    pvec_push(dst, deref(p0), deref(p1), deref(p2), deref(p3), deref(p4), deref(p5))
    i += 1
  }
  dst
}

## A bounded array-element table for fixed-array places. Entries are (root source span, constant index).
## Dynamic indices and unsupported nested array places deliberately never enter this table, so their
## existing conservative behavior is preserved. Keeping this separate from PVec avoids changing the
## bootstrap-sensitive nested-field entry width.
AVec := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena) }
avec_new := fn(a : ptr(mut rt::Arena), cap : usize) -> AVec {
  off := node_alloc(deref(a), cap * 24)
  base := unchecked bitcast(usize, deref(a).base) + off
  AVec(base = base, len = 0, cap = cap, arena = a)
}
avec_has_root := fn(v : ptr(AVec), src : ptr(u8), rs : usize, rn : usize) -> bool {
  av := deref(v)
  mut i := 0
  while i < av.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 24)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 24 + 8)
    if streq(src, deref(r0), deref(r1), rs, rn) { return true }
    i += 1
  }
  false
}
avec_has := fn(v : ptr(AVec), src : ptr(u8), rs : usize, rn : usize, ix : usize) -> bool {
  av := deref(v)
  mut i := 0
  while i < av.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 24)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 24 + 8)
    ixp : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 24 + 16)
    if streq(src, deref(r0), deref(r1), rs, rn) {
      if deref(ixp) == ix { return true }
    }
    i += 1
  }
  false
}
avec_push := fn(in out v : AVec, rs : usize, rn : usize, ix : usize) {
  if v.len >= v.cap {
    new_cap := v.cap * 2
    noff := node_alloc(deref(v.arena), new_cap * 24)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    mut i := 0
    while i < v.len * 3 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), nbase + i * 8)
      deref(dp) = deref(sp)
      i += 1
    }
    v.base = nbase
    v.cap = new_cap
  }
  r0 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 24)
  r1 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 24 + 8)
  r2 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 24 + 16)
  deref(r0) = rs
  deref(r1) = rn
  deref(r2) = ix
  v.len += 1
}
avec_remove := fn(in out v : AVec, src : ptr(u8), rs : usize, rn : usize, ix : usize) {
  mut i := 0
  mut found := false
  while i < v.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 24)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 24 + 8)
    r2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 24 + 16)
    if streq(src, deref(r0), deref(r1), rs, rn) and deref(r2) == ix { found = true; break }
    i += 1
  }
  if found == false { return }
  mut j := i + 1
  while j < v.len {
    mut k := 0
    while k < 3 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 24 + k * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 24 + k * 8)
      deref(dp) = deref(sp)
      k += 1
    }
    j += 1
  }
  v.len -= 1
}
avec_remove_root := fn(in out v : AVec, src : ptr(u8), rs : usize, rn : usize) {
  mut i := 0
  while i < v.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 24)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 24 + 8)
    if streq(src, deref(r0), deref(r1), rs, rn) {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 3 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 24 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 24 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else { i += 1 }
  }
}
avec_copy := fn(sv : ptr(AVec)) -> AVec {
  srcv := deref(sv)
  mut dst := avec_new(srcv.arena, srcv.cap)
  mut i := 0
  while i < srcv.len {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 24)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 24 + 8)
    r2 : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 24 + 16)
    avec_push(dst, deref(r0), deref(r1), deref(r2))
    i += 1
  }
  dst
}

## A bounded array-element table for paths `root.field[index]`. Entries are (root span, field span,
## constant index). This is deliberately separate from AVec because a field name is part of the place key.
## Dynamic indices and unsupported deeper paths never enter this table and remain conservative.
NAVec := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena) }
navec_new := fn(a : ptr(mut rt::Arena), cap : usize) -> NAVec {
  off := node_alloc(deref(a), cap * 40)
  base := unchecked bitcast(usize, deref(a).base) + off
  NAVec(base = base, len = 0, cap = cap, arena = a)
}
navec_has := fn(v : ptr(NAVec), src : ptr(u8), rs : usize, rn : usize, fs : usize, fnl : usize, ix : usize) -> bool {
  av := deref(v)
  mut i := 0
  while i < av.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 32)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fnl) and deref(p4) == ix { return true }
    i += 1
  }
  false
}
navec_has_field := fn(v : ptr(NAVec), src : ptr(u8), rs : usize, rn : usize, fs : usize, fnl : usize) -> bool {
  av := deref(v)
  mut i := 0
  while i < av.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 24)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fnl) { return true }
    i += 1
  }
  false
}
navec_has_root := fn(v : ptr(NAVec), src : ptr(u8), rs : usize, rn : usize) -> bool {
  av := deref(v)
  mut i := 0
  while i < av.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 8)
    if streq(src, deref(p0), deref(p1), rs, rn) { return true }
    i += 1
  }
  false
}
navec_has_root_index := fn(v : ptr(NAVec), src : ptr(u8), rs : usize, rn : usize, ix : usize) -> bool {
  av := deref(v)
  mut i := 0
  while i < av.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 8)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), av.base + i * 40 + 32)
    if streq(src, deref(p0), deref(p1), rs, rn) and deref(p4) == ix { return true }
    i += 1
  }
  false
}
navec_push := fn(in out v : NAVec, rs : usize, rn : usize, fs : usize, fnl : usize, ix : usize) {
  if v.len >= v.cap {
    new_cap := v.cap * 2
    noff := node_alloc(deref(v.arena), new_cap * 40)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    mut i := 0
    while i < v.len * 5 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), nbase + i * 8)
      deref(dp) = deref(sp)
      i += 1
    }
    v.base = nbase
    v.cap = new_cap
  }
  p0 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 40)
  p1 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 40 + 8)
  p2 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 40 + 16)
  p3 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 40 + 24)
  p4 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 40 + 32)
  deref(p0) = rs
  deref(p1) = rn
  deref(p2) = fs
  deref(p3) = fnl
  deref(p4) = ix
  v.len += 1
}
navec_remove := fn(in out v : NAVec, src : ptr(u8), rs : usize, rn : usize, fs : usize, fnl : usize, ix : usize) {
  mut i := 0
  mut found := false
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 32)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fnl) and deref(p4) == ix { found = true; break }
    i += 1
  }
  if found == false { return }
  mut j := i + 1
  while j < v.len {
    mut k := 0
    while k < 5 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 40 + k * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 40 + k * 8)
      deref(dp) = deref(sp)
      k += 1
    }
    j += 1
  }
  v.len -= 1
}
navec_remove_field := fn(in out v : NAVec, src : ptr(u8), rs : usize, rn : usize, fs : usize, fnl : usize) {
  mut i := 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 24)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fnl) {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 5 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 40 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 40 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else { i += 1 }
  }
}
navec_remove_root := fn(in out v : NAVec, src : ptr(u8), rs : usize, rn : usize) {
  mut i := 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 8)
    if streq(src, deref(p0), deref(p1), rs, rn) {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 5 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 40 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 40 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else { i += 1 }
  }
}

## A bounded nested path table for aggregate array fields: `root.array_field[index].leaf_field`.
## Entries are (root span, array-field span, leaf-field span, constant index). This is the next
## conservative DA tier beyond `root.field[index]`: dynamic indices and deeper unsupported paths stay
## unreadied rather than being guessed initialized.
NAPVec := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena) }
napvec_new := fn(a : ptr(mut rt::Arena), cap : usize) -> NAPVec {
  off := node_alloc(deref(a), cap * 56)
  base := unchecked bitcast(usize, deref(a).base) + off
  NAPVec(base = base, len = 0, cap = cap, arena = a)
}
napvec_has := fn(v : ptr(NAPVec), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize, ix : usize) -> bool {
  pv := deref(v)
  mut i := 0
  while i < pv.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 32)
    p5 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 40)
    p6 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 48)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) and streq(src, deref(p4), deref(p5), ss, sln) and deref(p6) == ix { return true }
    i += 1
  }
  false
}
napvec_has_index := fn(v : ptr(NAPVec), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ix : usize) -> bool {
  pv := deref(v)
  mut i := 0
  while i < pv.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 24)
    p6 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 48)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) and deref(p6) == ix { return true }
    i += 1
  }
  false
}
napvec_has_field := fn(v : ptr(NAPVec), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) -> bool {
  pv := deref(v)
  mut i := 0
  while i < pv.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 24)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) { return true }
    i += 1
  }
  false
}
napvec_has_root := fn(v : ptr(NAPVec), src : ptr(u8), rs : usize, rn : usize) -> bool {
  pv := deref(v)
  mut i := 0
  while i < pv.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), pv.base + i * 56 + 8)
    if streq(src, deref(p0), deref(p1), rs, rn) { return true }
    i += 1
  }
  false
}
napvec_push := fn(in out v : NAPVec, rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize, ix : usize) {
  if v.len >= v.cap {
    new_cap := v.cap * 2
    noff := node_alloc(deref(v.arena), new_cap * 56)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    mut i := 0
    while i < v.len * 7 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), nbase + i * 8)
      deref(dp) = deref(sp)
      i += 1
    }
    v.base = nbase
    v.cap = new_cap
  }
  mut k := 0
  while k < 7 {
    dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 56 + k * 8)
    if k == 0 { deref(dp) = rs }
    else if k == 1 { deref(dp) = rn }
    else if k == 2 { deref(dp) = fs }
    else if k == 3 { deref(dp) = fln }
    else if k == 4 { deref(dp) = ss }
    else if k == 5 { deref(dp) = sln }
    else { deref(dp) = ix }
    k += 1
  }
  v.len += 1
}
napvec_remove := fn(in out v : NAPVec, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize, ix : usize) {
  mut i := 0
  mut found := false
  while i < v.len {
    if napvec_has(ptr(v), src, rs, rn, fs, fln, ss, sln, ix) { found = true; break }
    i += 1
  }
  if not found { return }
  ## Locate the exact entry again while shifting, avoiding a second table representation.
  i = 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 32)
    p5 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 40)
    p6 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 48)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) and streq(src, deref(p4), deref(p5), ss, sln) and deref(p6) == ix { found = true; break }
    i += 1
  }
  if not found { return }
  mut j := i + 1
  while j < v.len {
    mut k := 0
    while k < 7 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 56 + k * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 56 + k * 8)
      deref(dp) = deref(sp)
      k += 1
    }
    j += 1
  }
  v.len -= 1
}
napvec_remove_index := fn(in out v : NAPVec, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ix : usize) {
  mut i := 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 24)
    p6 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 48)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) and deref(p6) == ix {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 7 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 56 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 56 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else { i += 1 }
  }
}
napvec_remove_field := fn(in out v : NAPVec, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) {
  mut i := 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 24)
    if streq(src, deref(p0), deref(p1), rs, rn) and streq(src, deref(p2), deref(p3), fs, fln) {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 7 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 56 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 56 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else { i += 1 }
  }
}
napvec_remove_root := fn(in out v : NAPVec, src : ptr(u8), rs : usize, rn : usize) {
  mut i := 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 56 + 8)
    if streq(src, deref(p0), deref(p1), rs, rn) {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 7 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 56 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 56 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else { i += 1 }
  }
}
napvec_copy := fn(sv : ptr(NAPVec)) -> NAPVec {
  srcv := deref(sv)
  mut dst := napvec_new(srcv.arena, srcv.cap)
  mut i := 0
  while i < srcv.len {
    mut q : usize = 0
    mut a0 : usize = 0
    mut a1 : usize = 0
    mut a2 : usize = 0
    mut a3 : usize = 0
    mut a4 : usize = 0
    mut a5 : usize = 0
    mut a6 : usize = 0
    while q < 7 {
      vp : ptr(usize) = unchecked bitcast(ptr(usize), srcv.base + i * 56 + q * 8)
      if q == 0 { a0 = deref(vp) } else if q == 1 { a1 = deref(vp) } else if q == 2 { a2 = deref(vp) } else if q == 3 { a3 = deref(vp) } else if q == 4 { a4 = deref(vp) } else if q == 5 { a5 = deref(vp) } else { a6 = deref(vp) }
      q += 1
    }
    napvec_push(dst, a0, a1, a2, a3, a4, a5, a6)
    i += 1
  }
  dst
}
navec_remove_index := fn(in out v : NAVec, src : ptr(u8), rs : usize, rn : usize, ix : usize) {
  mut i := 0
  while i < v.len {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 8)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 40 + 32)
    if streq(src, deref(p0), deref(p1), rs, rn) and deref(p4) == ix {
      mut j := i + 1
      while j < v.len {
        mut k := 0
        while k < 5 {
          sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + j * 40 + k * 8)
          dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + (j - 1) * 40 + k * 8)
          deref(dp) = deref(sp)
          k += 1
        }
        j += 1
      }
      v.len -= 1
    } else {
      i += 1
    }
  }
}

DA := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena), fields : usize, paths : usize, arrays : usize, nested_arrays : usize, nested_paths : usize }
da_fvec := fn(da : ptr(DA)) -> ptr(mut FVec) { unchecked bitcast(ptr(mut FVec), deref(da).fields) }
da_fvec_value := fn(da : DA) -> ptr(mut FVec) { unchecked bitcast(ptr(mut FVec), da.fields) }
da_pvec := fn(da : ptr(DA)) -> ptr(mut PVec) { unchecked bitcast(ptr(mut PVec), deref(da).paths) }
da_pvec_value := fn(da : DA) -> ptr(mut PVec) { unchecked bitcast(ptr(mut PVec), da.paths) }
da_avec := fn(da : ptr(DA)) -> ptr(mut AVec) { unchecked bitcast(ptr(mut AVec), deref(da).arrays) }
da_avec_value := fn(da : DA) -> ptr(mut AVec) { unchecked bitcast(ptr(mut AVec), da.arrays) }
da_navec := fn(da : ptr(DA)) -> ptr(mut NAVec) { unchecked bitcast(ptr(mut NAVec), deref(da).nested_arrays) }
da_navec_value := fn(da : DA) -> ptr(mut NAVec) { unchecked bitcast(ptr(mut NAVec), da.nested_arrays) }
da_napvec := fn(da : ptr(DA)) -> ptr(mut NAPVec) { unchecked bitcast(ptr(mut NAPVec), deref(da).nested_paths) }
da_napvec_value := fn(da : DA) -> ptr(mut NAPVec) { unchecked bitcast(ptr(mut NAPVec), da.nested_paths) }
da_new := fn(a : ptr(mut rt::Arena), cap : usize) -> DA {
  off := node_alloc(deref(a), cap * 16)
  base := unchecked bitcast(usize, deref(a).base) + off
  foff := node_alloc(deref(a), 32)
  fbase := unchecked bitcast(usize, deref(a).base) + foff
  fdata_off := node_alloc(deref(a), cap * 32)
  fdata := unchecked bitcast(usize, deref(a).base) + fdata_off
  fp : ptr(mut FVec) = unchecked bitcast(ptr(mut FVec), fbase)
  deref(fp).base = fdata
  deref(fp).len = 0
  deref(fp).cap = cap
  deref(fp).arena = a
  poff := node_alloc(deref(a), 32)
  pbase := unchecked bitcast(usize, deref(a).base) + poff
  pdata_off := node_alloc(deref(a), cap * 48)
  pdata := unchecked bitcast(usize, deref(a).base) + pdata_off
  pp : ptr(mut PVec) = unchecked bitcast(ptr(mut PVec), pbase)
  deref(pp).base = pdata
  deref(pp).len = 0
  deref(pp).cap = cap
  deref(pp).arena = a
  aoff := node_alloc(deref(a), 32)
  abase := unchecked bitcast(usize, deref(a).base) + aoff
  adata_off := node_alloc(deref(a), cap * 24)
  adata := unchecked bitcast(usize, deref(a).base) + adata_off
  ap : ptr(mut AVec) = unchecked bitcast(ptr(mut AVec), abase)
  deref(ap).base = adata
  deref(ap).len = 0
  deref(ap).cap = cap
  deref(ap).arena = a
  naoff := node_alloc(deref(a), 32)
  nabase := unchecked bitcast(usize, deref(a).base) + naoff
  nadata_off := node_alloc(deref(a), cap * 40)
  nadata := unchecked bitcast(usize, deref(a).base) + nadata_off
  nap : ptr(mut NAVec) = unchecked bitcast(ptr(mut NAVec), nabase)
  deref(nap).base = nadata
  deref(nap).len = 0
  deref(nap).cap = cap
  deref(nap).arena = a
  npoff := node_alloc(deref(a), 32)
  npbase := unchecked bitcast(usize, deref(a).base) + npoff
  npdata_off := node_alloc(deref(a), cap * 56)
  npdata := unchecked bitcast(usize, deref(a).base) + npdata_off
  npp : ptr(mut NAPVec) = unchecked bitcast(ptr(mut NAPVec), npbase)
  deref(npp).base = npdata
  deref(npp).len = 0
  deref(npp).cap = cap
  deref(npp).arena = a
  DA(base = base, len = 0, cap = cap, arena = a, fields = fbase, paths = pbase, arrays = abase, nested_arrays = nabase, nested_paths = npbase)
}
da_has_root := fn(da : ptr(DA), src : ptr(u8), s : usize, n : usize) -> bool {
  v := deref(da)
  mut i := 0
  while i < v.len {
    sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 16)
    np : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 16 + 8)
    if streq(src, deref(sp), deref(np), s, n) { return true }
    i += 1
  }
  false
}
da_has_field := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) -> bool {
  fvec_has(da_fvec(da), src, rs, rn, fs, fln)
}
da_has_field_root := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize) -> bool {
  fvec_has_root(da_fvec(da), src, rs, rn)
}
da_has_path := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize) -> bool {
  pvec_has(da_pvec(da), src, rs, rn, fs, fln, ss, sln)
}
da_has_path_prefix := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) -> bool {
  pvec_has_prefix(da_pvec(da), src, rs, rn, fs, fln)
}
da_has_path_root := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize) -> bool {
  pvec_has_root(da_pvec(da), src, rs, rn)
}
da_has_array_root := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize) -> bool {
  avec_has_root(da_avec(da), src, rs, rn)
}
da_has_array := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, ix : usize) -> bool {
  avec_has(da_avec(da), src, rs, rn, ix)
}
da_has_nested_array := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, fs : usize, fnl : usize, ix : usize) -> bool {
  navec_has(da_navec(da), src, rs, rn, fs, fnl, ix)
}
da_has_nested_array_field := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, fs : usize, fnl : usize) -> bool {
  navec_has_field(da_navec(da), src, rs, rn, fs, fnl)
}
da_has_array_field_root := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, ix : usize) -> bool {
  navec_has_root_index(da_navec(da), src, rs, rn, ix)
}
da_has_nested_path := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize, ix : usize) -> bool {
  napvec_has(da_napvec(da), src, rs, rn, fs, fln, ss, sln, ix)
}
da_has_nested_path_index := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ix : usize) -> bool {
  napvec_has_index(da_napvec(da), src, rs, rn, fs, fln, ix)
}
da_has_nested_path_field := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize) -> bool {
  napvec_has_field(da_napvec(da), src, rs, rn, fs, fln)
}
da_has_nested_path_root := fn(da : ptr(DA), src : ptr(u8), rs : usize, rn : usize) -> bool {
  napvec_has_root(da_napvec(da), src, rs, rn)
}
da_push_root := fn(da : ptr(DA), s : usize, n : usize) {
  mut v := deref(da)
  if v.len >= v.cap {
    new_cap := v.cap * 2
    noff := node_alloc(deref(v.arena), new_cap * 16)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    mut i := 0
    while i < v.len * 2 {
      sp : ptr(usize) = unchecked bitcast(ptr(usize), v.base + i * 8)
      dp : ptr(usize) = unchecked bitcast(ptr(usize), nbase + i * 8)
      deref(dp) = deref(sp)
      i += 1
    }
    v.base = nbase
    v.cap = new_cap
  }
  sp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 16)
  np : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + v.len * 16 + 8)
  deref(sp) = s
  deref(np) = n
  v.len += 1
  deref(da) = v
}
da_remove_root := fn(in out da : DA, src : ptr(u8), s : usize, n : usize) {
  mut i := 0
  mut found := false
  while i < da.len {
    sp : ptr(usize) = unchecked bitcast(ptr(usize), da.base + i * 16)
    np : ptr(usize) = unchecked bitcast(ptr(usize), da.base + i * 16 + 8)
    if streq(src, deref(sp), deref(np), s, n) { found = true; break }
    i += 1
  }
  if found == false { return }
  mut j := i + 1
  while j < da.len {
    sp2 : ptr(usize) = unchecked bitcast(ptr(usize), da.base + j * 16)
    np2 : ptr(usize) = unchecked bitcast(ptr(usize), da.base + j * 16 + 8)
    dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), da.base + (j - 1) * 16)
    dp2 : ptr(mut usize) = unchecked bitcast(ptr(mut usize), da.base + (j - 1) * 16 + 8)
    deref(dp) = deref(sp2)
    deref(dp2) = deref(np2)
    j += 1
  }
  da.len -= 1
  fvec_remove_root(da_fvec_value(da), src, s, n)
  pvec_remove_root(da_pvec_value(da), src, s, n)
  avec_remove_root(da_avec_value(da), src, s, n)
  navec_remove_root(da_navec_value(da), src, s, n)
  napvec_remove_root(da_napvec_value(da), src, s, n)
}
## The field-sensitive DA vectors (FVec/PVec/AVec/NAVec/NAPVec) all share the identical four-word
## `{ base, len, cap, arena }` header. Reading `.len`/`.base` DIRECTLY off a pointer-returning call
## (`da_fvec_value(x).len`) miscompiles to a stale/zero read on the self-host backend, so the branch
## SNAPSHOT (`da_copy`) and JOIN (`da_union_src`) loops must read those header words through an
## explicit `deref` of a captured pointer. `hdr_len`/`hdr_base` bitcast any vec pointer to the shared
## header and return the word by value — the working access pattern. Without this the copy/join loop
## bounds read 0, so every branch snapshot silently dropped all aggregate-leaf entries: a leaf written
## on only ONE arm of an if/else then read AFTER the join was wrongly accepted (uninitialized read).
hdr_len := fn(p : ptr(FVec)) -> usize { deref(p).len }
hdr_base := fn(p : ptr(FVec)) -> usize { deref(p).base }
da_copy := fn(sda : ptr(DA)) -> DA {
  srcd := deref(sda)
  mut dst := da_new(srcd.arena, srcd.cap)
  mut i := 0
  while i < srcd.len {
    sp : ptr(usize) = unchecked bitcast(ptr(usize), srcd.base + i * 16)
    np : ptr(usize) = unchecked bitcast(ptr(usize), srcd.base + i * 16 + 8)
    da_push_root(ptr(dst), deref(sp), deref(np))
    i += 1
  }
  fhp := unchecked bitcast(ptr(FVec), da_fvec_value(srcd))
  fln := hdr_len(fhp)
  fbs := hdr_base(fhp)
  i = 0
  while i < fln {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), fbs + i * 32)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), fbs + i * 32 + 8)
    f0 : ptr(usize) = unchecked bitcast(ptr(usize), fbs + i * 32 + 16)
    f1 : ptr(usize) = unchecked bitcast(ptr(usize), fbs + i * 32 + 24)
    fvec_push(da_fvec_value(dst), deref(r0), deref(r1), deref(f0), deref(f1))
    i += 1
  }
  php := unchecked bitcast(ptr(FVec), da_pvec_value(srcd))
  pln := hdr_len(php)
  pbs := hdr_base(php)
  i = 0
  while i < pln {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), pbs + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), pbs + i * 48 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), pbs + i * 48 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), pbs + i * 48 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), pbs + i * 48 + 32)
    p5 : ptr(usize) = unchecked bitcast(ptr(usize), pbs + i * 48 + 40)
    pvec_push(da_pvec_value(dst), deref(p0), deref(p1), deref(p2), deref(p3), deref(p4), deref(p5))
    i += 1
  }
  ahp := unchecked bitcast(ptr(FVec), da_avec_value(srcd))
  aln := hdr_len(ahp)
  abs := hdr_base(ahp)
  i = 0
  while i < aln {
    a0 : ptr(usize) = unchecked bitcast(ptr(usize), abs + i * 24)
    a1 : ptr(usize) = unchecked bitcast(ptr(usize), abs + i * 24 + 8)
    a2 : ptr(usize) = unchecked bitcast(ptr(usize), abs + i * 24 + 16)
    avec_push(da_avec_value(dst), deref(a0), deref(a1), deref(a2))
    i += 1
  }
  nhp := unchecked bitcast(ptr(FVec), da_navec_value(srcd))
  nln := hdr_len(nhp)
  nbs := hdr_base(nhp)
  i = 0
  while i < nln {
    n0 : ptr(usize) = unchecked bitcast(ptr(usize), nbs + i * 40)
    n1 : ptr(usize) = unchecked bitcast(ptr(usize), nbs + i * 40 + 8)
    n2 : ptr(usize) = unchecked bitcast(ptr(usize), nbs + i * 40 + 16)
    n3 : ptr(usize) = unchecked bitcast(ptr(usize), nbs + i * 40 + 24)
    n4 : ptr(usize) = unchecked bitcast(ptr(usize), nbs + i * 40 + 32)
    navec_push(da_navec_value(dst), deref(n0), deref(n1), deref(n2), deref(n3), deref(n4))
    i += 1
  }
  qhp := unchecked bitcast(ptr(FVec), da_napvec_value(srcd))
  qln := hdr_len(qhp)
  qbs := hdr_base(qhp)
  i = 0
  while i < qln {
    n0 : ptr(usize) = unchecked bitcast(ptr(usize), qbs + i * 56)
    n1 : ptr(usize) = unchecked bitcast(ptr(usize), qbs + i * 56 + 8)
    n2 : ptr(usize) = unchecked bitcast(ptr(usize), qbs + i * 56 + 16)
    n3 : ptr(usize) = unchecked bitcast(ptr(usize), qbs + i * 56 + 24)
    n4 : ptr(usize) = unchecked bitcast(ptr(usize), qbs + i * 56 + 32)
    n5 : ptr(usize) = unchecked bitcast(ptr(usize), qbs + i * 56 + 40)
    n6 : ptr(usize) = unchecked bitcast(ptr(usize), qbs + i * 56 + 48)
    napvec_push(da_napvec_value(dst), deref(n0), deref(n1), deref(n2), deref(n3), deref(n4), deref(n5), deref(n6))
    i += 1
  }
  dst
}
da_union_src := fn(left : ptr(DA), right : ptr(DA), src : ptr(u8)) -> DA {
  lv := deref(left)
  rv := deref(right)
  mut dst := da_new(lv.arena, lv.cap + rv.cap)
  mut i := 0
  while i < lv.len {
    sp : ptr(usize) = unchecked bitcast(ptr(usize), lv.base + i * 16)
    np : ptr(usize) = unchecked bitcast(ptr(usize), lv.base + i * 16 + 8)
    da_push_root(ptr(dst), deref(sp), deref(np))
    i += 1
  }
  i = 0
  while i < rv.len {
    sp2 : ptr(usize) = unchecked bitcast(ptr(usize), rv.base + i * 16)
    np2 : ptr(usize) = unchecked bitcast(ptr(usize), rv.base + i * 16 + 8)
    if not da_has_root(ptr(dst), src, deref(sp2), deref(np2)) { da_push_root(ptr(dst), deref(sp2), deref(np2)) }
    i += 1
  }
  lfhp := unchecked bitcast(ptr(FVec), da_fvec_value(lv))
  lfln := hdr_len(lfhp)
  lfbs := hdr_base(lfhp)
  i = 0
  while i < lfln {
    r0 : ptr(usize) = unchecked bitcast(ptr(usize), lfbs + i * 32)
    r1 : ptr(usize) = unchecked bitcast(ptr(usize), lfbs + i * 32 + 8)
    f0 : ptr(usize) = unchecked bitcast(ptr(usize), lfbs + i * 32 + 16)
    f1 : ptr(usize) = unchecked bitcast(ptr(usize), lfbs + i * 32 + 24)
    fvec_push(da_fvec_value(dst), deref(r0), deref(r1), deref(f0), deref(f1))
    i += 1
  }
  rfhp := unchecked bitcast(ptr(FVec), da_fvec_value(rv))
  rfln := hdr_len(rfhp)
  rfbs := hdr_base(rfhp)
  i = 0
  while i < rfln {
    r2 : ptr(usize) = unchecked bitcast(ptr(usize), rfbs + i * 32)
    r3 : ptr(usize) = unchecked bitcast(ptr(usize), rfbs + i * 32 + 8)
    f2 : ptr(usize) = unchecked bitcast(ptr(usize), rfbs + i * 32 + 16)
    f3 : ptr(usize) = unchecked bitcast(ptr(usize), rfbs + i * 32 + 24)
    if not fvec_has(da_fvec_value(dst), src, deref(r2), deref(r3), deref(f2), deref(f3)) { fvec_push(da_fvec_value(dst), deref(r2), deref(r3), deref(f2), deref(f3)) }
    i += 1
  }
  lphp := unchecked bitcast(ptr(FVec), da_pvec_value(lv))
  lpln := hdr_len(lphp)
  lpbs := hdr_base(lphp)
  i = 0
  while i < lpln {
    p0 : ptr(usize) = unchecked bitcast(ptr(usize), lpbs + i * 48)
    p1 : ptr(usize) = unchecked bitcast(ptr(usize), lpbs + i * 48 + 8)
    p2 : ptr(usize) = unchecked bitcast(ptr(usize), lpbs + i * 48 + 16)
    p3 : ptr(usize) = unchecked bitcast(ptr(usize), lpbs + i * 48 + 24)
    p4 : ptr(usize) = unchecked bitcast(ptr(usize), lpbs + i * 48 + 32)
    p5 : ptr(usize) = unchecked bitcast(ptr(usize), lpbs + i * 48 + 40)
    pvec_push(da_pvec_value(dst), deref(p0), deref(p1), deref(p2), deref(p3), deref(p4), deref(p5))
    i += 1
  }
  rphp := unchecked bitcast(ptr(FVec), da_pvec_value(rv))
  rpln := hdr_len(rphp)
  rpbs := hdr_base(rphp)
  i = 0
  while i < rpln {
    q0 : ptr(usize) = unchecked bitcast(ptr(usize), rpbs + i * 48)
    q1 : ptr(usize) = unchecked bitcast(ptr(usize), rpbs + i * 48 + 8)
    q2 : ptr(usize) = unchecked bitcast(ptr(usize), rpbs + i * 48 + 16)
    q3 : ptr(usize) = unchecked bitcast(ptr(usize), rpbs + i * 48 + 24)
    q4 : ptr(usize) = unchecked bitcast(ptr(usize), rpbs + i * 48 + 32)
    q5 : ptr(usize) = unchecked bitcast(ptr(usize), rpbs + i * 48 + 40)
    if not pvec_has(da_pvec_value(dst), src, deref(q0), deref(q1), deref(q2), deref(q3), deref(q4), deref(q5)) { pvec_push(da_pvec_value(dst), deref(q0), deref(q1), deref(q2), deref(q3), deref(q4), deref(q5)) }
    i += 1
  }
  lahp := unchecked bitcast(ptr(FVec), da_avec_value(lv))
  laln := hdr_len(lahp)
  labs := hdr_base(lahp)
  i = 0
  while i < laln {
    a0 : ptr(usize) = unchecked bitcast(ptr(usize), labs + i * 24)
    a1 : ptr(usize) = unchecked bitcast(ptr(usize), labs + i * 24 + 8)
    a2 : ptr(usize) = unchecked bitcast(ptr(usize), labs + i * 24 + 16)
    avec_push(da_avec_value(dst), deref(a0), deref(a1), deref(a2))
    i += 1
  }
  rahp := unchecked bitcast(ptr(FVec), da_avec_value(rv))
  raln := hdr_len(rahp)
  rabs := hdr_base(rahp)
  i = 0
  while i < raln {
    b0 : ptr(usize) = unchecked bitcast(ptr(usize), rabs + i * 24)
    b1 : ptr(usize) = unchecked bitcast(ptr(usize), rabs + i * 24 + 8)
    b2 : ptr(usize) = unchecked bitcast(ptr(usize), rabs + i * 24 + 16)
    if not avec_has(da_avec_value(dst), src, deref(b0), deref(b1), deref(b2)) { avec_push(da_avec_value(dst), deref(b0), deref(b1), deref(b2)) }
    i += 1
  }
  lnhp := unchecked bitcast(ptr(FVec), da_navec_value(lv))
  lnln := hdr_len(lnhp)
  lnbs := hdr_base(lnhp)
  i = 0
  while i < lnln {
    n0 : ptr(usize) = unchecked bitcast(ptr(usize), lnbs + i * 40)
    n1 : ptr(usize) = unchecked bitcast(ptr(usize), lnbs + i * 40 + 8)
    n2 : ptr(usize) = unchecked bitcast(ptr(usize), lnbs + i * 40 + 16)
    n3 : ptr(usize) = unchecked bitcast(ptr(usize), lnbs + i * 40 + 24)
    n4 : ptr(usize) = unchecked bitcast(ptr(usize), lnbs + i * 40 + 32)
    navec_push(da_navec_value(dst), deref(n0), deref(n1), deref(n2), deref(n3), deref(n4))
    i += 1
  }
  rnhp := unchecked bitcast(ptr(FVec), da_navec_value(rv))
  rnln := hdr_len(rnhp)
  rnbs := hdr_base(rnhp)
  i = 0
  while i < rnln {
    q0 : ptr(usize) = unchecked bitcast(ptr(usize), rnbs + i * 40)
    q1 : ptr(usize) = unchecked bitcast(ptr(usize), rnbs + i * 40 + 8)
    q2 : ptr(usize) = unchecked bitcast(ptr(usize), rnbs + i * 40 + 16)
    q3 : ptr(usize) = unchecked bitcast(ptr(usize), rnbs + i * 40 + 24)
    q4 : ptr(usize) = unchecked bitcast(ptr(usize), rnbs + i * 40 + 32)
    if not navec_has(da_navec_value(dst), src, deref(q0), deref(q1), deref(q2), deref(q3), deref(q4)) { navec_push(da_navec_value(dst), deref(q0), deref(q1), deref(q2), deref(q3), deref(q4)) }
    i += 1
  }
  lqhp := unchecked bitcast(ptr(FVec), da_napvec_value(lv))
  lqln := hdr_len(lqhp)
  lqbs := hdr_base(lqhp)
  i = 0
  while i < lqln {
    n0 : ptr(usize) = unchecked bitcast(ptr(usize), lqbs + i * 56)
    n1 : ptr(usize) = unchecked bitcast(ptr(usize), lqbs + i * 56 + 8)
    n2 : ptr(usize) = unchecked bitcast(ptr(usize), lqbs + i * 56 + 16)
    n3 : ptr(usize) = unchecked bitcast(ptr(usize), lqbs + i * 56 + 24)
    n4 : ptr(usize) = unchecked bitcast(ptr(usize), lqbs + i * 56 + 32)
    n5 : ptr(usize) = unchecked bitcast(ptr(usize), lqbs + i * 56 + 40)
    n6 : ptr(usize) = unchecked bitcast(ptr(usize), lqbs + i * 56 + 48)
    napvec_push(da_napvec_value(dst), deref(n0), deref(n1), deref(n2), deref(n3), deref(n4), deref(n5), deref(n6))
    i += 1
  }
  rqhp := unchecked bitcast(ptr(FVec), da_napvec_value(rv))
  rqln := hdr_len(rqhp)
  rqbs := hdr_base(rqhp)
  i = 0
  while i < rqln {
    q0 : ptr(usize) = unchecked bitcast(ptr(usize), rqbs + i * 56)
    q1 : ptr(usize) = unchecked bitcast(ptr(usize), rqbs + i * 56 + 8)
    q2 : ptr(usize) = unchecked bitcast(ptr(usize), rqbs + i * 56 + 16)
    q3 : ptr(usize) = unchecked bitcast(ptr(usize), rqbs + i * 56 + 24)
    q4 : ptr(usize) = unchecked bitcast(ptr(usize), rqbs + i * 56 + 32)
    q5 : ptr(usize) = unchecked bitcast(ptr(usize), rqbs + i * 56 + 40)
    q6 : ptr(usize) = unchecked bitcast(ptr(usize), rqbs + i * 56 + 48)
    if not napvec_has(da_napvec_value(dst), src, deref(q0), deref(q1), deref(q2), deref(q3), deref(q4), deref(q5), deref(q6)) { napvec_push(da_napvec_value(dst), deref(q0), deref(q1), deref(q2), deref(q3), deref(q4), deref(q5), deref(q6)) }
    i += 1
  }
  dst
}
da_assign := fn(in out dst : DA, src : DA) {
  dst.base = src.base
  dst.len = src.len
  dst.cap = src.cap
  dst.arena = src.arena
  dst.fields = src.fields
  dst.paths = src.paths
  dst.arrays = src.arrays
  dst.nested_arrays = src.nested_arrays
  dst.nested_paths = src.nested_paths
}

## Does an expression read a local that has not yet received a write? This is the conservative linear
## core of Types §9.4. Direct fields and bounded two-level aggregate paths are tracked separately, so a
## partial write never makes an unreadied sibling or enclosing aggregate readable.
da_bad_expr := fn(e : ptr(Expr), da : ptr(DA), src : ptr(u8)) -> bool {
  match deref(e) {
    Expr::Var(s, n) => { da_has_root(da, src, s, n) or da_has_field_root(da, src, s, n) or da_has_path_root(da, src, s, n) or da_has_array_root(da, src, s, n) or navec_has_root(da_navec(da), src, s, n) or da_has_nested_path_root(da, src, s, n) }
    Expr::Bin(op, l, r) => { da_bad_expr(l, da, src) or da_bad_expr(r, da, src) }
    Expr::If(c, t, f) => { da_bad_expr(c, da, src) or da_bad_expr(t, da, src) or da_bad_expr(f, da, src) }
    Expr::Match(sc, ah) => {
      mut bad := da_bad_expr(sc, da, src)
      mut arm := ah
      while arm != 0 {
        am := deref(arm_p(arm))
        if da_bad_expr(am.body, da, src) { bad = true }
        arm = am.next
      }
      bad
    }
    Expr::Call(cs, cl, na, gh) => {
      ## Capability-query operands are checked in a private semantic attempt and do not read runtime state.
      qnm := str_at((src + cs), cl)
      if qnm == "resolves" or qnm == "compiles" { return false }
      mut bad := false
      mut g := gh
      while g != 0 {
        ga := deref(arg_p(g))
        if da_bad_expr(ga.e, da, src) { bad = true }
        g = ga.next
      }
      bad
    }
    Expr::StructLit(cs, cl, nf, gh) => {
      mut bad := false
      mut g := gh
      while g != 0 {
        ga := deref(arg_p(g))
        if da_bad_expr(ga.e, da, src) { bad = true }
        g = ga.next
      }
      bad
    }
    Expr::EnumLit(es, el, vs, vl, np, gh) => {
      mut bad := false
      mut g := gh
      while g != 0 {
        ga := deref(arg_p(g))
        if da_bad_expr(ga.e, da, src) { bad = true }
        g = ga.next
      }
      bad
    }
    Expr::Field(b, fs, fl) => {
      aep := expr_array_elem_nested_path(e)
      if aep.ok {
        aix0 := expr_index_index(expr_field_base(expr_field_base(e)))
        bad_ix0 := da_bad_expr(aix0, da, src)
        if da_has_array(da, src, aep.rs, aep.rn, aep.ix) or da_has_nested_array(da, src, aep.rs, aep.rn, aep.fs, aep.fl, aep.ix) or da_has_nested_path(da, src, aep.rs, aep.rn, aep.fs, aep.fl, aep.ss, aep.sl, aep.ix) { return true }
        return bad_ix0
      }
      anp := expr_array_nested_path(e)
      if anp.ok {
        aix := expr_index_index(expr_field_base(e))
        bad_idx := da_bad_expr(aix, da, src)
        arrb := expr_index_base(expr_field_base(e))
        rvn := expr_var_span(expr_field_base(arrb))
        if rvn.n != 0 {
          if da_has_field(da, src, rvn.s, rvn.n, anp.fs, anp.fl) or navec_has(da_navec(da), src, rvn.s, rvn.n, anp.fs, anp.fl, anp.ix) or da_has_nested_path(da, src, rvn.s, rvn.n, anp.fs, anp.fl, anp.ss, anp.sl, anp.ix) { return true }
          return bad_idx
        }
      }
      ib := expr_index_base(b)
      if unchecked bitcast(usize, ib) != 0 {
        ii := expr_index_index(b)
        rv0 := expr_var_span(ib)
        if rv0.n != 0 and expr_is_num_lit(ii) {
          ivf := expr_num_lit_val(ii)
          if ivf >= 0 {
            bad_elem := da_has_array(da, src, rv0.s, rv0.n, usize(ivf))
            bad_field := da_has_nested_array(da, src, rv0.s, rv0.n, fs, fl, usize(ivf))
            bad_ix := da_bad_expr(ii, da, src)
            return bad_elem or bad_field or bad_ix
          }
        }
      }
      np := expr_nested_path(e)
      if np.sl != 0 {
        da_has_root(da, src, np.rs, np.rn) or da_has_field(da, src, np.rs, np.rn, np.fs, np.fl) or da_has_path(da, src, np.rs, np.rn, np.fs, np.fl, np.ss, np.sl)
      } else {
        bv := expr_var_span(b)
        if bv.n != 0 { da_has_root(da, src, bv.s, bv.n) or da_has_field(da, src, bv.s, bv.n, fs, fl) or da_has_nested_array_field(da, src, bv.s, bv.n, fs, fl) or da_has_nested_path_field(da, src, bv.s, bv.n, fs, fl) or da_has_path_prefix(da, src, bv.s, bv.n, fs, fl) }
        else { da_bad_expr(b, da, src) }
      }
    }
    Expr::AddrOf(p) => { da_bad_expr(p, da, src) }
    Expr::Deref(p) => { da_bad_expr(p, da, src) }
    Expr::ArrayLit(ne, gh) => {
      mut bad := false
      mut g := gh
      while g != 0 {
        ga := deref(arg_p(g))
        if da_bad_expr(ga.e, da, src) { bad = true }
        g = ga.next
      }
      bad
    }
    Expr::Index(b, i) => {
      fb := expr_field_base(b)
      if unchecked bitcast(usize, fb) != 0 and expr_is_num_lit(i) {
        rv := expr_var_span(fb)
        fv := expr_field_span(b)
        iv0 := expr_num_lit_val(i)
        if rv.n != 0 and fv.n != 0 and iv0 >= 0 {
          if da_has_nested_array(da, src, rv.s, rv.n, fv.s, fv.n, usize(iv0)) or da_has_nested_path_index(da, src, rv.s, rv.n, fv.s, fv.n, usize(iv0)) { return true }
          ## A tracked nested array field is only partially initialized. The exact element above is
          ## readable when its unreadied marker was removed, even though reading the whole field remains
          ## invalid. Do not recurse through `b` here, because `da_bad_expr(Field(root, field))` quite
          ## correctly rejects that whole-field read. The index expression itself is still checked.
          if da_has_nested_array_field(da, src, rv.s, rv.n, fv.s, fv.n) { return da_bad_expr(i, da, src) }
          return da_bad_expr(b, da, src) or da_bad_expr(i, da, src)
        }
      }
      bv := expr_var_span(b)
      if bv.n != 0 and expr_is_num_lit(i) {
        iv := expr_num_lit_val(i)
        whole_bad := da_has_array(da, src, bv.s, bv.n, usize(iv))
          field_bad := navec_has_root_index(da_navec(da), src, bv.s, bv.n, usize(iv))
          if iv >= 0 { return whole_bad or field_bad }
      }
      da_bad_expr(b, da, src) or da_bad_expr(i, da, src)
    }
    Expr::Try(inner) => { da_bad_expr(inner, da, src) }
    Expr::Slice(b, lo, hi) => { da_bad_expr(b, da, src) or da_bad_expr(lo, da, src) or da_bad_expr(hi, da, src) }
    Expr::CompField(b, i) => { da_bad_expr(b, da, src) or da_bad_expr(i, da, src) }
    Expr::Unchecked(inner) => { da_bad_expr(inner, da, src) }
    Expr::Bitcast(inner, ts, tl) => { da_bad_expr(inner, da, src) }
    Expr::Loop(b) => { false }
    _ => { false }
  }
}

check_expr_da_mode := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize, da : ptr(DA), allow_root_enum_array : bool) -> Result(Ty, CheckErr) {
  egab := sema_enum_global_array_value_bad(e, decls, upto, src, locals, nloc, a, allow_root_enum_array)
  if egab != 0 { return Result(Ty, CheckErr).Err(enum_global_array_err(egab)) }
  s3abad := s3a_expr_bad(e, decls, upto, src, a, locals, nloc)
  if s3abad != 0 { return Result(Ty, CheckErr).Err(located_err(s3abad)) }
  if da_bad_expr(e, da, src) { return Result(Ty, CheckErr).Err(unbound_code(e, decls, upto, src, a, locals, nloc)) }
  bad_capture := sema_plain_fn_capture_struct(e, decls, upto, src, locals, nloc, a)
  if bad_capture != 0 { return Result(Ty, CheckErr).Err(mismatch_err(bad_capture, 0)) }
  check_expr(e, decls, upto, src, a, locals, nloc)
}
check_expr_da := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize, da : ptr(DA)) -> Result(Ty, CheckErr) {
  check_expr_da_mode(e, decls, upto, src, a, locals, nloc, da, false)
}
## A direct enum-array element is a supported WHOLE-VALUE place only at the root of an inferred
## binding (`e := GE[i]`) or a match scrutinee. Nested consumers and typed/reassigned bindings still
## run the ordinary value-position fence.
check_expr_da_allow_enum_array_root := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize, da : ptr(DA)) -> Result(Ty, CheckErr) {
  check_expr_da_mode(e, decls, upto, src, a, locals, nloc, da, true)
}
## Poison the check: set the sticky failure bit, and — the first time a LOCATED code arrives (a
## `CheckErr` whose source span `code / 4` is nonzero) — record it in `fspan` so the diagnostic can
## name the line. A span-less code (`code / 4 == 0`) only flips the sticky bit, as before.
mark_failed := fn(locals : ptr(LVec), code : CheckErr) {
  lv := deref(locals)
  old := deref(lv.failed)
  if old % 2 == 0 { deref(lv.failed) = old + 1 }
  if deref(lv.fspan) == 0 and code / 4 != 0 { deref(lv.fspan) = code }
}
lvec_push := fn(in out v : LVec, x : Local) {
  st := lvec_stride()
  if v.len >= v.cap {
    new_cap := v.cap * 2
    noff := node_alloc(deref(v.arena), new_cap * st)
    nbase := unchecked bitcast(usize, deref(v.arena).base) + noff
    nwords := (v.len * st) / 8
    mut k := 0
    while k < nwords {
      sp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), v.base + k * 8)
      dp : ptr(mut usize) = unchecked bitcast(ptr(mut usize), nbase + k * 8)
      deref(dp) = deref(sp)
      k += 1
    }
    v.base = nbase
    v.cap = new_cap
  }
  p : ptr(mut Local) = unchecked bitcast(ptr(mut Local), v.base + v.len * st)
  deref(p) = x
  v.len = v.len + 1
  ## REMEMBER this binding's name function-wide (survives arm/branch truncation) — see LVec/`remembered`.
  lvec_remember(v, x.ns, x.nl)
}
lvec_at := fn(v : ptr(LVec), i : usize) -> Local {
  p : ptr(Local) = unchecked bitcast(ptr(Local), deref(v).base + i * lvec_stride())
  return deref(p)
}
## Drop the vector back to `n` entries (a no-op if already ≤ n). Used to POP an arm-scoped set of
## match-pattern bindings after checking that arm, so the next arm's `lvec_push` reuses the slots and
## the caller's `cnt` (which mirrors `v.len`) stays in lockstep — else a later push lands beyond `cnt`.
lvec_truncate := fn(in out v : LVec, n : usize) {
  if v.len > n { v.len = n }
}

## Resolve a type-annotation span `[ts, ts+tl)` to a `Ty`. A scalar is recognized by lexeme
## (`u64`/`usize`/`i64`/`i32`/`u32`/`u8` → int; `bool` → bool); otherwise the name is matched
## against the program's struct/enum declarations (a kind-2 `Decl` → struct, kind-3 → enum).
## An unrecognized name (or 0/0 = no annotation) yields unknown (tag 0).
## Scan a `ptr(mut? T)` annotation (whose `ptr` lexeme is at [ts, ts+tl)) for its pointee type NAME,
## returning that name's span ONLY when it is a KNOWN struct/enum decl. A qualified (`rt::Vec`), scalar
## (`usize`), or generic-parameter (`T`) pointee is not matched → {0,0} = unknown, treated as compatible
## with anything (so the ptr-target check stays conservative and never false-rejects). The pointee text
## sits right after the `ptr` lexeme: `( [mut ] NAME )`.
ptr_pointee_span := fn(src : ptr(u8), ts : usize, tl : usize, decls : ptr(rt::Vec), ncnt : usize) -> VSpan {
  ## scan from RIGHT AFTER the 3-char `ptr` keyword — the annotation span `tl` may cover either just
  ## `ptr` or the whole `ptr(mut T)`, so `ts + 3` is the reliable start of the `( … )` pointee clause.
  mut p := ts + 3
  while str_at((src + p), 1) == " " { p = p + 1 }
  if str_at((src + p), 1) != "(" { return VSpan(s = 0, n = 0) }
  p = p + 1
  while str_at((src + p), 1) == " " { p = p + 1 }
  if str_at((src + p), 4) == "mut " { p = p + 4 }
  while str_at((src + p), 1) == " " { p = p + 1 }
  ns2 := p
  mut scanning := true
  while scanning {
    c := str_at((src + p), 1)
    stop := c == " " or c == ")" or c == "," or c == "("
    if stop { scanning = false } else { p = p + 1 }
  }
  nl2 := p - ns2
  if nl2 == 0 { return VSpan(s = 0, n = 0) }
  mut r := VSpan(s = 0, n = 0)
  cnt := rt::vec_len(deref(decls))
  th := sema_name_hash(src, ns2, nl2)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < ncnt and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
      d := deref(decl_get(decls, i))
      kok := d.kind == 2 or d.kind == 3
      if kok and streq(src, d.name_start, d.name_len, ns2, nl2) { r = VSpan(s = ns2, n = nl2) }
    }
  }
  return r
}

resolve_ty := fn(src : ptr(u8), ts : usize, tl : usize, decls : ptr(rt::Vec), ncnt : usize) -> Ty {
  mut r := Ty(tag = 0, ns = 0, nl = 0)
  if tl == 0 { return r }
  w := str_at((src + ts), tl)
  if w == "u64" or w == "usize" or w == "i64" or w == "i32" or w == "u32" or w == "u8" or w == "isize" {
    r = Ty(tag = 1, ns = ts, nl = tl)
    return r
  }
  if w == "bool" { r = Ty(tag = 2, ns = ts, nl = tl); return r }
  if w == "str" { r = Ty(tag = 6, ns = ts, nl = tl); return r }
  ## Fixed arrays retain their complete annotation span so DA can recover the element count and track
  ## comptime-constant element places. The runtime layout remains the existing word-granular array path.
  if str_at((src + ts), 1) == "[" { r = Ty(tag = 7, ns = ts, nl = tl); return r }
  ## A pointer-typed parameter `p : ptr(mut T)` is captured by the parser as a type annotation whose
  ## lexeme is `ptr` (the head of the `ptr(...)` form) — resolve it to the pointer type (tag 5), and
  ## record its POINTEE type name in ns/nl when it is a known struct/enum (else {0,0} = unknown). This
  ## is what lets `ty_compat` discriminate `ptr(Arg)` from `ptr(Expr)` (ptr-typing dogfood).
  is_ptr := w == "ptr" or str_at((src + ts), 4) == "ptr("
  if is_ptr {
    sp := ptr_pointee_span(src, ts, tl, decls, ncnt)
    r = Ty(tag = 5, ns = sp.s, nl = sp.n)
    return r
  }
  ## Resolve the base spelling first (`Result(u64, E)` → `Result`), then follow one ordinary
  ## type-alias hop. The returned span is the nominal target declaration, so `C := Color` and
  ## `Color` produce the same identity instead of two unrelated aggregate names.
  bn := base_type_name(src, ts, tl)
  mut alias_ts := 0
  mut alias_tl := 0
  for i in 0..ncnt {
    d := deref(decl_get(decls, i))
    if (d.kind == 2 or d.kind == 3) and streq(src, d.name_start, d.name_len, bn.s, bn.n) {
      if d.kind == 2 { r = Ty(tag = 3, ns = d.name_start, nl = d.name_len) }
      if d.kind == 3 { r = Ty(tag = 4, ns = d.name_start, nl = d.name_len) }
    }
    if d.kind == 0 and streq(src, d.name_start, d.name_len, bn.s, bn.n) {
      if d.ret_tl != 0 { alias_ts = d.ret_ts; alias_tl = d.ret_tl }
      else if d.alias_tl != 0 {
        ah := base_type_name(src, d.alias_ts, d.alias_tl)
        alias_ts = ah.s; alias_tl = ah.n
      }
    }
  }
  if r.tag == 0 and alias_tl != 0 {
    at := base_type_name(src, alias_ts, alias_tl)
    mut j := 0
    while j < ncnt {
      d := deref(decl_get(decls, j))
      if (d.kind == 2 or d.kind == 3) {
        target := name_tail(src, at.s, at.n)
        if streq(src, d.name_start, d.name_len, target.s, target.n) {
          if d.kind == 2 { r = Ty(tag = 3, ns = d.name_start, nl = d.name_len) }
          if d.kind == 3 { r = Ty(tag = 4, ns = d.name_start, nl = d.name_len) }
        }
      }
      j += 1
    }
  }
  r
}

## True if `e` is a `Var` naming a PRELUDE namespace / enum type used in `.variant` / `.field` position
## (`Ordering.acquire`, `Arch.x86_64`, `target.arch`, `verify.checked`). Such a base is a type/namespace,
## not a bindable value — so a `base.f` field access on it must NOT be checked as a value read (else
## `check` rejects every valid `atomic`/`comptime`-arch program that `build` accepts — a check/build
## parity bug, §1 item 5). A fn-body match (the lowerable shape — avoids a nested `match … return`).
is_prelude_ns_var := fn(e : ptr(Expr), src : ptr(u8)) -> bool {
  match deref(e) {
    Expr::Var(s, n) => {
      nm := str_at((src + s), n)
      nm == "Ordering" or nm == "Arch" or nm == "target" or nm == "verify" or nm == "build"
    }
    _ => { false }
  }
}
## Is the name [s, s+n) declared among the first `upto` bindings (the prefix in scope)?
declared := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize) -> bool {
  for i in 0..upto {
    d := deref(decl_get(decls, i))
    if streq(src, d.name_start, d.name_len, s, n) { return true }
  }
  false
}

## PERF (sema hot path — `name_matches` was ~7.5% of self-build time): a per-decl NAME HASH pre-filters
## the O(cnt) `name_matches` scans (mirrors the lower's DNH). `SDNH[i]` = FNV-1a of decl `i`'s name;
## a scan compares the target call's TAIL-segment hash (what `name_matches` matches a decl name against)
## to `SDNH[i]` and only pays `decl_get` + `name_matches` on a hash MATCH. `name_matches` stays the
## arbiter, so a collision merely skips the skip → identical resolution (the sema pass reports the same
## diagnostics; the compiler's OUTPUT is unchanged / fixpoint-neutral). Built once at `check_program`.
mut SDNH : usize = 0
mut SDNH_N : usize = 0
sema_name_hash := fn(src : ptr(u8), s : usize, n : usize) -> usize {
  w := str_at((src + s), n)
  mut h := 1469598103934665603
  mut i := 0
  while i < n {
    unchecked { h = (h ^ usize(bytes(w)[i])) * 1099511628211 }
    i = i + 1
  }
  h
}
## Hash of the call's TAIL segment (after the last `::`) — exactly the span `name_matches` compares a decl
## name against (for an unqualified call the tail IS the whole name). The pre-filter compares this to the
## decl-name hash in `SDNH`.
sema_tail_hash := fn(src : ptr(u8), cs : usize, cn : usize) -> usize {
  mut i := 0
  mut tail := cs
  while i + 1 < cn {
    if str_at((src + cs + i), 2) == "::" { tail = cs + i + 2 }
    i += 1
  }
  sema_name_hash(src, tail, cn - (tail - cs))
}
## PERF (name→decl INDEX, perf 2026-08-15): `SDNH` made each `name_matches` scan cheaper but left it
## O(decls). `SNI` is the sema twin of the lower's `DNI`: a bucketed (CSR) map from a decl-name hash to
## the decl indices carrying it. `SNI_B` holds `SNI_NB + 1` bucket boundaries, `SNI_L` the `SNI_N` decl
## indices grouped by bucket and kept in INCREASING order within a bucket, so a candidate walk visits the
## same decls in the same ORDER as the full scan (last-match resolution unchanged). `name_matches`/`streq`
## stay the ARBITER — the index only NARROWS the candidate set. Not live (`SNI_N != cnt`, e.g. decls grew
## after the build) ⇒ the cursors degrade to `[0, cnt)` and `sni_at` is the identity: the original scan.
mut SNI_B : usize = 0
mut SNI_L : usize = 0
mut SNI_NB : usize = 0
mut SNI_N : usize = 0
## The `@limits(…)` decl LIST — `module_declares_limit` keys on the MODULE name, not the decl name, so
## the name index cannot narrow it; the `kind 0 / arity 99 / ret_tl != 0` decls are a handful, so walking
## just their indices (ascending, same predicate) replaces an O(decls) scan.
mut SLIM_L : usize = 0
mut SLIM_N : usize = 0
sni_live := fn(cnt : usize) -> bool { SNI_B != 0 and SNI_N == cnt }
sni_lo := fn(cnt : usize, th : usize) -> usize {
  if sni_live(cnt) == false { return 0 }
  rt::rec_get(unchecked bitcast(ptr(mut u8), SNI_B), th & (SNI_NB - 1))
}
sni_hi := fn(cnt : usize, th : usize) -> usize {
  if sni_live(cnt) == false { return cnt }
  rt::rec_get(unchecked bitcast(ptr(mut u8), SNI_B), (th & (SNI_NB - 1)) + 1)
}
sni_at := fn(cnt : usize, j : usize) -> usize {
  if sni_live(cnt) == false { return j }
  rt::rec_get(unchecked bitcast(ptr(mut u8), SNI_L), j)
}
slim_hi := fn(cnt : usize) -> usize {
  if SLIM_L == 0 or SNI_N != cnt { return cnt }
  SLIM_N
}
slim_at := fn(cnt : usize, j : usize) -> usize {
  if SLIM_L == 0 or SNI_N != cnt { return j }
  rt::rec_get(unchecked bitcast(ptr(mut u8), SLIM_L), j)
}
build_sema_dnh := fn(decls : ptr(rt::Vec), src : ptr(u8), in out a : rt::Arena) {
  cnt := rt::vec_len(deref(decls))
  base := rt::bump(a, cnt * 8 + 8)
  mut nlim := 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    rt::rec_set(unchecked bitcast(ptr(mut u8), base), i, sema_name_hash(src, d.name_start, d.name_len))
    if d.kind == 0 and d.arity == 99 and d.ret_tl != 0 { nlim = nlim + 1 }
    i = i + 1
  }
  SDNH = base
  SDNH_N = cnt
  ## bucket count = the smallest power of two ≥ 2·cnt (load factor ≤ 0.5), floor 64
  mut nb := 64
  while nb < cnt * 2 { nb = nb * 2 }
  bb := rt::bump(a, nb * 8 + 16)
  cur := rt::bump(a, nb * 8 + 16)
  lb := rt::bump(a, cnt * 8 + 8)
  mut b := 0
  while b < nb + 1 {
    rt::rec_set(unchecked bitcast(ptr(mut u8), bb), b, 0)
    rt::rec_set(unchecked bitcast(ptr(mut u8), cur), b, 0)
    b = b + 1
  }
  ## COUNT into slot `bucket + 1`, so the inclusive prefix leaves `bb[b]` = bucket `b`'s START.
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
  ## FILL in increasing decl order → each bucket's slice is ascending, preserving scan order.
  i = 0
  while i < cnt {
    h := rt::rec_get(unchecked bitcast(ptr(mut u8), base), i) & (nb - 1)
    p := rt::rec_get(unchecked bitcast(ptr(mut u8), bb), h) + rt::rec_get(unchecked bitcast(ptr(mut u8), cur), h)
    rt::rec_set(unchecked bitcast(ptr(mut u8), lb), p, i)
    rt::rec_set(unchecked bitcast(ptr(mut u8), cur), h, rt::rec_get(unchecked bitcast(ptr(mut u8), cur), h) + 1)
    i = i + 1
  }
  SNI_B = bb
  SNI_L = lb
  SNI_NB = nb
  SNI_N = cnt
  limb := rt::bump(a, nlim * 8 + 8)
  mut k := 0
  i = 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 0 and d.arity == 99 and d.ret_tl != 0 {
      rt::rec_set(unchecked bitcast(ptr(mut u8), limb), k, i)
      k = k + 1
    }
    i = i + 1
  }
  SLIM_L = limb
  SLIM_N = k
}
## True if a decl name `[dns,dnl)` matches a callee span `[cs,cn)` — either exactly, or as the TAIL
## after the last `::` (a qualified call `mod::sub::f` resolves to the decl named `f`, mirroring the
## lower). Without it `check` treats every qualified call as unresolved. Unqualified names (no `::`)
## fall back to the exact compare, so a plain call is unchanged (negative arity/name tests unaffected).
name_matches := fn(src : ptr(u8), dns : usize, dnl : usize, cs : usize, cn : usize) -> bool {
  if streq(src, dns, dnl, cs, cn) { return true }
  mut i := 0
  mut tail := cs
  while i + 1 < cn {
    if str_at((src + cs + i), 2) == "::" { tail = cs + i + 2 }
    i += 1
  }
  if tail == cs { return false }
  streq(src, dns, dnl, tail, cs + cn - tail)
}
## True if the module name `[ms,ms+ml)` is an AMBIENT-STDLIB module — its mangled name carries the
## `dir__stem` path double-underscore (`base__assert`, `std__fmt`, `alloc__vec`). `check` VERIFIES the
## user's modules but TRUSTS the stdlib (separately built + verified): it keeps lib decls for name/type
## RESOLUTION but does not re-`check_decl` them, so a check-gap on a stdlib feature (generics, comptime,
## …) never rejects a well-typed USER program — the intended check/build parity (§1 item 5). A
## single-`_` user module (`print_one`) is not matched; the fixpoint is unaffected (`check` isn't in the
## build path).
is_lib_module := fn(src : ptr(u8), ms : usize, ml : usize) -> bool {
  if ml < 2 { return false }
  mut i := 0
  while i + 1 < ml {
    if str_at((src + ms + i), 2) == "__" { return true }
    i += 1
  }
  false
}
## GENERICS tier: is the callee `[s, s+n)` a GENERIC fn (its first param `T : type`)? Its
## first call argument is then the COMPTIME TYPE argument (an ident naming a type) — NOT a
## value expression, so the checker skips it (a type name is not a local/decl). Mirrors lower's
## `generic_decl_of`. Resolves by tail name so a qualified `mod::f(T, …)` is recognized too.
## Searches the WHOLE decl list, not just `[0..upto)` — a generic callee may be declared LATER
## (use-before-decl, mirroring `callee_declared_anywhere`) OR be a driver-SYNTHESIZED generic clone
## (`__hoflam<fnpos>`, FN-6 §6.2) appended AFTER the caller. Missing it would treat the call as
## non-generic and check its type-arg (`u64`) as a value → a false "unbound name".
callee_is_generic := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize) -> bool {
  mut res := false
  cnt := rt::vec_len(deref(decls))
  th := sema_tail_hash(src, s, n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th {
      d := deref(decl_get(decls, i))
      if d.kind == 1 and d.is_generic and name_matches(src, d.name_start, d.name_len, s, n) { res = true }
    }
  }
  res
}

## Is the `pidx`-th parameter of the generic fn named [s, s+n) a COMPTIME TYPE parameter (`T : type`)?
## The matching call argument is then a type NAME, not a value, so the checker must SKIP it. Type
## params are NOT always leading (`gf(in out s : P, T : type, k)` puts `T` at index 1), so the skip
## is POSITIONAL, not a leading-count — arg `i` is skipped iff param `i` has type text `type`.
callee_param_is_type := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize, pidx : usize, a : ptr(mut rt::Arena)) -> bool {
  mut r := false
  cnt := rt::vec_len(deref(decls))
  th := sema_tail_hash(src, s, n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th {
      d := deref(decl_get(decls, i))
      if d.kind == 1 and d.is_generic and name_matches(src, d.name_start, d.name_len, s, n) {
        mut pp := d.params_head
        mut k := 0
        while pp != 0 {
          pm := deref(param_p(pp))
          if k == pidx and str_at((src + pm.ts), pm.tl) == "type" { r = true }
          k += 1
          pp = pm.next
        }
      }
    }
  }
  r
}

## Find the struct/enum `Decl` whose name is [s, s+n) among the first `upto` bindings; returns
## its index + 1 (0 = not found, so a `usize` doubles as found?). Used to resolve a struct
## literal's type and to look up a field's declared type.
type_decl_index := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize) -> usize {
  cnt := rt::vec_len(deref(decls))
  mut alias_ts := 0
  mut alias_tl := 0
  th := sema_name_hash(src, s, n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < upto and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
      d := deref(decl_get(decls, i))
      if streq(src, d.name_start, d.name_len, s, n) {
        if d.kind == 2 or d.kind == 3 { return i + 1 }
        if d.kind == 0 {
          if d.ret_tl != 0 { alias_ts = d.ret_ts; alias_tl = d.ret_tl }
          else if d.alias_tl != 0 {
            ah := base_type_name(src, d.alias_ts, d.alias_tl)
            alias_ts = ah.s; alias_tl = ah.n
          }
        }
      }
    }
  }
  if alias_tl != 0 {
    at := name_tail(src, alias_ts, alias_tl)
    mut j := 0
    while j < upto {
      d := deref(decl_get(decls, j))
      if (d.kind == 2 or d.kind == 3) and streq(src, d.name_start, d.name_len, at.s, at.n) { return j + 1 }
      j += 1
    }
  }
  0
}

## Reject an alias-of-alias before the lower can treat the second name as an ordinary value. The
## identity slice deliberately follows one hop only (`C := Color`, `R := Result(...)`); a second
## alias would otherwise parse as a field/UFCS expression and can silently select the wrong enum
## arm. Keep the diagnostic located at the unsupported RHS, and leave ordinary value aliases whose
## target is a function/value untouched.
sema_type_alias_chain_reject := fn(d : Decl, decls : ptr(rt::Vec), upto : usize, src : ptr(u8)) -> usize {
  if d.kind != 0 or d.arity != 0 { return 0 }
  mut ts := 0
  mut tl := 0
  if d.ret_tl != 0 { ts = d.ret_ts; tl = d.ret_tl }
  else if d.alias_tl != 0 { ts = d.alias_ts; tl = d.alias_tl }
  if tl == 0 { return 0 }
  target := base_type_name(src, ts, tl)
  if target.n == 0 { return 0 }
  mut i := 0
  while i < upto {
    td := deref(decl_get(decls, i))
    if td.kind == 0 and td.name_len != 0 and streq(src, td.name_start, td.name_len, target.s, target.n) {
      if td.ret_tl != 0 or td.alias_tl != 0 {
        if ts != 0 { return located_err(ts) }
        return located_err(d.name_start)
      }
    }
    i += 1
  }
  0
}

## The declared `Ty` of field [fs, fl) within a struct/enum decl `d` (its `fields_head` list);
## unknown (tag 0) if the field is absent. Resolves the field's captured type span (`ts`/`tl`)
## to a `Ty`. (The deref-walk over the arena list stays in this helper — `a` is a direct param.)
field_ty := fn(d : Decl, src : ptr(u8), fs : usize, fl : usize, decls : ptr(rt::Vec), upto : usize, a : ptr(mut rt::Arena)) -> Ty {
  mut r := Ty(tag = 0, ns = 0, nl = 0)
  mut f := d.fields_head
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, fs, fl) { r = resolve_ty(src, fd.ts, fd.tl, decls, upto) }
    f = fd.next
  }
  r
}

## A name in scope while checking a fn body: a parameter or a local statement binding, with
## its synthesized type (so a `Var` reference resolves the name AND its `Ty`).
pub Local := struct { ns : usize, nl : usize, tag : u8, prov : u8, tns : usize, tnl : usize }

## The `Ty` of the local named [s, s+n) among the first `nloc` locals; tag 99 in the returned
## `Ty` is impossible — instead the bool result distinguishes found. Returns the found local's
## `Ty` via the out param shape: we return a `Ty` and use tag-found via a sentinel. To keep it
## simple and pointer-free, `local_ty` returns a `Ty` whose tag is 255 when NOT found.
local_ty := fn(locals : ptr(LVec), upto : usize, src : ptr(u8), s : usize, n : usize) -> Ty {
  mut r := Ty(tag = 255, ns = 0, nl = 0)
  mut i := 0
  while i < upto {
    l := lvec_at(locals, i)
    if streq(src, l.ns, l.nl, s, n) {
      r = Ty(tag = l.tag, ns = l.tns, nl = l.tnl)
    }
    i += 1
  }
  r
}

## Provenance of a local pointer value relevant to a lower-side build fence. `prov == 1` means the
## pointer was taken from a FIELD place (`ptr(mut o.inner)`), not from the containing struct local. The
## lower can address the latter's fields but cannot yet recover the inner field's layout on a later
## `deref(p).f = v`; keeping this one bit in the existing local record mirrors that exact lost fact.
local_prov := fn(locals : ptr(LVec), upto : usize, src : ptr(u8), s : usize, n : usize) -> u8 {
  mut r : u8 = 0
  mut i := 0
  while i < upto {
    l := lvec_at(locals, i)
    if streq(src, l.ns, l.nl, s, n) { r = l.prov }
    i += 1
  }
  r
}

## Is the name [s, s+n) one of the locals (params + prior body bindings) collected so far?
local_in := fn(locals : ptr(LVec), upto : usize, src : ptr(u8), s : usize, n : usize) -> bool {
  for i in 0..upto {
    l := lvec_at(locals, i)
    if streq(src, l.ns, l.nl, s, n) { return true }
  }
  false
}

## Whether a local record is a COMPTIME binding rather than a runtime value. The parser erases both
## `comptime N` and the `: type` marker from `Param`, so recover the two source spellings here. Type
## parameters (`T : type`) and comptime value parameters (`comptime N : u64`) are valid in a foldable
## condition and must not be mistaken for runtime locals; ordinary body bindings remain runtime values.
sema_local_is_comptime := fn(src : ptr(u8), l : Local) -> bool {
  if param_is_comptime(src, l.ns) { return true }
  mut p := l.ns + l.nl
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p += 1 }
  if str_at((src + p), 1) != ":" { return false }
  p += 1
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p += 1 }
  if str_at((src + p), 4) != "type" { return false }
  c := str_at((src + p + 4), 1)
  c == " " or c == "\n" or c == "\t" or c == "\r" or c == ")" or c == ","
}

## The [s, s+n) name span of a `Var` expression (0/0 otherwise). A SMALL inline `match deref(e)`: the
## big `match deref(e)` in `check_expr` uses the bound-deref form (`node := deref(e); match node`),
## which does NOT dispatch the payload-heavy `Var` arm under the seed (scar #2 — a large multi-word-enum
## match). This accessor recovers the span so `check_expr` resolves a local Var's type before that match.
VSpan := struct { s : usize, n : usize }
expr_var_span := fn(e : ptr(Expr)) -> VSpan {
  match deref(e) {
    Expr::Var(s, n) => { VSpan(s = s, n = n) }
    _ => { VSpan(s = 0, n = 0) }
  }
}

## Peel a nested-field PLACE (`Field(Field(…Var(g)…, a), b)`) to its ROOT variable's name span — the
## aggregate the whole path ultimately stores INTO. Recurses down the `Field` chain; {0,0} if the root
## is not a plain Var. Used by the store-escape check to identify a `FieldPathAssign`'s outliving base.
field_path_root_var := fn(e : ptr(Expr)) -> VSpan {
  match deref(e) {
    Expr::Var(s, n) => { VSpan(s = s, n = n) }
    Expr::Field(base, fs, fl) => { field_path_root_var(base) }
    _ => { VSpan(s = 0, n = 0) }
  }
}

## The spans of a bounded two-level field path `root.first.second`; {0,0,0,0,0,0} for any other place.
NestedPath := struct { rs : usize, rn : usize, fs : usize, fl : usize, ss : usize, sl : usize }
expr_field_base := fn(e : ptr(Expr)) -> ptr(Expr) {
  match deref(e) {
    Expr::Field(base, fs, fl) => { base }
    _ => { unchecked bitcast(ptr(Expr), 0) }
  }
}
expr_field_span := fn(e : ptr(Expr)) -> VSpan {
  match deref(e) {
    Expr::Field(base, fs, fl) => { VSpan(s = fs, n = fl) }
    _ => { VSpan(s = 0, n = 0) }
  }
}
expr_addr_inner := fn(e : ptr(Expr)) -> ptr(Expr) {
  match deref(e) {
    Expr::AddrOf(inner) => { inner }
    _ => { unchecked bitcast(ptr(Expr), 0) }
  }
}
field_path_deref_var := fn(e : ptr(Expr)) -> VSpan {
  match deref(e) {
    Expr::Field(base, fs, fl) => { field_path_deref_var(base) }
    Expr::Deref(inner) => { expr_var_span(inner) }
    _ => { VSpan(s = 0, n = 0) }
  }
}
expr_index_base := fn(e : ptr(Expr)) -> ptr(Expr) {
  match deref(e) {
    Expr::Index(base, ix) => { base }
    _ => { unchecked bitcast(ptr(Expr), 0) }
  }
}
expr_index_index := fn(e : ptr(Expr)) -> ptr(Expr) {
  match deref(e) {
    Expr::Index(base, ix) => { ix }
    _ => { unchecked bitcast(ptr(Expr), 0) }
  }
}
expr_nested_path := fn(e : ptr(Expr)) -> NestedPath {
  mut z := NestedPath(rs = 0, rn = 0, fs = 0, fl = 0, ss = 0, sl = 0)
  mid := expr_field_base(e)
  if unchecked bitcast(usize, mid) == 0 { return z }
  outer := expr_field_span(e)
  inner := expr_field_span(mid)
  root := expr_field_base(mid)
  if unchecked bitcast(usize, root) == 0 { return z }
  rv := expr_var_span(root)
  if rv.n != 0 and inner.n != 0 and outer.n != 0 { z = NestedPath(rs = rv.s, rn = rv.n, fs = inner.s, fl = inner.n, ss = outer.s, sl = outer.n) }
  z
}

## The spans of a constant-index aggregate-array leaf path `root.array[index].field` where the array
## itself is a struct field. This is intentionally one bounded tier: a non-literal index or any deeper
## chain returns `ok = false` and remains conservative in DA.
ArrayNestedPath := struct { ok : bool, rs : usize, rn : usize, fs : usize, fl : usize, ss : usize, sl : usize, ix : usize }
expr_array_nested_path := fn(e : ptr(Expr)) -> ArrayNestedPath {
  mut z := ArrayNestedPath(ok = false, rs = 0, rn = 0, fs = 0, fl = 0, ss = 0, sl = 0, ix = 0)
  leafbase := expr_field_base(e)
  if unchecked bitcast(usize, leafbase) == 0 { return z }
  ixexpr := expr_index_index(leafbase)
  if unchecked bitcast(usize, ixexpr) == 0 or not expr_is_num_lit(ixexpr) { return z }
  iv := expr_num_lit_val(ixexpr)
  if iv < 0 { return z }
  arrfield := expr_index_base(leafbase)
  if unchecked bitcast(usize, arrfield) == 0 { return z }
  root := expr_field_base(arrfield)
  if unchecked bitcast(usize, root) == 0 { return z }
  rv := expr_var_span(root)
  af := expr_field_span(arrfield)
  lf := expr_field_span(e)
  if rv.n != 0 and af.n != 0 and lf.n != 0 { z = ArrayNestedPath(ok = true, rs = rv.s, rn = rv.n, fs = af.s, fl = af.n, ss = lf.s, sl = lf.n, ix = usize(iv)) }
  z
}

## The spans of a constant-index local-array element leaf path `root[index].field.leaf`.
## This is distinct from `root.array_field[index].leaf` above: the index is applied to the root
## array, then a nested aggregate field is selected inside that element. Non-literal indices and
## deeper shapes return `ok = false` so they remain conservative/fail-loud under Types §9.4.
expr_array_elem_nested_path := fn(e : ptr(Expr)) -> ArrayNestedPath {
  mut z := ArrayNestedPath(ok = false, rs = 0, rn = 0, fs = 0, fl = 0, ss = 0, sl = 0, ix = 0)
  mid := expr_field_base(e)
  if unchecked bitcast(usize, mid) == 0 { return z }
  idx := expr_field_base(mid)
  if unchecked bitcast(usize, idx) == 0 { return z }
  ixexpr := expr_index_index(idx)
  if unchecked bitcast(usize, ixexpr) == 0 or not expr_is_num_lit(ixexpr) { return z }
  iv := expr_num_lit_val(ixexpr)
  if iv < 0 { return z }
  root := expr_index_base(idx)
  if unchecked bitcast(usize, root) == 0 { return z }
  rv := expr_var_span(root)
  mf := expr_field_span(mid)
  lf := expr_field_span(e)
  if rv.n != 0 and mf.n != 0 and lf.n != 0 { z = ArrayNestedPath(ok = true, rs = rv.s, rn = rv.n, fs = mf.s, fl = mf.n, ss = lf.s, sl = lf.n, ix = usize(iv)) }
  z
}

## The callee NAME span of a direct `Call` (`{s,n}`), else `{0,0}` — a standalone single-level accessor.
## Lets the `Assign` binding recover a call-value's un-truncated RETURN-TYPE name via `callee_ret_ty`
## (the packed `Result(Ty,CheckErr)` from `check_expr` keeps the tag but drops the type-name ns/nl, so a
## call-created local otherwise records no resolvable type — the root of the exhaustiveness/@owning gap).
expr_call_callee_span := fn(e : ptr(Expr)) -> VSpan {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => { VSpan(s = cs, n = cl) }
    _ => { VSpan(s = 0, n = 0) }
  }
}

## The args-list head (arena handle) of a direct `Call`, else 0 — a SMALL inline accessor. Scar #2: the
## big-match `Call` arm is not dispatched under the seed, so the pre-match ptr-target arg check walks the
## args through this rather than that (dead-for-this-arm) match. Pairs with `expr_call_callee_span`.
expr_call_args_head := fn(e : ptr(Expr)) -> usize {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => { ah }
    _ => { 0 }
  }
}

## True only for an unqualified direct-name call. UFCS puts a `.` before the method name, qualified
## calls contain `::`, and expression-callee calls are marked separately in ast.al. CT-12's call-argument
## slice must not infer a parameter context for any of those forms: their resolution or receiver mapping
## is outside this deliberately narrow pre-emission judgement.
sema_direct_call_name := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  mut i := 0
  while i + 1 < n {
    if str_at((src + s + i), 2) == "::" { return false }
    i += 1
  }
  mut p := s
  while p > 0 {
    c := str_at((src + p - 1), 1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { p -= 1 }
    else { return c != "." }
  }
  true
}

expr_call_arity := fn(e : ptr(Expr)) -> usize {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => { na }
    _ => { 0 }
  }
}

## Recover the full source span of a call-shaped type expression (`Option(bool)`, `Slice(u8)`, …).
## The parser represents a generic instance as `Expr::Call` but stores only the callee-name span;
## the layout helpers need the enclosing parentheses to inspect its type arguments. Keep this small
## source scan in sema so the common checker can recognize the one deferred layout shape without
## teaching the type checker a broader generic-type model. A malformed or unbounded span is rejected
## by returning 0/0, never by scanning past the source indefinitely.
sema_generic_inst_type_span := fn(e : ptr(Expr), src : ptr(u8)) -> VSpan {
  if unchecked bitcast(usize, e) == 0 { return VSpan(s = 0, n = 0) }
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => {
      if na == 0 or cl == 0 { return VSpan(s = 0, n = 0) }
      mut i := cs + cl
      mut op := 0
      mut lim := cs + cl + 8
      while op == 0 and i < lim {
        c := str_at((src + i), 1)
        if c == "(" { op = i }
        else if c == " " or c == "\n" or c == "\t" or c == "\r" { i += 1 }
        else { return VSpan(s = 0, n = 0) }
      }
      if op == 0 { return VSpan(s = 0, n = 0) }
      mut depth := 0
      mut j := op
      mut cp := 0
      mut lim2 := op + 4096
      while cp == 0 and j < lim2 {
        c := str_at((src + j), 1)
        if c == "(" { depth += 1 }
        else if c == ")" {
          depth -= 1
          if depth == 0 { cp = j }
        }
        if cp == 0 { j += 1 }
      }
      if cp == 0 { return VSpan(s = 0, n = 0) }
      VSpan(s = cs, n = cp + 1 - cs)
    }
    _ => { VSpan(s = 0, n = 0) }
  }
}

## True only for the direct, one-argument `size(Option(bool))` fold. The bool niche is a deferred
## CLAYOUT S6 producer, so accepting the ordinary tag+payload fallback would answer a layout query
## with a value the implementation cannot yet justify. Keep `Option(ptr(T))`, `Option(u64)`, and all
## other size forms on their existing paths.
sema_size_bool_niche_bad := fn(e : ptr(Expr), src : ptr(u8)) -> bool {
  cs := expr_call_callee_span(e)
  if cs.n == 0 or str_at((src + cs.s), cs.n) != "size" { return false }
  if expr_call_arity(e) != 1 { return false }
  ah := expr_call_args_head(e)
  if ah == 0 { return false }
  aa := deref(arg_p(ah))
  ts := sema_generic_inst_type_span(aa.e, src)
  if ts.n == 0 { return false }
  is_bool_niche_pending(src, ts.s, ts.n)
}

## The complete parts of an enum-variant expression, else a zeroed result. This small accessor keeps
## variant-name validation on the bootstrap-safe pre-match path: the large `check_expr` match can skip
## payload-heavy `EnumLit` arms under the frozen seed, but a known enum with an unknown variant must never
## fall through to the lower as a `-1` discriminant.
EnumParts := struct { is_enum : bool, es : usize, el : usize, vs : usize, vl : usize }
expr_enum_parts := fn(e : ptr(Expr)) -> EnumParts {
  match deref(e) {
    Expr::EnumLit(es, el, vs, vl, np, ah) => { EnumParts(is_enum = true, es = es, el = el, vs = vs, vl = vl) }
    _ => { EnumParts(is_enum = false, es = 0, el = 0, vs = 0, vl = 0) }
  }
}

## Destructure a `Match` expression (value match) into its scrutinee + arm-list head — a SMALL inline
## `match deref(e)` accessor, because `check_expr`'s big bound-deref `match node` does NOT dispatch the
## payload-heavy `Match` arm under the seed (scar #2, same as `Var`). This lets `check_expr` run the
## exhaustiveness check on a VALUE match before that (dead-for-this-arm) match. `is_match` false → not a
## match. (`head` = the arena-linked `Arm` list; `scrut` = the scrutinee expr.)
MatchParts := struct { is_match : bool, scrut : ptr(Expr), head : ptr(mut Stmt) }
expr_match_parts := fn(e : ptr(Expr)) -> MatchParts {
  match deref(e) {
    Expr::Match(scrut, head) => { MatchParts(is_match = true, scrut = scrut, head = head) }
    _ => { MatchParts(is_match = false, scrut = unchecked bitcast(ptr(Expr), 0), head = 0) }
  }
}

## The statement body of a value-position `loop` expression, else null. This small accessor keeps the
## loop type rule on the pre-match path: payload-heavy expression arms can be skipped by the frozen seed's
## large bound-deref dispatcher, just like `Var` and `Match`.
expr_loop_body := fn(e : ptr(Expr)) -> ptr(mut Stmt) {
  match deref(e) {
    Expr::Loop(b) => { b }
    _ => { unchecked bitcast(ptr(mut Stmt), 0) }
  }
}

## SCALAR match exhaustiveness (Control Flow §5.4): does the arm list leave a value of the scrutinee's
## FINITE value domain uncovered? Returns true = a provable gap with no `_` (→ a compile error). This
## fires ONLY for a RANGE-containing scalar match (`a..b` / `a..=b` are brand-new syntax, so no existing
## program relies on the pre-existing no-scalar-check behavior → the check adds ZERO regression risk) over
## a type whose domain is small enough to enumerate: `bool` (tag 2 → [0,1]) or `u8` (tag 1, name `u8` →
## [0,255]). Coverage combines integer literals, OR-alternatives (each a `wild==0` literal arm after the
## parser's OR-expansion), and ranges (`wild` 5 half-open / 6 inclusive, `lit`=lo, `hi`=hi). Fail-OPEN
## (returns false) for a `_` arm (exhaustive), any non-literal/range arm (variant/str/comptime), a non-range
## match, or a wide/unknown scalar type — the same never-false-reject discipline as the enum check.
scalar_coverage_gap := fn(head : ptr(mut Arm), tag : u8, tns : usize, tnl : usize, src : ptr(u8)) -> bool {
  mut has_range := false
  mut has_wild := false
  mut all_simple := true
  mut arm := head
  while arm != 0 {
    am := deref(arm_p(arm))
    if am.wild == 1 { has_wild = true }
    else if am.wild == 5 or am.wild == 6 { has_range = true }
    else if am.wild == 0 and am.vs == 0 and am.vl == 0 { }   ## a scalar integer literal (or OR-expansion)
    else { all_simple = false }                              ## variant / str / comptime → fail-open
    arm = am.next
  }
  if has_wild { return false }
  if not all_simple { return false }
  if not has_range { return false }
  mut lo : i64 = 0
  mut hi : i64 = 0
  mut finite := false
  if tag == 2 { finite = true ; lo = 0 ; hi = 1 }
  else if tag == 1 and tnl != 0 and str_at((src + tns), tnl) == "u8" { finite = true ; lo = 0 ; hi = 255 }
  if not finite { return false }
  mut v := lo
  mut gap := false
  while v <= hi {
    mut covered := false
    mut a2 := head
    while a2 != 0 {
      m := deref(arm_p(a2))
      if m.wild == 0 and m.lit == v { covered = true }
      else if m.wild == 5 and m.lit <= v and v < m.hi { covered = true }
      else if m.wild == 6 and m.lit <= v and v <= m.hi { covered = true }
      a2 = m.next
    }
    if not covered { gap = true }
    v = v + 1
  }
  gap
}

## ─── AGGREGATE↔SCALAR CONFORMANCE (TYP-6) ────────────────────────────────────────────────────
## Reject a resolvable USER AGGREGATE (struct/enum) connected to a builtin SCALAR type, in BOTH
## directions — the check that MOVED UP from the emit path (the `lower.al` fail-loud nets): an aggregate
## VALUE flowing into a scalar SINK (a binding / assignment / call-arg / return / field / array-element)
## used to silently read the aggregate's word 0 as a scalar. Done in sema (post-overload-resolution) it
## ALSO catches the REVERSE (a scalar value into an aggregate sink) that a naive emit-time net could not.
## MONOTONIC-accepting: only a CONFIDENT aggregate-vs-scalar clash fires; an unresolved/unknown side is a
## no-op (poison-tolerant), so no valid program is newly rejected.
##
## AGGREGATE-LITERAL type-name (scar #2 workaround, mirrors `expr_var_span`): the struct/enum TYPE-name
## span of a `StructLit`/`EnumLit` VALUE expression, else `is_agg=false`. `check_expr`'s big bound-deref
## match does NOT dispatch these payload-heavy arms under the seed, so a struct/enum value binding
## otherwise records tag 0 — this small single-focus match recovers the type name RELIABLY.
AggLit := struct { is_agg : bool, s : usize, n : usize }
expr_agg_lit := fn(e : ptr(Expr)) -> AggLit {
  match deref(e) {
    Expr::StructLit(scs, scl, snf, sfh) => { AggLit(is_agg = true, s = scs, n = scl) }
    Expr::EnumLit(ets, etl, evs, evl, enp, eph) => { AggLit(is_agg = true, s = ets, n = etl) }
    _ => { AggLit(is_agg = false, s = 0, n = 0) }
  }
}
## True only for the parser's generic-construction shape `Name(type-args)(field = value, …)`.
## `StructLit` stores only the head after the parser erases the first parenthesized group, so recover
## that distinction from source: skip whitespace, consume the first balanced group, skip whitespace,
## then require the second `(` to begin an identifier followed by `=`. The bound is a malformed-source
## escape hatch; valid parser inputs stay far below it, while an unterminated scan remains non-matching.
sema_generic_ctor_shape := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  mut p := s + n
  mut steps := 0
  while steps < 4096 and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") {
    p += 1
    steps += 1
  }
  if str_at((src + p), 1) != "(" { return false }
  mut depth := 0
  mut has_arg := false
  mut closed := false
  while steps < 4096 {
    c := str_at((src + p), 1)
    if c == "(" { depth += 1; if depth > 1 { has_arg = true } }
    else if c == ")" {
      if depth == 0 { return false }
      depth -= 1
      if depth == 0 { p += 1; steps += 1; closed = true; break }
    } else if depth == 1 and c != " " and c != "\n" and c != "\t" and c != "\r" { has_arg = true }
    p += 1
    steps += 1
  }
  if not closed or has_arg == false { return false }
  while steps < 4096 and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") {
    p += 1
    steps += 1
  }
  if str_at((src + p), 1) != "(" { return false }
  p += 1
  steps += 1
  while steps < 4096 and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") {
    p += 1
    steps += 1
  }
  b := bytes(str_at((src + p), 1))[0]
  if not ((b >= 97 and b <= 122) or (b >= 65 and b <= 90) or (b >= 48 and b <= 57) or b == 95) { return false }
  mut ident := true
  while steps < 4096 and ident {
    q := bytes(str_at((src + p), 1))[0]
    if (q >= 97 and q <= 122) or (q >= 65 and q <= 90) or (q >= 48 and q <= 57) or q == 95 { p += 1; steps += 1 }
    else { ident = false }
  }
  while steps < 4096 and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") {
    p += 1
    steps += 1
  }
  str_at((src + p), 1) == "="
}
## Types §§5.1–5.2, 9.3 / Declarations §1.3 / Modules §§1–2 — a named-field literal is a
## construction only when its head resolves to a declared aggregate, a generic type constructor, or
## a one-hop alias of one. The parser deliberately erases `X(128)` before producing `StructLit(X, …)`;
## keeping this check on the shared semantic path prevents an unresolved head from reaching any lower.
## The alias scan covers generic-instance aliases such as the prelude's `u128 := uint(128)` without
## widening the ordinary type-name resolver or changing generic ABI/layout rules.
sema_unknown_type_ctor_span := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8)) -> VSpan {
  lit := expr_agg_lit(e)
  if not lit.is_agg { return VSpan(s = 0, n = 0) }
  mut is_struct := false
  match deref(e) {
    Expr::StructLit(scs0, scl0, snf0, sfh0) => { is_struct = true }
    _ => {}
  }
  if not is_struct { return VSpan(s = 0, n = 0) }
  if not sema_generic_ctor_shape(src, lit.s, lit.n) { return VSpan(s = 0, n = 0) }
  if qualified_type_name_known(decls, src, lit.s, lit.n) { return VSpan(s = 0, n = 0) }
  if callee_is_generic(decls, upto, src, lit.s, lit.n) { return VSpan(s = 0, n = 0) }
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 0 and d.alias_tl != 0 and streq(src, d.name_start, d.name_len, lit.s, lit.n) {
      ah := base_type_name(src, d.alias_ts, d.alias_tl)
      if callee_is_generic(decls, upto, src, ah.s, ah.n) { return VSpan(s = 0, n = 0) }
    }
    i += 1
  }
  VSpan(s = lit.s, n = lit.n)
}
## TOOL-17 / Tooling §2.7 — `Package` and `Target` exist only in the manifest configuration
## prelude. The parser represents both ordinary-source spellings as `StructLit`, whose generic field
## checking intentionally tolerates an unresolved head; reject only these two exact bare heads here.
## The driver removes the actual manifest binding before sema and gives source-visible package handles
## a synthetic `__manifest_Package` type. Therefore every remaining exact `Package`/`Target` literal is
## ordinary source, including declarations later in the anonymous `package.al` root, and must be fenced.
sema_manifest_value_ctor_span := fn(e : ptr(Expr), src : ptr(u8)) -> VSpan {
  lit := expr_agg_lit(e)
  if not lit.is_agg { return VSpan(s = 0, n = 0) }
  mut is_struct := false
  match deref(e) {
    Expr::StructLit(scs, scl, snf, sfh) => { is_struct = true }
    _ => {}
  }
  if not is_struct { return VSpan(s = 0, n = 0) }
  if lit.n == 7 and str_at((src + lit.s), 7) == "Package" { return VSpan(s = lit.s, n = lit.n) }
  if lit.n == 6 and str_at((src + lit.s), 6) == "Target" { return VSpan(s = lit.s, n = lit.n) }
  VSpan(s = 0, n = 0)
}
## The BASE-Var name span of a `Field(Var(b), f)` expression (else {0,0}) — recovers `EnumType` from a
## NULLARY variant access `EnumType.Variant` (parsed as a Field, not an EnumLit), so value_agg_ty can
## recognise it as an enum VALUE.
expr_field_base_var := fn(e : ptr(Expr)) -> VSpan {
  match deref(e) {
    Expr::Field(base, fs, fl) => { expr_var_span(base) }
    _ => { VSpan(s = 0, n = 0) }
  }
}
## The FIRST element expr of an `ArrayLit` (null if not an array / empty) — a scalar-element array is
## tagged (tag 7) at binding time so a whole-aggregate store into `xs[i]` is rejected.
expr_array_first := fn(e : ptr(Expr)) -> ptr(Expr) {
  match deref(e) {
    Expr::ArrayLit(nel, eh) => {
      if unchecked bitcast(usize, eh) != 0 { (deref(arg_p(eh))).e } else { unchecked bitcast(ptr(Expr), 0) }
    }
    _ => { unchecked bitcast(ptr(Expr), 0) }
  }
}
## True iff e is the initialized local-array shape whose first element is a direct literal of a
## resolved @packed struct. This mirrors lower::arr_elem_info's existing fail-loud fence while
## keeping the new rejection in the shared semantic/pre-emission path. Empty arrays, non-literal
## elements, ordinary structs, and non-initializing assignments remain outside this bounded slice.
sema_packed_array_literal := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  if unchecked bitcast(usize, e) == 0 { return false }
  first := expr_array_first(e)
  if unchecked bitcast(usize, first) == 0 { return false }
  al := expr_agg_lit(first)
  if not al.is_agg { return false }
  is_packed(decls, src, al.s, al.n)
}

## Skip the same whitespace and line-comment trivia as `lex_rt` while recovering a type from its source
## span. The AST deliberately keeps a local's type as source metadata, so this is needed to make the
## fence semantic across equivalent formatting/comment forms rather than dependent on raw punctuation.
sema_local_type_trivia := fn(src : ptr(u8), start : usize, end : usize) -> usize {
  mut p := start
  mut again := true
  while p < end and again {
    again = false
    while p < end {
      c := str_at((src + p), 1)
      if c == " " or c == "\n" or c == "\t" or c == "\r" { p += 1 } else { break }
    }
    if p < end and str_at((src + p), 1) == "#" {
      while p < end and str_at((src + p), 1) != "\n" { p += 1 }
      again = true
    }
  }
  p
}

## True iff the resolved local annotation is exactly the bounded mutable-array element shape
## `[[u8; 2]; 2]` or `[[u64; 2]; 2]`. `resolve_ty` retains the complete array span as tag 7 but
## intentionally does not retain dimensions or element types, so the source span supplies only this
## small, explicit shape check. Array type aliases are not a source form in this parser (aliases name
## nominal/generic types), and every other local/inferred/signature/field shape remains out of scope.
sema_local_multidim_array := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), ts : usize, tl : usize) -> bool {
  end := ts + tl
  p0 := sema_local_type_trivia(src, ts, end)
  if p0 >= end { return false }
  resolved := resolve_ty(src, p0, end - p0, decls, upto)
  if resolved.tag != 7 { return false }
  mut p := p0
  if str_at((src + p), 1) != "[" { return false }
  p += 1
  p = sema_local_type_trivia(src, p, end)
  if p >= end or str_at((src + p), 1) != "[" { return false }
  p += 1
  p = sema_local_type_trivia(src, p, end)
  mut scalar_len := 0
  if p + 2 <= end and str_at((src + p), 2) == "u8" { scalar_len = 2 }
  if p + 3 <= end and str_at((src + p), 3) == "u64" { scalar_len = 3 }
  if scalar_len == 0 { return false }
  p += scalar_len
  p = sema_local_type_trivia(src, p, end)
  if p >= end or str_at((src + p), 1) != ";" { return false }
  p += 1
  p = sema_local_type_trivia(src, p, end)
  if p >= end or str_at((src + p), 1) != "2" { return false }
  p += 1
  p = sema_local_type_trivia(src, p, end)
  if p >= end or str_at((src + p), 1) != "]" { return false }
  p += 1
  p = sema_local_type_trivia(src, p, end)
  if p >= end or str_at((src + p), 1) != ";" { return false }
  p += 1
  p = sema_local_type_trivia(src, p, end)
  if p >= end or str_at((src + p), 1) != "2" { return false }
  p += 1
  p = sema_local_type_trivia(src, p, end)
  if p >= end or str_at((src + p), 1) != "]" { return false }
  p += 1
  p = sema_local_type_trivia(src, p, end)
  p == end
}
## Return the source span of the first direct multidimensional fixed-array field in a STRUCT
## declaration, or 0. This is the semantic twin of lower_layout's pre-emission fence: share its
## source-shape predicate so check and build cannot disagree about whitespace or nested brackets.
## Generic instances are passed through `subst_field_ty`; scalar type arguments remain byte-identical,
## while an aggregate argument is inspected at its effective field span like the lower.
sema_multidim_array_field_bad := fn(d : Decl, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> usize {
  if d.kind != 2 { return 0 }
  mut f := d.fields_head
  while f != 0 {
    fd := deref(fld_p(f))
    eff := subst_field_ty(decls, src, d.name_start, d.name_len, fd.ts, fd.tl, a)
    if array_type_has_array_element(src, eff.s, eff.n) { return fd.ts }
    f = fd.next
  }
  0
}
## Is `v` a CONFIDENT numeric/boolean LITERAL (the REVERSE-direction scalar value)? Literals only — a
## scalar `Var` local is left tolerant (scalars are not reliably tag-recorded), so no valid program is
## newly rejected.
value_is_scalar_lit := fn(v : ptr(Expr)) -> bool {
  match deref(v) {
    Expr::Num(x, s, n) => { true }
    Expr::BoolLit(x) => { true }
    _ => { false }
  }
}
## Is `[s,n)` a BUILTIN SCALAR type NAME (int width / float / bool / char)? Mirrors the retired emit
## nets' `conv_kind(nm) >= 0 or nm == "bool" or nm == "char"` — the FORWARD scalar-sink test. Covers
## f32/f64/char that `resolve_ty` leaves tag 0, so a float/char sink still reads as a scalar sink here.
is_builtin_scalar_name := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return false }
  w := str_at((src + s), n)
  w == "u8" or w == "u16" or w == "u32" or w == "u64" or w == "usize" or w == "u128" or w == "i8" or w == "i16" or w == "i32" or w == "i64" or w == "isize" or w == "i128" or w == "f32" or w == "f64" or w == "bool" or w == "char"
}
## The CONFIDENT user-aggregate `Ty` (tag 3 struct / 4 enum, with the type-name span) of a VALUE
## expression, else tag 0 (poison-tolerant). A direct StructLit/EnumLit, or a `Var` naming a local
## RECORDED as an aggregate (tag 3/4 — see the reliable recording in `Stmt::Assign`).
value_agg_ty := fn(v : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize) -> Ty {
  al := expr_agg_lit(v)
  if al.is_agg {
    aty := resolve_ty(src, al.s, al.n, decls, upto)
    if aty.tag == 3 or aty.tag == 4 { return aty }
    return Ty(tag = 0, ns = 0, nl = 0)
  }
  ## NULLARY enum variant `EnumType.Variant` (a Field over an enum TYPE name, NOT a value local): an enum
  ## VALUE. Guarded so a struct field READ `p.f` (base is a value local) is NOT mistaken for one.
  fb := expr_field_base_var(v)
  if fb.n != 0 {
    fb_local := nloc != 0 and local_in(locals, nloc, src, fb.s, fb.n)
    if not fb_local {
      bt := resolve_ty(src, fb.s, fb.n, decls, upto)
      if bt.tag == 4 { return Ty(tag = 4, ns = fb.s, nl = fb.n) }
    }
  }
  vs := expr_var_span(v)
  if vs.n != 0 and nloc != 0 and local_in(locals, nloc, src, vs.s, vs.n) {
    raw := local_ty(locals, nloc, src, vs.s, vs.n)
    mut lt : u8 = raw.tag
    if lt >= 128 and lt != 255 { lt = lt - 128 }
    ## HIDDEN aggregate tags 9 (struct) / 10 (enum) are recorded by `Stmt::Assign` for a StructLit/EnumLit
    ## binding — hidden so `check_expr`'s Var resolution (which surfaces only 3/4/5) leaves them tag 0,
    ## keeping the OVERLOAD-NAIVE existing arg-vs-param checks tolerant (else `overload_three` false-rejects
    ## once struct args become known). Map them back to the real struct(3)/enum(4) tag here. A call-return
    ## struct is recorded as the real tag 3 and is treated identically.
    if lt == 3 or lt == 9 { return Ty(tag = 3, ns = raw.ns, nl = raw.nl) }
    if lt == 4 or lt == 10 { return Ty(tag = 4, ns = raw.ns, nl = raw.nl) }
  }
  Ty(tag = 0, ns = 0, nl = 0)
}
## The binary-expression aggregate boundary that must be checked before the large Expr match. The frozen
## seed can skip payload-heavy `Bin`/`StructLit` arms, so relying on the ordinary recursive arm alone lets
## `S(a = 1) + 1` become an unknown-plus-int and reach lower as a word-zero arithmetic result. Keep this
## deliberately narrow: only arithmetic/bitwise operators reject a confidently known user aggregate; the
## comparison operators are separate because aggregate equality has its own lower surface, and unknown
## operands remain poison-tolerant. The same helper runs inside a capability-query transaction and ordinary
## sema, keeping `compiles(expr)` identical to the ordinary typecheck attempt.
BinParts := struct { is_bin : bool, op : u8, left : ptr(Expr), right : ptr(Expr) }
expr_bin_parts := fn(e : ptr(Expr)) -> BinParts {
  match deref(e) {
    Expr::Bin(op, l, r) => { BinParts(is_bin = true, op = op, left = l, right = r) }
    _ => { BinParts(is_bin = false, op = 0, left = unchecked bitcast(ptr(Expr), 0), right = unchecked bitcast(ptr(Expr), 0)) }
  }
}
sema_op_symbol := fn(op : u8) -> str {
  if op == 16 { return "+" }
  if op == 17 { return "-" }
  if op == 18 { return "*" }
  if op == 19 { return "/" }
  if op == 29 { return "%" }
  if op == 34 { return "&" }
  if op == 35 { return "|" }
  if op == 36 { return "^" }
  ""
}
## Preserve a user operator whose FIRST parameter matches the known aggregate operand. The sema checker
## intentionally does not duplicate full overload resolution here; a matching operator is enough to keep
## this conformance net fail-open, while the lower's existing operator resolver remains authoritative.
sema_operator_overload_exists := fn(decls : ptr(rt::Vec), src : ptr(u8), op : u8, agg : Ty) -> bool {
  sym := sema_op_symbol(op)
  if sym.len == 0 or agg.nl == 0 { return false }
  at := base_type_name(src, agg.ns, agg.nl)
  if at.n == 0 { return false }
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut found := false
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and d.name_len == sym.len and str_at((src + d.name_start), d.name_len) == sym {
      mut p := d.params_head
      if p != 0 {
        pm := deref(param_p(p))
        pt := base_type_name(src, pm.ts, pm.tl)
        if pt.n != 0 and streq(src, pt.s, pt.n, at.s, at.n) { found = true }
      }
    }
    i += 1
  }
  found
}
bin_aggregate_arithmetic_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize) -> bool {
  bp := expr_bin_parts(e)
  if not bp.is_bin { return false }
  ## comparisons (20/24/25/26/27/28) and boolean operators (40/41/42) are not arithmetic sinks here.
  if bp.op == 20 or bp.op == 24 or bp.op == 25 or bp.op == 26 or bp.op == 27 or bp.op == 28 { return false }
  if bp.op == 40 or bp.op == 41 or bp.op == 42 { return false }
  lt := value_agg_ty(bp.left, decls, upto, src, locals, nloc)
  right_ty := value_agg_ty(bp.right, decls, upto, src, locals, nloc)
  mut bad := false
  ## Keep aggregate+aggregate and explicitly declared aggregate+scalar operator overloads (OP-1)
  ## untouched. This lane only closes a scalar literal beside an aggregate when no matching operator
  ## declaration exists — the exact silent word-zero case.
  if (lt.tag == 3 or lt.tag == 4) and value_is_scalar_lit(bp.right) and not sema_operator_overload_exists(decls, src, bp.op, lt) { bad = true }
  if (right_ty.tag == 3 or right_ty.tag == 4) and value_is_scalar_lit(bp.left) and not sema_operator_overload_exists(decls, src, bp.op, right_ty) { bad = true }
  bad
}
## A CONFIDENT aggregate↔scalar mismatch between a declared SINK type NAME `[ss,sn)` and a VALUE `v`, in
## BOTH directions. FORWARD: a builtin-scalar sink ← a confident user aggregate (the silent word-0 read
## the emit nets guarded). REVERSE: a user-aggregate (struct/enum) sink ← a confident scalar literal (the
## direction a naive emit net could not do). Poison-tolerant: an unknown sink or unresolved value → false.
agg_scalar_bad := fn(ss : usize, sn : usize, v : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize) -> bool {
  if sn == 0 { return false }
  mut bad := false
  if is_builtin_scalar_name(src, ss, sn) {
    va := value_agg_ty(v, decls, upto, src, locals, nloc)
    if va.tag == 3 or va.tag == 4 { bad = true }
  }
  st := resolve_ty(src, ss, sn, decls, upto)
  if st.tag == 3 or st.tag == 4 {
    if value_is_scalar_lit(v) { bad = true }
  }
  bad
}
## The raw TYPE-annotation span `[ts,tl)` of the i-th parameter of the top-level fn named [s,n) (walk
## order); {0,0} if absent. The NAME half of `callee_param_ty` — the conformance check needs the raw
## name to see a float/char scalar sink that `resolve_ty` reports as tag 0.
## How many top-level fns among `[0..upto)` match the callee name [s,n) (by tail name)? 1 = an
## UNAMBIGUOUS callee whose parameter types are safe to consult; >1 = an overload set (sema does not
## resolve overloads → the aggregate↔scalar call-arg check stays tolerant, so `overload_three` builds).
callee_fn_name_count := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize) -> usize {
  mut c : usize = 0
  th := sema_tail_hash(src, s, n)
  cnt := rt::vec_len(deref(decls))
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < upto and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
      d := deref(decl_get(decls, i))
      if d.kind == 1 and name_matches(src, d.name_start, d.name_len, s, n) { c += 1 }
    }
  }
  c
}
## Is an ordinary SAME-MODULE call provably ambiguous under the lower's current literal-category
## overload resolver? This deliberately covers only the genuine, spec-called-out case where EVERY
## argument is a bare integer/bool or float literal. The lower treats such an argument as matching
## every parameter in its scalar category, so two matching signatures are unambiguously an ambiguity.
## Non-literals, qualified calls, generics, guarded declarations, and cross-module names are left to
## the existing fail-loud frontier rather than guessed, preventing a false reject from sema's coarser Ty.
sema_int_overload_param := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  t := str_at((src + s), n)
  t == "u64" or t == "i64" or t == "usize" or t == "isize" or t == "u32" or t == "i32"
    or t == "u16" or t == "i16" or t == "u8" or t == "i8" or t == "bool" or t == "char"
}
sema_float_overload_param := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  t := str_at((src + s), n)
  t == "f64" or t == "f32"
}
sema_literal_class := fn(e : ptr(Expr)) -> u8 {
  match deref(e) {
    Expr::Num(v, s, n) => { 1 }
    Expr::BoolLit(v) => { 1 }
    Expr::FloatLit(s, n) => { 2 }
    _ => { 0 }
  }
}
literal_overload_ambiguous := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, nargs : usize, args_head : ptr(mut Arg), mod_s : usize, mod_l : usize) -> bool {
  ## This slice is intentionally unqualified. The owning-module span makes an unqualified lookup exact;
  ## qualified source paths require the lower's module-path normalization and remain unchanged.
  mut qi := 0
  while qi + 1 < cl { if str_at((src + cs + qi), 2) == "::" { return false }; qi += 1 }
  mut nfound := 0
  cnt := rt::vec_len(deref(decls))
  nh := sema_name_hash(src, cs, cl)
  mut jc := sni_lo(cnt, nh)
  jce := sni_hi(cnt, nh)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == nh {
    d := deref(decl_get(decls, i))
    same_name := streq(src, d.name_start, d.name_len, cs, cl)
    same_mod := streq(src, d.mod_start, d.mod_len, mod_s, mod_l)
    unguarded := unchecked bitcast(usize, d.when_cond) == 0
    if (d.kind == 1 or d.kind == 4) and d.is_generic == false and unguarded and d.arity == nargs and same_name and same_mod {
      mut pp := d.params_head
      mut gg := args_head
      mut matches := true
      while pp != 0 and gg != 0 {
        pm := deref(param_p(pp))
        ga := deref(arg_p(gg))
        lc := sema_literal_class(ga.e)
        bn := base_type_name(src, pm.ts, pm.tl)
        if lc == 1 and not sema_int_overload_param(src, bn.s, bn.n) { matches = false }
        else if lc == 2 and not sema_float_overload_param(src, bn.s, bn.n) { matches = false }
        else if lc == 0 { matches = false }
        pp = pm.next
        gg = ga.next
      }
      if matches and pp == 0 and gg == 0 { nfound += 1 }
    }
    }
    i += 1
  }
  nfound > 1
}
callee_param_type_span := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize, pidx : usize, a : ptr(mut rt::Arena)) -> VSpan {
  mut r := VSpan(s = 0, n = 0)
  th := sema_tail_hash(src, s, n)
  cnt := rt::vec_len(deref(decls))
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < upto and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
      d := deref(decl_get(decls, i))
      if d.kind == 1 and name_matches(src, d.name_start, d.name_len, s, n) {
        mut pp := d.params_head
        mut k := 0
        while pp != 0 {
          pm := deref(param_p(pp))
          if k == pidx { r = VSpan(s = pm.ts, n = pm.tl) }
          k += 1
          pp = pm.next
        }
      }
    }
  }
  r
}
## The raw TYPE-annotation span `[ts,tl)` of field [fns,fnl) within struct/enum [sns,snl); {0,0} if
## absent. The NAME half of `field_ty`, for the field-assign conformance check.
sema_field_ann_span := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), sns : usize, snl : usize, fns : usize, fnl : usize, a : ptr(mut rt::Arena)) -> VSpan {
  mut r := VSpan(s = 0, n = 0)
  di := type_decl_index(decls, upto, src, sns, snl)
  if di != 0 {
    d := deref(decl_get(decls, di - 1))
    mut f := d.fields_head
    while f != 0 {
      fd := deref(fld_p(f))
      if streq(src, fd.ns, fd.nl, fns, fnl) { r = VSpan(s = fd.ts, n = fd.tl) }
      f = fd.next
    }
  }
  r
}

## The sema-side type span for the lower's `base_struct_span` shapes: a local aggregate or a nested
## field whose declared type is an aggregate. Pointer/deref/index roots deliberately stay UNKNOWN —
## this mirror must follow the exact place forms that the build resolver can prove, not invent a wider
## type-flow analysis. Hidden aggregate tags 9/10 are the reliable names recorded for literal bindings.
s3a_struct_span := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> VSpan {
  mut r := VSpan(s = 0, n = 0)
  ev := expr_var_span(e)
  if ev.n != 0 {
    lt := local_ty(locals, nloc, src, ev.s, ev.n)
    mut tag := lt.tag
    if tag >= 128 and tag != 255 { tag = tag - 128 }
    if (tag == 3 or tag == 9) and lt.nl != 0 { r = VSpan(s = lt.ns, n = lt.nl) }
  } else {
    fs := expr_field_span(e)
    if fs.n != 0 {
      base := expr_field_base(e)
      bt := s3a_struct_span(base, decls, upto, src, locals, nloc, a)
      if bt.n != 0 {
        ft := sema_field_ann_span(decls, upto, src, bt.s, bt.n, fs.s, fs.n, a)
        rt0 := resolve_ty(src, ft.s, ft.n, decls, upto)
        if rt0.tag == 3 { r = VSpan(s = rt0.ns, n = rt0.nl) }
      }
    }
  }
  r
}

## Exact aggregate-field classification from `lower::agg_field_of`. The array/tuple prefix tests are
## intentional: S3(a) owns the call/return by-value fence, while S3(c/d)'s array-element place fence
## remains a build-only cross-backend boundary and is not pulled into this predicate.
s3a_field_is_aggregate := fn(decls : ptr(rt::Vec), src : ptr(u8), ft : VSpan) -> bool {
  if ft.n == 0 { return false }
  ftb := base_type_name(src, ft.s, ft.n)
  mut is_agg := false
  if ftb.n != 0 {
    if struct_decl_of(decls, src, ftb.s, ftb.n) >= 0 { is_agg = true }
    if enum_decl_of(decls, src, ftb.s, ftb.n) >= 0 { is_agg = true }
  }
  if str_at((src + ft.s), 1) == "[" or str_at((src + ft.s), 1) == "(" { is_agg = true }
  if str_at((src + ft.s), ft.n) == "str" { is_agg = true }
  if ftb.n != 0 and str_at((src + ftb.s), ftb.n) == "Slice" { is_agg = true }
  is_agg
}

## Return the field-name span when an aggregate field is about to enter the lower's WORD-model
## by-value resolver under a BYTE-layout containing struct. A plain `c := o.inner` is not a sink and
## remains accepted; callers use this only for call arguments and return expressions.
s3a_field_by_value_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  fs := expr_field_span(e)
  if fs.n == 0 { return 0 }
  base := expr_field_base(e)
  bt := s3a_struct_span(base, decls, upto, src, locals, nloc, a)
  if bt.n == 0 { return 0 }
  ft := sema_field_ann_span(decls, upto, src, bt.s, bt.n, fs.s, fs.n, a)
  if not s3a_field_is_aggregate(decls, src, ft) { return 0 }
  if layout_kind_is_byte(layout_kind(decls, src, bt.s, bt.n, deref(a))) { return fs.s }
  0
}

## Mirror `emit_addr_of`'s two supported field-address forms. The returned span is the field itself,
## matching lower's located source line; zero means the address is known-good or this conservative
## mirror cannot prove the lower's place shape.
s3a_addr_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  p := expr_addr_inner(e)
  if unchecked bitcast(usize, p) == 0 { return 0 }
  fs := expr_field_span(p)
  if fs.n == 0 { return 0 }
  base := expr_field_base(p)
  if expr_field_span(base).n != 0 { return fs.s }
  root := expr_var_span(base)
  if root.n == 0 { return fs.s }
  if is_mod_mut_global(decls, src, root.s, root.n) { return 0 }
  bt := s3a_struct_span(base, decls, upto, src, locals, nloc, a)
  if bt.n != 0 and std_struct_has_byte_layout(decls, src, bt.s, bt.n, deref(a)) { return 0 }
  fs.s
}

## Call-argument half of the shared S3(a) sink predicate. This intentionally does not inspect the
## callee signature: lower's `agg_field_of` fence is a place/layout decision before ABI resolution, so
## the same field shape must be rejected for an overload or a forward call as well.
s3a_call_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  ah := expr_call_args_head(e)
  mut g := ah
  mut bad := 0
  while g != 0 and bad == 0 {
    ga := deref(arg_p(g))
    bad = s3a_field_by_value_bad(ga.e, decls, upto, src, locals, nloc, a)
    g = ga.next
  }
  bad
}

## Recursive expression walk used before the bootstrap-sensitive large `check_expr` match. The old
## checker can legally return through a payload-heavy Call arm without visiting its source shape under
## the frozen seed; this structural walk is independent of synthesized type results and therefore keeps
## the check/build question aligned without changing any existing type policy.
s3a_expr_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> usize {
  mut bad := s3a_addr_bad(e, decls, upto, src, locals, nloc, a)
  if bad == 0 { bad = s3a_call_bad(e, decls, upto, src, locals, nloc, a) }
  if bad != 0 { return bad }
  match deref(e) {
    Expr::Bin(op, l, r) => {
      bad = s3a_expr_bad(l, decls, upto, src, a, locals, nloc)
      if bad == 0 { bad = s3a_expr_bad(r, decls, upto, src, a, locals, nloc) }
    }
    Expr::If(c, t, f) => {
      bad = s3a_expr_bad(c, decls, upto, src, a, locals, nloc)
      if bad == 0 { bad = s3a_expr_bad(t, decls, upto, src, a, locals, nloc) }
      if bad == 0 { bad = s3a_expr_bad(f, decls, upto, src, a, locals, nloc) }
    }
    Expr::Match(sc, ah) => {
      bad = s3a_expr_bad(sc, decls, upto, src, a, locals, nloc)
      mut arm := ah
      while arm != 0 and bad == 0 {
        am := deref(arm_p(arm))
        bad = s3a_expr_bad(am.body, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_stmts_bad(am.body_stmts, decls, upto, src, a, locals, nloc) }
        arm = am.next
      }
    }
    Expr::Call(cs0, cl0, na0, ah0) => {
      mut g := ah0
      while g != 0 and bad == 0 {
        ga := deref(arg_p(g))
        bad = s3a_expr_bad(ga.e, decls, upto, src, a, locals, nloc)
        g = ga.next
      }
    }
    Expr::StructLit(ss, sl, nf, fh) => {
      mut g := fh
      while g != 0 and bad == 0 {
        ga := deref(arg_p(g))
        bad = s3a_expr_bad(ga.e, decls, upto, src, a, locals, nloc)
        g = ga.next
      }
    }
    Expr::EnumLit(es, el, vs, vl, np, ph) => {
      mut g := ph
      while g != 0 and bad == 0 {
        ga := deref(arg_p(g))
        bad = s3a_expr_bad(ga.e, decls, upto, src, a, locals, nloc)
        g = ga.next
      }
    }
    Expr::Field(base, fs, fl) => { bad = s3a_expr_bad(base, decls, upto, src, a, locals, nloc) }
    Expr::AddrOf(p) => { bad = s3a_expr_bad(p, decls, upto, src, a, locals, nloc) }
    Expr::Deref(p) => { bad = s3a_expr_bad(p, decls, upto, src, a, locals, nloc) }
    Expr::ArrayLit(ne, eh) => {
      mut g := eh
      while g != 0 and bad == 0 {
        ga := deref(arg_p(g))
        bad = s3a_expr_bad(ga.e, decls, upto, src, a, locals, nloc)
        g = ga.next
      }
    }
    Expr::Index(base, idx) => {
      bad = s3a_expr_bad(base, decls, upto, src, a, locals, nloc)
      if bad == 0 { bad = s3a_expr_bad(idx, decls, upto, src, a, locals, nloc) }
    }
    Expr::Try(inner) => { bad = s3a_expr_bad(inner, decls, upto, src, a, locals, nloc) }
    Expr::Slice(base, lo, hi) => {
      bad = s3a_expr_bad(base, decls, upto, src, a, locals, nloc)
      if bad == 0 { bad = s3a_expr_bad(lo, decls, upto, src, a, locals, nloc) }
      if bad == 0 { bad = s3a_expr_bad(hi, decls, upto, src, a, locals, nloc) }
    }
    Expr::CompField(base, idx) => {
      bad = s3a_expr_bad(base, decls, upto, src, a, locals, nloc)
      if bad == 0 { bad = s3a_expr_bad(idx, decls, upto, src, a, locals, nloc) }
    }
    Expr::Unchecked(inner) => { bad = s3a_expr_bad(inner, decls, upto, src, a, locals, nloc) }
    Expr::Lambda(pos, ph, rts, rtl, bh, value) => {
      bad = s3a_stmts_bad(bh, decls, upto, src, a, locals, nloc)
      if bad == 0 { bad = s3a_expr_bad(value, decls, upto, src, a, locals, nloc) }
    }
    Expr::Bitcast(inner, ts, tl) => { bad = s3a_expr_bad(inner, decls, upto, src, a, locals, nloc) }
    Expr::Loop(body) => { bad = s3a_stmts_bad(body, decls, upto, src, a, locals, nloc) }
    _ => {}
  }
  bad
}

## Statement companion for `s3a_expr_bad`; it reaches expression positions the ordinary `check_expr_da`
## wrapper does not receive (notably a FieldPathAssign's PLACE) and follows nested control-flow bodies.
s3a_stmts_bad := fn(head : ptr(mut Stmt), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> usize {
  mut cur := head
  mut bad := 0
  while cur != 0 and bad == 0 {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::Assign(ns, nl, v, nx) => { bad = s3a_expr_bad(v, decls, upto, src, a, locals, nloc) }
      Stmt::While(c, b, nx) => {
        bad = s3a_expr_bad(c, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_stmts_bad(b, decls, upto, src, a, locals, nloc) }
      }
      Stmt::FieldAssign(bns, bnl, fns, fnl, v, nx) => { bad = s3a_expr_bad(v, decls, upto, src, a, locals, nloc) }
      Stmt::Return(v, nx) => { bad = s3a_expr_bad(v, decls, upto, src, a, locals, nloc) }
      Stmt::If(c, th, el, nx) => {
        bad = s3a_expr_bad(c, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_stmts_bad(th, decls, upto, src, a, locals, nloc) }
        if bad == 0 { bad = s3a_stmts_bad(el, decls, upto, src, a, locals, nloc) }
      }
      Stmt::Match(sc, ah, nx) => {
        bad = s3a_expr_bad(sc, decls, upto, src, a, locals, nloc)
        mut arm := ah
        while arm != 0 and bad == 0 {
          am := deref(arm_p(arm))
          bad = s3a_expr_bad(am.body, decls, upto, src, a, locals, nloc)
          if bad == 0 { bad = s3a_stmts_bad(am.body_stmts, decls, upto, src, a, locals, nloc) }
          arm = am.next
        }
      }
      Stmt::For(fns, fnl, lo, hi, b, nx) => {
        bad = s3a_expr_bad(lo, decls, upto, src, a, locals, nloc)
        if bad == 0 and hi != 0 { bad = s3a_expr_bad(hi, decls, upto, src, a, locals, nloc) }
        if bad == 0 { bad = s3a_stmts_bad(b, decls, upto, src, a, locals, nloc) }
      }
      Stmt::DerefAssign(p, v, nx) => {
        bad = s3a_expr_bad(p, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_expr_bad(v, decls, upto, src, a, locals, nloc) }
      }
      Stmt::IndexAssign(b, i, v, nx) => {
        bad = s3a_expr_bad(b, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_expr_bad(i, decls, upto, src, a, locals, nloc) }
        if bad == 0 { bad = s3a_expr_bad(v, decls, upto, src, a, locals, nloc) }
      }
      Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => {
        bad = s3a_expr_bad(b, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_expr_bad(i, decls, upto, src, a, locals, nloc) }
        if bad == 0 { bad = s3a_expr_bad(v, decls, upto, src, a, locals, nloc) }
      }
      Stmt::FieldPathAssign(p, v, nx) => {
        bad = s3a_expr_bad(p, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_expr_bad(v, decls, upto, src, a, locals, nloc) }
      }
      Stmt::Loop(b, nx) => { bad = s3a_stmts_bad(b, decls, upto, src, a, locals, nloc) }
      Stmt::ExprStmt(v, nx) => { bad = s3a_expr_bad(v, decls, upto, src, a, locals, nloc) }
      Stmt::CompIf(c, th, el, nx) => {
        bad = s3a_expr_bad(c, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_stmts_bad(th, decls, upto, src, a, locals, nloc) }
        if bad == 0 { bad = s3a_stmts_bad(el, decls, upto, src, a, locals, nloc) }
      }
      Stmt::CompFor(cvs, cvl, iv, b, nx) => { bad = s3a_stmts_bad(b, decls, upto, src, a, locals, nloc) }
      Stmt::CompForRange(rvs, rvl, lo, hi, b, nx) => {
        bad = s3a_expr_bad(lo, decls, upto, src, a, locals, nloc)
        if bad == 0 and hi != 0 { bad = s3a_expr_bad(hi, decls, upto, src, a, locals, nloc) }
        if bad == 0 { bad = s3a_stmts_bad(b, decls, upto, src, a, locals, nloc) }
      }
      Stmt::Unchecked(b, nx) => { bad = s3a_stmts_bad(b, decls, upto, src, a, locals, nloc) }
      Stmt::AllocWith(e, b, nx) => {
        bad = s3a_expr_bad(e, decls, upto, src, a, locals, nloc)
        if bad == 0 { bad = s3a_stmts_bad(b, decls, upto, src, a, locals, nloc) }
      }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  bad
}

## A return sink applies the aggregate-field-by-value fence to the expression itself and to branch
## values, while leaving ordinary local binding (`c := o.inner`) alone.
s3a_return_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> usize {
  mut bad := s3a_field_by_value_bad(e, decls, upto, src, locals, nloc, a)
  if bad != 0 { return bad }
  match deref(e) {
    Expr::If(c, t, f) => {
      bad = s3a_return_bad(t, decls, upto, src, a, locals, nloc)
      if bad == 0 { bad = s3a_return_bad(f, decls, upto, src, a, locals, nloc) }
    }
    Expr::Match(sc, ah) => {
      mut arm := ah
      while arm != 0 and bad == 0 {
        am := deref(arm_p(arm))
        bad = s3a_return_bad(am.body, decls, upto, src, a, locals, nloc)
        arm = am.next
      }
    }
    _ => {}
  }
  bad
}

## Parse a fixed-array annotation `[T; N]` and return N, or -1 for an unsupported/non-fixed form.
## This is intentionally limited to decimal fixed lengths, matching the current lower's fixed-array
## surface. The element type is not guessed here: the DA slice tracks places, while ordinary sema keeps
## its existing poison-tolerant element typing.
array_type_count := fn(src : ptr(u8), ts : usize, tl : usize) -> i64 {
  if tl < 4 or str_at((src + ts), 1) != "[" { return -1 }
  end := ts + tl
  mut p := ts + 1
  mut semi := 0
  while p < end {
    if str_at((src + p), 1) == ";" { semi = p; break }
    p += 1
  }
  if semi == 0 { return -1 }
  p = semi + 1
  while p < end and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\t") { p += 1 }
  mut n : i64 = 0
  mut any := false
  while p < end {
    c := bytes(str_at((src + p), 1))[0]
    if c == 93 { break }
    if c < 48 or c > 57 { return -1 }
    any = true
    n = n * 10 + i64(c - 48)
    p += 1
  }
  if not any or p >= end or bytes(str_at((src + p), 1))[0] != 93 { return -1 }
  n
}

## Whether a fixed-array annotation has a known scalar element type. This keeps the pre-existing
## aggregate-to-scalar INDEX-ASSIGN rejection limited to scalar-element arrays; `[Rec; N]` and
## `[Enum; N]` already use the aggregate element lowering path and remain accepted.
array_elem_scalar := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  if tl < 4 or str_at((src + ts), 1) != "[" { return false }
  end := ts + tl
  mut p := ts + 1
  mut semi := 0
  while p < end {
    if str_at((src + p), 1) == ";" { semi = p; break }
    p += 1
  }
  if semi == 0 { return false }
  mut es := ts + 1
  while es < semi and (str_at((src + es), 1) == " " or str_at((src + es), 1) == "\t") { es += 1 }
  mut ee := semi
  while ee > es and (str_at((src + ee - 1), 1) == " " or str_at((src + ee - 1), 1) == "\t") { ee -= 1 }
  if ee <= es { return false }
  ew := str_at((src + es), ee - es)
  ew == "u8" or ew == "u32" or ew == "u64" or ew == "usize" or ew == "i32" or ew == "i64" or ew == "isize" or ew == "bool"
}

array_elem_span := fn(src : ptr(u8), ts : usize, tl : usize) -> VSpan {
  mut z := VSpan(s = 0, n = 0)
  if tl < 4 { return z }
  end := ts + tl
  ## `typearg_at` returns the source slice between tuple commas, so a multiline tuple may leave
  ## `\n`/`\r`/tabs around the component. Keep this source recovery in lockstep with
  ## `local_type_span`, which already treats all four bytes as whitespace.
  mut head := ts
  while head < end and (str_at((src + head), 1) == " " or str_at((src + head), 1) == "\n" or str_at((src + head), 1) == "\t" or str_at((src + head), 1) == "\r") { head += 1 }
  if head >= end or str_at((src + head), 1) != "[" { return z }
  mut p := head + 1
  mut semi := 0
  while p < end {
    if str_at((src + p), 1) == ";" { semi = p; break }
    p += 1
  }
  if semi == 0 { return z }
  mut es := head + 1
  while es < semi and (str_at((src + es), 1) == " " or str_at((src + es), 1) == "\n" or str_at((src + es), 1) == "\t" or str_at((src + es), 1) == "\r") { es += 1 }
  mut ee := semi
  while ee > es and (str_at((src + ee - 1), 1) == " " or str_at((src + ee - 1), 1) == "\n" or str_at((src + ee - 1), 1) == "\t" or str_at((src + ee - 1), 1) == "\r") { ee -= 1 }
  if ee > es { z = VSpan(s = es, n = ee - es) }
  z
}

array_elem_ty := fn(src : ptr(u8), ty : Ty, decls : ptr(rt::Vec), upto : usize) -> Ty {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 7 { return Ty(tag = 0, ns = 0, nl = 0) }
  sp := array_elem_span(src, ty.ns, ty.nl)
  resolve_ty(src, sp.s, sp.n, decls, upto)
}

## Replace a whole unreadied aggregate marker with one unreadied direct-field entry per declared field.
## Unknown/non-struct types stay conservative: the root marker is not discharged.
da_seed_fields := fn(in out da : DA, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), rs : usize, rn : usize, ty : Ty) {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag == 3 and ty.nl != 0 {
    di := type_decl_index(decls, upto, src, ty.ns, ty.nl)
    if di != 0 {
      d := deref(decl_get(decls, di - 1))
      mut f := d.fields_head
      while f != 0 {
        fd := deref(fld_p(f))
        fvec_push(da_fvec_value(da), rs, rn, fd.ns, fd.nl)
        f = fd.next
      }
    }
  }
}

## Replace a whole unreadied fixed-array marker with one unreadied entry per element. Large or malformed
## lengths stay conservative by retaining the root marker, rather than allocating unbounded DA state.
da_seed_array := fn(in out da : DA, src : ptr(u8), rs : usize, rn : usize, ty : Ty) {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 7 { return }
  n := array_type_count(src, ty.ns, ty.nl)
  if n < 0 or n > 256 { return }
  da_remove_root(da, src, rs, rn)
  mut i : i64 = 0
  while i < n {
    avec_push(da_avec_value(da), rs, rn, usize(i))
    i += 1
  }
}

## A constant-index write initializes exactly one fixed-array element. Dynamic or out-of-range indices
## remain conservative and therefore do not discharge any DA entry.
da_assign_array := fn(in out da : DA, src : ptr(u8), rs : usize, rn : usize, ix : i64, ty : Ty) {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 7 or ix < 0 { return }
  n := array_type_count(src, ty.ns, ty.nl)
  if n < 0 or ix >= n { return }
  avec_remove(da_avec_value(da), src, rs, rn, usize(ix))
  navec_remove_index(da_navec_value(da), src, rs, rn, usize(ix))
  napvec_remove_index(da_napvec_value(da), src, rs, rn, 0, 0, usize(ix))
}

## A constant-index `root[index].field = value` on a local fixed array of simple structs initializes only
## that field of that element. Dynamic/out-of-range indices and non-struct elements remain conservative.
da_assign_array_field := fn(in out da : DA, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ix : i64, ty : Ty) {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 7 or ix < 0 { return }
  n := array_type_count(src, ty.ns, ty.nl)
  if n < 0 or n > 256 or ix >= n { return }
  et := array_elem_ty(src, ty, decls, upto)
  mut etag := et.tag
  if etag >= 128 and etag != 255 { etag = etag - 128 }
  if etag != 3 or et.nl == 0 { return }
  if da_has_array(ptr(da), src, rs, rn, usize(ix)) {
    avec_remove(da_avec_value(da), src, rs, rn, usize(ix))
    di := type_decl_index(decls, upto, src, et.ns, et.nl)
    if di != 0 {
      d := deref(decl_get(decls, di - 1))
      mut f := d.fields_head
      while f != 0 {
        fd := deref(fld_p(f))
        navec_push(da_navec_value(da), rs, rn, fd.ns, fd.nl, usize(ix))
        f = fd.next
      }
    }
  }
  navec_remove(da_navec_value(da), src, rs, rn, fs, fln, usize(ix))
  napvec_remove_index(da_napvec_value(da), src, rs, rn, fs, fln, usize(ix))
}

## A constant-index `root.array[index].field = value` on an array field of a local struct. The first
## leaf write expands the array field into one unreadied leaf marker per element; a whole-element write
## can have left a NAVec marker for the selected index, which is expanded just for that element.
da_assign_array_nested_field := fn(in out da : DA, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize, ix : i64, ty : Ty) {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 3 or ty.nl == 0 or ix < 0 { return }
  if da_has_root(ptr(da), src, rs, rn) {
    da_remove_root(da, src, rs, rn)
    da_seed_fields(da, decls, upto, src, rs, rn, ty)
  }
  fsp := sema_field_ann_span(decls, upto, src, ty.ns, ty.nl, fs, fln, unchecked bitcast(ptr(mut rt::Arena), da.arena))
  ft := resolve_ty(src, fsp.s, fsp.n, decls, upto)
  mut ftag := ft.tag
  if ftag >= 128 and ftag != 255 { ftag = ftag - 128 }
  if ftag != 7 { return }
  n := array_type_count(src, ft.ns, ft.nl)
  if n < 0 or n > 256 or ix >= n { return }
  et := array_elem_ty(src, ft, decls, upto)
  mut etag := et.tag
  if etag >= 128 and etag != 255 { etag = etag - 128 }
  if etag != 3 or et.nl == 0 { return }
  if da_has_field(ptr(da), src, rs, rn, fs, fln) {
    fvec_remove(da_fvec_value(da), src, rs, rn, fs, fln)
    di := type_decl_index(decls, upto, src, et.ns, et.nl)
    if di != 0 {
      d := deref(decl_get(decls, di - 1))
      mut j : i64 = 0
      while j < n {
        mut ff := d.fields_head
        while ff != 0 {
          fd := deref(fld_p(ff))
          napvec_push(da_napvec_value(da), rs, rn, fs, fln, fd.ns, fd.nl, usize(j))
          ff = fd.next
        }
        j += 1
      }
    }
  }
  if navec_has(da_navec(da), src, rs, rn, fs, fln, usize(ix)) {
    navec_remove_index(da_navec_value(da), src, rs, rn, fs, fln, usize(ix))
    di2 := type_decl_index(decls, upto, src, et.ns, et.nl)
    if di2 != 0 {
      d2 := deref(decl_get(decls, di2 - 1))
      mut ff2 := d2.fields_head
      while ff2 != 0 {
        fd2 := deref(fld_p(ff2))
        napvec_push(da_napvec_value(da), rs, rn, fs, fln, fd2.ns, fd2.nl, usize(ix))
        ff2 = fd2.next
      }
    }
  }
  napvec_remove(da_napvec_value(da), src, rs, rn, fs, fln, ss, sln, usize(ix))
}

## A constant-index `root[index].field.leaf = value` on a local fixed array of structs.
## The first leaf write expands the selected element and then the selected aggregate field; sibling
## element fields, sibling leaf fields, and whole aggregate reads stay unreadied until explicitly written.
da_assign_array_elem_nested_field := fn(in out da : DA, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ss : usize, sln : usize, ix : i64, ty : Ty) {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 7 or ix < 0 { return }
  n := array_type_count(src, ty.ns, ty.nl)
  if n < 0 or n > 256 or ix >= n { return }
  et := array_elem_ty(src, ty, decls, upto)
  mut etag := et.tag
  if etag >= 128 and etag != 255 { etag = etag - 128 }
  if etag != 3 or et.nl == 0 { return }
  if da_has_array(ptr(da), src, rs, rn, usize(ix)) {
    avec_remove(da_avec_value(da), src, rs, rn, usize(ix))
    di := type_decl_index(decls, upto, src, et.ns, et.nl)
    if di != 0 {
      d := deref(decl_get(decls, di - 1))
      mut f := d.fields_head
      while f != 0 {
        fd := deref(fld_p(f))
        navec_push(da_navec_value(da), rs, rn, fd.ns, fd.nl, usize(ix))
        f = fd.next
      }
    }
  }
  fsp := sema_field_ann_span(decls, upto, src, et.ns, et.nl, fs, fln, unchecked bitcast(ptr(mut rt::Arena), da.arena))
  ft := resolve_ty(src, fsp.s, fsp.n, decls, upto)
  mut ftag := ft.tag
  if ftag >= 128 and ftag != 255 { ftag = ftag - 128 }
  if ftag != 3 or ft.nl == 0 { return }
  if da_has_nested_array(ptr(da), src, rs, rn, fs, fln, usize(ix)) {
    navec_remove(da_navec_value(da), src, rs, rn, fs, fln, usize(ix))
    di2 := type_decl_index(decls, upto, src, ft.ns, ft.nl)
    if di2 != 0 {
      d2 := deref(decl_get(decls, di2 - 1))
      mut ff := d2.fields_head
      while ff != 0 {
        fd2 := deref(fld_p(ff))
        napvec_push(da_napvec_value(da), rs, rn, fs, fln, fd2.ns, fd2.nl, usize(ix))
        ff = fd2.next
      }
    }
  }
  napvec_remove(da_napvec_value(da), src, rs, rn, fs, fln, ss, sln, usize(ix))
}

## A constant-index write to `root.field[index]` initializes exactly one element of a fixed-array field.
## The first such write expands the direct field marker into one unreadied entry per array element. Only
## the supported one-field scalar-array shape is represented here; deeper and dynamic paths stay conservative.
da_assign_nested_array := fn(in out da : DA, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ix : i64, ty : Ty) {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 3 or ty.nl == 0 or ix < 0 { return }
  if da_has_root(ptr(da), src, rs, rn) {
    da_remove_root(da, src, rs, rn)
    da_seed_fields(da, decls, upto, src, rs, rn, ty)
  }
  if da_has_field(ptr(da), src, rs, rn, fs, fln) {
    fsp := sema_field_ann_span(decls, upto, src, ty.ns, ty.nl, fs, fln, unchecked bitcast(ptr(mut rt::Arena), da.arena))
    ft := resolve_ty(src, fsp.s, fsp.n, decls, upto)
    mut ftag := ft.tag
    if ftag >= 128 and ftag != 255 { ftag = ftag - 128 }
    if ftag == 7 {
      n := array_type_count(src, ft.ns, ft.nl)
      if n >= 0 and n <= 256 and ix < n {
        fvec_remove(da_fvec_value(da), src, rs, rn, fs, fln)
        mut j : i64 = 0
        while j < n {
          navec_push(da_navec_value(da), rs, rn, fs, fln, usize(j))
          j += 1
        }
      }
    }
  }
  navec_remove(da_navec_value(da), src, rs, rn, fs, fln, usize(ix))
  napvec_remove_index(da_napvec_value(da), src, rs, rn, fs, fln, usize(ix))
}

## A direct `p.f = value` initializes only `f`. On the first field write, replace the whole-place marker with
## one unreadied entry per declared field, then remove the written field. A whole direct-field write also
## discharges any nested descendants below that field.
da_assign_field := fn(in out da : DA, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), rs : usize, rn : usize, fs : usize, fln : usize, ty : Ty) {
  if da_has_root(ptr(da), src, rs, rn) {
    da_remove_root(da, src, rs, rn)
    da_seed_fields(da, decls, upto, src, rs, rn, ty)
  }
  fvec_remove(da_fvec_value(da), src, rs, rn, fs, fln)
  pvec_remove_prefix(da_pvec_value(da), src, rs, rn, fs, fln)
  navec_remove_field(da_navec_value(da), src, rs, rn, fs, fln)
  napvec_remove_field(da_napvec_value(da), src, rs, rn, fs, fln)
}

## Initialize a bounded nested path `root.first.second`. The first aggregate field is expanded into child
## path entries on first descent; only the exact leaf is then discharged. Unsupported deeper/array paths
## remain conservative because they never remove the root or an unreadied prefix.
da_assign_path := fn(in out da : DA, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), np : NestedPath, ty : Ty) {
  mut tag := ty.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 3 or ty.nl == 0 { return }
  if da_has_root(ptr(da), src, np.rs, np.rn) {
    da_remove_root(da, src, np.rs, np.rn)
    da_seed_fields(da, decls, upto, src, np.rs, np.rn, ty)
  }
  if da_has_field(ptr(da), src, np.rs, np.rn, np.fs, np.fl) {
    fsp := sema_field_ann_span(decls, upto, src, ty.ns, ty.nl, np.fs, np.fl, unchecked bitcast(ptr(mut rt::Arena), da.arena))
    ft := resolve_ty(src, fsp.s, fsp.n, decls, upto)
    mut ftag := ft.tag
    if ftag >= 128 and ftag != 255 { ftag = ftag - 128 }
    fvec_remove(da_fvec_value(da), src, np.rs, np.rn, np.fs, np.fl)
    if ftag == 3 and ft.nl != 0 {
      di := type_decl_index(decls, upto, src, ft.ns, ft.nl)
      if di != 0 {
        d := deref(decl_get(decls, di - 1))
        mut f := d.fields_head
        while f != 0 {
          fd := deref(fld_p(f))
          pvec_push(da_pvec_value(da), np.rs, np.rn, np.fs, np.fl, fd.ns, fd.nl)
          f = fd.next
        }
      }
    }
  }
  pvec_remove(da_pvec_value(da), src, np.rs, np.rn, np.fs, np.fl, np.ss, np.sl)
}
## The declared TYPE-annotation span of a module-level value binding named [s,n); {0,0} if absent — the
## global-reassign sink (`G = <agg>`). Recovers the `: T` from source (globals carry no dedicated type
## field), mirroring `local_type_span` for a local.
global_type_span := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> VSpan {
  cnt := rt::vec_len(deref(decls))
  mut r := VSpan(s = 0, n = 0)
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and streq(src, d.name_start, d.name_len, s, n) {
      lts := local_type_span(src, d.name_start, d.name_len)
      r = VSpan(s = lts.s, n = lts.n)
    }
    i += 1
  }
  r
}
## Recover the concrete STRUCT type of a mutable global. An explicit `: R` annotation is the first
## source; an inferred `mut G := R(...)` uses the initializer's StructLit type. No other inferred
## shape is admitted here, so this fence cannot turn an unknown/scalar global into an aggregate reject.
global_struct_type_span := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> VSpan {
  ann := global_type_span(decls, src, s, n)
  if ann.n != 0 and struct_decl_of(decls, src, ann.s, ann.n) >= 0 { return ann }
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and streq(src, d.name_start, d.name_len, s, n) {
      if unchecked bitcast(usize, d.value) != 0 {
        lit := expr_agg_lit(d.value)
        if lit.is_agg and struct_decl_of(decls, src, lit.s, lit.n) >= 0 { return VSpan(s = lit.s, n = lit.n) }
        call_ty := expr_call_result_ty(d.value, decls, cnt, src)
        if call_ty.tag == 3 and call_ty.nl != 0 { return VSpan(s = call_ty.ns, n = call_ty.nl) }
      }
    }
    i += 1
  }
  VSpan(s = 0, n = 0)
}
## The direct-name counterpart used by statement write places, whose parser representation stores the
## base as a name span instead of an `Expr`. Hidden tag 9 is the reliable inferred-struct recording;
## the global fallback covers a module-level annotated or inferred struct. Other types remain unknown.
sema_struct_owner_name_span := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, s : usize, n : usize) -> VSpan {
  lt := local_ty(locals, nloc, src, s, n)
  mut tag : u8 = lt.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if (tag == 3 or tag == 9) and lt.nl != 0 { return VSpan(s = lt.ns, n = lt.nl) }
  global_struct_type_span(decls, src, s, n)
}
## A bare/qualified assignment target may be a global owned by another package module. The complete
## module-visibility walk runs after `check_stmts`, but this early local-name fence must not turn a valid
## ancestor global (or the existing later visibility diagnostic for a private sibling global) into a new
## generic `unbound name`. Existence is intentionally module-blind here; `sema_vis_stmts` remains the
## authority for which module may address it.
sema_global_name_anywhere := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  mut i := 0
  cnt := rt::vec_len(deref(decls))
  while i < cnt {
    d := deref(decl_get(decls, i))
    if sema_is_global_decl(d, src) and streq(src, d.name_start, d.name_len, s, n) { return true }
    i += 1
  }
  false
}
## Recover a confidently known STRUCT owner for a value expression. The local aggregate recording is
## the primary source; a module-level aggregate and the direct literal/call shapes are included so the
## field-name fence covers the same obvious values without inventing general type flow. Unknown,
## scalar, string, enum, pointer-root, and unresolved expressions stay open (poison-tolerant).
sema_struct_owner_span := fn(base : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> VSpan {
  mut r := s3a_struct_span(base, decls, upto, src, locals, nloc, a)
  if r.n == 0 {
    bv := expr_var_span(base)
    if bv.n != 0 { r = global_struct_type_span(decls, src, bv.s, bv.n) }
  }
  if r.n == 0 {
    lit := expr_agg_lit(base)
    if lit.is_agg and struct_decl_of(decls, src, lit.s, lit.n) >= 0 { r = VSpan(s = lit.s, n = lit.n) }
  }
  if r.n == 0 {
    ct := expr_call_result_ty(base, decls, upto, src)
    if ct.tag == 3 and ct.nl != 0 { r = VSpan(s = ct.ns, n = ct.nl) }
  }
  r
}
## The direct/local/global field-name fence. A known struct must contain the selected field; otherwise
## the old `field_ty` returned unknown and the lower read/stored word zero. Keep prelude namespace and
## unknown-owner accesses tolerant, because their associated/pointer layouts are outside this bounded
## sema slice and existing lowering remains authoritative there.
sema_field_name_missing := fn(base : ptr(Expr), fs : usize, fl : usize, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> bool {
  if is_prelude_ns_var(base, src) { return false }
  owner := sema_struct_owner_span(base, decls, upto, src, locals, nloc, a)
  if owner.n == 0 { return false }
  sema_field_ann_span(decls, upto, src, owner.s, owner.n, fs, fl, a).n == 0
}
## The x86 lower has a fail-loud fence for exactly this shape: a compatible, non-literal struct value
## entering a bare mutable struct global. Mirror only that proven boundary in sema so WAT/AArch64/RISC-V
## cannot emit a word-0-only store. Struct literals remain supported; unknown/scalar values stay open for
## the ordinary type checks and all local/field/index assignment paths remain untouched.
global_nonlit_struct_assign_bad := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize, v : ptr(Expr), tv : Ty, locals : ptr(LVec), nloc : usize) -> bool {
  if expr_agg_lit(v).is_agg { return false }
  mut vt := tv
  if vt.tag != 3 { vt = value_agg_ty(v, decls, upto, src, locals, nloc) }
  if vt.tag != 3 { vt = expr_call_result_ty(v, decls, upto, src) }
  if vt.tag != 3 { return false }
  global_struct_type_span(decls, src, s, n).n != 0
}
## The explicit byte-array component accepted by the standard tuple-local tier (Types §6.1). This is
## deliberately narrower than every byte-sized scalar: only a direct `[u8|i8|bits8; N]` component
## selects the byte tuple representation. A nested array/struct or an ordinary tuple stays outside this
## fence, as do tuple parameters and returns handled by the existing lower guard.
sema_byte_array_elem := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 2 and (str_at((src + s), 2) == "u8" or str_at((src + s), 2) == "i8") { return true }
  n == 5 and str_at((src + s), 5) == "bits8"
}
sema_tuple_has_direct_byte_array := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  if tl == 0 or str_at((src + ts), 1) != "(" { return false }
  mut i := 0
  mut found := false
  mut scanning := true
  while scanning {
    cs := typearg_at(src, ts, 0, usize(i))
    if cs.n == 0 { scanning = false } else {
      ae := array_elem_span(src, cs.s, cs.n)
      if ae.n != 0 and sema_byte_array_elem(src, ae.s, ae.n) { found = true }
      i += 1
    }
  }
  found
}
## A module-level VALUE declaration with an explicit tuple annotation containing a direct standard byte
## array is outside the word-based global ABI. Do not inspect inferred values, locals, fields, indexes,
## parameters, returns, packed types, or ordinary tuples here: this is the exact pre-emission boundary
## already enforced by lower::validate_standard_byte_tuple_boundaries.
sema_standard_tuple_global_bad := fn(d : Decl, src : ptr(u8)) -> bool {
  if d.is_fn or d.kind != 0 or d.ret_tl != 0 or d.arity != 0 { return false }
  ## Use the CURRENT declaration's source occurrence. A bare-name lookup is unsound when two package
  ## modules both declare `G`: it can inspect the other module's annotation and either miss the unsafe
  ## byte tuple or reject a harmless ordinary tuple. `name_start` is the parser-owned occurrence for
  ## this Decl, so it carries the module identity without widening the AST.
  ann := local_type_span(src, d.name_start, d.name_len)
  ann.n != 0 and sema_tuple_has_direct_byte_array(src, ann.s, ann.n)
}
## RETURN-sink conformance: recursively scan a fn body for a `return <v>` whose value is an aggregate↔
## scalar clash against the declared return type span `[rts,rtl)` (both directions, via `agg_scalar_bad`).
## Recurses into nested control-flow blocks so a return in an if/while/for/match branch is covered. This
## is the float/char-aware complement to `check_stmts`' tag-only `ret_tag` return check (which already
## covers int/bool/struct/enum). Poison-tolerant.
ret_agg_bad := fn(head : ptr(mut Stmt), rts : usize, rtl : usize, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut res := false
  while cur != 0 {
    st := deref(stmt_p(Stmt, cur))
    match st {
      ## …and Types §9.1 REPRESENTABILITY in the DECLARED RETURN type, which is likewise the context
      ## the returned literal takes its type from (Declarations §3.4): `g := fn() -> u8 { return 300 }`
      ## was accepted in silence. Same walker, same span — `[rts, rtl)` IS the return type name.
      Stmt::Return(rv, nx) => { if agg_scalar_bad(rts, rtl, rv, decls, upto, src, locals, nloc) or ann_lit_range_bad(src, rts, rtl, rv) { res = true } }
      Stmt::If(c, th, el, nx) => { if ret_agg_bad(th, rts, rtl, decls, upto, src, locals, nloc, a) or ret_agg_bad(el, rts, rtl, decls, upto, src, locals, nloc, a) { res = true } }
      Stmt::While(c, b, nx) => { if ret_agg_bad(b, rts, rtl, decls, upto, src, locals, nloc, a) { res = true } }
      Stmt::Loop(b, nx) => { if ret_agg_bad(b, rts, rtl, decls, upto, src, locals, nloc, a) { res = true } }
      Stmt::Unchecked(b, nx) => { if ret_agg_bad(b, rts, rtl, decls, upto, src, locals, nloc, a) { res = true } }
      Stmt::AllocWith(ae, b, nx) => { if ret_agg_bad(b, rts, rtl, decls, upto, src, locals, nloc, a) { res = true } }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if ret_agg_bad(b, rts, rtl, decls, upto, src, locals, nloc, a) { res = true } }
      Stmt::Match(sc, ah, nx) => {
        mut arm := ah
        while arm != 0 { am := deref(arm_p(arm)); if ret_agg_bad(am.body_stmts, rts, rtl, decls, upto, src, locals, nloc, a) { res = true }; arm = am.next }
      }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  res
}

## CT-12 RETURN sink: a `return <expr>` is an integer-context sink when the enclosing function
## declares `-> T`. Reuse the same checked-comptime walker as annotated/module bindings so a literal
## overflow (or a previously-resolved constant expression) is diagnosed at its arithmetic site. This
## deliberately does not type/evaluate runtime returns, and `ct_check` preserves `unchecked` wrapping.
ct_return_guard_err := fn(head : ptr(mut Stmt), rts : usize, rtl : usize, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> CheckErr {
  mut cur := head
  while cur != 0 {
    st := deref(stmt_p(Stmt, cur))
    mut got : CheckErr = 0
    match st {
      Stmt::Return(rv, nx) => { got = ct_guard_err(src, rts, rtl, rv, s_of(rv, a), decls, upto) }
      Stmt::If(c, th, el, nx) => {
        got = ct_return_guard_err(th, rts, rtl, decls, upto, src, a)
        if got == 0 { got = ct_return_guard_err(el, rts, rtl, decls, upto, src, a) }
      }
      Stmt::While(c, b, nx) => { got = ct_return_guard_err(b, rts, rtl, decls, upto, src, a) }
      Stmt::Loop(b, nx) => { got = ct_return_guard_err(b, rts, rtl, decls, upto, src, a) }
      Stmt::Unchecked(b, nx) => { got = ct_return_guard_err(b, rts, rtl, decls, upto, src, a) }
      Stmt::AllocWith(ae, b, nx) => { got = ct_return_guard_err(b, rts, rtl, decls, upto, src, a) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { got = ct_return_guard_err(b, rts, rtl, decls, upto, src, a) }
      Stmt::Match(sc, ah, nx) => {
        mut arm := ah
        while arm != 0 and got == 0 {
          am := deref(arm_p(arm))
          got = ct_return_guard_err(am.body_stmts, rts, rtl, decls, upto, src, a)
          arm = am.next
        }
      }
      _ => {}
    }
    if got != 0 { return got }
    cur = stmt_next_at(cur, a)
  }
  0
}

## The declared return `Ty` of the top-level fn named [s, s+n) (a kind-1 decl), if any; unknown
## otherwise. Used to type-check a `Call`'s result.
callee_ret_ty := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize) -> Ty {
  mut r := Ty(tag = 0, ns = 0, nl = 0)
  cnt := rt::vec_len(deref(decls))
  th := sema_name_hash(src, s, n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < upto and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
      d := deref(decl_get(decls, i))
      if d.kind == 1 and streq(src, d.name_start, d.name_len, s, n) {
        r = resolve_ty(src, d.ret_ts, d.ret_tl, decls, upto)
      }
    }
  }
  r
}

## Recover a call expression's declared result type directly, bypassing the packed `Result(Ty, …)`
## carrier used by `check_expr`. The carrier intentionally preserves only the tag; this helper keeps
## the same conservative unknown result for indirect, overloaded, generic, qualified, or unresolved
## calls, while making a known direct/UFCS call result available to an enclosing argument or return sink.
## TYP-6 conversion expressions are represented by the parser as ordinary one-argument Calls. The lower
## already intercepts these names before generic call emission, so the sema mirror must give the integer
## conversions their scalar tag here as well; otherwise `return u64(x)` can pass check and later link
## against a nonexistent `__u64` function. This is deliberately a name whitelist, not width-aware checking.
sema_builtin_integer_cast_name := fn(name : str) -> bool {
  if name == "usize" or name == "isize" or name == "u8" or name == "u16" or name == "u32" or name == "u64" { return true }
  if name == "i8" or name == "i16" or name == "i32" or name == "i64" { return true }
  false
}

expr_call_result_ty := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8)) -> Ty {
  cs := expr_call_callee_span(e)
  if cs.n == 0 { return Ty(tag = 0, ns = 0, nl = 0) }
  if expr_call_arity(e) == 1 and sema_builtin_integer_cast_name(str_at((src + cs.s), cs.n)) {
    return Ty(tag = 1, ns = cs.s, nl = cs.n)
  }
  callee_ret_ty(decls, upto, src, cs.s, cs.n)
}

## Is a direct CALL's uniquely resolved exact-arity callee an aggregate return? This is the sema-side
## mirror of the lower's global-init fence, deliberately kept conservative: only one exact-name,
## exact-arity declaration is classified, and qualified/overloaded/defaulted/indirect calls stay for
## the existing backend boundary. A false negative leaves the lower's established reject in place; a
## false positive here would reject a valid global, so no tail-name fallback is guessed. The return
## spelling covers the aggregate families in this slice that are visible without lowering state: named
## struct/enum, tuple, str, and Slice(T). Fixed-array call returns stay outside this issue's boundary;
## their existing lower-side byte-array guard remains authoritative.
sema_call_returns_aggregate := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  cs := expr_call_callee_span(e)
  if cs.n == 0 { return false }
  nargs := expr_call_arity(e)
  cnt := rt::vec_len(deref(decls))
  mut chosen : i64 = -1
  mut matches := 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and d.arity == nargs and streq(src, d.name_start, d.name_len, cs.s, cs.n) { chosen = i64(i); matches += 1 }
    i += 1
  }
  if chosen < 0 or matches != 1 { return false }
  d := deref(decl_get(decls, usize(chosen)))
  if d.ret_tl == 0 { return false }
  if struct_decl_of(decls, src, d.ret_ts, d.ret_tl) >= 0 { return true }
  if enum_decl_of(decls, src, d.ret_ts, d.ret_tl) >= 0 { return true }
  head := str_at((src + d.ret_ts), 1)
  if head == "(" { return true }
  bn := base_type_name(src, d.ret_ts, d.ret_tl)
  if bn.n != 0 {
    bt := str_at((src + bn.s), bn.n)
    if bt == "str" or bt == "Slice" { return true }
  }
  false
}

## A CONST module-level VALUE with a runtime aggregate CALL has no executable initialization phase.
## Keep this predicate byte-for-byte aligned with lower::emit_rodata_decl's proven fence: mutable globals,
## function/type metadata, and non-call initializers remain on their existing paths. The declaration's
## name span is the stable diagnostic location, independent of where the callee was declared.
sema_global_init_call_bad := fn(d : Decl, decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  if d.is_fn or d.kind != 0 or d.ret_tl != 0 or d.arity != 0 { return false }
  if local_is_mut(src, d.name_start) { return false }
  if unchecked bitcast(usize, d.value) == 0 { return false }
  sema_call_returns_aggregate(d.value, decls, src)
}

## Types §4.2/§4.4 — a string value has no value-conversion path into an integer. The lower treats
## the builtin integer names as conversion constructors, so this narrow pre-match guard keeps ordinary
## sema and `compiles(...)` in agreement for the literal form whose type is certain. A user `@convert`
## remains a separate explicit constructor surface; this helper does not search or invent one.
sema_builtin_str_integer_cast_bad := fn(e : ptr(Expr), src : ptr(u8)) -> bool {
  cs := expr_call_callee_span(e)
  if cs.n == 0 or expr_call_arity(e) != 1 { return false }
  if not sema_builtin_integer_cast_name(str_at((src + cs.s), cs.n)) { return false }
  ah := expr_call_args_head(e)
  if ah == 0 { return false }
  ga := deref(arg_p(ah))
  ## Use the existing exhaustive literal classifier: a payload-heavy direct match on StrLit is not
  ## reliable in the frozen bootstrap lowering, while lbv_lit_tag is already the proven literal path.
  lbv_lit_tag(ga.e) == 6
}

## A known enum/union variant name must be present in the declaration's field list. An unresolved type
## stays fail-open: this helper is only a check for `E.Zzz` after `E` itself has resolved, so it never
## guesses about qualified/generic types that the current sema cannot identify.
sema_enum_variant_known := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), es : usize, el : usize, vs : usize, vl : usize) -> bool {
  mut matched := false
  mut found := false
  mut i := 0
  while i < upto {
    d := deref(decl_get(decls, i))
    if d.kind == 3 and name_matches(src, d.name_start, d.name_len, es, el) {
      matched = true
      mut f := d.fields_head
      while f != 0 {
        fd := deref(fld_p(f))
        if streq(src, fd.ns, fd.nl, vs, vl) { found = true }
        f = fd.next
      }
    }
    i += 1
  }
  if not matched { return true }
  found
}

## The declared `Ty` of the i-th parameter of the top-level fn named [s, s+n) (param index by
## walk order); unknown if the fn/param is absent. Used to type-check a `Call`'s i-th argument.
callee_param_ty := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize, pidx : usize, a : ptr(mut rt::Arena)) -> Ty {
  mut r := Ty(tag = 0, ns = 0, nl = 0)
  cnt := rt::vec_len(deref(decls))
  th := sema_name_hash(src, s, n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < upto and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and streq(src, d.name_start, d.name_len, s, n) {
      mut pp := d.params_head
      mut k := 0
      while pp != 0 {
        pm := deref(param_p(pp))
        if k == pidx { r = resolve_ty(src, pm.ts, pm.tl, decls, upto) }
        k += 1
        pp = pm.next
      }
    }
    }
  }
  r
}

## Does the decl's LAST parameter use the bare comptime-variadic rest type `...`? The parser records it
## as a type span whose first two bytes are `..` (the third dot is consumed, like lower::decl_is_variadic).
decl_is_variadic := fn(d : Decl, src : ptr(u8)) -> bool {
  if d.arity == 0 { return false }
  mut p := d.params_head
  mut last := d.params_head
  while p != 0 { pm := deref(param_p(p)); last = p; p = pm.next }
  lp := deref(param_p(last))
  lp.tl >= 2 and str_at((src + lp.ts), 2) == ".."
}

## Does the decl's LAST parameter use the §7.2 SLICE-variadic rest `...T` (`pmode == 3`)? Such a callee
## accepts ANY number of trailing arguments after its fixed params (gathered into one `[T]` slice), so
## the arity check treats it like the comptime variadic. (The parser marks it `pmode == 3` with `ts`/`tl`
## = the element type — distinct from the comptime `...`, whose `ts` is the `..` span.)
decl_is_slice_variadic := fn(d : Decl) -> bool {
  if d.arity == 0 { return false }
  mut p := d.params_head
  mut last := d.params_head
  while p != 0 { pm := deref(param_p(p)); last = p; p = pm.next }
  deref(param_p(last)).pmode == 3
}

## Do the parameters `[nargs, stop)` of a fn (its `params_head` list) ALL carry a §5.1 default? `stop`
## lets comptime-variadic arity check cover only the FIXED params before the `...` rest.
params_defaults_cover_until := fn(params_head : ptr(mut Param), stop : usize, src : ptr(u8), nargs : usize, a : ptr(mut rt::Arena)) -> bool {
  mut pp := params_head
  mut k := 0
  mut ok := true
  while pp != 0 and k < stop {
    pm := deref(param_p(pp))
    if k >= nargs and not (str_at((src + pm.ts), pm.tl) != "ptr" and pm.pps != 0) { ok = false }
    k += 1
    pp = pm.next
  }
  ok
}

## Do the parameters `[nargs, arity)` of a fn (its `params_head` list) ALL carry a §5.1 default, so a
## call supplying only `nargs` positional args is well-formed (the lower fills the omitted trailing
## ones — FN-5)? A default is a non-pointer value param whose `pps != 0` (the parser stores the default
## `Expr` pointer there; `pps` is read as a pointee span ONLY for a `ptr` param, so this reuse is
## unambiguous). A trailing param WITHOUT a default → false (a genuine arity error). `src/` has no
## defaults → every trailing param fails the test, so a short call stays rejected → check unchanged.
params_defaults_cover := fn(params_head : ptr(mut Param), arity : usize, src : ptr(u8), nargs : usize, a : ptr(mut rt::Arena)) -> bool {
  params_defaults_cover_until(params_head, arity, src, nargs, a)
}

## Concrete call arity against the known overload set: -1 no known function (forward/external call,
## left unresolved), 0 a known name but no matching arity, 1 at least one signature matches. A comptime
## variadic callee accepts any arg count after its fixed params; if the call supplies fewer than the fixed
## count, the omitted fixed tail must be covered by §5.1 defaults.
call_arity_match := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize, nargs : usize, a : ptr(mut rt::Arena)) -> i64 {
  mut state := -1
  th := sema_tail_hash(src, s, n)
  cnt := rt::vec_len(deref(decls))
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < upto and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
    d := deref(decl_get(decls, i))
    if (d.kind == 1 or d.kind == 4) and name_matches(src, d.name_start, d.name_len, s, n) {
      if state < 0 { state = 0 }
      if decl_is_variadic(d, src) {
        nf := d.arity - 1
        if nargs >= nf { state = 1 }
        if nargs < nf and params_defaults_cover_until(d.params_head, nf, src, nargs, a) { state = 1 }
      } else if decl_is_slice_variadic(d) {
        ## §7.2 slice variadic: any arg count >= the fixed-param count (the rest gathers into a `[T]`).
        nfs := d.arity - 1
        if nargs >= nfs { state = 1 }
        if nargs < nfs and params_defaults_cover_until(d.params_head, nfs, src, nargs, a) { state = 1 }
      } else {
        if d.arity == nargs { state = 1 }
        if nargs < d.arity and params_defaults_cover(d.params_head, d.arity, src, nargs, a) { state = 1 }
      }
    }
    }
  }
  state
}

## Is the callee `[s, s+n)` DECLARED anywhere in the program (a top-level fn/type/const/import, by
## tail-name — so a qualified `mod::f` resolves)? Searches the WHOLE decl list, not just `[0..upto)`:
## a callee may be defined LATER (use-before-decl is legal). Any decl kind counts (a bare `Point(…)`
## tuple-constructor names a TYPE) — maximally permissive so the undefined-callee diagnostic below
## never wrong-rejects a forward reference or a constructor call.
callee_declared_anywhere := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  cnt := rt::vec_len(deref(decls))
  th := sema_tail_hash(src, s, n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th {
      d := deref(decl_get(decls, i))
      if name_matches(src, d.name_start, d.name_len, s, n) { return true }
    }
    i += 1
  }
  false
}

## Skip the whitespace run at `p0` (bounded by `lim`) — the type-text scanner's step. Mirrors the
## lower's `fnty_skip_ws`.
sema_fnty_skip_ws := fn(src : ptr(u8), p0 : usize, lim : usize) -> usize {
  mut p := p0
  mut done := false
  while p < lim and done == false {
    c := str_at((src + p), 1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { p = p + 1 } else { done = true }
  }
  p
}

## The end offset of the TYPE NAME starting at `p0` — the run that is neither whitespace nor a type-text
## punctuator. A `mod::Type` tail stays whole; a `ptr(u8)` / `Vec(T)` head stops at its `(`, which is all
## the scalar classification needs. Mirrors the lower's `fnty_name_end`.
sema_fnty_name_end := fn(src : ptr(u8), p0 : usize, lim : usize) -> usize {
  mut p := p0
  mut done := false
  while p < lim and done == false {
    c := str_at((src + p), 1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { done = true }
    if c == "(" or c == ")" or c == "," or c == "{" or c == "}" or c == "=" or c == ";" { done = true }
    if done == false { p = p + 1 }
  }
  p
}

## The RETURN-type name span of the fn-value type text whose `fn` keyword sits at `p0` (`fn(A, B) -> R`
## → `R`); {0,0} when the text is not such a type or declares no return. Mirrors the lower's
## `fnty_params_end` + `fnty_ret_span` pair: it scans FORWARD from `p0` (a field's recorded type span
## keeps the head, and the `-> R` tail follows it verbatim in the source), balancing the parameter list
## before reading the arrow.
sema_fnty_ret_span := fn(src : ptr(u8), p0 : usize) -> VSpan {
  lim := p0 + 512
  if str_at((src + p0), 2) != "fn" { return VSpan(s = 0, n = 0) }
  mut p := sema_fnty_skip_ws(src, p0 + 2, lim)
  if str_at((src + p), 1) != "(" { return VSpan(s = 0, n = 0) }
  mut d := 0
  mut pe := 0
  while p < lim {
    c := str_at((src + p), 1)
    if c == "(" { d = d + 1 }
    if c == ")" {
      if d > 0 { d = d - 1 }
      if d == 0 { pe = p + 1; p = lim } else { p = p + 1 }
    } else { p = p + 1 }
  }
  if pe == 0 { return VSpan(s = 0, n = 0) }
  mut q := sema_fnty_skip_ws(src, pe, lim)
  if str_at((src + q), 2) != "->" { return VSpan(s = 0, n = 0) }
  q = sema_fnty_skip_ws(src, q + 2, lim)
  e := sema_fnty_name_end(src, q, lim)
  if e == q { return VSpan(s = 0, n = 0) }
  VSpan(s = q, n = e - q)
}

## Does the type text `[s, s+n)` name a ONE-WORD SCALAR — an integer / bool / float / char / bit-block /
## pointer? Deliberately an ALLOWLIST: an aggregate (`str`, a declared struct/enum, an array), a generic
## type parameter and anything unrecognized all answer false, so a caller that gates on it stays on the
## conservative side.
sema_ty_is_scalar := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return false }
  nm := str_at((src + s), n)
  return nm == "u8" or nm == "u16" or nm == "u32" or nm == "u64" or nm == "usize"
    or nm == "i8" or nm == "i16" or nm == "i32" or nm == "i64" or nm == "isize"
    or nm == "f32" or nm == "f64" or nm == "bool" or nm == "char"
    or nm == "bits8" or nm == "bits16" or nm == "bits32" or nm == "bits64"
    or nm == "ptr"
}

## FN-10 — is `[s, s+n)` the NAME of a fn-VALUE-typed FIELD (`f : fn(T…) -> R`) of SOME declared
## struct/enum/union? A call THROUGH such a field — `o.f(41)` — is desugared by the parser into a UFCS
## `Call(f, [o, 41])`, so its callee names neither a declared fn nor a local and the undefined-callee
## diagnostic rejected it as an "unbound name" even though the LOWER resolves it correctly (the
## `fn_field_call_slot` field-indirect path). The two-arg form only LOOKED supported because the corpus
## fixture happens to hold a same-named LOCAL that the `local_in` exemption above catches. Exempt the
## shape here instead. Deliberately permissive — whole-program and receiver-independent, mirroring
## `callee_declared_anywhere`'s "any decl by tail-name exempts the call" philosophy: it only ever ADDS
## acceptance (a callee resolving to NO decl, NO built-in, NO local and NO fn-typed field anywhere is
## still rejected), and the lower/link stay the terminal arbiter. `src/` + `lib/` declare NO fn-typed
## field, so this never fires on the self-build → the check verdict is unchanged → fixpoint-neutral.
##
## Restricted to a field whose fn type returns a ONE-WORD SCALAR. An AGGREGATE-returning field call
## BOUND to a local (`p := o.g(40)` for `g : fn(u64) -> P`) is resolved by the lower BEFORE the slot
## table exists, so the destination is sized as a scalar and every field of `p` reads garbage — the
## lower's own `fnfield_call_ret_span` documents that this shape "stays fail-loud in `check`". Exempting
## it would turn a loud reject into a SILENT MISCOMPILE, so the aggregate return classes stay rejected
## here. (The enum SCRUTINEE form `match o.g(x)` never needed this exemption — a `Stmt::Match` scrutinee
## is not walked by the undefined-callee diagnostic — and keeps working through `fnfield_call_ret_enum`.)
callee_is_fn_valued_field := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut r := false
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 2 or d.kind == 3 {
      mut f := d.fields_head
      while f != 0 {
        fd := deref(fld_p(f))
        if streq(src, fd.ns, fd.nl, s, n) and fd.tl >= 3 and str_at((src + fd.ts), 3) == "fn(" {
          rt2 := sema_fnty_ret_span(src, fd.ts)
          if sema_ty_is_scalar(src, rt2.s, rt2.n) { r = true }
        }
        f = fd.next
      }
    }
    i += 1
  }
  r
}

## FN-11 — is the local TYPE-ANNOTATION text `[s, s+n)` a `dyn fn(…) -> R` type (the `dyn` keyword
## prefixing a function-value type, Functions §1.6)? Mirrors the lower's `is_dyn_type`; kept here so
## sema can police the construction form without importing the emit module.
sema_is_dyn_type := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n < 4 { return false }
  if str_at((src + s), 3) != "dyn" { return false }
  c := str_at((src + s + 3), 1)
  c == " " or c == "\t" or c == "\n" or c == "\r"
}

## FN-10 — is the field type text `[s, s+n)` a PLAIN function value (`fn(...) -> R`), not
## the two-word `dyn fn(...) -> R` closure pair? Keep this lexical: `resolve_ty` intentionally treats
## function values as scalar/unknown, while this distinction is the ABI boundary that must reject a
## captured environment before any backend sees the lambda.
sema_is_plain_fn_type := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n < 3 or str_at((src + s), 2) != "fn" { return false }
  mut p := s + 2
  end := s + n
  while p < end {
    c := str_at((src + p), 1)
    if c == " " or c == "\t" or c == "\n" or c == "\r" { p = p + 1 }
    else { return c == "(" }
  }
  false
}

## FN-11 — is `e` the prelude construction call `dyn_over(…)`? The ONLY form the spec admits as the
## initializer of a `dyn fn(T…)->R` binding (Functions §1.6: "constructed by `dyn_over` over a named
## place"). Mirrors the lower's `is_dyn_over_call`.
sema_is_dyn_over_call := fn(e : ptr(Expr), src : ptr(u8)) -> bool {
  cs := expr_call_callee_span(e)
  if cs.n == 0 { return false }
  str_at((src + cs.s), cs.n) == "dyn_over"
}

## Is the callee `[s, s+n)` a comptime TYPE-BUILTIN whose arguments are TYPE names, not values
## (`size(T)`, `align(T)`, `typeinfo(T)`)? A type-shaped argument must not be walked as an unbound
## VALUE — the `expr_has_unbound` Call arm consults this (next-up #2; Types §6.4/§6.5).
callee_is_type_builtin := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  nm := str_at((src + s), n)
  nm == "size" or nm == "align" or nm == "typeinfo"
}

## Is `e` a TYPE-shaped argument to a comptime type-builtin: a bare Var naming a KNOWN type (a scalar
## spelling or a declared struct/enum/union), a tuple type `(T0, T1, …)`, a generic type constructor
## such as `Option(T)`, or an array-TYPE literal `[T; N]`? Such an argument is not a value expression —
## its inner type names must not trip the unbound walk.
sema_type_arg_ok := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  ev := expr_var_span(e)
  if ev.n != 0 { return type_name_known(decls, src, ev.s, ev.n) }
  mut ok := false
  match deref(e) {
    Expr::ArrayLit(nel, ah) => {
      if nel == 0 { ok = true }
      else {
        ok = true
        mut g := ah
        while g != 0 {
          ga := deref(arg_p(g))
          if not sema_type_arg_ok(ga.e, decls, src) { ok = false }
          g = ga.next
        }
      }
    }
    Expr::Call(cs, cl, na, ah) => {
      ## A known struct/enum type-function (`Option`, `Result`, `Slice`, …), or the builtin pointer
      ## constructor, is a type expression when all of its arguments are themselves type expressions.
      head_ok := type_name_known(decls, src, cs, cl) or str_at((src + cs), cl) == "ptr"
      if head_ok {
        ok = true
        mut g := ah
        while g != 0 {
          ga := deref(arg_p(g))
          if not sema_type_arg_ok(ga.e, decls, src) { ok = false }
          g = ga.next
        }
      }
    }
    _ => {}
  }
  if ok { return true }
  mut es : usize = 0
  mut en : usize = 0
  array_type_lit(e, decls, src, es, en) >= 0
}

## Return the source span of a DIRECT type-builtin argument that names no known type, or 0.  This is
## deliberately narrower than a general type checker: it covers only a bare NAME in a package-owned
## nested module.  Qualified paths/aliases, generic type expressions, sibling-private resolution and
## signature annotations remain separate slices.  A preceding dot identifies the UFCS/value form
## (`x.size()`), whose first argument is a value rather than a type name and must stay on its existing
## path.
sema_package_type_builtin_arg_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) -> usize {
  if SEMA_PACKAGE_MODULES_N == 0 or not sema_module_in_package(src, cs, cl) { return 0 }
  if cs != 0 and str_at((src + cs - 1), 1) == "." { return 0 }
  ev := expr_var_span(e)
  if ev.n == 0 { return 0 }
  if sema_gref_split(src, ev.s, ev.n).qual { return 0 }
  if not type_name_known(decls, src, ev.s, ev.n) { return ev.s }
  0
}

## Is the callee `[s, s+n)` a BUILT-IN callee — a prelude identifier the lower handles directly rather
## than a declared fn? Covers the width/type CASTS (`u32(x)`, `f64(x)`, `bits32(x)`), the
## layout/pointer METHODS reached via UFCS `x.m()` → `Call(m, [x])` (`ptr`/`len`/`size`/`align`),
## `typeinfo`, and the lower's special-cased intrinsics (`bytes`/`sub`/`expect`). A call to one of
## these is legal even though no `fn` declares it, so the undefined-callee diagnostic must exempt it.
is_builtin_callee := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  ## match on the TAIL name (after the last `::`) so a QUALIFIED intrinsic (`atomic::load`,
  ## `atomic::fetch_add`) resolves like its bare form — mirrors name_matches' tail logic.
  mut tail := s
  mut i := 0
  while i + 1 < n {
    if str_at((src + s + i), 2) == "::" { tail = s + i + 2 }
    i += 1
  }
  nm := str_at((src + tail), n - (tail - s))
  return nm == "u8" or nm == "u16" or nm == "u32" or nm == "u64" or nm == "usize"
    or nm == "i8" or nm == "i16" or nm == "i32" or nm == "i64" or nm == "isize"
    or nm == "f32" or nm == "f64" or nm == "bool" or nm == "char" or nm == "str"
    or nm == "bits8" or nm == "bits16" or nm == "bits32" or nm == "bits64"
    or nm == "typeinfo" or nm == "ptr" or nm == "len" or nm == "size" or nm == "align"
    or nm == "resolves" or nm == "compiles"
    or nm == "bytes" or nm == "sub" or nm == "expect" or nm == "bitcast"
    ## Stage-0 STR/BYTE + shift/rotate + control intrinsics the lower emits directly (no `fn`
    ## declares them in `src/` — `lib/base/str.al`'s `str_at`/`str_eq` are shadowed by the lower's
    ## intrinsic emit): a call to one is legal though unresolvable, so exempt it.
    or nm == "str_at" or nm == "str_eq" or nm == "byte_at"
    or nm == "shl" or nm == "shr" or nm == "rotl" or nm == "rotr"
    or nm == "panic" or nm == "forget"
    or nm == "load" or nm == "store" or nm == "swap" or nm == "fence"
    or nm == "fetch_add" or nm == "fetch_sub" or nm == "fetch_and" or nm == "fetch_or"
    or nm == "fetch_xor" or nm == "compare_exchange" or nm == "exchange"
    or nm == "cas_strong" or nm == "cas_weak"   ## atomic COMPARE-AND-SWAP intrinsics (spec ch.110 §2), lowered to `lock cmpxchgq`
    or nm == "dyn_over"   ## FN-11 type-erased `dyn fn(…)->R` fat-pair constructor over an explicit place (spec §Functions §1.6)
    or nm == "movq" or nm == "addq" or nm == "subq" or nm == "andq" or nm == "orq" or nm == "xorq" or nm == "shlq" or nm == "shrq" or nm == "sarq" or nm == "imulq" or nm == "negq" or nm == "notq" or nm == "syscall" or nm == "ret" or nm == "asm"   ## raw-asm instruction intrinsics + escape (spec ch.80 §2/§4)
}

## Is `[s, s+n)` an x86_64 GP register name (spec ch.80 §6 — an arch-data prelude identifier, not a
## keyword)? Register operands (`movq(rax, 60)`) are ordinary `Var` exprs, so `check` must treat them as
## bound (not unbound names). Case-sensitive lowercase, matching the arch table.
is_register_name := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  nm := str_at((src + s), n)
  return nm == "rax" or nm == "rbx" or nm == "rcx" or nm == "rdx" or nm == "rsi" or nm == "rdi"
    or nm == "rbp" or nm == "rsp" or nm == "r8" or nm == "r9" or nm == "r10" or nm == "r11"
    or nm == "r12" or nm == "r13" or nm == "r14" or nm == "r15"
}

## The variant/field NAME of a prelude enum literal (`Ordering.acquire` → "acquire"), else "". Handles
## both the `Field` (`Ordering.acquire`) and nullary-`EnumLit` (`Ordering.acquire()`) spellings. A
## single-level fn-body match (avoids a nested `match … return`, which the seed miscompiles).
field_variant_name := fn(e : ptr(Expr), src : ptr(u8)) -> str {
  match deref(e) {
    Expr::Field(base, fs, fl) => { if is_prelude_ns_var(base, src) { str_at((src + fs), fl) } else { "" } }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { if str_at((src + es), el) == "Ordering" { str_at((src + vs), vl) } else { "" } }
    _ => { "" }
  }
}
## The `Ordering.<variant>` name of the arg at index `i` of a call's arg list, else "".
ordering_arg_name := fn(ah : ptr(mut Arg), i : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> str {
  mut g := ah
  mut k := 0
  while g != 0 {
    ga := deref(arg_p(g))
    if k == i { return field_variant_name(ga.e, src) }
    k += 1
    g = ga.next
  }
  ""
}
## Ordering strength rank (relaxed < acquire = release < acq_rel < seq_cst); -1 for unknown/non-literal.
ordering_rank := fn(o : str) -> i64 {
  if o == "relaxed" { return 0 }
  if o == "acquire" { return 1 }
  if o == "release" { return 1 }
  if o == "acq_rel" { return 2 }
  if o == "seq_cst" { return 3 }
  -1
}
## True if the atomic call `[cs,cl)(…)` uses an ILLEGAL ordering for its operation (spec ch.110 §2/§3,
## same constraints as C11): `atomic::load` ∈ {relaxed,acquire,seq_cst}; `atomic::store` ∈
## {relaxed,release,seq_cst}; `fence` ∈ {acquire,release,acq_rel,seq_cst} (relaxed illegal); a CAS
## FAILURE ordering ∈ {relaxed,acquire,seq_cst} and MUST NOT be stronger than success; RMW = any. An
## unrecognized / non-literal ordering is left unchecked — only clear violations are rejected.
atomic_ordering_bad := fn(cs : usize, cl : usize, ah : ptr(mut Arg), src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  nm := str_at((src + cs), cl)
  if nm == "atomic::load" {
    o := ordering_arg_name(ah, 1, src, a)
    return o == "release" or o == "acq_rel"
  }
  if nm == "atomic::store" {
    o := ordering_arg_name(ah, 2, src, a)
    return o == "acquire" or o == "acq_rel"
  }
  if nm == "fence" {
    return ordering_arg_name(ah, 0, src, a) == "relaxed"
  }
  if nm == "atomic::cas_strong" or nm == "atomic::cas_weak" {
    fl := ordering_arg_name(ah, 4, src, a)
    if fl == "release" or fl == "acq_rel" { return true }
    oknm := ordering_arg_name(ah, 3, src, a)
    ro := ordering_rank(oknm)
    rf := ordering_rank(fl)
    if ro < 0 { return false }
    if rf < 0 { return false }
    if rf > ro { return true }
    return false
  }
  false
}
## `atomic_ordering_bad` lifted to an arbitrary expression: true iff `e` is a `Call` with an illegal
## atomic ordering. Lets a STATEMENT-position bare call (`atomic::store(…)`) be checked directly.
call_atomic_ordering_bad := fn(e : ptr(Expr), src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => { atomic_ordering_bad(cs, cl, ah, src, a) }
    _ => { false }
  }
}
## Name-resolution prepass for one expression. It is deliberately scalar: the self-host ABI can
## lose an error encoded inside the wide `Result(Ty, _)` returned by type synthesis. Calls may name
## later declarations, matching the existing call rule; their argument expressions are resolved.
## The inner VALUE of a preserved `Expr::Bitcast` (`bitcast(ptr(<sub-word>), v)`), or null when `e`
## is not that node. Standalone pointer-PARAM helper (a `match deref(e)` in its own fn dispatches
## reliably under the seed, unlike an added arm in a big payload match). Used by the two EXHAUSTIVE
## (wildcard-free) Expr walkers — `expr_has_unbound` + `check_expr` — to unwrap the transparent node
## pre-match, so a missing arm never falls through and MISREADS the payload as a `Var`.
bitcast_inner := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Bitcast(inner, ps, pl) => { r = inner }
    _ => {}
  }
  r
}

## Name-only resolution walk for an expression that is used for its effect or as a control condition.
## This is intentionally separate from `expr_has_unbound`: that older prepass also performs call-arity and
## argument-type checks, which are valid on ordinary value/RHS paths but would misclassify type-builtin
## operands (`size(T)`) and compiler-synthesized defer markers when applied to every discarded expression.
## Keep this walk limited to binding/field existence; the ordinary checker remains responsible for types,
## arity, and all deferred/target-specific rules.
expr_statement_has_unbound := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> bool {
  if unchecked bitcast(usize, e) == 0 { return false }
  ubci := bitcast_inner(e)
  if unchecked bitcast(usize, ubci) != 0 { return expr_statement_has_unbound(ubci, decls, upto, src, a, locals, nloc) }
  match deref(e) {
    Expr::Num(v, s, n) => { false }
    Expr::BoolLit(v) => { false }
    Expr::FloatLit(s, n) => { false }
    Expr::StrLit(s, n, lbl, _ps, _pn) => { false }
    Expr::Var(s, n) => {
      mut found := false
      if nloc != 0 { found = local_in(locals, nloc, src, s, n) }
      if not found { found = declared(decls, rt::vec_len(deref(decls)), src, s, n) }
      if not found { found = is_register_name(src, s, n) }
      if not found { found = remembered(locals, src, s, n) }
      not found
    }
    ## Compound expressions are left to the established value checker here. Its payload-heavy
    ## dispatch is intentionally not duplicated in this statement-only fence; direct Var/Call/Field
    ## roots cover this issue's dropped statement values without changing existing arithmetic, match,
    ## layout, or control-flow expression paths.
    Expr::Bin(op, l, r) => { false }
    Expr::If(c, t, f) => { false }
    Expr::Match(scrut, head) => { false }
    Expr::Call(cs, cl, na, ah) => {
      nm := str_at((src + cs), cl)
      ## These names are parser-only defer markers, not user calls. Their action/body is checked by the
      ## established defer-aware paths; treating the marker as an ordinary unresolved call would reject
      ## every valid `defer` before lower can register it.
      if nm == "__defer" or nm == "__deferblk" or nm == "__deferblkend" { return false }
      mut bad := false
      mut callee_ok := callee_declared_anywhere(decls, src, cs, cl) or is_builtin_callee(src, cs, cl)
      if not callee_ok and nloc != 0 and local_in(locals, nloc, src, cs, cl) { callee_ok = true }
      if not callee_ok and na >= 1 and callee_is_fn_valued_field(decls, src, cs, cl) { callee_ok = true }
      if not callee_ok { bad = true }
      ## `size`/`align`/`typeinfo` arguments are type expressions, not runtime name uses. Generic type
      ## parameters are likewise skipped at their declared type-argument positions.
      tb := callee_is_type_builtin(src, cs, cl)
      gen := callee_is_generic(decls, upto, src, cs, cl)
      mut ai := 0
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        if not tb and not (gen and callee_param_is_type(decls, upto, src, cs, cl, ai, a)) {
          if expr_statement_has_unbound(ga.e, decls, upto, src, a, locals, nloc) { bad = true }
        }
        ai += 1
        g = ga.next
      }
      bad
    }
    Expr::StructLit(ss, sl, nf, fh) => { false }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { false }
    Expr::Field(base, fs, fl) => {
      mut bad := false
      ## A type/namespace field (`str.size()`, `Ordering.acquire`, `typeinfo(T).fields`) is not a
      ## runtime read of the base name. Known user-struct fields still go through the field-name fence.
      bv := expr_var_span(base)
      if not is_prelude_ns_var(base, src) and not (bv.n != 0 and type_name_known(decls, src, bv.s, bv.n)) {
        bad = expr_statement_has_unbound(base, decls, upto, src, a, locals, nloc)
      }
      if not bad and sema_field_name_missing(base, fs, fl, decls, upto, src, locals, nloc, a) { bad = true }
      bad
    }
    Expr::AddrOf(p) => { false }
    Expr::Deref(p) => { false }
    Expr::ArrayLit(ne, eh) => { false }
    Expr::Index(base, idx) => { false }
    Expr::Try(inner) => { false }
    Expr::Slice(base, lo, hi) => { false }
    Expr::CompField(base, idx) => { false }
    Expr::Unchecked(inner) => { expr_statement_has_unbound(inner, decls, upto, src, a, locals, nloc) }
    Expr::FnRef(fnpos, fms, fml) => { false }
    Expr::Lambda(fnpos, ph, rts, rtl, bh, val) => { false }
    Expr::Loop(b) => { false }
  }
}

expr_has_unbound := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> bool {
  ## `bitcast(ptr(<sub-word>), v)` PRESERVED node — transparent: its bound-ness is the inner's.
  ## Handled pre-match (this match has NO wildcard, so an unmatched Bitcast would fall through and
  ## MISREAD its payload as a `Var` span → a SPURIOUS unbound). `bitcast_inner` dispatches reliably.
  ubci := bitcast_inner(e)
  if unchecked bitcast(usize, ubci) != 0 { return expr_has_unbound(ubci, decls, upto, src, a, locals, nloc) }
  match deref(e) {
    Expr::Num(v, s, n) => { false }
    Expr::BoolLit(v) => { false }
    Expr::FloatLit(s, n) => { false }
    Expr::StrLit(s, n, lbl, _ps, _pn) => { false }
    Expr::Var(s, n) => {
      mut found := false
      if nloc != 0 { found = local_in(locals, nloc, src, s, n) }
      ## a top-level name resolves WHOLE-PROGRAM, not prefix-only: a module-level binding (esp. a `mut`
      ## GLOBAL like `A64_CHK`, `A64_SUB_ITS`, `hardreject`) is used FREELY before its textual decl
      ## (`aarch64.al`'s `ov := A64_CHK`, decl ~1327), exactly as the lower resolves globals — so a
      ## use-before-decl reference must not read as unbound. A truly undefined name is declared NOWHERE →
      ## still `not found` → still rejected (`reject_unbound`/`reject_undefined_callee` unaffected).
      if not found { found = declared(decls, rt::vec_len(deref(decls)), src, s, n) }
      ## a raw-asm register operand (`movq(rax, 60)`; spec ch.80 §6) is an arch-data prelude identifier,
      ## not an unbound name — exempt it (like `is_prelude_ns_var` for `Ordering`/`Arch`/…).
      if not found { found = is_register_name(src, s, n) }
      ## a `:=` body binding LEAKS function-scoped (Alatyr locals are not block-scoped — `if c { x := 5 } … x`
      ## sees `x`). The threaded `nloc` window is per-block/per-arm and is TRUNCATED at match-arm / if-branch
      ## boundaries, so a leaked `:=` local referenced from a LATER sibling branch (or an else-if branch the
      ## checker walks as a sibling arm) drops out of the window and reads as a false "unbound". Consult the
      ## function-wide REMEMBERED set (every `:=` / for-var / param, never truncated) as a fallback — a name
      ## bound ANYWHERE in the fn is legitimately in scope. Monotonic: it only ADDS resolvable names (a truly
      ## undefined name is remembered NOWHERE → still unbound → `reject_unbound` unaffected).
      if not found { found = remembered(locals, src, s, n) }
      not found
    }
    Expr::Bin(op, l, r) => { expr_has_unbound(l, decls, upto, src, a, locals, nloc) or expr_has_unbound(r, decls, upto, src, a, locals, nloc) }
    Expr::If(c, t, f) => { expr_has_unbound(c, decls, upto, src, a, locals, nloc) or expr_has_unbound(t, decls, upto, src, a, locals, nloc) or expr_has_unbound(f, decls, upto, src, a, locals, nloc) }
    Expr::Match(scrut, head) => {
      mut bad := expr_has_unbound(scrut, decls, upto, src, a, locals, nloc)
      mut arm := head
      mut nl2 := nloc
      while arm != 0 {
        am := deref(arm_p(arm))
        ## a variant arm binds its payload vars (`binds_head`) VISIBLE ONLY in that arm — push them
        ## before recursing so `Some(w) => w` does not read `w` as unbound, then pop (`lvec_truncate`
        ## + `nl2` restore) so they do not leak into a sibling arm.
        base := nl2
        mut bd := am.binds_head
        while unchecked bitcast(usize, bd) != 0 {
          bnns := bnd_ns(bd)
          bnnl := bnd_nl(bd)
          if not local_in(locals, nl2, src, bnns, bnnl) {
            lvec_push(deref(locals), Local(ns = bnns, nl = bnnl, tag = 0, prov = 0, tns = 0, tnl = 0))
            nl2 += 1
          }
          bd = bnd_next(bd)
        }
        if expr_has_unbound(am.body, decls, upto, src, a, locals, nl2) { bad = true }
        lvec_truncate(deref(locals), base)
        nl2 = base
        arm = am.next
      }
      bad
    }
    Expr::Call(cs, cl, na, ah) => {
      ## Capability-query operands are checked in a private semantic attempt. A failed attempt is the
      ## compile-time bool false, not an error in the enclosing expression.
      qnm := str_at((src + cs), cl)
      if qnm == "resolves" or qnm == "compiles" { return false }
      mut bad := false
      mut g := ah
      gen := callee_is_generic(decls, upto, src, cs, cl)
      if not gen and call_arity_match(decls, upto, src, cs, cl, na, a) == 0 { bad = true }
      ## an UNDEFINED function call is a name resolving to no declared fn/type AND not
      ## a built-in (a prelude identifier the lower handles) — reject at CHECK time rather than at LINK.
      ## Accumulates into `bad` (the poison path the caller turns into a located `mark_failed`); no early
      ## return (that mis-lowers the arm under the seed). Conservative: any decl by tail-name
      ## (use-before-decl / forward refs / constructors OK) or any built-in exempts the call.
      mut callee_ok := callee_declared_anywhere(decls, src, cs, cl) or is_builtin_callee(src, cs, cl)
      ## a FUNCTION-VALUE call — the callee names a bound LOCAL/PARAM holding a fn (`f(x)` for a
      ## higher-order `f`), not a top-level fn — is legal too; exempt a callee that resolves as a local.
      if not callee_ok and nloc != 0 and local_in(locals, nloc, src, cs, cl) { callee_ok = true }
      ## FN-10 — a call THROUGH a fn-VALUE STRUCT FIELD (`o.f(41)`, desugared by the parser to the UFCS
      ## `Call(f, [o, 41])`): the callee names a FIELD, not a fn or a local. The lower lowers it to an
      ## indirect call through the field word (`fn_field_call_slot`); exempt it here so the front end
      ## stops reporting a spurious "unbound name". Needs at least the receiver argument.
      if not callee_ok and na >= 1 and callee_is_fn_valued_field(decls, src, cs, cl) { callee_ok = true }
      if not callee_ok { bad = true }
      ## atomic/fence ordering-legality (spec ch.110 §2/§3): reject a load/store/fence/CAS whose
      ## ordering is illegal for that operation. Neutral — `src/` makes no `atomic`/`fence` calls.
      if atomic_ordering_bad(cs, cl, ah, src, a) { bad = true }
      ## An OVERLOAD SET (>1 same-name fn) is NOT resolved by sema (sema.al ~631), so the per-arg
      ## conformance check below cannot know WHICH overload's parameter type to compare against —
      ## `callee_param_ty` returns just one of them, and comparing a scalar arg against a sibling
      ## overload's AGGREGATE parameter falsely fails (`g(u64)`+`g(A)` called `g(10)` rejected the
      ## scalar call as a spurious "unbound name"). Stay tolerant for an overload set — exactly the
      ## intent that lets `overload_three` build; real resolution + rejection happen later (lower/link).
      ## The genuine unbound-Var walk of each argument (below) is kept regardless.
      ovset := callee_fn_name_count(decls, upto, src, cs, cl) > 1
      ## a comptime TYPE-BUILTIN (`size`/`align`/`typeinfo`) takes TYPE names as arguments, not values:
      ## a type-shaped arg (a bare known-type-name Var, or an array-TYPE literal `[T; N]` whose inner
      ## names ARE the type) is NOT an unbound VALUE — without this `size([u64; 3])` read `u64` as an
      ## unbound Var (next-up #2; Types §6.4).
      tb := callee_is_type_builtin(src, cs, cl)
      mut ai := 0
      while g != 0 {
        ga := deref(arg_p(g))
        if not (gen and callee_param_is_type(decls, upto, src, cs, cl, ai, a)) {
          if tb and sema_type_arg_ok(ga.e, decls, src) { }
          else if expr_has_unbound(ga.e, decls, upto, src, a, locals, nloc) { bad = true }
          if not gen and not ovset {
            at := check_expr(ga.e, decls, upto, src, a, locals, nloc)
            match at {
              Result::Ok(av) => {
                pt := callee_param_ty(decls, upto, src, cs, cl, ai, a)
                if not tag_compat(av.tag, pt.tag) { bad = true }
              }
              Result::Err(e0) => { bad = true }
            }
          }
        }
        ai += 1
        g = ga.next
      }
      bad
    }
    Expr::StructLit(ss, sl, nf, fh) => {
      mut bad := false
      mut g := fh
      while g != 0 { ga := deref(arg_p(g)); if expr_has_unbound(ga.e, decls, upto, src, a, locals, nloc) { bad = true }; g = ga.next }
      bad
    }
    Expr::EnumLit(es, el, vs, vl, np, ph) => {
      mut bad := false
      mut g := ph
      while g != 0 { ga := deref(arg_p(g)); if expr_has_unbound(ga.e, decls, upto, src, a, locals, nloc) { bad = true }; g = ga.next }
      bad
    }
    Expr::Field(base, fs, fl) => {
      mut bad := false
      if not is_prelude_ns_var(base, src) { bad = expr_has_unbound(base, decls, upto, src, a, locals, nloc) }
      if not bad and sema_field_name_missing(base, fs, fl, decls, upto, src, locals, nloc, a) { bad = true }
      bad
    }
    Expr::AddrOf(p) => { expr_has_unbound(p, decls, upto, src, a, locals, nloc) }
    Expr::Deref(p) => { expr_has_unbound(p, decls, upto, src, a, locals, nloc) }
    Expr::ArrayLit(nel, eh) => {
      mut bad := false
      mut g := eh
      while g != 0 { ga := deref(arg_p(g)); if expr_has_unbound(ga.e, decls, upto, src, a, locals, nloc) { bad = true }; g = ga.next }
      bad
    }
    Expr::Index(base, idx) => { expr_has_unbound(base, decls, upto, src, a, locals, nloc) or expr_has_unbound(idx, decls, upto, src, a, locals, nloc) }
    Expr::Try(inner) => { expr_has_unbound(inner, decls, upto, src, a, locals, nloc) }
    Expr::Unchecked(inner) => { expr_has_unbound(inner, decls, upto, src, a, locals, nloc) }
    Expr::Slice(base, lo, hi) => { expr_has_unbound(base, decls, upto, src, a, locals, nloc) or expr_has_unbound(lo, decls, upto, src, a, locals, nloc) or expr_has_unbound(hi, decls, upto, src, a, locals, nloc) }
    Expr::CompField(base, idx) => { expr_has_unbound(base, decls, upto, src, a, locals, nloc) or expr_has_unbound(idx, decls, upto, src, a, locals, nloc) }
    ## FN-6 — a lifted-lambda code pointer (`FnRef`) binds no names; a `Lambda` is lifted before check.
    Expr::FnRef(fnpos, fms, fml) => { false }
    Expr::Lambda(fnpos, ph, rts, rtl, bh, val) => { false }
    ## loop-as-expression (§7.2): the body's leaf uses are resolved by lower's frame map (function-scoped
    ## locals); the loop introduces no unbound names of its own (poison-tolerant, never false-rejects).
    Expr::Loop(b) => { false }
  }
}

## Synthesize the `Ty` of one expression AND type-check it. Every `Var` must be bound among
## `decls[0..upto]` (the earlier top-level bindings) OR among `locals[0..nloc]` (the fn's
## params + prior body bindings; `nloc = 0` for a top-level value binding) — else `Unbound`.
## Type rules (a `Mismatch` rejects): arithmetic `+ - * /` needs two ints → int; a comparison
## `== < > <= >= !=` needs matching operands → bool; an `if`/`match` needs agreeing branches →
## their type; a `Call` argument must match the callee's parameter type → the callee's return
## type; a `StructLit` field value must match the field's declared type → the struct type; a
## `Field` access needs a struct base → the field's type; an `EnumLit` → the enum type. The
## span carried in a `Mismatch` is the offending sub-expression's. Fallible (`?`); recurses.
pub check_expr := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> Result(Ty, CheckErr) {
  ## `bitcast(ptr(<sub-word>), v)` PRESERVED node — bit-identity, so its type IS the inner value's.
  ## Handled HERE (pre-match) because the big `match deref(e)` below mis-dispatches payload-heavy arms
  ## under the bootstrap seed (scar #2); recursing on the inner reliably yields the inner's type.
  bci := bitcast_inner(e)
  if unchecked bitcast(usize, bci) != 0 { return check_expr(bci, decls, upto, src, a, locals, nloc) }
  mvc0 := sema_manifest_value_ctor_span(e, src)
  if mvc0.n != 0 { return Result(Ty, CheckErr).Err(manifest_value_err(mvc0.s)) }
  uct0 := sema_unknown_type_ctor_span(e, decls, upto, src)
  if uct0.n != 0 { return Result(Ty, CheckErr).Err(unknown_type_ctor_err(uct0.s)) }
  ## Value-loop type inference belongs on the pre-match path for the same bootstrap-dispatch reason as
  ## the other payload-heavy expression helpers. The loop body itself is classified by the established
  ## break walker; no runtime evaluation occurs here.
  leb0 := expr_loop_body(e)
  if unchecked bitcast(usize, leb0) != 0 {
    lcode0 := lbv_stmts(leb0, 0, decls, upto, src, a, locals, nloc)
    ltag0 := lbv_code_tag(lcode0)
    if ltag0 == 250 { return Result(Ty, CheckErr).Err(mismatch_err(lbv_code_span(lcode0), 0)) }
    return Result(Ty, CheckErr).Ok(Ty(tag = ltag0, ns = 0, nl = 0))
  }
  ## Capability queries are call-shaped builtins whose operand is inspected without runtime evaluation and
  ## rewritten to a comptime bool. This first layer answers name resolution; type validation is added only
  ## through the same scoped check path after this bootstrap-safe shape is established.
  qcs0 := expr_call_callee_span(e)
  qnm0 := str_at((src + qcs0.s), qcs0.n)
  if qnm0 == "resolves" or qnm0 == "compiles" {
    qn0 := expr_call_arity(e)
    if qn0 != 1 {
      mark_failed(locals, mismatch_err(qcs0.s, 0))
      return Result(Ty, CheckErr).Err(mismatch_err(qcs0.s, 0))
    }
    qah0 := expr_call_args_head(e)
    qarg0 := deref(arg_p(qah0))
    ## A query attempt is a semantic transaction: NONE of the operand walk's temporary locals,
    ## remembered bindings, or sticky diagnostics may escape into the enclosing check. Snapshot BEFORE
    ## `expr_has_unbound`, not only around the later `compiles` type synthesis: that resolver recursively
    ## calls `check_expr` for ordinary call arguments, and those nested checks can `mark_failed` (for
    ## example an aggregate passed to a scalar parameter). Without this outer snapshot a false query
    ## poisoned the containing function instead of yielding `false`. `resolves` needs the same boundary.
    mut qstate0 := false
    mut old_len0 := 0
    mut old_pcnt0 := 0
    mut old_failed0 := 0
    mut old_fspan0 := 0
    if unchecked bitcast(usize, locals) != 0 {
      qstate0 = true
      old_len0 = deref(locals).len
      old_pcnt0 = deref(locals).pcnt
      old_failed0 = deref(deref(locals).failed)
      old_fspan0 = deref(deref(locals).fspan)
    }
    mut qok0 := true
    if expr_has_unbound(qarg0.e, decls, upto, src, a, locals, nloc) { qok0 = false }
    if qok0 and qnm0 == "compiles" {
      if unchecked bitcast(usize, locals) != 0 {
        qr1 := check_expr(qarg0.e, decls, upto, src, a, locals, nloc)
        match qr1 {
          Result::Ok(_t) => { qok0 = true }
          Result::Err(_x) => { qok0 = false }
        }
      }
    }
    if qstate0 {
      ## A sticky diagnostic produced inside the attempt is the query result `false`, even when the
      ## bootstrap-safe `Result(Ty, CheckErr)` carrier returned `Ok` and reported the failure only through
      ## `mark_failed`. Observe it before restoring the enclosing state.
      if deref(deref(locals).failed) != old_failed0 or deref(deref(locals).fspan) != old_fspan0 { qok0 = false }
      deref(locals).len = old_len0
      deref(locals).pcnt = old_pcnt0
      deref(deref(locals).failed) = old_failed0
      deref(deref(locals).fspan) = old_fspan0
    }
    if qok0 { deref(unchecked bitcast(ptr(mut Expr), e)) = Expr.BoolLit(true) }
    else { deref(unchecked bitcast(ptr(mut Expr), e)) = Expr.BoolLit(false) }
    return Result(Ty, CheckErr).Ok(Ty(tag = 2, ns = 0, nl = 0))
  }
  ## Resolve a LOCAL `Var`'s type BEFORE the big `match deref(e)` below — that match uses the bound-deref
  ## form, which does not dispatch this payload-heavy arm under the seed (scar #2). Surface a CONCRETE
  ## tag ONLY for a USER enum/struct local (tag 3/4) — enough to reject `x : <scalar> = <enum-local>` and
  ## `return <enum-local>` against a scalar return — and keep scalars/ptr/str/bool tolerant (tag 0), so
  ## the still-incomplete positive type model does not reintroduce wrong-rejects. (A fn-body-level
  ## `return`, NOT inside a match arm — safe under the seed.)
  evs := expr_var_span(e)
  if evs.n != 0 and nloc != 0 and local_in(locals, nloc, src, evs.s, evs.n) {
    raw := local_ty(locals, nloc, src, evs.s, evs.n)
    mut ltag : u8 = raw.tag
    if ltag >= 128 and ltag != 255 { ltag = ltag - 128 }
    mut rtag : u8 = 0
    ## surface a CONCRETE tag for a struct/enum (3/4) local AND a POINTER (5) local — the latter carries
    ## its pointee name in ns/nl (when nominal), so `ty_compat` can reject a `ptr(X)` flowing into a
    ## `ptr(Y)` slot. Scalars/str/bool stay tolerant (tag 0); a ptr with an unknown pointee (nl==0) is
    ## still tolerant inside `ty_compat`, so nothing new is FALSE-rejected.
    if ltag == 3 or ltag == 4 or ltag == 5 { rtag = ltag }
    return Result(Ty, CheckErr).Ok(Ty(tag = rtag, ns = raw.ns, nl = raw.nl))
  }
  ## A direct `local[N]` over a fixed `[T; N]` is the one indexed shape whose bound is already
  ## available to the common checker. Keep this before the large payload match so the frozen seed,
  ## `check`, `-o`, and every emit-to-stdout backend observe the same located reject.
  ib0 := expr_index_base(e)
  if unchecked bitcast(usize, ib0) != 0 {
    ii0 := expr_index_index(e)
    if fixed_array_index_oob(ib0, ii0, src, locals, nloc) {
      return Result(Ty, CheckErr).Err(located_err(expr_num_lit_start(ii0)))
    }
  }
  ## PRE-MATCH ptr-target CALL-ARG check (scar #2: the big-match `Call` arm is not dispatched under the
  ## seed, so call-arg type-checking runs HERE as a side-effect + fall-through, like the exhaustiveness
  ## check below). For a DIRECT, NON-generic call, walk the args: a Var arg naming a local POINTER with a
  ## known nominal pointee, passed to a param that is a pointer with a DIFFERENT known nominal pointee, is
  ## a mismatch (`ptr(X)` flowing into a `ptr(Y)` slot — the node-handle confusion class).
  ## Conservative: only Var-local args, only when BOTH pointees resolve to a known struct/enum → never a
  ## false reject. Stepped bools (the isolated `streq` dodges the `cmp-and-fn-call` mis-lower scar).
  ecs := expr_call_callee_span(e)
  cgen := callee_is_generic(decls, upto, src, ecs.s, ecs.n)
  ## CT-12 / Comptime §2.6 — a fully comptime-known checked guard in a direct scalar call argument
  ## fails before emission, just as the existing binding/return sinks do. Keep the source-shape gates
  ## here because `Expr::Call` is also the representation for UFCS, qualified and expression-callee
  ## calls; those forms have no unambiguous direct parameter context in this bounded slice.
  if ecs.n != 0 and not cgen and sema_direct_call_name(src, ecs.s, ecs.n) and not ecallee_is(ecs.s) {
    mut ctg := expr_call_args_head(e)
    mut ctp := 0
    while ctg != 0 {
      cta := deref(arg_p(ctg))
      cte := call_arg_ct_guard_err(decls, upto, src, ecs.s, ecs.n, ctp, cta.e)
      if cte != 0 { mark_failed(locals, cte) }
      ctp += 1
      ctg = cta.next
    }
  }
  ## Types §4.6 — reject the scalar/brand constructor shape before any consumer can read arg 0.
  ## This is shared by ordinary checking and the private `compiles` transaction; the latter snapshots
  ## the sticky diagnostic and turns the same invalid expression into `false` without emitting.
  if ecs.n != 0 and sema_scalar_conversion_arity_bad(e, decls, src) {
    mark_failed(locals, scalar_conversion_err(ecs.s))
  }
  ## A builtin numeric conversion from a string is outside the conversion lattice. Keep this guard on
  ## the shared pre-match path so a direct call and the private `compiles` transaction observe the same
  ## rejection; the frozen seed may otherwise skip the payload-heavy Call arm and leave it unknown.
  if sema_builtin_str_integer_cast_bad(e, src) { mark_failed(locals, mismatch_err(s_of(e, a), 0)) }
  ## CLAYOUT S2 — the bool niche producer is deferred until S6. Reject the exact direct size fold
  ## before any backend can apply the ordinary one-word fallback; `located_err` keeps check, x86 build,
  ## and all emit-to-stdout entry points on one source-located diagnostic path.
  if ecs.n != 0 and sema_size_bool_niche_bad(e, src) {
    return Result(Ty, CheckErr).Err(located_err(ecs.s))
  }
  ## QUERY: reject a known aggregate operand in an arithmetic/bitwise binary expression before the
  ## payload-heavy `Bin` arm can be skipped by the frozen seed. This is intentionally shared by ordinary
  ## `check` and the query's private `check_expr` attempt, so neither path accepts a silent word-zero.
  if bin_aggregate_arithmetic_bad(e, decls, upto, src, locals, nloc) { mark_failed(locals, mismatch_err(s_of(e, a), 0)) }
  ## ENUM-CONSTRUCTOR variant validation (Types §6.2): the parser records `E.Zzz(…)` as an `EnumLit`
  ## when `E` is a known enum, but the lower's `variant_index` is intentionally a codegen lookup and
  ## returns -1 for a missing name. Reject the missing variant here, before that sentinel can become a
  ## runtime discriminant. Unknown/non-nominal heads remain fail-open.
  eparts0 := expr_enum_parts(e)
  if eparts0.is_enum and enum_decl_of(decls, src, eparts0.es, eparts0.el) >= 0 {
    if not sema_enum_variant_known(decls, upto, src, eparts0.es, eparts0.el, eparts0.vs, eparts0.vl) {
      mark_failed(locals, mismatch_err(eparts0.vs, eparts0.vl))
    }
  }
  ## FN-7 / P3-DIAG: the big bound-deref match below does not reliably dispatch payload-heavy Call
  ## nodes under the frozen seed, so detect the narrow, provable literal-overload ambiguity here through
  ## the bootstrap-safe call accessors. Poisoning preserves the ordinary checker walk while carrying the
  ## distinct located code to both public renderers.
  if ecs.n != 0 and not cgen {
    lvmod0 := deref(locals)
    if literal_overload_ambiguous(decls, src, ecs.s, ecs.n, expr_call_arity(e), expr_call_args_head(e), lvmod0.mod_s, lvmod0.mod_l) {
      mark_failed(locals, ambiguous_err(ecs.s))
    }
  }
  ## GENERIC when-GUARD located reject (CT-4/CT-5) — a generic call to a `when`-guarded instance the
  ## lower will NOT emit (its predicate folds FALSE for this call's concrete type-arg) is rejected HERE with
  ## a SOURCE LOCATION (was a bare undefined-symbol LINK error). `sema_when_guard_false_span` is a FAITHFUL
  ## SUBSET of `lower::guard_fold_inst` (folds `size(U) <op> N` over a concrete struct/enum type-arg; every
  ## other form → admit) → never rejects a lower-admitted instance. Neutral on the self-build (no generic
  ## `when` in `src/`+`lib/` → every `when_cond == 0` → the fold is never reached).
  if ecs.n != 0 and cgen {
    gwspan := sema_when_guard_false_span(decls, src, ecs.s, ecs.n, expr_call_args_head(e), a)
    if gwspan != 0 { mark_failed(locals, located_err(gwspan)) }
  }
  if ecs.n != 0 and nloc != 0 and (not cgen) {
    mut gg := expr_call_args_head(e)
    mut apidx := 0
    while gg != 0 {
      ga := deref(arg_p(gg))
      avs := expr_var_span(ga.e)
      argloc := avs.n != 0 and local_in(locals, nloc, src, avs.s, avs.n)
      at := local_ty(locals, nloc, src, avs.s, avs.n)
      mut atag : u8 = at.tag
      if atag >= 128 and atag != 255 { atag = atag - 128 }
      pt := callee_param_ty(decls, upto, src, ecs.s, ecs.n, apidx, a)
      known := argloc and atag == 5 and pt.tag == 5 and at.nl != 0 and pt.nl != 0
      if known { if not streq(src, at.ns, at.nl, pt.ns, pt.nl) { mark_failed(locals, mismatch_err(avs.s, 0)) } }
      apidx += 1
      gg = ga.next
    }
  }
  ## CALL-ARG aggregate↔scalar conformance (TYP-6) — the retired `check_agg_arg_scalar_param` emit
  ## net PLUS the REVERSE (a scalar literal into an aggregate param) the net could not do. Gated to an
  ## UNAMBIGUOUS callee (exactly one same-name fn among `[0..upto)`): sema does not model overload
  ## resolution, so an overloaded name is left tolerant (post-resolution — the fix that keeps
  ## `overload_three` building). Not gated on `nloc` (the reverse `f(42)` sits in a body with no locals).
  if ecs.n != 0 and (not cgen) and callee_fn_name_count(decls, upto, src, ecs.s, ecs.n) == 1 {
    mut ag := expr_call_args_head(e)
    mut apix := 0
    while ag != 0 {
      ca := deref(arg_p(ag))
      psp := callee_param_type_span(decls, upto, src, ecs.s, ecs.n, apix, a)
      if agg_scalar_bad(psp.s, psp.n, ca.e, decls, upto, src, locals, nloc) { mark_failed(locals, mismatch_err(s_of(ca.e, a), 0)) }
      ## …and the LITERAL-argument conformance mirror of the annotated-binding rule (see
      ## `call_arg_lit_incompatible`): the literal forms `check_expr`'s reordered arm list reports as
      ## UNKNOWN, judged against the parameter's declared type by the shared whitelist.
      if call_arg_lit_incompatible(decls, upto, src, ecs.s, ecs.n, apix, ca.e) { mark_failed(locals, mismatch_err(s_of(ca.e, a), 0)) }
      ## A nested direct/UFCS call has a known declared result even when the outer call's large match
      ## returns an UNKNOWN tag under the seed. Compare that result against the outer parameter here so
      ## `take(make_struct())` cannot pass a multi-word aggregate into a `str` (or scalar) slot.
      crt0 := expr_call_result_ty(ca.e, decls, upto, src)
      ## `in out` aggregate parameters use the pointer ABI: a pointer-valued helper such as
      ## `da_fvec_value(da)` is the place representation for an aggregate `FVec` parameter and is
      ## intentionally accepted by the existing checker/lower seam. The conformance gap this lane
      ## closes is a value-result mismatch (`S`/`str`/scalar), not pointer-to-aggregate ABI plumbing.
      pty0 := callee_param_ty(decls, upto, src, ecs.s, ecs.n, apix, a)
      if crt0.tag != 0 and not (crt0.tag == 5 and pty0.tag == 3) {
        if pty0.tag != 0 and not ty_compat(crt0, pty0, src) { mark_failed(locals, mismatch_err(s_of(ca.e, a), 0)) }
      }
      apix += 1
      ag = ca.next
    }
  }
  ## EXHAUSTIVENESS for a VALUE match (§60/CF-1) — the dual of the `check_stmts` statement-match check.
  ## Done here (BEFORE the big `match deref(e)`) as a side-effect + fall-through, because the big match's
  ## payload-heavy `Expr::Match` arm is not dispatched under the seed (scar #2, same as `Var`); poison
  ## via `mark_failed` (surfaces through the sticky failure word — verified). Resolve the scrutinee's
  ## enum type via `local_ty` DIRECTLY (its by-value `Ty` preserves the name span ns/nl; `check_expr`'s
  ## `Result(Ty, CheckErr)` payload truncates them). Fail-open: a local enum scrutinee, all-plain arms
  ## (no `_`/comptime/lit), decl found, a variant provably uncovered → else skip.
  emp := expr_match_parts(e)
  if emp.is_match {
    msv := expr_var_span(emp.scrut)
    if msv.n != 0 and nloc != 0 and local_in(locals, nloc, src, msv.s, msv.n) {
      msty := local_ty(locals, nloc, src, msv.s, msv.n)
      mut mstag : u8 = msty.tag
      if mstag >= 128 and mstag != 255 { mstag = mstag - 128 }
      if mstag == 4 and msty.nl != 0 {
        mut mall_plain := true
        mut ma2 := emp.head
        while ma2 != 0 {
          mam2 := deref(arm_p(ma2))
          if mam2.wild != 0 { mall_plain = false }
          ma2 = mam2.next
        }
        if mall_plain {
          mut medi : i64 = 0 - 1
          mut mdi := 0
          while mdi < upto {
            md := deref(decl_get(decls, mdi))
            if md.kind == 3 and streq(src, md.name_start, md.name_len, msty.ns, msty.nl) { medi = i64(mdi) }
            mdi += 1
          }
          if medi >= 0 {
            med := deref(decl_get(decls, usize(medi)))
            mut mfv := med.fields_head
            mut muncovered := false
            while mfv != 0 {
              mfdc := deref(fld_p(mfv))
              mut mcovered := false
              mut ma3 := emp.head
              while ma3 != 0 {
                mam3 := deref(arm_p(ma3))
                if streq(src, mam3.vs, mam3.vl, mfdc.ns, mfdc.nl) { mcovered = true }
                ma3 = mam3.next
              }
              if not mcovered { muncovered = true }
              mfv = mfdc.next
            }
            if muncovered { mark_failed(locals, mismatch_err(s_of(emp.scrut, a), 0)) }
          }
        }
      }
      ## SCALAR exhaustiveness (§5.4): a RANGE-containing `bool`/`u8` value-match must cover its finite
      ## domain (else poison the check). Fail-open for anything else (see scalar_coverage_gap).
      if (mstag == 1 or mstag == 2) and scalar_coverage_gap(emp.head, mstag, msty.ns, msty.nl, src) {
        mark_failed(locals, mismatch_err(s_of(emp.scrut, a), 0))
      }
    }
  }
  node := deref(e)
  match node {
    Expr::Num(v, s, n) => { Result(Ty, CheckErr).Ok(Ty(tag = 1, ns = 0, nl = 0)) }
    ## FN-6 — a lifted-lambda code pointer is a word-sized scalar value (tag 1). (`Lambda` is lifted to
    ## `FnRef` by the driver's pass before `check`, so only `FnRef` reaches here.)
    Expr::FnRef(fnpos, fms, fml) => { Result(Ty, CheckErr).Ok(Ty(tag = 1, ns = 0, nl = 0)) }
    ## a bool literal types `bool` (tag 2) — NOT int. This is the whole point of the distinct node:
    ## `x : bool = true` type-checks while `x : bool = 1` (a `Num`, tag 1) stays a mismatch.
    Expr::BoolLit(v) => { Result(Ty, CheckErr).Ok(Ty(tag = 2, ns = 0, nl = 0)) }
    Expr::Var(s, n) => {
      ## NOTE: this arm must NOT use an early `return` — an early return inside a `match` arm is
      ## dead under the bootstrap seed (it falls through to the arm tail), which silently discarded
      ## the resolved local type and yielded tag 0 for every local. Structure it as a single
      ## if/else-if/else whose branch values ARE the arm's result.
      mut found_local := false
      if nloc != 0 { found_local = local_in(locals, nloc, src, s, n) }
      if found_local {
        raw := local_ty(locals, nloc, src, s, n)
        mut ltag : u8 = raw.tag
        if ltag >= 128 and ltag != 255 { ltag = ltag - 128 }
        Result(Ty, CheckErr).Ok(Ty(tag = ltag, ns = raw.ns, nl = raw.nl))
      } else if upto == 0 {
        Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0))
      } else {
        found_top := declared(decls, upto, src, s, n)
        Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0))
      }
    }
    Expr::Bin(op, l, r) => {
      tl := check_expr(l, decls, upto, src, a, locals, nloc)?
      tr := check_expr(r, decls, upto, src, a, locals, nloc)?
      ## A comparison (kinds 20/24/25/26/27/28) yields bool; its operands must agree.
      if op == 20 or op == 24 or op == 25 or op == 26 or op == 27 or op == 28 {
        if ty_eq(tl, tr) { Result(Ty, CheckErr).Ok(Ty(tag = 2, ns = 0, nl = 0)) }
        else { Result(Ty, CheckErr).Err(mismatch_err(s_of(l, a), 0)) }
      } else if op == 40 or op == 41 {
        ## boolean `and`/`or`: both operands must be bool (tag 2) → bool. (`not` is op 42,
        ## a prefix unary parsed as `Bin(42, x, x)` — both slots are the SAME operand, so
        ## checking the left covers it; result bool.)
        bad_bl := tl.tag != 0 and tl.tag != 2
        bad_br := tr.tag != 0 and tr.tag != 2
        if bad_bl { Result(Ty, CheckErr).Err(mismatch_err(s_of(l, a), 0)) }
        else if bad_br { Result(Ty, CheckErr).Err(mismatch_err(s_of(r, a), 0)) }
        else { Result(Ty, CheckErr).Ok(Ty(tag = 2, ns = 0, nl = 0)) }
      } else if op == 42 {
        ## boolean `not`: the operand must be bool → bool.
        bad_n := tl.tag != 0 and tl.tag != 2
        if bad_n { Result(Ty, CheckErr).Err(mismatch_err(s_of(l, a), 0)) }
        else { Result(Ty, CheckErr).Ok(Ty(tag = 2, ns = 0, nl = 0)) }
      } else {
        ## arithmetic: both operands must be int OR a pointer (the usize↔ptr handle seam — `base + off`,
        ## `p - q` for pointer distance; MEM-7/8, I11) → int. A ptr operand is accepted like an int; the
        ## result stays int (tag 1), which `tag_compat` treats as compatible with a ptr slot downstream.
        bad_l := tl.tag != 0 and tl.tag != 1 and tl.tag != 5
        bad_r := tr.tag != 0 and tr.tag != 1 and tr.tag != 5
        if bad_l { Result(Ty, CheckErr).Err(mismatch_err(s_of(l, a), 0)) }
        else if bad_r { Result(Ty, CheckErr).Err(mismatch_err(s_of(r, a), 0)) }
        else { Result(Ty, CheckErr).Ok(Ty(tag = 1, ns = 0, nl = 0)) }
      }
    }
    Expr::If(c, t, f) => {
      cc := check_expr(c, decls, upto, src, a, locals, nloc)?
      ## the condition must be bool (a known non-bool is a `Mismatch`; unknown is poison-tolerant).
      if cc.tag != 0 and cc.tag != 2 { er := Result(Ty, CheckErr).Err(mismatch_err(s_of(c, a), 0)); return er }
      tt := check_expr(t, decls, upto, src, a, locals, nloc)?
      tf := check_expr(f, decls, upto, src, a, locals, nloc)?
      if ty_eq(tt, tf) { Result(Ty, CheckErr).Ok(unify(tt, tf)) }
      else { Result(Ty, CheckErr).Err(mismatch_err(s_of(f, a), 0)) }
    }
    Expr::Match(scrut, head) => {
      cs := check_expr(scrut, decls, upto, src, a, locals, nloc)?
      mut arm := head
      mut acc := Ty(tag = 0, ns = 0, nl = 0)
      mut seen := false
      mut nl2 := nloc
      while arm != 0 {
        am := deref(arm_p(arm))
        ## bind the arm's PAYLOAD variables (poison-tolerant, instance-dependent types) VISIBLE ONLY
        ## while checking THIS arm's body — mirrors the statement-match binding. `nl2` restores the
        ## local count after the arm; `lvec_truncate` keeps the vec length in lockstep.
        base := nl2
        mut bd := am.binds_head
        while unchecked bitcast(usize, bd) != 0 {
          bnns := bnd_ns(bd)
          bnnl := bnd_nl(bd)
          if not local_in(locals, nl2, src, bnns, bnnl) {
            lvec_push(deref(locals), Local(ns = bnns, nl = bnnl, tag = 0, prov = 0, tns = 0, tnl = 0))
            nl2 += 1
          }
          bd = bnd_next(bd)
        }
        cb := check_expr(am.body, decls, upto, src, a, locals, nl2)?
        lvec_truncate(deref(locals), base)
        nl2 = base
        if seen {
          if not ty_eq(acc, cb) { er := Result(Ty, CheckErr).Err(mismatch_err(s_of(am.body, a), 0)); return er }
          acc = unify(acc, cb)
        } else { acc = cb; seen = true }
        arm = am.next
      }
      Result(Ty, CheckErr).Ok(acc)
    }
    ## `name(a0, …, a5)` — a call. The CALLEE may be defined later (use-before-decl), so it is
    ## NOT required to be in scope; but if it IS a known top-level fn, each argument is checked
    ## against the parameter's declared type. The call's type is the callee's declared return
    ## type (unknown if the callee is not resolvable).
    Expr::Call(qcs, qcl, qnargs, qargs_head) => {
      ## GENERICS tier: a generic callee's FIRST argument is the comptime TYPE argument (an
      ## ident naming a type, not a value) — skip it (don't resolve it as a Var, don't
      ## type-check it against a parameter). The remaining VALUE arguments have the generic's
      ## type-parameter type `T`, which is not a concrete `Ty` here, so they are recursed into
      ## (name resolution) but NOT type-checked against the parameter — monomorphization at the
      ## call binds `T`; the per-instance body is checked structurally.
      qgen := callee_is_generic(decls, upto, src, qcs, qcl)
      mut g := qargs_head
      mut pidx := 0
      mut bad := false
      mut bad_span := 0
      ## atomic/fence ordering-legality (spec ch.110 §2/§3) — covers a STATEMENT-position call
      ## (`atomic::store(…)` as a bare statement) that only reaches `check_expr`, not `expr_has_unbound`.
      if atomic_ordering_bad(qcs, qcl, qargs_head, src, a) { bad = true }
      while g != 0 {
        ga := deref(arg_p(g))
        ## a generic call's type-argument positions (params `T : type`) are type names, not values
        if not (qgen and callee_param_is_type(decls, upto, src, qcs, qcl, pidx, a)) {
          ta := check_expr(ga.e, decls, upto, src, a, locals, nloc)?
          if not qgen {
            pt := callee_param_ty(decls, upto, src, qcs, qcl, pidx, a)
            if not ty_compat(ta, pt, src) {
              if not bad { bad = true; bad_span = s_of(ga.e, a) }
            }
          }
        }
        pidx += 1
        g = ga.next
      }
      if bad { er := Result(Ty, CheckErr).Err(mismatch_err(bad_span, 0)); return er }
      Result(Ty, CheckErr).Ok(callee_ret_ty(decls, upto, src, qcs, qcl))
    }
    ## `S(f0 = e0, …, fN = eN)` — a struct construction. Each field value (in declaration order)
    ## is checked against the struct field's declared type; the literal's type is the struct.
    Expr::StructLit(scs, scl, snf, sfhead) => {
      di := type_decl_index(decls, upto, src, scs, scl)
      mut sg := sfhead
      mut fld := 0
      if di != 0 { fld = (deref(decl_at(Decl, rt::vec_get(deref(decls), di - 1)))).fields_head }
      while sg != 0 {
        sa := deref(arg_p(sg))
        tv := check_expr(sa.e, decls, upto, src, a, locals, nloc)?
        if fld != 0 {
          fd := deref(fld_p(fld))
          ft := resolve_ty(src, fd.ts, fd.tl, decls, upto)
          if not ty_compat(tv, ft, src) { er := Result(Ty, CheckErr).Err(mismatch_err(s_of(sa.e, a), 0)); return er }
          fld = fd.next
        }
        sg = sa.next
      }
      st := resolve_ty(src, scs, scl, decls, upto)
      if st.tag == 3 { return Result(Ty, CheckErr).Ok(st) }
      Result(Ty, CheckErr).Ok(Ty(tag = 3, ns = scs, nl = scl))
    }
    ## `base.f` — a field read: the base must be a struct; the result is `f`'s declared type.
    Expr::Field(base, fs, fl) => {
      ## a PRELUDE namespace/enum-type base (`Ordering.acquire`, `Arch.x86_64`, …) is a type/associated
      ## access, not a value — its type is opaque (tag 0, accepted). Without this `check` rejects every
      ## valid `atomic`/`comptime`-arch program while `build` accepts it (check/build parity, §1 item 5).
      if is_prelude_ns_var(base, src) { pu := Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0)); return pu }
      tb := check_expr(base, decls, upto, src, a, locals, nloc)?
      if tb.tag == 0 { unk := Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0)); return unk }
      ## Only a clear NON-aggregate scalar (int/bool) genuinely has no fields → mismatch. A `str` carries
      ## the `.ptr`/`.len` pseudo-fields, an array/slice `.len`, and a `ptr(T)` AUTO-DEREFS to the pointee
      ## struct's fields (the self-host reads `node.next` directly on a `ptr(mut Stmt)`) — accept those:
      ## str/slice yield a tolerant unknown (tag 0), a ptr resolves against its known pointee struct.
      if tb.tag == 1 or tb.tag == 2 { er := Result(Ty, CheckErr).Err(mismatch_err(fs, fl)); return er }
      if tb.tag != 3 and tb.tag != 5 { unk := Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0)); return unk }
      di := type_decl_index(decls, upto, src, tb.ns, tb.nl)
      if di == 0 { unk := Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0)); return unk }
      sd := deref(decl_at(Decl, rt::vec_get(deref(decls), di - 1)))
      ftt := field_ty(sd, src, fs, fl, decls, upto, a)
      Result(Ty, CheckErr).Ok(ftt)
    }
    ## `E.V(p0, …, pN)` — an enum-variant construction: the payload-arg expressions are checked
    ## (their type against the variant's payload type is DEFERRED — only the first payload type
    ## span is captured); the value's type is the enum.
    Expr::EnumLit(es, el, vs, vl, np, phead) => {
      mut eg := phead
      while eg != 0 {
        ea := deref(arg_p(eg))
        ce0 := check_expr(ea.e, decls, upto, src, a, locals, nloc)?
        eg = ea.next
      }
      et := resolve_ty(src, es, el, decls, upto)
      if et.tag == 4 { return Result(Ty, CheckErr).Ok(et) }
      Result(Ty, CheckErr).Ok(Ty(tag = 4, ns = es, nl = el))
    }
    ## `ptr(<place>)` — take the address of a place. The inner place is checked (its name
    ## must be bound); the result is a POINTER type (tag 5). Pointee-type tracking is deferred
    ## (the toy grammar's pointers point to ints), so the pointer carries no pointee span.
    Expr::AddrOf(p) => {
      tp := check_expr(p, decls, upto, src, a, locals, nloc)?
      Result(Ty, CheckErr).Ok(Ty(tag = 5, ns = 0, nl = 0))
    }
    ## `deref(<ptr>)` — a load through a pointer. The inner pointer is checked; the result
    ## type is the pointee, which is unknown (tag 0) under the deferred pointee-type tracking
    ## (poison-tolerant, so a `deref(p)` used as a u64 result never spuriously mismatches).
    Expr::Deref(p) => {
      td := check_expr(p, decls, upto, src, a, locals, nloc)?
      Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0))
    }
    ## A string literal `"…"` has the `str` type (tag 6). No sub-expression to check.
    Expr::StrLit(s, n, lbl, _ps, _pn) => { Result(Ty, CheckErr).Ok(Ty(tag = 6, ns = 0, nl = 0)) }
    ## `[e0, …, eN]` — an array literal: each element expression is checked; the value's type
    ## is array (tag 7). Per-element type agreement is DEFERRED (the toy arrays hold word-sized
    ## ints; element-type tracking is not load-bearing for the supported grammar).
    Expr::ArrayLit(anel, aehead) => {
      mut ag := aehead
      while ag != 0 {
        aa := deref(arg_p(ag))
        te := check_expr(aa.e, decls, upto, src, a, locals, nloc)?
        ag = aa.next
      }
      Result(Ty, CheckErr).Ok(Ty(tag = 7, ns = 0, nl = 0))
    }
    ## `a[i]` — an element read: the index must be int (a known non-int is a `Mismatch`); the
    ## base is checked (any `Var` inside must be bound). The element type is unknown (tag 0,
    ## poison-tolerant) since element-type tracking is deferred — so `a[i]` used as a u64 never
    ## spuriously mismatches.
    Expr::Index(ibase, iidx) => {
      tb := check_expr(ibase, decls, upto, src, a, locals, nloc)?
      ti := check_expr(iidx, decls, upto, src, a, locals, nloc)?
      if ti.tag != 0 and ti.tag != 1 { er := Result(Ty, CheckErr).Err(mismatch_err(s_of(iidx, a), 0)); return er }
      Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0))
    }
    ## Remaining expression forms are deliberately conservative but must still be explicit. Keeping
    ## these arms in the reordered checker prevents a newly introduced expression from being silently
    ## interpreted as another payload shape under the frozen seed. Their nested operands are checked for
    ## name/type errors; the result stays UNKNOWN where the checker has no stable scalar type contract.
    Expr::FloatLit(fs, fl) => { Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0)) }
    Expr::Slice(sbase, slo, shi) => {
      bs := check_expr(sbase, decls, upto, src, a, locals, nloc)?
      lo := check_expr(slo, decls, upto, src, a, locals, nloc)?
      hi := check_expr(shi, decls, upto, src, a, locals, nloc)?
      if lo.tag != 0 and lo.tag != 1 { er := Result(Ty, CheckErr).Err(mismatch_err(s_of(slo, a), 0)); return er }
      if hi.tag != 0 and hi.tag != 1 { er := Result(Ty, CheckErr).Err(mismatch_err(s_of(shi, a), 0)); return er }
      Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0))
    }
    Expr::CompField(cfbase, cfidx) => {
      cb := check_expr(cfbase, decls, upto, src, a, locals, nloc)?
      ci := check_expr(cfidx, decls, upto, src, a, locals, nloc)?
      Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0))
    }
    Expr::Lambda(fnpos, lph, lrts, lrtl, lbh, lval) => {
      Result(Ty, CheckErr).Ok(Ty(tag = 1, ns = 0, nl = 0))
    }
    Expr::Bitcast(binner, bps, bpl) => { check_expr(binner, decls, upto, src, a, locals, nloc) }
    ## `inner?` — the tryable `?` operator. The inner expression is checked; it must be a
    ## tryable ENUM value (tag 4) — a known non-enum inner is a `Mismatch` (an unknown inner,
    ## e.g. a call whose return type isn't a captured enum, is poison-tolerant). The `?`
    ## expression's value type is the success variant's payload, which under the deferred
    ## enum-payload-type tracking is unknown (tag 0, poison-tolerant) — so `f()?` used as a
    ## u64 never spuriously mismatches. SIMPLIFICATION: the convention "success = variant 0"
    ## and "the enclosing fn returns the same enum type" is enforced structurally by lower (it
    ## delivers the failure enum through the fn's enum-return convention), not re-checked here.
    Expr::Try(inner) => {
      ttr := check_expr(inner, decls, upto, src, a, locals, nloc)?
      if ttr.tag != 0 and ttr.tag != 4 { er := Result(Ty, CheckErr).Err(mismatch_err(s_of(inner, a), 0)); return er }
      Result(Ty, CheckErr).Ok(Ty(tag = 0, ns = 0, nl = 0))
    }
    ## `unchecked <inner>` — verification-mode scope (Types §4.2). The TYPE is the inner's type
    ## (fully transparent); the mode affects only the lower's guard emission.
    Expr::Unchecked(inner) => { check_expr(inner, decls, upto, src, a, locals, nloc) }
    ## `loop { … }` in VALUE position (loop-as-expression, §7.2). Reuse the established break-value
    ## walker so a typed sink sees the loop's common reachable-break type instead of UNKNOWN. A loop with
    ## no value break remains UNKNOWN (Never is bottom here), while a known incompatible pair returns the
    ## same located mismatch used by the standalone BREAK consistency pass.
    Expr::Loop(b) => {
      lcode := lbv_stmts(b, 0, decls, upto, src, a, locals, nloc)
      ltag := lbv_code_tag(lcode)
      if ltag == 250 { Result(Ty, CheckErr).Err(mismatch_err(lbv_code_span(lcode), 0)) }
      else { Result(Ty, CheckErr).Ok(Ty(tag = ltag, ns = 0, nl = 0)) }
    }
  }
}

## Pick the more-specific of two compatible types (a known type over unknown). The result is
## built into a `mut` local first so the sret return delivers from a place (a by-value
## aggregate param has no frame home of its own — the documented non-place-return shape).
unify := fn(a : Ty, b : Ty) -> Ty {
  mut r : Ty = a
  if a.tag == 0 { r = b }
  r
}

## ─── LOOP-AS-EXPRESSION break-value TYPE CONSISTENCY (Control Flow §7.2) ─────────────────────────────
## "break-values of incompatible type are ill-formed": the loop's type is the common type of its
## reachable `break <value>` exits. These walkers detect a KNOWN-incompatible pair at CHECK time and are
## wired into `check_fn` as a bool pass (exactly like `stmts_bad_loop_control`) — NOT into `check_expr`'s
## NON-EXHAUSTIVE, REORDERED arm list (whose later arms do not reliably dispatch under the bootstrap
## seed — a separated pre-existing diagnostic). `check_expr`'s value-loop arm therefore stays UNKNOWN
## (preserving every current accept). Literal tags are the fast path (Num→int 1, BoolLit→bool 2,
## StrLit→str 6, StructLit→3, EnumLit→4, ArrayLit→7); known locals and ordinary checker expressions
## contribute their inferred tags, while unresolved forms remain UNKNOWN (0, poison-tolerant). The rule
## therefore fires only on two KNOWN incompatible values. DORMANT for the self-build (`src/`+`lib/` never
## use a value loop) → fixpoint-neutral.
## The running common type: 0 = unknown, else the known compatible tag.
lbv_lit_tag := fn(e : ptr(Expr)) -> u8 {
  match deref(e) {
    Expr::Num(_v, _s, _n) => { 1 }
    Expr::BoolLit(_v) => { 2 }
    Expr::Var(_s, _n) => { 0 }
    Expr::Bin(_op, _l, _r) => { 0 }
    Expr::If(_cc, _t, _f) => { 0 }
    Expr::Match(_sc, _ah) => { 0 }
    Expr::Call(_cs, _cl, _na, _ah) => { 0 }
    Expr::StructLit(_ss, _sl, _nf, _fh) => { 3 }
    Expr::Field(_b, _fs, _fl) => { 0 }
    Expr::EnumLit(_es, _el, _vs, _vl, _np, _ph) => { 4 }
    Expr::AddrOf(_p) => { 0 }
    Expr::Deref(_p) => { 0 }
    Expr::StrLit(_s, _n, _lbl, _ps, _pn) => { 6 }
    Expr::ArrayLit(_anel, _aehead) => { 7 }
    Expr::Index(_ib, _ii) => { 0 }
    Expr::Try(_inner) => { 0 }
    Expr::FloatLit(_s, _n) => { 0 }
    Expr::Slice(_sb, _slo, _shi) => { 0 }
    Expr::CompField(_ca, _cb) => { 0 }
    Expr::Unchecked(_inner) => { 0 }
    Expr::Lambda(_vs, _ph, _ps, _pl, _nl, _body) => { 0 }
    Expr::FnRef(_fpos, _fms, _fml) => { 0 }
    Expr::Bitcast(_inner, _ps, _pl) => { 0 }
    Expr::Loop(_b) => { 0 }
  }
}

## ── Types §9.1 — an integer literal's PER-TYPE range is checked at compile time ──────────────────
##
## "An integer literal is a compile-time number; its type is inferred from context, and its
## representability in that type is **checked at compile time** — a literal outside the target
## type's range is a compile error (I11), never a silent wrap." Nothing checked it below 64 bits:
## `x : u8 = 300` was accepted in silence and the program then ran on a truncated value — precisely
## the silent wrap the invariant forbids.
##
## `resolve_ty` collapses every integer WIDTH onto tag 1, which is why the annotated-binding
## conformance rule below cannot make this judgement. The width therefore comes from the type NAME —
## the span `local_type_span` / `Param.ts` / `Decl.ret_ts` already carry.
##
## `v` is the `Expr::Num` payload: an `i64` holding the literal's 64-BIT PATTERN (`parser::lit_val_at`
## decodes into a `usize`; the AST node is `Num(i64)`). The grammar has NO negative literal — unary
## `-x` is `Unchecked(Bin(17, Num(0), x))`, which is not a `Num` and never reaches here — so a
## NEGATIVE payload means one thing only: the written literal was at or above 2^63. That reduces the
## 64-bit half of the judgement to a sign test and keeps every comparison here SIGNED, so none of it
## depends on how an unsigned compare lowers.
##
## A WHITELIST of proven-bad cases, exactly like `ann_lit_incompatible`: only the names below are
## judged at all. `u64`/`usize` hold every 64-bit pattern, so no literal is ever out of range for
## them; every other name (`f64`, `char`, `bits8`, a brand, a generic instance, an array/pointer
## annotation, an unresolvable name) falls through to ACCEPTED. Base is irrelevant — `0xFF`, `0b…`,
## `0o…` and `255` all reach the AST as the same decoded value (`parser::dec_val`).
num_lit_out_of_range := fn(w : str, v : i64) -> bool {
  if w == "u8" { return v < 0 or v > 255 }
  if w == "u16" { return v < 0 or v > 65535 }
  if w == "u32" { return v < 0 or v > 4294967295 }
  ## a non-negative literal can only exceed a SIGNED type's positive bound; the negative bound
  ## (`i8` -128) is unreachable without the unary-minus form, which is not a `Num`.
  if w == "i8" { return v < 0 or v > 127 }
  if w == "i16" { return v < 0 or v > 32767 }
  if w == "i32" { return v < 0 or v > 2147483647 }
  if w == "i64" or w == "isize" { return v < 0 }
  false
}

## The §9.1 judgement over a declared-type SPAN `[ts, ts+tl)` and the expression filling it. Only a
## bare `Num` LITERAL is judged — that is the "untyped literal in range" clause of Declarations
## §3.1/§3.4, and it is the one form whose value is certain with no inference, no overload
## resolution and no conversion. Every other expression form is left to the other rules.
ann_lit_range_bad := fn(src : ptr(u8), ts : usize, tl : usize, e : ptr(Expr)) -> bool {
  if tl == 0 { return false }
  if expr_is_num_lit(e) == false { return false }
  num_lit_out_of_range(str_at((src + ts), tl), expr_num_lit_val(e))
}

## TYP-13 (Types §9.1/§9.2) — float spelling is semantic.  Do not let an integral
## value such as `1.0` take an integer annotation's type merely because the value happens
## to have no fractional part.  This is deliberately a separate predicate rather than a
## new literal tag: the ordinary checker keeps float values poison-tolerant and the lower's
## aggregate/ABI paths already recognize Expr::FloatLit independently.
float_lit_into_integer_bad := fn(src : ptr(u8), ts : usize, tl : usize, e : ptr(Expr)) -> bool {
  if tl == 0 { return false }
  mut is_float := false
  match deref(e) { Expr::FloatLit(_s, _n) => { is_float = true } _ => {} }
  if not is_float { return false }
  w := str_at((src + ts), tl)
  w == "u8" or w == "u16" or w == "u32" or w == "u64" or w == "usize" or w == "u128" or w == "i8" or w == "i16" or w == "i32" or w == "i64" or w == "isize" or w == "i128"
}

## Exact integer-to-float representability for the two language float formats.  The AST
## stores a Num as an i64 bit-pattern: negative values are written unsigned literals in
## [2^63, 2^64), so an unchecked bitcast gives the intended magnitude for this test.
## An integer with highest bit e is exact iff its low e-(p-1) bits are zero, where p is
## the format's significand width (24 for f32, 53 for f64).  This avoids host floating
## arithmetic and therefore keeps check deterministic across targets.
int_lit_exact_in_float := fn(src : ptr(u8), ts : usize, tl : usize, e : ptr(Expr)) -> bool {
  if tl == 0 or not expr_is_num_lit(e) { return true }
  w := str_at((src + ts), tl)
  mut p : usize = 0
  if w == "f32" { p = 24 }
  else if w == "f64" { p = 53 }
  else { return true }
  u := unchecked bitcast(usize, expr_num_lit_val(e))
  mut hi := u
  mut exponent : usize = 0
  while hi > 1 { hi = hi.shr(1) ; exponent += 1 }
  if exponent < p { return true }
  drop := exponent - (p - 1)
  mut low := u
  mut i : usize = 0
  while i < drop {
    if low % 2 != 0 { return false }
    low = low / 2
    i += 1
  }
  true
}

int_lit_into_float_bad := fn(src : ptr(u8), ts : usize, tl : usize, e : ptr(Expr)) -> bool {
  if tl == 0 or (not expr_is_num_lit(e) and not ct_is_const(e)) { return false }
  w := str_at((src + ts), tl)
  if w != "f32" and w != "f64" { return false }
  if expr_is_num_lit(e) { return not int_lit_exact_in_float(src, ts, tl, e) }
  v := ct_val(e, w)
  mut p : usize = 0
  if w == "f32" { p = 24 } else { p = 53 }
  u := unchecked bitcast(usize, v)
  mut hi := u
  mut exponent : usize = 0
  while hi > 1 { hi = hi.shr(1) ; exponent += 1 }
  if exponent < p { return false }
  drop := exponent - (p - 1)
  mut low := u
  mut i : usize = 0
  while i < drop {
    if low % 2 != 0 { return true }
    low = low / 2
    i += 1
  }
  false
}

## Types §9.1 / Declarations §3.4 — with no context an integer literal takes the target's native SIGNED
## integer. All supported targets are 64-bit, so a bare `Num` whose payload is negative is a written,
## non-negative literal in [2^63, 2^64), which does not fit the default i64. A written negative literal
## is parsed as `Unchecked(Bin(17, Num(0), ...))`, not as `Num`, and is intentionally outside this helper.
default_lit_range_bad := fn(e : ptr(Expr)) -> bool {
  if expr_is_num_lit(e) == false { return false }
  expr_num_lit_val(e) < 0
}

## ── CT-12 — a failed CHECKED GUARD during COMPTIME evaluation is a LOCATED diagnostic ───────────
##
## Comptime §2.6: "The evaluator runs the same checked-guard family as run time, but it has no
## process to trap in: a guard that fails during comptime evaluation is a **located compile-time
## diagnostic** at the operation's site … never deferred into the emitted program, and no wrapped,
## saturated, or otherwise adjusted value is materialized in its place." Before this, a module
## binding `K : u64 = 18446744073709551615 + 1` built green and died with a bare SIGILL only when a
## run-time path reached it (or, on a path never taken, died never) — the implementation fork the
## decision closes.
##
## Inside an `unchecked` scope the evaluator drops the guards exactly as run time does, with ONE
## forced difference: an operation whose unchecked behaviour is HARDWARE-defined rather than
## *defined* — division by zero and an over-width shift — stays a diagnostic, because the evaluator
## has no hardware behaviour to reproduce and I11 forbids inventing one. The two's-complement wrap
## of `+`/`-`/`*`/unary `-` IS defined, so those evaluate normally under `unchecked`.
##
## SCOPE (deliberately narrow, so this can never over-reject the deliberate wrapping arithmetic in
## the compiler's own `src/`+`lib/`): only a FULLY LITERAL constant expression is judged — `Num`
## leaves combined by `+`/`-`/`*` (value-producing), plus `/`/`%` and `shl`/`shr` (judged, but NOT
## value-producing, so their result never feeds an enclosing overflow test). A `Var`, a call, a
## field/index read and every other form is NOT constant here and is left entirely alone. The
## operating type is the binding's declared type name (`u64`, `i8`, …), or `i64` — the target's
## native signed integer (Types §9.1 / Declarations §3.4) — when there is no annotation.

## A distinct diagnostic class for the CT-12 comptime guard, above the ambiguous marker so every
## existing `CheckErr` value stays byte-for-byte unchanged. Eight-byte slots: the low three bits
## carry the guard kind (1 overflow, 2 division by zero, 3 shift out of range), the rest the source
## offset. Both public renderers strip the marker before decoding.
CT_DIAG_MARKER := 6917529027641081856
comptime_err := fn(s : usize, kind : usize) -> CheckErr { CT_DIAG_MARKER + s * 8 + kind }

## The operating WIDTH / SIGNEDNESS of a declared integer type name. An unknown name (a brand, a
## float, a generic instance) reads as the native 64-bit signed word — the widest, least-rejecting
## reading, so an unrecognized annotation can only UNDER-diagnose.
ct_width := fn(w : str) -> i64 {
  if w == "u8" or w == "i8" or w == "bits8" { return 8 }
  if w == "u16" or w == "i16" or w == "bits16" { return 16 }
  if w == "u32" or w == "i32" or w == "bits32" { return 32 }
  64
}
ct_signed := fn(w : str) -> bool {
  w == "i8" or w == "i16" or w == "i32" or w == "i64" or w == "isize"
}
## Is the exact value `v` representable in `w`? Native-width names answer true (every 64-bit pattern
## is one of their values); the 64-bit overflow test above them is what judges those.
ct_fits := fn(w : str, v : i64) -> bool {
  if w == "u8" or w == "bits8" { return v >= 0 and v <= 255 }
  if w == "u16" or w == "bits16" { return v >= 0 and v <= 65535 }
  if w == "u32" or w == "bits32" { return v >= 0 and v <= 4294967295 }
  if w == "i8" { return v >= (0 - 128) and v <= 127 }
  if w == "i16" { return v >= (0 - 32768) and v <= 32767 }
  if w == "i32" { return v >= (0 - 2147483648) and v <= 2147483647 }
  true
}
## The MOST NEGATIVE value of a signed `w` (the `MIN / -1` operand of the checked-overflow set).
ct_min := fn(w : str) -> i64 {
  if w == "i8" { return 0 - 128 }
  if w == "i16" { return 0 - 32768 }
  if w == "i32" { return 0 - 2147483648 }
  nmax := unchecked (0 - 9223372036854775807)
  unchecked (nmax - 1)
}

## UNSIGNED 64-bit `<` over two raw patterns, using only SIGNED comparisons (the same discipline
## `num_lit_out_of_range` keeps: nothing here depends on how an unsigned compare lowers). Equal sign
## bits → the signed order is the unsigned order; differing → whichever has the high bit set is the
## larger unsigned.
ct_ult := fn(x : i64, y : i64) -> bool {
  if (x < 0) == (y < 0) { return x < y }
  return y < 0
}
## The unsigned high / low 32 bits of a raw 64-bit pattern. The high half comes from a LOGICAL right
## shift (`shr` on a `u64`, OP-6) — a signed `/ 2^32` would truncate toward zero and read a negative
## pattern as a small negative number rather than as its large unsigned value. The low half is then
## exact by subtraction. Both results land in [0, 2^32), so every partial product below is computed
## with non-negative arithmetic. (No `+`/`-` here takes a >32-bit literal operand: the x86 immediate
## form is 32-bit signed, and the register allocator folds such a literal straight into the
## instruction — the multiply loads it into a register instead.)
ct_hi32 := fn(x : i64) -> i64 {
  xu : u64 = unchecked bitcast(u64, x)
  hs : u64 = shr(xu, 32)
  unchecked bitcast(i64, hs)
}
ct_lo32 := fn(x : i64) -> i64 {
  hu : u64 = unchecked bitcast(u64, ct_hi32(x))
  hb : u64 = shl(hu, 32)
  unchecked (x - unchecked bitcast(i64, hb))
}
## EXACT unsigned 64-bit multiply overflow: split both operands into 32-bit halves (each in
## [0, 2^32), so every partial product is computed with non-negative arithmetic) and ask whether the
## 128-bit product's high word is nonzero. `a*b = al*bl + (ah*bl + al*bh)*2^32 + ah*bh*2^64`.
ct_umulov := fn(a : i64, b : i64) -> bool {
  ah := ct_hi32(a)
  al := ct_lo32(a)
  bh := ct_hi32(b)
  bl := ct_lo32(b)
  if ah != 0 and bh != 0 { return true }
  cross := unchecked (unchecked (ah * bl) + unchecked (al * bh))
  if ct_hi32(cross) != 0 { return true }
  lohi := ct_hi32(unchecked (al * bl))
  return ct_hi32(unchecked (cross + lohi)) != 0
}
## EXACT signed 64-bit multiply overflow: `p / a != b` recovers the discarded high half; the one
## case that division itself cannot answer (`MIN * -1`) is decided ahead of it.
ct_smulov := fn(a : i64, b : i64) -> bool {
  if a == 0 { return false }
  mn := ct_min("i64")
  if a == (0 - 1) and b == mn { return true }
  if b == (0 - 1) and a == mn { return true }
  p := unchecked (a * b)
  return unchecked (p / a) != b
}
## Does `a <op> b` fail its CHECKED guard in the operating type `w`? Two tiers, mirroring the lower's
## own emission (`jnc` unsigned / `jno` signed at native width, then the narrow-width range test):
## the native 64-bit overflow first, then — for a sub-native `w` — representability of the exact
## result in that width.
ct_arith_ovf := fn(op : u8, a : i64, b : i64, w : str) -> bool {
  sg := ct_signed(w)
  mut s := 0
  if op == 16 { s = unchecked (a + b) }
  if op == 17 { s = unchecked (a - b) }
  if op == 18 { s = unchecked (a * b) }
  mut ov := false
  if op == 16 {
    if sg { ov = ((a < 0) == (b < 0)) and ((s < 0) != (a < 0)) } else { ov = ct_ult(s, a) }
  }
  if op == 17 {
    if sg { ov = ((a < 0) != (b < 0)) and ((s < 0) != (a < 0)) } else { ov = ct_ult(a, b) }
  }
  if op == 18 {
    if sg { ov = ct_smulov(a, b) } else { ov = ct_umulov(a, b) }
  }
  if ov { return true }
  if ct_width(w) < 64 { return not ct_fits(w, s) }
  false
}

## Is `e` a literal `0`? The lower SKIPS the overflow guard on a `0 - x` left operand (the negation /
## sentinel idiom pervasive in `src/`), so this judgement must skip it too — check and build agree.
ct_is_zero_lit := fn(e : ptr(Expr)) -> bool {
  expr_is_num_lit(e) and expr_num_lit_val(e) == 0
}
## Is `e` a VALUE-producing comptime constant here? Only integer literals combined by `+`/`-`/`*`.
## Deliberately NOT constant: an `unchecked` sub-expression (its wrap is a value model this walker
## does not model), a `0 - x` negation (guard-skipped above), `/`/`%` (whose unsigned quotient this
## signed evaluator does not reproduce), a shift, and every non-literal form. Anything excluded here
## simply stops the overflow judgement from propagating outward — it never causes a rejection.
ct_named_value := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8)) -> ptr(Expr) {
  mut out := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Var(s, n) => {
      cnt := rt::vec_len(deref(decls))
      mut i := 0
      mut hits := 0
      while i < upto and i < cnt {
        d := deref(decl_get(decls, i))
        if d.kind == 0 and streq(src, d.name_start, d.name_len, s, n) { hits += 1 ; out = d.value }
        i += 1
      }
      if hits != 1 { out = unchecked bitcast(ptr(Expr), 0) }
    }
    _ => {}
  }
  out
}

ct_is_const := fn(e : ptr(Expr)) -> bool {
  mut res := false
  match deref(e) {
    Expr::Num(v, s, n) => { res = true }
    Expr::Bin(op, l, r) => {
      if op == 16 or op == 17 or op == 18 {
        if ct_is_const(l) and ct_is_const(r) { res = true }
        if op == 17 and ct_is_zero_lit(l) { res = false }
      }
    }
    _ => {}
  }
  res
}

ct_is_const_env := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8)) -> bool {
  mut res := false
  match deref(e) {
    Expr::Num(v, s, n) => { res = true }
    Expr::Var(_s, _n) => { v := ct_named_value(e, decls, upto, src); if unchecked bitcast(usize, v) != 0 { res = ct_is_const_env(v, decls, upto, src) } }
    Expr::Bin(op, l, r) => {
      if op == 16 or op == 17 or op == 18 { if ct_is_const_env(l, decls, upto, src) and ct_is_const_env(r, decls, upto, src) { res = true }; if op == 17 and ct_is_zero_lit(l) { res = false } }
    }
    _ => {}
  }
  res
}
## The value of such a constant, computed with WRAPPING arithmetic. Only reached for a subtree
## `ct_is_const` accepted, and only after every operation in it passed its guard — so the 64-bit
## pattern is the exact mathematical value.
ct_val := fn(e : ptr(Expr), w : str) -> i64 {
  mut res := 0
  match deref(e) {
    Expr::Num(v, s, n) => { res = v }
    Expr::Bin(op, l, r) => {
      lv := ct_val(l, w)
      rv := ct_val(r, w)
      if op == 16 { res = unchecked (lv + rv) }
      if op == 17 { res = unchecked (lv - rv) }
      if op == 18 { res = unchecked (lv * rv) }
    }
    _ => {}
  }
  res
}

ct_val_env := fn(e : ptr(Expr), w : str, decls : ptr(rt::Vec), upto : usize, src : ptr(u8)) -> i64 {
  mut res := 0
  match deref(e) {
    Expr::Num(v, s, n) => { res = v }
    Expr::Var(_s, _n) => { v := ct_named_value(e, decls, upto, src); if unchecked bitcast(usize, v) != 0 { res = ct_val_env(v, w, decls, upto, src) } }
    Expr::Bin(op, l, r) => { lv := ct_val_env(l, w, decls, upto, src); rv := ct_val_env(r, w, decls, upto, src); if op == 16 { res = unchecked (lv + rv) }; if op == 17 { res = unchecked (lv - rv) }; if op == 18 { res = unchecked (lv * rv) } }
    _ => {}
  }
  res
}
## The SOURCE OFFSET of the operation being judged — the first literal under it, so the diagnostic
## lands on the line the arithmetic is written on rather than on the binding's name. 0 = unknown
## (the caller then falls back to the binding's own name span).
ct_span := fn(e : ptr(Expr)) -> usize {
  mut res := 0
  match deref(e) {
    Expr::Num(v, s, n) => { res = s }
    Expr::Unchecked(inner) => { res = ct_span(inner) }
    Expr::Bin(op, l, r) => {
      res = ct_span(l)
      if res == 0 { res = ct_span(r) }
    }
    Expr::Call(cs, cl, na, ah) => { res = cs }
    _ => {}
  }
  res
}
## The `k`-th argument expression of an arena-linked call-argument list, else the null pointer.
ct_arg_at := fn(h : ptr(mut Arg), k : usize) -> ptr(Expr) {
  mut res := unchecked bitcast(ptr(Expr), 0)
  mut g := h
  mut i := 0
  while unchecked bitcast(usize, g) != 0 {
    ga := deref(arg_p(g))
    if i == k { res = ga.e }
    g = ga.next
    i += 1
  }
  res
}

## The CT-12 walk: 0 when nothing fails, else `<source offset> * 8 + <kind>` (1 overflow, 2 division
## by zero, 3 shift out of range). `chk` is the verification mode in force — an `Unchecked` node
## flips it off for its subtree, which drops the overflow judgement (kind 1) but NOT the two
## hardware-defined ones (kinds 2 and 3), exactly as §2.6 requires.
ct_check := fn(e : ptr(Expr), w : str, chk : bool, src : ptr(u8), decls : ptr(rt::Vec), upto : usize) -> usize {
  mut res := 0
  match deref(e) {
    Expr::Unchecked(inner) => { res = ct_check(inner, w, false, src, decls, upto) }
    Expr::Bin(op, l, r) => {
      res = ct_check(l, w, chk, src, decls, upto)
      if res == 0 { res = ct_check(r, w, chk, src, decls, upto) }
      ## BOTH operands must be comptime constants: CT-12 governs the COMPTIME EVALUATION of an
      ## operation, not a run-time one that happens to divide by a literal zero (that is the run-time
      ## checked-guard family, CG-8, and it traps in the emitted program as it always has).
      if res == 0 and (op == 19 or op == 29) and ct_is_const_env(l, decls, upto, src) and ct_is_const_env(r, decls, upto, src) {
        if ct_val_env(r, w, decls, upto, src) == 0 { res = ct_span(e) * 8 + 2 }
        else if chk and ct_signed(w) and ct_val_env(r, w, decls, upto, src) == (0 - 1) and ct_val_env(l, w, decls, upto, src) == ct_min(w) { res = ct_span(e) * 8 + 1 }
      }
      if res == 0 and chk and (op == 16 or op == 17 or op == 18) {
        if ct_is_const_env(l, decls, upto, src) and ct_is_const_env(r, decls, upto, src) and not (op == 17 and ct_is_zero_lit(l)) {
          if ct_arith_ovf(op, ct_val_env(l, w, decls, upto, src), ct_val_env(r, w, decls, upto, src), w) { res = ct_span(e) * 8 + 1 }
        }
      }
    }
    Expr::Call(cs, cl, na, ah) => {
      cnm := str_at((src + cs), cl)
      if (cnm == "shl" or cnm == "shr" or cnm == "rotl" or cnm == "rotr") and na == 2 {
        a0 := ct_arg_at(ah, 0)
        a1 := ct_arg_at(ah, 1)
        if unchecked bitcast(usize, a0) != 0 and unchecked bitcast(usize, a1) != 0 {
          res = ct_check(a0, w, chk, src, decls, upto)
          if res == 0 { res = ct_check(a1, w, chk, src, decls, upto) }
          ## `rotl`/`rotr` are TOTAL (count mod N, OP-6) — they carry no width guard, so only the
          ## SHIFTS are judged here.
          ## Again BOTH operands: a RUN-TIME `unchecked { shl(x, 9) }` over a runtime `x` keeps its
          ## existing hardware-mask behaviour (`test/unchecked_narrow_shift_wrap.al`) — only a shift
          ## the evaluator itself would perform is a comptime guard failure.
          if res == 0 and (cnm == "shl" or cnm == "shr") and ct_is_const_env(a0, decls, upto, src) and ct_is_const_env(a1, decls, upto, src) {
            cnt := ct_val_env(a1, w, decls, upto, src)
            if cnt < 0 or cnt >= ct_width(w) { res = ct_span(e) * 8 + 3 }
          }
        }
      }
    }
    _ => {}
  }
  res
}

## The public CT-12 judgement over one binding: its declared type span `[ts, ts+tl)` (empty = no
## annotation → the native signed default) and its initializer. Returns 0 (accepted) or a located
## `CheckErr`, falling back to the binding's own name span when the failing operation carries none.
ct_guard_err := fn(src : ptr(u8), ts : usize, tl : usize, e : ptr(Expr), name_start : usize, decls : ptr(rt::Vec), upto : usize) -> CheckErr {
  if unchecked bitcast(usize, e) == 0 { return 0 }
  mut w := "i64"
  if tl != 0 {
    bn := base_type_name(src, ts, tl)
    w = str_at((src + bn.s), bn.n)
  }
  c := ct_check(e, w, true, src, decls, upto)
  if c == 0 { return 0 }
  mut sp := c / 8
  if sp == 0 { sp = name_start }
  comptime_err(sp, c % 8)
}

## CT-12 CALL-ARG sink: recover a parameter type only for one unqualified, direct, non-generic,
## non-variadic function. An aggregate/`out`/`in out` parameter is deliberately refused because its
## parameter span is not a scalar value context; an unknown or non-integer type is refused as well.
## The declaration scan covers the whole program because use-before-declaration is legal; uniqueness
## remains the guard against consulting an unresolved overload set. The caller supplies the exact
## argument expression, so `ct_guard_err` retains the arithmetic site and its existing `unchecked` /
## runtime-dependent behavior. This is a judgement helper, never an arity or overload resolver.
call_arg_ct_param_span := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize, pidx : usize) -> VSpan {
  mut out := VSpan(s = 0, n = 0)
  mut hits : usize = 0
  mut blocked := false
  cnt := rt::vec_len(deref(decls))
  th := sema_name_hash(src, s, n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc += 1
    if SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th {
      d := deref(decl_get(decls, i))
      if d.kind == 1 and streq(src, d.name_start, d.name_len, s, n) {
        hits += 1
        if d.is_generic or decl_is_variadic(d, src) or decl_is_slice_variadic(d) { blocked = true }
        mut pp := d.params_head
        mut k : usize = 0
        while pp != 0 {
          pm := deref(param_p(pp))
          if k == pidx {
            if pm.pmode == 0 { out = VSpan(s = pm.ts, n = pm.tl) }
            else { blocked = true }
          }
          k += 1
          pp = pm.next
        }
      }
    }
  }
  if hits != 1 or blocked { return VSpan(s = 0, n = 0) }
  out
}

## Apply the CT-12 call-argument boundary after the caller has established that this is an ordinary
## direct call. `resolve_ty` is used only as an integer-sink gate; `ct_guard_err` remains the single
## checked-constant evaluator and diagnostic encoder shared by bindings and returns.
call_arg_ct_guard_err := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize, pidx : usize, e : ptr(Expr)) -> CheckErr {
  psp := call_arg_ct_param_span(decls, upto, src, s, n, pidx)
  if psp.n == 0 { return 0 }
  pt := resolve_ty(src, psp.s, psp.n, decls, upto)
  if pt.tag != 1 { return 0 }
  ct_guard_err(src, psp.s, psp.n, e, 0, decls, upto)
}

## TYP-6 / Declarations §3.1 — an ANNOTATED binding's initializer MUST be **assignable** to the
## declared type: of that type, implicitly convertible to it (only lossless **widen**, Types §4.3),
## or an untyped literal in range (§3.4). Otherwise the declaration is ill-formed.
##
## The tag `check_expr` hands back is NOT usable for that judgement. Its arm list is the
## NON-EXHAUSTIVE, REORDERED one documented above `lbv_lit_tag`, and its later arms do not reliably
## dispatch under the bootstrap seed — a `"…"` initializer comes back tag 0 (UNKNOWN, and unknown is
## compatible with everything by the poison-tolerance rule). That is the one dropped fact behind the
## silent failure: `x : u64 = "nope"` passed `alatyr check` with rc 0 and NO output, and the built
## program returned a wrong value — the annotation constrained nothing at all.
##
## Recover the initializer's type from the EXHAUSTIVE, declaration-ordered `lbv_lit_tag` instead. It
## answers only for LITERAL forms — the forms whose type is certain with no inference, no overload
## resolution and no conversion search — and 0 (unknown) for everything else.
##
## The rule below is a WHITELIST of rejects, never `not tag_compat`: it names, one pair at a time,
## the (declared tag, literal tag) combinations that NO class of the Types §4.2 conversion lattice
## connects. Everything it cannot prove non-conforming stays ACCEPTED exactly as before — an
## unknown annotation (`f64`/`char`/generic/qualified — `resolve_ty` reports 0 for those), a
## non-literal initializer, a widening pair, and a literal taking its type from context (§3.4).
ann_lit_incompatible := fn(dtag : u8, ltag : u8) -> bool {
  ## A STRING literal is the two-word `{ptr, len}` value of type `str` (Types §6). No **widen**,
  ## **narrow**, **numeric**, **brand** or **reinterpret** class connects `str` to an integer or to
  ## `bool`, and a `str` literal is NOT an untyped literal that takes its type from context (§3.4 is
  ## about integer/float literals) — so `x : u64 = "nope"` / `x : bool = "nope"` are ill-formed with
  ## no reading under which they could conform.
  if ltag == 6 and dtag == 1 { return true }
  if ltag == 6 and dtag == 2 { return true }
  ## …and into a POINTER sink (one word). **reinterpret** is the only class that could relate them and it
  ## requires EQUAL bit width, so not even an explicit `bitcast` spells this; there is nothing for an
  ## implicit conversion to be a lossless subset of.
  ##
  ## NOT the FIXED-ARRAY sink, though `str`-vs-`[T; N]` looks like the same judgement: `embed(path)`
  ## (Comptime §2.4) folds to a StrLit NODE carrying the binary-safe byte representation, and its
  ## spec-facing surface IS `[u8; N]` — so `b : [u8; 4] = embed(…)` is a CONFORMING binding that this
  ## rule would false-reject (it did: `embed_typed_bytes`). A StrLit node is therefore not proof of a
  ## `str`-typed value once the sink is an array; leave that pair accepted.
  if ltag == 6 and dtag == 5 { return true }
  ## A BOOLEAN literal is of type `bool`, a distinct kernel type — not a numeric domain (Types §4.2). Its
  ## relation to an integer is the **numeric** class (domain change), which is ALWAYS explicit (§4.3):
  ## `u64(b)`. `x : u64 = true` therefore has no conforming reading, and neither do the pointer, `str` and
  ## fixed-array sinks. (`x : bool = true` stays accepted — that is the conforming case, §3.1.)
  if ltag == 2 and dtag == 1 { return true }
  if ltag == 2 and dtag == 5 { return true }
  if ltag == 2 and dtag == 6 { return true }
  if ltag == 2 and dtag == 7 { return true }
  ## A FIXED-ARRAY literal `[e0, …, eN]` is an N-element aggregate (Types §9.4) — no lattice class
  ## relates it to a word-sized integer, to `bool`, or to `str`.
  if ltag == 7 and dtag == 1 { return true }
  if ltag == 7 and dtag == 2 { return true }
  if ltag == 7 and dtag == 6 { return true }
  ## …and the mirror: a bare integer literal is NOT an array. §3.4's "a literal takes its type from
  ## context" is about the numeric TYPE it takes (`u8` vs `u64`), never about becoming an aggregate.
  if ltag == 1 and dtag == 7 { return true }
  ## `str` against a NOMINAL struct/enum, both directions. Held back one pass because a user
  ## conversion-constructor (Types §4.6) looked like it might make such a binding conforming — §4.6
  ## settles it: "a `@convert` fires **only** through an explicit `T(v)`; it is never an implicit
  ## conversion (only **widen** is implicit, §4.3)". So no in-scope `@convert` can rescue a bare
  ## `x : S = "abc"`; the explicit `S("abc")` is the spelling that does. A `brand(U)` declaration is
  ## NOT reached by this pair — `resolve_ty` leaves a brand name unknown (tag 0) — so brand identity,
  ## which is likewise always explicit (§4.2), is not being judged here.
  if ltag == 6 and dtag == 3 { return true }
  if ltag == 6 and dtag == 4 { return true }
  if ltag == 3 and dtag == 6 { return true }
  if ltag == 4 and dtag == 6 { return true }
  false
}

## TYP-6 / Functions §2.3 — the CALL-ARGUMENT mirror of the annotated-binding rule above. An `in`
## parameter "is bound by a value argument"; that argument must be **assignable** to the parameter's
## declared type under the SAME Types §4.2/§4.3 lattice (only **widen** is implicit; a `@convert`
## fires only through an explicit `T(v)`, §4.6) — so the identical `ann_lit_incompatible` whitelist
## decides it. `f("nope")` for `f(n : u64)` returned 112 SILENTLY with `check` rc 0: `check_expr`'s
## Call arm DOES compare the arg tag against `callee_param_ty`, but its arm list is the
## NON-EXHAUSTIVE, REORDERED one documented above `lbv_lit_tag`, so a StrLit/BoolLit/ArrayLit/
## StructLit/EnumLit argument comes back tag 0 = UNKNOWN and unknown is compatible with everything.
## (An `Expr::Num` argument DOES dispatch — which is why `reject_call_arg_type`, `f(42)` into a
## `bool` param, was already caught.) The dropped fact is the argument's LITERAL form, recovered here
## from the EXHAUSTIVE `lbv_lit_tag`.
##
## Every gate below is a REFUSAL TO JUDGE, never a reject:
##  - `hits != 1` — the name must resolve to EXACTLY ONE top-level fn (`streq`, exact). sema does not
##    model overload resolution, so with `f(u64)` + `f(str)` in scope a parameter type read off "one
##    of them" would false-reject the other one's legal call. An overloaded, qualified, UFCS-through-
##    a-field, fn-VALUE or local callee finds 0 or >1 and is left alone.
##  - `is_generic` — a generic parameter's declared type is the type-PARAMETER `T`; monomorphization
##    at the call binds it, so `id(str, "ok")` is conforming for every T (§1.3).
##  - variadic (comptime `...` and §7.2 slice `...T`) — the trailing arguments do not map
##    one-to-one onto declared parameters, so a positional index is not a parameter index.
##  - `pmode != 0` — an ARRAY/SLICE/TUPLE parameter (pmode 1) records only its ELEMENT type in
##    `ts`/`tl` (ast.al `Param`), so `[u64; 2]` reads back as `u64` and `f([40, 2])` would
##    false-reject; only the one row that survives the missing element type (a ONE-word integer/bool
##    literal into an N-word aggregate) is judged there. `out`/`in out` (pmode 2) take a PLACE
##    argument (§2.3), a judgement this literal rule does not make; pmode 3 is the slice-variadic rest.
##  - a missing parameter at that index (arity error, already rejected elsewhere) — stay silent.
## Anything `resolve_ty` cannot classify (`f64`, `char`, `u16`, a brand, a generic instance
## `Option(u64)`, a not-yet-declared nominal) is tag 0 and the whitelist never rejects on it.
call_arg_lit_incompatible := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), s : usize, n : usize, pidx : usize, e : ptr(Expr)) -> bool {
  ltag := lbv_lit_tag(e)
  mut giveup := ltag == 0
  mut hits : usize = 0
  mut found := false
  mut isagg := false
  mut pts : usize = 0
  mut ptl : usize = 0
  cnt := rt::vec_len(deref(decls))
  th := sema_name_hash(src, s, n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < upto and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
      d := deref(decl_get(decls, i))
      if d.kind == 1 and streq(src, d.name_start, d.name_len, s, n) {
        hits += 1
        if d.is_generic { giveup = true }
        if decl_is_variadic(d, src) { giveup = true }
        if decl_is_slice_variadic(d) { giveup = true }
        mut pp := d.params_head
        mut k : usize = 0
        while pp != 0 {
          pm := deref(param_p(pp))
          if k == pidx and pm.pmode == 0 { found = true; pts = pm.ts; ptl = pm.tl }
          ## pmode 1 = an ARRAY `[T; N]`, SLICE `[T]` or TUPLE `(T0, …)` parameter — an N-word
          ## BY-REFERENCE aggregate whose `ts`/`tl` holds only the ELEMENT type (ast.al `Param`), so the
          ## whitelist cannot be asked about it. What IS provable without the element type is the
          ## `ltag 1 / dtag 7` row itself: a bare integer or bool literal is ONE word, and §3.4's "a
          ## literal takes its type from context" is about the numeric TYPE it takes, never about
          ## becoming an aggregate (Types §9.4). Every other literal form still gives up here — in
          ## particular a StrLit, because `embed(path)` folds to a StrLit NODE whose spec surface IS
          ## `[u8; N]` (Comptime §2.4), and because `str` is itself a `{ptr, len}` two-word value.
          if k == pidx and pm.pmode == 1 { isagg = true }
          if k == pidx and pm.pmode != 0 and pm.pmode != 1 { giveup = true }
          k += 1
          pp = pm.next
        }
      }
    }
  }
  if giveup { return false }
  if hits != 1 { return false }
  if isagg { return ltag == 1 or ltag == 2 }
  if not found { return false }
  ## Types §9.1 REPRESENTABILITY in the PARAMETER's declared type — the argument place is the
  ## "context" a literal takes its type from (Declarations §3.4), so `f(300)` for `f(v : u8)` is the
  ## same compile error as `x : u8 = 300`. Read off the parameter's type NAME, behind every gate
  ## above (unambiguous non-generic non-variadic callee, a real `in` parameter at this index).
  if ann_lit_range_bad(src, pts, ptl, e) { return true }
  dt := resolve_ty(src, pts, ptl, decls, upto)
  ann_lit_incompatible(dt.tag, ltag)
}

## The declared return `Ty` of the callee of `e`, but ONLY when the name resolves to EXACTLY ONE
## top-level fn declaration — i.e. when no overload set has to be resolved to know the answer.
## `callee_ret_ty` matches by name and lets the LAST match win, which is fine for filling in a dropped
## type NAME but is NOT sound as the basis of a REJECT: with `f(n : u64) -> u64` and `f(s : str) -> str`
## in scope it would report `str` for `f(1)` and false-reject `x : u64 = f(1)`. Counting first makes the
## answer unambiguous or nothing at all. Everything else — an overloaded name, a fn VALUE / lambda
## callee, a qualified or UFCS callee whose span does not streq a decl name, a generic `-> T`, a missing
## return type — yields tag 0 (unknown), which the whitelist never rejects.
sole_fn_ret_ty := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8)) -> Ty {
  mut r := Ty(tag = 0, ns = 0, nl = 0)
  cs := expr_call_callee_span(e)
  if cs.n == 0 { return r }
  cnt := rt::vec_len(deref(decls))
  th := sema_name_hash(src, cs.s, cs.n)
  mut jc := sni_lo(cnt, th)
  jce := sni_hi(cnt, th)
  mut hits := 0
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if i < upto and (SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == th) {
      d := deref(decl_get(decls, i))
      if d.kind == 1 and streq(src, d.name_start, d.name_len, cs.s, cs.n) {
        hits = hits + 1
        r = resolve_ty(src, d.ret_ts, d.ret_tl, decls, upto)
      }
    }
  }
  if hits != 1 { return Ty(tag = 0, ns = 0, nl = 0) }
  r
}

## Infer a break value's known type when the literal-only fast path has no answer. The ordinary
## checker is reused with the completed function locals table, so Vars, calls, arithmetic, fields,
## and branch expressions participate without inventing a second type system. A checker error or an
## unresolved expression remains unknown (poison-tolerant), preserving correct-or-reject behavior.
lbv_known_tag := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> u8 {
  lit := lbv_lit_tag(e)
  if lit != 0 { return lit }
  ## The ordinary checker deliberately exposes only a conservative subset of local types through its
  ## `Var` arm. Break-value consistency needs the complete recorded binding type, however, and this
  ## direct lookup also preserves aggregate names that the Result payload truncates. Keep the lookup
  ## poison-tolerant: an absent or unreadable local remains unknown and falls through to the ordinary
  ## expression checker for calls, arithmetic, fields, and branch expressions.
  vs := expr_var_span(e)
  if vs.n != 0 and nloc != 0 and local_in(locals, nloc, src, vs.s, vs.n) {
    raw := local_ty(locals, nloc, src, vs.s, vs.n)
    mut tag : u8 = raw.tag
    if tag >= 128 and tag != 255 { tag = tag - 128 }
    if tag == 9 { tag = 3 }
    if tag == 10 { tag = 4 }
    if tag != 255 { return tag }
  }
  rv := check_expr(e, decls, upto, src, a, locals, nloc)
  match rv {
    Result::Ok(t) => { t.tag }
    Result::Err(_e) => { 0 }
  }
}

## Walk an expression for VALUE-position loops (`x := loop { … }` nested anywhere, including inside a
## break VALUE of an enclosing loop) and validate their bodies. A Lambda body is a SEPARATE function —
## loops there cannot break to the enclosing loop, so it is not recursed (conservative).
lbv_expr := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> bool {
  match deref(e) {
    Expr::Num(_v, _s, _n) => { false }
    Expr::BoolLit(_v) => { false }
    Expr::Var(_s, _n) => { false }
    Expr::Bin(_op, l, r) => { lbv_expr(l, decls, upto, src, a, locals, nloc) or lbv_expr(r, decls, upto, src, a, locals, nloc) }
    Expr::If(cc, t, f) => { lbv_expr(cc, decls, upto, src, a, locals, nloc) or lbv_expr(t, decls, upto, src, a, locals, nloc) or lbv_expr(f, decls, upto, src, a, locals, nloc) }
    Expr::Match(sc, ah) => {
      mut bad := lbv_expr(sc, decls, upto, src, a, locals, nloc)
      mut arm := ah
      while unchecked bitcast(usize, arm) != 0 {
        am := deref(arm_p(arm))
        if lbv_expr(am.body, decls, upto, src, a, locals, nloc) { bad = true }
        arm = am.next
      }
      bad
    }
    Expr::Call(_cs, _cl, _na, ah) => {
      mut bad := false
      mut g := ah
      while unchecked bitcast(usize, g) != 0 {
        ga := deref(arg_p(g))
        if lbv_expr(ga.e, decls, upto, src, a, locals, nloc) { bad = true }
        g = ga.next
      }
      bad
    }
    Expr::StructLit(_ss, _sl, _nf, fh) => {
      mut bad := false
      mut g := fh
      while unchecked bitcast(usize, g) != 0 {
        ga := deref(arg_p(g))
        if lbv_expr(ga.e, decls, upto, src, a, locals, nloc) { bad = true }
        g = ga.next
      }
      bad
    }
    Expr::Field(base, _fs, _fl) => { lbv_expr(base, decls, upto, src, a, locals, nloc) }
    Expr::EnumLit(_es, _el, _vs, _vl, _np, ph) => {
      mut bad := false
      mut g := ph
      while unchecked bitcast(usize, g) != 0 {
        ga := deref(arg_p(g))
        if lbv_expr(ga.e, decls, upto, src, a, locals, nloc) { bad = true }
        g = ga.next
      }
      bad
    }
    Expr::AddrOf(p) => { lbv_expr(p, decls, upto, src, a, locals, nloc) }
    Expr::Deref(p) => { lbv_expr(p, decls, upto, src, a, locals, nloc) }
    Expr::StrLit(_s, _n, _lbl, _ps, _pn) => { false }
    Expr::ArrayLit(_anel, aehead) => {
      mut bad := false
      mut g := aehead
      while unchecked bitcast(usize, g) != 0 {
        ga := deref(arg_p(g))
        if lbv_expr(ga.e, decls, upto, src, a, locals, nloc) { bad = true }
        g = ga.next
      }
      bad
    }
    Expr::Index(ib, ii) => { lbv_expr(ib, decls, upto, src, a, locals, nloc) or lbv_expr(ii, decls, upto, src, a, locals, nloc) }
    Expr::Try(inner) => { lbv_expr(inner, decls, upto, src, a, locals, nloc) }
    Expr::FloatLit(_s, _n) => { false }
    Expr::Slice(sb, slo, shi) => { lbv_expr(sb, decls, upto, src, a, locals, nloc) or lbv_expr(slo, decls, upto, src, a, locals, nloc) or lbv_expr(shi, decls, upto, src, a, locals, nloc) }
    Expr::CompField(ca, cb) => { lbv_expr(ca, decls, upto, src, a, locals, nloc) or lbv_expr(cb, decls, upto, src, a, locals, nloc) }
    Expr::Unchecked(inner) => { lbv_expr(inner, decls, upto, src, a, locals, nloc) }
    Expr::Lambda(_vs, _ph, _ps, _pl, _nl, _body) => { false }
    Expr::FnRef(_fpos, _fms, _fml) => { false }
    Expr::Bitcast(inner, _ps, _pl) => { lbv_expr(inner, decls, upto, src, a, locals, nloc) }
  Expr::Loop(b) => { lbv_code_tag(lbv_stmts(b, 0, decls, upto, src, a, locals, nloc)) == 250 }
  }
}

## Merge a break-value / sub-walk type `t` into the running verdict `acc`. Verdict encoding in the
## low byte: 0 = unknown (no known break type yet), 1..7 = the common literal tag, 250 = a
## KNOWN-incompatible pair (spec §7.2 "ill-formed"). For 250, the high bytes carry the offending
## break value's source span when one is available, moving the public diagnostic from function name to
## break site without changing unknown/poison behavior. `tag_compat` is the sema compatibility relation.
lbv_code := fn(tag : u8, span : usize) -> usize { return usize(tag) + span * 256 }
lbv_code_tag := fn(code : usize) -> u8 { return u8(code % 256) }
lbv_code_span := fn(code : usize) -> usize { return code / 256 }
lbv_merge := fn(acc : usize, t : u8, span : usize) -> usize {
  at := lbv_code_tag(acc)
  if at == 250 { return acc }
  if t == 0 { return acc }
  if at == 0 { return lbv_code(t, span) }
  if tag_compat(at, t) { return acc }
  lbv_code(250, span)
}
lbv_merge_code := fn(acc : usize, code : usize) -> usize { return lbv_merge(acc, lbv_code_tag(code), lbv_code_span(code)) }


lbv_expr_code := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> usize {
  match deref(e) {
    Expr::Num(_v, _s, _n) => { 0 }
    Expr::BoolLit(_v) => { 0 }
    Expr::Var(_s, _n) => { 0 }
    Expr::Bin(_op, l, r) => { lbv_merge_code(lbv_expr_code(l, decls, upto, src, a, locals, nloc), lbv_expr_code(r, decls, upto, src, a, locals, nloc)) }
    Expr::If(cc, t, f) => { a0 := lbv_expr_code(cc, decls, upto, src, a, locals, nloc) ; a1 := lbv_merge_code(a0, lbv_expr_code(t, decls, upto, src, a, locals, nloc)) ; lbv_merge_code(a1, lbv_expr_code(f, decls, upto, src, a, locals, nloc)) }
    Expr::Match(sc, ah) => {
      mut bad := lbv_expr_code(sc, decls, upto, src, a, locals, nloc)
      mut arm := ah
      while unchecked bitcast(usize, arm) != 0 {
        am := deref(arm_p(arm))
        bad = lbv_merge_code(bad, lbv_expr_code(am.body, decls, upto, src, a, locals, nloc))
        arm = am.next
      }
      bad
    }
    Expr::Call(_cs, _cl, _na, ah) => {
      mut bad : usize = 0
      mut g := ah
      while unchecked bitcast(usize, g) != 0 {
        ga := deref(arg_p(g))
        bad = lbv_merge_code(bad, lbv_expr_code(ga.e, decls, upto, src, a, locals, nloc))
        g = ga.next
      }
      bad
    }
    Expr::StructLit(_ss, _sl, _nf, fh) => {
      mut bad : usize = 0
      mut g := fh
      while unchecked bitcast(usize, g) != 0 {
        ga := deref(arg_p(g))
        bad = lbv_merge_code(bad, lbv_expr_code(ga.e, decls, upto, src, a, locals, nloc))
        g = ga.next
      }
      bad
    }
    Expr::Field(base, _fs, _fl) => { lbv_expr_code(base, decls, upto, src, a, locals, nloc) }
    Expr::EnumLit(_es, _el, _vs, _vl, _np, ph) => {
      mut bad : usize = 0
      mut g := ph
      while unchecked bitcast(usize, g) != 0 {
        ga := deref(arg_p(g))
        bad = lbv_merge_code(bad, lbv_expr_code(ga.e, decls, upto, src, a, locals, nloc))
        g = ga.next
      }
      bad
    }
    Expr::AddrOf(p) => { lbv_expr_code(p, decls, upto, src, a, locals, nloc) }
    Expr::Deref(p) => { lbv_expr_code(p, decls, upto, src, a, locals, nloc) }
    Expr::StrLit(_s, _n, _lbl, _ps, _pn) => { 0 }
    Expr::ArrayLit(_anel, aehead) => {
      mut bad : usize = 0
      mut g := aehead
      while unchecked bitcast(usize, g) != 0 {
        ga := deref(arg_p(g))
        bad = lbv_merge_code(bad, lbv_expr_code(ga.e, decls, upto, src, a, locals, nloc))
        g = ga.next
      }
      bad
    }
    Expr::Index(ib, ii) => { lbv_merge_code(lbv_expr_code(ib, decls, upto, src, a, locals, nloc), lbv_expr_code(ii, decls, upto, src, a, locals, nloc)) }
    Expr::Try(inner) => { lbv_expr_code(inner, decls, upto, src, a, locals, nloc) }
    Expr::FloatLit(_s, _n) => { 0 }
    Expr::Slice(sb, slo, shi) => { a0 := lbv_expr_code(sb, decls, upto, src, a, locals, nloc) ; a1 := lbv_merge_code(a0, lbv_expr_code(slo, decls, upto, src, a, locals, nloc)) ; lbv_merge_code(a1, lbv_expr_code(shi, decls, upto, src, a, locals, nloc)) }
    Expr::CompField(ca, cb) => { lbv_merge_code(lbv_expr_code(ca, decls, upto, src, a, locals, nloc), lbv_expr_code(cb, decls, upto, src, a, locals, nloc)) }
    Expr::Unchecked(inner) => { lbv_expr_code(inner, decls, upto, src, a, locals, nloc) }
    Expr::Lambda(_vs, _ph, _ps, _pl, _nl, _body) => { 0 }
    Expr::FnRef(_fpos, _fms, _fml) => { 0 }
    Expr::Bitcast(inner, _ps, _pl) => { lbv_expr_code(inner, decls, upto, src, a, locals, nloc) }
    Expr::Loop(b) => { lbv_stmts(b, 0, decls, upto, src, a, locals, nloc) }
  }
}

lbv_expr_conflict := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> usize {
  code := lbv_expr_code(e, decls, upto, src, a, locals, nloc)
  if lbv_code_tag(code) == 250 { return code }
  return 0
}

## Walk a statement list at loop-containment `c` (the count of enclosing loops between a break site and
## the value-loop being validated); a `break <value>` whose depth `d` equals `c` exits THAT loop. A
## value-loop's own body is entered at containment 0 (from `lbv_expr`'s `Expr::Loop` arm), nested
## statement loops add 1 (their bare breaks keep depth 0 and belong to them, not us). Returns the
## VERDICT (0 / 1..7 / 250): because breaks may sit in nested if/match/loop bodies, the sub-walk's
## accumulated common type is merged into the running verdict — a conflict is reported by the single
## `250` result, so the caller (and the enclosing loop's own accumulation) sees the ill-formed pair.
lbv_stmts := fn(head : ptr(mut Stmt), c : usize, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> usize {
  mut acc : usize = 0                         ## low byte: 0 = unknown; 1..7 = known tag; 250 = conflict
  mut ec : usize = 0
  mut st := head
  while unchecked bitcast(usize, st) != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Break(v, d, nx) => {
        if d == c and unchecked bitcast(usize, v) != 0 {
          ## Variables are now resolved from the completed locals table, while unknown expressions remain
          ## poison-tolerant through `lbv_known_tag`. Do not skip bare Vars: that was the old literal-only
          ## policy and made `break x` invisible to the consistency check.
          t := lbv_known_tag(v, decls, upto, src, a, locals, nloc)
            if t != 0 { acc = lbv_merge(acc, t, s_of(v, a)) }
        }
        st = nx
      }
      Stmt::Assign(_ns, _nl, v, nx) => {
        ec = lbv_expr_conflict(v, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        st = nx
      }
      Stmt::While(cx, b, nx) => {
        ec = lbv_expr_conflict(cx, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
          acc = lbv_merge_code(acc, lbv_stmts(b, c + 1, decls, upto, src, a, locals, nloc))
        st = nx
      }
      Stmt::FieldAssign(_bns, _bnl, _fns, _fnl, fv, nx) => {
        ec = lbv_expr_conflict(fv, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        st = nx
      }
      Stmt::Return(rv, nx) => {
        ec = lbv_expr_conflict(rv, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        st = nx
      }
      Stmt::If(cx, th, el, nx) => {
        ec = lbv_expr_conflict(cx, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
          acc = lbv_merge_code(acc, lbv_stmts(th, c, decls, upto, src, a, locals, nloc))
          acc = lbv_merge_code(acc, lbv_stmts(el, c, decls, upto, src, a, locals, nloc))
        st = nx
      }
      Stmt::Match(sc, ah, nx) => {
        ec = lbv_expr_conflict(sc, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        mut arm := ah
        while unchecked bitcast(usize, arm) != 0 {
          am := deref(arm_p(arm))
            acc = lbv_merge_code(acc, lbv_stmts(am.body_stmts, c, decls, upto, src, a, locals, nloc))
          arm = am.next
        }
        st = nx
      }
      Stmt::For(_fns, _fnl, lo, hi, b, nx) => {
        ec = lbv_expr_conflict(lo, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        ## a FOR-IN `for x in <iterable>` has a NULL `hi` (the very shape `check_expr` guards against) —
        ## only the range form `lo .. hi` walks the high bound.
        if unchecked bitcast(usize, hi) != 0 {
          ec = lbv_expr_conflict(hi, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        }
          acc = lbv_merge_code(acc, lbv_stmts(b, c + 1, decls, upto, src, a, locals, nloc))
        st = nx
      }
      Stmt::DerefAssign(p, v, nx) => {
        ec = lbv_expr_conflict(p, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        ec = lbv_expr_conflict(v, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        st = nx
      }
      Stmt::IndexAssign(ib, ii, iv, nx) => {
        ec = lbv_expr_conflict(ib, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        ec = lbv_expr_conflict(ii, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        ec = lbv_expr_conflict(iv, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        st = nx
      }
      Stmt::IndexFieldAssign(fia, fii, _ifs, _ifl, fiv, nx) => {
        ec = lbv_expr_conflict(fia, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        ec = lbv_expr_conflict(fii, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        ec = lbv_expr_conflict(fiv, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        st = nx
      }
      Stmt::FieldPathAssign(pl, fpv, nx) => {
        ## The left side is a write place, not a value read. DA handles unreadied-place legality;
        ## break-value consistency only needs to inspect the stored value.
        ec = lbv_expr_conflict(fpv, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        st = nx
      }
      Stmt::Loop(b, nx) => {
          acc = lbv_merge_code(acc, lbv_stmts(b, c + 1, decls, upto, src, a, locals, nloc))
        st = nx
      }
      Stmt::Continue(_cd, nx) => { st = nx }
      Stmt::ExprStmt(e, nx) => {
        ec = lbv_expr_conflict(e, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        st = nx
      }
      Stmt::CompIf(cc, cthen, celse, nx) => {
        ec = lbv_expr_conflict(cc, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
          acc = lbv_merge_code(acc, lbv_stmts(cthen, c, decls, upto, src, a, locals, nloc))
          acc = lbv_merge_code(acc, lbv_stmts(celse, c, decls, upto, src, a, locals, nloc))
        st = nx
      }
      Stmt::CompFor(_cvs, _cvl, _civ, cb, nx) => {
          acc = lbv_merge_code(acc, lbv_stmts(cb, c, decls, upto, src, a, locals, nloc))
        st = nx
      }
      Stmt::CompMatch(cmsc, cmah, nx) => {
        ec = lbv_expr_conflict(cmsc, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        mut cam := cmah
        while unchecked bitcast(usize, cam) != 0 {
          cm := deref(arm_p(cam))
            acc = lbv_merge_code(acc, lbv_stmts(cm.body_stmts, c, decls, upto, src, a, locals, nloc))
          cam = cm.next
        }
        st = nx
      }
      Stmt::CompForRange(_rvs, _rvl, rlo, rhi, rb, nx) => {
        ec = lbv_expr_conflict(rlo, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        ## a PACK-iter `comptime for a in args` (a no-`..` form) parses to a CompForRange with a NULL
        ## `rhi` — guard it exactly like the runtime for-in above.
        if unchecked bitcast(usize, rhi) != 0 {
          ec = lbv_expr_conflict(rhi, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
        }
          acc = lbv_merge_code(acc, lbv_stmts(rb, c, decls, upto, src, a, locals, nloc))
        st = nx
      }
      Stmt::Unchecked(b, nx) => {
          acc = lbv_merge_code(acc, lbv_stmts(b, c, decls, upto, src, a, locals, nloc))
        st = nx
      }
      Stmt::AllocWith(ae, b, nx) => {
        ec = lbv_expr_conflict(ae, decls, upto, src, a, locals, nloc)
        if lbv_code_tag(ec) == 250 { acc = ec }
          acc = lbv_merge_code(acc, lbv_stmts(b, c, decls, upto, src, a, locals, nloc))
        st = nx
      }
    }
  }
  acc
}

## The source-span start of an expression (for a `Mismatch`'s offending span): a `Var`'s /
## `Call`'s / `StructLit`'s / `EnumLit`'s name span start, else 0. Keep this legacy shape for
## callers whose diagnostic KIND depends on whether the original expression carried a direct span.
s_of := fn(e : ptr(Expr), a : ptr(mut rt::Arena)) -> usize {
  match deref(e) {
    Expr::Var(vs0, vn0) => { vs0 }
    Expr::Call(qs, ql, qn, qh) => { qs }
    Expr::StructLit(ss, sl, sn, sh) => { ss }
    Expr::EnumLit(es0, el0, evs, evl, enp, eph) => { es0 }
    Expr::Field(fb, ffs, ffl) => { ffs }
    _ => { 0 }
  }
}

## Find the first actually unbound variable in a compound expression without invoking `check_expr`
## again. Re-running the value checker here could mutate the sticky failure state (and a `compiles` query
## is transactional), so this walk mirrors only its name-resolution decisions. If the original boolean
## fence failed for a non-name reason, this helper returns 0 and the legacy span/kind remains in force.
expr_unbound_span := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> usize {
  ubci := bitcast_inner(e)
  if unchecked bitcast(usize, ubci) != 0 { return expr_unbound_span(ubci, decls, upto, src, a, locals, nloc) }
  match deref(e) {
    Expr::Num(v, ns0, nn0) => { 0 }
    Expr::BoolLit(b0) => { 0 }
    Expr::FloatLit(fs0, fn0) => { 0 }
    Expr::StrLit(ss0, sn0, lbl0, _ps0, _pn0) => { 0 }
    Expr::Var(vs0, vn0) => {
      mut found := false
      if nloc != 0 { found = local_in(locals, nloc, src, vs0, vn0) }
      if not found { found = declared(decls, rt::vec_len(deref(decls)), src, vs0, vn0) }
      if not found { found = is_register_name(src, vs0, vn0) }
      if not found { found = remembered(locals, src, vs0, vn0) }
      if not found { vs0 } else { 0 }
    }
    Expr::Bin(op0, left0, right0) => {
      mut r0 := expr_unbound_span(left0, decls, upto, src, a, locals, nloc)
      if r0 == 0 { r0 = expr_unbound_span(right0, decls, upto, src, a, locals, nloc) }
      r0
    }
    Expr::If(c0, t0, f0) => {
      mut r1 := expr_unbound_span(c0, decls, upto, src, a, locals, nloc)
      if r1 == 0 { r1 = expr_unbound_span(t0, decls, upto, src, a, locals, nloc) }
      if r1 == 0 { r1 = expr_unbound_span(f0, decls, upto, src, a, locals, nloc) }
      r1
    }
    ## The existing boolean fence pushes match-arm payload names into a temporary local window. Mirror
    ## that window here so an unbound name in an arm is located without treating its payload binding as
    ## an error or leaking it into the next arm.
    Expr::Match(scrut0, ah0) => {
      mut r1m := expr_unbound_span(scrut0, decls, upto, src, a, locals, nloc)
      mut arm0 := ah0
      mut nl2m := nloc
      while arm0 != 0 {
        am0 := deref(arm_p(arm0))
        base0 := nl2m
        mut bd0 := am0.binds_head
        while unchecked bitcast(usize, bd0) != 0 {
          bnns0 := bnd_ns(bd0)
          bnnl0 := bnd_nl(bd0)
          if not local_in(locals, nl2m, src, bnns0, bnnl0) {
            lvec_push(deref(locals), Local(ns = bnns0, nl = bnnl0, tag = 0, prov = 0, tns = 0, tnl = 0))
            nl2m += 1
          }
          bd0 = bnd_next(bd0)
        }
        if r1m == 0 { r1m = expr_unbound_span(am0.body, decls, upto, src, a, locals, nl2m) }
        lvec_truncate(deref(locals), base0)
        nl2m = base0
        arm0 = am0.next
      }
      r1m
    }
    Expr::Call(cs0, cl0, na0, ah1) => {
      qnm0 := str_at((src + cs0), cl0)
      if qnm0 == "resolves" or qnm0 == "compiles" { return 0 }
      mut callee_ok0 := callee_declared_anywhere(decls, src, cs0, cl0) or is_builtin_callee(src, cs0, cl0)
      if not callee_ok0 and nloc != 0 and local_in(locals, nloc, src, cs0, cl0) { callee_ok0 = true }
      if not callee_ok0 and na0 >= 1 and callee_is_fn_valued_field(decls, src, cs0, cl0) { callee_ok0 = true }
      if not callee_ok0 { return cs0 }
      gen0 := callee_is_generic(decls, upto, src, cs0, cl0)
      if not gen0 and call_arity_match(decls, upto, src, cs0, cl0, na0, a) == 0 { return cs0 }
      tb0 := callee_is_type_builtin(src, cs0, cl0)
      mut ai0 := 0
      mut g0 := ah1
      while g0 != 0 {
        ga0 := deref(arg_p(g0))
        if not (gen0 and callee_param_is_type(decls, upto, src, cs0, cl0, ai0, a)) {
          if tb0 and sema_type_arg_ok(ga0.e, decls, src) { }
          else {
            r2 := expr_unbound_span(ga0.e, decls, upto, src, a, locals, nloc)
            if r2 != 0 { return r2 }
          }
        }
        ai0 += 1
        g0 = ga0.next
      }
      0
    }
    Expr::StructLit(ss1, sl1, nf1, fh1) => {
      mut r3 := 0
      mut g1 := fh1
      while g1 != 0 and r3 == 0 {
        ga1 := deref(arg_p(g1))
        r3 = expr_unbound_span(ga1.e, decls, upto, src, a, locals, nloc)
        g1 = ga1.next
      }
      r3
    }
    Expr::EnumLit(es1, el1, vs1, vl1, np1, ph1) => {
      mut r4 := 0
      mut g2 := ph1
      while g2 != 0 and r4 == 0 {
        ga2 := deref(arg_p(g2))
        r4 = expr_unbound_span(ga2.e, decls, upto, src, a, locals, nloc)
        g2 = ga2.next
      }
      r4
    }
    Expr::Field(base3, fs3, fl3) => {
      if is_prelude_ns_var(base3, src) { 0 } else { expr_unbound_span(base3, decls, upto, src, a, locals, nloc) }
    }
    Expr::AddrOf(p0) => { expr_unbound_span(p0, decls, upto, src, a, locals, nloc) }
    Expr::Deref(p1) => { expr_unbound_span(p1, decls, upto, src, a, locals, nloc) }
    Expr::ArrayLit(ne1, eh1) => {
      mut r5 := 0
      mut g3 := eh1
      while g3 != 0 and r5 == 0 {
        ga3 := deref(arg_p(g3))
        r5 = expr_unbound_span(ga3.e, decls, upto, src, a, locals, nloc)
        g3 = ga3.next
      }
      r5
    }
    Expr::Index(base4, idx4) => {
      mut r6 := expr_unbound_span(base4, decls, upto, src, a, locals, nloc)
      if r6 == 0 { r6 = expr_unbound_span(idx4, decls, upto, src, a, locals, nloc) }
      r6
    }
    Expr::Try(inner3) => { expr_unbound_span(inner3, decls, upto, src, a, locals, nloc) }
    Expr::Slice(base5, lo5, hi5) => {
      mut r7 := expr_unbound_span(base5, decls, upto, src, a, locals, nloc)
      if r7 == 0 { r7 = expr_unbound_span(lo5, decls, upto, src, a, locals, nloc) }
      if r7 == 0 { r7 = expr_unbound_span(hi5, decls, upto, src, a, locals, nloc) }
      r7
    }
    Expr::CompField(base6, idx6) => {
      mut r8 := expr_unbound_span(base6, decls, upto, src, a, locals, nloc)
      if r8 == 0 { r8 = expr_unbound_span(idx6, decls, upto, src, a, locals, nloc) }
      r8
    }
    Expr::Unchecked(inner4) => { expr_unbound_span(inner4, decls, upto, src, a, locals, nloc) }
    Expr::FnRef(fnpos2, fms2, fml2) => { 0 }
    Expr::Lambda(fnpos3, ph2, rts2, rtl2, bh2, val2) => { 0 }
    Expr::Loop(body1) => { 0 }
  }
}

## Keep the old message class for direct Var/Call/aggregate/Field errors. A compound poison-only
## error used to fall back to `invalid` at the declaration; it now keeps that same `invalid` class while
## carrying the actual unbound child's source line.
unbound_code := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) -> CheckErr {
  legacy := s_of(e, a)
  nested := expr_unbound_span(e, decls, upto, src, a, locals, nloc)
  if nested != 0 {
    if legacy != 0 { return unbound_err(nested, 0) }
    return located_err(nested)
  }
  if legacy != 0 { return unbound_err(legacy, 0) }
  unbound_err(0, 0)
}

## Is `e` an integer LITERAL (`Num`)? (single-level match — seed-safe)
expr_is_num_lit := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::Num(v, s, n) => { r = true } _ => {} }
  r
}

## The value of an integer-literal `Num` expr, else 0.
expr_num_lit_val := fn(e : ptr(Expr)) -> i64 {
  mut r := 0
  match deref(e) { Expr::Num(v, s, n) => { r = v } _ => {} }
  r
}

## Types §6.4 / Assembly §3 / issue #5 — a direct numeric index on a local fixed array is a
## compile-time fact when the binding retains its `[T; N]` annotation. Reject only the proven
## out-of-range case, including N = 0; an array type remains legal, and dynamic slices, non-literal
## indices, aggregate paths, and globals stay on their existing runtime/deferred paths.
fixed_array_index_oob := fn(base : ptr(Expr), idx : ptr(Expr), src : ptr(u8), locals : ptr(LVec), nloc : usize) -> bool {
  if unchecked bitcast(usize, locals) == 0 or nloc == 0 or not expr_is_num_lit(idx) { return false }
  bv := expr_var_span(base)
  if bv.n == 0 or not local_in(locals, nloc, src, bv.s, bv.n) { return false }
  bt := local_ty(locals, nloc, src, bv.s, bv.n)
  mut tag : u8 = bt.tag
  if tag >= 128 and tag != 255 { tag = tag - 128 }
  if tag != 7 { return false }
  n := array_type_count(src, bt.ns, bt.nl)
  if n < 0 { return false }
  iv := expr_num_lit_val(idx)
  iv < 0 or iv >= n
}

## The source start of a numeric literal, for a located reject at the offending index token.
expr_num_lit_start := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::Num(v, s, n) => { r = s } _ => {} }
  r
}

## Does expression `e` MENTION the variable named `[xs, xs+xl)`? A conservative, standalone recursive
## walk (mirrors `expr_has_unbound`'s proven structure). Covers the common sub-expression-bearing forms;
## any variant not listed returns false — an UNDER-approximation, so a missed form is only a false
## NEGATIVE (under-enforcement), never a false positive (which would wrongly reject valid code). Used by
## the use-after-`forget` linearity check (spec §10): the discharge consumes an `@owning` handle,
## so a later mention of it is a use-after-consume error.
expr_mentions_var := fn(e : ptr(Expr), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  match deref(e) {
    Expr::Var(s, n) => { streq(src, s, n, xs, xl) }
    Expr::Bin(op, l, r) => { expr_mentions_var(l, src, xs, xl, a) or expr_mentions_var(r, src, xs, xl, a) }
    Expr::If(c, t, f) => { expr_mentions_var(c, src, xs, xl, a) or expr_mentions_var(t, src, xs, xl, a) or expr_mentions_var(f, src, xs, xl, a) }
    Expr::Field(b, fs, fl) => { expr_mentions_var(b, src, xs, xl, a) }
    Expr::Deref(p) => { expr_mentions_var(p, src, xs, xl, a) }
    Expr::AddrOf(p) => { expr_mentions_var(p, src, xs, xl, a) }
    Expr::Try(p) => { expr_mentions_var(p, src, xs, xl, a) }
    Expr::Unchecked(p) => { expr_mentions_var(p, src, xs, xl, a) }
    Expr::Index(b, i) => { expr_mentions_var(b, src, xs, xl, a) or expr_mentions_var(i, src, xs, xl, a) }
    Expr::Call(cs, cl, na, ah) => {
      mut r := false
      mut g := ah
      while g != 0 { ga := deref(arg_p(g)) ; if expr_mentions_var(ga.e, src, xs, xl, a) { r = true } ; g = ga.next }
      r
    }
    Expr::StructLit(ns, nl, nf, fh) => {
      mut r := false
      mut g := fh
      while g != 0 { ga := deref(arg_p(g)) ; if expr_mentions_var(ga.e, src, xs, xl, a) { r = true } ; g = ga.next }
      r
    }
    _ => { false }
  }
}

## The first RUNTIME LOCAL mentioned by a `comptime if` condition, or `{0,0}` when the condition only
## uses literals, module facts, target facts, or other non-local expressions. This is deliberately a
## local-dependency fence rather than a second comptime evaluator: `lower::comptime_cond_eval` remains
## the authority for the complete foldable set, while `check` must reject the unambiguous runtime-local
## case before any backend can see it. The walk covers every expression child that can carry a value;
## an omitted AST form is only a conservative false negative and remains fail-loud in the lower.
sema_comptime_cond_runtime_local := fn(e : ptr(Expr), src : ptr(u8), locals : ptr(LVec), nloc : usize) -> VSpan {
  mut out := VSpan(s = 0, n = 0)
  if unchecked bitcast(usize, e) == 0 { return out }
  match deref(e) {
    Expr::Var(s, n) => {
      mut i := 0
      while i < nloc and out.n == 0 {
        l := lvec_at(locals, i)
        if streq(src, l.ns, l.nl, s, n) and not sema_local_is_comptime(src, l) { out = VSpan(s = s, n = n) }
        i += 1
      }
    }
    Expr::Bin(op, l, r) => {
      out = sema_comptime_cond_runtime_local(l, src, locals, nloc)
      if out.n == 0 { out = sema_comptime_cond_runtime_local(r, src, locals, nloc) }
    }
    Expr::If(c, t, f) => {
      out = sema_comptime_cond_runtime_local(c, src, locals, nloc)
      if out.n == 0 { out = sema_comptime_cond_runtime_local(t, src, locals, nloc) }
      if out.n == 0 { out = sema_comptime_cond_runtime_local(f, src, locals, nloc) }
    }
    Expr::Match(sc, ah) => {
      out = sema_comptime_cond_runtime_local(sc, src, locals, nloc)
      mut arm := ah
      while arm != 0 and out.n == 0 {
        am := deref(arm_p(arm))
        out = sema_comptime_cond_runtime_local(am.body, src, locals, nloc)
        arm = am.next
      }
    }
    Expr::Call(cs, cl, na, ah) => {
      mut g := ah
      while g != 0 and out.n == 0 {
        ga := deref(arg_p(g))
        out = sema_comptime_cond_runtime_local(ga.e, src, locals, nloc)
        g = ga.next
      }
    }
    Expr::StructLit(ss, sl, nf, fh) => {
      mut g := fh
      while g != 0 and out.n == 0 {
        ga := deref(arg_p(g))
        out = sema_comptime_cond_runtime_local(ga.e, src, locals, nloc)
        g = ga.next
      }
    }
    Expr::Field(b, fs, fl) => { out = sema_comptime_cond_runtime_local(b, src, locals, nloc) }
    Expr::EnumLit(es, el, vs, vl, np, ph) => {
      mut g := ph
      while g != 0 and out.n == 0 {
        ga := deref(arg_p(g))
        out = sema_comptime_cond_runtime_local(ga.e, src, locals, nloc)
        g = ga.next
      }
    }
    Expr::AddrOf(p) => { out = sema_comptime_cond_runtime_local(p, src, locals, nloc) }
    Expr::Deref(p) => { out = sema_comptime_cond_runtime_local(p, src, locals, nloc) }
    Expr::ArrayLit(ne, eh) => {
      mut g := eh
      while g != 0 and out.n == 0 {
        ga := deref(arg_p(g))
        out = sema_comptime_cond_runtime_local(ga.e, src, locals, nloc)
        g = ga.next
      }
    }
    Expr::Index(b, ix) => {
      out = sema_comptime_cond_runtime_local(b, src, locals, nloc)
      if out.n == 0 { out = sema_comptime_cond_runtime_local(ix, src, locals, nloc) }
    }
    Expr::Try(inner) => { out = sema_comptime_cond_runtime_local(inner, src, locals, nloc) }
    Expr::Slice(b, lo, hi) => {
      out = sema_comptime_cond_runtime_local(b, src, locals, nloc)
      if out.n == 0 { out = sema_comptime_cond_runtime_local(lo, src, locals, nloc) }
      if out.n == 0 { out = sema_comptime_cond_runtime_local(hi, src, locals, nloc) }
    }
    Expr::CompField(b, ix) => {
      out = sema_comptime_cond_runtime_local(b, src, locals, nloc)
      if out.n == 0 { out = sema_comptime_cond_runtime_local(ix, src, locals, nloc) }
    }
    Expr::Unchecked(inner) => { out = sema_comptime_cond_runtime_local(inner, src, locals, nloc) }
    Expr::Lambda(pos, ph, rts, rtl, bh, val) => { out = sema_comptime_cond_runtime_local(val, src, locals, nloc) }
    Expr::Bitcast(inner, ts, tl) => { out = sema_comptime_cond_runtime_local(inner, src, locals, nloc) }
    _ => {}
  }
  out
}

## If statement handle `h` is a discharge `forget(x)` (an `ExprStmt` calling `forget` with one `Var`
## argument), the forgotten variable's name span; else `{0, 0}`. `forget` is the linearity discharge
## primitive — only ever applied to an `@owning` handle — so no type resolution is needed here.
## If expression `e` is a linearity DISCHARGE call (spec §10), the discharged handle's name span;
## else `{0,0}`. Two discharge forms: the `forget` primitive (exact tail-name), and a type-specific
## FREE (tail-name ending `_free` — `strbuf_free`/`hashmap_free`/… ; a `_free`-suffixed fn is
## overwhelmingly a consumer). The discharged handle is the LAST bare-`Var` argument (a non-generic
## free `strbuf_free(s)` has the sole var `s`; a generic `free(T, v)` has the handle `v` last, the type
## a non-`Var`). Single-level `match deref(e)` (the proven accessor shape — a nested match degenerates
## under the seed). Conservative: a non-`Var` handle arg / a bare `free` name is a safe false negative.
expr_discharge_var := fn(e : ptr(Expr), src : ptr(u8), a : ptr(mut rt::Arena)) -> VSpan {
  mut res := VSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => {
      ## tail-name after the last `::` (a qualified `strbuf::strbuf_free` resolves like its bare form)
      mut toff := 0
      mut i := 0
      while i + 1 < cl { if str_at((src + cs + i), 2) == "::" { toff = i + 2 } ; i = i + 1 }
      tn := cl - toff
      nm := str_at((src + cs + toff), tn)
      is_forget := nm == "forget"
      ## a FREE: a `_free`-suffixed name (strbuf_free/hashmap_free/map_free/strmap_free), a consumer whose
      ## handle is its sole/last `Var` arg. (Bare `free` is NOT matched: the allocator `free(self, T, h,
      ## size, align)` carries the handle mid-signature, so the last-Var-arg heuristic would misfire.)
      ## …AND the call takes exactly ONE argument (the sole handle: `strbuf_free(s)`, `hashmap_free(m)`,
      ## `map_free(m)`, `strmap_free(m)`). Without the arity gate, ANY `_free`-suffixed helper matched —
      ## the compiler's own `d_cap_free(e, ph, na, …, hardreject)` (9 args) was mistaken for a discharge of
      ## its LAST `Var` arg, so the next recursive `d_cap_free(…)` read as a use-after-free (a false
      ## "unbound"). A real container free is unary; requiring `na == 1` excludes the multi-arg helpers.
      is_free := na == 1 and tn >= 5 and str_at((src + cs + toff + tn - 5), 5) == "_free"
      if is_forget or is_free {
        mut g := ah
        while g != 0 { ga := deref(arg_p(g)) ; vv := expr_var_span(ga.e) ; if vv.n != 0 { res = vv } ; g = ga.next }
      }
    }
    ## UFCS discharge over a simple-`Var` receiver (`x.strbuf_free()` — the corpus form) parses as an
    ## `EnumLit`: `es/el` = the receiver var name, `vs/vl` = the method name. If the method is a discharge
    ## (`forget` / `_free` tail), the receiver `es/el` is the consumed handle. An enum-variant lit never
    ## matches (variant names are not `forget`/`*_free`).
    Expr::EnumLit(es, el, vs, vl, np, phead) => {
      vm := str_at((src + vs), vl)
      if vm == "forget" or (vl >= 5 and str_at((src + vs + vl - 5), 5) == "_free") { res = VSpan(s = es, n = el) }
    }
    _ => {}
  }
  res
}

## The discharged-handle span if statement handle `h` is a discharge call — either as a bare `ExprStmt`
## (`forget(x)`) or bound in an `Assign` value (`r := strbuf_free(x)` — the corpus's free shape). Stmt
## accessors use BOUND-deref (`st := deref(...); match st`); an inline `match deref(node_ptr(Stmt))`
## degenerates the `ptr(Expr)` payload extraction (the lean-lower scar).
stmt_forget_var := fn(h : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> VSpan {
  mut res := VSpan(s = 0, n = 0)
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::ExprStmt(e, nx) => { res = expr_discharge_var(e, src, a) }
    Stmt::Assign(ns, nl, v, nx) => { res = expr_discharge_var(v, src, a) }
    _ => {}
  }
  res
}

## Does statement handle `h` MENTION the variable `[xs, xs+xl)`? Conservative: the expression-bearing
## statement forms that carry a use (`ExprStmt`/`Return`/`Assign` value); other forms return false
## (under-approximation — a false negative is safe, a false positive would wrongly reject).
## Walk a statement LIST — does any statement mention `[xs, xl)`? (Recurses via `stmt_mentions_var`.)
stmts_mention_var := fn(head : ptr(mut Stmt), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut res := false
  while cur != 0 { if stmt_mentions_var(cur, src, xs, xl, a) { res = true } ; cur = stmt_next_at(cur, a) }
  res
}

## Walk a `Match`'s arm list — does any arm (value `body` or statement `body_stmts`) mention `[xs, xl)`?
arms_mention_var := fn(head : ptr(mut Stmt), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut arm := head
  mut res := false
  while arm != 0 {
    am := deref(arm_p(arm))
    if expr_mentions_var(am.body, src, xs, xl, a) { res = true }
    if stmts_mention_var(am.body_stmts, src, xs, xl, a) { res = true }
    arm = am.next
  }
  res
}

## Does statement `h` MENTION the var `[xs, xl)`? Covers the value-bearing statement shapes AND recurses
## into nested control-flow blocks (if/while/loop/for/match) — so a use-after-discharge in a BRANCH after
## an unconditional `forget(x)` (`forget(x); if c { …x… }`) is caught, not just a same-list use.
stmt_mentions_var := fn(h : usize, src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut res := false
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::ExprStmt(e, nx) => { res = expr_mentions_var(e, src, xs, xl, a) }
    Stmt::Return(rv, nx) => { res = expr_mentions_var(rv, src, xs, xl, a) }
    Stmt::Assign(ns, nl, v, nx) => { res = expr_mentions_var(v, src, xs, xl, a) }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { res = streq(src, bns, bnl, xs, xl) or expr_mentions_var(fv, src, xs, xl, a) }
    Stmt::DerefAssign(p, v, nx) => { res = expr_mentions_var(p, src, xs, xl, a) or expr_mentions_var(v, src, xs, xl, a) }
    Stmt::IndexAssign(b, i, v, nx) => { res = expr_mentions_var(b, src, xs, xl, a) or expr_mentions_var(i, src, xs, xl, a) or expr_mentions_var(v, src, xs, xl, a) }
    Stmt::FieldPathAssign(pl, v, nx) => { res = expr_mentions_var(pl, src, xs, xl, a) or expr_mentions_var(v, src, xs, xl, a) }
    Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { res = expr_mentions_var(b, src, xs, xl, a) or expr_mentions_var(i, src, xs, xl, a) or expr_mentions_var(v, src, xs, xl, a) }
    Stmt::If(c, th, el, nx) => { res = expr_mentions_var(c, src, xs, xl, a) or stmts_mention_var(th, src, xs, xl, a) or stmts_mention_var(el, src, xs, xl, a) }
    Stmt::While(c, b, nx) => { res = expr_mentions_var(c, src, xs, xl, a) or stmts_mention_var(b, src, xs, xl, a) }
    Stmt::Loop(b, nx) => { res = stmts_mention_var(b, src, xs, xl, a) }
    Stmt::Unchecked(b, nx) => { res = stmts_mention_var(b, src, xs, xl, a) }
    Stmt::AllocWith(ae, b, nx) => { res = stmts_mention_var(b, src, xs, xl, a) }
    Stmt::For(fns, fnl, lo, hi, b, nx) => { res = expr_mentions_var(lo, src, xs, xl, a) or expr_mentions_var(hi, src, xs, xl, a) or stmts_mention_var(b, src, xs, xl, a) }
    Stmt::Match(sc, ah, nx) => { res = expr_mentions_var(sc, src, xs, xl, a) or arms_mention_var(ah, src, xs, xl, a) }
    _ => {}
  }
  res
}

## Does a lambda body bind `[xs, xl)` itself? Parameters, `:=` locals, loop variables, and match
## payloads shadow an enclosing local with the same spelling; a plain fn value is rejected only for a
## genuine free-variable use. Reassignments (`x = ...`) are deliberately not bindings, so they remain
## captures of the enclosing place.
sema_lambda_binds_arms := fn(head : ptr(mut Arm), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut arm := head
  mut hit := false
  while arm != 0 and not hit {
    am := deref(arm_p(arm))
    mut bd := am.binds_head
    while bd != 0 and not hit {
      if streq(src, bnd_ns(bd), bnd_nl(bd), xs, xl) { hit = true }
      bd = bnd_next(bd)
    }
    if not hit { hit = sema_lambda_binds_stmts(am.body_stmts, src, xs, xl, a) }
    arm = am.next
  }
  hit
}

sema_lambda_binds_stmts := fn(head : ptr(mut Stmt), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut hit := false
  while cur != 0 and not hit {
    st := deref(stmt_p(Stmt, cur))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { if not assign_is_reassign(src, ns, nl) and streq(src, ns, nl, xs, xl) { hit = true } }
      Stmt::If(c, th, el, nx) => { hit = sema_lambda_binds_stmts(th, src, xs, xl, a); if not hit { hit = sema_lambda_binds_stmts(el, src, xs, xl, a) } }
      Stmt::While(c, b, nx) => { hit = sema_lambda_binds_stmts(b, src, xs, xl, a) }
      Stmt::Loop(b, nx) => { hit = sema_lambda_binds_stmts(b, src, xs, xl, a) }
      Stmt::For(ns, nl, lo, hi, b, nx) => { if streq(src, ns, nl, xs, xl) { hit = true } else { hit = sema_lambda_binds_stmts(b, src, xs, xl, a) } }
      Stmt::Match(sc, ah, nx) => { hit = sema_lambda_binds_arms(ah, src, xs, xl, a) }
      Stmt::CompIf(c, th, el, nx) => { hit = sema_lambda_binds_stmts(th, src, xs, xl, a); if not hit { hit = sema_lambda_binds_stmts(el, src, xs, xl, a) } }
      Stmt::CompFor(vs, vl, iv, b, nx) => { if streq(src, vs, vl, xs, xl) { hit = true } else { hit = sema_lambda_binds_stmts(b, src, xs, xl, a) } }
      Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { if streq(src, vs, vl, xs, xl) { hit = true } else { hit = sema_lambda_binds_stmts(b, src, xs, xl, a) } }
      Stmt::CompMatch(sc, ah, nx) => { hit = sema_lambda_binds_arms(ah, src, xs, xl, a) }
      Stmt::Unchecked(b, nx) => { hit = sema_lambda_binds_stmts(b, src, xs, xl, a) }
      Stmt::AllocWith(e, b, nx) => { hit = sema_lambda_binds_stmts(b, src, xs, xl, a) }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  hit
}

sema_lambda_binds_name := fn(ph : ptr(mut Param), bh : ptr(mut Stmt), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut p := ph
  mut hit := false
  while p != 0 and not hit {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, xs, xl) { hit = true }
    p = pm.next
  }
  if not hit { hit = sema_lambda_binds_stmts(bh, src, xs, xl, a) }
  hit
}

## Return the lambda's `fn` source position if it mentions an enclosing local; otherwise 0. The
## existing conservative expression walker is intentional: it recognizes the ordinary value-bearing
## lambda forms without expanding closure ABI/dyn or unrelated residual expression cases.
sema_lambda_capture_span := fn(ph : ptr(mut Param), bh : ptr(mut Stmt), val : ptr(Expr), src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  mut bad := 0
  mut i := 0
  while i < nloc and bad == 0 {
    l := lvec_at(locals, i)
    if not sema_lambda_binds_name(ph, bh, src, l.ns, l.nl, a) {
      if stmts_mention_var(bh, src, l.ns, l.nl, a) or expr_mentions_var(val, src, l.ns, l.nl, a) { bad = l.ns }
    }
    i += 1
  }
  bad
}

## FN-10 — a capturing lambda cannot inhabit a plain one-word fn field/value. Return its located
## `fn` span so callers can use the normal semantic `type mismatch` diagnostic on every front end.
sema_plain_fn_capture_span := fn(ts : usize, tl : usize, e : ptr(Expr), src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  if not sema_is_plain_fn_type(src, ts, tl) { return 0 }
  mut bad := 0
  match deref(e) {
    Expr::Lambda(pos, ph, rts, rtl, bh, val) => { bad = sema_lambda_capture_span(ph, bh, val, src, locals, nloc, a); if bad != 0 { bad = pos } }
    _ => {}
  }
  bad
}

## Standalone walk for the StructLit shape: `check_expr`'s large enum match is intentionally
## conservative under the frozen seed, so the common FN-10 fence is applied by `check_expr_da` before
## any backend-specific lowering can see the nested lambda.
sema_plain_fn_capture_struct := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  mut bad := 0
  match deref(e) {
    Expr::StructLit(ss, sl, nf, fh) => {
      di := type_decl_index(decls, upto, src, ss, sl)
      mut fld := 0
      if di != 0 { fld = (deref(decl_at(Decl, rt::vec_get(deref(decls), di - 1)))).fields_head }
      mut g := fh
      while g != 0 and bad == 0 {
        ga := deref(arg_p(g))
        if fld != 0 {
          fd := deref(fld_p(fld))
          bad = sema_plain_fn_capture_span(fd.ts, fd.tl, ga.e, src, locals, nloc, a)
          fld = fd.next
        }
        g = ga.next
      }
    }
    _ => {}
  }
  bad
}

## USE-AFTER-`forget` linearity check (spec §10 — the first enforced slice of `@owning` linearity):
## within a statement list, a `forget(x)` DISCHARGES the linear handle `x`, so any LATER mention of `x`
## in the same list is a use-after-consume error — poisoned via `mark_failed`. Scoped to one list (a
## cross-block use is a safe false negative). Corpus-safe: the compiler's 5 `forget` sites are all
## terminal (the handle is never touched after discharge), so this rejects nothing that exists today.
check_forget_uses := fn(head : ptr(mut Stmt), src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec)) {
  mut cur := head
  while cur != 0 {
    fv := stmt_forget_var(cur, src, a)
    if fv.n != 0 {
      mut nx := stmt_next_at(cur, a)
      while nx != 0 {
        if stmt_mentions_var(nx, src, fv.s, fv.n, a) { mark_failed(locals, unbound_err(fv.s, 0)) }
        nx = stmt_next_at(nx, a)
      }
    }
    cur = stmt_next_at(cur, a)
  }
}

## Check a fn body's arena-linked statement list (`head`, 0 = none) and grow the in-scope
## `locals` as bindings are introduced: an `Assign`'s value expression is checked, then its
## name is recorded with the value's synthesized type (so later statements see its type); a
## `While`'s condition + nested body are checked; `If`/`Match` recurse into their branch/arm
## statement lists; `Return`/`FieldAssign` check their value. `nloc` (the length of `locals`)
## is threaded by-value; `locals` itself is appended to. Returns the updated local count.
check_stmts := fn(head : ptr(mut Stmt), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize, da : ptr(DA)) -> Result(usize, CheckErr) {
  check_forget_uses(head, src, a, locals)
  mut cur := head
  mut cnt := nloc
  ret_tag := deref((deref(locals)).failed) / 2
  while cur != 0 {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::Assign(ns, nl, v, nx) => {
        ## Declarations §1.2 / §10 — a plain re-assignment writes an existing place. The old branch
        ## treated an unknown `name = value` as a fresh local, so a misspelled target disappeared and
        ## the program could return a clean wrong value. Keep module mut-globals and known top-level
        ## bindings on their existing paths; reject only a name proven absent from both scopes.
        if assign_is_reassign(src, ns, nl) and not local_in(locals, cnt, src, ns, nl) and not is_mod_mut_global(decls, src, ns, nl) and not declared(decls, upto, src, ns, nl) and not sema_global_name_anywhere(decls, src, ns, nl) {
          return Result(usize, CheckErr).Err(unbound_err(ns, nl))
        }
        ## Types §8 — reject the initialized local array literal before any lower/backend can apply
        ## the word-granular array stride to a byte-precise @packed element. Reassignments stay on
        ## their ordinary path; this is intentionally the exact local-initializer slice only.
        if not assign_is_reassign(src, ns, nl) {
          if sema_packed_array_literal(v, decls, src) {
            return Result(usize, CheckErr).Err(packed_array_err(ns))
          }
        }
        ## `name : T` is represented by the parser as Assign(name, zero-sentinel) to preserve the
        ## bootstrap-sensitive AST shape. Recover its declared type from source, record the local as
        ## unreadied, and do not type-check or mark the sentinel as an initializer.
        if local_is_uninit(src, ns, nl) {
          ann0 := local_type_span(src, ns, nl)
          ## Issue #215 bounded fallback: the exact local 2D fixed-array shapes are not yet safely
          ## lowerable, including a declaration followed by a later initialization. Reject before any
          ## backend can treat the nested array as a word-strided scalar array.
          if local_is_mut(src, ns) and sema_local_multidim_array(decls, upto, src, ann0.s, ann0.n) { return Result(usize, CheckErr).Err(local_multidim_array_err(ns)) }
          dt0 := resolve_ty(src, ann0.s, ann0.n, decls, upto)
          if dt0.tag == 0 { return Result(usize, CheckErr).Err(located_err(ns)) }
          mut bt0 : u8 = dt0.tag
          if local_is_mut(src, ns) { bt0 = bt0 + 128 }
          lvec_push(deref(locals), Local(ns = ns, nl = nl, tag = bt0, prov = 0, tns = dt0.ns, tnl = dt0.nl))
          da_push_root(da, ns, nl)
          if dt0.tag == 7 { da_seed_array(deref(da), src, ns, nl, dt0) }
          cnt += 1
          cur = nx
          continue
        }
        ## a bound atomic call (`r := atomic::cas_*(…)`) with an illegal ordering (spec ch.110 §2) —
        ## poison via `mark_failed` (an early `return` mid-arm mis-lowers the arm's later logic).
        if call_atomic_ordering_bad(v, src, a) { mark_failed(locals, mismatch_err(s_of(v, a), 0)) }
        if expr_has_unbound(v, decls, upto, src, a, locals, cnt) { mark_failed(locals, unbound_code(v, decls, upto, src, a, locals, cnt)) }
        ann := local_type_span(src, ns, nl)
        ## Issue #215 bounded fallback: reject the exact direct annotation in the shared semantic pass,
        ## so `check`, build, and all emit-to-stdout backends cannot accept a silent wrong value/trap.
        ## Reassignments and every non-local shape remain outside this local declaration fence.
        if not assign_is_reassign(src, ns, nl) and local_is_mut(src, ns) and sema_local_multidim_array(decls, upto, src, ann.s, ann.n) {
          return Result(usize, CheckErr).Err(local_multidim_array_err(ns))
        }
        ## The lower has one deliberate whole-element consumer for this shape: an inferred local
        ## binding (`e := GE[i]`). An annotation or a reassignment may select a narrower/existing
        ## slot, so keep those in the ordinary value-position fence rather than letting the later
        ## aggregate copy outrun the destination's proven layout.
        tv := check_expr_da_mode(v, decls, upto, src, a, locals, cnt, da,
          not assign_is_reassign(src, ns, nl) and ann.n == 0)?
        ## FN-11 (Functions §1.6) — a `dyn fn(T…)->R` value is the type-erased two-word {code, env} fat
        ## pair, and the ONLY construction form the spec admits is `dyn_over(ptr(mut <store>))` over a
        ## NAMED PLACE holding a static closure (the env is explicit storage the `dyn` borrows, I3). Any
        ## OTHER initializer supplies no environment place — notably a plain fn NAME
        ## (`d : dyn fn(u64)->u64 = f`), which is the ZERO-CAPTURE case that the thin function-value type
        ## `fn(T…)->R` (FN-10) already covers. Left unchecked the lower's fat-pair emit went looking for a
        ## store slot that does not exist, read a bogus lambda index out of the decl vector and the
        ## COMPILER SIGSEGV'd; reject it here instead, LOCATED, before the lower can fault. `src/`+`lib/`
        ## declare no `dyn` local, so this never fires on the self-build → fixpoint-neutral.
        if ann.n != 0 and sema_is_dyn_type(src, ann.s, ann.n) and not sema_is_dyn_over_call(v, src) {
          mark_failed(locals, mismatch_err(ns, 0))
        }
        dt := resolve_ty(src, ann.s, ann.n, decls, upto)
        ## a re-assignment `=` to an existing local reuses its slot/type — and the new value's
        ## type must MATCH the local's established type (a `:=` binding fixed it; a later `=`
        ## with a mismatched type is an error; poison-tolerant via `ty_eq`). A fresh `:=` records
        ## the value's type. (The parser models both as `Assign`; distinguish by the source glyph.)
        ## A `:=` RE-BINDING of an already-bound name is legal (Alatyr has function-scoped locals that
        ## LEAK out of blocks — `if c { x := 5 } … x` sees `x` — and a later `:=` REDECLARES/shadows,
        ## re-typing the name; the lower compiles both, e.g. two sibling `for` loops each `d := …`). So
        ## only a `=` (reassign) to an existing local takes the immutable/type-match path; a `:=` (even
        ## of an existing name) takes the fresh-binding path below, re-pushing the current type (the
        ## LAST push wins in `local_ty`). Without this, the second `d :=` false-fired "immutable write".
        if is_mod_mut_global(decls, src, ns, nl) and assign_is_reassign(src, ns, nl) and not local_in(locals, cnt, src, ns, nl) {
          ## a `=` write to a module-level `mut` GLOBAL (`A64_CHK = ov`, `A64_SUB_ITS = …`): a `static`
          ## place the global's own `mut` authorizes writing — NOT a local. Do not push it as a fake local
          ## (which made a SECOND write to the same global read as an immutable-local reassign) and do not
          ## run the local immutable/type-match check. The RHS is already checked above; nothing more here.
          ## GLOBAL-REASSIGN conformance (TYP-6): `G = <aggregate>` into a scalar global (or the
          ## REVERSE, a scalar literal into an aggregate global) — the retired `Stmt::Assign` scalar-global
          ## emit net. Recover `G`'s declared `: T` from source and check it against the RHS.
          gsp := global_type_span(decls, src, ns, nl)
          if agg_scalar_bad(gsp.s, gsp.n, v, decls, upto, src, locals, cnt) { mark_failed(locals, mismatch_err(ns, 0)) }
          if global_nonlit_struct_assign_bad(decls, upto, src, ns, nl, v, tv, locals, cnt) { mark_failed(locals, global_agg_err(ns)) }
        } else if local_in(locals, cnt, src, ns, nl) and assign_is_reassign(src, ns, nl) {
          raw := local_ty(locals, cnt, src, ns, nl)
          ## Declarations §3.1 / Memory §1.6 — an existing local without `mut` is a validly typed
          ## place, but it is not writable. Use the dedicated located diagnostic instead of
          ## `mismatch_err`: the assignment's type already agrees, and the useful fact is the write
          ## permission at this source span. The same branch handles plain `=` and every compound
          ## operator after `assign_is_reassign` has recovered its spelling.
          if raw.tag < 128 and not da_has_root(da, src, ns, nl) and not local_is_mut(src, ns) or raw.tag == 255 { mark_failed(locals, immutable_err(ns)) }
          mut xtag : u8 = raw.tag
          if xtag >= 128 and xtag != 255 { xtag = xtag - 128 }
          ## normalize the HIDDEN aggregate tags (9 struct / 10 enum, set for a StructLit/EnumLit binding)
          ## back to their real struct(3)/enum(4) tag for the reassign type-match — else `tag_compat(9, 3)`
          ## false-rejects a valid `mut r := S(...)  … r = <struct value>` (a real tag-3 RHS).
          if xtag == 9 { xtag = 3 }
          if xtag == 10 { xtag = 4 }
          xt := Ty(tag = xtag, ns = raw.ns, nl = raw.nl)
          if not tag_compat(xt.tag, tv.tag) { mark_failed(locals, mismatch_err(ns, 0)) }
        } else {
          mut bad_decl := false
          if ann.n != 0 { bad_decl = not tag_compat(dt.tag, tv.tag) }
          ## Declarations §3.1 assignability, on the RELIABLE literal tag (`ann_lit_incompatible`) —
          ## `tv.tag` above is 0 for a literal whose `check_expr` arm does not dispatch, so the
          ## annotation constrained nothing. Located at the binding's own name span.
          if ann.n != 0 and ann_lit_incompatible(dt.tag, lbv_lit_tag(v)) { bad_decl = true }
          ## TYP-13: a float-spelled literal is never an integer initializer, while an integer
          ## literal in f32/f64 context must be exactly representable in that format.
          if ann.n != 0 and float_lit_into_integer_bad(src, ann.s, ann.n, v) { bad_decl = true }
          if ann.n != 0 and int_lit_into_float_bad(src, ann.s, ann.n, v) { bad_decl = true }
          ## Types §9.1 REPRESENTABILITY, on the annotation's type NAME (the width `dt.tag` collapsed
          ## away): `x : u8 = 300` / `x : i8 = 200` / `x : u32 = 5_000_000_000` were all accepted in
          ## silence and truncated at run time.
          if ann.n != 0 and ann_lit_range_bad(src, ann.s, ann.n, v) { bad_decl = true }
          ## With no annotation the literal takes the target's native SIGNED type (Types §9.1 /
          ## Declarations §3.4). A negative `Num` payload is the parser's 64-bit representation of a
          ## written non-negative literal at or above 2^63; reject it before the untyped binding can
          ## silently preserve the bit pattern as a native word.
          if ann.n == 0 and default_lit_range_bad(v) { bad_decl = true }
          ## CT-12 / Comptime §2.6 — a failed CHECKED GUARD in the comptime evaluation of this
          ## initializer is a LOCATED diagnostic at the operation's site, never a deferred trap.
          cte := ct_guard_err(src, ann.s, ann.n, v, ns, decls, upto)
          if cte != 0 { mark_failed(locals, cte) }
          ## The same whitelist over a CALL result, whose type comes from the callee's own DECLARED
          ## return type — the second source reliable enough to reject on (`sole_fn_ret_ty` answers only
          ## for an unambiguous, non-overloaded name). `g := fn() -> str { … }  x : u64 = g()` used to
          ## bind a two-word `str` into a word-sized integer and return a silent wrong value.
          if ann.n != 0 and lbv_lit_tag(v) == 0 {
            crt := sole_fn_ret_ty(v, decls, upto, src)
            if ann_lit_incompatible(dt.tag, crt.tag) { bad_decl = true }
          }
          if bad_decl { mark_failed(locals, mismatch_err(ns, 0)) }
          mut bind_tag : u8 = tv.tag
          mut bind_prov : u8 = 0
          ain := expr_addr_inner(v)
          if unchecked bitcast(usize, ain) != 0 and expr_field_span(ain).n != 0 { bind_prov = 1 }
          ## The binding's type NAME never comes from `tv`: `check_expr` hands its `Ty` back through the
          ## PACKED `Result(Ty, CheckErr)` carrier, which preserves only the TAG — `tv.ns`/`tv.nl` are
          ## STACK GARBAGE (the truncation the tag-5 recovery below already documents, generalized: it is
          ## a property of the carrier, not of the pointer tag). Seeding `bind_ns`/`bind_nl` with them
          ## recorded a "type-name span" that is not a `src` offset at all — typically a whole ABSOLUTE
          ## address. `local_is_owning` then fed it to `type_is_owning` → `streq(src + <absolute addr>,…)`
          ## and the COMPILER SIGSEGV'd at CHECK time on a valid program (`t := s` where `s : Slice(u64)`
          ## is a PARAM: `Slice` resolves to a NOMINAL struct decl, so the tag-3 leak probe fires and the
          ## garbage span is dereferenced). The frozen seed compiles the same program without faulting even
          ## though its own source snapshot carries this very line — the read is out of bounds there too, it
          ## just lands on a benign stale word in that binary's frame layout. So this is not a source-level
          ## regression against the seed but a LAYOUT-DEPENDENT out-of-bounds read that the current tree's
          ## frames finally aimed at a live absolute address. Start
          ## from UNKNOWN (0/0 — poison-tolerant everywhere a name is consulted) and let only RELIABLE
          ## STORAGE fill it in below: the callee's declared return type, a Var-local's RECORDED type,
          ## the aggregate-literal recovery, or the binding's own `: T` annotation.
          mut bind_ns := 0
          mut bind_nl := 0
          ## RECOVER the un-truncated type-NAME for a call-value binding (`x := f(...)`): `check_expr`'s
          ## `Result(Ty,…)` keeps the tag but drops ns/nl, so `x` otherwise records no resolvable type name.
          ## Re-resolve the callee's declared return type directly (`callee_ret_ty`, un-packed). Guarded to
          ## the SAME tag (never changes the type, only fills the dropped name), unannotated bindings only.
          ccs := expr_call_callee_span(v)
          if ccs.n != 0 {
            crt := callee_ret_ty(decls, upto, src, ccs.s, ccs.n)
            ## adopt the callee's declared return type DIRECTLY (not via the truncating Result) — restores
            ## the tag + type-name the packed `Result` dropped. STRUCT-only (tag 3): every `@owning` type is
            ## a struct, so this suffices for leak-detection while leaving ENUM locals untouched (recording a
            ## call-created enum's generic return-type name — e.g. `Result(U, E)` — would make the match
            ## exhaustiveness check mis-resolve its variants and spuriously reject; found via result_and_then).
            if crt.tag == 3 and crt.nl != 0 { bind_tag = crt.tag; bind_ns = crt.ns; bind_nl = crt.nl }
          }
          ## POINTER value (tag 5): the pointee NAME drives `ty_compat`'s ptr(X)-vs-ptr(Y) discrimination,
          ## but `tv.ns/tv.nl` came back through the truncating `Result(Ty,…)` (see above) → GARBAGE. A
          ## garbage pointee that happens to be nonzero makes a valid `x := <ptr-value>` then `f(x)`
          ## SPURIOUSLY mismatch against `f`'s real param pointee (found whole-tree: `b := bind_head` then
          ## `bnd_next(b)`; `inner := e` then `str_lit_info(inner)`). Recover the pointee RELIABLY from
          ## STORAGE, never the truncated Result: a Var-local RHS → that local's recorded pointee; otherwise
          ## DROP to unknown (0/0, poison-tolerant). Monotonic — this only ever REMOVES a known-pointee
          ## mismatch (an unknown pointee is compatible with anything), never introduces one.
          if bind_tag == 5 {
            bind_ns = 0
            bind_nl = 0
            rvs := expr_var_span(v)
            if rvs.n != 0 {
              rlt := local_ty(locals, cnt, src, rvs.s, rvs.n)
              mut rltag : u8 = rlt.tag
              if rltag >= 128 and rltag != 255 { rltag = rltag - 128 }
              if rltag == 5 { bind_ns = rlt.ns; bind_nl = rlt.nl; bind_prov = local_prov(locals, cnt, src, rvs.s, rvs.n) }
            }
          }
          if dt.tag != 0 { bind_tag = dt.tag; bind_ns = dt.ns; bind_nl = dt.nl }
          ## RELIABLE aggregate recording (scar #2: StructLit/EnumLit don't dispatch check_expr's big
          ## match, so `tv.tag` came back 0). Recover the aggregate type NAME + tag straight from the
          ## literal, so a later use of this local (return / annotated-local / call-arg / field / array-
          ## element / global sink) is checked against a scalar sink (TYP-6). An ARRAY literal of
          ## SCALAR-LITERAL elements is tagged 7 (scalar-element array) so a whole-aggregate store into
          ## `xs[i]` is rejected. Only fires when nothing has typed the binding yet (bind_tag == 0), so an
          ## annotation / call-return type still wins.
          if bind_tag == 0 {
            ## HIDDEN tags 9 (struct) / 10 (enum): `value_agg_ty` maps them back, but `check_expr`'s Var
            ## resolution does NOT surface them, so the overload-naive existing arg checks stay tolerant.
            ## Covers a StructLit / EnumLit / nullary-enum-variant RHS (and a Var aliasing such a local).
            vag := value_agg_ty(v, decls, upto, src, locals, cnt)
            if vag.tag == 3 { bind_tag = 9; bind_ns = vag.ns; bind_nl = vag.nl }
            else if vag.tag == 4 { bind_tag = 10; bind_ns = vag.ns; bind_nl = vag.nl }
            else {
              afe := expr_array_first(v)
              if unchecked bitcast(usize, afe) != 0 and value_is_scalar_lit(afe) { bind_tag = 7 }
            }
          }
          ## ANNOTATED-local conformance (both directions): `x : <scalar> = <aggregate>` or `x :
          ## <aggregate> = <scalar-literal>` — covers the float/char sink the tag-only `bad_decl` misses.
          if agg_scalar_bad(ann.s, ann.n, v, decls, upto, src, locals, cnt) { mark_failed(locals, mismatch_err(ns, 0)) }
          if local_is_mut(src, ns) { bind_tag = bind_tag + 128 }
          lvec_push(deref(locals), Local(ns = ns, nl = nl, tag = bind_tag, prov = bind_prov, tns = bind_ns, tnl = bind_nl))
          cnt += 1
        }
        da_remove_root(deref(da), src, ns, nl)
        cur = nx
      }
      Stmt::While(c, b, nx) => {
        cc := check_expr_da(c, decls, upto, src, a, locals, cnt, da)?
        ## the loop condition must be bool (a known non-bool is a `Mismatch`).
        if cc.tag != 0 and cc.tag != 2 { return Result(usize, CheckErr).Err(mismatch_err(s_of(c, a), 0)) }
        cnt = check_stmts(b, decls, upto, src, a, locals, cnt, da)?
        cur = nx
      }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => {
        if declared(decls, upto, src, bns, bnl) {
        } else if local_in(locals, cnt, src, bns, bnl) {
        } else { return Result(usize, CheckErr).Err(unbound_err(bns, bnl)) }
        ## A known struct write must name one of that struct's declared fields. The parser stores this
        ## write as separate base/field spans, so the expression walker cannot validate it for us.
        bowner := sema_struct_owner_name_span(decls, upto, src, locals, cnt, bns, bnl)
        if bowner.n != 0 and sema_field_ann_span(decls, upto, src, bowner.s, bowner.n, fns, fnl, a).n == 0 {
          return Result(usize, CheckErr).Err(unbound_err(fns, fnl))
        }
        cv := check_expr_da(fv, decls, upto, src, a, locals, cnt, da)?
        ## FIELD-ASSIGN conformance (TYP-6): `t.field = <aggregate>` into a scalar field (or the
        ## REVERSE, a scalar literal into an aggregate field) — the retired `Stmt::FieldAssign` emit net.
        ## Resolve the base's struct type NAME from its recorded local tag (3 = struct), then the field's
        ## declared type span, then check the stored value against it. Poison-tolerant (a non-struct or
        ## unknown base → no fire).
        bfe := local_ty(locals, cnt, src, bns, bnl)
        mut bftag : u8 = bfe.tag
        if bftag >= 128 and bftag != 255 { bftag = bftag - 128 }
        if (bftag == 3 or bftag == 9) and bfe.nl != 0 {
          ftsp := sema_field_ann_span(decls, upto, src, bfe.ns, bfe.nl, fns, fnl, a)
          if agg_scalar_bad(ftsp.s, ftsp.n, fv, decls, upto, src, locals, cnt) { mark_failed(locals, mismatch_err(bns, 0)) }
          da_assign_field(deref(da), decls, upto, src, bns, bnl, fns, fnl, Ty(tag = 3, ns = bfe.ns, nl = bfe.nl))
        }
        cur = nx
      }
      ## `o.i.v = e` — a nested-field store; check the value expression (the place is a nested Field).
      Stmt::FieldPathAssign(pl, fpv, nx) => {
        pbase := field_path_deref_var(pl)
        pfs := expr_field_span(pl)
        if pbase.n != 0 and local_prov(locals, cnt, src, pbase.s, pbase.n) == 1 and pfs.n != 0 {
          return Result(usize, CheckErr).Err(located_err(pfs.s))
        }
        cvp := check_expr_da(fpv, decls, upto, src, a, locals, cnt, da)?
        aep := expr_array_elem_nested_path(pl)
        if aep.ok {
          aty1 := local_ty(locals, cnt, src, aep.rs, aep.rn)
          da_assign_array_elem_nested_field(deref(da), decls, upto, src, aep.rs, aep.rn, aep.fs, aep.fl, aep.ss, aep.sl, i64(aep.ix), aty1)
        }
        anp := expr_array_nested_path(pl)
        if anp.ok {
          aty0 := local_ty(locals, cnt, src, anp.rs, anp.rn)
          da_assign_array_nested_field(deref(da), decls, upto, src, anp.rs, anp.rn, anp.fs, anp.fl, anp.ss, anp.sl, i64(anp.ix), aty0)
        }
        np := expr_nested_path(pl)
        if np.sl != 0 {
          mut rt := local_ty(locals, cnt, src, np.rs, np.rn)
          if rt.tag == 255 {
            gts := global_type_span(decls, src, np.rs, np.rn)
            if gts.n != 0 { rt = resolve_ty(src, gts.s, gts.n, decls, upto) }
          }
          da_assign_path(deref(da), decls, upto, src, np, rt)
        }
        cur = nx
      }
      Stmt::Return(rv, nx) => {
        s3ar := s3a_return_bad(rv, decls, upto, src, a, locals, cnt)
        if s3ar != 0 { return Result(usize, CheckErr).Err(located_err(s3ar)) }
        ## Check the DA place state before the broad unbound walker. The latter is intentionally
        ## conservative for ordinary expressions but can descend into an aggregate field return after
        ## a nested-path write; fail here with the located DA diagnostic instead of reaching that crashy
        ## aggregate path.
        if da_bad_expr(rv, da, src) { return Result(usize, CheckErr).Err(unbound_code(rv, decls, upto, src, a, locals, cnt)) }
        if expr_has_unbound(rv, decls, upto, src, a, locals, cnt) { mark_failed(locals, unbound_code(rv, decls, upto, src, a, locals, cnt)) }
        ## RETURN-PATH CHECK: an early `return <e>` must match the fn's declared return type
        ## (`ret_tag`, 0 = unknown → no check). Poison-tolerant: only when BOTH the returned
        ## type and the declared return type are KNOWN and differ is it a `Mismatch`. This
        ## covers returns nested in if/while/match branches (ret_tag threads into those bodies).
        rr := check_expr_da(rv, decls, upto, src, a, locals, cnt, da)
        match rr {
          Result::Ok(cr) => {
            if ret_tag != 0 and not tag_compat(cr.tag, u8(ret_tag)) { return Result(usize, CheckErr).Err(mismatch_err(s_of(rv, a), 0)) }
            ## The frozen seed can leave a payload-heavy literal's ordinary `check_expr` result UNKNOWN
            ## even though the AST shape is exact. Recover the literal tag on this return boundary so a
            ## `StrLit` cannot inhabit a scalar result slot merely because `cr.tag == 0`. This is the
            ## same bootstrap-safe classifier used by annotated bindings and loop-value checking; an
            ## unknown/non-literal remains conservative and is still handled by the existing paths.
            rlit := lbv_lit_tag(rv)
            if ret_tag != 0 and rlit != 0 and not tag_compat(rlit, u8(ret_tag)) { return Result(usize, CheckErr).Err(mismatch_err(s_of(rv, a), 0)) }
            ## A direct/UFCS call can have a declared result even when the bootstrap-safe `check_expr`
            ## carrier surfaced UNKNOWN for the payload-heavy call node. Recover that result before
            ## accepting an early `return make_str()` from a scalar-returning function.
            rcall := expr_call_result_ty(rv, decls, upto, src)
            if ret_tag != 0 and rcall.tag != 0 and not tag_compat(rcall.tag, u8(ret_tag)) {
              return Result(usize, CheckErr).Err(mismatch_err(s_of(rv, a), 0))
            }
          }
          Result::Err(e) => { return Result(usize, CheckErr).Err(e) }
        }
        cur = nx
      }
      Stmt::If(c, th, el, nx) => {
        if expr_statement_has_unbound(c, decls, upto, src, a, locals, cnt) {
          return Result(usize, CheckErr).Err(unbound_code(c, decls, upto, src, a, locals, cnt))
        }
        cc := check_expr_da(c, decls, upto, src, a, locals, cnt, da)?
        ## the condition must be bool (a known non-bool is a `Mismatch`).
        if cc.tag != 0 and cc.tag != 2 { return Result(usize, CheckErr).Err(mismatch_err(s_of(c, a), 0)) }
        ## With no unreadied places, preserve the established linear checker path. This is also important
        ## for the self-hosted compiler's large, fully-initialized source tree: branch snapshots are only
        ## materialized when the function actually contains an uninitialized place.
        if deref(da).len == 0 and hdr_len(unchecked bitcast(ptr(FVec), da_fvec(da))) == 0 and hdr_len(unchecked bitcast(ptr(FVec), da_pvec(da))) == 0 and hdr_len(unchecked bitcast(ptr(FVec), da_avec(da))) == 0 and hdr_len(unchecked bitcast(ptr(FVec), da_navec(da))) == 0 and hdr_len(unchecked bitcast(ptr(FVec), da_napvec(da))) == 0 {
          cnt = check_stmts(th, decls, upto, src, a, locals, cnt, da)?
          cnt = check_stmts(el, decls, upto, src, a, locals, cnt, da)?
        } else {
          ## Each arm starts from the same incoming unreadied set. A write in only one arm must not
          ## make the binding appear initialized after the join; a diverging arm contributes no path.
          ## Compute divergence before threading state. A direct-return arm can be checked for diagnostics,
          ## then discarded; the surviving arm is checked from the original incoming state and its state stays
          ## in `da` without a post-join copy.
          then_div := stmts_return(th, a) or stmt_starts_return(th, a)
          else_div := stmts_return(el, a) or stmt_starts_return(el, a)
          incoming_da := da_copy(da)
          then_cnt := check_stmts(th, decls, upto, src, a, locals, cnt, da)?
          then_da := da_copy(da)
          da_assign(deref(da), incoming_da)
          else_cnt := check_stmts(el, decls, upto, src, a, locals, cnt, da)?
          if then_div and not else_div {
          } else {
            else_da := da_copy(da)
            if then_div and else_div {
              deref(da).len = 0
            } else if else_div {
              da_assign(deref(da), then_da)
            } else {
              da2 := da_union_src(ptr(then_da), ptr(else_da), src)
              da_assign(deref(da), da2)
            }
          }
          if then_cnt > else_cnt { cnt = then_cnt } else { cnt = else_cnt }
        }
        cur = nx
      }
      Stmt::Match(sc, ah, nx) => {
        cs := check_expr_da_allow_enum_array_root(sc, decls, upto, src, a, locals, cnt, da)?
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          ## a variant arm `Variant(p0, …) => …` binds its PAYLOAD variables (`binds_head`, a `Bind`
          ## list) as locals VISIBLE ONLY IN THAT ARM. Their concrete types are instance-dependent
          ## (the enum payload, possibly a generic type-param) — bind them poison-tolerant (tag 0) so
          ## the arm body's references resolve. `base` restores the local count after the arm so the
          ## bindings (and the arm's own locals) do not leak into sibling arms.
          base := cnt
          mut bd := am.binds_head
          while unchecked bitcast(usize, bd) != 0 {
            bnns := bnd_ns(bd)
            bnnl := bnd_nl(bd)
            if not local_in(locals, cnt, src, bnns, bnnl) {
              lvec_push(deref(locals), Local(ns = bnns, nl = bnnl, tag = 0, prov = 0, tns = 0, tnl = 0))
              cnt += 1
            }
            bd = bnd_next(bd)
          }
          cnt = check_stmts(am.body_stmts, decls, upto, src, a, locals, cnt, da)?
          lvec_truncate(deref(locals), base)
          cnt = base
          arm = am.next
        }
        ## EXHAUSTIVENESS (§60/CF-1): a `match` on a KNOWN enum whose arms are ALL plain variant patterns
        ## (no `_` wildcard / comptime / lit arm — `wild != 0`) must cover EVERY variant; an uncovered
        ## variant is a `Mismatch`. Resolve the scrutinee's enum type by calling `local_ty` DIRECTLY on
        ## the scrutinee `Var` (its by-value `Ty` return preserves the type-NAME span ns/nl — verified),
        ## NOT via `cs` (check_expr's `Result(Ty, CheckErr)` payload truncates ns/nl to just the tag).
        ## Fail-open: fires only for a local enum scrutinee whose decl is found AND a variant is provably
        ## uncovered; a wildcard/special arm, non-local scrutinee, or unresolved type skips. The parser
        ## normalizes `Col::R` → `vs/vl = "R"`, so `streq` vs the bare variant name is correct.
        sv := expr_var_span(sc)
        if sv.n != 0 and cnt != 0 and local_in(locals, cnt, src, sv.s, sv.n) {
          sty := local_ty(locals, cnt, src, sv.s, sv.n)
          mut stag : u8 = sty.tag
          if stag >= 128 and stag != 255 { stag = stag - 128 }
          if stag == 4 and sty.nl != 0 {
            mut all_plain := true
            mut a2 := ah
            while a2 != 0 {
              am2 := deref(arm_p(a2))
              if am2.wild != 0 { all_plain = false }
              a2 = am2.next
            }
            if all_plain {
              mut edi : i64 = 0 - 1
              mut di := 0
              while di < upto {
                d := deref(decl_get(decls, di))
                if d.kind == 3 and streq(src, d.name_start, d.name_len, sty.ns, sty.nl) { edi = i64(di) }
                di += 1
              }
              if edi >= 0 {
                ed := deref(decl_get(decls, usize(edi)))
                mut fv := ed.fields_head
                mut uncovered := false
                while fv != 0 {
                  fdc := deref(fld_p(fv))
                  mut covered := false
                  mut a3 := ah
                  while a3 != 0 {
                    am3 := deref(arm_p(a3))
                    if streq(src, am3.vs, am3.vl, fdc.ns, fdc.nl) { covered = true }
                    a3 = am3.next
                  }
                  if not covered { uncovered = true }
                  fv = fdc.next
                }
                if uncovered { return Result(usize, CheckErr).Err(mismatch_err(s_of(sc, a), 0)) }
              }
            }
          }
          ## SCALAR exhaustiveness (§5.4): a RANGE-containing `bool`/`u8` scalar match must cover its
          ## finite domain (else a compile error). Fail-open for anything else (see scalar_coverage_gap).
          if (stag == 1 or stag == 2) and scalar_coverage_gap(ah, stag, sty.ns, sty.nl, src) {
            return Result(usize, CheckErr).Err(mismatch_err(s_of(sc, a), 0))
          }
        }
        cur = nx
      }
      ## `for i in lo .. hi { body }` — the bounds must be int; `i` is an int local visible in
      ## the body. (If a comparison/value were used as a bound it would be bool — `ty_eq` here
      ## is poison-tolerant, but a known non-int bound is rejected.)
      ## `deref(p) = v` — a store through a pointer. Both the pointer expression and the
      ## value expression are checked (their pointee/value type agreement is deferred — the
      ## pointee type is not tracked); introduces no new local.
      Stmt::DerefAssign(ptr, val, nx) => {
        cp := check_expr_da(ptr, decls, upto, src, a, locals, cnt, da)?
        cv := check_expr_da(val, decls, upto, src, a, locals, cnt, da)?
        cur = nx
      }
      ## `arr[i] = v` — an array element write. The base + index + value expressions are all
      ## checked (the base `Var` must be bound; the index must be int per the `Index` rule);
      ## introduces no new local. Element/value type agreement is deferred (element-type
      ## tracking is not done — the toy arrays hold word-sized ints).
      Stmt::IndexAssign(ib, ii, iv, nx) => {
        ## The base is a write place, not a value read. A simple local array may still be unreadied here.
        cib := check_expr(ib, decls, upto, src, a, locals, cnt)?
        ## Types §6.4 / Assembly §3 / issue #5 — the write target has the same statically provable
        ## bound as an `Expr::Index` read, but its base and index are stored as separate Stmt fields.
        ## Reuse the exact direct-local fixed-array test so zero-length and ordinary fixed-array OOB
        ## writes reject at the index literal while dynamic, nonliteral, global, and aggregate paths
        ## remain on their existing deferred/runtime paths.
        if fixed_array_index_oob(ib, ii, src, locals, cnt) {
          return Result(usize, CheckErr).Err(located_err(expr_num_lit_start(ii)))
        }
        cii := check_expr_da(ii, decls, upto, src, a, locals, cnt, da)?
        if cii.tag != 0 and cii.tag != 1 { return Result(usize, CheckErr).Err(mismatch_err(s_of(ii, a), 0)) }
        civ := check_expr_da(iv, decls, upto, src, a, locals, cnt, da)?
        ## INDEX-ASSIGN conformance (TYP-6): `xs[i] = <aggregate>` where `xs` is a SCALAR-element
        ## array (tag 7, recorded at binding from a scalar-literal-element ArrayLit) — the retired
        ## `Stmt::IndexAssign` emit net. Poison-tolerant: only a confidently scalar-element array + a
        ## confident aggregate value fires (a struct/enum-element array is left tolerant).
        ibv := expr_var_span(ib)
        if ibv.n != 0 {
          iae := local_ty(locals, cnt, src, ibv.s, ibv.n)
          if expr_is_num_lit(ii) {
            da_assign_array(deref(da), src, ibv.s, ibv.n, expr_num_lit_val(ii), iae)
          }
          mut iatag : u8 = iae.tag
          if iatag >= 128 and iatag != 255 { iatag = iatag - 128 }
          if iatag == 7 and (iae.nl == 0 or array_elem_scalar(src, iae.ns, iae.nl)) {
            va := value_agg_ty(iv, decls, upto, src, locals, cnt)
            if va.tag == 3 or va.tag == 4 { mark_failed(locals, mismatch_err(ibv.s, 0)) }
          }
        } else {
          if unchecked bitcast(usize, expr_field_base(ib)) != 0 and expr_is_num_lit(ii) {
            fbv := expr_field_base(ib)
            frv := expr_var_span(fbv)
            ffv := expr_field_span(ib)
            if frv.n != 0 and ffv.n != 0 {
              mut rte := local_ty(locals, cnt, src, frv.s, frv.n)
              if rte.tag == 255 {
                gts2 := global_type_span(decls, src, frv.s, frv.n)
                if gts2.n != 0 { rte = resolve_ty(src, gts2.s, gts2.n, decls, upto) }
              }
              da_assign_nested_array(deref(da), decls, upto, src, frv.s, frv.n, ffv.s, ffv.n, expr_num_lit_val(ii), rte)
            }
          }
        }
        cur = nx
      }
      ## `a[i].f = v` — an array-of-struct element-field write. The base array, index, and
      ## value are checked (the index must be int); introduces no new local. Field/value type
      ## agreement is deferred (element-type tracking is poison-tolerant here).
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => {
        ## The indexed base is a write place (`a[i].f`), not a whole-element read. Constant-index local
        ## fixed arrays of simple structs are tracked field-by-field; dynamic indices stay conservative.
        cfa := check_expr(fia, decls, upto, src, a, locals, cnt)?
        ## `Stmt::IndexFieldAssign` carries the direct array base and index separately, just like
        ## `Stmt::IndexAssign`; apply the same bounded check before the field-specific DA bookkeeping.
        if fixed_array_index_oob(fia, fii, src, locals, cnt) {
          return Result(usize, CheckErr).Err(located_err(expr_num_lit_start(fii)))
        }
        cfi := check_expr_da(fii, decls, upto, src, a, locals, cnt, da)?
        if cfi.tag != 0 and cfi.tag != 1 { return Result(usize, CheckErr).Err(mismatch_err(s_of(fii, a), 0)) }
        cfv := check_expr_da(fiv, decls, upto, src, a, locals, cnt, da)?
        iav := expr_var_span(fia)
        if iav.n != 0 and expr_is_num_lit(fii) {
          aty := local_ty(locals, cnt, src, iav.s, iav.n)
          da_assign_array_field(deref(da), decls, upto, src, iav.s, iav.n, ifs, ifl, expr_num_lit_val(fii), aty)
        } else if unchecked bitcast(usize, expr_field_base(fia)) != 0 and expr_is_num_lit(fii) {
          arrroot := expr_var_span(expr_field_base(fia))
          arrfield := expr_field_span(fia)
          if arrroot.n != 0 and arrfield.n != 0 {
            aty2 := local_ty(locals, cnt, src, arrroot.s, arrroot.n)
            da_assign_array_nested_field(deref(da), decls, upto, src, arrroot.s, arrroot.n, arrfield.s, arrfield.n, ifs, ifl, expr_num_lit_val(fii), aty2)
          }
        }
        cur = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        ## A RANGE `for i in lo .. hi` has a non-null `fhi`; both bounds must be int. A FOR-IN
        ## `for x in <iterable>` has `fhi == null` (0) — `flo` is the iterable (any aggregate/slice, NOT
        ## an int) and the loop var binds each ELEMENT. `check_expr_da(fhi, da)` when `fhi` is null DEREFERENCES
        ## A NULL POINTER → `check` SEGFAULTED on every for-in (`for_over_slice`/`_nonvar`/…); guard it.
        mut vtag : u8 = 0
        if unchecked bitcast(usize, fhi) != 0 {
          tlo := check_expr_da(flo, decls, upto, src, a, locals, cnt, da)?
          thi := check_expr_da(fhi, decls, upto, src, a, locals, cnt, da)?
          if tlo.tag != 0 and tlo.tag != 1 { return Result(usize, CheckErr).Err(mismatch_err(s_of(flo, a), 0)) }
          if thi.tag != 0 and thi.tag != 1 { return Result(usize, CheckErr).Err(mismatch_err(s_of(fhi, a), 0)) }
          vtag = 1
        } else {
          tf := check_expr_da(flo, decls, upto, src, a, locals, cnt, da)?
        }
        ## bind the loop variable (int for a range; the element type — left UNKNOWN, poison-tolerant —
        ## for a for-in) before checking the body.
        if local_in(locals, cnt, src, fns, fnl) {
        } else {
          lvec_push(deref(locals), Local(ns = fns, nl = fnl, tag = vtag, prov = 0, tns = 0, tnl = 0))
          cnt += 1
        }
        cnt = check_stmts(fb, decls, upto, src, a, locals, cnt, da)?
        cur = nx
      }
      ## `loop { body }` — the body is checked (locals it introduces thread out, as for `while`);
      ## no condition. `break` is a leaf with no value (a `break` outside a loop is checked by
      ## the scalar structural prepass in `stmts_bad_loop_control`).
      Stmt::Loop(b, nx) => {
        cnt = check_stmts(b, decls, upto, src, a, locals, cnt, da)?
        cur = nx
      }
      Stmt::Unchecked(b, nx) => {
        cnt = check_stmts(b, decls, upto, src, a, locals, cnt, da)?
        cur = nx
      }
      Stmt::AllocWith(ae, b, nx) => {
        cnt = check_stmts(b, decls, upto, src, a, locals, cnt, da)?
        cur = nx
      }
      Stmt::Break(_bv, _bd, nx) => {
        egab0 := sema_enum_global_array_value_bad(_bv, decls, upto, src, locals, cnt, a, false)
        if egab0 != 0 { return Result(usize, CheckErr).Err(enum_global_array_err(egab0)) }
        cur = nx
      }
      Stmt::Continue(_cd, nx) => { cur = nx }
      ## A bare expression statement (a call / `?` for effect): type-check the expression for
      ## well-formedness; its result is discarded, so it introduces no local.
      Stmt::ExprStmt(e, nx) => {
        ## a bare atomic/fence call in statement position — check ordering legality here (it reaches
        ## only `check_expr`, and the wrapper is the reliable hook, §1/§4 / spec ch.110).
        if call_atomic_ordering_bad(e, src, a) { er := Result(usize, CheckErr).Err(mismatch_err(0, 0)); return er }
        if expr_statement_has_unbound(e, decls, upto, src, a, locals, cnt) {
          return Result(usize, CheckErr).Err(unbound_code(e, decls, upto, src, a, locals, cnt))
        }
        ce := check_expr_da(e, decls, upto, src, a, locals, cnt, da)?
        cur = nx
      }
      ## COMPTIME statements (`comptime if`/`for`/`match`) — advance to the next statement. The branch
      ## bodies are NOT type-checked here: they are comptime-selected, and per two-phase semantics an
      ## unselected target-absent branch is not resolved/checked (§3.2). Without these arms the match had
      ## no case for them and no wildcard, so `cur` never advanced → `check` INFINITE-LOOPED on any
      ## `comptime if` (e.g. `arch_intrinsic.al`, num.al's operator shape) — a real hang, not just a gap.
      Stmt::CompIf(cc, cthen, celse, nx) => {
        ## The ordinary checker intentionally skips comptime bodies because target folding selects them
        ## later. The enum-array safety boundary is target-independent, however: whichever target makes
        ## an arm live must still reject a width-blind `GE[i]` value before its backend emits code.
        ctlocal := sema_comptime_cond_runtime_local(cc, src, locals, cnt)
        if ctlocal.n != 0 { return Result(usize, CheckErr).Err(comptime_cond_err(ctlocal.s)) }
        egcc := sema_enum_global_array_value_bad(cc, decls, upto, src, locals, cnt, a, false)
        if egcc != 0 { return Result(usize, CheckErr).Err(enum_global_array_err(egcc)) }
        egct := sema_enum_global_array_value_bad_stmts(cthen, decls, upto, src, locals, cnt, a)
        if egct != 0 { return Result(usize, CheckErr).Err(enum_global_array_err(egct)) }
        egce := sema_enum_global_array_value_bad_stmts(celse, decls, upto, src, locals, cnt, a)
        if egce != 0 { return Result(usize, CheckErr).Err(enum_global_array_err(egce)) }
        cur = nx
      }
      Stmt::CompFor(cvs, cvl, civ, cb, nx) => {
        if civ == 0 and sema_compfor_is_fields(src, cvs, cvl) {
          bad := sema_bad_typeinfo_field_stmts(cb, src, cvs, cvl, a)
          if bad != 0 { return Result(usize, CheckErr).Err(located_err(bad)) }
        }
        egcf := sema_enum_global_array_value_bad_stmts(cb, decls, upto, src, locals, cnt, a)
        if egcf != 0 { return Result(usize, CheckErr).Err(enum_global_array_err(egcf)) }
        cur = nx
      }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => {
        ## §3.3 COMPTIME STEP BUDGET: a LITERAL-bounded `comptime for` unrolling > 100000 steps is a
        ## clean CHECK diagnostic (the lower aborts on ANY over-budget range; this catches the common
        ## literal case at check with a location). Non-literal bounds are left to the lower's guard.
        if expr_is_num_lit(rlo) and expr_is_num_lit(rhi) and expr_num_lit_val(rhi) - expr_num_lit_val(rlo) > 100000 {
          return Result(usize, CheckErr).Err(located_err(s_of(rlo, a)))
        }
        mut egcr := sema_enum_global_array_value_bad(rlo, decls, upto, src, locals, cnt, a, false)
        if egcr == 0 { egcr = sema_enum_global_array_value_bad(rhi, decls, upto, src, locals, cnt, a, false) }
        if egcr == 0 { egcr = sema_enum_global_array_value_bad_stmts(rb, decls, upto, src, locals, cnt, a) }
        if egcr != 0 { return Result(usize, CheckErr).Err(enum_global_array_err(egcr)) }
        cur = nx
      }
      Stmt::CompMatch(cmsc, cmah, nx) => {
        mut egcm := sema_enum_global_array_value_bad(cmsc, decls, upto, src, locals, cnt, a, true)
        mut armc := cmah
        while armc != 0 and egcm == 0 {
          amc := deref(arm_p(armc))
          basec := cnt
          mut arm_cntc := cnt
          mut bdc := amc.binds_head
          while bdc != 0 {
            bnsc := bnd_ns(bdc)
            bnlc := bnd_nl(bdc)
            if not local_in(locals, arm_cntc, src, bnsc, bnlc) {
              lvec_push(deref(locals), Local(ns = bnsc, nl = bnlc, tag = 0, prov = 0, tns = 0, tnl = 0))
              arm_cntc += 1
            }
            bdc = bnd_next(bdc)
          }
          egcm = sema_enum_global_array_value_bad(amc.body, decls, upto, src, locals, arm_cntc, a, false)
          if egcm == 0 { egcm = sema_enum_global_array_value_bad_stmts(amc.body_stmts, decls, upto, src, locals, arm_cntc, a) }
          lvec_truncate(deref(locals), basec)
          armc = amc.next
        }
        if egcm != 0 { return Result(usize, CheckErr).Err(enum_global_array_err(egcm)) }
        cur = nx
      }
    }
  }
  Result(usize, CheckErr).Ok(cnt)
}

stmt_next_at := fn(h : usize, a : ptr(mut rt::Arena)) -> usize {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { nx }
    Stmt::While(c, b, nx) => { nx }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { nx }
    Stmt::FieldPathAssign(pl, fpv, nx) => { nx }
    Stmt::Return(rv, nx) => { nx }
    Stmt::If(c, th, el, nx) => { nx }
    Stmt::Match(sc, ah, nx) => { nx }
    Stmt::For(ns, nl, lo, hi, b, nx) => { nx }
    Stmt::DerefAssign(p, v, nx) => { nx }
    Stmt::IndexAssign(b, i, v, nx) => { nx }
    Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { nx }
    Stmt::Loop(b, nx) => { nx }
    Stmt::Unchecked(b, nx) => { nx }
    Stmt::AllocWith(ae, b, nx) => { nx }
    Stmt::Break(_bv, _bd, nx) => { nx }
    Stmt::Continue(_cd, nx) => { nx }
    Stmt::ExprStmt(e, nx) => { nx }
    Stmt::CompIf(c, th, el, nx) => { nx }
    Stmt::CompFor(vs, vl, iv, b, nx) => { nx }
    Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { nx }
    Stmt::CompMatch(sc, ah, nx) => { nx }
  }
}

expr_is_no_tail := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Num(v, s, n) => { v == 0 - 1 and n == 0 }
    _ => { false }
  }
}

## Structural loop-control prepass: `break`/`continue` require an enclosing runtime loop. This is
## kept separate from `check_stmts` to avoid widening or reshaping that hot self-host checker path.
stmts_bad_loop_control := fn(head : ptr(mut Stmt), in_loop : bool, a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut bad := false
  while cur != 0 {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::While(c, b, nx) => {
        if stmts_bad_loop_control(b, true, a) { bad = true }
        cur = nx
      }
      Stmt::For(ns, nl, lo, hi, b, nx) => {
        if stmts_bad_loop_control(b, true, a) { bad = true }
        cur = nx
      }
      Stmt::Loop(b, nx) => {
        if stmts_bad_loop_control(b, true, a) { bad = true }
        cur = nx
      }
      Stmt::Unchecked(b, nx) => {
        if stmts_bad_loop_control(b, true, a) { bad = true }
        cur = nx
      }
      Stmt::AllocWith(ae, b, nx) => {
        if stmts_bad_loop_control(b, true, a) { bad = true }
        cur = nx
      }
      Stmt::If(c, th, el, nx) => {
        if stmts_bad_loop_control(th, in_loop, a) { bad = true }
        if stmts_bad_loop_control(el, in_loop, a) { bad = true }
        cur = nx
      }
      Stmt::Match(sc, ah, nx) => {
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          if stmts_bad_loop_control(am.body_stmts, in_loop, a) { bad = true }
          arm = am.next
        }
        cur = nx
      }
      Stmt::Break(_bv, _bd, nx) => {
        if not in_loop { bad = true }
        cur = nx
      }
      Stmt::Continue(_cd, nx) => {
        if not in_loop { bad = true }
        cur = nx
      }
      Stmt::CompIf(c, th, el, nx) => {
        if stmts_bad_loop_control(th, in_loop, a) { bad = true }
        if stmts_bad_loop_control(el, in_loop, a) { bad = true }
        cur = nx
      }
      Stmt::CompFor(vs, vl, iv, b, nx) => {
        if stmts_bad_loop_control(b, in_loop, a) { bad = true }
        cur = nx
      }
      Stmt::CompMatch(sc, ah, nx) => {
        mut arm2 := ah
        while arm2 != 0 {
          am2 := deref(arm_p(arm2))
          if stmts_bad_loop_control(am2.body_stmts, in_loop, a) { bad = true }
          arm2 = am2.next
        }
        cur = nx
      }
      _ => { cur = stmt_next_at(cur, a) }
    }
  }
  bad
}

## Whether normal execution of a statement list must finish through `return`. Only the final
## statement can establish the property; `if` requires both branches and `match` every arm.
stmts_return := fn(head : ptr(mut Stmt), a : ptr(mut rt::Arena)) -> bool {
  if head == 0 { return false }
  mut last := head
  mut next := stmt_next_at(last, a)
  while next != 0 { last = next; next = stmt_next_at(last, a) }
  end := deref(stmt_p(Stmt, last))
  match end {
    Stmt::Return(rv, nx) => { true }
    Stmt::If(c, th, el, nx) => { el != 0 and stmts_return(th, a) and stmts_return(el, a) }
    ## a `comptime if` folds to exactly ONE branch at compile time; if BOTH branches return, the
    ## taken one returns regardless of which — so it satisfies the missing-return check (mirrors `If`).
    ## A fn whose whole body is a returning `comptime if` (`pick`/`other` in comptime_if) needs this.
    Stmt::CompIf(c, th, el, nx) => { el != 0 and stmts_return(th, a) and stmts_return(el, a) }
    Stmt::Match(sc, ah, nx) => {
      if ah == 0 { false }
      else {
        mut all := true
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          if not stmts_return(am.body_stmts, a) { all = false }
          arm = am.next
        }
        all
      }
    }
    ## a `comptime match typeinfo(T)` folds to ONE arm at compile time; if every arm returns, the
    ## folded one returns — so a fn whose body is a returning `comptime match` (comptime_match_bare)
    ## satisfies the missing-return check. Same all-arms-return shape as the runtime `Match`.
    Stmt::CompMatch(sc, ah, nx) => {
      if ah == 0 { false }
      else {
        mut all := true
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          if not stmts_return(am.body_stmts, a) { all = false }
          arm = am.next
        }
        all
      }
    }
    ## a trailing `unchecked { … }` / `@alloc(a) { … }` BLOCK carries the fn's result through its own
    ## tail — recurse into the block (`addr`/`off`'s whole body is `unchecked { base + off }`). Without
    ## this the missing-result check false-fired "invalid" on every unchecked-block-bodied fn.
    Stmt::Unchecked(b, nx) => { stmts_return(b, a) }
    Stmt::AllocWith(ae, b, nx) => { stmts_return(b, a) }
    _ => { false }
  }
}

## A parser-produced branch may retain an unreachable trailing sentinel after a direct `return`. This
## narrow companion recognizes that common shape without treating an arbitrary conditional return as a
## diverging arm; the full return-path helper remains authoritative for ordinary function tails.
stmt_starts_return := fn(head : ptr(mut Stmt), a : ptr(mut rt::Arena)) -> bool {
  if head == 0 { return false }
  st := deref(stmt_p(Stmt, head))
  match st {
    Stmt::Return(rv, nx) => { true }
    Stmt::If(c, th, el, nx) => { el != 0 and stmt_starts_return(th, a) and stmt_starts_return(el, a) }
    _ => { false }
  }
}

## Whether the statement list's final statement is an existing lower-supported tail-value carrier.
## This keeps the current braced `match` tail mode valid: with `cx.tail`, the final arm `ExprStmt`
## delivers the function result through `emit_return_value`.
stmts_tail_value := fn(head : ptr(mut Stmt), a : ptr(mut rt::Arena)) -> bool {
  if head == 0 { return false }
  mut last := head
  mut next := stmt_next_at(last, a)
  while next != 0 { last = next; next = stmt_next_at(last, a) }
  end := deref(stmt_p(Stmt, last))
  match end {
    Stmt::ExprStmt(e, nx) => { true }
    Stmt::Match(sc, ah, nx) => {
      if ah == 0 { false }
      else {
        mut all := true
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          if not stmts_tail_value(am.body_stmts, a) { all = false }
          arm = am.next
        }
        all
      }
    }
    Stmt::CompIf(c, th, el, nx) => { el != 0 and stmts_tail_value(th, a) and stmts_tail_value(el, a) }
    ## a trailing `if c { … } else { … }` where BOTH branches carry a tail value IS the fn's result (the
    ## lower delivers the taken branch's value) — the dual of `stmts_return`'s `If` arm. A match ARM whose
    ## body is such an if/else (e.g. `value_is_float`'s `Var` arm) reaches here; without it the enclosing
    ## match failed the missing-result check → "invalid" on every match-of-if-arms fn.
    Stmt::If(c, th, el, nx) => { el != 0 and stmts_tail_value(th, a) and stmts_tail_value(el, a) }
    ## a trailing `unchecked { … }` / `@alloc(a) { … }` block delivers the fn's tail value from inside
    ## the block (`addr := fn(…) -> ptr(u8) { unchecked { base + off } }`) — recurse into it.
    Stmt::Unchecked(b, nx) => { stmts_tail_value(b, a) }
    Stmt::AllocWith(ae, b, nx) => { stmts_tail_value(b, a) }
    _ => { false }
  }
}

## Recover whether a comptime-for header iterates `typeinfo(X).fields`. The parser intentionally keeps
## only the loop-variable span, so this small source scan mirrors lower::compfor_iter_arg and lets `check`
## validate the closed Field descriptor schema without type-checking the selected body.
sema_compfor_is_fields := fn(src : ptr(u8), vs : usize, vl : usize) -> bool {
  mut p := vs + vl
  lim := p + 512
  while p < lim and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") { p += 1 }
  if str_at((src + p), 2) != "in" { return false }
  p += 2
  while p < lim and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") { p += 1 }
  if str_at((src + p), 8) != "typeinfo" { return false }
  p += 8
  while p < lim and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") { p += 1 }
  if str_at((src + p), 1) != "(" { return false }
  mut depth := 1
  p += 1
  while p < lim and depth != 0 {
    c := str_at((src + p), 1)
    if c == "(" { depth += 1 }
    else if c == ")" { depth -= 1 }
    p += 1
  }
  while p < lim and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") { p += 1 }
  str_at((src + p), 1) == "." and str_at((src + p + 1), 6) == "fields"
}

## Find an unknown member read on the current comptime Field loop variable. Returns the member's source
## offset, or 0. The four CT-6 members are the complete descriptor schema; a missing result means the
## expression is unrelated and remains on the ordinary poison-tolerant sema path.
sema_bad_typeinfo_field_expr := fn(e : ptr(Expr), src : ptr(u8), vs : usize, vl : usize, a : ptr(mut rt::Arena)) -> usize {
  mut bad := 0
  match deref(e) {
    Expr::Bin(op, l, r) => { bad = sema_bad_typeinfo_field_expr(l, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(r, src, vs, vl, a) } }
    Expr::If(c, t, f) => { bad = sema_bad_typeinfo_field_expr(c, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(t, src, vs, vl, a) } ; if bad == 0 { bad = sema_bad_typeinfo_field_expr(f, src, vs, vl, a) } }
    Expr::Match(sc, ah) => {
      bad = sema_bad_typeinfo_field_expr(sc, src, vs, vl, a)
      mut arm := ah
      while arm != 0 and bad == 0 { am := deref(arm_p(arm)); bad = sema_bad_typeinfo_field_expr(am.body, src, vs, vl, a); if bad == 0 and am.body_stmts != 0 { bad = sema_bad_typeinfo_field_stmts(am.body_stmts, src, vs, vl, a) } ; arm = am.next }
    }
    Expr::Call(cs, cl, na, ah) => {
      mut arg := ah
      while arg != 0 and bad == 0 { aa := deref(arg_p(arg)); bad = sema_bad_typeinfo_field_expr(aa.e, src, vs, vl, a); arg = aa.next }
    }
    Expr::StructLit(ss, sl, nf, ah) => {
      mut arg := ah
      while arg != 0 and bad == 0 { aa := deref(arg_p(arg)); bad = sema_bad_typeinfo_field_expr(aa.e, src, vs, vl, a); arg = aa.next }
    }
    Expr::EnumLit(es, el, evs, evl, na, ah) => {
      mut arg := ah
      while arg != 0 and bad == 0 { aa := deref(arg_p(arg)); bad = sema_bad_typeinfo_field_expr(aa.e, src, vs, vl, a); arg = aa.next }
    }
    Expr::Field(base, fs, fl) => {
      vn := expr_var_span(base)
      if vn.n != 0 and streq(src, vn.s, vn.n, vs, vl) {
        nm := str_at((src + fs), fl)
        if not (nm == "name" or nm == "type" or nm == "offset" or nm == "mutable") { bad = fs }
      } else { bad = sema_bad_typeinfo_field_expr(base, src, vs, vl, a) }
    }
    Expr::AddrOf(x) => { bad = sema_bad_typeinfo_field_expr(x, src, vs, vl, a) }
    Expr::Deref(x) => { bad = sema_bad_typeinfo_field_expr(x, src, vs, vl, a) }
    Expr::ArrayLit(n, ah) => {
      mut arg := ah
      while arg != 0 and bad == 0 { aa := deref(arg_p(arg)); bad = sema_bad_typeinfo_field_expr(aa.e, src, vs, vl, a); arg = aa.next }
    }
    Expr::Index(base, idx) => { bad = sema_bad_typeinfo_field_expr(base, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(idx, src, vs, vl, a) } }
    Expr::Try(x) => { bad = sema_bad_typeinfo_field_expr(x, src, vs, vl, a) }
    Expr::Slice(base, lo, hi) => { bad = sema_bad_typeinfo_field_expr(base, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(lo, src, vs, vl, a) } ; if bad == 0 { bad = sema_bad_typeinfo_field_expr(hi, src, vs, vl, a) } }
    Expr::CompField(base, idx) => { bad = sema_bad_typeinfo_field_expr(base, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(idx, src, vs, vl, a) } }
    Expr::Unchecked(x) => { bad = sema_bad_typeinfo_field_expr(x, src, vs, vl, a) }
    Expr::Lambda(pos, ph, rs, rl, bs, value) => { bad = sema_bad_typeinfo_field_expr(value, src, vs, vl, a) }
    Expr::Bitcast(x, ts, tl) => { bad = sema_bad_typeinfo_field_expr(x, src, vs, vl, a) }
    Expr::Loop(body) => { bad = sema_bad_typeinfo_field_stmts(body, src, vs, vl, a) }
    _ => {}
  }
  bad
}

## Recursive statement companion for `sema_bad_typeinfo_field_expr`; it follows all expression-bearing
## statement forms but does not type-check or otherwise change comptime branch selection.
sema_bad_typeinfo_field_stmts := fn(head : ptr(mut Stmt), src : ptr(u8), vs : usize, vl : usize, a : ptr(mut rt::Arena)) -> usize {
  mut cur := head
  mut bad := 0
  while cur != 0 and bad == 0 {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::Assign(ns, nl, v, nx) => { bad = sema_bad_typeinfo_field_expr(v, src, vs, vl, a) }
      Stmt::While(c, b, nx) => { bad = sema_bad_typeinfo_field_expr(c, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_stmts(b, src, vs, vl, a) } }
      Stmt::FieldAssign(bns, bnl, fns, fnl, v, nx) => { bad = sema_bad_typeinfo_field_expr(v, src, vs, vl, a) }
      Stmt::Return(v, nx) => { bad = sema_bad_typeinfo_field_expr(v, src, vs, vl, a) }
      Stmt::If(c, th, el, nx) => { bad = sema_bad_typeinfo_field_expr(c, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_stmts(th, src, vs, vl, a) } ; if bad == 0 { bad = sema_bad_typeinfo_field_stmts(el, src, vs, vl, a) } }
      Stmt::Match(sc, ah, nx) => {
        bad = sema_bad_typeinfo_field_expr(sc, src, vs, vl, a)
        mut arm := ah
        while arm != 0 and bad == 0 { am := deref(arm_p(arm)); bad = sema_bad_typeinfo_field_expr(am.body, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_stmts(am.body_stmts, src, vs, vl, a) } ; arm = am.next }
      }
      Stmt::For(ns, nl, lo, hi, b, nx) => { bad = sema_bad_typeinfo_field_expr(lo, src, vs, vl, a); if bad == 0 and hi != 0 { bad = sema_bad_typeinfo_field_expr(hi, src, vs, vl, a) } ; if bad == 0 { bad = sema_bad_typeinfo_field_stmts(b, src, vs, vl, a) } }
      Stmt::DerefAssign(p, v, nx) => { bad = sema_bad_typeinfo_field_expr(p, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(v, src, vs, vl, a) } }
      Stmt::IndexAssign(b, i, v, nx) => { bad = sema_bad_typeinfo_field_expr(b, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(i, src, vs, vl, a) } ; if bad == 0 { bad = sema_bad_typeinfo_field_expr(v, src, vs, vl, a) } }
      Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { bad = sema_bad_typeinfo_field_expr(b, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(i, src, vs, vl, a) } ; if bad == 0 { bad = sema_bad_typeinfo_field_expr(v, src, vs, vl, a) } }
      Stmt::FieldPathAssign(p, v, nx) => { bad = sema_bad_typeinfo_field_expr(p, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_expr(v, src, vs, vl, a) } }
      Stmt::Loop(b, nx) => { bad = sema_bad_typeinfo_field_stmts(b, src, vs, vl, a) }
      Stmt::ExprStmt(v, nx) => { bad = sema_bad_typeinfo_field_expr(v, src, vs, vl, a) }
      Stmt::CompIf(c, th, el, nx) => { bad = sema_bad_typeinfo_field_expr(c, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_stmts(th, src, vs, vl, a) } ; if bad == 0 { bad = sema_bad_typeinfo_field_stmts(el, src, vs, vl, a) } }
      Stmt::CompFor(cvs, cvl, iv, b, nx) => { bad = sema_bad_typeinfo_field_stmts(b, src, vs, vl, a) }
      Stmt::CompForRange(rvs, rvl, lo, hi, b, nx) => { bad = sema_bad_typeinfo_field_expr(lo, src, vs, vl, a); if bad == 0 and hi != 0 { bad = sema_bad_typeinfo_field_expr(hi, src, vs, vl, a) } ; if bad == 0 { bad = sema_bad_typeinfo_field_stmts(b, src, vs, vl, a) } }
      Stmt::Unchecked(b, nx) => { bad = sema_bad_typeinfo_field_stmts(b, src, vs, vl, a) }
      Stmt::AllocWith(e, b, nx) => { bad = sema_bad_typeinfo_field_expr(e, src, vs, vl, a); if bad == 0 { bad = sema_bad_typeinfo_field_stmts(b, src, vs, vl, a) } }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  bad
}

## Check a fn body + return expr with a freshly-allocated `locals` set, freeing it on every
## Is `[tns, tnl)` the name of an `@owning` type? Find its decl and scan a bounded window from the
## name for the `@owning` effector — catches `Name := @owning struct/enum {…}` and the generic
## `Name := fn(T : type) -> type { @owning struct }`. A miss is a safe leak false-negative; only `@owning`
## types carry the marker, so a stray hit within the window is implausible.
type_is_owning := fn(decls : ptr(rt::Vec), upto : usize, src : ptr(u8), tns : usize, tnl : usize) -> bool {
  mut res := false
  if tnl == 0 { return res }
  for i in 0..upto {
    d := deref(decl_get(decls, i))
    if (d.kind == 1 or d.kind == 2 or d.kind == 3) and streq(src, d.name_start, d.name_len, tns, tnl) {
      p := d.name_start + d.name_len
      mut k := 0
      while k < 64 { if str_at((src + p + k), 7) == "@owning" { res = true } ; k = k + 1 }
    }
  }
  res
}

## Is the local `[xs, xl)` an `@owning` handle? Its recorded type (tag 3 struct / 4 enum; name in tns/tnl —
## reliable for call-values via the return-type-name recovery at the `Assign` binding) resolves to an
## `@owning` type. False for scalars / unresolved / non-owning aggregates.
local_is_owning := fn(locals : ptr(LVec), nloc : usize, src : ptr(u8), xs : usize, xl : usize, decls : ptr(rt::Vec), upto : usize) -> bool {
  lt := local_ty(locals, nloc, src, xs, xl)
  mut base : u8 = lt.tag
  if base >= 128 and base != 255 { base = base - 128 }
  if base != 3 and base != 4 { return false }
  type_is_owning(decls, upto, src, lt.ns, lt.nl)
}

## Does expr `e` USE the var `[xs, xl)` — CONSERVATIVELY for leak-detection: any form not fully understood
## returns `true` ("might use it, assume so"), so leak-detection can only false-NEGATIVE, never falsely
## flag a live handle. (Contrast `expr_mentions_var`, an under-approximation for use-after-discharge.)
expr_uses_var_cons := fn(e : ptr(Expr), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  match deref(e) {
    Expr::Num(v, s, n) => { false }
    Expr::BoolLit(v) => { false }
    Expr::StrLit(s, n, lbl, _ps, _pn) => { false }
    Expr::FloatLit(s, n) => { false }
    Expr::Var(s, n) => { streq(src, s, n, xs, xl) }
    Expr::Bin(op, l, r) => { expr_uses_var_cons(l, src, xs, xl, a) or expr_uses_var_cons(r, src, xs, xl, a) }
    Expr::Field(b, fs, fl) => { expr_uses_var_cons(b, src, xs, xl, a) }
    Expr::Deref(p) => { expr_uses_var_cons(p, src, xs, xl, a) }
    Expr::AddrOf(p) => { expr_uses_var_cons(p, src, xs, xl, a) }
    Expr::Try(p) => { expr_uses_var_cons(p, src, xs, xl, a) }
    Expr::Unchecked(p) => { expr_uses_var_cons(p, src, xs, xl, a) }
    Expr::Index(b, i) => { expr_uses_var_cons(b, src, xs, xl, a) or expr_uses_var_cons(i, src, xs, xl, a) }
    Expr::Call(cs, cl, na, ah) => {
      mut r := false
      mut g := ah
      while g != 0 { ga := deref(arg_p(g)) ; if expr_uses_var_cons(ga.e, src, xs, xl, a) { r = true } ; g = ga.next }
      r
    }
    Expr::StructLit(ns, nl, nf, fh) => {
      mut r := false
      mut g := fh
      while g != 0 { ga := deref(arg_p(g)) ; if expr_uses_var_cons(ga.e, src, xs, xl, a) { r = true } ; g = ga.next }
      r
    }
    Expr::ArrayLit(cnt, eh) => {
      mut r := false
      mut g := eh
      while g != 0 { ga := deref(arg_p(g)) ; if expr_uses_var_cons(ga.e, src, xs, xl, a) { r = true } ; g = ga.next }
      r
    }
    Expr::EnumLit(es, el, vs, vl, np, ph) => {
      ## receiver name (`es/el`, a UFCS receiver) counts as a use; plus any payload/arg exprs.
      mut r := streq(src, es, el, xs, xl)
      mut g := ph
      while g != 0 { ga := deref(arg_p(g)) ; if expr_uses_var_cons(ga.e, src, xs, xl, a) { r = true } ; g = ga.next }
      r
    }
    _ => { true }   ## Match / any other form: not fully scanned → assume USED (never falsely flag a leak)
  }
}

## Does statement `h` USE the var `[xs, xl)` — conservative (unknown form → true). Covers the straight-line
## value-bearing statement shapes; a store TARGETED AT the handle (`x.f = …` / an assign to `x`) also counts.
stmt_uses_var_cons := fn(h : usize, src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut res := false
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::ExprStmt(e, nx) => { res = expr_uses_var_cons(e, src, xs, xl, a) }
    Stmt::Return(rv, nx) => { res = expr_uses_var_cons(rv, src, xs, xl, a) }
    Stmt::Assign(ns, nl, v, nx) => { res = streq(src, ns, nl, xs, xl) or expr_uses_var_cons(v, src, xs, xl, a) }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { res = streq(src, bns, bnl, xs, xl) or expr_uses_var_cons(fv, src, xs, xl, a) }
    Stmt::DerefAssign(p, v, nx) => { res = expr_uses_var_cons(p, src, xs, xl, a) or expr_uses_var_cons(v, src, xs, xl, a) }
    Stmt::IndexAssign(b, i, v, nx) => { res = expr_uses_var_cons(b, src, xs, xl, a) or expr_uses_var_cons(i, src, xs, xl, a) or expr_uses_var_cons(v, src, xs, xl, a) }
    Stmt::FieldPathAssign(pl, v, nx) => { res = expr_uses_var_cons(pl, src, xs, xl, a) or expr_uses_var_cons(v, src, xs, xl, a) }
    Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { res = expr_uses_var_cons(b, src, xs, xl, a) or expr_uses_var_cons(i, src, xs, xl, a) or expr_uses_var_cons(v, src, xs, xl, a) }
    ## RUNTIME control flow — RECURSE into the nested block(s), so a use/discharge of the handle in ANY
    ## branch is found (→ not a leak). A handle used nowhere on any path is still flagged. (Comptime forms /
    ## break / continue / anything else fall to `_ => true` — conservatively "used", never a false positive.)
    Stmt::If(c, th, el, nx) => { res = expr_uses_var_cons(c, src, xs, xl, a) or stmts_use_cons(th, src, xs, xl, a) or stmts_use_cons(el, src, xs, xl, a) }
    Stmt::While(c, b, nx) => { res = expr_uses_var_cons(c, src, xs, xl, a) or stmts_use_cons(b, src, xs, xl, a) }
    Stmt::Loop(b, nx) => { res = stmts_use_cons(b, src, xs, xl, a) }
    Stmt::Unchecked(b, nx) => { res = stmts_use_cons(b, src, xs, xl, a) }
    Stmt::AllocWith(ae, b, nx) => { res = stmts_use_cons(b, src, xs, xl, a) }
    Stmt::For(fns, fnl, lo, hi, b, nx) => { res = expr_uses_var_cons(lo, src, xs, xl, a) or expr_uses_var_cons(hi, src, xs, xl, a) or stmts_use_cons(b, src, xs, xl, a) }
    Stmt::Match(sc, ah, nx) => { res = expr_uses_var_cons(sc, src, xs, xl, a) or arms_use_cons(ah, src, xs, xl, a) }
    _ => { res = true }   ## comptime form / break / continue / unknown → assume USED (conservative)
  }
  res
}

## Walk a statement LIST / a `Match`'s arms — does any statement/arm conservatively USE `[xs, xl)`?
stmts_use_cons := fn(head : ptr(mut Stmt), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut res := false
  while cur != 0 { if stmt_uses_var_cons(cur, src, xs, xl, a) { res = true } ; cur = stmt_next_at(cur, a) }
  res
}

arms_use_cons := fn(head : ptr(mut Stmt), src : ptr(u8), xs : usize, xl : usize, a : ptr(mut rt::Arena)) -> bool {
  mut arm := head
  mut res := false
  while arm != 0 {
    am := deref(arm_p(arm))
    if expr_uses_var_cons(am.body, src, xs, xl, a) { res = true }
    if stmts_use_cons(am.body_stmts, src, xs, xl, a) { res = true }
    arm = am.next
  }
  res
}


## The bound name of an `Assign` statement `h` (`x := …` / `x = …`), else `{0,0}`.
stmt_binding_var := fn(h : usize, a : ptr(mut rt::Arena)) -> VSpan {
  mut res := VSpan(s = 0, n = 0)
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { res = VSpan(s = ns, n = nl) }
    _ => {}
  }
  res
}

## LEAK-detection (spec §10): in a STRAIGHT-LINE fn, an `@owning` local that is bound and then NEVER
## used (not discharged, returned, stored, or passed) before the fn ends is a LEAK — poisoned via
## `mark_failed`. Sound by construction: any uncertain form makes the conservative scan report "used", so
## a leak is flagged only when the handle is PROVABLY never touched again (subsequent statements + the
## trailing value `dval`). Covers CONTROL-FLOW fns too: the use scan recurses into nested branches, so a
## handle used/discharged in ANY branch is not flagged — only a handle used NOWHERE on any path is a leak
## (the "created and totally ignored" case; the per-path "not discharged on SOME branch" case needs full
## multi-path obligation tracking and is a safe false-negative here). Corpus-safe (fixpoint confirms).
check_leaks := fn(head : ptr(mut Stmt), dval : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena), locals : ptr(LVec), nloc : usize) {
  mut cur := head
  while cur != 0 {
    bv := stmt_binding_var(cur, a)
    if bv.n != 0 and local_is_owning(locals, nloc, src, bv.s, bv.n, decls, upto) {
      mut used := expr_uses_var_cons(dval, src, bv.s, bv.n, a)
      mut nx := stmt_next_at(cur, a)
      while nx != 0 { if stmt_uses_var_cons(nx, src, bv.s, bv.n, a) { used = true } ; nx = stmt_next_at(nx, a) }
      if used == false { mark_failed(locals, unbound_err(bv.s, 0)) }
    }
    cur = stmt_next_at(cur, a)
  }
}

## Is `e` the address of a FN-SCOPED place — `ptr(x)` (`AddrOf(Var x)`) where `x` is a local/param (in
## `locals`)? RETURNING such a value dangles (the stack slot dies at the return) — spec Memory §5 marks
## `fn f() -> ptr(T) { x := 0 ; ptr(x) }` ill-formed. A global's address (not in `locals`) is fine.
expr_is_local_addr := fn(e : ptr(Expr), locals : ptr(LVec), nloc : usize, src : ptr(u8)) -> bool {
  mut res := false
  match deref(e) {
    Expr::AddrOf(inner) => {
      vv := expr_var_span(inner)
      if vv.n != 0 and local_in(locals, nloc, src, vv.s, vv.n) { res = true }
    }
    _ => {}
  }
  res
}

## Does a top-level `return <e>` in the list return the address of a fn-scoped place (a dangling ptr)?
stmts_return_local_addr := fn(head : ptr(mut Stmt), locals : ptr(LVec), nloc : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut res := false
  while cur != 0 {
    st := deref(stmt_p(Stmt, cur))
    match st {
      Stmt::Return(rv, nx) => { if expr_is_local_addr(rv, locals, nloc, src) { res = true } }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  res
}

## True if `[s, n)` names a MODULE-LEVEL mutable GLOBAL — a kind-0 non-fn zero-arity value decl whose
## name is preceded by `mut` in source (`mut G : ptr(u64) = …`). Such a place is `static` (Memory
## §5.3.1: it outlives every automatic place). The sema twin of `lower::is_module_mut_global`.
is_mod_mut_global := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return false }
  cnt := rt::vec_len(deref(decls))
  nh := sema_name_hash(src, s, n)
  mut res := false
  mut jc := sni_lo(cnt, nh)
  jce := sni_hi(cnt, nh)
  mut i := 0
  while jc < jce {
    i = sni_at(cnt, jc)
    jc = jc + 1
    if SDNH == 0 or i >= SDNH_N or rt::rec_get(unchecked bitcast(ptr(mut u8), SDNH), i) == nh {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.ret_tl == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, s, n) and local_is_mut(src, d.name_start) { res = true }
    }
    i += 1
  }
  res
}

## True if `[s, n)` names an `out` / `in out` parameter of the fn whose params are `params_head`
## (pmode == 2, ast.al). Such a parameter is a reference to the CALLER's place, which outlives the
## callee (Memory §5.3.1) — so storing a callee-local's address into it escapes upward.
is_out_param := fn(params_head : ptr(mut Param), src : ptr(u8), s : usize, n : usize, a : ptr(mut rt::Arena)) -> bool {
  mut pp := params_head
  mut res := false
  while pp != 0 {
    pm := deref(param_p(pp))
    if pm.pmode == 2 and streq(src, pm.ns, pm.nl, s, n) { res = true }
    pp = pm.next
  }
  res
}

## Walk a `Match`'s arms for a store-escape (below), recursing into each arm's statement body.
arms_store_escape := fn(head : ptr(mut Stmt), locals : ptr(LVec), nloc : usize, src : ptr(u8), a : ptr(mut rt::Arena), decls : ptr(rt::Vec), params_head : ptr(mut Param)) -> bool {
  mut arm := head
  mut res := false
  while arm != 0 {
    am := deref(arm_p(arm))
    if stmts_store_escape(am.body_stmts, locals, nloc, src, a, decls, params_head) { res = true }
    arm = am.next
  }
  res
}

## SCOPED-REFERENCE store-escape (spec Memory §5.3.1): storing `ptr(<fn-local>)` — the address of an
## automatic place that dies at the return — into a `static` place that OUTLIVES it is a forbidden
## upward flow. The canonical case (§5.3.1 example): a whole-place assign `G = ptr(x)` where `G` is a
## module-level `mut` global. Recurses through nested control-flow blocks so an escape inside an
## if/while/for/match branch is caught too. Conservative + sound: only a bare `ptr(<local>)` stored
## into a genuine module mut global (not a same/inner-scope binding) is flagged. (Escape via an `out`
## parameter / into an aggregate field is a follow-up.)
stmts_store_escape := fn(head : ptr(mut Stmt), locals : ptr(LVec), nloc : usize, src : ptr(u8), a : ptr(mut rt::Arena), decls : ptr(rt::Vec), params_head : ptr(mut Param)) -> bool {
  mut cur := head
  mut res := false
  while cur != 0 {
    st := deref(stmt_p(Stmt, cur))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        ## a REASSIGN into an OUTLIVING place — a module mut global (a `static` place) OR an `out`/`in
        ## out` parameter (a reference to the caller's place) — whose RHS is the address of a fn-scoped
        ## local escapes upward. `assign_is_reassign` distinguishes this from a same-named `:=` local
        ## binding (well-formed); check_stmts adds every Assign name to `locals`, so `local_in` cannot
        ## tell bind from reassign — the source scan does.
        rhs_local_addr := expr_is_local_addr(v, locals, nloc, src)
        tgt_global := is_mod_mut_global(decls, src, ns, nl)
        tgt_out := is_out_param(params_head, src, ns, nl, a)
        outlives := tgt_global or tgt_out
        reassign := assign_is_reassign(src, ns, nl)
        if rhs_local_addr and outlives and reassign { res = true }
      }
      ## storing `ptr(<local>)` into a FIELD / ELEMENT of a module mut global aggregate — a `static`
      ## place that outlives the local (§5.3.1: "a field of any aggregate that outlives R"). A field /
      ## element assign is always a store to an existing place, so no bind-vs-reassign check is needed;
      ## the base is a module mut global.
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => {
        if expr_is_local_addr(fv, locals, nloc, src) and is_mod_mut_global(decls, src, bns, bnl) { res = true }
      }
      Stmt::IndexAssign(b, i, iv, nx) => {
        bv := expr_var_span(b)
        if expr_is_local_addr(iv, locals, nloc, src) and is_mod_mut_global(decls, src, bv.s, bv.n) { res = true }
      }
      Stmt::IndexFieldAssign(b, i, fs, fl, ifv, nx) => {
        bv := expr_var_span(b)
        if expr_is_local_addr(ifv, locals, nloc, src) and is_mod_mut_global(decls, src, bv.s, bv.n) { res = true }
      }
      ## a DEEP-NESTED field path `G.a.b = ptr(<local>)` (`FieldPathAssign`): peel the place to its root
      ## var; if that root is a module mut global (a `static` place outliving the local), the address
      ## escapes upward — §5.3.1's "a field of any aggregate that outlives R" at arbitrary field depth.
      Stmt::FieldPathAssign(pl, pv, nx) => {
        rv := field_path_root_var(pl)
        if expr_is_local_addr(pv, locals, nloc, src) and rv.n != 0 and is_mod_mut_global(decls, src, rv.s, rv.n) { res = true }
      }
      Stmt::If(c, th, el, nx) => { if stmts_store_escape(th, locals, nloc, src, a, decls, params_head) or stmts_store_escape(el, locals, nloc, src, a, decls, params_head) { res = true } }
      Stmt::While(c, b, nx) => { if stmts_store_escape(b, locals, nloc, src, a, decls, params_head) { res = true } }
      Stmt::Loop(b, nx) => { if stmts_store_escape(b, locals, nloc, src, a, decls, params_head) { res = true } }
      Stmt::Unchecked(b, nx) => { if stmts_store_escape(b, locals, nloc, src, a, decls, params_head) { res = true } }
      Stmt::AllocWith(ae, b, nx) => { if stmts_store_escape(b, locals, nloc, src, a, decls, params_head) { res = true } }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if stmts_store_escape(b, locals, nloc, src, a, decls, params_head) { res = true } }
      Stmt::Match(sc, ah, nx) => { if arms_store_escape(ah, locals, nloc, src, a, decls, params_head) { res = true } }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  res
}

## True iff the fn declared at name span `[ns, ns+nl)` is a bodyless `@extern` FFI import (`name :=
## @extern … fn(…) -> R` / `@extern("sym")`). The parser gives it a placeholder `Num(0)` value + an
## empty body (Modules §7), so it carries nothing to check — and its declared return type may be an
## aggregate (a struct-returning `@abi(c)` import) that would spuriously MISMATCH the `Num(0)`
## placeholder in `check_fn`'s tail-value conformance. Source-scan (the parser records no flag),
## mirroring lower's `callee_is_abi_c`: from past the name, skip ws + `:=` + ws, then test for
## `@extern`. `src/` declares no `@extern` fn → this never fires on the self-build (fixpoint-neutral;
## `check` emits no code anyway). A `@abi(syscall)`/`@abi(naked)` fn is not matched (no leading `@extern`).
decl_is_extern_fn := fn(src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut p := ns + nl
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return false }
  p += 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  str_at((src + p), 7) == "@extern"
}

## exit (both success and the first error). The fallible sub-checks are captured by `match`
## (not `?`) so the owning `locals` Vec is always discharged before returning — `?` would leak
## it on an early failure (Memory §5.9 linearity). The locals are seeded with the fn's
## declared params (their resolved types); `check_stmts` grows the set as body bindings appear;
## then the trailing return expr (`value`) is checked, and its type must match the fn's declared
## return type (`-> R`) — a `Mismatch` at the return expr's span otherwise.
check_fn := fn(d : Decl, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> Result(usize, CheckErr) {
  ## A bodyless `@extern` FFI import has no body/tail to check — its `-> R` signature is trusted (the
  ## definition is external), exactly like the `@abi(syscall)` kind-4 fns `check_decl` already skips.
  ## Return early so a struct-returning `@abi(c)` import's placeholder `Num(0)` value is not compared
  ## against its aggregate return type (a spurious mismatch). Neutral: `src/` declares no `@extern`.
  if decl_is_extern_fn(src, d.name_start, d.name_len) { return Result(usize, CheckErr).Ok(0) }
  ## Encode the declared return tag in the same word used by `mark_failed`: high bits are
  ## `ret_tag * 2`, low bit is the sticky failure flag. This keeps return checking out of
  ## `check_stmts`' parameter list, avoiding a self-host stack-arg ABI edge for small integers.
  rett0 := resolve_ty(src, d.ret_ts, d.ret_tl, decls, upto)
  mut failed_word := usize(rett0.tag) * 2
  mut fspan_word := 0
  mut locals := lvec_new(a, 16, ptr(failed_word), ptr(fspan_word), d.mod_start, d.mod_len)
  mut pp := d.params_head
  while pp != 0 {
    pm := deref(param_p(pp))
    pt := resolve_ty(src, pm.ts, pm.tl, decls, upto)
    mut ptag : u8 = pt.tag
    if pm.pmode == 2 { ptag = ptag + 128 }
    lvec_push(locals, Local(ns = pm.ns, nl = pm.nl, tag = ptag, prov = 0, tns = pt.ns, tnl = pt.nl))
    pp = pm.next
  }
  ## Keep the scalar error code in a frame home while the internal Result path is active. The lean
  ## lower otherwise loses the sibling failure-state write when the Err payload is discarded.
  mut err := unbound_err(0, 0)
  mut failed := false
  mut pbad := 0
  mut pp0 := d.params_head
  while pp0 != 0 {
    pm0 := deref(param_p(pp0))
    pt0 := resolve_ty(src, pm0.ts, pm0.tl, decls, upto)
    if pt0.tag == 3 and layout_kind_is_byte(layout_kind(decls, src, pt0.ns, pt0.nl, deref(a))) and std_struct_has_aggregate_field(decls, src, pt0.ns, pt0.nl, deref(a)) { pbad = pm0.ns }
    pp0 = pm0.next
  }
  if pbad != 0 { failed = true; err = located_err(pbad) }
  no_tail := expr_is_no_tail(d.value)
  ## Locate structural rejections at the FN's declaration name (a `break`/`continue` AST node carries
  ## no span, and a missing result is a whole-fn property) — an honest "invalid at line N in <module>"
  ## rather than "location not tracked" (§1 item 6).
  if stmts_bad_loop_control(d.body_stmts, false, a) { failed = true; err = located_err(d.name_start) }
  if d.ret_tl != 0 and no_tail and not (stmts_return(d.body_stmts, a) or stmts_tail_value(d.body_stmts, a)) { failed = true; err = located_err(d.name_start) }
  ## FN-6 first slice: a LIFTED LAMBDA (SENTINEL `name_len == 0`) returning a MULTI-WORD aggregate —
  ## struct (tag 3), enum (tag 4), or str (tag 6) — is not yet supported (a lambda is called only
  ## indirectly, and the call site has no signature to size/field-resolve the aggregate result → a
  ## silent miscompile). Reject fail-loud on the check path (lower rejects on the build path). Nested
  ## `if`s, not `and` — the seed mis-lowers a comparison AND-ed condition here.
  if d.name_len == 0 {
    if rett0.tag == 3 { failed = true; err = located_err(d.name_start) }
    if rett0.tag == 4 { failed = true; err = located_err(d.name_start) }
    if rett0.tag == 6 { failed = true; err = located_err(d.name_start) }
  }
  mut nloc := d.arity
  ## the declared return type's tag — threaded into `check_stmts` so EVERY early `return <e>`
  ## (including in if/while/match branches) is checked against it, not just the tail expr.
  mut da := da_new(a, 16)
  rs := check_stmts(d.body_stmts, decls, upto, src, a, ptr(locals), d.arity, ptr(da))
  match rs {
    Result::Ok(n) => { nloc = n }
    Result::Err(e) => { err = e; failed = true }
  }
  ## Modules §3 body parity: check_stmts has already populated the function-wide local table, so the
  ## structural visibility walk can distinguish a legitimate local shadow from an inaccessible global
  ## without duplicating the checker’s block-scope bookkeeping.  A failure is a located semantic fact,
  ## not a lower/linker accident.
  if failed == false {
    vr0 := sema_vis_stmts(d.body_stmts, decls, src, d.mod_start, d.mod_len, ptr(locals), nloc, a)
    if vr0 != 0 { err = located_err(vr0); failed = true }
    if failed == false and no_tail == false {
      vr1 := sema_vis_expr(d.value, decls, src, d.mod_start, d.mod_len, ptr(locals), nloc, a)
      if vr1 != 0 { err = located_err(vr1); failed = true }
    }
  }
  ## §7.2 break-value TYPE CONSISTENCY (spec: "break-values of incompatible type are ill-formed"): run
  ## after `check_stmts` has populated the function-wide locals table, so Vars, calls, arithmetic, and
  ## fields can contribute known types in addition to literal values. Top level is entered at containment
  ## 255 (no real loop), so stray fn-level breaks impose nothing. Poisoned checker results remain unknown.
  if failed == false {
    lbvc := lbv_stmts(d.body_stmts, 255, decls, upto, src, a, ptr(locals), nloc)
    if lbv_code_tag(lbvc) == 250 {
      failed = true
      lsp := lbv_code_span(lbvc)
      if lsp != 0 { err = mismatch_err(lsp, 0) } else { err = mismatch_err(d.name_start, 0) }
    }
  }
  if failed == false and no_tail == false {
    s3at := s3a_return_bad(d.value, decls, upto, src, a, ptr(locals), nloc)
    if s3at != 0 { failed = true; err = located_err(s3at) }
  }
  if failed == false and no_tail == false {
    if expr_has_unbound(d.value, decls, upto, src, a, ptr(locals), nloc) and not da_bad_expr(d.value, ptr(da), src) { mark_failed(ptr(locals), unbound_code(d.value, decls, upto, src, a, ptr(locals), nloc)) }
    rv := check_expr_da(d.value, decls, upto, src, a, ptr(locals), nloc, ptr(da))
    match rv {
      Result::Ok(bt) => {
        ## the body's value type `bt` must match the declared return type `-> R`. NOTE: a body
        ## that ends in an early `return` has a placeholder tail expr `Num(0)` (an int), so a
        ## struct/enum-returning fn whose body all-early-returns would spuriously mismatch here;
        ## the toy grammar's fns return ints, so this is sound in practice (a refinement would
        ## skip the tail check when `body_stmts` ends in a `Return`). `ty_eq` is poison-tolerant,
        ## so an unresolved tail or return type never spuriously rejects. Recover a direct/UFCS
        ## call's declared result before comparing: the packed checker result may have surfaced 0.
        rett := resolve_ty(src, d.ret_ts, d.ret_tl, decls, upto)
        mut tail_ty := bt
        tcall := expr_call_result_ty(d.value, decls, upto, src)
        if tcall.tag != 0 { tail_ty = tcall }
        if not ty_compat(tail_ty, rett, src) { err = mismatch_err(s_of(d.value, a), 0); failed = true }
        ## The same literal fallback is needed for a tail expression: `fn() -> u64 { "x" }` has no
        ## explicit Stmt::Return for the ordinary tag check to see, while `lbv_lit_tag` knows the exact
        ## `StrLit` shape. Unknown tails stay poison-tolerant when the declared result is unresolved.
        rtail_lit := lbv_lit_tag(d.value)
        if rtail_lit != 0 and rett.tag != 0 and not tag_compat(rtail_lit, rett.tag) { err = mismatch_err(s_of(d.value, a), 0); failed = true }
      }
      Result::Err(e) => { err = e; failed = true }
    }
  }
  ## RETURN-sink aggregate↔scalar conformance (TYP-6) — the retired `Stmt::Return` emit net. The
  ## `check_stmts` `ret_tag` check already covers int/bool/struct/enum returns (both directions); this
  ## adds the float/char-aware sweep over every `return <v>` (nested branches too) + the tail value,
  ## consulting the return type NAME so an `-> f64`/`-> char` scalar sink is covered. Poison-tolerant.
  if d.ret_tl != 0 {
    if ret_agg_bad(d.body_stmts, d.ret_ts, d.ret_tl, decls, upto, src, ptr(locals), nloc, a) { mark_failed(ptr(locals), located_err(d.name_start)) }
    ## CT-12 / Comptime §2.6 — a checked constant expression returned from a function is evaluated
    ## in the declared `-> T` integer context. Preserve its operation span instead of collapsing the
    ## failure to the function name; runtime returns and `unchecked` expressions remain untouched.
    rcte := ct_return_guard_err(d.body_stmts, d.ret_ts, d.ret_tl, decls, upto, src, a)
    if rcte != 0 { err = rcte; failed = true }
    if no_tail == false {
      if agg_scalar_bad(d.ret_ts, d.ret_tl, d.value, decls, upto, src, ptr(locals), nloc) { mark_failed(ptr(locals), located_err(d.name_start)) }
    }
  }
  ## §10 leak-detection: an `@owning` local bound then never used before the fn ends (a leaked
  ## handle). Run after the body + params are in `locals` (so a local's `@owning` type resolves), and only
  ## if nothing has failed yet (avoid piling onto an already-rejected fn). Poisons via `mark_failed`.
  if failed == false and failed_word % 2 == 0 { check_leaks(d.body_stmts, d.value, decls, upto, src, a, ptr(locals), nloc) }
  ## DANGLING-pointer (spec Memory §5): returning `ptr(<local/param>)` escapes a stack-slot address that
  ## dies at the return. Checks the trailing value + top-level `return` statements. A returned global
  ## address / a bitcast handle-pointer (the corpus's pointer-return shape) is NOT flagged.
  if failed == false and failed_word % 2 == 0 {
    if expr_is_local_addr(d.value, ptr(locals), nloc, src) { mark_failed(ptr(locals), unbound_err(s_of(d.value, a), 0)) }
    if stmts_return_local_addr(d.body_stmts, ptr(locals), nloc, src, a) { mark_failed(ptr(locals), located_err(d.name_start)) }
  }
  ## STORE-ESCAPE (spec Memory §5.3.1): storing `ptr(<fn-local>)` into a module-level `mut` global — a
  ## static place that outlives the local — is a forbidden upward flow (the dual of the return-dangling
  ## case above). Same guards: only run on an otherwise-clean fn.
  if failed == false and failed_word % 2 == 0 {
    if stmts_store_escape(d.body_stmts, ptr(locals), nloc, src, a, decls, d.params_head) { mark_failed(ptr(locals), located_err(d.name_start)) }
  }
  fv := 0
  if failed_word % 2 != 0 { failed = true }
  ## If the failure carries no source span yet (`err / 4 == 0`): promote a `mark_failed`-recorded
  ## located code if one exists, else fall back to the FN's declaration name — so any fn-body
  ## rejection whose finer location was lost (e.g. a mismatched `return <literal>`, whose `Num` node
  ## has no span) still reports "at line N in <module>" rather than "location not tracked" (§1 item 6).
  if failed and err / 4 == 0 {
    if fspan_word != 0 { err = fspan_word } else { err = located_err(d.name_start) }
  }
  ## Surface the captured error (`err`, carrying kind + source span) via the `Err` channel so a
  ## diagnostic can locate the failure. Both the old `Ok(1)` and this `Err` make `check_program`
  ## return non-zero (reject), so the exit-code verdict is unchanged — only the span is now available.
  if failed { Result(usize, CheckErr).Err(err) } else { Result(usize, CheckErr).Ok(0) }
}

## Check one top-level decl by `kind`. A value binding (0) checks its `value` expr against the
## earlier top-level decls only (no locals). A fn (1) checks its body + return expr + return
## type with its params + body bindings in scope (`check_fn`). A struct (2) / enum (3) carries
## no expressions to check (skip).
check_decl := fn(d : Decl, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> Result(usize, CheckErr) {
  if d.kind == 1 { return check_fn(d, decls, upto, src, a) }
  if d.kind == 0 {
    mut failed_word := 0
    mut fspan_word := 0
    mut none := lvec_new(a, 1, ptr(failed_word), ptr(fspan_word), d.mod_start, d.mod_len)
    egab := sema_enum_global_array_value_bad(d.value, decls, upto, src, ptr(none), 0, a, false)
    if egab != 0 { return Result(usize, CheckErr).Err(enum_global_array_err(egab)) }
    vr0 := sema_vis_expr(d.value, decls, src, d.mod_start, d.mod_len, ptr(none), 0, a)
    if vr0 != 0 { return Result(usize, CheckErr).Err(located_err(vr0)) }
    rv := check_expr(d.value, decls, upto, src, a, ptr(none), 0)
    ## Declarations §3.1 assignability for a MODULE-LEVEL annotated binding — the same rule
    ## `check_stmts` applies to a local, on the same proven-only whitelist. A module binding carries no
    ## dedicated type field, so its `: T` is recovered from source exactly as `global_type_span` does.
    ## Without this `G : u64 = "nope"` was accepted at module scope even after the local form rejected.
    gts := local_type_span(src, d.name_start, d.name_len)
    if gts.n != 0 {
      gdt := resolve_ty(src, gts.s, gts.n, decls, upto)
      if ann_lit_incompatible(gdt.tag, lbv_lit_tag(d.value)) { mark_failed(ptr(none), mismatch_err(d.name_start, 0)) }
      if float_lit_into_integer_bad(src, gts.s, gts.n, d.value) { mark_failed(ptr(none), mismatch_err(d.name_start, 0)) }
      if int_lit_into_float_bad(src, gts.s, gts.n, d.value) { mark_failed(ptr(none), mismatch_err(d.name_start, 0)) }
      ## Types §9.1 REPRESENTABILITY at MODULE scope — the same per-type literal bound the local form
      ## applies, on the annotation's type NAME (`G : u8 = 300`).
      if ann_lit_range_bad(src, gts.s, gts.n, d.value) { mark_failed(ptr(none), mismatch_err(d.name_start, 0)) }
    } else {
      ## A module-level `name := literal` has the same no-context default as a local binding.
      if default_lit_range_bad(d.value) { mark_failed(ptr(none), mismatch_err(d.name_start, 0)) }
    }
    ## CT-12 / Comptime §2.6 — the MODULE-SCOPE mirror: `K : u64 = 18446744073709551615 + 1` is
    ## rejected where it is written, not left to trap when some run-time path reaches it.
    gcte := ct_guard_err(src, gts.s, gts.n, d.value, d.name_start, decls, upto)
    if gcte != 0 { mark_failed(ptr(none), gcte) }
    fv := 0
    match rv {
      Result::Ok(t) => {
        ## a poisoned value binding: surface the located code (if any) so the diagnostic names the
        ## line, else fall back to the BINDING's name span (parity with `check_fn`, §1 item 6) — never
        ## the span-less `Ok(1)` that drove the driver's "location not tracked". Verdict unchanged (still
        ## a reject); only the location is now always available.
        if failed_word != 0 {
          if fspan_word != 0 { return Result(usize, CheckErr).Err(fspan_word) }
          return Result(usize, CheckErr).Err(located_err(d.name_start))
        }
        return Result(usize, CheckErr).Ok(0)
      }
      Result::Err(e) => { return Result(usize, CheckErr).Err(e) }
    }
  }
  Result(usize, CheckErr).Ok(0)
}

## Whether two function declarations have the same overload signature. Return type does not
## participate (FN-7); parameter count and declared parameter types do.
same_fn_signature := fn(a0 : Decl, b0 : Decl, src : ptr(u8), ar : ptr(mut rt::Arena)) -> bool {
  if a0.arity != b0.arity { return false }
  mut ap := a0.params_head
  mut bp := b0.params_head
  while ap != 0 and bp != 0 {
    pa := deref(param_p(ap))
    pb := deref(param_p(bp))
    if not streq(src, pa.ts, pa.tl, pb.ts, pb.tl) { return false }
    ap = pa.next
    bp = pb.next
  }
  ap == 0 and bp == 0
}

## The arch NAME `[s,n)` of an `Arch.<name>` field access (the RHS of `target.arch == Arch.x86_64`),
## else `n == 0`. Mirrors `lower::arch_rhs_name` so `check` folds a decl guard exactly as `build` does.
sema_arch_rhs_name := fn(e : ptr(Expr), src : ptr(u8)) -> VSpan {
  match deref(e) {
    Expr::Field(b, fs, fl) => {
      vn := expr_var_span(b)
      if vn.n != 0 and str_at((src + vn.s), vn.n) == "Arch" { VSpan(s = fs, n = fl) } else { VSpan(s = 0, n = 0) }
    }
    _ => { VSpan(s = 0, n = 0) }
  }
}
## Fold a DECLARATION `when`-guard predicate (Comptime §7.1/§9; CT-5) for the x86_64 build: 1 = TRUE
## (decl active), 0 = FALSE (decl "as if absent"), -1 = cannot fold (KEEP active). A BYTE-FOR-BYTE
## mirror of `lower::decl_guard_fold` so `check` agrees with `build` on which guarded decls exist —
## TARGET gating `target.arch == Arch.<name>` composed with `not`/`and`/`or` (ops 42/40/41, `==`/`!=`
## = 20/28). Recurses on itself (never a nested match) to stay within the self-host lower idiom limits.
guard_fold := fn(cond : ptr(Expr), src : ptr(u8)) -> i64 {
  match deref(cond) {
    Expr::Bin(op, l, r) => {
      an := sema_arch_rhs_name(r, src)
      if an.n != 0 {
        eq := str_at((src + an.s), an.n) == "x86_64"
        if i64(op) == 20 { if eq { return 1 } return 0 }   ## `==`
        if i64(op) == 28 { if eq { return 0 } return 1 }   ## `!=`
        return -1
      }
      if i64(op) == 42 {                                   ## `not <pred>`
        lv := guard_fold(l, src)
        if lv == 1 { return 0 }
        if lv == 0 { return 1 }
        return -1
      }
      if i64(op) == 40 {                                   ## `and`
        lv := guard_fold(l, src)
        if lv == 0 { return 0 }
        rv := guard_fold(r, src)
        if rv == 0 { return 0 }
        if lv == 1 and rv == 1 { return 1 }
        return -1
      }
      if i64(op) == 41 {                                   ## `or`
        lv := guard_fold(l, src)
        if lv == 1 { return 1 }
        rv := guard_fold(r, src)
        if rv == 1 { return 1 }
        if lv == 0 and rv == 0 { return 0 }
        return -1
      }
      return -1
    }
    _ => { return -1 }
  }
}
## True iff decl `d` carries a `when`-guard that folds FALSE for this (x86_64) build — the spec's
## "as if the declaration were absent" (Comptime §9). Such a decl is neither duplicate-checked nor
## body-checked (exactly as `lower::emit_program` neuters it), so a false-guarded companion (a target
## alternative whose body calls a symbol absent on this target, or whose name duplicates the active
## one) does not FALSE-reject. A decl with no guard (`when_cond == 0`) or a TRUE/unfoldable guard stays
## active. `src/`+`lib/` carry no `when` (every `when_cond` is 0) → always active → check unchanged.
guard_is_false := fn(d : Decl, src : ptr(u8)) -> bool {
  if unchecked bitcast(usize, d.when_cond) == 0 { return false }
  guard_fold(d.when_cond, src) == 0
}

## ─── GENERIC when-GUARD LOCATED REJECT (CT-4/CT-5) ──────────────────────────────────────────────
## A generic fn may carry a comptime `when P(T)` predicate gating its INSTANTIATION: an instance whose
## concrete type-arg makes `P` FALSE is AS-IF-ABSENT — the lower's `guard_fold_inst` skips emitting it, so
## a call to it fails LOUD at LINK (undefined symbol). These helpers give `check` a SOURCE-LOCATED reject
## for that case instead of a bare link failure. They are a FAITHFUL SUBSET of `lower::guard_fold_inst`:
## they fold `size(U) <op> N` over a concrete STRUCT/ENUM type-arg (composed with `and`/`or`/`not`), built
## on the SAME `lower_layout` size primitives the lower's fold uses (`struct_words`/`enum_inst_words`), so
## the byte size agrees to the byte. EVERY OTHER predicate form — a `match typeinfo(T)` is-kind, a field/
## variant COUNT, a named `fn(type)->bool` call, AND a SCALAR or ABSTRACT (enclosing type-param) type-arg —
## is left UNFOLDED (→ admit). So sema NEVER rejects an instance the lower would emit (the direction that
## would break the build); those still fail-loud at link exactly as before. `src/`+`lib/` carry no generic
## `when` → every callee's `when_cond == 0` → this never fires on the self-build (fixpoint-neutral).

## Up to THREE type-PARAMETER bindings (param NAME span → the call's concrete type-ARG span), mirroring
## `lower::GuardTP`. A `.._l == 0` slot is absent. Passed BY POINTER (a 12-word bundle, sidestepping the
## by-value aggregate word budget) to the fold — its construction is this fn's OWN top-level local (the
## lower's landmine: a `ptr()` of a GuardTP built inside a match arm segfaults the lean lower).
SGuardTP := struct {
  gp_s : usize, gp_l : usize, its : usize, itl : usize,
  gp2_s : usize, gp2_l : usize, its2 : usize, itl2 : usize,
  gp3_s : usize, gp3_l : usize, its3 : usize, itl3 : usize,
}
## Resolve a type-name span `(ts,tl)` through the bindings `tp`: a generic type-PARAMETER → its concrete
## type-ARG; a name matching none is a concrete type used AS-IS. Mirrors `lower::guard_resolve_tp`.
sema_guard_resolve_tp := fn(tp : ptr(SGuardTP), src : ptr(u8), ts : usize, tl : usize) -> VSpan {
  t := deref(tp)
  if t.gp_l != 0 and streq(src, ts, tl, t.gp_s, t.gp_l) { return VSpan(s = t.its, n = t.itl) }
  if t.gp2_l != 0 and streq(src, ts, tl, t.gp2_s, t.gp2_l) { return VSpan(s = t.its2, n = t.itl2) }
  if t.gp3_l != 0 and streq(src, ts, tl, t.gp3_s, t.gp3_l) { return VSpan(s = t.its3, n = t.itl3) }
  VSpan(s = ts, n = tl)
}
## A comparison operator on two ints (24 `<` / 25 `>` / 26 `<=` / 27 `>=` / 20 `==` / 28 `!=`); 1 = true,
## 0 = false, -1 = not a comparison op. Byte-mirror of `lower::guard_cmp`.
sema_guard_cmp := fn(op : i64, l : i64, r : i64) -> i64 {
  if op == 24 { if l < r { return 1 } return 0 }
  if op == 25 { if l > r { return 1 } return 0 }
  if op == 26 { if l <= r { return 1 } return 0 }
  if op == 27 { if l >= r { return 1 } return 0 }
  if op == 20 { if l == r { return 1 } return 0 }
  if op == 28 { if l != r { return 1 } return 0 }
  return 0 - 1
}

## True when a resolved guard type span is concrete enough for the shared layout ladder. A bare unknown
## name remains unfoldable, preserving the old admit-by-default behavior for an abstract type parameter.
sema_guard_type_concrete := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return false }
  if str_at((src + s), 1) == "(" { return true }
  if str_at((src + s), 1) == "[" { return true }
  bn := base_type_name(src, s, n)
  if type_name_known(decls, src, bn.s, bn.n) { return true }
  if str_at((src + bn.s), bn.n) == "ptr" { return true }
  if is_view_type(src, s, n) { return true }
  false
}

## If `e` is `size(X)` over a concrete type-arg (resolved through `tp`), use the SAME byte-size ladder
## as the lower: packed/standard-byte structs report exact bytes, word structs retain their word size,
## tuples use standard product padding, and views/enums/niches use their declared layout. An abstract or
## unknown type stays UNFOLDED so a not-yet-monomorphized call is never wrongly rejected.
sema_guard_size_operand := fn(e : ptr(Expr), tp : ptr(SGuardTP), decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena)) -> i64 {
  match deref(e) {
    Expr::Call(cs, cl, nargs, ah) => {
      if str_at((src + cs), cl) == "size" and nargs >= 1 {
        aa := deref(arg_p(ah))
        tn := expr_var_span(aa.e)
        if tn.n == 0 { return 0 - 1 }
        rv := sema_guard_resolve_tp(tp, src, tn.s, tn.n)
        if not sema_guard_type_concrete(decls, src, rv.s, rv.n) { return 0 - 1 }
        ## S6 owns the constructive bool niche. Keep the checker conservative here; a direct lower
        ## `size(Option(bool))` still rejects loudly, never answers the ordinary 8-byte fallback.
        if is_bool_niche_pending(src, rv.s, rv.n) { return 0 - 1 }
        return i64(layout_type_size_bytes(decls, src, rv.s, rv.n, deref(a)))
      }
      return 0 - 1
    }
    _ => { return 0 - 1 }
  }
}
## ─── IS-KIND / FIELD-COUNT / NAMED-PREDICATE fold support (CT-4/CT-5) — the remaining `guard_fold_inst`
## forms, each a FAITHFUL sema mirror of its `lower.al` counterpart. Every one folds to a DEFINITE 0/1 only
## when the resolved type-arg is provably CONCRETE (a declared struct/enum, or a recognized scalar/pointer/
## str/fn/array/tuple spelling); a bare unknown name — an enclosing type-PARAM not yet monomorphized — folds
## to -1 (admit), so a not-yet-instantiated call is never wrongly rejected. Where the lower resolves a type
## name it uses the SAME `lower_layout` primitives (`base_type_name`/`struct_decl_of`/`enum_decl_of`/
## `brand_underlying`) as the lower's own fold, so `check` and `build` classify identically.

## `conv_kind` mirror (a pure leaf) — reimplemented rather than imported (it lives in `lower.al`, which sema
## must NOT import). f64/f32 → 1, the fixed-width integers → 0, else -1. Used ONLY to exclude the prelude
## scalar brands from the `Brand` kind (exactly as `lower::comptime_type_kind` does).
sema_conv_kind := fn(name : str) -> i64 {
  if name == "f64" or name == "f32" { return 1 }
  if name == "usize" or name == "isize" or name == "u8" or name == "u16" or name == "u32" or name == "u64" or name == "i8" or name == "i16" or name == "i32" or name == "i64" { return 0 }
  return 0 - 1
}
## Types §4.6 — a scalar/brand conversion constructor is exactly `T(v)`. This mirrors the lower's
## dispatch boundary: the built-in integer/float names use `sema_conv_kind`, while `brand_underlying`
## recognises bool/char and nominal brands. Ordinary calls are deliberately untouched, including a
## zero-argument user function whose name does not resolve as one of these conversion constructors.
sema_scalar_conversion_arity_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  cs := expr_call_callee_span(e)
  if cs.n == 0 or expr_call_arity(e) == 1 { return false }
  nm := str_at((src + cs.s), cs.n)
  if sema_conv_kind(nm) >= 0 { return true }
  brand_underlying(decls, src, cs.s, cs.n).n != 0
}
## Is `nm` a built-in SCALAR type spelling (a recognized concrete scalar — never a user type-param name)?
## The kernel scalars are NOT brands (only bool/char/f32/f64 are), so `brand_underlying` cannot see them;
## this list is what lets a concrete scalar type-arg (e.g. `u64`) fold its is-KIND guard while an abstract
## enclosing type-param (`T`) stays UNFOLDED. Admit is always safe, so an omitted exotic width just stays
## link-time — never a wrong reject.
sema_is_scalar_name := fn(nm : str) -> bool {
  if nm == "bool" or nm == "char" { return true }
  if nm == "usize" or nm == "isize" { return true }
  if nm == "u8" or nm == "u16" or nm == "u32" or nm == "u64" { return true }
  if nm == "i8" or nm == "i16" or nm == "i32" or nm == "i64" { return true }
  if nm == "f32" or nm == "f64" { return true }
  false
}
## Map a `match typeinfo(T)` arm's variant name to a KIND value — byte-mirror of `lower::comptime_kind_of_name`.
sema_comptime_kind_of_name := fn(src : ptr(u8), vs : usize, vl : usize) -> i64 {
  nm := str_at((src + vs), vl)
  if nm == "Struct" { return 2 }
  if nm == "Enum" { return 3 }
  if nm == "Array" { return 5 }
  if nm == "Scalar" { return 0 }
  if nm == "Brand" { return 6 }
  if nm == "Tuple" { return 7 }
  if nm == "Pointer" { return 8 }
  if nm == "Str" { return 9 }
  if nm == "Function" { return 10 }
  if nm == "Union" { return 11 }
  return 0 - 1
}
## A concrete instance type's KIND — byte-mirror of `lower::comptime_type_kind` (2 Struct / 3 Enum / 5 Array /
## 7 Tuple / 6 Brand / 8 Pointer / 9 Str / 10 Function / 0 Scalar; -1 = empty). Same helper chain the lower's
## own `comptime_type_kind` walks, so the kind agrees. ONLY called on a type already proven concrete.
sema_comptime_type_kind := fn(it_s : usize, it_l : usize, decls : ptr(rt::Vec), src : ptr(u8)) -> i64 {
  if it_l == 0 { return 0 - 1 }
  if str_at((src + it_s), 1) == "[" { return 5 }
  if str_at((src + it_s), 1) == "(" { return 7 }
  bn := base_type_name(src, it_s, it_l)
  bnm := str_at((src + bn.s), bn.n)
  if bnm == "ptr" { return 8 }
  if bnm == "str" { return 9 }
  if bnm == "fn" { return 10 }
  if brand_underlying(decls, src, bn.s, bn.n).n != 0 and not (bnm == "bool" or bnm == "char" or sema_conv_kind(bnm) >= 0) { return 6 }
  if struct_decl_of(decls, src, bn.s, bn.n) >= 0 { return 2 }
  if enum_decl_of(decls, src, bn.s, bn.n) >= 0 { return 3 }
  return 0
}
## Is the resolved type-name `[s, s+n)` provably CONCRETE (fully monomorphized), so its kind/count may fold?
## True for a declared struct/enum/brand, a `ptr`/`str`/`fn` spelling, an array `[…]`/tuple `(…)` spelling,
## or a recognized scalar. FALSE for a bare unknown name — an enclosing type-PARAM the lower folds only once
## it is a concrete instance type; those stay UNFOLDED here → admit → never a wrong reject.
sema_type_is_concrete := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return false }
  if str_at((src + s), 1) == "[" { return true }
  if str_at((src + s), 1) == "(" { return true }
  bn := base_type_name(src, s, n)
  bnm := str_at((src + bn.s), bn.n)
  if bnm == "ptr" or bnm == "str" or bnm == "fn" { return true }
  if struct_decl_of(decls, src, bn.s, bn.n) >= 0 { return true }
  if enum_decl_of(decls, src, bn.s, bn.n) >= 0 { return true }
  if brand_underlying(decls, src, bn.s, bn.n).n != 0 { return true }
  sema_is_scalar_name(bnm)
}
## If `scrut` is `typeinfo(U)` over a CONCRETE type-arg (resolved through `tp`), that type's KIND; -1 for a
## non-`typeinfo` scrutinee OR an abstract (not-yet-monomorphized) type-param. Mirrors `lower::guard_typeinfo_kind`
## but gated on `sema_type_is_concrete` so an abstract `U` folds to -1 (admit) — never a wrong reject.
sema_guard_typeinfo_kind := fn(scrut : ptr(Expr), tp : ptr(SGuardTP), decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena)) -> i64 {
  match deref(scrut) {
    Expr::Call(cs, cl, nargs, ah) => {
      if str_at((src + cs), cl) == "typeinfo" and nargs >= 1 {
        aa := deref(arg_p(ah))
        tn := expr_var_span(aa.e)
        if tn.n == 0 { return 0 - 1 }
        rv := sema_guard_resolve_tp(tp, src, tn.s, tn.n)
        if not sema_type_is_concrete(decls, src, rv.s, rv.n) { return 0 - 1 }
        return sema_comptime_type_kind(rv.s, rv.n, decls, src)
      }
      return 0 - 1
    }
    _ => { return 0 - 1 }
  }
}
## The RESOLVED concrete type a `typeinfo(U)` names (through `tp`), else `{0,0}` — mirrors
## `lower::guard_typeinfo_arg_type`. Backs the field/variant-COUNT fold.
sema_guard_typeinfo_arg_type := fn(scrut : ptr(Expr), tp : ptr(SGuardTP), src : ptr(u8)) -> VSpan {
  match deref(scrut) {
    Expr::Call(cs, cl, nargs, ah) => {
      if str_at((src + cs), cl) == "typeinfo" and nargs >= 1 {
        aa := deref(arg_p(ah))
        tn := expr_var_span(aa.e)
        return sema_guard_resolve_tp(tp, src, tn.s, tn.n)
      }
      return VSpan(s = 0, n = 0)
    }
    _ => { return VSpan(s = 0, n = 0) }
  }
}
## The declared FIELD count (struct) / VARIANT count (enum) of a concrete type `(rs,rn)` — the fold value of
## `typeinfo(T).fields.len` / `.variants.len`; -1 for a non-aggregate (a scalar/pointer has no member list,
## which is also how an abstract type-param — never a struct/enum decl — stays UNFOLDED). Byte-mirror of
## `lower::guard_type_member_count`.
sema_guard_type_member_count := fn(rs : usize, rn : usize, decls : ptr(rt::Vec), src : ptr(u8)) -> i64 {
  if rn == 0 { return 0 - 1 }
  bnt := base_type_name(src, rs, rn)
  sd := struct_decl_of(decls, src, bnt.s, bnt.n)
  if sd >= 0 {
    sdd := deref(decl_get(decls, usize(sd)))
    mut fc := 0
    mut f := sdd.fields_head
    while f != 0 { fc = fc + 1 ; f = deref(fld_p(f)).next }
    return i64(fc)
  }
  ed := enum_decl_of(decls, src, bnt.s, bnt.n)
  if ed >= 0 {
    edd := deref(decl_get(decls, usize(ed)))
    mut vc := 0
    mut vf := edd.fields_head
    while vf != 0 { vc = vc + 1 ; vf = deref(fld_p(vf)).next }
    return i64(vc)
  }
  return 0 - 1
}
## Peel `typeinfo(U).fields` / `.variants` (the Field WRAPPING the `typeinfo` call) to the resolved instance
## type of its inner `typeinfo(U)` call (through `tp`); `{0,0}` otherwise.
sema_guard_fields_typeinfo_arg := fn(e : ptr(Expr), tp : ptr(SGuardTP), src : ptr(u8)) -> VSpan {
  match deref(e) {
    Expr::Field(inner, ifs, ifl) => { sema_guard_typeinfo_arg_type(inner, tp, src) }
    _ => { VSpan(s = 0, n = 0) }
  }
}
## If `e` is `typeinfo(T).fields.len` / `.variants.len` / `typeinfo(T).n`, the resolved instance type's member
## COUNT; -1 otherwise. Mirrors `lower::guard_field_count`, binding the `Field` base in the top match arm.
## NOTE: this folds only in the two-pass BUILD path (the emit / sema-on-build parse, where `typeinfo(T)` keeps
## its `Call` shape with `T` present). The single-pass `check` SUBCOMMAND parses with an EMPTY enum table, so
## `is_generic_enum_ctor` rewrites the postfix `typeinfo(T).<member>` to `Field(Var(typeinfo), …)` — ERASING
## the `(T)` type-arg — and this fold then admits (-1), which is SAFE (it can only fail to LOCATE, never
## wrongly reject). The size / is-KIND / named-predicate forms are unaffected (they carry no such postfix).
sema_guard_field_count := fn(e : ptr(Expr), tp : ptr(SGuardTP), decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena)) -> i64 {
  match deref(e) {
    Expr::Field(base, fs, fl) => {
      tnm := str_at((src + fs), fl)
      if tnm == "len" {
        rtp := sema_guard_fields_typeinfo_arg(base, tp, src)
        return sema_guard_type_member_count(rtp.s, rtp.n, decls, src)
      }
      if tnm == "n" {
        rtp := sema_guard_typeinfo_arg_type(base, tp, src)
        return sema_guard_type_member_count(rtp.s, rtp.n, decls, src)
      }
      return 0 - 1
    }
    _ => { return 0 - 1 }
  }
}
## The SINGLE trailing bool expr of a candidate NAMED predicate body (a trailing-expr body OR a lone
## `return <expr>`); null otherwise. Byte-mirror of `lower::guard_stmt_ret_expr`/`guard_pred_body_expr`.
sema_guard_stmt_ret_expr := fn(bs : ptr(mut Stmt)) -> ptr(Expr) {
  match deref(stmt_p(Stmt, bs)) {
    Stmt::Return(e, next) => {
      if unchecked bitcast(usize, next) == 0 { return e }
      unchecked bitcast(ptr(Expr), 0)
    }
    _ => { unchecked bitcast(ptr(Expr), 0) }
  }
}
sema_guard_pred_body_expr := fn(bs : ptr(mut Stmt), val : ptr(Expr)) -> ptr(Expr) {
  if unchecked bitcast(usize, bs) == 0 { return val }
  sema_guard_stmt_ret_expr(bs)
}
## Resolve a NAMED-predicate call `[cs,cl)` to the index of the first GENERIC fn declaration whose tail name
## matches (or -1). Mirrors how `sema_when_guard_false_span` resolves the OUTER callee (a first-`is_generic`-
## match scan) — the same faithful-enough resolution the shipped size fold already relies on; the Call arm
## then gates on a `bool` return + single-expr body exactly as `lower::guard_fold_inst` does.
sema_guard_pred_resolve := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) -> i64 {
  mut gi : i64 = 0 - 1
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt and gi < 0 {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and d.is_generic and name_matches(src, d.name_start, d.name_len, cs, cl) { gi = i64(i) }
    i += 1
  }
  gi
}
## INLINE a named comptime-predicate body `be` under a FRESH binding of the predicate's OWN type-params (bound
## positionally to the call args `ah`, each first resolved through the caller instance's `tp`), then recurse
## `sema_guard_fold_inst`. Byte-mirror of `lower::guard_pred_call_fold`; the `SGuardTP` is built as THIS fn's
## OWN top-level local (the lean-lower aggregate-local frame-home rule the lower's helper also observes).
sema_guard_pred_call_fold := fn(be : ptr(Expr), ph : ptr(mut Param), ah : usize, tp : ptr(SGuardTP), decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena)) -> i64 {
  mut i1s := 0
  mut i1l := 0
  mut t1s := 0
  mut t1l := 0
  mut i2s := 0
  mut i2l := 0
  mut t2s := 0
  mut t2l := 0
  mut i3s := 0
  mut i3l := 0
  mut t3s := 0
  mut t3l := 0
  mut pp := ph
  mut ag := ah
  mut slot := 0
  while pp != 0 {
    pm := deref(param_p(pp))
    if str_at((src + pm.ts), pm.tl) == "type" and ag != 0 {
      aa := deref(arg_p(ag))
      av := expr_var_span(aa.e)
      rv := sema_guard_resolve_tp(tp, src, av.s, av.n)
      if slot == 0 { i1s = pm.ns ; i1l = pm.nl ; t1s = rv.s ; t1l = rv.n }
      else if slot == 1 { i2s = pm.ns ; i2l = pm.nl ; t2s = rv.s ; t2l = rv.n }
      else if slot == 2 { i3s = pm.ns ; i3l = pm.nl ; t3s = rv.s ; t3l = rv.n }
      slot += 1
    }
    if ag != 0 { agn := deref(arg_p(ag)) ; ag = agn.next }
    pp = pm.next
  }
  itp := SGuardTP(gp_s = i1s, gp_l = i1l, its = t1s, itl = t1l,
                  gp2_s = i2s, gp2_l = i2l, its2 = t2s, itl2 = t2l,
                  gp3_s = i3s, gp3_l = i3l, its3 = t3s, itl3 = t3l)
  sema_guard_fold_inst(be, ptr(itp), decls, src, a)
}
## Fold a generic-fn `when`-predicate for THIS call's concrete type-args `tp`: 1 = TRUE (admit), 0 = FALSE
## (reject — the instance is as-if-absent), -1 = cannot fold (admit). A FAITHFUL mirror of
## `lower::guard_fold_inst` across ALL its forms: `size(U) <op> N` and `typeinfo(U).fields.len <op> N`
## (RHS an int literal) composed with `and`(40)/`or`(41)/`not`(42); a `match typeinfo(U) { <Kind>(_) => …}`
## is-KIND scrutinee; and a named `fn(type)->bool` predicate CALL (inlined). Recurses on itself. Any form it
## cannot fold, and any type-arg not provably concrete, → -1 (admit). The 0-propagation and every type/size/
## count/kind primitive is byte-identical to the lower's, so sema returns 0 (reject) ONLY when the lower's
## fold also returns 0 → sema never rejects a lower-admitted instance.
sema_guard_fold_inst := fn(cond : ptr(Expr), tp : ptr(SGuardTP), decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena)) -> i64 {
  match deref(cond) {
    Expr::Bin(op, l, r) => {
      if i64(op) == 42 {
        lv := sema_guard_fold_inst(l, tp, decls, src, a)
        if lv == 1 { return 0 }
        if lv == 0 { return 1 }
        return 0 - 1
      }
      if i64(op) == 40 {
        lv := sema_guard_fold_inst(l, tp, decls, src, a)
        if lv == 0 { return 0 }
        rv := sema_guard_fold_inst(r, tp, decls, src, a)
        if rv == 0 { return 0 }
        if lv == 1 and rv == 1 { return 1 }
        return 0 - 1
      }
      if i64(op) == 41 {
        lv := sema_guard_fold_inst(l, tp, decls, src, a)
        if lv == 1 { return 1 }
        rv := sema_guard_fold_inst(r, tp, decls, src, a)
        if rv == 1 { return 1 }
        if lv == 0 and rv == 0 { return 0 }
        return 0 - 1
      }
      lsz := sema_guard_size_operand(l, tp, decls, src, a)
      if lsz >= 0 and expr_is_num_lit(r) {
        return sema_guard_cmp(i64(op), lsz, expr_num_lit_val(r))
      }
      lcnt := sema_guard_field_count(l, tp, decls, src, a)
      if lcnt >= 0 and expr_is_num_lit(r) {
        return sema_guard_cmp(i64(op), lcnt, expr_num_lit_val(r))
      }
      return 0 - 1
    }
    Expr::Call(cs, cl, nargs, ah) => {
      idx := sema_guard_pred_resolve(decls, src, cs, cl)
      if idx < 0 { return 0 - 1 }
      pd := deref(decl_get(decls, usize(idx)))
      if pd.is_fn == false { return 0 - 1 }
      if pd.is_generic == false { return 0 - 1 }
      if str_at((src + pd.ret_ts), pd.ret_tl) == "bool" {
        be := sema_guard_pred_body_expr(pd.body_stmts, pd.value)
        if unchecked bitcast(usize, be) == 0 { return 0 - 1 }
        return sema_guard_pred_call_fold(be, pd.params_head, ah, tp, decls, src, a)
      }
      return 0 - 1
    }
    Expr::Match(scrut, arms_head) => {
      k := sema_guard_typeinfo_kind(scrut, tp, decls, src, a)
      if k < 0 { return 0 - 1 }
      am := deref(arm_p(arms_head))
      if am.vl != 0 {
        want := sema_comptime_kind_of_name(src, am.vs, am.vl)
        if want >= 0 {
          if k == want { return 1 }
          return 0
        }
      }
      return 0 - 1
    }
    _ => { return 0 - 1 }
  }
}
## The source span at which to LOCATE a when-guard reject for a generic call `[cs,cl)` with args `ah`, or
## 0 = ADMIT. Finds the generic callee (first `is_generic` fn matching by tail name); if it carries a
## `when` predicate (`when_cond != 0`) that folds FALSE for this call's concrete type-args, returns the
## call-site span `cs`; else 0. Type-PARAM→type-ARG bindings are collected POSITIONALLY (the arg at a
## `type` param position is a type NAME), up to three (mirroring the lower's instance-slot collection).
sema_when_guard_false_span := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, ah : usize, a : ptr(mut rt::Arena)) -> usize {
  mut gi : i64 = 0 - 1
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt and gi < 0 {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and d.is_generic and name_matches(src, d.name_start, d.name_len, cs, cl) { gi = i64(i) }
    i += 1
  }
  if gi < 0 { return 0 }
  gd := deref(decl_get(decls, usize(gi)))
  if unchecked bitcast(usize, gd.when_cond) == 0 { return 0 }
  mut i1s := 0
  mut i1l := 0
  mut t1s := 0
  mut t1l := 0
  mut i2s := 0
  mut i2l := 0
  mut t2s := 0
  mut t2l := 0
  mut i3s := 0
  mut i3l := 0
  mut t3s := 0
  mut t3l := 0
  mut slot := 0
  mut pp := gd.params_head
  mut ag := ah
  while pp != 0 {
    pm := deref(param_p(pp))
    if str_at((src + pm.ts), pm.tl) == "type" and ag != 0 {
      aa := deref(arg_p(ag))
      av0 := expr_var_span(aa.e)
      mut av := av0
      tv := tuple_typearg_span(aa.e, src)
      if tv.n != 0 { av = VSpan(s = tv.s, n = tv.n) }
      if slot == 0 { i1s = pm.ns ; i1l = pm.nl ; t1s = av.s ; t1l = av.n }
      else if slot == 1 { i2s = pm.ns ; i2l = pm.nl ; t2s = av.s ; t2l = av.n }
      else if slot == 2 { i3s = pm.ns ; i3l = pm.nl ; t3s = av.s ; t3l = av.n }
      slot += 1
    }
    if ag != 0 { agn := deref(arg_p(ag)) ; ag = agn.next }
    pp = pm.next
  }
  tp := SGuardTP(gp_s = i1s, gp_l = i1l, its = t1s, itl = t1l,
                 gp2_s = i2s, gp2_l = i2l, its2 = t2s, itl2 = t2l,
                 gp3_s = i3s, gp3_l = i3l, its3 = t3s, itl3 = t3l)
  if sema_guard_fold_inst(gd.when_cond, ptr(tp), decls, src, a) == 0 { return cs }
  0
}

## A declaration conflicts with an earlier declaration in the same module unless both are
## functions with distinct overload signatures. Module path + spelling define the namespace.
## The anonymous package root is one merged scope with its direct source modules (MOD-12):
## a root binding named `geo` also clashes with the `geo.al` module, even though the parser
## records those declarations with different `Decl.mod` values.
duplicate_root_child_module := fn(d : Decl, prev : Decl, src : ptr(u8)) -> bool {
  if d.name_len == 0 or prev.name_len == 0 { return false }
  if d.mod_len == 7 and str_at((src + d.mod_start), d.mod_len) == "package"
     and prev.mod_len == d.name_len
     and sema_mod_seg_eq(src, prev.mod_start, prev.mod_len, d.name_start, d.name_len) { return true }
  if prev.mod_len == 7 and str_at((src + prev.mod_start), prev.mod_len) == "package"
     and d.mod_len == prev.name_len
     and sema_mod_seg_eq(src, d.mod_start, d.mod_len, prev.name_start, prev.name_len) { return true }
  false
}

duplicate_decl := fn(d : Decl, decls : ptr(rt::Vec), upto : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  ## A LIFTED LAMBDA (FN-6) has the SENTINEL empty name (`name_len == 0`); two lambdas both compare
  ## name-equal (empty == empty) and, when they share an arity, `same_fn_signature` marks the second a
  ## duplicate — a FALSE rejection of a valid program (two 1-arg lambdas in one fn built + ran fine).
  ## A lambda is uniquely identified by its `fn`-offset, never a duplicate — exclude it.
  if d.name_len == 0 { return false }
  ## a FALSE `when`-guarded decl is absent (CT-5) → never a duplicate of anything.
  if guard_is_false(d, src) { return false }
  for i in 0..upto {
    prev := deref(decl_get(decls, i))
    ## a FALSE `when`-guarded EARLIER decl is absent → cannot be the thing `d` duplicates (lets the
    ## TRUE companion `Foo := … when x86_64` coexist with a dropped `Foo := … when aarch64`).
    if not guard_is_false(prev, src) {
      same_name := streq(src, prev.name_start, prev.name_len, d.name_start, d.name_len)
      same_mod := streq(src, prev.mod_start, prev.mod_len, d.mod_start, d.mod_len)
      if same_name and same_mod {
        prev_fn := prev.kind == 1 or prev.kind == 4
        this_fn := d.kind == 1 or d.kind == 4
        if not (prev_fn and this_fn) { return true }
        if same_fn_signature(prev, d, src, a) { return true }
      }
      ## The root's ordinary declarations and its direct child module names occupy one scope.
      ## Restrict the check to package-owned modules so a dependency's private module cannot
      ## collide with an unrelated root spelling in the consuming package.
      if duplicate_root_child_module(d, prev, src) and sema_module_in_package(src, prev.mod_start, prev.mod_len) { return true }
    }
  }
  false
}

## Check a whole program: each decl may reference only earlier decls (a fn additionally sees its
## params + body bindings). The public boundary is deliberately scalar: 0 accepted, 1 rejected.
## Structured errors remain internal until diagnostics rendering consumes them directly; carrying
## a nested generic `Result(_, CheckErr)` across the self-host boundary is not ABI-stable yet.
## Does the statement list contain a COMPTIME construct (`comptime if`/`for`/`match`), directly or
## nested inside an ordinary `if`/`while`/`for`/`loop`/`match` body? Used to enforce the `no_alloc`-style
## `no_comptime` LIMIT (I5/I9, FND-10). Advances via `stmt_next_at` (all-variant), so the detection
## match may use `_` without truncating the walk. Recurses into structured bodies + match arms.
stmts_have_comptime := fn(head : ptr(mut Stmt), a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut result := false
  while cur != 0 and result == false {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::CompIf(c, th, el, n) => { result = true }
      Stmt::CompFor(vs, vl, iv, b, n) => { result = true }
      Stmt::CompForRange(vs, vl, lo, hi, b, n) => { result = true }
      Stmt::CompMatch(sc, ah, n) => { result = true }
      Stmt::If(c, th, el, n) => { if stmts_have_comptime(th, a) { result = true } else if stmts_have_comptime(el, a) { result = true } }
      Stmt::While(c, b, n) => { if stmts_have_comptime(b, a) { result = true } }
      Stmt::For(fns, fnl, lo, hi, b, n) => { if stmts_have_comptime(b, a) { result = true } }
      Stmt::Loop(b, n) => { if stmts_have_comptime(b, a) { result = true } }
      Stmt::Unchecked(b, n) => { if stmts_have_comptime(b, a) { result = true } }
      Stmt::AllocWith(ae, b, n) => { if stmts_have_comptime(b, a) { result = true } }
      Stmt::Match(sc, ah, n) => { if arms_have_comptime(ah, a) { result = true } }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  result
}

## Do any of the match arms' bodies contain a comptime construct? (Helper for `stmts_have_comptime`.)
arms_have_comptime := fn(ah : ptr(mut Arm), a : ptr(mut rt::Arena)) -> bool {
  mut arm := ah
  mut result := false
  while arm != 0 and result == false {
    am := deref(arm_p(arm))
    if stmts_have_comptime(am.body_stmts, a) { result = true }
    arm = am.next
  }
  result
}

## The tail name (after the last `::`) of `[s, s+n)` equals `w`? So a qualified `alloc::allocate`
## matches its bare `allocate` (mirrors `is_builtin_callee`'s tail logic).
name_tail_is := fn(src : ptr(u8), s : usize, n : usize, w : str) -> bool {
  mut tail := s
  mut tn := n
  mut i := 0
  while i + 1 < n {
    if str_at((src + s + i), 2) == "::" { tail = s + i + 2; tn = n - (i + 2) }
    i += 1
  }
  str_at((src + tail), tn) == w
}

## Does the qualified call span `[cs, cs+cl)` start with the source module path `m`? The declaration
## table stores the same path with `::` replaced by `__` (e.g. `std::io` → `std__io`), so the source
## prefix check keeps a bare user function named `print` from being mistaken for the std wrapper.
call_has_module_prefix := fn(src : ptr(u8), cs : usize, cl : usize, m : str) -> bool {
  if cl <= m.len + 2 { return false }
  if str_at((src + cs), m.len) != m { return false }
  str_at((src + cs + m.len), 2) == "::"
}

## Is the qualified call `[cs, cs+cl)` a declaration in `decl_mod`, optionally with the exact tail
## `fn_name`? The module guard is the capability boundary for ambient std wrappers; name matching still
## uses the ordinary tail rule, so the helper accepts the same qualified spelling the lower resolves.
callee_is_module_fn := fn(decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), cs : usize, cl : usize,
                          call_mod : str, decl_mod : str, fn_name : str) -> bool {
  if not call_has_module_prefix(src, cs, cl, call_mod) { return false }
  mut result := false
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    if (d.kind == 1 or d.kind == 4) and str_at((src + d.mod_start), d.mod_len) == decl_mod and name_matches(src, d.name_start, d.name_len, cs, cl) {
      if fn_name.len == 0 or str_at((src + d.name_start), d.name_len) == fn_name { result = true }
    }
  }
  result
}

## Is `e` a direct call to the allocation surface `allocate(…)` (tail-name matched), or to the standard
## OS-backed arena constructor, possibly through `?` (`allocate(…)?`)? Shallow (does NOT descend into
## Bin/args) — used to enforce the `no_alloc` LIMIT. The standard constructor is included here because
## it is the public allocation capability used by codec/library code; its body is trusted as a library
## unit and is therefore not discovered by re-checking the ambient stdlib.
## A SMALL inline `match deref(e)` (dispatches correctly, unlike the big `check_expr` match).
expr_is_alloc_call := fn(e : ptr(Expr), decls : ptr(rt::Vec), cnt : usize, src : ptr(u8)) -> bool {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => {
      name_tail_is(src, cs, cl, "allocate") or callee_is_module_fn(decls, cnt, src, cs, cl, "std::os", "std__os", "arena")
    }
    Expr::Try(inner) => { expr_is_alloc_call(inner, decls, cnt, src) }
    Expr::Unchecked(inner) => { expr_is_alloc_call(inner, decls, cnt, src) }
    _ => { false }
  }
}

## Does the statement list contain a direct allocation capability (for the `no_alloc` LIMIT)? Same shape
## as `stmts_have_comptime` — advance via all-variant `stmt_next_at`, recurse into structured bodies + arms.
## Checks the value expr of Assign/Return/ExprStmt (the common allocation positions); indirect allocation
## through an arbitrary user/library wrapper, or a call nested inside another expression, remains the
## documented first-slice false-negative rather than a wrong-reject. `alloc::with` is itself a runtime
## allocation scope and is therefore forbidden even when its body happens not to allocate immediately.
stmts_have_alloc := fn(head : ptr(mut Stmt), decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut result := false
  while cur != 0 and result == false {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::Assign(ns, nl, v, n) => { if expr_is_alloc_call(v, decls, cnt, src) { result = true } }
      Stmt::Return(rv, n) => { if expr_is_alloc_call(rv, decls, cnt, src) { result = true } }
      Stmt::ExprStmt(e, n) => { if expr_is_alloc_call(e, decls, cnt, src) { result = true } }
      Stmt::If(c, th, el, n) => { if stmts_have_alloc(th, decls, cnt, src, a) { result = true } else if stmts_have_alloc(el, decls, cnt, src, a) { result = true } }
      Stmt::While(c, b, n) => { if stmts_have_alloc(b, decls, cnt, src, a) { result = true } }
      Stmt::For(fns, fnl, lo, hi, b, n) => { if stmts_have_alloc(b, decls, cnt, src, a) { result = true } }
      Stmt::Loop(b, n) => { if stmts_have_alloc(b, decls, cnt, src, a) { result = true } }
      Stmt::Unchecked(b, n) => { if stmts_have_alloc(b, decls, cnt, src, a) { result = true } }
      Stmt::AllocWith(ae, b, n) => { result = true }
      Stmt::Match(sc, ah, n) => { if arms_have_alloc(ah, decls, cnt, src, a) { result = true } }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  result
}

## Do any match arms contain a direct allocation capability? (Helper for `stmts_have_alloc`; checks both a
## statement-match arm's body statements and a value-match arm's body expression.)
arms_have_alloc := fn(ah : ptr(mut Arm), decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  mut arm := ah
  mut result := false
  while arm != 0 and result == false {
    am := deref(arm_p(arm))
    if stmts_have_alloc(am.body_stmts, decls, cnt, src, a) { result = true }
    else if unchecked bitcast(usize, am.body) != 0 and expr_is_alloc_call(am.body, decls, cnt, src) { result = true }
    arm = am.next
  }
  result
}

## Is the callee named `[cs, cs+cl)` a `@abi(syscall)` fn (a kind-4 decl)? Used to enforce the
## `freestanding` LIMIT: a raw syscall is the clearest OS dependence. `name_matches` handles the
## qualified/tail form (`rt::sys_write` ≡ `sys_write`).
callee_is_syscall := fn(decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), cs : usize, cl : usize) -> bool {
  mut r := false
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 4 and name_matches(src, d.name_start, d.name_len, cs, cl) { r = true }
  }
  r
}

## Is the call an OS capability? Raw `@abi(syscall)` remains the general case; the ambient std wrappers
## below are the public OS surfaces whose bodies are trusted and therefore are not re-walked as library
## declarations. The module check is deliberately qualified, so a user `print`/`arena` is unaffected.
callee_is_os_call := fn(decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), cs : usize, cl : usize) -> bool {
  if callee_is_syscall(decls, cnt, src, cs, cl) { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::io", "std__io", "") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::os", "std__os", "") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::process", "std__process", "run") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::time", "std__time", "now_monotonic") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::time", "std__time", "now_realtime") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::thread", "std__thread", "spawn") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::thread", "std__thread", "join") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::sync", "std__sync", "lock") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "std::sync", "std__sync", "unlock") { return true }
  if callee_is_module_fn(decls, cnt, src, cs, cl, "base::process", "base__process", "exit") { return true }
  false
}

## Is `e` a direct call to an OS capability (possibly through `?`)? Shallow (same rationale as
## `expr_is_alloc_call`). For the `freestanding` LIMIT.
expr_calls_syscall := fn(e : ptr(Expr), decls : ptr(rt::Vec), cnt : usize, src : ptr(u8)) -> bool {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => { callee_is_os_call(decls, cnt, src, cs, cl) }
    Expr::Try(inner) => { expr_calls_syscall(inner, decls, cnt, src) }
    Expr::Unchecked(inner) => { expr_calls_syscall(inner, decls, cnt, src) }
    _ => { false }
  }
}

## Does the statement list make a direct syscall (for the `freestanding` LIMIT)? Same walk shape as
## `stmts_have_alloc`. Shallow (direct value-position call); indirect OS use (via a std fn that itself
## syscalls) is a documented first-slice gap (false-negative, never a wrong-reject).
stmts_call_syscall := fn(head : ptr(mut Stmt), decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut result := false
  while cur != 0 and result == false {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::Assign(ns, nl, v, n) => { if expr_calls_syscall(v, decls, cnt, src) { result = true } }
      Stmt::Return(rv, n) => { if expr_calls_syscall(rv, decls, cnt, src) { result = true } }
      Stmt::ExprStmt(e, n) => { if expr_calls_syscall(e, decls, cnt, src) { result = true } }
      Stmt::If(c, th, el, n) => { if stmts_call_syscall(th, decls, cnt, src, a) { result = true } else if stmts_call_syscall(el, decls, cnt, src, a) { result = true } }
      Stmt::While(c, b, n) => { if stmts_call_syscall(b, decls, cnt, src, a) { result = true } }
      Stmt::For(fns, fnl, lo, hi, b, n) => { if stmts_call_syscall(b, decls, cnt, src, a) { result = true } }
      Stmt::Loop(b, n) => { if stmts_call_syscall(b, decls, cnt, src, a) { result = true } }
      Stmt::Unchecked(b, n) => { if stmts_call_syscall(b, decls, cnt, src, a) { result = true } }
      Stmt::AllocWith(ae, b, n) => { if stmts_call_syscall(b, decls, cnt, src, a) { result = true } }
      Stmt::Match(sc, ah, n) => { if arms_call_syscall(ah, decls, cnt, src, a) { result = true } }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  result
}

## Do any match arms make a direct syscall? (Helper for `stmts_call_syscall`.)
arms_call_syscall := fn(ah : ptr(mut Arm), decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  mut arm := ah
  mut result := false
  while arm != 0 and result == false {
    am := deref(arm_p(arm))
    if stmts_call_syscall(am.body_stmts, decls, cnt, src, a) { result = true }
    else if unchecked bitcast(usize, am.body) != 0 and expr_calls_syscall(am.body, decls, cnt, src) { result = true }
    arm = am.next
  }
  result
}

## The parser lowers ordinary unary `-x` to `Unchecked(Bin(17, Num(0, 0, 0), x))` so the lower can
## preserve its established two's-complement arithmetic path. The synthetic zero has no source span;
## a written `0` always carries one. Keep this distinction local to the limits scan: it identifies
## parser syntax, not an explicit verification-mode escape. In particular, `unchecked -x` is nested
## `Unchecked(Unchecked(Bin(...)))` and the outer wrapper remains a real violation. Keep the child
## `Num` test in a helper: the frozen seed has a known miscompile for a nested match on a bound child.
limit_parser_synthetic_zero := fn(e : ptr(Expr)) -> bool {
  mut result := false
  match deref(e) {
    Expr::Num(v, s, n) => { result = v == 0 and s == 0 and n == 0 }
    _ => {}
  }
  result
}
limit_parser_unary_neg_body := fn(inner : ptr(Expr)) -> bool {
  mut result := false
  match deref(inner) {
    Expr::Bin(op, l, r) => {
      if op == 17 {
        result = limit_parser_synthetic_zero(l)
      }
    }
    _ => {}
  }
  result
}

## Does the expression tree contain an `unchecked <expr>` (`Expr::Unchecked`) ANYWHERE? A FULL recursive
## expr walk (mirrors `expr_has_unbound`'s traversal — every `ptr(Expr)` child plus the Call/StructLit/
## EnumLit/ArrayLit arg lists and Match arms). Unlike the shallow `no_alloc`/`freestanding` scans this is
## DEEP: the `no_unchecked` LIMIT (I5/I9, FND-10) promises the TU contains no `unchecked` escape, so a
## nested `a + unchecked b` must not slip past. This walks the EXPRESSION form (`Expr::Unchecked`); the
## SCOPED STATEMENT form `unchecked { … }` (`Stmt::Unchecked`) is caught by
## `stmts_have_unchecked` below — an earlier revision of this comment claimed "`unchecked` is only ever
## an expression … there is no statement block form to handle", which was the whole bug.
expr_has_unchecked := fn(e : ptr(Expr), a : ptr(mut rt::Arena)) -> bool {
  match deref(e) {
    ## The outer wrapper around parser-generated unary `-` is an implementation marker, not source
    ## syntax. Recurse through that one wrapper while retaining the ordinary explicit-escape result.
    Expr::Unchecked(inner) => {
      if limit_parser_unary_neg_body(inner) { expr_has_unchecked(inner, a) } else { true }
    }
    Expr::Bin(op, l, r) => { expr_has_unchecked(l, a) or expr_has_unchecked(r, a) }
    Expr::If(c, t, f) => { expr_has_unchecked(c, a) or expr_has_unchecked(t, a) or expr_has_unchecked(f, a) }
    Expr::Match(scrut, head) => {
      mut bad := expr_has_unchecked(scrut, a)
      mut arm := head
      while arm != 0 and bad == false {
        am := deref(arm_p(arm))
        if unchecked bitcast(usize, am.body) != 0 and expr_has_unchecked(am.body, a) { bad = true }
        arm = am.next
      }
      bad
    }
    Expr::Call(cs, cl, na, ah) => {
      mut bad := false
      mut g := ah
      while g != 0 and bad == false { ga := deref(arg_p(g)); if expr_has_unchecked(ga.e, a) { bad = true }; g = ga.next }
      bad
    }
    Expr::StructLit(ss, sl, nf, fh) => {
      mut bad := false
      mut g := fh
      while g != 0 and bad == false { ga := deref(arg_p(g)); if expr_has_unchecked(ga.e, a) { bad = true }; g = ga.next }
      bad
    }
    Expr::EnumLit(es, el, vs, vl, np, ph) => {
      mut bad := false
      mut g := ph
      while g != 0 and bad == false { ga := deref(arg_p(g)); if expr_has_unchecked(ga.e, a) { bad = true }; g = ga.next }
      bad
    }
    Expr::Field(base, fs, fl) => { expr_has_unchecked(base, a) }
    Expr::AddrOf(p) => { expr_has_unchecked(p, a) }
    Expr::Deref(p) => { expr_has_unchecked(p, a) }
    Expr::ArrayLit(nel, eh) => {
      mut bad := false
      mut g := eh
      while g != 0 and bad == false { ga := deref(arg_p(g)); if expr_has_unchecked(ga.e, a) { bad = true }; g = ga.next }
      bad
    }
    Expr::Index(base, idx) => { expr_has_unchecked(base, a) or expr_has_unchecked(idx, a) }
    Expr::Try(inner) => { expr_has_unchecked(inner, a) }
    Expr::Slice(base, lo, hi) => { expr_has_unchecked(base, a) or expr_has_unchecked(lo, a) or expr_has_unchecked(hi, a) }
    Expr::CompField(base, idx) => { expr_has_unchecked(base, a) or expr_has_unchecked(idx, a) }
    _ => { false }
  }
}

## Does the statement list contain an `unchecked` scope (for the `no_unchecked` LIMIT)? Walk shape as
## `stmts_have_alloc`, but checks the value expr of EVERY store form (Assign/FieldAssign/Deref/Index/
## IndexField/FieldPath) plus conditions/bounds, and recurses ALL structured bodies incl. the comptime
## forms (a `comptime`-unrolled body still lowers runtime code). Deep per-expr via `expr_has_unchecked`.
stmts_have_unchecked := fn(head : ptr(mut Stmt), a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut result := false
  while cur != 0 and result == false {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::Assign(ns, nl, v, n) => { if expr_has_unchecked(v, a) { result = true } }
      Stmt::FieldAssign(os, ol, fs, fl, v, n) => { if expr_has_unchecked(v, a) { result = true } }
      Stmt::Return(rv, n) => { if unchecked bitcast(usize, rv) != 0 and expr_has_unchecked(rv, a) { result = true } }
      Stmt::ExprStmt(e, n) => { if expr_has_unchecked(e, a) { result = true } }
      Stmt::DerefAssign(p, v, n) => { if expr_has_unchecked(p, a) { result = true } else if expr_has_unchecked(v, a) { result = true } }
      Stmt::IndexAssign(b, ix, v, n) => { if expr_has_unchecked(b, a) { result = true } else if expr_has_unchecked(ix, a) { result = true } else if expr_has_unchecked(v, a) { result = true } }
      Stmt::IndexFieldAssign(b, ix, fs, fl, v, n) => { if expr_has_unchecked(b, a) { result = true } else if expr_has_unchecked(ix, a) { result = true } else if expr_has_unchecked(v, a) { result = true } }
      Stmt::FieldPathAssign(pl, v, n) => { if expr_has_unchecked(pl, a) { result = true } else if expr_has_unchecked(v, a) { result = true } }
      Stmt::If(c, th, el, n) => { if expr_has_unchecked(c, a) { result = true } else if stmts_have_unchecked(th, a) { result = true } else if stmts_have_unchecked(el, a) { result = true } }
      Stmt::While(c, b, n) => { if expr_has_unchecked(c, a) { result = true } else if stmts_have_unchecked(b, a) { result = true } }
      Stmt::For(fns, fnl, lo, hi, b, n) => { if expr_has_unchecked(lo, a) { result = true } else if expr_has_unchecked(hi, a) { result = true } else if stmts_have_unchecked(b, a) { result = true } }
      Stmt::Loop(b, n) => { if stmts_have_unchecked(b, a) { result = true } }
      ## The SCOPED STATEMENT form `unchecked { … }` IS the escape — the block itself opts the
      ## enclosed statements out of I11 verification, exactly like the `unchecked <expr>` operator does.
      ## This arm used to only RECURSE into the body, so a `@limits(no_unchecked)` unit was rejected for
      ## `return unchecked (a + b)` but ACCEPTED for `unchecked { r = a + b }` — the unit contract (I5/I9,
      ## FND-10) was escapable by respelling the same opt-out as a block. Flag it unconditionally; the
      ## body needs no walk (a nested `unchecked` inside an `unchecked` block is already a violation).
      Stmt::Unchecked(b, n) => { result = true }
      ## `break <value>` carries an EXPRESSION the scan used to skip entirely, so `break unchecked (a + b)`
      ## slipped past the contract. The value is optional (a bare `break`), hence the null guard — the
      ## same shape `Stmt::Return` uses above.
      Stmt::Break(bv, bd, n) => { if unchecked bitcast(usize, bv) != 0 and expr_has_unchecked(bv, a) { result = true } }
      ## `@alloc(<expr>) { … }` — the ALLOCATOR expression was skipped, only the body was walked.
      Stmt::AllocWith(ae, b, n) => { if expr_has_unchecked(ae, a) { result = true } else if stmts_have_unchecked(b, a) { result = true } }
      Stmt::Match(sc, ah, n) => { if expr_has_unchecked(sc, a) { result = true } else if arms_have_unchecked(ah, a) { result = true } }
      Stmt::CompIf(c, th, el, n) => { if stmts_have_unchecked(th, a) { result = true } else if stmts_have_unchecked(el, a) { result = true } }
      Stmt::CompFor(vs, vl, iv, b, n) => { if stmts_have_unchecked(b, a) { result = true } }
      Stmt::CompMatch(sc, ah, n) => { if arms_have_unchecked(ah, a) { result = true } }
      Stmt::CompForRange(vs, vl, lo, hi, b, n) => { if stmts_have_unchecked(b, a) { result = true } }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  result
}

## Do any match arms contain an `unchecked` scope? (Helper for `stmts_have_unchecked`; checks a
## statement-match arm's body statements and a value-match arm's body expression — mirrors `arms_have_alloc`.)
arms_have_unchecked := fn(ah : ptr(mut Arm), a : ptr(mut rt::Arena)) -> bool {
  mut arm := ah
  mut result := false
  while arm != 0 and result == false {
    am := deref(arm_p(arm))
    if stmts_have_unchecked(am.body_stmts, a) { result = true }
    else if unchecked bitcast(usize, am.body) != 0 and expr_has_unchecked(am.body, a) { result = true }
    arm = am.next
  }
  result
}

## The raw-asm INSTRUCTION-intrinsic names (Assembly §2/§4) admitted as a `Call` under `no_abstractions`
## — the x86_64 first-slice set the lower actually emits (`movq`/`addq`/… + `syscall`/`ret` + the `asm()`
## escape). A cast/conversion (`u64(x)`) or a layout method is deliberately NOT here: a guarded
## conversion is not 1:1 (CG-12 / Assembly §3). (Qualified `x86_64::movq` forms are a follow-up.)
is_asm_instr_name := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  nm := str_at((src + s), n)
  return nm == "movq" or nm == "addq" or nm == "subq" or nm == "andq" or nm == "orq" or nm == "xorq"
    or nm == "shlq" or nm == "shrq" or nm == "sarq" or nm == "imulq" or nm == "negq" or nm == "notq"
    or nm == "syscall" or nm == "ret" or nm == "asm"
}

## Does the expression contain a STRUCTURED ABSTRACTION forbidden under `no_abstractions` (CG-12 /
## Assembly §1.1)? The criterion: a construct is admitted iff it emits exactly the instruction(s) it
## names or nothing (erased). Forbidden are the library value-operators (`Bin`), structured control
## flow (`If`/`Match`), `?` (`Try`), structured data access/construction (`Field`/`Index`/`Slice`/
## `CompField`/`EnumLit`/`StructLit`), the pointer ops (`AddrOf`/`Deref`), and a `Call` to anything but
## a raw instruction intrinsic (its args recursed). Immediates, registers (`Var`), array data, and
## instruction-intrinsic calls are admitted.
expr_has_abstraction := fn(e : ptr(Expr), src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  match deref(e) {
    Expr::Bin(op, l, r) => { true }
    Expr::If(c, t, f) => { true }
    Expr::Match(sc, h) => { true }
    Expr::Try(inner) => { true }
    Expr::Field(b, fs, fl) => { true }
    Expr::Index(b, i) => { true }
    Expr::Slice(b, lo, hi) => { true }
    Expr::CompField(b, i) => { true }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { true }
    Expr::StructLit(ss, sl, nf, fh) => { true }
    Expr::AddrOf(p) => { true }
    Expr::Deref(p) => { true }
    Expr::Call(cs, cl, na, ah) => {
      if not is_asm_instr_name(src, cs, cl) { true }
      else {
        mut bad := false
        mut g := ah
        while g != 0 and bad == false { ga := deref(arg_p(g)); if expr_has_abstraction(ga.e, src, a) { bad = true }; g = ga.next }
        bad
      }
    }
    Expr::Unchecked(inner) => { expr_has_abstraction(inner, src, a) }
    Expr::ArrayLit(nel, eh) => {
      mut bad := false
      mut g := eh
      while g != 0 and bad == false { ga := deref(arg_p(g)); if expr_has_abstraction(ga.e, src, a) { bad = true }; g = ga.next }
      bad
    }
    _ => { false }
  }
}

## Does the statement list use a construct forbidden under `no_abstractions`? Structured stores
## (`FieldAssign`/`IndexAssign`/`IndexFieldAssign`/`FieldPathAssign`/`DerefAssign`) and structured
## control flow (`If`/`While`/`For`/`Loop`/`Match`/`Break`/`Continue`) are forbidden outright; the
## value forms (`Assign`/`Return`/`ExprStmt`) are admitted with their expression checked; comptime
## constructs are erased (permitted) but their bodies still emit runtime code, so they are recursed.
stmts_have_abstraction := fn(head : ptr(mut Stmt), src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  mut cur := head
  mut result := false
  while cur != 0 and result == false {
    s := deref(stmt_p(Stmt, cur))
    match s {
      Stmt::Assign(ns, nl, v, n) => { if expr_has_abstraction(v, src, a) { result = true } }
      Stmt::Return(rv, n) => { if unchecked bitcast(usize, rv) != 0 and expr_has_abstraction(rv, src, a) { result = true } }
      Stmt::ExprStmt(e, n) => { if expr_has_abstraction(e, src, a) { result = true } }
      Stmt::FieldAssign(bns, bnl, fs, fl, v, n) => { result = true }
      Stmt::IndexAssign(b, i, v, n) => { result = true }
      Stmt::IndexFieldAssign(b, i, fs, fl, v, n) => { result = true }
      Stmt::FieldPathAssign(pl, v, n) => { result = true }
      Stmt::DerefAssign(p, v, n) => { result = true }
      Stmt::If(c, th, el, n) => { result = true }
      Stmt::While(c, b, n) => { result = true }
      Stmt::For(fns, fnl, lo, hi, b, n) => { result = true }
      Stmt::Loop(b, n) => { result = true }
      Stmt::Unchecked(b, n) => { result = true }
      Stmt::AllocWith(ae, b, n) => { result = true }
      Stmt::Match(sc, ah, n) => { result = true }
      Stmt::Break(_bv, _bd, n) => { result = true }
      Stmt::Continue(_cd, n) => { result = true }
      Stmt::CompIf(c, th, el, n) => { if stmts_have_abstraction(th, src, a) { result = true } else if stmts_have_abstraction(el, src, a) { result = true } }
      Stmt::CompFor(vs, vl, iv, b, n) => { if stmts_have_abstraction(b, src, a) { result = true } }
      Stmt::CompMatch(sc, ah, n) => { if arms_have_abstraction(ah, src, a) { result = true } }
      Stmt::CompForRange(vs, vl, lo, hi, b, n) => { if stmts_have_abstraction(b, src, a) { result = true } }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  result
}

## Do any (comptime-)match arms use a construct forbidden under `no_abstractions`? (Helper for
## `stmts_have_abstraction` — a `CompMatch` arm's body statements.)
arms_have_abstraction := fn(ah : ptr(mut Arm), src : ptr(u8), a : ptr(mut rt::Arena)) -> bool {
  mut arm := ah
  mut result := false
  while arm != 0 and result == false {
    am := deref(arm_p(arm))
    if stmts_have_abstraction(am.body_stmts, src, a) { result = true }
    else if unchecked bitcast(usize, am.body) != 0 and expr_has_abstraction(am.body, src, a) { result = true }
    arm = am.next
  }
  result
}

## Does the span `[ss, ss+sl)` contain the limit word `w` as a substring? Limit names are not substrings
## of one another (`no_comptime`/`no_alloc`/`no_abstractions`/`freestanding`/`no_unchecked`/`no_opt`), so
## a plain substring match over the `@limits(…)` list span is unambiguous.
span_has_limit := fn(src : ptr(u8), ss : usize, sl : usize, w : str) -> bool {
  wl := w.len
  if wl == 0 or wl > sl { return false }
  mut i := ss
  mut r := false
  last := ss + sl - wl
  while i <= last and r == false {
    if str_at((src + i), wl) == w { r = true }
    i += 1
  }
  r
}

## Does the MODULE `[ms, ms+ml)` declare the LIMIT `w`? A `@limits(a, b, …)` parses to a kind-0 marker
## decl (the LIMITS-MARKER sentinel `arity == 99`; alias-shaped so the lower skips it) whose `ret` span
## covers the WHOLE limit list and whose `mod_*` is its file. Per I9 (locality of the TU contract) a
## limit binds ONLY its own translation unit, so enforcement matches the marker's module against the
## checked decl's module. The `arity == 99` gate separates the marker from an ordinary value/alias decl,
## so the substring scan never false-matches normal code.
module_declares_limit := fn(decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), w : str, ms : usize, ml : usize) -> bool {
  mut r := false
  jce := slim_hi(cnt)
  mut jc := 0
  while jc < jce {
    i := slim_at(cnt, jc)
    jc = jc + 1
    if i < cnt {
      d := deref(decl_get(decls, i))
      if d.kind == 0 and d.arity == 99 and d.ret_tl != 0 and streq(src, d.mod_start, d.mod_len, ms, ml) and span_has_limit(src, d.ret_ts, d.ret_tl, w) { r = true }
    }
  }
  r
}

## The six orthogonal limits (spec FND-10 / aspects-map §0). An `@limits(...)` naming anything else is a
## typo / unknown limit — silently doing nothing violates I3 (nothing hidden), so it is rejected.
is_known_limit := fn(w : str) -> bool {
  w == "no_abstractions" or w == "no_alloc" or w == "freestanding" or w == "no_unchecked" or w == "no_comptime" or w == "no_opt"
}

## Is every identifier in the `@limits(…)` list span `[ss, ss+sl)` a known limit? Splits on separators
## (`,` / space / parens) and checks each name against `is_known_limit`. An unknown name → false (reject).
limits_all_known := fn(src : ptr(u8), ss : usize, sl : usize) -> bool {
  mut i := 0
  mut ok := true
  while i < sl {
    c := str_at((src + ss + i), 1)
    if c == "," or c == " " or c == "(" or c == ")" or c == "\t" {
      i += 1
    } else {
      mut j := i
      while j < sl and str_at((src + ss + j), 1) != "," and str_at((src + ss + j), 1) != " " and str_at((src + ss + j), 1) != "(" and str_at((src + ss + j), 1) != ")" { j += 1 }
      w := str_at((src + ss + i), j - i)
      if not is_known_limit(w) { ok = false }
      i = j
    }
  }
  ok
}

## FND-11 — a manifest-limit-list delimiter byte? (list dual of `limits_all_known`'s split — a limit
## NAME is a maximal run of non-delimiters). Used to tokenize the manifest `limits` ceiling text.
lim_delim := fn(c : str) -> bool {
  return c == "," or c == " " or c == "[" or c == "]" or c == "(" or c == ")" or c == "\t" or c == "\n"
}

## FND-11 — does the ceiling text `[cbase, cbase+clen)` name the limit `name` (whole-word)? The ceiling
## lives in the MANIFEST buffer (a separate str from `src`), so this is a cross-buffer byte compare.
ceiling_has := fn(cbase : usize, clen : usize, name : str) -> bool {
  nbase := unchecked bitcast(usize, name.ptr)
  mut i := 0
  mut found := false
  while i < clen {
    if lim_delim(str_at(cbase + i, 1)) {
      i += 1
    } else {
      mut j := i
      while j < clen and not lim_delim(str_at(cbase + j, 1)) { j += 1 }
      if (j - i) == name.len {
        mut k := 0
        mut eq := true
        while k < name.len { if str_at(cbase + i + k, 1) != str_at(nbase + k, 1) { eq = false } ; k += 1 }
        if eq { found = true }
      }
      i = j
    }
  }
  found
}

## FND-11 (Tooling §2.3) — ENFORCE the manifest `limits` CEILING package-wide: every user fn is
## restricted by each limit the ceiling names, regardless of its module's own `@limits` (a module with
## NO `@limits` inherits the ceiling; one WITH `@limits` was validated ⊇ ceiling upstream, so enforcing
## the ceiling limits on it is idempotent). This is the enforcement dual of the per-file `@limits` loop
## in `check_program`, reached from the BUILD path (which does not run `check_program`) with the ceiling
## from the manifest. Returns a `CheckErr`-encoded reject (located at the offending fn name) or 0.
## DORMANT on an empty ceiling → returns 0 at once → fixpoint-neutral (the self-host build has none).
pub enforce_ceiling := fn(decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena), ceiling : str) -> usize {
  if ceiling.len == 0 { return 0 }
  cnt := rt::vec_len(deref(decls))
  cbase := unchecked bitcast(usize, ceiling.ptr)
  for i in 0..cnt {
    dl := deref(decl_get(decls, i))
    if is_lib_module(src, dl.mod_start, dl.mod_len) { }
    else if dl.kind == 1 {
      if ceiling_has(cbase, ceiling.len, "no_comptime") and stmts_have_comptime(dl.body_stmts, a) { return limit_err(dl.name_start, 1) }
      if ceiling_has(cbase, ceiling.len, "no_alloc") and (stmts_have_alloc(dl.body_stmts, decls, cnt, src, a) or (unchecked bitcast(usize, dl.value) != 0 and expr_is_alloc_call(dl.value, decls, cnt, src))) { return limit_err(dl.name_start, 2) }
      if ceiling_has(cbase, ceiling.len, "freestanding") and (stmts_call_syscall(dl.body_stmts, decls, cnt, src, a) or (unchecked bitcast(usize, dl.value) != 0 and expr_calls_syscall(dl.value, decls, cnt, src))) { return limit_err(dl.name_start, 3) }
      ## A function's trailing expression is stored in Decl.value, separately from body_stmts. This is
      ## especially important for generic definitions: the limit contract is checked on the definition
      ## before monomorphization, so a prohibited escape/abstraction cannot hide in a never-yet-instantiated
      ## `fn(T : type, …) -> R { expr }` tail. The sentinel Num(-1) used for statement-only bodies is
      ## harmless to both deep expression walkers.
      if ceiling_has(cbase, ceiling.len, "no_unchecked") and (stmts_have_unchecked(dl.body_stmts, a) or (unchecked bitcast(usize, dl.value) != 0 and expr_has_unchecked(dl.value, a))) { return limit_err(dl.name_start, 4) }
      if ceiling_has(cbase, ceiling.len, "no_abstractions") and (stmts_have_abstraction(dl.body_stmts, src, a) or (unchecked bitcast(usize, dl.value) != 0 and expr_has_abstraction(dl.value, src, a))) { return limit_err(dl.name_start, 5) }
    }
  }
  0
}

## A source span `[s, s+n)` — sema-local (kept off `lower_ctx::CSpan` so this pass carries no
## cross-module type dependency).
ESpan := struct { s : usize, n : usize }

## The EXACT `@export("name")` symbol span attached to `[name_s, name_s+name_l)` (Modules §6.3),
## or 0/0. The parser discards attributes, so check must mirror lower's recovery for both declaration
## prefixes and value-position `name := [attributes] fn(…)`; otherwise duplicate exports pass silently.
export_name := fn(src : ptr(u8), name_s : usize, name_l : usize) -> ESpan {
  mut v := name_s + name_l
  while str_at((src + v), 1) == " " or str_at((src + v), 1) == "\n" or str_at((src + v), 1) == "\t" or str_at((src + v), 1) == "\r" { v = v + 1 }
  if str_at((src + v), 2) == ":=" {
    v = v + 2
    mut attrs := true
    while attrs {
      while str_at((src + v), 1) == " " or str_at((src + v), 1) == "\n" or str_at((src + v), 1) == "\t" or str_at((src + v), 1) == "\r" { v = v + 1 }
      if str_at((src + v), 1) != "@" { attrs = false }
      else {
        if str_at((src + v), 7) == "@export" {
          c := str_at((src + v + 7), 1)
          if c == "(" or c == " " or c == "\n" or c == "\t" or c == "\r" {
            mut q := v + 7
            while str_at((src + q), 1) == " " or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t" or str_at((src + q), 1) == "\r" { q = q + 1 }
            if str_at((src + q), 1) == "(" {
              q = q + 1
              while str_at((src + q), 1) == " " or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t" or str_at((src + q), 1) == "\r" { q = q + 1 }
              if str_at((src + q), 1) == "\"" {
                es := q + 1
                mut ee := es
                while str_at((src + ee), 1) != "\"" { ee = ee + 1 }
                return ESpan(s = es, n = ee - es)
              }
            }
          }
        }
        v = v + 1
        while (str_at((src + v), 1) >= "a" and str_at((src + v), 1) <= "z") or (str_at((src + v), 1) >= "A" and str_at((src + v), 1) <= "Z") or (str_at((src + v), 1) >= "0" and str_at((src + v), 1) <= "9") or str_at((src + v), 1) == "_" { v = v + 1 }
        if str_at((src + v), 1) == "(" {
          mut depth := 1
          v = v + 1
          while depth > 0 {
            c := str_at((src + v), 1)
            if c == "\"" {
              v = v + 1
              while str_at((src + v), 1) != "\"" { v = v + 1 }
              v = v + 1
            } else if c == "(" { depth = depth + 1; v = v + 1 }
            else if c == ")" { depth = depth - 1; v = v + 1 }
            else { v = v + 1 }
          }
        }
      }
    }
  }
  mut p := name_s
  mut scanning := true
  while scanning {
    while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
    if p >= 3 and str_at((src + p - 3), 3) == "mut" { p = p - 3 }
    else if p >= 3 and str_at((src + p - 3), 3) == "pub" { p = p - 3 }
    else if p >= 7 and str_at((src + p - 7), 7) == "@inline" { p = p - 7 }
    else { scanning = false }
  }
  while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
  if p < 11 { return ESpan(s = 0, n = 0) }
  if str_at((src + p - 1), 1) != ")" { return ESpan(s = 0, n = 0) }
  clq := p - 2
  if str_at((src + clq), 1) != "\"" { return ESpan(s = 0, n = 0) }
  mut oq := clq
  while oq > 0 and str_at((src + oq - 1), 1) != "\"" { oq = oq - 1 }
  if oq == 0 { return ESpan(s = 0, n = 0) }
  opq := oq - 1
  if opq < 8 { return ESpan(s = 0, n = 0) }
  if str_at((src + opq - 8), 9) != "@export(\"" { return ESpan(s = 0, n = 0) }
  ESpan(s = oq, n = clq - oq)
}

## FND-10 declared `@limits` enforcement, shared by `check` and by the BUILD path. This deliberately
## does NOT run the whole type-checker; build must reject limit-contract violations before lower/emission,
## but the self-host tree still has check-only gaps unrelated to the limits contract.
pub enforce_declared_limits := fn(decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena)) -> usize {
  cnt := rt::vec_len(deref(decls))
  ## Reject an `@limits(…)` naming an UNKNOWN limit (a typo silently doing nothing = an I3 violation). The
  ## marker is a kind-0 / arity-99 decl whose `ret` span is the limit list; validate each name (FND-10).
  for i in 0..cnt {
    dm := deref(decl_get(decls, i))
    if dm.kind == 0 and dm.arity == 99 and dm.ret_tl != 0 and not is_lib_module(src, dm.mod_start, dm.mod_len) and not limits_all_known(src, dm.ret_ts, dm.ret_tl) { return limit_err(dm.ret_ts, 0) }
  }
  ## §6.6 LINKER-SYMBOL UNIQUENESS: two `@export("foo")` (or `@export` colliding on the same exact
  ## name) MUST be a compile error — the assembler would also reject the duplicate symbol, but a
  ## LOCATED source diagnostic (§1 item 6) is clearer than a `.s`-line clash. Only user decls carry
  ## `@export`; the inner loop runs solely for a decl that IS exported, so a program with no `@export`
  ## (the whole self-host tree) never enters it → O(n) + fixpoint-neutral. Reject at the later decl.
  for i in 0..cnt {
    di := deref(decl_get(decls, i))
    if is_lib_module(src, di.mod_start, di.mod_len) { }
    else {
      ei := export_name(src, di.name_start, di.name_len)
      if ei.n != 0 {
        for j in 0..i {
          dj := deref(decl_get(decls, j))
          if is_lib_module(src, dj.mod_start, dj.mod_len) { }
          else {
            ej := export_name(src, dj.name_start, dj.name_len)
            ## reuse the DUPLICATE-NAME kind (3): two declarations exporting the same exact symbol are a
            ## name collision at the linker level — located at the later decl (§1 item 6).
            if ej.n != 0 and streq(src, ei.s, ei.n, ej.s, ej.n) { return 3 + di.name_start * 4 }
          }
        }
      }
    }
  }
  ## LIMITS enforcement (I5/I9, FND-10) — PER-FILE (I9 locality of the TU contract): each fn is checked
  ## against the limits its OWN module declares (`module_declares_limit` matches the `@limits` marker's
  ## module). `no_comptime` → no `comptime if`/`for`/`match`; `no_alloc` → no `allocate(…)` call. Reject
  ## located at the fn name. Lib modules exempt. Additive: a module with no `@limits` is never restricted
  ## (the `and` short-circuits before the body walk). A `@limits(no_comptime)` in file A does NOT restrict
  ## file B.
  for i in 0..cnt {
    dl := deref(decl_get(decls, i))
    if is_lib_module(src, dl.mod_start, dl.mod_len) { }
    else if dl.kind == 1 {
      if module_declares_limit(decls, cnt, src, "no_comptime", dl.mod_start, dl.mod_len) and stmts_have_comptime(dl.body_stmts, a) { return limit_err(dl.name_start, 1) }
      if module_declares_limit(decls, cnt, src, "no_alloc", dl.mod_start, dl.mod_len) and (stmts_have_alloc(dl.body_stmts, decls, cnt, src, a) or (unchecked bitcast(usize, dl.value) != 0 and expr_is_alloc_call(dl.value, decls, cnt, src))) { return limit_err(dl.name_start, 2) }
      if module_declares_limit(decls, cnt, src, "freestanding", dl.mod_start, dl.mod_len) and (stmts_call_syscall(dl.body_stmts, decls, cnt, src, a) or (unchecked bitcast(usize, dl.value) != 0 and expr_calls_syscall(dl.value, decls, cnt, src))) { return limit_err(dl.name_start, 3) }
      ## Decl.value is the separate trailing-expression slot of a function Decl (the generic AST uses the
      ## same representation). Scan it here as well as the statement list so the declared file contract
      ## is enforced before generic instantiation and before any lowerer rewrites the body.
      if module_declares_limit(decls, cnt, src, "no_unchecked", dl.mod_start, dl.mod_len) and (stmts_have_unchecked(dl.body_stmts, a) or (unchecked bitcast(usize, dl.value) != 0 and expr_has_unchecked(dl.value, a))) { return limit_err(dl.name_start, 4) }
      if module_declares_limit(decls, cnt, src, "no_abstractions", dl.mod_start, dl.mod_len) and (stmts_have_abstraction(dl.body_stmts, src, a) or (unchecked bitcast(usize, dl.value) != 0 and expr_has_abstraction(dl.value, src, a))) { return limit_err(dl.name_start, 5) }
    }
  }
  0
}

## ── Declarations §2.3 — an UNKNOWN `@name` is a Semantic diagnostic, not a silent no-op ──────────
##
## The parser's declaration-prefix loop recognizes the attributes it can act on and falls through to
## `pc.idx = pc.idx + 2` for everything else — it CONSUMES the `@` + ident and drops them. So
## `@bogusattr X := 42` compiled clean, and a typo'd `@pcked` / `@inlien` / `@expost` declared a
## property that was then replaced by NO property at all, without a word. Declarations §2.3 is
## explicit: "An unknown `@name`, or one applied to a target kind not listed for it, is a Semantic
## diagnostic that names the family".
##
## This belongs in SEMA and not in the parser. The library attribute set is OPEN: §2.3 closes only
## the layout machine levers (`@repr`…`@niche`, CT-10) and says "other `@name` are comptime-function
## effectors (prelude or library, indistinguishable)". A closed known-list in the parser would turn
## away every user-defined effector; the judgement has to run against the RESOLVED DECLARATION SET,
## which only sema has.
##
## The attribute TEXT is still in `src` (the parser only advanced past the tokens), so the chain is
## recovered by the same BACKWARD SOURCE SCAN `lower_layout::_decl_prefix_attr` uses for
## `@packed`/`@repr` — here ENUMERATING the chain instead of searching it for one name.

## Is source byte `src[i]` ASCII whitespace? (local twin of `lower_layout::_ws1`, which is private.)
_sws1 := fn(src : ptr(u8), i : usize) -> bool {
  w := str_at((src + i), 1)
  w == " " or w == "\n" or w == "\t" or w == "\r"
}
## Is source byte `src[i]` an ident byte (letter / digit / `_`)? Wider than `lower_layout::_alpha1`
## on purpose: a user-defined effector may be named `my_attr2`, and reading its FULL name is what
## lets the decl-set lookup below recognize it instead of mis-splitting it into an unknown tail.
_sident1 := fn(src : ptr(u8), i : usize) -> bool {
  c := bytes(str_at((src + i), 1))[0]
  (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 95
}
## Is source offset `i` inside a `##` COMMENT? The backward walker reads RAW SOURCE, and `src/` is
## full of prose naming attributes in backticks (`@ident`, `@attr`, `@progbits`); a comment link is
## not a declaration prefix, so finding one ENDS the walk rather than being judged. Without this the
## scan would reject real declarations for text written about them.
_sin_comment := fn(src : ptr(u8), i : usize) -> bool {
  mut p := i
  while p > 0 {
    p = p - 1
    c := str_at((src + p), 1)
    if c == "\n" { return false }
    if c == "#" { return true }
  }
  false
}

## The v1 attribute families of Declarations §2.3, verbatim from its table — storage / layout /
## contract / abi / codegen / linkage / build / control / test. This is the BUILT-IN half of the
## answer only: a name absent from here is still accepted when it names a declaration (below).
sema_attr_builtin := fn(w : str) -> bool {
  if w == "reg" or w == "stack" or w == "static" or w == "scoped" or w == "section" or w == "alloc" { return true }
  if w == "repr" or w == "align" or w == "packed" or w == "offset" or w == "endian" or w == "niche" { return true }
  if w == "require" or w == "owning" or w == "convert" { return true }
  if w == "abi" or w == "inline" or w == "extern" or w == "export" { return true }
  if w == "limits" or w == "label" or w == "test" { return true }
  false
}

## The source offset of the first UNKNOWN `@name` in the DECLARATION-PREFIX chain of the declaration
## whose name starts at `ns` — 0 when the chain is empty or every link resolves.
##
## Walking BACKWARD from the name, each turn either steps over one fixed role-axis modifier
## (Grammar §3.2 `modifier ::= "pub" | "mut" | "comptime" | attribute`, in any order — the parser's
## own prefix loop accepts them interleaved) or over one `@ident` / `@ident(args)` link. The FIRST
## token that is neither ends the walk, so a preceding declaration's tail (`}`, `)`, a bare ident, a
## comment) is never read as this declaration's prefix.
##
## A link is judged UNKNOWN only when BOTH sources of truth say nothing about it: it is not a §2.3
## built-in family member, and no declaration in the program carries that name. The second half is
## deliberately liberal — ANY declaration, not just a comptime function — because CT-10 makes a
## library effector indistinguishable from a prelude one and the cost of a false reject here is a
## legal program turned away. Everything the walk cannot classify stays ACCEPTED.
sema_unknown_prefix_attr := fn(decls : ptr(rt::Vec), cnt : usize, src : ptr(u8), ns : usize) -> usize {
  if ns == 0 { return 0 }
  mut bad := 0
  mut p := ns - 1
  mut go := true
  while go {
    while p > 0 and _sws1(src, p) { p = p - 1 }
    if p == 0 { go = false }
    else {
      mut ate := false
      ## a fixed role-axis modifier between the attribute chain and the name
      if p >= 2 and str_at((src + (p - 2)), 3) == "pub" { if p < 3 { go = false } else { p = p - 3 ; ate = true } }
      else if p >= 2 and str_at((src + (p - 2)), 3) == "mut" { if p < 3 { go = false } else { p = p - 3 ; ate = true } }
      else if p >= 7 and str_at((src + (p - 7)), 8) == "comptime" { if p < 8 { go = false } else { p = p - 8 ; ate = true } }
      if go and not ate {
        mut e := p
        ## an optional argument list `( … )` — walk back to its `(`
        if str_at((src + e), 1) == ")" {
          while e > 0 and str_at((src + e), 1) != "(" { e = e - 1 }
          if str_at((src + e), 1) != "(" { return bad }
          if e == 0 { return bad }
          e = e - 1
          while e > 0 and _sws1(src, e) { e = e - 1 }
        }
        if _sident1(src, e) == false { go = false }
        else {
          mut b := e
          while b > 0 and _sident1(src, b) { b = b - 1 }
          mut istart := b
          if _sident1(src, b) == false { istart = b + 1 }
          ilen := (e - istart) + 1
          if istart == 0 { go = false }
          else if str_at((src + (istart - 1)), 1) != "@" { go = false }
          else if _sin_comment(src, istart) { go = false }
          else {
            if sema_attr_builtin(str_at((src + istart), ilen)) { }
            else if declared(decls, cnt, src, istart, ilen) { }
            else { bad = istart }
            if istart < 2 { go = false } else { p = istart - 2 }
          }
        }
      }
    }
  }
  bad
}

## §8 `@repr(T)` LOCATED reject (spec Types §8) — a FAITHFUL sema mirror of `lower::validate_repr`
## (driver build path, currently a bare unlocated `panic`; `check` did not run it at all). An enum
## carrying `@repr(T)` must have T an INTEGER type (`uN`/`iN`/`usize`/`bitsN`) wide enough to encode
## every discriminant (0..variant_count-1); otherwise the spec mandates a compile diagnostic. This
## classifies the tag via the SAME `lower_layout` primitives `validate_repr` uses — `enum_repr_ty`
## (span extraction), `repr_ty_is_integer`, `repr_ty_capacity` — and counts variants by walking the SAME
## `fields_head` list, so sema rejects EXACTLY the enums the build's `validate_repr` panics on (never a
## lower-admitted enum). Returns a `CheckErr` LOCATED at the enum's name (kind 0 → "invalid at line N"),
## or 0 when the enum has no `@repr` or its tag is valid. Neutral for the self-host build: no `@repr` in
## `src/`+`lib/` → `enum_repr_ty` returns an empty span for every enum → always 0.
sema_repr_reject := fn(d : Decl, decls : ptr(rt::Vec), src : ptr(u8)) -> usize {
  if d.kind != 3 { return 0 }
  rsp := enum_repr_ty(decls, src, d.name_start, d.name_len)
  if rsp.n == 0 { return 0 }
  if repr_ty_is_integer(src, rsp.s, rsp.n) == false { return located_err(d.name_start) }
  mut f := d.fields_head
  mut vc := 0
  while f != 0 { fd := deref(fld_p(f)); vc = vc + 1; f = fd.next }
  cap := repr_ty_capacity(src, rsp.s, rsp.n)
  if cap != 0 and vc > cap { return located_err(d.name_start) }
  0
}

## PROPOSAL 7 / Types §7 — the parser's parameter path records `[T]` and `[T; N]` as the same
## `pmode == 1` aggregate shape. The lower currently treats that shape as a fixed-array address, while
## the specification defines `[T]` as a `{ptr, len}` slice. Locate the closing bracket from source and
## distinguish the two spellings here, in sema, before any backend can observe the ambiguous AST. A
## semicolon at the outer bracket level is the fixed-array form; no semicolon is the slice sugar form.
sema_slice_sugar_at := fn(src : ptr(u8), open : usize) -> bool {
  if str_at((src + open), 1) != "[" { return false }
  mut depth := 0
  mut saw_semi := false
  mut p := open
  mut steps := 0
  while steps < 1024 {
    c := str_at((src + p), 1)
    if c == "[" { depth += 1 }
    else if c == ";" and depth == 1 { saw_semi = true }
    else if c == "]" {
      if depth == 1 { return not saw_semi }
      if depth > 1 { depth -= 1 }
    }
    p += 1
    steps += 1
  }
  false
}

## The parser stores an ARRAY parameter's element span (`pm.ts`/`pm.tl`), not its opening `[`. Recover
## that opening delimiter by walking over source whitespace. `pmode == 1` is required by the caller, so
## a preceding `[` is the parameter's own array delimiter rather than an unrelated expression bracket.
sema_param_array_open := fn(src : ptr(u8), ts : usize) -> usize {
  mut p := ts
  while p > 0 and _sws1(src, p - 1) { p -= 1 }
  if p > 0 and str_at((src + (p - 1)), 1) == "[" { return p - 1 }
  0
}

## Return the first source location of an unsupported `[T]` parameter/return annotation. A zero offset
## cannot be encoded as a located CheckErr, so malformed/edge source spans fall back to the declaration
## name; valid user declarations normally place the bracket at a nonzero offset.
sema_slice_sugar_reject := fn(d : Decl, src : ptr(u8)) -> usize {
  if d.kind != 1 { return 0 }
  mut pp := d.params_head
  while pp != 0 {
    pm := deref(param_p(pp))
    if pm.pmode == 1 {
      open := sema_param_array_open(src, pm.ts)
      if open != 0 and sema_slice_sugar_at(src, open) { return located_err(open) }
      if open == 0 and sema_slice_sugar_at(src, pm.ts) { return located_err(d.name_start) }
    }
    pp = pm.next
  }
  if d.ret_tl != 0 and sema_slice_sugar_at(src, d.ret_ts) {
    if d.ret_ts != 0 { return located_err(d.ret_ts) }
    return located_err(d.name_start)
  }
  0
}

## Issue #11, bounded Slice 3a — the ordinary type checker is poison-tolerant for an unresolved
## annotation, which is correct inside expressions but unsafe at a function boundary: lower then
## treats an unknown nominal type as a scalar and may emit an ABI/layout that never existed. The
## parser stores only the HEAD of multi-token annotations (`ptr`, `fn`, `Box`, …), so this validator
## deliberately handles ONLY a single bare identifier. Generic/qualified/pointer/function forms keep
## their existing validators; a `T : type` parameter is an abstract type, not an unknown name.
sema_fn_type_param_name := fn(d : Decl, src : ptr(u8), s : usize, n : usize) -> bool {
  mut pp := d.params_head
  while pp != 0 {
    pm := deref(param_p(pp))
    if str_at((src + pm.ts), pm.tl) == "type" and streq(src, pm.ns, pm.nl, s, n) { return true }
    pp = pm.next
  }
  false
}

## A plain type alias such as CheckErr := usize is recorded as a kind-0 decl with alias_ts/alias_tl,
## but lower_layout::type_name_known intentionally answers only built-ins and aggregate aliases. Keep
## this signature fence from mistaking a declared scalar/qualified alias for an unresolved nominal name,
## while still refusing an ordinary value binding whose RHS merely happens to be an identifier.
sema_type_alias_known := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 0 and d.alias_tl != 0 and streq(src, d.name_start, d.name_len, s, n) {
      rhs := base_type_name(src, d.alias_ts, d.alias_tl)
      if type_name_known(decls, src, rhs.s, rhs.n) { return true }
      if qualified_type_name_known(decls, src, rhs.s, rhs.n) { return true }
      w := str_at((src + rhs.s), rhs.n)
      if w == "ptr" or w == "fn" or w == "bits8" or w == "bits16" or w == "bits32" or w == "bits64" { return true }
      if brand_underlying(decls, src, rhs.s, rhs.n).n != 0 { return true }
    }
    i += 1
  }
  false
}

sema_signature_type_head_unknown := fn(d : Decl, decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> usize {
  if n == 0 or not _sident1(src, s) { return 0 }
  mut i := 1
  while i < n {
    if not _sident1(src, s + i) { return 0 }
    i += 1
  }
  ## `type` is the meta-type annotation of a generic function's compile-time parameter and type
  ## functions' result annotation; it is intentionally not a nominal type name.
  if str_at((src + s), n) == "type" { return 0 }
  ## A parser-recorded tail of `mod::Type` has the separator immediately before it; a complete
  ## qualified return span is caught by the same splitter. Visibility/identity remains separate.
  if sema_gref_split(src, s, n).qual { return 0 }
  if sema_fn_type_param_name(d, src, s, n) { return 0 }
  ## The parser keeps only the head for `ptr(T)`, `fn(...) -> R`, and generic constructors. Do not
  ## turn those multi-token forms into a bare-name decision merely because their head is unresolved.
  mut p := s + n
  while _sws1(src, p) { p += 1 }
  if str_at((src + p), 1) == "(" { return 0 }
  if type_name_known(decls, src, s, n) { return 0 }
  ## The layout scalar table also admits the bitsN representation family, while the generic
  ## type-name helper intentionally predates that family. Nominal brands are likewise represented
  ## exactly like their underlying scalar and remain an established deferred sema type.
  w := str_at((src + s), n)
  if w == "bits8" or w == "bits16" or w == "bits32" or w == "bits64" { return 0 }
  if brand_underlying(decls, src, s, n).n != 0 { return 0 }
  if sema_type_alias_known(decls, src, s, n) { return 0 }
  located_err(s)
}

sema_signature_type_reject := fn(d : Decl, decls : ptr(rt::Vec), src : ptr(u8)) -> usize {
  if d.is_fn == false { return 0 }
  mut pp := d.params_head
  while pp != 0 {
    pm := deref(param_p(pp))
    r0 := sema_signature_type_head_unknown(d, decls, src, pm.ts, pm.tl)
    if r0 != 0 { return r0 }
    pp = pm.next
  }
  if d.ret_tl != 0 {
    r1 := sema_signature_type_head_unknown(d, decls, src, d.ret_ts, d.ret_tl)
    if r1 != 0 { return r1 }
  }
  0
}

## Validate only the newly supported surface: module-qualified arguments of a generic type appearing
## in a function parameter or result annotation. The parser stores the generic head span and leaves
## `(args...)` in source; `typearg_at` recovers each top-level argument without widening the AST.
## Bare args and all other unsupported forms retain their existing behavior. A qualified argument
## must resolve to the named module's concrete struct/enum/union declaration; otherwise reject at the
## argument itself instead of silently assigning scalar layout to an unknown type.
type_span_has_path_sep := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  mut i := 0
  while i + 1 < n {
    if str_at((src + s + i), 2) == "::" { return true }
    i += 1
  }
  false
}

qualified_generic_span_reject := fn(decls : ptr(rt::Vec), src : ptr(u8), hs : usize, hn : usize) -> usize {
  ## `ptr(mut rt::Arena)` also has a head followed by parentheses, but it is a type constructor,
  ## not a user generic declaration. Restrict this validator to parser-recorded generic aggregate
  ## declarations (`Result`/`Option`/user generic structs/enums), leaving pointer/function syntax to
  ## its existing validators.
  mut generic_head := false
  cnt := rt::vec_len(deref(decls))
  mut di := 0
  while di < cnt {
    gd := deref(decl_get(decls, di))
    if (gd.kind == 2 or gd.kind == 3) and gd.is_generic
       and streq(src, gd.name_start, gd.name_len, hs, hn) { generic_head = true }
    di += 1
  }
  if generic_head == false { return 0 }
  mut i := 0
  mut scanning := true
  while scanning and i < 16 {
    ta := typearg_at(src, hs, hn, i)
    if ta.n == 0 { scanning = false }
    else {
      if type_span_has_path_sep(src, ta.s, ta.n) and not qualified_type_name_known(decls, src, ta.s, ta.n) {
        return located_err(ta.s)
      }
      i += 1
    }
  }
  0
}

sema_qualified_generic_reject := fn(d : Decl, decls : ptr(rt::Vec), src : ptr(u8)) -> usize {
  if d.kind != 1 { return 0 }
  mut pp := d.params_head
  while pp != 0 {
    pm := deref(param_p(pp))
    r := qualified_generic_span_reject(decls, src, pm.ts, pm.tl)
    if r != 0 { return r }
    pp = pm.next
  }
  if d.ret_tl != 0 { return qualified_generic_span_reject(decls, src, d.ret_ts, d.ret_tl) }
  0
}

## ── MODULES §3 CHECK/PARITY ──────────────────────────────────────────────────────────────────────
## The lower already has this predicate for the build-only visibility pass.  The checker cannot call
## lower (that would make a cycle), so this is the sema-side, located-return twin.  It deliberately
## shares the lower's source representation: declaration modules are `__`-joined spans, while a
## source path uses `::`; both are the same module identity.
sema_mod_seg_eq := fn(src : ptr(u8), as_ : usize, al : usize, bs : usize, bl : usize) -> bool {
  if al != bl { return false }
  mut i := 0
  mut ok := true
  while i < al {
    ca := str_at((src + as_ + i), 1)
    cb := str_at((src + bs + i), 1)
    if ca != cb {
      sepa := ca == ":" or ca == "_"
      sepb := cb == ":" or cb == "_"
      if not (sepa and sepb) { ok = false }
    }
    i += 1
  }
  ok
}

## `package.al` is the anonymous package-root module.  The driver publishes that fact only to lower;
## sema sees the same module stem in every Decl, so keep the root rule local and explicit here.
sema_is_root_mod := fn(src : ptr(u8), ms : usize, ml : usize) -> bool {
  ml == 7 and str_at((src + ms), ml) == "package"
}

## A root declaration is private to its own package tree.  The anonymous module name alone cannot
## express that boundary because dependency modules are checked in the same Decl Vec, so the driver
## publishes the current package's owned module-name spans before the sema pass.
mut SEMA_PACKAGE_MODULES_P : usize = 0
mut SEMA_PACKAGE_MODULES_N : usize = 0
pub set_package_modules := fn(p : usize, n : usize) -> i64 {
  SEMA_PACKAGE_MODULES_P = p
  SEMA_PACKAGE_MODULES_N = n
  0
}

sema_module_in_package := fn(src : ptr(u8), ms : usize, ml : usize) -> bool {
  if SEMA_PACKAGE_MODULES_N == 0 { return false }
  mods := unchecked bitcast(ptr(rt::Vec), SEMA_PACKAGE_MODULES_P)
  mut i := 0
  while i + 1 < rt::vec_len(deref(mods)) {
    ns := rt::vec_get(deref(mods), i)
    nl := rt::vec_get(deref(mods), i + 1)
    if sema_mod_seg_eq(src, ms, ml, ns, nl) { return true }
    i += 2
  }
  false
}

## Rank a declaration module against the module that spells a reference.  A non-negative rank means
## the declaration is on the caller's own/ancestor chain and is therefore visible even when private.
sema_mod_anc_rank := fn(src : ptr(u8), ms : usize, ml : usize, cs : usize, cl : usize) -> i64 {
  if ml == cl and sema_mod_seg_eq(src, ms, ml, cs, cl) { return i64(ml) }
  if sema_is_root_mod(src, ms, ml) {
    if SEMA_PACKAGE_MODULES_N == 0 or sema_module_in_package(src, cs, cl) { return 0 }
    return -1
  }
  if ml == 0 { return -1 }
  if ml + 2 >= cl { return -1 }
  sep := str_at((src + cs + ml), 2)
  if sep != "__" and sep != "::" { return -1 }
  if sema_mod_seg_eq(src, ms, ml, cs, ml) == false { return -1 }
  i64(ml)
}

sema_decl_visible_from := fn(src : ptr(u8), d : Decl, cs : usize, cl : usize) -> bool {
  if sema_mod_anc_rank(src, d.mod_start, d.mod_len, cs, cl) >= 0 { return true }
  decl_is_pub(src, d.name_start)
}

sema_colon_pos := fn(src : ptr(u8), cs : usize, cl : usize) -> i64 {
  mut r := -1
  mut i := 0
  while i + 1 < cl {
    if str_at((src + cs + i), 2) == "::" { r = i64(i); i += 2 } else { i += 1 }
  }
  r
}

sema_gref_ident_byte := fn(src : ptr(u8), i : usize) -> bool {
  b := bytes(str_at((src + i), 1))[0]
  (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
}

## A source span may be the whole `mod::name` path or only the parser's tail `name`.  Recover both
## forms exactly as the lower's global resolver does, so qualified constants and globals use the same
## module identity as qualified calls/types.
SemaGRef := struct { ms : usize, ml : usize, ns : usize, nl : usize, qual : bool }
sema_gref_split := fn(src : ptr(u8), s : usize, n : usize) -> SemaGRef {
  z := SemaGRef(ms = 0, ml = 0, ns = s, nl = n, qual = false)
  if n == 0 { return z }
  cp := sema_colon_pos(src, s, n)
  if cp >= 0 {
    hl := usize(cp)
    if hl + 2 < n { return SemaGRef(ms = s, ml = hl, ns = s + hl + 2, nl = n - hl - 2, qual = true) }
    return z
  }
  if s < 3 { return z }
  if str_at((src + s - 2), 2) != "::" { return z }
  he := s - 2
  mut p := he
  mut scanning := true
  while scanning {
    mut q := p
    while q > 0 and sema_gref_ident_byte(src, q - 1) { q -= 1 }
    if q == p { return z }
    p = q
    if p >= 2 and str_at((src + p - 2), 2) == "::" { p -= 2 } else { scanning = false }
  }
  SemaGRef(ms = p, ml = he - p, ns = s, nl = n, qual = true)
}

## Return the first located violation for a fully-resolved module-head/name pair.  An unknown head is
## intentionally ignored: aliases and intrinsic/prelude namespaces have their own resolution rules.
sema_vis_pair := fn(decls : ptr(rt::Vec), src : ptr(u8), hs : usize, hl : usize, ns : usize, nl : usize, cs : usize, cl : usize, k1 : u8, k2 : u8) -> usize {
  if hl == 0 or nl == 0 { return 0 }
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if (d.kind == k1 or d.kind == k2) and d.name_len != 0
       and streq(src, d.name_start, d.name_len, ns, nl)
       and sema_mod_seg_eq(src, d.mod_start, d.mod_len, hs, hl)
       and sema_decl_visible_from(src, d, cs, cl) == false { return ns }
    i += 1
  }
  0
}

sema_vis_qual := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, cs : usize, cl : usize, k1 : u8, k2 : u8) -> usize {
  if n == 0 { return 0 }
  g := sema_gref_split(src, s, n)
  if g.qual == false { return 0 }
  sema_vis_pair(decls, src, g.ms, g.ml, g.ns, g.nl, cs, cl, k1, k2)
}

sema_vis_type_span := fn(decls : ptr(rt::Vec), src : ptr(u8), ts : usize, tl : usize, cs : usize, cl : usize) -> usize {
  if tl == 0 { return 0 }
  bn := base_type_name(src, ts, tl)
  if bn.n == 0 { return 0 }
  r0 := sema_vis_qual(decls, src, bn.s, bn.n, cs, cl, 2, 3)
  if r0 != 0 { return r0 }
  sema_type_ambiguous(decls, src, bn.s, bn.n, cs, cl)
}

## `is_lib_module` is intentionally broad enough to recognize source submodules too.  The ambient
## closure has three reserved roots, however; its bodies are already verified independently and must
## remain trusted here, or the source-only parity walk would re-check `base__derive`/`std__os` and turn
## a valid user program into a false reject.
sema_is_ambient_nested := fn(src : ptr(u8), ms : usize, ml : usize) -> bool {
  mut sep := 0
  mut i := 0
  while i + 1 < ml {
    if str_at((src + ms + i), 2) == "__" { sep = i; i = ml } else { i += 1 }
  }
  if sep == 0 { return false }
  (sep == 4 and str_at((src + ms), 4) == "base")
    or (sep == 5 and str_at((src + ms), 5) == "alloc")
    or (sep == 3 and str_at((src + ms), 3) == "std")
}

## Lower keeps a deliberate last-segment leniency for ambient module copies (`strbuf` can reach
## `alloc__strbuf`).  The sema-side ambiguity checks must use the same predicate or checking the
## compiler's own imported library would create a false reject.
sema_mod_head_matches := fn(src : ptr(u8), as_ : usize, al : usize, ms : usize, ml : usize) -> bool {
  if sema_mod_seg_eq(src, as_, al, ms, ml) { return true }
  mut ls := 0
  mut k := 0
  while k + 1 < al {
    if str_at((src + as_ + k), 2) == "__" or str_at((src + as_ + k), 2) == "::" { ls = k + 2 }
    k += 1
  }
  if ls == 0 { return false }
  streq(src, as_ + ls, al - ls, ms, ml)
}

## Recover the module head selected by a listed projection for one member name.  This is only an
## ambiguity escape hatch: the declared-surface walk already validates each projection member.
sema_projection_head_for := fn(src : ptr(u8), rs : usize, rl : usize, ns : usize, nl : usize) -> SemaGRef {
  z := SemaGRef(ms = 0, ml = 0, ns = 0, nl = 0, qual = false)
  if rl < 4 or str_at((src + rs), 1) != "(" { return z }
  mut e := rs + 1
  ende := rs + rl
  while e < ende and str_at((src + e), 1) != ")" { e += 1 }
  if e >= ende { return z }
  mut p := e + 1
  while p < ende and str_at((src + p), 1) != "=" { p += 1 }
  if p >= ende { return z }
  p += 1
  while p < ende and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") { p += 1 }
  if p >= ende { return z }
  mut q := rs + 1
  while q < e {
    while q < e and (str_at((src + q), 1) == " " or str_at((src + q), 1) == "," or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t" or str_at((src + q), 1) == "\r") { q += 1 }
    mut r := q
    while r < e and sema_gref_ident_byte(src, r) { r += 1 }
    if r == q { q += 1 }
    else {
      if streq(src, q, r - q, ns, nl) {
        g := sema_gref_split(src, p, ende - p)
        if g.qual { return g }
        ## A listed projection's RHS is itself a module head (`(PUB_C) := geo`), so a
        ## single-segment head has no `::` for sema_gref_split to mark as qualified.
        return SemaGRef(ms = p, ml = ende - p, ns = 0, nl = 0, qual = true)
      }
      q = r
    }
  }
  z
}

## A module-level alias or listed projection introduces a name in the projecting module.  The lower's
## global resolver follows that binding before applying the bare-global addressability fence; the sema
## walk must do the same or a legal `(PUB_C) := geo` would be mistaken for a bare access to `geo`'s
## storage. Private targets are still rejected by sema_vis_declared before any body reaches this helper.
sema_bound_name_in_module := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, cs : usize, cl : usize) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.ret_tl != 0
       and sema_mod_seg_eq(src, d.mod_start, d.mod_len, cs, cl) {
      if d.name_len != 0 and streq(src, d.name_start, d.name_len, s, n) { return true }
      if d.name_len == 0 and sema_projection_head_for(src, d.ret_ts, d.ret_tl, s, n).qual { return true }
    }
    i += 1
  }
  false
}

## A §4.1/§4.1.1 binding can disambiguate an otherwise off-chain same-name set.  Return true only
## when the binding names a concrete declaration of the requested kind in its selected module; a
## plain module alias (`m := M`) is intentionally not treated as a name binding.
sema_binding_resolves := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, cs : usize, cl : usize, k1 : u8, k2 : u8) -> bool {
  if nl == 0 or cl == 0 { return false }
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    b := deref(decl_get(decls, i))
    if b.is_fn == false and b.kind == 0 and b.arity == 0 and b.ret_tl != 0
       and sema_mod_seg_eq(src, b.mod_start, b.mod_len, cs, cl) {
      mut hs := 0
      mut hl := 0
      mut ts := ns
      mut tl := nl
      if b.name_len == 0 {
        ph := sema_projection_head_for(src, b.ret_ts, b.ret_tl, ns, nl)
        if ph.qual { hs = ph.ms; hl = ph.ml }
      } else if streq(src, b.name_start, b.name_len, ns, nl) {
        g := sema_gref_split(src, b.ret_ts, b.ret_tl)
        if g.qual { hs = g.ms; hl = g.ml; ts = g.ns; tl = g.nl }
      }
      if hl != 0 {
        mut j := 0
        while j < cnt {
          d := deref(decl_get(decls, j))
          if (d.kind == k1 or d.kind == k2) and streq(src, d.name_start, d.name_len, ts, tl)
             and sema_mod_head_matches(src, d.mod_start, d.mod_len, hs, hl) { return true }
          j += 1
        }
      }
    }
    i += 1
  }
  false
}

## A bare type name is rejected only in the same proven shape as lower_layout::type_decl_ranked:
## more than one nominal candidate, no own/ancestor candidate, no explicit binding, and every
## candidate private. A unique off-chain name and any public candidate retain the historical
## compatibility fallback because the parser may have discarded a qualified head.
sema_type_ambiguous := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, cs : usize, cl : usize) -> usize {
  if n == 0 { return 0 }
  g := sema_gref_split(src, s, n)
  if g.qual { return 0 }
  cnt := rt::vec_len(deref(decls))
  mut hits := 0
  mut anypub := false
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if (d.kind == 2 or d.kind == 3) and streq(src, d.name_start, d.name_len, s, n) {
      hits += 1
      if decl_is_pub(src, d.name_start) { anypub = true }
      if sema_mod_head_matches(src, d.mod_start, d.mod_len, cs, cl) or sema_mod_anc_rank(src, d.mod_start, d.mod_len, cs, cl) >= 0 { return 0 }
    }
    i += 1
  }
  if hits <= 1 or anypub { return 0 }
  if sema_binding_resolves(decls, src, s, n, cs, cl, 2, 3) { return 0 }
  s
}

## Mirror lower::callee_arity_collision without consulting lower's name index. The checker has already
## built its own index for normal bodies, but this source-only pass also visits nested module bodies,
## where a full scan is preferable to importing lower's mutable resolver state.
sema_callee_arity_collision := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, cs : usize, cl : usize) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if (d.kind == 1 or d.kind == 4) and streq(src, d.name_start, d.name_len, s, n)
       and sema_mod_head_matches(src, d.mod_start, d.mod_len, cs, cl) == false
       and sema_mod_anc_rank(src, d.mod_start, d.mod_len, cs, cl) < 0 {
      mut j := 0
      while j < cnt {
        e := deref(decl_get(decls, j))
        if j != i and (e.kind == 1 or e.kind == 4) and streq(src, e.name_start, e.name_len, s, n)
           and sema_mod_head_matches(src, e.mod_start, e.mod_len, cs, cl) == false
           and sema_mod_anc_rank(src, e.mod_start, e.mod_len, cs, cl) < 0
           and e.arity == d.arity and e.is_generic == d.is_generic
           and sema_mod_seg_eq(src, e.mod_start, e.mod_len, d.mod_start, d.mod_len) == false { return true }
        j += 1
      }
    }
    i += 1
  }
  false
}

## A bare call is a located §3 violation only when every same-name candidate is off-chain and the
## lower resolver would hit its same-arity/genericity collision. Unique names, ancestor/own matches,
## and explicit bindings remain accepted.
sema_callee_ambiguous := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, cs : usize, cl : usize) -> usize {
  if n == 0 or sema_gref_split(src, s, n).qual { return 0 }
  cnt := rt::vec_len(deref(decls))
  mut hits := 0
  mut generic := false
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if (d.kind == 1 or d.kind == 4) and streq(src, d.name_start, d.name_len, s, n) {
      if d.is_generic { generic = true }
      if sema_mod_head_matches(src, d.mod_start, d.mod_len, cs, cl) or sema_mod_anc_rank(src, d.mod_start, d.mod_len, cs, cl) >= 0 { return 0 }
      hits += 1
    }
  i += 1
  }
  ## Generic calls have an additional resolver-owned tie-break (leading type-argument count and
  ## generic arity), so this non-generic mirror must not preempt it. The §3 reject family here is the
  ## equal-arity, non-generic bare-call ambiguity handled by lower::callee_arity_collision.
  if hits <= 1 or generic { return 0 }
  if sema_binding_resolves(decls, src, s, n, cs, cl, 1, 4) { return 0 }
  if sema_callee_arity_collision(decls, src, s, n, cs, cl) { return s }
  0
}

## A `pub` alias/projection is a re-export, not a private down-tree use.  Preserve that separate
## Modules §4.3 rule while returning the same located CheckErr shape as §3.
sema_vis_reexport := fn(decls : ptr(rt::Vec), src : ptr(u8), hs : usize, hl : usize, ns : usize, nl : usize) -> usize {
  if hl == 0 or nl == 0 { return 0 }
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.name_len != 0 and streq(src, d.name_start, d.name_len, ns, nl)
       and sema_mod_seg_eq(src, d.mod_start, d.mod_len, hs, hl)
       and decl_is_pub(src, d.name_start) == false { return ns }
    i += 1
  }
  0
}

## Recover a listed projection `(a, b) := M` from the parser's verbatim RHS span.
sema_vis_projection := fn(decls : ptr(rt::Vec), src : ptr(u8), rs : usize, rl : usize, cs : usize, cl : usize, is_pub : bool) -> usize {
  if rl < 4 or str_at((src + rs), 1) != "(" { return 0 }
  mut e := rs + 1
  ende := rs + rl
  while e < ende and str_at((src + e), 1) != ")" { e += 1 }
  if e >= ende { return 0 }
  mut p := e + 1
  while p < ende and str_at((src + p), 1) != "=" { p += 1 }
  if p >= ende { return 0 }
  p += 1
  while p < ende and (str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r") { p += 1 }
  if p >= ende { return 0 }
  hs := p
  hl := ende - p
  mut q := rs + 1
  mut res := 0
  while q < e and res == 0 {
    while q < e and (str_at((src + q), 1) == " " or str_at((src + q), 1) == "," or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t" or str_at((src + q), 1) == "\r") { q += 1 }
    mut r := q
    while r < e and sema_gref_ident_byte(src, r) { r += 1 }
    if r == q { q += 1 }
    else {
      res = sema_vis_pair(decls, src, hs, hl, q, r - q, cs, cl, 1, 4)
      if res == 0 { res = sema_vis_pair(decls, src, hs, hl, q, r - q, cs, cl, 2, 3) }
      if res == 0 { res = sema_vis_pair(decls, src, hs, hl, q, r - q, cs, cl, 0, 0) }
      if res == 0 and is_pub { res = sema_vis_reexport(decls, src, hs, hl, q, r - q) }
      q = r
    }
  }
  res
}

## Declared-surface half of Modules §3: signatures, aggregate fields, aliases, re-exports and listed
## projections.  This runs before body checking, matching lower's pre-emission pass.
sema_vis_declared := fn(decls : ptr(rt::Vec), src : ptr(u8)) -> usize {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    mut pp := d.params_head
    while pp != 0 {
      pm := deref(param_p(pp))
      r0 := sema_vis_type_span(decls, src, pm.ts, pm.tl, d.mod_start, d.mod_len)
      if r0 != 0 { return r0 }
      pp = pm.next
    }
    if d.is_fn and d.ret_tl != 0 {
      r1 := sema_vis_type_span(decls, src, d.ret_ts, d.ret_tl, d.mod_start, d.mod_len)
      if r1 != 0 { return r1 }
    }
    mut f := d.fields_head
    while f != 0 {
      fd := deref(fld_p(f))
      r2 := sema_vis_type_span(decls, src, fd.ts, fd.tl, d.mod_start, d.mod_len)
      if r2 != 0 { return r2 }
      f = fd.next
    }
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.ret_tl != 0 and d.name_len != 0 {
      mut r3 := sema_vis_qual(decls, src, d.ret_ts, d.ret_tl, d.mod_start, d.mod_len, 1, 4)
      if r3 == 0 { r3 = sema_vis_qual(decls, src, d.ret_ts, d.ret_tl, d.mod_start, d.mod_len, 2, 3) }
      if r3 == 0 { r3 = sema_vis_qual(decls, src, d.ret_ts, d.ret_tl, d.mod_start, d.mod_len, 0, 0) }
      if r3 == 0 and decl_is_pub(src, d.name_start) {
        gr := sema_gref_split(src, d.ret_ts, d.ret_tl)
        if gr.qual { r3 = sema_vis_reexport(decls, src, gr.ms, gr.ml, gr.ns, gr.nl) }
      }
      if r3 != 0 { return r3 }
    }
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.ret_tl != 0 and d.name_len == 0 {
      r4 := sema_vis_projection(decls, src, d.ret_ts, d.ret_tl, d.mod_start, d.mod_len, decl_is_pub(src, d.ret_ts))
      if r4 != 0 { return r4 }
    }
    i += 1
  }
  0
}

## The ordinary checker deliberately trusts ambient-library modules, and `is_lib_module` also covers
## source submodules whose mangled names contain `__` (for example `mod__child`).  Visibility is a
## separate invariant, so run this lightweight name collection + AST walk for those skipped bodies too;
## it performs no type checking and therefore does not reopen the library trust boundary.
sema_collect_name := fn(locals : ptr(LVec), src : ptr(u8), s : usize, n : usize) {
  if n != 0 and not local_in(locals, deref(locals).len, src, s, n) {
    lvec_push(deref(locals), Local(ns = s, nl = n, tag = 0, prov = 0, tns = 0, tnl = 0))
  }
}

sema_collect_expr := fn(e : ptr(Expr), locals : ptr(LVec), src : ptr(u8), a : ptr(mut rt::Arena)) {
  if unchecked bitcast(usize, e) == 0 { return }
  match deref(e) {
    Expr::Bin(op, l, r) => { sema_collect_expr(l, locals, src, a); sema_collect_expr(r, locals, src, a) }
    Expr::If(c, t, f) => { sema_collect_expr(c, locals, src, a); sema_collect_expr(t, locals, src, a); sema_collect_expr(f, locals, src, a) }
    Expr::Match(sc, ah) => {
      sema_collect_expr(sc, locals, src, a)
      mut arm := ah
      while arm != 0 {
        am := deref(arm_p(arm))
        mut bd := am.binds_head
        while bd != 0 { sema_collect_name(locals, src, bnd_ns(bd), bnd_nl(bd)); bd = bnd_next(bd) }
        sema_collect_expr(am.body, locals, src, a)
        sema_collect_stmts(am.body_stmts, locals, src, a)
        arm = am.next
      }
    }
    Expr::Call(cs, cl, na, ah) => { mut g := ah; while g != 0 { ga := deref(arg_p(g)); sema_collect_expr(ga.e, locals, src, a); g = ga.next } }
    Expr::StructLit(cs, cl, nf, fh) => { mut g := fh; while g != 0 { ga := deref(arg_p(g)); sema_collect_expr(ga.e, locals, src, a); g = ga.next } }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { mut g := ph; while g != 0 { ga := deref(arg_p(g)); sema_collect_expr(ga.e, locals, src, a); g = ga.next } }
    Expr::Field(b, fs, fl) => { sema_collect_expr(b, locals, src, a) }
    Expr::AddrOf(p) => { sema_collect_expr(p, locals, src, a) }
    Expr::Deref(p) => { sema_collect_expr(p, locals, src, a) }
    Expr::ArrayLit(ne, eh) => { mut g := eh; while g != 0 { ga := deref(arg_p(g)); sema_collect_expr(ga.e, locals, src, a); g = ga.next } }
    Expr::Index(b, ix) => { sema_collect_expr(b, locals, src, a); sema_collect_expr(ix, locals, src, a) }
    Expr::Try(inner) => { sema_collect_expr(inner, locals, src, a) }
    Expr::Slice(b, lo, hi) => { sema_collect_expr(b, locals, src, a); sema_collect_expr(lo, locals, src, a); sema_collect_expr(hi, locals, src, a) }
    Expr::CompField(b, ix) => { sema_collect_expr(b, locals, src, a); sema_collect_expr(ix, locals, src, a) }
    Expr::Unchecked(inner) => { sema_collect_expr(inner, locals, src, a) }
    Expr::Lambda(pos, ph, rts, rtl, bh, val) => { sema_collect_stmts(bh, locals, src, a); sema_collect_expr(val, locals, src, a) }
    Expr::Bitcast(inner, ts, tl) => { sema_collect_expr(inner, locals, src, a) }
    Expr::Loop(body) => { sema_collect_stmts(body, locals, src, a) }
    _ => {}
  }
}

sema_collect_stmts := fn(head : ptr(mut Stmt), locals : ptr(LVec), src : ptr(u8), a : ptr(mut rt::Arena)) {
  mut cur := head
  while cur != 0 {
    st := deref(stmt_p(Stmt, cur))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        if not assign_is_reassign(src, ns, nl) { sema_collect_name(locals, src, ns, nl) }
        sema_collect_expr(v, locals, src, a)
      }
      Stmt::While(c, b, nx) => { sema_collect_expr(c, locals, src, a); sema_collect_stmts(b, locals, src, a) }
      Stmt::FieldAssign(bns, bnl, fns, fnl, v, nx) => { sema_collect_expr(v, locals, src, a) }
      Stmt::Return(v, nx) => { sema_collect_expr(v, locals, src, a) }
      Stmt::If(c, th, el, nx) => { sema_collect_expr(c, locals, src, a); sema_collect_stmts(th, locals, src, a); sema_collect_stmts(el, locals, src, a) }
      Stmt::Match(sc, ah, nx) => {
        sema_collect_expr(sc, locals, src, a)
        mut arm := ah
        while arm != 0 { am := deref(arm_p(arm)); mut bd := am.binds_head; while bd != 0 { sema_collect_name(locals, src, bnd_ns(bd), bnd_nl(bd)); bd = bnd_next(bd) }; sema_collect_stmts(am.body_stmts, locals, src, a); sema_collect_expr(am.body, locals, src, a); arm = am.next }
      }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { sema_collect_name(locals, src, fns, fnl); sema_collect_expr(lo, locals, src, a); sema_collect_expr(hi, locals, src, a); sema_collect_stmts(b, locals, src, a) }
      Stmt::DerefAssign(p, v, nx) => { sema_collect_expr(p, locals, src, a); sema_collect_expr(v, locals, src, a) }
      Stmt::IndexAssign(b, ix, v, nx) => { sema_collect_expr(b, locals, src, a); sema_collect_expr(ix, locals, src, a); sema_collect_expr(v, locals, src, a) }
      Stmt::IndexFieldAssign(b, ix, fs, fl, v, nx) => { sema_collect_expr(b, locals, src, a); sema_collect_expr(ix, locals, src, a); sema_collect_expr(v, locals, src, a) }
      Stmt::FieldPathAssign(p, v, nx) => { sema_collect_expr(p, locals, src, a); sema_collect_expr(v, locals, src, a) }
      Stmt::Loop(b, nx) => { sema_collect_stmts(b, locals, src, a) }
      Stmt::Break(v, bd, nx) => { sema_collect_expr(v, locals, src, a) }
      Stmt::ExprStmt(v, nx) => { sema_collect_expr(v, locals, src, a) }
      Stmt::CompIf(c, th, el, nx) => { sema_collect_expr(c, locals, src, a); sema_collect_stmts(th, locals, src, a); sema_collect_stmts(el, locals, src, a) }
      Stmt::CompFor(vs, vl, iv, b, nx) => { sema_collect_name(locals, src, vs, vl); sema_collect_stmts(b, locals, src, a) }
      Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { sema_collect_name(locals, src, vs, vl); sema_collect_expr(lo, locals, src, a); sema_collect_expr(hi, locals, src, a); sema_collect_stmts(b, locals, src, a) }
      Stmt::Unchecked(b, nx) => { sema_collect_stmts(b, locals, src, a) }
      Stmt::AllocWith(e0, b, nx) => { sema_collect_expr(e0, locals, src, a); sema_collect_stmts(b, locals, src, a) }
      Stmt::Continue(cd, nx) => {}
      Stmt::CompMatch(sc, ah, nx) => {
        sema_collect_expr(sc, locals, src, a)
        mut arm := ah
        while arm != 0 { am := deref(arm_p(arm)); mut bd := am.binds_head; while bd != 0 { sema_collect_name(locals, src, bnd_ns(bd), bnd_nl(bd)); bd = bnd_next(bd) }; sema_collect_stmts(am.body_stmts, locals, src, a); sema_collect_expr(am.body, locals, src, a); arm = am.next }
      }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
}

sema_vis_all_bodies := fn(decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena)) -> usize {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if is_lib_module(src, d.mod_start, d.mod_len) and not sema_is_ambient_nested(src, d.mod_start, d.mod_len) and not guard_is_false(d, src) {
      if d.kind == 1 or d.kind == 4 or d.kind == 5 {
        mut fw := 0
        mut fs := 0
        mut locals := lvec_new(a, 16, ptr(fw), ptr(fs), d.mod_start, d.mod_len)
        mut pp := d.params_head
        while pp != 0 { pm := deref(param_p(pp)); sema_collect_name(ptr(locals), src, pm.ns, pm.nl); pp = pm.next }
        sema_collect_stmts(d.body_stmts, ptr(locals), src, a)
        vr0 := sema_vis_stmts(d.body_stmts, decls, src, d.mod_start, d.mod_len, ptr(locals), deref(locals).len, a)
        if vr0 != 0 { return located_err(vr0) }
        if unchecked bitcast(usize, d.value) != 0 {
          vr1 := sema_vis_expr(d.value, decls, src, d.mod_start, d.mod_len, ptr(locals), deref(locals).len, a)
          if vr1 != 0 { return located_err(vr1) }
        }
      } else if d.kind == 0 and unchecked bitcast(usize, d.value) != 0 {
        mut fw0 := 0
        mut fs0 := 0
        mut locals0 := lvec_new(a, 1, ptr(fw0), ptr(fs0), d.mod_start, d.mod_len)
        vr2 := sema_vis_expr(d.value, decls, src, d.mod_start, d.mod_len, ptr(locals0), 0, a)
        if vr2 != 0 { return located_err(vr2) }
      }
    }
    i += 1
  }
  0
}

sema_is_global_decl := fn(d : Decl, src : ptr(u8)) -> bool {
  if d.is_fn or d.kind != 0 or d.arity != 0 or d.ret_tl != 0 { return false }
  if unchecked bitcast(usize, d.value) == 0 { return false }
  ## A bare/qualified Var initializer is a module alias/import, not storage.  This is the same
  ## distinction lower's global resolver makes before applying the addressability rule.
  expr_var_span(d.value).n == 0
}

## Return the first global-addressability violation for a source name, or 0 when it is local, visible,
## or not a module-level value at all.  A public sibling global still requires a qualified path; a bare
## name is resolved only on the caller's own/ancestor chain, exactly as lower's gref resolver does.
sema_global_ref_bad := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, cs : usize, cl : usize) -> usize {
  g := sema_gref_split(src, s, n)
  if g.nl == 0 { return 0 }
  if not g.qual and sema_bound_name_in_module(decls, src, g.ns, g.nl, cs, cl) { return 0 }
  cnt := rt::vec_len(deref(decls))
  mut any := false
  mut exact := false
  mut visible := false
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if sema_is_global_decl(d, src) and streq(src, d.name_start, d.name_len, g.ns, g.nl) {
      any = true
      if g.qual {
        if sema_mod_seg_eq(src, d.mod_start, d.mod_len, g.ms, g.ml) {
          exact = true
          if sema_decl_visible_from(src, d, cs, cl) == false { return g.ns }
          visible = true
        }
      } else if sema_mod_anc_rank(src, d.mod_start, d.mod_len, cs, cl) >= 0 { visible = true }
    }
    i += 1
  }
  if g.qual {
    if exact { return 0 }
    ## An alias/unknown head is deliberately left to the lower's alias resolver.
    return 0
  }
  if any and visible == false { return g.ns }
  0
}

## True when `d` is a storage-backed module value whose initializer is an array whose first element is an
## enum value. The parser's checked two-pass path represents the first element as `EnumLit`, matching the
## lower's `global_arr_enum` classifier and keeping the declaration/read/write layout in one shape.
sema_enum_global_array_decl := fn(d : Decl, decls : ptr(rt::Vec), upto : usize, src : ptr(u8)) -> bool {
  if not sema_is_global_decl(d, src) { return false }
  first := expr_array_first(d.value)
  if unchecked bitcast(usize, first) == 0 { return false }
  ep := expr_enum_parts(first)
  ep.is_enum and enum_decl_of(decls, src, ep.es, ep.el) >= 0
}

## Whether the enum-array declaration has the exact first-element shape that lower::global_arr_enum can
## consume. This intentionally mirrors the classifier above instead of treating a source-level nullary
## variant spelling as a separate AST shape: the checked parser pass has already normalized it to `EnumLit`.
sema_enum_global_array_decl_lowerable := fn(d : Decl, decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  if not sema_is_global_decl(d, src) { return false }
  first := expr_array_first(d.value)
  if unchecked bitcast(usize, first) == 0 { return false }
  ep := expr_enum_parts(first)
  ep.is_enum and enum_decl_of(decls, src, ep.es, ep.el) >= 0
}

## Resolve a bare alias/projection binding to the qualified value it names. The lower follows this
## binding before selecting a module global; the safety fence must do the same or `(GE) := geo` / `GE[i]`
## would bypass the common reject and reach the backend's late guard. `qual = false` means the name is not
## a value binding (a plain module alias or an ordinary local is deliberately left to its own resolver).
sema_enum_global_array_binding := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, cs : usize, cl : usize) -> SemaGRef {
  z := SemaGRef(ms = 0, ml = 0, ns = 0, nl = 0, qual = false)
  if n == 0 or cl == 0 { return z }
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    b := deref(decl_get(decls, i))
    if b.is_fn == false and b.kind == 0 and b.arity == 0 and b.ret_tl != 0
       and sema_mod_seg_eq(src, b.mod_start, b.mod_len, cs, cl) {
      if b.name_len != 0 and streq(src, b.name_start, b.name_len, s, n) {
        g := sema_gref_split(src, b.ret_ts, b.ret_tl)
        if g.qual { return g }
      } else if b.name_len == 0 {
        ph := sema_projection_head_for(src, b.ret_ts, b.ret_tl, s, n)
        if ph.qual { return SemaGRef(ms = ph.ms, ml = ph.ml, ns = s, nl = n, qual = true) }
      }
    }
    i += 1
  }
  z
}

## Return the base-name span of a visible enum-array global used through `base[index]`, or 0 when the
## base is local/non-global. `allow_root` admits only the lowerable whole-element root forms; a
## Qualified and bare names follow the same module visibility rules as the existing global-reference
## walk; an inaccessible sibling is left to that walk's own diagnostic.
sema_enum_global_array_use_bad := fn(base : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, allow_root : bool) -> usize {
  bv := expr_var_span(base)
  if bv.n == 0 { return 0 }
  if nloc != 0 and local_in(locals, nloc, src, bv.s, bv.n) { return 0 }
  g := sema_gref_split(src, bv.s, bv.n)
  if g.nl == 0 { return 0 }
  cs := (deref(locals)).mod_s
  cl := (deref(locals)).mod_l
  cnt := rt::vec_len(deref(decls))
  if not g.qual {
    ## A named alias or listed projection wins over same-name globals in the current module. Resolve it
    ## before the generic `sema_bound_name_in_module` escape, then apply the target declaration's own
    ## visibility and enum-array classification exactly as the lower's binding_head_span path does.
    ba := sema_enum_global_array_binding(decls, src, g.ns, g.nl, cs, cl)
    if ba.qual {
      mut ai := 0
      while ai < cnt {
        ad := deref(decl_get(decls, ai))
        if sema_enum_global_array_decl(ad, decls, upto, src)
           and streq(src, ad.name_start, ad.name_len, ba.ns, ba.nl)
           and sema_mod_seg_eq(src, ad.mod_start, ad.mod_len, ba.ms, ba.ml)
           and sema_decl_visible_from(src, ad, cs, cl) {
          if not allow_root or not sema_enum_global_array_decl_lowerable(ad, decls, src) { return bv.s }
          return 0
        }
        ai += 1
      }
      ## The binding is known, but its target is not an enum-array global. Do not fall through to a
      ## same-name global from another module; the alias already determines what the source means.
      return 0
    }
    if sema_bound_name_in_module(decls, src, g.ns, g.nl, cs, cl) { return 0 }
  }
  mut best := 0 - 1
  if not g.qual {
    mut bi := 0
    while bi < cnt {
      bd := deref(decl_get(decls, bi))
      if sema_is_global_decl(bd, src) and streq(src, bd.name_start, bd.name_len, g.ns, g.nl) {
        br := sema_mod_anc_rank(src, bd.mod_start, bd.mod_len, cs, cl)
        if br > best { best = br }
      }
      bi += 1
    }
  }
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if sema_enum_global_array_decl(d, decls, upto, src) and streq(src, d.name_start, d.name_len, g.ns, g.nl) {
      mut visible := false
      if g.qual {
        if sema_mod_seg_eq(src, d.mod_start, d.mod_len, g.ms, g.ml) and sema_decl_visible_from(src, d, cs, cl) { visible = true }
      } else if sema_mod_anc_rank(src, d.mod_start, d.mod_len, cs, cl) == best { visible = true }
      if visible and (not allow_root or not sema_enum_global_array_decl_lowerable(d, decls, src)) { return bv.s }
    }
    i += 1
  }
  0
}

## Context-aware structural walk for the global enum-array boundary. `allow_root` is used only for the
## supported whole-element root forms: a binding RHS, a write place, or a match scrutinee. Every nested
## expression is a VALUE consumer, so `f(GE[i])`, arithmetic, returns, and branch values are rejected
## before a backend can apply its width-blind one-word Index path.
sema_enum_global_array_value_bad := fn(e : ptr(Expr), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena), allow_root : bool) -> usize {
  if unchecked bitcast(usize, e) == 0 { return 0 }
  ib := expr_index_base(e)
  if unchecked bitcast(usize, ib) != 0 {
    mut bad := sema_enum_global_array_value_bad(ib, decls, upto, src, locals, nloc, a, false)
    if bad == 0 { bad = sema_enum_global_array_use_bad(ib, decls, upto, src, locals, nloc, allow_root) }
    if bad == 0 { bad = sema_enum_global_array_value_bad(expr_index_index(e), decls, upto, src, locals, nloc, a, false) }
    return bad
  }
  emp := expr_match_parts(e)
  if emp.is_match {
    mut bad := sema_enum_global_array_value_bad(emp.scrut, decls, upto, src, locals, nloc, a, true)
    mut arm := emp.head
    while arm != 0 and bad == 0 {
      am := deref(arm_p(arm))
      arm_base := nloc
      mut arm_cnt := nloc
      mut bd := am.binds_head
      while bd != 0 {
        bnns := bnd_ns(bd)
        bnnl := bnd_nl(bd)
        if not local_in(locals, arm_cnt, src, bnns, bnnl) {
          lvec_push(deref(locals), Local(ns = bnns, nl = bnnl, tag = 0, prov = 0, tns = 0, tnl = 0))
          arm_cnt += 1
        }
        bd = bnd_next(bd)
      }
      bad = sema_enum_global_array_value_bad(am.body, decls, upto, src, locals, arm_cnt, a, false)
      if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(am.body_stmts, decls, upto, src, locals, arm_cnt, a) }
      lvec_truncate(deref(locals), arm_base)
      arm = am.next
    }
    return bad
  }
  ah0 := expr_call_args_head(e)
  if ah0 != 0 {
    mut g := ah0
    mut bad0 := 0
    while g != 0 and bad0 == 0 {
      ga := deref(arg_p(g))
      bad0 = sema_enum_global_array_value_bad(ga.e, decls, upto, src, locals, nloc, a, false)
      g = ga.next
    }
    return bad0
  }
  match deref(e) {
    Expr::Bin(op, l, r) => {
      bad1 := sema_enum_global_array_value_bad(l, decls, upto, src, locals, nloc, a, false)
      if bad1 != 0 { return bad1 }
      sema_enum_global_array_value_bad(r, decls, upto, src, locals, nloc, a, false)
    }
    Expr::If(c, t, f) => {
      bad2 := sema_enum_global_array_value_bad(c, decls, upto, src, locals, nloc, a, false)
      if bad2 != 0 { return bad2 }
      bad3 := sema_enum_global_array_value_bad(t, decls, upto, src, locals, nloc, a, false)
      if bad3 != 0 { return bad3 }
      sema_enum_global_array_value_bad(f, decls, upto, src, locals, nloc, a, false)
    }
    Expr::StructLit(ss, sl, nf, fh) => {
      mut g1 := fh
      mut bad4 := 0
      while g1 != 0 and bad4 == 0 { ga1 := deref(arg_p(g1)); bad4 = sema_enum_global_array_value_bad(ga1.e, decls, upto, src, locals, nloc, a, false); g1 = ga1.next }
      bad4
    }
    Expr::EnumLit(es, el, vs, vl, np, ph) => {
      mut g2 := ph
      mut bad5 := 0
      while g2 != 0 and bad5 == 0 { ga2 := deref(arg_p(g2)); bad5 = sema_enum_global_array_value_bad(ga2.e, decls, upto, src, locals, nloc, a, false); g2 = ga2.next }
      bad5
    }
    Expr::Field(base, fs, fl) => { sema_enum_global_array_value_bad(base, decls, upto, src, locals, nloc, a, false) }
    Expr::AddrOf(p) => { sema_enum_global_array_value_bad(p, decls, upto, src, locals, nloc, a, false) }
    Expr::Deref(p) => { sema_enum_global_array_value_bad(p, decls, upto, src, locals, nloc, a, false) }
    Expr::ArrayLit(ne, eh) => {
      mut g3 := eh
      mut bad6 := 0
      while g3 != 0 and bad6 == 0 { ga3 := deref(arg_p(g3)); bad6 = sema_enum_global_array_value_bad(ga3.e, decls, upto, src, locals, nloc, a, false); g3 = ga3.next }
      bad6
    }
    Expr::Try(inner) => { sema_enum_global_array_value_bad(inner, decls, upto, src, locals, nloc, a, false) }
    Expr::Slice(base, lo, hi) => {
      bad7 := sema_enum_global_array_value_bad(base, decls, upto, src, locals, nloc, a, false)
      if bad7 != 0 { return bad7 }
      bad8 := sema_enum_global_array_value_bad(lo, decls, upto, src, locals, nloc, a, false)
      if bad8 != 0 { return bad8 }
      sema_enum_global_array_value_bad(hi, decls, upto, src, locals, nloc, a, false)
    }
    Expr::CompField(base, ix) => {
      bad9 := sema_enum_global_array_value_bad(base, decls, upto, src, locals, nloc, a, false)
      if bad9 != 0 { return bad9 }
      sema_enum_global_array_value_bad(ix, decls, upto, src, locals, nloc, a, false)
    }
    Expr::Unchecked(inner) => { sema_enum_global_array_value_bad(inner, decls, upto, src, locals, nloc, a, false) }
    Expr::Lambda(pos, ph, rts, rtl, bh, value) => {
      lambda_base := nloc
      mut lambda_cnt := nloc
      mut lp := ph
      while lp != 0 {
        pm := deref(param_p(lp))
        if not local_in(locals, lambda_cnt, src, pm.ns, pm.nl) {
          lvec_push(deref(locals), Local(ns = pm.ns, nl = pm.nl, tag = 0, prov = 0, tns = 0, tnl = 0))
          lambda_cnt += 1
        }
        lp = pm.next
      }
      bad10 := sema_enum_global_array_value_bad_stmts(bh, decls, upto, src, locals, lambda_cnt, a)
      if bad10 != 0 { lvec_truncate(deref(locals), lambda_base); return bad10 }
      bad11 := sema_enum_global_array_value_bad(value, decls, upto, src, locals, lambda_cnt, a, false)
      lvec_truncate(deref(locals), lambda_base)
      bad11
    }
    Expr::Bitcast(inner, ts, tl) => { sema_enum_global_array_value_bad(inner, decls, upto, src, locals, nloc, a, false) }
    Expr::Loop(body) => { sema_enum_global_array_value_bad_stmts(body, decls, upto, src, locals, nloc, a) }
    _ => { 0 }
  }
}

sema_enum_global_array_value_bad_stmts := fn(head : ptr(mut Stmt), decls : ptr(rt::Vec), upto : usize, src : ptr(u8), locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  saved_len := deref(locals).len
  saved_pcnt := deref(locals).pcnt
  mut cur := head
  mut bad := 0
  mut cnt := nloc
  while cur != 0 and bad == 0 {
    st := deref(stmt_p(Stmt, cur))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        ann := local_type_span(src, ns, nl)
        allow := not assign_is_reassign(src, ns, nl) and ann.n == 0
        bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, allow)
        if bad == 0 and not assign_is_reassign(src, ns, nl) and not local_in(locals, cnt, src, ns, nl) {
          lvec_push(deref(locals), Local(ns = ns, nl = nl, tag = 0, prov = 0, tns = 0, tnl = 0))
          cnt += 1
        }
      }
      Stmt::While(c, b, nx) => { bad = sema_enum_global_array_value_bad(c, decls, upto, src, locals, cnt, a, false); if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(b, decls, upto, src, locals, cnt, a) } }
      Stmt::FieldAssign(bns, bnl, fns, fnl, v, nx) => { bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, false) }
      Stmt::Return(v, nx) => { bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, false) }
      Stmt::If(c, th, el, nx) => { bad = sema_enum_global_array_value_bad(c, decls, upto, src, locals, cnt, a, false); if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(th, decls, upto, src, locals, cnt, a) }; if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(el, decls, upto, src, locals, cnt, a) } }
      Stmt::Match(sc, ah, nx) => {
        bad = sema_enum_global_array_value_bad(sc, decls, upto, src, locals, cnt, a, true)
        mut arm := ah
        while arm != 0 and bad == 0 {
          am := deref(arm_p(arm))
          arm_base := cnt
          mut arm_cnt := cnt
          mut bd := am.binds_head
          while bd != 0 {
            bnns := bnd_ns(bd)
            bnnl := bnd_nl(bd)
            if not local_in(locals, arm_cnt, src, bnns, bnnl) {
              lvec_push(deref(locals), Local(ns = bnns, nl = bnnl, tag = 0, prov = 0, tns = 0, tnl = 0))
              arm_cnt += 1
            }
            bd = bnd_next(bd)
          }
          bad = sema_enum_global_array_value_bad(am.body, decls, upto, src, locals, arm_cnt, a, false)
          if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(am.body_stmts, decls, upto, src, locals, arm_cnt, a) }
          lvec_truncate(deref(locals), arm_base)
          arm = am.next
        }
      }
      Stmt::For(fns, fnl, lo, hi, b, nx) => {
        bad = sema_enum_global_array_value_bad(lo, decls, upto, src, locals, cnt, a, false)
        if bad == 0 and unchecked bitcast(usize, hi) != 0 { bad = sema_enum_global_array_value_bad(hi, decls, upto, src, locals, cnt, a, false) }
        if bad == 0 {
          loop_base := cnt
          if not local_in(locals, cnt, src, fns, fnl) { lvec_push(deref(locals), Local(ns = fns, nl = fnl, tag = 0, prov = 0, tns = 0, tnl = 0)); cnt += 1 }
          bad = sema_enum_global_array_value_bad_stmts(b, decls, upto, src, locals, cnt, a)
          lvec_truncate(deref(locals), loop_base)
          cnt = loop_base
        }
      }
      Stmt::DerefAssign(p, v, nx) => { bad = sema_enum_global_array_value_bad(p, decls, upto, src, locals, cnt, a, true); if bad == 0 { bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, false) } }
      Stmt::IndexAssign(b, i, v, nx) => { bad = sema_enum_global_array_value_bad(b, decls, upto, src, locals, cnt, a, true); if bad == 0 { bad = sema_enum_global_array_value_bad(i, decls, upto, src, locals, cnt, a, false) }; if bad == 0 { bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, false) } }
      Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { bad = sema_enum_global_array_value_bad(b, decls, upto, src, locals, cnt, a, true); if bad == 0 { bad = sema_enum_global_array_value_bad(i, decls, upto, src, locals, cnt, a, false) }; if bad == 0 { bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, false) } }
      Stmt::FieldPathAssign(p, v, nx) => { bad = sema_enum_global_array_value_bad(p, decls, upto, src, locals, cnt, a, true); if bad == 0 { bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, false) } }
      Stmt::Loop(b, nx) => { bad = sema_enum_global_array_value_bad_stmts(b, decls, upto, src, locals, cnt, a) }
      Stmt::Unchecked(b, nx) => { bad = sema_enum_global_array_value_bad_stmts(b, decls, upto, src, locals, cnt, a) }
      Stmt::Break(v, bd, nx) => { bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, false) }
      Stmt::ExprStmt(v, nx) => { bad = sema_enum_global_array_value_bad(v, decls, upto, src, locals, cnt, a, false) }
      Stmt::AllocWith(e0, b, nx) => { bad = sema_enum_global_array_value_bad(e0, decls, upto, src, locals, cnt, a, false); if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(b, decls, upto, src, locals, cnt, a) } }
      ## Comptime bodies are normally skipped by the type checker because only the selected branch
      ## is semantically active. This fence is structural and intentionally visits both branches: a
      ## known enum-array global in either source branch must not reach a backend's width-blind path
      ## when the target fold selects it.
      Stmt::CompIf(c, th, el, nx) => { bad = sema_enum_global_array_value_bad(c, decls, upto, src, locals, cnt, a, false); if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(th, decls, upto, src, locals, cnt, a) }; if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(el, decls, upto, src, locals, cnt, a) } }
      Stmt::CompFor(vs, vl, iv, b, nx) => {
        base := cnt
        if not local_in(locals, cnt, src, vs, vl) { lvec_push(deref(locals), Local(ns = vs, nl = vl, tag = 0, prov = 0, tns = 0, tnl = 0)); cnt += 1 }
        bad = sema_enum_global_array_value_bad_stmts(b, decls, upto, src, locals, cnt, a)
        lvec_truncate(deref(locals), base)
        cnt = base
      }
      Stmt::CompForRange(vs, vl, lo, hi, b, nx) => {
        bad = sema_enum_global_array_value_bad(lo, decls, upto, src, locals, cnt, a, false)
        if bad == 0 { bad = sema_enum_global_array_value_bad(hi, decls, upto, src, locals, cnt, a, false) }
        if bad == 0 {
          base := cnt
          if not local_in(locals, cnt, src, vs, vl) { lvec_push(deref(locals), Local(ns = vs, nl = vl, tag = 0, prov = 0, tns = 0, tnl = 0)); cnt += 1 }
          bad = sema_enum_global_array_value_bad_stmts(b, decls, upto, src, locals, cnt, a)
          lvec_truncate(deref(locals), base)
          cnt = base
        }
      }
      Stmt::CompMatch(sc, ah, nx) => {
        bad = sema_enum_global_array_value_bad(sc, decls, upto, src, locals, cnt, a, true)
        mut arm := ah
        while arm != 0 and bad == 0 {
          am := deref(arm_p(arm))
          base := cnt
          mut arm_cnt := cnt
          mut bd := am.binds_head
          while bd != 0 {
            bnns := bnd_ns(bd)
            bnnl := bnd_nl(bd)
            if not local_in(locals, arm_cnt, src, bnns, bnnl) { lvec_push(deref(locals), Local(ns = bnns, nl = bnnl, tag = 0, prov = 0, tns = 0, tnl = 0)); arm_cnt += 1 }
            bd = bnd_next(bd)
          }
          bad = sema_enum_global_array_value_bad(am.body, decls, upto, src, locals, arm_cnt, a, false)
          if bad == 0 { bad = sema_enum_global_array_value_bad_stmts(am.body_stmts, decls, upto, src, locals, arm_cnt, a) }
          lvec_truncate(deref(locals), base)
          arm = am.next
        }
      }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  lvec_truncate(deref(locals), saved_len)
  deref(locals).pcnt = saved_pcnt
  bad
}

## Structural expression walk for the body half.  It checks qualified callable/type references and
## module globals, while keeping a final function-wide local set so legitimate shadowing remains valid.
sema_vis_expr := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  if unchecked bitcast(usize, e) == 0 { return 0 }
  ## Bootstrap-safe accessors first: the frozen seed does not reliably dispatch every payload-heavy
  ## Expr arm in a large `match deref(e)`.  Var and Call are the two forms whose source spans carry
  ## the module/global facts, so recover them before the structural match below.
  ev0 := expr_var_span(e)
  if ev0.n != 0 {
    if nloc != 0 and local_in(locals, nloc, src, ev0.s, ev0.n) { return 0 }
    tv0 := sema_type_ambiguous(decls, src, ev0.s, ev0.n, cs, cl)
    if tv0 != 0 { return tv0 }
    return sema_global_ref_bad(decls, src, ev0.s, ev0.n, cs, cl)
  }
  ec0 := expr_call_callee_span(e)
  if ec0.n != 0 {
    mut cr0 := sema_vis_qual(decls, src, ec0.s, ec0.n, cs, cl, 1, 4)
    if cr0 == 0 { cr0 = sema_vis_qual(decls, src, ec0.s, ec0.n, cs, cl, 2, 3) }
    if cr0 == 0 and (nloc == 0 or not local_in(locals, nloc, src, ec0.s, ec0.n)) {
      cr0 = sema_callee_ambiguous(decls, src, ec0.s, ec0.n, cs, cl)
    }
    mut cg0 := expr_call_args_head(e)
    if cr0 == 0 and callee_is_type_builtin(src, ec0.s, ec0.n) {
      if cg0 != 0 {
        cga0 := deref(arg_p(cg0))
        cr0 = sema_package_type_builtin_arg_bad(cga0.e, decls, src, cs, cl)
      }
    }
    while cg0 != 0 and cr0 == 0 {
      cga0 := deref(arg_p(cg0))
      cr0 = sema_vis_expr(cga0.e, decls, src, cs, cl, locals, nloc, a)
      cg0 = cga0.next
    }
    return cr0
  }
  match deref(e) {
    Expr::Var(s, n) => {
      if nloc != 0 and local_in(locals, nloc, src, s, n) { return 0 }
      tv := sema_type_ambiguous(decls, src, s, n, cs, cl)
      if tv != 0 { return tv }
      sema_global_ref_bad(decls, src, s, n, cs, cl)
    }
    Expr::Call(ss, sl, na, ah) => {
      mut r := sema_vis_qual(decls, src, ss, sl, cs, cl, 1, 4)
      if r == 0 { r = sema_vis_qual(decls, src, ss, sl, cs, cl, 2, 3) }
      if r == 0 { r = sema_callee_ambiguous(decls, src, ss, sl, cs, cl) }
      mut g := ah
      while g != 0 and r == 0 {
        ga := deref(arg_p(g))
        r = sema_vis_expr(ga.e, decls, src, cs, cl, locals, nloc, a)
        g = ga.next
      }
      r
    }
    Expr::StructLit(ss, sl, nf, fh) => {
      mut r := sema_vis_type_span(decls, src, ss, sl, cs, cl)
      mut g := fh
      while g != 0 and r == 0 {
        ga := deref(arg_p(g))
        r = sema_vis_expr(ga.e, decls, src, cs, cl, locals, nloc, a)
        g = ga.next
      }
      r
    }
    Expr::EnumLit(es, el, vs, vl, np, ph) => {
      mut r := sema_vis_type_span(decls, src, es, el, cs, cl)
      mut g := ph
      while g != 0 and r == 0 {
        ga := deref(arg_p(g))
        r = sema_vis_expr(ga.e, decls, src, cs, cl, locals, nloc, a)
        g = ga.next
      }
      r
    }
    Expr::Bin(op, l, r0) => {
      r := sema_vis_expr(l, decls, src, cs, cl, locals, nloc, a)
      if r != 0 { return r }
      sema_vis_expr(r0, decls, src, cs, cl, locals, nloc, a)
    }
    Expr::If(c, t, f) => {
      r := sema_vis_expr(c, decls, src, cs, cl, locals, nloc, a)
      if r != 0 { return r }
      r2 := sema_vis_expr(t, decls, src, cs, cl, locals, nloc, a)
      if r2 != 0 { return r2 }
      sema_vis_expr(f, decls, src, cs, cl, locals, nloc, a)
    }
    Expr::Match(sc, ah) => {
      mut r := sema_vis_expr(sc, decls, src, cs, cl, locals, nloc, a)
      mut arm := ah
      while arm != 0 and r == 0 {
        am := deref(arm_p(arm))
        r = sema_vis_expr(am.body, decls, src, cs, cl, locals, nloc, a)
        if r == 0 { r = sema_vis_stmts(am.body_stmts, decls, src, cs, cl, locals, nloc, a) }
        arm = am.next
      }
      r
    }
    Expr::Field(base, fs, fl) => { sema_vis_expr(base, decls, src, cs, cl, locals, nloc, a) }
    Expr::AddrOf(p) => { sema_vis_expr(p, decls, src, cs, cl, locals, nloc, a) }
    Expr::Deref(p) => { sema_vis_expr(p, decls, src, cs, cl, locals, nloc, a) }
    Expr::ArrayLit(ne, eh) => {
      mut r := 0
      mut g := eh
      while g != 0 and r == 0 { ga := deref(arg_p(g)); r = sema_vis_expr(ga.e, decls, src, cs, cl, locals, nloc, a); g = ga.next }
      r
    }
    Expr::Index(base, ix) => {
      r := sema_vis_expr(base, decls, src, cs, cl, locals, nloc, a)
      if r != 0 { return r }
      sema_vis_expr(ix, decls, src, cs, cl, locals, nloc, a)
    }
    Expr::Try(inner) => { sema_vis_expr(inner, decls, src, cs, cl, locals, nloc, a) }
    Expr::Slice(base, lo, hi) => {
      r := sema_vis_expr(base, decls, src, cs, cl, locals, nloc, a)
      if r != 0 { return r }
      r2 := sema_vis_expr(lo, decls, src, cs, cl, locals, nloc, a)
      if r2 != 0 { return r2 }
      sema_vis_expr(hi, decls, src, cs, cl, locals, nloc, a)
    }
    Expr::CompField(base, ix) => {
      r := sema_vis_expr(base, decls, src, cs, cl, locals, nloc, a)
      if r != 0 { return r }
      sema_vis_expr(ix, decls, src, cs, cl, locals, nloc, a)
    }
    Expr::Unchecked(inner) => { sema_vis_expr(inner, decls, src, cs, cl, locals, nloc, a) }
    Expr::Lambda(pos, ph, rts, rtl, bh, val) => {
      r := sema_vis_stmts(bh, decls, src, cs, cl, locals, nloc, a)
      if r != 0 { return r }
      sema_vis_expr(val, decls, src, cs, cl, locals, nloc, a)
    }
    Expr::Bitcast(inner, ts, tl) => { sema_vis_expr(inner, decls, src, cs, cl, locals, nloc, a) }
    Expr::Loop(body) => { sema_vis_stmts(body, decls, src, cs, cl, locals, nloc, a) }
    _ => { 0 }
  }
}

sema_vis_stmts := fn(head : ptr(mut Stmt), decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, locals : ptr(LVec), nloc : usize, a : ptr(mut rt::Arena)) -> usize {
  mut cur := head
  mut r := 0
  while cur != 0 and r == 0 {
    st := deref(stmt_p(Stmt, cur))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        if assign_is_reassign(src, ns, nl) and (nloc == 0 or not local_in(locals, nloc, src, ns, nl)) { r = sema_global_ref_bad(decls, src, ns, nl, cs, cl) }
        if r == 0 { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) }
      }
      Stmt::While(c, b, nx) => { r = sema_vis_expr(c, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_stmts(b, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::FieldAssign(bns, bnl, fns, fnl, v, nx) => {
        if nloc == 0 or not local_in(locals, nloc, src, bns, bnl) { r = sema_global_ref_bad(decls, src, bns, bnl, cs, cl) }
        if r == 0 { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) }
      }
      Stmt::Return(v, nx) => { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) }
      Stmt::If(c, th, el, nx) => { r = sema_vis_expr(c, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_stmts(th, decls, src, cs, cl, locals, nloc, a) }; if r == 0 { r = sema_vis_stmts(el, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::Match(sc, ah, nx) => {
        r = sema_vis_expr(sc, decls, src, cs, cl, locals, nloc, a)
        mut arm := ah
        while arm != 0 and r == 0 { am := deref(arm_p(arm)); r = sema_vis_stmts(am.body_stmts, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_expr(am.body, decls, src, cs, cl, locals, nloc, a) }; arm = am.next }
      }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { r = sema_vis_expr(lo, decls, src, cs, cl, locals, nloc, a); if r == 0 and unchecked bitcast(usize, hi) != 0 { r = sema_vis_expr(hi, decls, src, cs, cl, locals, nloc, a) }; if r == 0 { r = sema_vis_stmts(b, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::DerefAssign(p, v, nx) => { r = sema_vis_expr(p, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::IndexAssign(b, ix, v, nx) => { r = sema_vis_expr(b, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_expr(ix, decls, src, cs, cl, locals, nloc, a) }; if r == 0 { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::IndexFieldAssign(b, ix, fs, fl, v, nx) => { r = sema_vis_expr(b, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_expr(ix, decls, src, cs, cl, locals, nloc, a) }; if r == 0 { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::FieldPathAssign(p, v, nx) => { r = sema_vis_expr(p, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::Loop(b, nx) => { r = sema_vis_stmts(b, decls, src, cs, cl, locals, nloc, a) }
      Stmt::Break(v, bd, nx) => { if unchecked bitcast(usize, v) != 0 { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::ExprStmt(v, nx) => { r = sema_vis_expr(v, decls, src, cs, cl, locals, nloc, a) }
      Stmt::CompIf(c, th, el, nx) => { r = sema_vis_expr(c, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_stmts(th, decls, src, cs, cl, locals, nloc, a) }; if r == 0 { r = sema_vis_stmts(el, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::CompFor(vs, vl, iv, b, nx) => { r = sema_vis_stmts(b, decls, src, cs, cl, locals, nloc, a) }
      Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { r = sema_vis_expr(lo, decls, src, cs, cl, locals, nloc, a); if r == 0 and unchecked bitcast(usize, hi) != 0 { r = sema_vis_expr(hi, decls, src, cs, cl, locals, nloc, a) }; if r == 0 { r = sema_vis_stmts(b, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::Unchecked(b, nx) => { r = sema_vis_stmts(b, decls, src, cs, cl, locals, nloc, a) }
      Stmt::AllocWith(e0, b, nx) => { r = sema_vis_expr(e0, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_stmts(b, decls, src, cs, cl, locals, nloc, a) } }
      Stmt::Continue(cd, nx) => {}
      Stmt::CompMatch(sc, ah, nx) => {
        r = sema_vis_expr(sc, decls, src, cs, cl, locals, nloc, a)
        mut arm := ah
        while arm != 0 and r == 0 { am := deref(arm_p(arm)); r = sema_vis_stmts(am.body_stmts, decls, src, cs, cl, locals, nloc, a); if r == 0 { r = sema_vis_expr(am.body, decls, src, cs, cl, locals, nloc, a) }; arm = am.next }
      }
      _ => {}
    }
    cur = stmt_next_at(cur, a)
  }
  r
}

pub check_program := fn(decls : ptr(rt::Vec), src : ptr(u8), a : ptr(mut rt::Arena)) -> usize {
  ## PERF: build the per-decl name-hash pre-filter for the O(cnt) `name_matches` resolution scans.
  build_sema_dnh(decls, src, deref(a))
  lim := enforce_declared_limits(decls, src, a)
  if lim != 0 { return lim }
  vis0 := sema_vis_declared(decls, src)
  if vis0 != 0 { return located_err(vis0) }
  ## `is_lib_module` is also the parser's nested-module marker (`parent__child`). The ordinary loop
  ## below trusts those bodies, so run the same source-only visibility walk over them here; this keeps
  ## check/build parity without re-entering the full type checker for ambient library code.
  vis1 := sema_vis_all_bodies(decls, src, a)
  if vis1 != 0 { return vis1 }
  cnt := rt::vec_len(deref(decls))
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    ## TRUST the stdlib: keep ambient-lib decls for resolution but do not re-check them (check/build
    ## parity — a check-gap on a stdlib feature must not reject a well-typed user program, §1 item 5).
    if is_lib_module(src, d.mod_start, d.mod_len) { }
    ## a FALSE `when`-guarded decl (CT-5, Comptime §9) is "as if absent" for THIS target: skip its
    ## duplicate + body check entirely, exactly as `lower::emit_program` neuters it before emission.
    else if guard_is_false(d, src) { }
    else {
      ## Memory §2.2 — module-level data bindings have no implicit runtime initializer. A direct aggregate
      ## CALL would therefore be folded as zeroed/static storage while its callee never runs; reject the
      ## same CONST shape before any backend can emit it, with one diagnostic class for every CLI path.
      if sema_global_init_call_bad(d, decls, src) { return global_init_call_err(d.name_start) }
      ## Issue #214 / Types §6.4 + I11: the lower's direct nested-array field fence must run on the
      ## check path too. Reject the declaration before any backend can reserve a word-only image;
      ## the sema helper shares lower_layout's exact source predicate and preserves the field line.
      mdf := sema_multidim_array_field_bad(d, decls, src, deref(a))
      if mdf != 0 { return multidim_array_field_err(mdf) }
      ## Types §6.1 / Memory — a direct byte-array component gives a tuple its standard byte layout,
      ## but module-global storage remains word-based. Reject the exact explicit global form before any
      ## backend can emit a partial word copy; the local tuple tier and ordinary tuple ABI remain open.
      if sema_standard_tuple_global_bad(d, src) { return standard_tuple_global_err(d.name_start) }
      ca := sema_type_alias_chain_reject(d, decls, i, src)
      if ca != 0 { return ca }
      ## PROPOSAL 7: reject the spec's `[T]` slice spelling in PARAMETER and RETURN positions while the
      ## lower only has the fixed-array ABI for the parser's shared `pmode == 1` representation. Local
      ## `[T]` annotations are deliberately not inspected here; their existing view lowering is correct.
      ss := sema_slice_sugar_reject(d, src)
      if ss != 0 { return ss }
      ## Issue #11 Slice 3a: an unknown bare nominal type in a function parameter/return annotation
      ## must fail before body checking or backend emission. Composite and qualified forms remain on
      ## their dedicated validation paths.
      st := sema_signature_type_reject(d, decls, src)
      if st != 0 { return st }
      ## Types §1/§4.1 + Modules §2: a qualified type argument is a concrete comptime type value whose
      ## declaration identity includes its module. Unknown/unsupported paths are located rejects.
      qg := sema_qualified_generic_reject(d, decls, src)
      if qg != 0 { return qg }
      ## Return the ENCODED error code (kind in the low 2 bits, source start in the rest — the
      ## `CheckErr` encoding) on rejection, so a caller can decode it into a source-located
      ## diagnostic. Any non-zero result is still "reject" (the verdict is unchanged); the caller
      ## normalizes it to the exit-code convention. `3` is the duplicate-name code (kind 3, no span).
      ## kind 3 + the duplicate decl's name offset as the span (§1 item 6 — locate it too, not a bare
      ## "duplicate name"); `name_start * 4` keeps `% 4 == 3` so the kind decodes unchanged.
      if duplicate_decl(d, decls, i, src, a) { return 3 + d.name_start * 4 }
      ## §8 @repr(T) representability — LOCATED reject (mirror of `lower::validate_repr`); user enums only
      ## (lib enums are trusted, exactly as the surrounding is_lib_module skip). Neutral: no `@repr` in src/.
      rr := sema_repr_reject(d, decls, src)
      if rr != 0 { return rr }
      ## Declarations §2.3 — an UNKNOWN `@name` in DECLARATION-PREFIX position (see
      ## `sema_unknown_prefix_attr`). Located at the attribute's own name. User decls only, exactly
      ## like the `@repr` reject above. Neutral for the self-build: every prefix attribute in
      ## `src/`+`lib/` is a §2.3 built-in.
      ua := sema_unknown_prefix_attr(decls, cnt, src, d.name_start)
      if ua != 0 { return unbound_err(ua, 0) }
      cr := check_decl(d, decls, i, src, a)
      match cr {
        Result::Ok(c) => { if c != 0 { return 1 } }
        Result::Err(e) => { return e }
      }
    }
  }
  0
}
