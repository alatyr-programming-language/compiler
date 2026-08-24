## selfhost::lower::collect_slots — the FRAME-SLOT COLLECTOR: one walk of a function body that reserves
## every local's slot (scalars, structs, tuples, arrays, enums, str/slice fat pairs, `dyn` boxes, lifted
## lambda captures) before a single instruction is emitted, so `slot_of` can answer during emit.
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. Everything the walk leans on that is NOT imported below —
## `streq`, `decl_at`, `decl_get`, `is_slice_expr`, the `bind_*_slot` binders, the `*_info` shape
## classifiers, and the `Subst` TYPE — binds `lower.al`'s OWN declaration through the ancestor chain
## (Modules §3 for values, P1-TYPE-ANCESTOR for the type), not an unrelated module's same-named
## private duplicate. `is_slice_expr` (also declared in `wat`) and `streq` (also in six other modules,
## with a DIFFERENT body in `aarch64`) are exactly the names `scripts/callee_module_check.sh` exists to
## keep honest across this boundary.
##
## The band names NO module global and declares NO type — the only thing it needs from the parent is
## the ancestor chain. `collect_slots` is re-imported into `lower.al` by BARE NAME so all 43 call
## sites are unchanged and the boundary stays `@inline`-transparent.
arm_p := ast::arm_p
stmt_p := ast::stmt_p
local_type_span := ast::local_type_span
local_is_uninit := ast::local_is_uninit
(Expr, Stmt, bnd_ns, bnd_nl, bnd_next) := ast
(SVec, arg_expr_at, var_name_span) := lower_ctx
(base_type_name, enum_decl_of, enum_inst_words, is_niche_folded, is_union_decl, struct_decl_of, struct_words, union_words, variant_payload_type) := lower_layout
## SIBLING child, reached by an EXPLICIT qualified path (Modules §4). It was a bare name until the
## place band moved to `src/lower/place.al`; a bare child-to-child call would bind through the
## unique-declaration leniency, which `scripts/callee_module_check.sh` cannot see.
(field_read_agg) := lower::place

pub collect_slots := fn(in out slots : SVec, head : ptr(mut Stmt), src : ptr(u8), decls : ptr(rt::Vec), a : rt::Arena, synth : ptr(mut rt::Arena), sub : ptr(Subst)) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        ## A `name := S(…)` binding gets a struct slot (base + nfields reserved); a
        ## `name := E.V(…)` binding gets an enum slot (base + 1 discriminant + max_arity
        ## payload words reserved); any other value is a scalar single slot.
        ## resolve a module-CONSTANT Var RHS to its value (`p := ORIGIN` / `s := MSG`) so the binding
        ## sizes `p` by the const's struct/str value — the copy rides the existing struct-lit/str-lit path.
        if local_is_uninit(src, ns, nl) {
          if is_module_mut_global(decls, src, ns, nl) == false { bind_uninit_slot(slots, src, ns, nl, decls, a) }
          s = nx
          continue
        }
        mut v := const_rhs(v, decls, src)
        ## A module-level const STRUCT field is not a bare Var, so const_rhs cannot resolve it. Repeat
        ## the same narrow recovery used by emit_st_assign before any slot-shape classifier runs;
        ## otherwise `v := app.version` reserves one scalar word even though its const field is a
        ## two-word str view, and the later call ABI passes `v`'s ptr word instead of its pair address.
        match deref(v) {
          Expr::Field(base, fs, fl) => {
            cv := const_struct_field(base, fs, fl, decls, src, a)
            if unchecked bitcast(usize, cv) != 0 { v = cv }
          }
          _ => {}
        }
        rqa := require_agg_parts(v, decls, src, a)
        si := struct_lit_info(v)
        ei := enum_lit_info(v)
        ti := str_lit_info(v)
        ai := array_lit_info(v)
        if is_module_mut_global(decls, src, ns, nl) {
          ## a write to a MUTABLE module GLOBAL (`COUNTER = …`) — no local slot; the global is
          ## `.data`-addressed by label. (Never a `:=` binding: `mut NAME := …` is a module decl.)
        } else if slot_of(ptr(slots), src, ns, nl) < 0 and local_is_plain_assign(src, ns, nl)
                  and gref_unresolved(decls, src, ns, nl) {
          ## Modules §3 — `NAME = v` where `NAME` is a global of a module this one may not address.
          ## Binding a slot here is what turned a cross-module write into a frame store that smashed
          ## the stack, so reject. A DECLARATION (`NAME := v` / `NAME : T = v`) is excluded above: it
          ## introduces a new local and legitimately shadows the global's spelling.
          reject_gref_unresolved(decls, src, ns, nl)
        } else if local_type_span(src, ns, nl).n != 0 and is_dyn_type(src, local_type_span(src, ns, nl).s, local_type_span(src, ns, nl).n) {
          ## FN-11: `d : dyn fn(…)->R = dyn_over(…)` — a two-word {code, env} fat pair (dormant: src/lib
          ## declare no `dyn` type, so this never fires there → fixpoint-neutral).
          bind_dyn_slot(slots, src, ns, nl)
        } else if fnref_info(v).is_r and stmts_have_dyn_over(head, src, ns, nl, a) {
          ## FN-11: a static-closure STORE `s := fn(…){…}` (lifted to FnRef) consumed by
          ## `dyn_over(ptr(mut s))` — bind `s` as the capture ENV storage (ek 12). The capture COUNT is
          ## the lifted lambda's arity minus the `dyn` type's user-arg count (the captures are the trailing
          ## params d_try_capture appended); reserve that many env words. Fall back to 1 if the dyn local's
          ## type can't be recovered (single-capture, the prior behaviour).
          fr := fnref_info(v)
          nu := dyn_store_nuser(head, src, ns, nl, a)
          lidx := lam_idx_by_fnpos(decls, fr.fnpos)
          mut ncap := 1
          if lidx >= 0 and nu >= 0 {
            larity := deref(decl_get(decls, usize(lidx))).arity
            if i64(larity) > nu { ncap = usize(i64(larity) - nu) }
          }
          bind_dyn_store_slot(slots, src, ns, nl, fr.fnpos, fr.ms, fr.ml, ncap)
        } else if rqa.ok {
          ## `r := R(U(…))` is an aggregate value even though the parser represents the constructor as a
          ## normal Call. Reserve the COMPLETE underlying layout; the require alias is nominally
          ## distinct but layout-identical to U (§8.1). Enum aliases must retain `ek = 3`, otherwise
          ## later match/argument/return consumers see a struct-sized block but lose the tag semantics.
          rk := require_agg_kind(decls, src, rqa.under.s, rqa.under.n)
          rw := require_agg_words(rqa.under, decls, src, a)
          if rk == 3 { bind_enum_slot(slots, src, ns, nl, rqa.under.s, rqa.under.n, rw) }
          else { bind_struct_slot(slots, src, ns, nl, rqa.under.s, rqa.under.n, rw) }
        } else if si.is_s {
          ## Types §9.4: inside a generic INSTANCE a construction head over the callee's own type
          ## parameter (`b := Box(T)(v = x)`) resolves to the instantiation (`Box(P)`) — the raw
          ## `Box(T)` sizes the `v : T` field as ONE word, so the local reserved (and later read) a
          ## truncated aggregate. 0/0 → the raw span, byte-identical, for every other construction.
          gsi := subst_inst_struct_span(si.ss, si.sl, decls, src, synth, sub.gps, sub.gpl, sub.its, sub.itl, sub.gps2, sub.gpl2, sub.its2, sub.itl2, sub.gps3, sub.gpl3, sub.its3, sub.itl3)
          mut sis := si.ss
          mut sin := si.sl
          if gsi.n != 0 { sis = gsi.s ; sin = gsi.n }
          nf := struct_words(decls, src, sis, sin, a)
          bind_struct_slot(slots, src, ns, nl, sis, sin, nf)
        } else if ei.is_e and is_union_decl(decls, src, ei.es, ei.el) {
          ## RAW UNION construction `u := U.m(value)` (spec Types §6.3) — the write form parses as the SAME
          ## variant-ctor `EnumLit` as an enum. Bind a struct-LIKE slot (ek 2) carrying the union TYPE span
          ## and sized by the union's MAX member width (`union_words`, NO discriminant — untagged overlap),
          ## so a later read `u.m` resolves via the struct field path with `field_word_offset → 0` (every
          ## member at offset 0). Dormant for the self-host build (`src/`+`lib/` declare no union).
          bind_struct_slot(slots, src, ns, nl, ei.es, ei.el, union_words(decls, src, ei.es, ei.el, a))
        } else if ei.is_e {
          ## §8 `@niche`: `o : Option(ptr(T)) = Option.Some(p)/Option.None` is NICHE-FOLDED — ONE word
          ## (`None`=0, `Some(p)`=p), no discriminant (Types §6.2/§8, Memory §4.2). The enum LITERAL span
          ## `ei.es` is the BARE `Option` (no type-arg), so recover the payload type from the local's
          ## DECLARED annotation (`local_type_span`); if folded, reserve ONE word and store the FULL span
          ## (`Option(ptr(T))`) as the slot's type so `emit_enum_match`/the Assign construct read the fold.
          ## Non-folded (every corpus enum local) → the byte-identical `[disc, payload]` path below.
          lts := local_type_span(src, ns, nl)
          if lts.n != 0 and is_niche_folded(src, lts.s, lts.n) {
            bind_enum_slot(slots, src, ns, nl, lts.s, lts.n, 1)
          } else {
            ## The enum LITERAL span `ei.es` is the BARE `Option` (no type-arg). When the immediate payload
            ## is itself an AGGREGATE literal (`o := Option.Some(Option.Some(42))`), that bare span loses the
            ## inner type: the slot under-sizes AND a `match o` binds the payload as a SCALAR (its declared
            ## type is the un-substituted param `T`). Recover the full instance type (`Option(Option(T))`) so
            ## the slot sizes correctly and the outer match binds the inner-enum payload as an enum. A SCALAR
            ## payload (the common case) synthesizes nothing → keeps the bare span (byte-identical).
            arg0e := arg_expr_at(enum_lit_full(v).phead, 0, a)
            mut es2 := ei.es
            mut el2 := ei.el
            if enum_lit_full(v).np >= 1 {
              av := var_agg_info(arg0e, ptr(slots), src)
              mut acall := false
              match deref(arg0e) {
                Expr::Call(cs0, cl0, na0, ah0) => { acall = true }
                _ => {}
              }
              if acall { acall = enum_ret_call_d(arg0e, decls, src, a) }
              if enum_lit_full(arg0e).is_e or struct_lit_info(arg0e).is_s or av.ek == 2 or av.ek == 3 or acall {
                ft := synth_lit_type(v, decls, src, a, synth, ptr(slots))
                if ft.n != 0 { es2 = ft.s; el2 = ft.n }
              }
            }
            mut mx := enum_type_payload_words(decls, src, es2, el2, a)
            ## A direct enum literal may carry a complete array payload even when its constructor
            ## span is the bare enum head (`Opt.Some([Row; N])`). Keep the literal-specific answer
            ## as a floor for synthesized/generic contexts without changing scalar enum sizing.
            lapt := enum_lit_array_payload_words(v, decls, src, a)
            if lapt > mx { mx = lapt }
            bind_enum_slot(slots, src, ns, nl, es2, el2, 1 + mx)
          }
        } else if ti.is_s and fixed_array_byte_eek(src, ns, nl) != 0 {
          ## `local : [u8|i8|bits8; N] = embed(...)` is represented by the parser as a StrLit, but
          ## its declared array type selects the packed byte slot. Keep it before the ordinary str
          ## branch so direct indexing, `.len`, address-of, and byte loads use the array ABI.
          lts := local_type_span(src, ns, nl)
          bind_array_slot(slots, src, ns, nl, parse_arr_len(src, lts.s, lts.n), AElem(eek = fixed_array_byte_eek(src, ns, nl), ess = 0, esl = 0, stride = 1))
        } else if ti.is_s {
          ## a `name := "…"` binding gets a str slot (ptr + len = 2 reserved words)
          bind_str_slot(slots, src, ns, nl)
        } else if is_slice_expr(v) and slice_arr_stride(v, ptr(slots), src) != 0 {
          ## a `s := arr[lo..hi]` binding whose base is a raw SCALAR/FLOAT array — a TYPED slice VIEW
          ## (ek 5 is_ref + a runtime len word), NOT a str byte-view, so `s[i]` reads elements (§4).
          sesp := slice_arr_espan(v, ptr(slots), src)
          bind_slice_slot(slots, src, ns, nl, slice_arr_stride(v, ptr(slots), src), slice_arr_eek(v, ptr(slots), src), sesp.s, sesp.n)
        } else if is_sub_call(v, src) or is_strat_call(v, src) or is_bytes_call(v, src) or is_slice_expr(v) {
          ## a `name := sub(s, start, len)` / `str_at(base, len)` / `bytes(x)` / `base[lo..hi]`
          ## binding (a str VIEW) is a str value too — a str slot (ptr + len = 2 reserved words),
          ## like a literal binding.
          bind_str_slot(slots, src, ns, nl)
        } else if ai.is_a {
          ## a `name := [e0, …]` binding gets an array slot (base + nel*stride element words);
          ## the element layout is read from the first literal element (scalar / struct / enum).
          mut aelem := arr_elem_info(ai.ehead, src, decls, a, ptr(slots))
          ## A numeric literal has no scalar type of its own. An explicit `[u8|i8|bits8; N]`
          ## annotation therefore overrides the literal's default word element kind and selects
          ## the byte-packed local storage tier. Inferred `[1, 2, …]` remains the historical word
          ## array and stays fixpoint-neutral.
          beek := fixed_array_byte_eek(src, ns, nl)
          if beek != 0 { aelem = AElem(eek = beek, ess = 0, esl = 0, stride = 1) }
          else if tuple_type_has_byte_component(src, ns, nl) { aelem = AElem(eek = 12, ess = 0, esl = ai.nel, stride = tuple_standard_byte_words(decls, src, ns, nl, a)) }
          bind_array_slot(slots, src, ns, nl, ai.nel, aelem)
        } else if is_cas_call(v, src) {
          ## a `r := atomic::cas_*(…)` binding — reserve `r` as a 2-word tuple `(current, succeeded)`;
          ## the Assign emits `cmpxchg` into the two slots (`r.0` current, `r.1` succeeded 0/1).
          bind_array_slot(slots, src, ns, nl, 2, AElem(eek = 0, ess = 0, esl = 0, stride = 1))
        } else if fixed_array_byte_return_len(v, decls, src, a) >= 1 {
          ## P1-BYTES: a bounded `r := f(…)` where `f` returns `[u8; N]`, 1 <= N <= 8. The
          ## returned %rax word is copied into the same packed byte block used by typed locals, so
          ## `r[k]` reuses the existing byte-address/load path. Wider or non-u8 array returns do not
          ## match and continue to their existing fail-loud scalar/aggregate diagnostics.
          rnel := usize(fixed_array_byte_return_len(v, decls, src, a))
          bind_array_slot(slots, src, ns, nl, rnel, AElem(eek = 8, ess = 0, esl = 0, stride = 1))
        } else if tuple_ret_call(v, decls, src, a) {
          ## a `name := f(…)` binding where `f` returns a TUPLE `(…)` — reserve `name` as an N-word
          ## scalar array (like a tuple LITERAL binding); the components arrive %rax/%rdx/… and are
          ## stored into the N slots. `t.0`/`t.1` then read them via the array-element path.
          bind_array_slot(slots, src, ns, nl, call_ret_tuple_words(v, decls, src, a), AElem(eek = 0, ess = 0, esl = 0, stride = 1))
        } else if str_ret_call(v, decls, src, a) or gen_ret_str_infer(v, ptr(slots), decls, src, a) {
          ## a `name := f(…)` binding where `f` returns a `str` — reserve `name` as a str (ptr + len
          ## = 2 slots); the result arrives ptr/%rax, len/%rdx. WITHOUT this it sized as a scalar
          ## (1 slot), dropping the len + breaking the by-ref str reads of a later use.
          ## `gen_ret_str_infer` is the same binding for a GENERIC callee returning its own type
          ## parameter with the type argument OMITTED and inferred `str` (`t := id(s)`), which the
          ## positional `str_ret_call` cannot see.
          bind_str_slot(slots, src, ns, nl)
        } else if ufcs_ret_struct_span(v, ptr(slots), decls, src, a).n != 0 {
          ## Hunk C: an implicit-UFCS `r := o.unwrap()` / `o.expect(m)` returning a MULTI-WORD struct
          ## payload `T` (recovered from the receiver's slot type, e.g. `Option(Rec)` → `Rec`) — reserve
          ## `r` as that struct so both return words are stored (the emit re-tags the same `unwrap__Rec`
          ## instance). `gen_ret_struct_span` misses it (the UFCS type-arg is the receiver Var, not a struct).
          ucsp := ufcs_ret_struct_span(v, ptr(slots), decls, src, a)
          bind_struct_slot(slots, src, ns, nl, ucsp.s, ucsp.n, struct_words(decls, src, ucsp.s, ucsp.n, a))
        } else if gen_ret_struct_span(v, decls, src, a).n != 0 {
          ## a `p := id(P, …)` where a GENERIC fn returns its type param (substituted to the struct P)
          ## — reserve `p` as that struct; the instance delivers it in the return registers.
          gcsp := gen_ret_struct_span(v, decls, src, a)
          bind_struct_slot(slots, src, ns, nl, gcsp.s, gcsp.n, struct_words(decls, src, gcsp.s, gcsp.n, a))
        } else if gen_ret_sret_span(v, decls, src, a).n != 0 {
          ## a `c := mk(S, …)` where a GENERIC fn returns its type param substituted to a struct TOO WIDE
          ## for the register-return budget (>= 8 words) — reserve `c` as that struct; its ADDRESS is the
          ## instance's hidden %rdi and the callee writes the result straight into these slots (the SRET
          ## dual of the branch above, mirroring the concrete `sret_ret_call` binding). Without it `c` fell
          ## through to a bare SCALAR slot and every field read 0 (a silent miscompile).
          gssp := gen_ret_sret_span(v, decls, src, a)
          bind_struct_slot(slots, src, ns, nl, gssp.s, gssp.n, struct_words(decls, src, gssp.s, gssp.n, a))
        } else if struct_ret_call(v, decls, src, a) {
          ## a `name := f(…)` binding where `f` returns a 2-word struct — reserve `name` as that
          ## struct (2 slots); the result arrives in %rax/%rdx and is stored into the two slots.
          ## When `f` is GENERIC returning `Slice(<typeparam>)` over a STRUCT element (`omap_values ->
          ## Slice(V)`, V a struct), record the SUBSTITUTED span (`Slice(Rec)`) so a later `v := name[i]`
          ## recovers the concrete element for the whole-element copy; a raw/scalar-element call keeps the
          ## declared span (byte-identical) since `subst_slice_ret_span` returns 0/0 for it.
          ## Types §9.4: when `f` is GENERIC returning a generic-struct APPLICATION over its own type
          ## parameter (`mkbox(T, x) -> Box(T)`) called at an AGGREGATE type-arg, record the RESOLVED
          ## application (`Box(P)`) instead — the raw `Box(T)` sizes the payload field as ONE word, so
          ## the binding took one word of a wider value (a silent truncation).
          raw_csp := call_ret_struct_span(v, decls, src, a)
          sub_csp := subst_slice_ret_span(v, decls, src, a, synth, sub.gps, sub.gpl, sub.its, sub.itl, sub.gps2, sub.gpl2, sub.its2, sub.itl2)
          gen_csp := subst_gen_struct_ret_span(v, decls, src, a, synth)
          mut csp_s := raw_csp.s
          mut csp_n := raw_csp.n
          if sub_csp.n != 0 { csp_s = sub_csp.s; csp_n = sub_csp.n }
          if gen_csp.n != 0 { csp_s = gen_csp.s; csp_n = gen_csp.n }
          nf := struct_words(decls, src, csp_s, csp_n, a)
          bind_struct_slot(slots, src, ns, nl, csp_s, csp_n, nf)
        } else if slice_ret_call(v, decls, src, a) {
          ## a `r := f(…)` binding where `f` returns `Slice(T)` BY VALUE (§7.2), the `Slice` type-decl
          ## ABSENT from `decls` (else `struct_ret_call` above owns it, byte-identically) — reserve `r`
          ## as an ek-5 TYPED SLICE (2 words {ptr, len}, `is_ref`, runtime-len marker for a scalar/float
          ## element, or the element type span for a struct/enum element). The call delivers ptr/%rax +
          ## len/%rdx; the Assign emit stores them into the two words. `r.len`/`r[i]`/`for x in r` then
          ## read it exactly like a `s := arr[lo..hi]` view. Without this `r` bound as a BARE SCALAR
          ## (dropping `.ptr`/`.len` → `.len` read 0, `[i]` garbage — the silent-0 miscompile).
          sri := slice_ret_elem(v, decls, src, a, sub.gps, sub.gpl, sub.its, sub.itl, sub.gps2, sub.gpl2, sub.its2, sub.itl2)
          bind_slice_slot(slots, src, ns, nl, sri.stride, sri.eek, sri.ess, sri.esl)
        } else if sret_ret_call(v, decls, src, a) {
          ## a `name := f(…)` binding where `f` returns a struct > 7 words (SRET) — reserve `name` as
          ## that struct; its ADDRESS is passed to the callee as the hidden %rdi, which writes the
          ## result straight into these slots (no register-copy after the call).
          csp := call_ret_struct_span(v, decls, src, a)
          nf := struct_words(decls, src, csp.s, csp.n, a)
          bind_struct_slot(slots, src, ns, nl, csp.s, csp.n, nf)
        } else if call_ret_ty_span(v, decls, src, a).n != 0 and is_niche_folded(src, call_ret_ty_span(v, decls, src, a).s, call_ret_ty_span(v, decls, src, a).n) {
          ## §8 `@niche`: a `o := f(…)` where `f` returns `Option(ptr(T))` — the folded return delivers ONE
          ## word in %rax (see `emit_return_value`), so bind `o` as a 1-word FOLDED slot carrying the
          ## `Option(ptr(T))` type span, so a later `match o` uses the folded dispatch. Placed before the
          ## generic/enum-return branches because a folded return is NOT recognized as an enum
          ## (`enum_decl_of` doesn't resolve the parenthesized instance) — those branches miss it.
          crt := call_ret_ty_span(v, decls, src, a)
          bind_enum_slot(slots, src, ns, nl, crt.s, crt.n, 1)
        } else if gen_ret_enum_span(v, decls, src, a).n != 0 {
          ## a `o := id(Opt, …)` where a GENERIC fn returns its type param (substituted to the enum Opt)
          ## — reserve `o` as that enum; the instance delivers disc/%rax + payload/%rdx.
          gesp := gen_ret_enum_span(v, decls, src, a)
          bind_enum_slot(slots, src, ns, nl, gesp.s, gesp.n, 1 + enum_inst_words(decls, src, gesp.s, gesp.n, a))
        } else if enum_ret_call_d(v, decls, src, a) {
          ## a `name := f(…)` binding where `f` returns an ENUM — reserve `name` as that enum
          ## (disc + max-payload words); the result arrives disc/%rax, payload/%rdx (the passes'
          ## `pr := parse_program(…)` then `match pr`). When `f` is GENERIC and its return enum's
          ## payload is a callee type-PARAM (`wrap -> Opt(T)`), record the SUBSTITUTED span
          ## (`Opt(Pt)`) so the slot is sized + the `match` binds the payload as the concrete type,
          ## not the un-substituted param; a raw (concrete-return) call keeps the declared span
          ## (byte-identical).
          raw_es := call_ret_enum_span_d(v, decls, src, a)
          sub_es := subst_enum_ret_span(v, decls, src, a, synth, sub.gps, sub.gpl, sub.its, sub.itl, sub.gps2, sub.gpl2, sub.its2, sub.itl2)
          mut es_s := raw_es.s
          mut es_n := raw_es.n
          if sub_es.n != 0 { es_s = sub_es.s; es_n = sub_es.n }
          mx := enum_inst_words(decls, src, es_s, es_n, a)
          bind_enum_slot(slots, src, ns, nl, es_s, es_n, 1 + mx)
        } else if try_ok_struct_span(v, decls, src, a).n != 0 {
          ## `x := <call>?` where the callee returns `Result(Struct, E)` — bind `x` as the Ok-payload
          ## STRUCT so `x.field` resolves to `x`'s base (the `?` delivers the payload word 0 there). A
          ## bare-scalar binding made `x.tag` read `base-1` (a stale slot → the type-mismatch miscompile).
          tos := try_ok_struct_span(v, decls, src, a)
          bind_struct_slot(slots, src, ns, nl, tos.s, tos.n, struct_words(decls, src, tos.s, tos.n, a))
        } else if addr_struct_span(v, ptr(slots), src).n != 0 {
          ## a `p := ptr(<struct local>)` binding — record p as a pointer-to-struct (ek 7) carrying
          ## the pointee struct's type, so a later `s := deref(p)` copies the right words.
          asp := addr_struct_span(v, ptr(slots), src)
          bind_ptrstruct_slot(slots, src, ns, nl, asp.s, asp.n)
        } else if addr_ptrptr_struct_span(v, ptr(slots), src).n != 0 {
          ## a `pp := ptr(mut p)` binding where `p` is a pointer-to-struct (ek 7) — a POINTER-TO-POINTER-
          ## to-struct. Bind `pp` as a 1-word scalar carrying the ULTIMATE pointee struct span (eek-1
          ## marker), so `deref(deref(pp)).field` resolves + `p2 := deref(pp)` infers ek-7. A u64/scalar
          ## double pointer (inner `p` not ek 7) never reaches here → binds scalar as before.
          app := addr_ptrptr_struct_span(v, ptr(slots), src)
          bind_ptrptrstruct_slot(slots, src, ns, nl, app.s, app.n)
        } else if deref_ptrptr_pointee_span(v, ptr(slots), src).n != 0 {
          ## a `p2 := deref(pp)` binding where `pp` is a pointer-to-pointer-to-struct (eek-1 marker) —
          ## `deref(pp)` is a `ptr(mut Struct)`, so bind `p2` as an ek-7 pointer-to-struct carrying the
          ## pointee span, so a later `deref(p2).field` resolves. The pointer VALUE (`&Struct`) is stored
          ## 1-word by the scalar Assign emit (deref_struct_span(deref(pp)) is 0 since `pp` is ek 0, so no
          ## struct-copy path fires). The bind-mid dual of the direct `deref(deref(pp)).field`.
          ppp := deref_ptrptr_pointee_span(v, ptr(slots), src)
          bind_ptrstruct_slot(slots, src, ns, nl, ppp.s, ppp.n)
        } else if index_elem_ptrstruct_span(v, ptr(slots), src).n != 0 {
          ## a `p := s[i]` binding where `s` is a POINTER-element slice (eek 7, from a `[ptr(mut b0), …]`
          ## literal) — record `p` as a pointer-to-struct (ek 7) carrying the pointee span, so a later
          ## `deref(p).field` resolves through it (the element's inferred type is `ptr(mut <pointee>)`).
          ## Without this `p` bound scalar and `deref(p).field` read 0. The pointer VALUE stores 1-word
          ## (the scalar Assign emit). The element-read dual of the `p := ptr(x)` / `n := node.next` binds.
          ips := index_elem_ptrstruct_span(v, ptr(slots), src)
          bind_ptrstruct_slot(slots, src, ns, nl, ips.s, ips.n)
        } else if deref_struct_span(v, ptr(slots), src).n != 0 {
          ## a `s := deref(p)` binding where p is a pointer-to-struct — reserve `s` as that struct
          ## (the words are copied in from the arena/pointee — the read dual of the multi-word store).
          dsp := deref_struct_span(v, ptr(slots), src)
          nf := struct_words(decls, src, dsp.s, dsp.n, a)
          bind_struct_slot(slots, src, ns, nl, dsp.s, dsp.n, nf)
        } else if deref_field_struct_span(v, ptr(slots), decls, src, a).n != 0 {
          ## a `ab := deref(v.arena)` binding — the deref'd struct FIELD is a `ptr(mut Struct)`;
          ## reserve `ab` as that pointee struct (the words are copied in from the pointee on emit).
          dfs := deref_field_struct_span(v, ptr(slots), decls, src, a)
          nf := struct_words(decls, src, dfs.s, dfs.n, a)
          bind_struct_slot(slots, src, ns, nl, dfs.s, dfs.n, nf)
        } else if deref_call_struct_span(v, decls, src, a).n != 0 {
          ## a `s := deref(get(T, …))` binding — reserve s as struct T (the call returns a pointer
          ## into the arena; the words are copied in).
          dcs := deref_call_struct_span(v, decls, src, a)
          nf := struct_words(decls, src, dcs.s, dcs.n, a)
          bind_struct_slot(slots, src, ns, nl, dcs.s, dcs.n, nf)
        } else if deref_call_ret_struct_span(v, decls, src, a, sub.gps, sub.gpl, sub.its, sub.itl, sub.gps2, sub.gpl2, sub.its2, sub.itl2).n != 0 {
          ## a `existing := deref(key_at(K, …))` binding inside a generic INSTANCE — the callee returns
          ## `ptr(mut K)`; resolve K to the concrete instance struct + reserve `existing` as it (so the
          ## eq/hash call passes it BY REFERENCE, not as a scalar). Fires only inside an instance.
          drs := deref_call_ret_struct_span(v, decls, src, a, sub.gps, sub.gpl, sub.its, sub.itl, sub.gps2, sub.gpl2, sub.its2, sub.itl2)
          nf := struct_words(decls, src, drs.s, drs.n, a)
          bind_struct_slot(slots, src, ns, nl, drs.s, drs.n, nf)
        } else if deref_call_pointee_unresolved(v, decls, src, a) {
          reject_deref_call_pointee(v, src)
        } else if deref_view_pointee_span(v, ptr(slots), decls, src, a, sub).n != 0 {
          ## P1-CLAYOUT S3(b) — `v := deref(<pointer to a §7 VIEW>)`: the pointee IS the two-word
          ## `{ptr, len}` pair, so `v` is a str LOCAL (2 words), exactly like `v := <str var>`. The
          ## pointer may be a bitcast local, a `ptr(mut str)` annotation, an eek-6 call-derived
          ## pointer local, or the CALL itself (`deref(val_at(K, V, m, a, i))` at `V = str`) — the
          ## pointee is recovered by TYPE-PARAMETER POSITION, never by name. Before this the binding
          ## fell to the SCALAR slot below: one word survived, so `v.len` read the neighbouring slot
          ## and `str_eq(v, …)` compared against a garbage length — a silent wrong value (I11).
          bind_str_slot(slots, src, ns, nl)
        } else if deref_call_enum_span(v, decls, src, a).n != 0 {
          ## a `st := deref(node_ptr(E, …))` binding — reserve `st` as enum E (disc + max-payload
          ## words) so a following `match st` is recognized as an enum match (ek 3); the words are
          ## copied in from the arena pointee on the emit side.
          dce := deref_call_enum_span(v, decls, src, a)
          mx := enum_inst_words(decls, src, dce.s, dce.n, a)
          bind_enum_slot(slots, src, ns, nl, dce.s, dce.n, 1 + mx)
        } else if call_ret_ptrstruct_span(v, decls, src, a).n != 0 {
          ## a `ep := node_ptr(S, …)` / `ep := decl_at(S, …)` binding — record `ep` as a
          ## pointer-to-struct (ek 7) carrying the pointee struct's type, so a later
          ## `eold := deref(ep)` copies the right words and `eold.field` resolves (the AST
          ## list-update path; the pointer itself is stored 1-word by the scalar Assign emit).
          cps := call_ret_ptrstruct_span(v, decls, src, a)
          bind_ptrstruct_slot(slots, src, ns, nl, cps.s, cps.n)
        } else if call_ret_ptrstruct_ret_span(v, decls, src, a).n != 0 {
          ## a `p := get(…)` binding where `get` is a non-generic fn returning `ptr(Struct)` —
          ## record `p` as a pointer-to-struct (ek 7) carrying the pointee struct span, so a later
          ## `deref(p).f` / `p.f` resolves the field through the pointer (§4 pointer-returning calls).
          ## The pointer itself is stored 1-word by the scalar Assign emit (ek 7 is a 1-word pointer).
          crp := call_ret_ptrstruct_ret_span(v, decls, src, a)
          bind_ptrstruct_slot(slots, src, ns, nl, crp.s, crp.n)
        } else if gen_ret_ptrstruct_span(v, decls, src, a).n != 0 {
          ## a `p := get(P, …)` binding where a GENERIC `get` returns `ptr(mut T)` (T → the concrete
          ## struct P) — record `p` as a pointer-to-struct (ek 7) so `deref(p).f` resolves the field
          ## through the pointer. The generic dual of the `call_ret_ptrstruct_ret_span` branch above.
          grp := gen_ret_ptrstruct_span(v, decls, src, a)
          bind_ptrstruct_slot(slots, src, ns, nl, grp.s, grp.n)
        } else if call_view_pointee_bind(v, decls, src, a, sub).n != 0 {
          ## P1-CLAYOUT S3(b) — `slot := dq_elem(T, ptr(d), i)` at `T = str`: a pointer LOCAL whose
          ## pointee is a §7 VIEW. Bind it as the eek-6 marked scalar carrying the RESOLVED pointee
          ## span, so the later `deref(slot) = x` store and `deref(slot)` read move BOTH words. Placed
          ## AFTER every pointer-to-STRUCT branch, so a struct pointee keeps its ek-7 binding.
          cvp := call_view_pointee_bind(v, decls, src, a, sub)
          bind_ptrview_slot(slots, src, ns, nl, cvp.s, cvp.n)
        } else if field_ptrstruct_span(v, ptr(slots), decls, src, a).n != 0 {
          ## a `n := node.next` binding where field `next` is `ptr(Struct)` — record `n` as a
          ## pointer-to-struct (ek 7) carrying the pointee span, so `deref(n).field` resolves through
          ## the pointer (linked-list / tree traversal via a struct ptr field). Without this `n` was a
          ## scalar and `deref(n).field` read `0`. The pointer value stores 1-word (the scalar Assign emit).
          fps := field_ptrstruct_span(v, ptr(slots), decls, src, a)
          bind_ptrstruct_slot(slots, src, ns, nl, fps.s, fps.n)
        } else if var_ptrstruct_span(v, ptr(slots), src).n != 0 {
          ## a `cur := <ptr-to-struct var/param>` binding (e.g. `cur := head`, head a `ptr(Node)` param) —
          ## copy the ek-7 pointee so `deref(cur).field` resolves; the linked-list/tree walk cursor.
          vps := var_ptrstruct_span(v, ptr(slots), src)
          bind_ptrstruct_slot(slots, src, ns, nl, vps.s, vps.n)
        } else if bitcast_struct_target(v, decls, src).n != 0 {
          ## `y := bitcast(<UserStruct>, x)` — the parser-preserved aggregate reinterpret: reserve `y`
          ## as the TARGET struct (so `y.field` resolves against IT, not the source type), and the emit
          ## word-copies the source aggregate's slots (same size — bitcast's contract). Neutral: `src/`
          ## has no user-struct bitcast, so this branch never fires when self-building.
          bts := bitcast_struct_target(v, decls, src)
          bind_struct_slot(slots, src, ns, nl, bts.s, bts.n, struct_words(decls, src, bts.s, bts.n, a))
        } else if bitcast_ptrstruct_span_sub(v, decls, src, a, sub.gps, sub.gpl, sub.its, sub.itl, sub.gps2, sub.gpl2, sub.its2, sub.itl2, sub.gps3, sub.gpl3, sub.its3, sub.itl3).n != 0 {
          ## `vp := unchecked bitcast(ptr(Struct), addr)` (NO type annotation) — record `vp` as a
          ## pointer-to-struct (ek 7) carrying the POINTEE struct span (recovered from the bitcast
          ## TARGET), so a later `p := deref(vp)` copies the right words and `vp.f` / `deref(vp).f`
          ## resolve the aggregate THROUGH the pointer rather than reading zeros. The type-annotated
          ## form is handled by the `local_type_span` branch below; this covers the INFERRED local.
          ## The `_sub` variant also resolves a type-PARAM pointee (`bitcast(ptr(mut V), …)` inside a
          ## generic `OMap(K,V)` method) via the Subst → the omap struct-value shift/store copies whole.
          ## Neutral for src/: its ptr-struct bitcasts are all `ptr(mut usize)` (scalar → 0/0) or handled
          ## unchanged (concrete pointee → same span, no subst).
          bps := bitcast_ptrstruct_span_sub(v, decls, src, a, sub.gps, sub.gpl, sub.its, sub.itl, sub.gps2, sub.gpl2, sub.its2, sub.itl2, sub.gps3, sub.gpl3, sub.its3, sub.itl3)
          bind_ptrstruct_slot(slots, src, ns, nl, bps.s, bps.n)
        } else if var_agg_info(v, ptr(slots), src).ek == 2 {
          ## `x := <struct var>` — reserve `x` as that struct; the emit side word-copies the source.
          va := var_agg_info(v, ptr(slots), src)
          nf := aggregate_words(decls, src, va.s, va.n, a)
          bind_struct_slot(slots, src, ns, nl, va.s, va.n, nf)
        } else if var_agg_info(v, ptr(slots), src).ek == 3 {
          ## `x := <enum var>` — reserve `x` as that enum (disc + max-payload words).
          va := var_agg_info(v, ptr(slots), src)
          mx := enum_inst_words(decls, src, va.s, va.n, a)
          bind_enum_slot(slots, src, ns, nl, va.s, va.n, 1 + mx)
        } else if view_var_kind(v, ptr(slots), src) == 4 {
          ## Types §9.4 — `t := <str var>`: a `str` is a 2-word `{ptr, len}` VIEW, so reserve `t` as a
          ## str LOCAL (both words) exactly like a `t := "…"` / `t := sub(…)` binding. Without this it
          ## fell through to the SCALAR slot below — one word — and the emit stored only the pointer:
          ## `t.len` then read the neighbouring slot (0) and, for a str PARAM source, the stored word
          ## was the caller's pair ADDRESS rather than the data pointer. Both SILENT.
          bind_str_slot(slots, src, ns, nl)
        } else if view_var_kind(v, ptr(slots), src) == 5 and slot_name_is_annotated(src, ns, nl) == false {
          ## §7.2 — `t := <Slice(T) var>`: reserve `t` as a slice VIEW local (2 words {ptr, len}),
          ## carrying the SOURCE slot's element stride / kind / type span so `t.len`, `t[i]` and
          ## `for x in t` read it exactly like the source view. Same silent word-1 drop as above.
          ## (`Slice(u8)`/`Slice(u32)` PARAMS never had the bug: an element type outside the
          ## `known_scalar_slice` set makes `bind_param` fall through to the NOMINAL `Slice` struct
          ## decl — `ek 2` — whose ordinary 2-word struct-var copy path was already correct.)
          vsvn := var_name_span(v)
          vsent := deref(svec_at(SlotEntry, ptr(slots), entry_of(ptr(slots), src, vsvn.s, vsvn.n)))
          bind_slice_slot(slots, src, ns, nl, vsent.estride, vsent.eek, vsent.sns, vsent.snl)
        } else if field_read_agg(v, ptr(slots), decls, src, a).kind == 2 {
          ## `x := s.f` where `f` is a STRUCT field — reserve `x` as that struct; the emit copies the
          ## field's words from the base struct (an aggregate-field extract, not a scalar).
          fa := field_read_agg(v, ptr(slots), decls, src, a)
          bind_struct_slot(slots, src, ns, nl, fa.s, fa.n, struct_words(decls, src, fa.s, fa.n, a))
        } else if field_read_agg(v, ptr(slots), decls, src, a).kind == 3 {
          ## `x := s.f` where `f` is an ENUM field — reserve `x` as that enum (disc + max-payload).
          fa := field_read_agg(v, ptr(slots), decls, src, a)
          bind_enum_slot(slots, src, ns, nl, fa.s, fa.n, 1 + enum_inst_words(decls, src, fa.s, fa.n, a))
        } else if field_read_agg(v, ptr(slots), decls, src, a).kind == 4 {
          ## `x := s.f` where `f` is a `str` field — reserve `x` as a str LOCAL (ptr + len = 2 words,
          ## ek 4), so `x.len` / `x.ptr` / `x[i]` read it like any other str; the emit copies BOTH of
          ## the field's words in. Was a scalar slot → word 0 only, `x.len` read 0 (silent).
          bind_str_slot(slots, src, ns, nl)
        } else if global_field_agg(v, decls, src, a).kind == 2 {
          ## `x := STATE.f` (STATE a global struct, f a STRUCT field) — reserve x as that struct.
          ga := global_field_agg(v, decls, src, a)
          bind_struct_slot(slots, src, ns, nl, ga.s, ga.n, struct_words(decls, src, ga.s, ga.n, a))
        } else if global_field_agg(v, decls, src, a).kind == 3 {
          ## `x := STATE.f` (STATE a global struct, f an ENUM field) — reserve x as that enum.
          ga := global_field_agg(v, decls, src, a)
          bind_enum_slot(slots, src, ns, nl, ga.s, ga.n, 1 + enum_inst_words(decls, src, ga.s, ga.n, a))
        } else if is_mut_struct_global_var(v, decls, src) {
          ## `p := STATE` — RHS is a mutable STRUCT global; reserve `p` as that struct (the emit side
          ## word-copies the CURRENT `.data` cells — a runtime snapshot, not the compile-time init).
          gsli := struct_lit_info(mut_global_value(decls, src, var_name_span(v).s, var_name_span(v).n))
          bind_struct_slot(slots, src, ns, nl, gsli.ss, gsli.sl, struct_words(decls, src, gsli.ss, gsli.sl, a))
        } else if is_mut_enum_global_var(v, decls, src) {
          ## `s := STATE` — RHS is a mutable ENUM global; reserve `s` as that enum (disc + max-payload
          ## words); the emit copies its `.data` words in (a snapshot). A following `match s` then works.
          geli := enum_lit_info(mut_global_value(decls, src, var_name_span(v).s, var_name_span(v).n))
          bind_enum_slot(slots, src, ns, nl, geli.es, geli.el, 1 + enum_inst_words(decls, src, geli.es, geli.el, a))
        } else if bin_operator_ret_struct(v, decls, src, ptr(slots), a).n != 0 {
          ## `r := a <op> b` where `<op>` is a user operator RETURNING a struct (`@inline` or the
          ## non-inline fallback) — reserve `r` as that struct so `r.field` resolves (the routed
          ## operator delivers word 0; a 1-word struct is stored like a scalar). `src/`'s scalar Bins
          ## never match → neutral.
          brs := bin_operator_ret_struct(v, decls, src, ptr(slots), a)
          bind_struct_slot(slots, src, ns, nl, brs.s, brs.n, struct_words(decls, src, brs.s, brs.n, a))
        } else {
          ## a `name := arr[i]` of an AGGREGATE-element array binds `name` as that aggregate
          ## (a whole-element READ into a struct/enum local); any other value is a scalar slot.
          ivl := index_value_layout(v, ptr(slots), src, decls, a)
          if ivl.is_agg and ivl.eek == 2 {
            nf := struct_words(decls, src, ivl.ess, ivl.esl, a)
            bind_struct_slot(slots, src, ns, nl, ivl.ess, ivl.esl, nf)
          } else if ivl.is_agg and ivl.eek == 3 {
            mx := enum_inst_words(decls, src, ivl.ess, ivl.esl, a)
            bind_enum_slot(slots, src, ns, nl, ivl.ess, ivl.esl, 1 + mx)
          } else if ivl.is_agg and ivl.eek == 4 {
            ## a `name := strs[i]` whole-element read of a str-array binds `name` as a str local
            ## (2 words); emit_elem_copy_in copies the {ptr, len} pair into its slots.
            bind_str_slot(slots, src, ns, nl)
          } else if match_if_agg_kind(v, decls, src, a).kind != 0 {
            ## a `name := match/if { … => <agg/str> }` binding — size `name` by the value's kind
            ## (struct/enum/tuple/str); the Assign emit delivers each arm/branch's value into its slots.
            mak := match_if_agg_kind(v, decls, src, a)
            if mak.kind == 2 { bind_struct_slot(slots, src, ns, nl, mak.s, mak.n, struct_words(decls, src, mak.s, mak.n, a)) } else {
              if mak.kind == 3 { bind_enum_slot(slots, src, ns, nl, mak.s, mak.n, 1 + enum_inst_words(decls, src, mak.s, mak.n, a)) } else {
                if mak.kind == 5 { bind_array_slot(slots, src, ns, nl, mak.nel, arr_elem_info(mak.ehead, src, decls, a, ptr(slots))) } else {
                  bind_str_slot(slots, src, ns, nl)
                }
              }
            }
          } else if value_is_float(v, ptr(slots), src, decls, a) or float_ret_call(v, decls, src) {
            ## a `name : f64 = …` / `name := f64(…)` / float-arithmetic / `name := floatfn(…)`
            ## binding — one word, ek 9. (A float-RETURNING call delivers in %xmm0; the scalar store
            ## reads it back via `emit_gas`, which moves %xmm0→%rax for such a call.)
            bind_float_slot(slots, src, ns, nl)
          } else {
            lts := local_type_span(src, ns, nl)
            if lts.n != 0 {
              ## a `p : ptr(<opt mut> Struct) = …` local (e.g. `bitcast(ptr(Pt), addr)`): bind as a
              ## POINTER-TO-STRUCT (ek 7) carrying the POINTEE struct span, so `p.f` / `p.f = v`
              ## resolve through the pointer (the down-growing pointee layout) rather than as a bare
              ## scalar whose fields collapse onto p's own slot. Preserves the pointee type that a
              ## bitcast-to-`ptr(Struct)` established. A non-struct-pointer annotation stays ek 0.
              pps := ptr_pointee_struct_span(src, lts.s, lts.n, decls, a)
              ## A DECLARED `x : f64 = …` / `x : f32 = …` local binds as a FLOAT slot (ek 9) so a later
              ## `u64(x)` TRUNCATES the float instead of reading its raw IEEE bits as an integer. The
              ## value-driven classification above misses it when the initializer is an INDIRECT call
              ## through a fn VALUE (which has no `Decl` to read a return type from — FN-6). `src/`
              ## declares no `: f64`/`: f32` local, and every `lib/` one has a float-valued RHS already
              ## classified above, so this reclassifies nothing that built before → fixpoint-neutral.
              ltn := str_at((src + lts.s), lts.n)
              if ltn == "f64" or ltn == "f32" { bind_float_slot(slots, src, ns, nl) } else {
                if pps.n != 0 { bind_ptrstruct_slot(slots, src, ns, nl, pps.s, pps.n) }
                else { bind_slot_typed(slots, src, ns, nl, lts.s, lts.n) }
              }
            }
            else {
              ## No declared type — INFER the scalar type from the init (`x := f(…)` / `x := T(y)` /
              ## `x := <var>`) and record it, so `x`'s arithmetic routes to num.al's guarded operators
              ## (widening checked coverage). 0/0 → leave untyped (direct wrapping lowering, as before).
              its := infer_local_scalar_type(v, ptr(slots), decls, src, a)
              if its.n != 0 { bind_slot_typed(slots, src, ns, nl, its.s, its.n) }
              else { bind_slot(slots, src, ns, nl) }
            }
          }
        }
        s = nx
      }
      Stmt::While(c, b, nx) => {
        collect_slots(slots, b, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::Loop(b, nx) => {
        collect_slots(slots, b, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::Unchecked(b, nx) => {
        collect_slots(slots, b, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::AllocWith(ae, b, nx) => {
        collect_slots(slots, b, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      ## A bare expression statement (a call evaluated for effect, result discarded) introduces
      ## no new local — no slot is reserved.
      Stmt::ExprStmt(e, nx) => { s = nx }
      ## A struct field mutation `var.field = e` introduces no new local — the base var was
      ## already bound (as a struct local) by an earlier `Assign`, so no slot is reserved.
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => {
        s = nx
      }
      ## A nested-field store `o.i.v = e` introduces no new local (base + value are read, not bound).
      Stmt::FieldPathAssign(pl, fpv, nx) => {
        s = nx
      }
      ## An early `return e` introduces no new local (the value expr is read, not bound).
      Stmt::Return(rv, nx) => {
        s = nx
      }
      ## A `deref(p) = v` store introduces no new local (the pointer + value are read).
      Stmt::DerefAssign(ptr, val, nx) => {
        s = nx
      }
      ## An `arr[i] = v` write introduces no new local — the array local was already bound (by
      ## an earlier `Assign` of an array literal), and the index + value are read, not bound.
      Stmt::IndexAssign(ib, ii, iv, nx) => {
        s = nx
      }
      ## An `a[i].f = v` element-field write introduces no new local (the array local was bound
      ## by an earlier `Assign`; the index + value are read, not bound).
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => {
        s = nx
      }
      ## A statement-position `if` / `match`: recurse into the branch / arm body statement
      ## lists so any locals THEY introduce (an `Assign` inside a branch) get a frame slot.
      ## The branches share the function frame (no per-block scoping in this slice).
      Stmt::If(c, th, el, nx) => {
        collect_slots(slots, th, src, decls, a, synth, sub)
        collect_slots(slots, el, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::Match(sc, ah, nx) => {
        ## Resolve the scrutinee's enum type (a `Var` slot ek 3), then for each arm bind a SINGLE
        ## struct/enum-typed payload binding as a REAL aggregate slot (ek 2/3) with its resolved type — so a
        ## `j := <payload binding>` inside the arm infers the payload's aggregate type (var_agg_info reads ek
        ## + type span) instead of a scalar slot (a later `match j` would then read only word 0 → wrong arm).
        ## `emit_match` re-aliases each payload binding per arm (last-wins), so this reservation is unused at
        ## emit on every backend — it only feeds collect-time slot typing. Bound before each arm's recursion;
        ## left in the map (payload names are arm-local). Multi-binding / scalar payloads keep the scalar path.
        msc := var_name_span(sc)
        mut mes := 0
        mut mel := 0
        if msc.n != 0 {
          ment := deref(svec_at(SlotEntry, slots, entry_of(slots, src, msc.s, msc.n)))
          if streq(src, ment.ns, ment.nl, msc.s, msc.n) and ment.ek == 3 { mes = ment.sns; mel = ment.snl }
        }
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          if mes != 0 {
            mut mnb := 0
            mut mcb := am.binds_head
            while unchecked bitcast(usize, mcb) != 0 { mnb = mnb + 1; mcb = bnd_next(mcb) }
            if mnb == 1 {
              mpty := variant_payload_type(decls, src, mes, mel, am.vs, am.vl, a)
              if mpty.n != 0 {
                mbh := am.binds_head
                mpbn := base_type_name(src, mpty.s, mpty.n)
                if struct_decl_of(decls, src, mpbn.s, mpbn.n) >= 0 { bind_struct_slot(slots, src, bnd_ns(mbh), bnd_nl(mbh), mpty.s, mpty.n, struct_words(decls, src, mpty.s, mpty.n, a)) }
                else if enum_decl_of(decls, src, mpbn.s, mpbn.n) >= 0 { bind_enum_slot(slots, src, bnd_ns(mbh), bnd_nl(mbh), mpty.s, mpty.n, 1 + enum_inst_words(decls, src, mpty.s, mpty.n, a)) }
              }
            }
          }
          collect_slots(slots, am.body_stmts, src, decls, a, synth, sub)
          arm = am.next
        }
        s = nx
      }
      ## A `for i in lo .. hi { body }` introduces the loop variable `i` as a scalar local
      ## (its own frame slot), then recurses into the body for any locals THAT introduces.
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        ## The loop var: an element of a FLOAT array (`ek==5, eek==9`) iterates as a float local
        ## (`ek==9`, the xmm path); otherwise a plain scalar slot. Only the iterable form (fhi==0)
        ## has a Var iterable to inspect; a range-`for`'s `flo` is the lo bound.
        mut lv_float := false
        mut lv_agg : u8 = 0        ## 2 = struct-element array, 3 = enum-element array (the loop var is that aggregate)
        mut lv_str := false        ## a str-ELEMENT slice/array (eek 4): the loop var is a 2-word str
        mut lv_es := 0
        mut lv_el := 0
        if unchecked bitcast(usize, fhi) == 0 {
          fbv := var_name_span(flo)
          ## a global ARRAY iterable (`for e in ARR`, ARR a `mut` array global) has NO frame slot — check
          ## it FIRST and bind the loop var from the ArrayLit's first element (a STRUCT element → an
          ## aggregate loop var; a scalar element leaves lv_agg 0 → scalar). Reading a slot for it (the
          ## `else`) would deref entry_of == -1 = garbage.
          gmgv := if fbv.n != 0 { mut_global_value(decls, src, fbv.s, fbv.n) } else { unchecked bitcast(ptr(Expr), 0) }
          if unchecked bitcast(usize, gmgv) != 0 and array_lit_info(gmgv).is_a {
            gesli := struct_lit_info(arg_expr_at(array_lit_info(gmgv).ehead, 0, a))
            if gesli.is_s { lv_agg = 2; lv_es = gesli.ss; lv_el = gesli.sl }
          } else if fbv.n != 0 {
            fse := deref(svec_at(SlotEntry, slots, entry_of(slots, src, fbv.s, fbv.n)))
            if fse.ek == 5 and fse.eek == 9 { lv_float = true }
            if fse.ek == 5 and fse.eek == 2 { lv_agg = 2; lv_es = fse.sns; lv_el = fse.snl }
            if fse.ek == 5 and fse.eek == 3 { lv_agg = 3; lv_es = fse.sns; lv_el = fse.snl }
            ## a str-element slice VIEW LOCAL (`for x in strs[lo..hi]`, eek 4 is_ref sns==0): the loop var
            ## is a 2-word str. Gated exactly like the emit's `is_str_slice` so a plain `[str; N]` array
            ## for-loop (eek 4, NOT is_ref) is unchanged.
            if fse.ek == 5 and fse.eek == 4 and fse.is_ref and fse.sns == 0 { lv_str = true }
          }
        }
        if lv_agg == 2 { bind_struct_slot(slots, src, fns, fnl, lv_es, lv_el, struct_words(decls, src, lv_es, lv_el, a)) } else {
          if lv_agg == 3 { bind_enum_slot(slots, src, fns, fnl, lv_es, lv_el, 1 + enum_inst_words(decls, src, lv_es, lv_el, a)) } else {
            if lv_str { bind_str_slot(slots, src, fns, fnl) } else {
              if lv_float { bind_float_slot(slots, src, fns, fnl) } else { bind_slot(slots, src, fns, fnl) }
            }
          }
        }
        ## ITERABLE `for x in <slice>` (fhi == 0): reserve a hidden loop-index slot immediately after
        ## the loop var (the lower reads it at `slot_of(x) + 1`). Range-`for` (fhi != 0) reserves nothing.
        ## For a NON-VAR iterable (`for x in f()` / `for c in bytes(s)` — a call/expr, not a Var) also
        ## reserve a 2-word {ptr,len} MATERIALIZATION temp (at `slot_of(x)+2 .. +3`) so the iterable is
        ## evaluated ONCE before the loop into a place the counted loop reads (one-time materialization).
        if unchecked bitcast(usize, fhi) == 0 {
          ioff := svec_len(ptr(slots))
          svec_push(slots, SlotEntry(ns = 0, nl = 0, off = ioff, sns = 0, snl = 0, ek = 0, estride = 1, eek = 0, is_ref = false))
          if var_name_span(flo).n == 0 {
            tpo := svec_len(ptr(slots))
            svec_push(slots, SlotEntry(ns = 0, nl = 0, off = tpo, sns = 0, snl = 0, ek = 0, estride = 1, eek = 0, is_ref = false))
            tlo := svec_len(ptr(slots))
            svec_push(slots, SlotEntry(ns = 0, nl = 0, off = tlo, sns = 0, snl = 0, ek = 0, estride = 1, eek = 0, is_ref = false))
          }
        }
        collect_slots(slots, fb, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::CompIf(ccond, cthen, celse, nx) => {
        collect_slots(slots, cthen, src, decls, a, synth, sub)
        collect_slots(slots, celse, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::CompFor(cvs, cvl, civ, cb, nx) => {
        collect_slots(slots, cb, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => {
        ## `comptime for i in lo .. hi { body }` — the loop var `i` is a scalar local set to each
        ## constant during the unroll; reserve its slot, then collect the body's locals (the body is
        ## emitted once per iteration into these same slots).
        rb0 := bind_slot(slots, src, rvs, rvl)
        collect_slots(slots, rb, src, decls, a, synth, sub)
        s = nx
      }
      Stmt::CompMatch(cmsc, cmah, nx) => {
        mut car := cmah
        while car != 0 { cam := deref(arm_p(car)); collect_slots(slots, cam.body_stmts, src, decls, a, synth, sub); car = cam.next }
        s = nx
      }
    }
  }
}
