## selfhost::aarch64 (backend breadth), item 2: aarch64 (AArch64 / ARM64 Linux GAS).
##
## A backend against the SAME parsed `Decl` model the x86_64 lower and the WASM backend consume.
## Scope: the scalar kernel (functions, up to 8 i64 params, local `:=` + reassignment, literals,
## params/locals/scalar-globals, arithmetic/comparison/bitwise/boolean Bin, value + statement `if`,
## `while`, direct calls, `return`, call-as-statement) PLUS scalar-field value STRUCTS in the frame
## (construct `p := S(f=…)`, field read `p.f`, field write `p.f = v`). It emits a `.global _start`
## that calls `main` and turns the x0 result into the AArch64 `exit` syscall (nr 93 in x8); assembled
## by `aarch64-unknown-linux-gnu-{as,ld}` and run under `qemu-aarch64`, the exit code is checked like
## the native x86_64 / wasmtime paths.
##
## CODEGEN MODEL: a naive STACK MACHINE — every expression computes into x0; a binary op pushes lhs,
## evaluates rhs into x0, pops lhs (rhs → x1), combines. The frame holds params (1 word each) then
## locals; a struct local occupies `struct_words` CONTIGUOUS words (variable-size slots) and its fields
## are accessed directly at `[x29, #(base_off + field_word_offset*8)]` — no separate base pointer.
## Anything outside the supported set (struct params/return/copy, enums, arrays, strings, enum match, nested
## new `:=`, >8 args, generics, multi-word struct fields) emits `brk #0` — a fail-loud trap (SIGTRAP →
## exit 133 under qemu), never a silently-wrong result.
##
## ADDITIVE: nothing in the self-build invokes `emit_a64_program`, so the x86_64 GAS the tree emits for
## itself is byte-for-byte unchanged and the TOOL-1 fixpoint (seed==Stage1==Stage2) is unaffected.
##
## Lean-lower discipline (each cost a mis-lower once): NO top-level `else if` chain as a fn body (reads
## as a tail value-if — use standalone ifs + a flag); NO inline fn call as an `if` condition or str arg
## (bind to a local); NO nested if/else inside a match arm (keep arm bodies FLAT — standalone ifs with
## compound conditions + `mut` flags); NO `return <nested-call>` (use a `mut` accumulator). A helper may
## take >6 params (verified), but a NEW struct RETURN type mis-lowers under the frozen seed → resolve
## struct-type spans via separate usize accessors, never a returned struct.
(Arg, Arm, Bind, Decl, Expr, FieldDecl, Param, Stmt, local_is_mut) := ast
(bnd_ns, bnd_nl, bnd_next) := ast
fld_p := ast::fld_p
param_p := ast::param_p
arm_p := ast::arm_p
arg_p := ast::arg_p
stmt_p := ast::stmt_p
(push_str, push_int) := rt
(layout_kind, layout_kind_is_packed, layout_kind_is_byte, struct_decl_of, struct_words, field_word_offset, field_words, standard_field_byte_offset, layout_field_offset_bytes, layout_elem_stride_bytes, array_elem_word_reservation, std_array_elem_byte_tier, std_struct_is_byte_writable, std_struct_is_word_granular, standard_type_byte_size, scalar_byte_size, std_struct_has_direct_byte_layout, packed_field_byte_offset, std_copy_kind, std_copy_image_bytes, layout_copy_nsteps, layout_copy_step, require_no_byte_layout_array_elem) := lower_layout
(enum_decl_of, variant_index, enum_max_arity, enum_inst_words) := lower_layout
(typearg_at, base_type_name) := lower_layout
(ann_tok_stop, scalar_name_is_signed, scalar_name_is_unsigned, scalar_name_is_float, scalar_name_narrow, scalar_name_is_int_conv) := lower_layout
(ann_scan_signed, ann_scan_unsigned, ann_scan_narrow, ann_scan_float) := lower_layout
(param_ann_signed, param_ann_unsigned, named_param_is_float, callee_ret_is_float) := lower_layout
(ct_kind_of_name, ct_num_kind_of_name, ct_scalar_num_kind, ct_type_kind, std_ty_aggregate, struct_plain, ty_is_scalar) := lower_layout
(decl_tparam_count, decl_tparam_pos, decl_leading_tparam_run, generic_gi, gen_call_ok, param_tuple_open_at, param_tuple_allscalar_n, arrty_semi, arg_list_count) := lower_layout
(ex_is_index, ex_index_base, ex_index_idx, ex_is_field, ex_is_num_lit, ex_is_zero_lit) := lower_layout
(ex_var_ns, ex_var_nl, ex_call_argh, ex_struct_lit_args, ex_enum_lit_args, ex_is_array_lit, ex_array_lit_ehead, ex_is_slice, ex_slice_base, ex_slice_lo, ex_slice_hi) := lower_layout
(ex_value_is_scalar, ex_value_init, ex_is_cmp_op, ex_is_no_tail, str_esc_byte, dec_digit_val, bind_list_index) := lower_layout
(arch_rhs_span, arch_guard_fold, apply_when_guards) := lower_layout
variant_payload_type := lower_layout::variant_payload_type
field_type_is_float := lower_layout::field_type_is_float

## TOOL-5 cross-target mode. The ordinary backend keeps its historical `main` wrapper; the selected
## package `test` target asks for a small AArch64 runner instead. The runner's filter facts arrive as
## scalars because the driver deliberately does not pass a test-selection aggregate across modules.
mut A64_TEST_MODE : bool = false
mut A64_TEST_FILTER_P : usize = 0
mut A64_TEST_FILTER_N : usize = 0
mut A64_TEST_KEEP : bool = false
mut A64_TEST_DECL_INDEX : usize = 0
pub set_cross_test_mode := fn(mode : usize) -> i64 {
  A64_TEST_MODE = mode != 0
  return 0
}
pub set_cross_test_filter := fn(p : usize, n : usize) -> i64 {
  A64_TEST_FILTER_P = p
  A64_TEST_FILTER_N = n
  return 0
}
pub set_cross_test_options := fn(keep : usize) -> i64 {
  A64_TEST_KEEP = keep != 0
  return 0
}
## MOD §6.3/§7.2 — the source-scan symbol helpers shared with the x86_64 lower: `@export("sym")` alias
## + `@extern("sym")` external symbol (both recover the attribute from source, no Decl field). `CSpan`
## is their span-result type. Reused (not duplicated) so the aarch64/x86_64 symbol rules stay identical.
(CSpan, decl_at, decl_get, node_ptr, streq, param_find, is_slice_local, arrty_nel, sub_arr_len, ann_span, expr_is_struct_lit, expr_struct_lit_ns, expr_struct_lit_nl, expr_field_base, expr_field_name_s, expr_field_name_l, expr_is_enum_lit, expr_enum_lit_ns, expr_enum_lit_nl, expr_enum_variant_ns, expr_enum_variant_nl, expr_is_str_lit, expr_str_lit_ns, expr_str_lit_nl, expr_str_lit_label, expr_call_name_ns, expr_call_name_nl) := lower_ctx
(export_name, extern_symbol, field_type_span, compfor_iter_arg, fixed_array_byte_return_len, fixed_array_byte_return_len_span) := lower

handle_id := fn(e : ptr(Expr)) -> i64 { i64(unchecked bitcast(usize, e)) }

## PER-EMISSION MONOTONIC LABEL COUNTER (the a64 analogue of x86 lower.al's `nl`). Label ids were
## historically derived from a STABLE AST handle (`handle_id`/`i64(ar)`), which is unique per source
## node but IDENTICAL across the N re-emissions a comptime unroll (`comptime for … { match/if/loop }`)
## produces — so a label-bearing subtree emitted once per unroll iteration would collide (the assembler
## rejects "symbol already defined"). Fetching a FRESH counter value at every label-bearing construct
## instead gives each (re-)emission its own disjoint label set. Deterministic: a single never-reset
## global advanced in fixed emission order yields byte-identical GAS for identical source (fixpoint /
## Stage2==Stage3 safe); global across the whole file, so labels stay unique between functions too.
## A64 emit is dormant in the x86 self-build, so this global never advances there (x86 fixpoint neutral).
mut A64_NL := 0
a64_next_label := fn() -> i64 { r := A64_NL ; A64_NL = A64_NL + 1 ; r }

count_params := fn(params_head : ptr(mut Param), a : rt::Arena) -> i64 {
  mut p := params_head
  mut k := 0
  while p != 0 { pm := deref(param_p(p)) ; k = k + 1 ; p = pm.next }
  i64(k)
}

## Single-match `If` accessors — `is` + the then-branch expr. A struct-valued if-EXPRESSION
## (`x := if c {f()} else {g()}`) delivers its value through the branch tails; when each tail is a
## struct-returning call the branches leave the struct words in x0..x_(w-1), exactly like the tail of a
## struct-returning fn — so the binding path sizes/delivers it via the then-branch's return span (below).
a64_is_if := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::If(c, t, f) => { r = true } _ => {} }
  r
}
a64_if_then := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(e) { Expr::If(c, t, f) => { r = t } _ => {} }
  r
}
a64_if_cond := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(e) { Expr::If(c, t, f) => { r = c } _ => {} }
  r
}
a64_if_else := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(e) { Expr::If(c, t, f) => { r = f } _ => {} }
  r
}
## Single-match `Match`-EXPRESSION accessors — `is`, the scrutinee expr, the arm-list head. A struct-
## valued match-EXPRESSION (`p := match o { A => S(…), B => S(…) }`) is the match dual of the if-expr:
## dispatch on the enum scrutinee, each arm delivers a struct value into x0..x_(w-1), and the binding
## stores those words into p's slots. Delivery reuses emit_a64_struct_value (below).
a64_is_match := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::Match(sc, ah) => { r = true } _ => {} }
  r
}
a64_match_scrut := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(e) { Expr::Match(sc, ah) => { r = sc } _ => {} }
  r
}
a64_match_armh := fn(e : ptr(Expr)) -> ptr(mut Arm) {
  mut r : ptr(mut Arm) = unchecked bitcast(ptr(mut Arm), 0)
  match deref(e) { Expr::Match(sc, ah) => { r = ah } _ => {} }
  r
}
## True IFF every arm of a match-EXPRESSION is a SIMPLE variant/wildcard arm with an EXPRESSION body
## (no statement-body arm, no `comptime for` variant-template arm wild∈{2,3}) — the shapes the struct
## value-match path below can deliver. Anything else keeps the caller's fail-loud `brk`.
a64_match_arms_simple := fn(head : ptr(mut Arm)) -> bool {
  mut ar := head
  mut ok := true
  while ar != 0 {
    am := deref(arm_p(ar))
    if am.body_stmts != 0 { ok = false }
    if am.wild == 2 { ok = false }
    if am.wild == 3 { ok = false }
    ar = am.next
  }
  ok
}



## THIS BACKEND'S OWN ARCH IDENTITY (Tooling §2.7). `target.*` is the RESOLVED SELECTED machine model —
## the machine being compiled FOR — so when this emitter runs, `target.arch` IS `Arch.aarch64`. It used
## to fold as `x86_64` "so the sweep compares like-for-like", which made `target.arch == Arch.x86_64`
## TRUE while emitting aarch64 instructions: a conformance defect that also made every library arch gate
## inert. ONE accessor so the `comptime if` fold and the `when`-guard fold can never drift apart.
a64_target_arch := fn() -> str { "aarch64" }


a64_comp_cond_fold := fn(cond : ptr(Expr), src : ptr(u8)) -> i64 {
  mut r := 0 - 1
  match deref(cond) {
    Expr::Bin(op, l, rr) => {
      an := arch_rhs_span(rr, src)
      if an.n != 0 {
        eq := str_at((src + an.s), an.n) == a64_target_arch()
        if op == 20 { if eq { r = 1 } else { r = 0 } }
        if op == 28 { if eq { r = 0 } else { r = 1 } }
      }
      ## TYPE-name equality `T == <type>` / `T != <type>` inside a mono INSTANCE (A64_SUB active,
      ## §8): the LHS names the instance's type-param, the RHS is a (bare) type name → compare the
      ## concrete instance type's base name. Mirrors the x86 `comptime_cond_eval` type-eq arm.
      if an.n == 0 and (op == 20 or op == 28) and A64_SUB_GPL != 0 {
        lvs := ex_var_ns(l)
        lvn := ex_var_nl(l)
        rvs := ex_var_ns(rr)
        rvn := ex_var_nl(rr)
        if lvn != 0 and rvn != 0 and streq(src, lvs, lvn, A64_SUB_GPS, A64_SUB_GPL) {
          itb := base_type_name(src, A64_SUB_ITS, A64_SUB_ITL)
          teq := streq(src, itb.s, itb.n, rvs, rvn)
          if op == 20 { if teq { r = 1 } else { r = 0 } }
          if op == 28 { if teq { r = 0 } else { r = 1 } }
        }
      }
      if an.n == 0 and op == 42 {
        lv := a64_comp_cond_fold(l, src)
        if lv == 1 { r = 0 }
        if lv == 0 { r = 1 }
      }
      if an.n == 0 and op == 40 {
        lv := a64_comp_cond_fold(l, src)
        rv := a64_comp_cond_fold(rr, src)
        if lv == 0 or rv == 0 { r = 0 }
        if lv == 1 and rv == 1 { r = 1 }
      }
      if an.n == 0 and op == 41 {
        lv := a64_comp_cond_fold(l, src)
        rv := a64_comp_cond_fold(rr, src)
        if lv == 1 or rv == 1 { r = 1 }
        if lv == 0 and rv == 0 { r = 0 }
      }
    }
    ## `verify.checked` (CT-11): the current verification mode (A64_CHK — checked by default, cleared
    ## inside `unchecked {}`). Mirrors x86 `comptime_cond_eval`'s `cx.vchk` arm so a `comptime if
    ## verify.checked` predicate folds identically on both backends.
    Expr::Field(b, fs, fl) => {
      if ex_var_nl(b) != 0 and str_at((src + ex_var_ns(b)), ex_var_nl(b)) == "verify" {
        if A64_CHK { r = 1 } else { r = 0 }
      }
    }
    ## `match typeinfo(T) { <Kind>(_) => true; _ => false }` used as a comptime-if CONDITION (§8): fold
    ## by T's KIND inside a mono INSTANCE (A64_SUB active). The FIRST arm's variant name is the tested
    ## kind; a match → 1, else 0. Mirrors x86 `comptime_cond_eval`'s `Match` arm. `a64_decls()` supplies
    ## decls (set per-fn in `emit_a64_fn`, always live during body emit).
    Expr::Match(scrut, arms_head) => {
      if A64_SUB_ITL != 0 {
        kind := ct_type_kind(A64_SUB_ITS, A64_SUB_ITL, a64_decls(), src)
        am := deref(arm_p(arms_head))
        if am.vl != 0 {
          want := ct_kind_of_name(src, am.vs, am.vl)
          if want >= 0 { if kind == want { r = 1 } else { r = 0 } }
        }
      }
    }
    _ => {}
  }
  r
}



## The struct-type name (start / len via two accessors) of the LOCAL `[ns,nl]` — taken from its
## first `:=` whose value is a StructLit; 0/0 if the local is not a struct.
a64_local_struct_ns := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := head
  mut rs := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and expr_is_struct_lit(v) { rs = expr_struct_lit_ns(v) ; done = true }
        ## a local bound to a struct-RETURNING CALL takes the callee's returned struct type (§8 piece 2).
        if streq(src, ans, anl, ns, nl) and (not done) { crs := a64_binding_ret_struct_span(v, a64_decls(), src, a) ; if crs.n != 0 { rs = crs.s ; done = true } }
        ## a local bound to a WIDE-struct-returning CALL (`s := mk()`, SRET) takes the callee's struct type.
        if streq(src, ans, anl, ns, nl) and (not done) { srs := a64_call_ret_sret_span(v, a64_decls(), src, a) ; if srs.n != 0 { rs = srs.s ; done = true } }
        ## an aggregate-VAR copy `q := p` takes p's struct type (resolve the source local recursively).
        if streq(src, ans, anl, ns, nl) and (not done) {
          cvns := ex_var_ns(v) ; cvnl := ex_var_nl(v)
          if cvnl != 0 and (not streq(src, cvns, cvnl, ns, nl)) {
            if a64_local_struct_nl(head, src, cvns, cvnl, a) != 0 { rs = a64_local_struct_ns(head, src, cvns, cvnl, a) ; done = true }
            ## a snapshot of a module GLOBAL struct (`p := ORIGIN` / `p := STATE`) takes the global's type.
            if not done { gss := a64_global_agg_struct_span(a64_decls(), src, cvns, cvnl) ; if gss.n != 0 { rs = gss.s ; done = true } }
          }
        }
        ## `x := xs[i]` — an ELEMENT copy out of an array of structs takes the ELEMENT struct's type, so
        ## `x.field` reads resolve against x's own (element-wide) frame slots.
        if streq(src, ans, anl, ns, nl) and (not done) { eis := a64_index_elem_struct_span(v, src, a, a64_decls()) ; if eis.n != 0 { rs = eis.s ; done = true } }
        ## a standard-byte aggregate FIELD copy (`copy := o.inner`) carries the FIELD's concrete struct
        ## type even though it is not a bare Var/Index shape.
        if streq(src, ans, anl, ns, nl) and (not done) and ex_is_field(v) {
          sfp := a64_std_path_ty(v, head, src, a, a64_decls())
          if a64_std_path_ok(v, head, src, a, a64_decls()) and sfp.n != 0 {
            sbn := base_type_name(src, sfp.s, sfp.n)
            if struct_decl_of(a64_decls(), src, sbn.s, sbn.n) >= 0 { rs = sfp.s ; done = true }
          }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        ## an ITERABLE for over a struct-element array types its loop var as the element struct, so
        ## `p.field` reads resolve through localok (base = the loop var's copied element slots).
        if streq(src, fns, fnl, ns, nl) and unchecked bitcast(usize, fhi) == 0 {
          es := a64_arr_elem_struct_span(head, src, ex_var_ns(flo), ex_var_nl(flo), a)
          if es.n != 0 { rs = es.s ; done = true }
        }
        s = nx
      }
      ## comptime-for/if loop vars are scalar / their locals are fn-frame level — a struct-element type
      ## scan just advances past them (matching the `for`/`if` arms above; no top-level local is hidden).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { s = nx }
      Stmt::CompIf(cc, cth, cel, cnx) => { s = cnx }
      Stmt::Loop(lb, lnx) => { s = lnx }
      Stmt::Unchecked(ub, unx) => { s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::IndexAssign(_iab, _iai, _iav, ianx) => { s = ianx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  rs
}
a64_local_struct_nl := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := head
  mut rn := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and expr_is_struct_lit(v) { rn = expr_struct_lit_nl(v) ; done = true }
        if streq(src, ans, anl, ns, nl) and (not done) { crs := a64_binding_ret_struct_span(v, a64_decls(), src, a) ; if crs.n != 0 { rn = crs.n ; done = true } }
        ## a local bound to a WIDE-struct-returning CALL (`s := mk()`, SRET) takes the callee's struct width.
        if streq(src, ans, anl, ns, nl) and (not done) { srs := a64_call_ret_sret_span(v, a64_decls(), src, a) ; if srs.n != 0 { rn = srs.n ; done = true } }
        ## an aggregate-VAR copy `q := p` takes p's struct type width (resolve the source local recursively).
        if streq(src, ans, anl, ns, nl) and (not done) {
          cvns := ex_var_ns(v) ; cvnl := ex_var_nl(v)
          if cvnl != 0 and (not streq(src, cvns, cvnl, ns, nl)) {
            cprl := a64_local_struct_nl(head, src, cvns, cvnl, a)
            if cprl != 0 { rn = cprl ; done = true }
            ## a snapshot of a module GLOBAL struct (`p := ORIGIN` / `p := STATE`) takes the global's width.
            if not done { gss := a64_global_agg_struct_span(a64_decls(), src, cvns, cvnl) ; if gss.n != 0 { rn = gss.n ; done = true } }
          }
        }
        ## `x := xs[i]` — an ELEMENT copy takes the ELEMENT struct's type (see the _ns twin).
        if streq(src, ans, anl, ns, nl) and (not done) { eis := a64_index_elem_struct_span(v, src, a, a64_decls()) ; if eis.n != 0 { rn = eis.n ; done = true } }
        ## a standard-byte aggregate FIELD copy carries the FIELD's concrete struct width.
        if streq(src, ans, anl, ns, nl) and (not done) and ex_is_field(v) {
          sfp := a64_std_path_ty(v, head, src, a, a64_decls())
          if a64_std_path_ok(v, head, src, a, a64_decls()) and sfp.n != 0 {
            sbn := base_type_name(src, sfp.s, sfp.n)
            if struct_decl_of(a64_decls(), src, sbn.s, sbn.n) >= 0 { rn = sfp.n ; done = true }
          }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        if streq(src, fns, fnl, ns, nl) and unchecked bitcast(usize, fhi) == 0 {
          es := a64_arr_elem_struct_span(head, src, ex_var_ns(flo), ex_var_nl(flo), a)
          if es.n != 0 { rn = es.n ; done = true }
        }
        s = nx
      }
      ## comptime-for/if loop vars are scalar / their locals are fn-frame level — a struct-element type
      ## scan just advances past them (matching the `for`/`if` arms above; no top-level local is hidden).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { s = nx }
      Stmt::CompIf(cc, cth, cel, cnx) => { s = cnx }
      Stmt::Loop(lb, lnx) => { s = lnx }
      Stmt::Unchecked(ub, unx) => { s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::IndexAssign(_iab, _iai, _iav, ianx) => { s = ianx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  rn
}

## The struct-type name (start / len) of a struct-typed PARAM `[ns,nl]` — its `: T` annotation where T
## names a struct decl; 0/0 otherwise. A struct param is passed BY REFERENCE: its slot holds the base
## address of the caller's struct (read-only support — a field WRITE through a param would diverge from
## by-value and is trapped).
a64_param_struct_ns := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> usize {
  mut p := params_head
  mut rs := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      ## GENERICS (§8): substitute the type-param with the instance type so a `v : T` STRUCT param is
      ## recognized (in-instance only), mirroring a64_param_enum_ns.
      mut ets := pm.ts
      mut etl := pm.tl
      if A64_SUB_GPL != 0 {
        if streq(src, pm.ts, pm.tl, A64_SUB_GPS, A64_SUB_GPL) { ets = A64_SUB_ITS ; etl = A64_SUB_ITL }
      }
      ## strip a generic type-argument application (`Box(T)` → `Box`) so a param `q : Box(T)` (a generic
      ## struct — all word-sized instances share one layout) resolves; a plain struct name is unchanged.
      bt := base_type_name(src, ets, etl)
      if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { rs = bt.s }
    }
    p = pm.next
  }
  rs
}
a64_param_struct_nl := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> usize {
  mut p := params_head
  mut rn := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      mut ets := pm.ts
      mut etl := pm.tl
      if A64_SUB_GPL != 0 {
        if streq(src, pm.ts, pm.tl, A64_SUB_GPS, A64_SUB_GPL) { ets = A64_SUB_ITS ; etl = A64_SUB_ITL }
      }
      bt := base_type_name(src, ets, etl)
      if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { rn = bt.n }
    }
    p = pm.next
  }
  rn
}

## The ELEMENT type span of an explicit fixed-array PARAM `[ns,nl]` with positive static length, or
## {0,0}. The parser stores the element in `pm.ts/pm.tl`, marks the parameter with `pmode == 1`, and
## stores the static length in `pm.pps`; it does not store the source `[E; N]` annotation as a type span.
## Generic/slice/tuple parameters remain outside this bounded path.
a64_param_arr_elem_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize) -> CSpan {
  mut p := params_head
  mut r := CSpan(s = 0, n = 0)
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      if pm.pmode == 1 and pm.pps > 0 { r = CSpan(s = pm.ts, n = pm.tl) }
    }
    p = pm.next
  }
  r
}

a64_param_fixed_array_len := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize) -> i64 {
  mut p := params_head
  mut r := i64(0)
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { if pm.pmode == 1 { r = i64(pm.pps) } }
    p = pm.next
  }
  r
}


## GENERICS (§8 mono): the element WORD-stride of param `[ns,nl]` when it is a generic array param —
## declared with the bare type-param name (`a : T`) and, in the active instance, T substitutes to an
## ARRAY `[E; N]` (A64_SUB_ITS points at `[`) with a SCALAR element. Such a param is passed BY REFERENCE
## (its slot holds the array's base address, from the caller's `add x0,x29,#off`), so `a[i]` loads at
## `[base + i*stride*8]`. Returns the element stride in WORDS (1 for a scalar element), else 0. A STRUCT/
## enum element is a later slice → 0 (falls to the fail-loud index stub, never a silent miscompile).
## Reads the substitution GLOBALS directly + scans the element span INLINE (a span-param helper is
## mis-passed by the seed in the emit path — landmine).
a64_param_gen_arr_stride := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if A64_SUB_GPL == 0 { return 0 }
  if str_at((src + A64_SUB_ITS), 1) != "[" { return 0 }
  mut p := params_head
  mut isgen := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { if streq(src, pm.ts, pm.tl, A64_SUB_GPS, A64_SUB_GPL) { isgen = true } }
    p = pm.next
  }
  if not isgen { return 0 }
  ## element type span = `[`..top-level `;`, trimmed of surrounding spaces
  mut adep := 0
  mut asemi := A64_SUB_ITS + 1
  mut ap := A64_SUB_ITS + 1
  mut ago := true
  while ago and ap < A64_SUB_ITS + A64_SUB_ITL {
    ac := str_at((src + ap), 1)
    if ac == "(" or ac == "[" { adep = adep + 1 }
    else if (ac == ")" or ac == "]") and adep > 0 { adep = adep - 1 }
    else if ac == ";" and adep == 0 { asemi = ap ; ago = false }
    ap = ap + 1
  }
  mut aes := A64_SUB_ITS + 1
  while aes < asemi and str_at((src + aes), 1) == " " { aes = aes + 1 }
  mut aet := asemi
  while aet > aes and str_at((src + aet - 1), 1) == " " { aet = aet - 1 }
  ## SCALAR element only (stride 1 word); a struct/enum element is a documented follow-up.
  if struct_decl_of(decls, src, aes, aet - aes) >= 0 { return 0 }
  if enum_decl_of(decls, src, aes, aet - aes) >= 0 { return 0 }
  1
}

## The ELEMENT-type span of a `Slice(E)` PARAM named `[s,n)`, recovered by scanning SOURCE forward from
## the param name (`: Slice(E)`) — the aarch64 twin of lower.al's `slice_param_elem_span`, so the two
## backends detect a slice param identically. {0,0} when the param is not `: Slice(...)`. (No `...T`
## variadic branch: this backend does not lower slice-variadics.)
a64_slice_elem_span := fn(src : ptr(u8), s : usize, n : usize) -> CSpan {
  mut p := s + n
  end := p + 512
  mut c := str_at((src + p), 1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") { p = p + 1 ; c = str_at((src + p), 1) }
  if c != ":" { return CSpan(s = 0, n = 0) }
  p = p + 1
  c = str_at((src + p), 1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") { p = p + 1 ; c = str_at((src + p), 1) }
  if str_at((src + p), 6) != "Slice(" { return CSpan(s = 0, n = 0) }
  es := p + 6
  mut ee := es
  while ee < end and str_at((src + ee), 1) != ")" { ee = ee + 1 }
  if ee == end { return CSpan(s = 0, n = 0) }
  if ee == es { return CSpan(s = 0, n = 0) }
  CSpan(s = es, n = ee - es)
}
## Is the PARAM `[ns,nl]` a `Slice(E)` param whose element E is a SCALAR (not a struct/enum decl)? A slice
## param is passed BY REFERENCE: its frame slot holds a POINTER to the caller's `{ptr,len}` block (word0 =
## data ptr, word1 = runtime len), so a read (`s[i]`, `s.len()`, `for x in s`) DOUBLE-derefs. A struct/
## enum-element slice param (non-scalar E) is a documented follow-up — false here → fail-loud (no silent
## miscompile). Scalar element ⇒ 1-word stride (the x86 `estride == 1` case).
a64_slice_param_scalar := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut p := params_head
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      es := a64_slice_elem_span(src, pm.ns, pm.nl)
      if es.n != 0 {
        if struct_decl_of(decls, src, es.s, es.n) < 0 and enum_decl_of(decls, src, es.s, es.n) < 0 { r = true }
      }
    }
    p = pm.next
  }
  r
}

## The CURRENT function's `params_head`, stashed as a module global at the top of `emit_a64_fn` (the
## A64_CHK/A64_AGG pattern — each fn is emitted to completion before the next, so no re-entrancy). Lets
## the per-fn FRAME SCANNERS (a64_local_scan / a64_iter_stride / a64_arr_elem_struct_span), which take no
## `params_head`, still recognize a slice PARAM base — needed to size + type a struct/enum-element
## `Slice(E)` PARAM loop var without threading params through the whole scanner call graph.
mut A64_PARAMS := 0
a64_params := fn() -> ptr(mut Param) { unchecked bitcast(ptr(mut Param), A64_PARAMS) }
## The current fn's `decls` (constant across an emit), for scanners whose signature omits it.
mut A64_DECLS := 0
a64_decls := fn() -> ptr(rt::Vec) { unchecked bitcast(ptr(rt::Vec), A64_DECLS) }
## The current fn's BODY statement-list head, for scanners whose signature omits body_head (a64_val_words,
## called during frame sizing, needs it to size a bare-Var aggregate-copy RHS `q := p` as p's local width).
mut A64_BODY := 0
a64_body := fn() -> ptr(mut Stmt) { unchecked bitcast(ptr(mut Stmt), A64_BODY) }

## --- GENERICS (§8 monomorphization on aarch64) ------------------------------------------------
## The aarch64 backend emits monomorphized instances of a generic fn (a LEADING `T : type` param) as
## `<fn>__<typetag>` and routes each generic call to its instance — instead of the old `brk #0` stub.
## Scope of this slice: a SINGLE leading comptime type-parameter (`fn(T : type, …)`), scalar value
## params, EXPLICIT (`f(u64, …)`) or simple IMPLICIT (`id(k)`, `k` a scalar param) type-args. The
## instance's substitution (`T`'s name span → the concrete type span) rides four module globals, set
## per-instance in `emit_a64_program`'s mono pass (the A64_PARAMS/A64_CHK pattern — one fn at a time,
## no re-entrancy) and read by `a64_comp_cond_fold` (`comptime if T == …`). Zero → no substitution.
mut A64_SUB_GPS := 0    ## the generic type-param NAME span start …
mut A64_SUB_GPL := 0    ## … and length (0 = no active substitution)
mut A64_SUB_ITS := 0    ## the instance's concrete type span start …
mut A64_SUB_ITL := 0    ## … and length (non-zero while emitting an instance = instance mode)
## 2nd/3rd type-param substitution (a leading RUN of 2..3 comptime type-params, `pick3(A, B, C, …)`):
## the NAME span (GPS2/GPL2, GPS3/GPL3) → the instance concrete type span (ITS2/ITL2, ITS3/ITL3). 0/0
## when the instance has fewer type-params. The 2nd/3rd type-args are BARE scalar names (array/tuple
## _2/_3 are rejected in a64_resolve_typearg → the call falls to a fail-loud stub).
mut A64_SUB_GPS2 := 0
mut A64_SUB_GPL2 := 0
mut A64_SUB_ITS2 := 0
mut A64_SUB_ITL2 := 0
mut A64_SUB_GPS3 := 0
mut A64_SUB_GPL3 := 0
mut A64_SUB_ITS3 := 0
mut A64_SUB_ITL3 := 0

## The collected monomorphization instance set for the current program: three parallel FIXED module
## arrays (generic-decl index / type-arg span start / type-arg span length), `A64_INST_N` live entries.
## Fixed BSS arrays (not arena-bump) so the storage is not tied to a by-value arena copy. Instances are
## RECORDED DURING EMIT at each generic call site (`a64_inst_add`) and consumed to emit one `<fn>__<tag>`
## instance per entry. 2048 is far beyond any single program's distinct generic instantiations; the a64
## backend runs only for single-file cross-checks (never the self-build), so this BSS is otherwise inert.
mut A64_INST_GI : [usize; 512] = [0; 512]
mut A64_INST_TS : [usize; 512] = [0; 512]
mut A64_INST_TL : [usize; 512] = [0; 512]
## parallel arrays for the 2nd/3rd type-arg of a multi-type-param instance (0/0 when absent).
mut A64_INST_TS2 : [usize; 512] = [0; 512]
mut A64_INST_TL2 : [usize; 512] = [0; 512]
mut A64_INST_TS3 : [usize; 512] = [0; 512]
mut A64_INST_TL3 : [usize; 512] = [0; 512]
mut A64_INST_N := 0
## The emitted FLOAT-LITERAL pool for the current program: the source offsets whose
## `.Lflt<offset>: .double <text>` cell has ALREADY been written, `A64_FLT_N` live entries.
##
## A `.Lflt` label IS its literal's source-span start — a `FloatLit` carries no separate label field
## (unlike a `StrLit`, whose label index the driver RENUMBERS per HOF clone). So when the driver's
## FN-6 §6.2 D-cap path DEEP-CLONES a higher-order fn whose body holds a float literal, the clone
## copies the span start VERBATIM (it cannot be bumped — the same offset also indexes the literal's
## decimal TEXT), and the original H and its `__hoflam<fnpos>` clone are two decls carrying the same
## offset. The rodata walk visits decls, so it wrote the cell ONCE PER DECL while every `adrp x9,
## .Lflt<off>` reference resolved to one name: two definitions of one symbol, which `as` refuses
## ("symbol `.Lflt<off>' is already defined"). Both loads name the SAME offset and read the SAME
## text, so ONE shared cell is correct — record each distinct offset here and emit it at most once.
## x86_64 already does this in `lower::emit_rodata_expr` (a threaded `seen` Vec); a64/rv64 derive the
## label from the same span field, which is why the SAME number duplicates on both of them.
##
## Fixed BSS array (not arena-bump) so the storage is not tied to a by-value arena copy, matching
## A64_INST_*. 1024 is far beyond any single program's distinct float literals (all of `lib/` holds
## fewer than a hundred). On overflow the cell is emitted UNCONDITIONALLY: a missing cell is an
## undefined-symbol LINK error in code that would otherwise have run, whereas the unfiltered duplicate
## is exactly the status quo — both are loud, and the loud failure that keeps working programs working
## wins.
mut A64_FLT_OFF : [usize; 1024] = [0; 1024]
mut A64_FLT_N := 0
## True when `off` has NOT been emitted yet, recording it; false when this cell is already in the pool.
a64_flt_first := fn(off : usize) -> bool {
  mut i := 0
  mut found := false
  while i < A64_FLT_N {
    if A64_FLT_OFF[i] == off { found = true }
    i = i + 1
  }
  if found { return false }
  if A64_FLT_N < 1024 {
    A64_FLT_OFF[A64_FLT_N] = off
    A64_FLT_N = A64_FLT_N + 1
  }
  return true
}
## Resolved-type-arg OUT registers (the a64 idiom avoids returning a multi-word CSpan from a helper —
## the frozen seed can truncate such a return in some call contexts). `a64_resolve_typearg` writes the
## span here; callers read it.
mut A64_TA_S := 0
mut A64_TA_N := 0
## resolved 2nd/3rd type-args (leading-run generics), same OUT-register idiom.
mut A64_TA_S2 := 0
mut A64_TA_N2 := 0
mut A64_TA_S3 := 0
mut A64_TA_N3 := 0

## The element-type span E of the `Slice(E)` PARAM named `[ns,nl]` (scanning the param's `: Slice(E)`
## annotation), or {0,0} if `[ns,nl]` is not a slice param. The by-name twin used by the aggregate paths.
a64_slice_param_elem_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize) -> CSpan {
  mut p := params_head
  mut r := CSpan(s = 0, n = 0)
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { r = a64_slice_elem_span(src, pm.ns, pm.nl) }
    p = pm.next
  }
  r
}
## Element WORD stride of the `Slice(E)` PARAM `[ns,nl]`: struct_words for a struct E, 1+enum_max_arity
## for an enum E, else 0 (not an aggregate slice param). The by-reference param's element step in words.
a64_slice_param_agg_stride := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  es := a64_slice_param_elem_span(params_head, src, ns, nl)
  mut r := 0
  if es.n != 0 {
    if struct_decl_of(decls, src, es.s, es.n) >= 0 { require_no_byte_layout_array_elem(decls, src, es.s, es.n, a) ; r = i64(struct_words(decls, src, es.s, es.n, a)) }
    if enum_decl_of(decls, src, es.s, es.n) >= 0 { r = 1 + i64(enum_max_arity(decls, src, es.s, es.n, a)) }
  }
  r
}
## The element STRUCT span of the `Slice(P)` PARAM `[ns,nl]` (P a struct), else {0,0} — types a struct
## slice-param loop var / `s[i].field` read.
a64_slice_param_struct_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> CSpan {
  es := a64_slice_param_elem_span(params_head, src, ns, nl)
  mut r := CSpan(s = 0, n = 0)
  if es.n != 0 { if struct_decl_of(decls, src, es.s, es.n) >= 0 { r = es } }
  r
}
## The element ENUM span of the `Slice(E)` PARAM `[ns,nl]` (E an enum), else {0,0} — types a `match s[i]`.
a64_slice_param_enum_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> CSpan {
  es := a64_slice_param_elem_span(params_head, src, ns, nl)
  mut r := CSpan(s = 0, n = 0)
  if es.n != 0 { if enum_decl_of(decls, src, es.s, es.n) >= 0 { r = es } }
  r
}

## Is the `.len()` receiver `recv` a slice whose runtime length this backend can read — a scalar-element
## `Slice(E)` PARAM or a local slice VIEW? Gates the `Call("len", [recv])` intercept so a user-defined
## `len` on a non-slice receiver falls through to the ordinary call path.
a64_len_recv_slice := fn(recv : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), body_head : ptr(mut Stmt), decls : ptr(rt::Vec), a : rt::Arena) -> bool {
  rns := ex_var_ns(recv)
  rnl := ex_var_nl(recv)
  mut r := false
  if rnl != 0 {
    if a64_slice_param_scalar(params_head, src, rns, rnl, a, decls) { r = true }
    if is_slice_local(body_head, src, rns, rnl, a) { r = true }
  }
  r
}

## Are ALL fields of struct `[s,n)` single-word scalars? (Only scalar-field structs are laid out in the
## frame; a multi-word field makes the struct unsupported.) Mirrors wat.al's struct_all_scalar.
a64_struct_all_scalar := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut ok := true
  while f != 0 {
    fd := deref(fld_p(f))
    ## NESTED-GENERIC (§8 mono): substitute a type-PARAM field with the instance's concrete type-arg
    ## (`Box(P)`'s `v : T` → the aggregate `P`) via field_type_span (which routes subst_field_ty). An
    ## AGGREGATE type-arg CHANGES the field span → the struct is NOT all-scalar: its slit field value is
    ## itself a `{…}` and must take the nested-materialization store, not the one-word positional store
    ## (which would emit a scalar `brk`). subst changes the span ONLY for an aggregate type-arg; a scalar
    ## type-arg / a plain (non-generic) / a comptime-value type-fn stay put → byte-identical everywhere else.
    ft := field_type_span(decls, src, s, n, fd.ns, fd.nl, a)
    changed := ft.n != 0 and (ft.s != fd.ts or ft.n != fd.tl)
    if changed { ok = false }
    if (not changed) and field_words(decls, src, fd.ts, fd.tl, fd.wsize, a) != 1 { ok = false }
    f = fd.next
  }
  ok
}
## The word count of a struct `[s,n]` eligible for the register struct-return ABI (word k → x_k): a PLAIN
## (arity-0) struct of 1..8 words, else 0. The arity-0 gate excludes a comptime-VALUE-param type-fn like
## `uint(N)` — resolving its layout (struct_words) would need a binding the a64 emit path lacks and would
## PANIC; a plain struct (incl. one with enum/str fields — delivery is a type-agnostic word copy) resolves
## safely. Also excludes generic type-fns (`Box(T)`), matching the prior all-scalar gate's behavior there.
a64_ret_struct_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  ## PARAMS present → a generic / comptime-value type-fn (`uint(N)`, `Box(T)`): its layout needs a binding
  ## the a64 path lacks, so struct_words would PANIC — skip (0). Only a PLAIN struct decl reaches struct_words.
  if unchecked bitcast(usize, d.params_head) != 0 { return 0 }
  w := i64(struct_words(decls, src, s, n, a))
  if w >= 1 and w <= 8 { return w }
  0
}
## The word count of a PLAIN struct `[s,n]` that returns via SRET (the AAPCS64 indirect-result path): a
## plain (arity-0) struct WIDER than 8 words (too big for the x0..x7 register struct-return), else 0. Same
## arity-0 gate as a64_ret_struct_words (a comptime-value / generic type-fn would PANIC in struct_words).
a64_ret_sret_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  if unchecked bitcast(usize, d.params_head) != 0 { return 0 }
  w := i64(struct_words(decls, src, s, n, a))
  if w > 8 { return w }
  0
}
## The full {disc, payload…} word count of an ENUM `[s,n]` that returns via SRET (the x8 indirect-result
## path) — the enum analogue of a64_ret_sret_words: 1 + max_arity when `[s,n]` names an enum decl AND the
## total width EXCEEDS the 8-register enum-return budget, else 0. A ≤8-word enum keeps the register
## convention (a64_ret_enum_words / A64_RET_ENUM); a wider one is delivered through x8 like a wide struct.
a64_ret_enum_sret_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> i64 {
  if enum_decl_of(decls, src, s, n) < 0 { return 0 }
  w := 1 + i64(enum_max_arity(decls, src, s, n, a))
  if w > 8 { return w }
  0
}
## Is field `[fs,fl]` of struct `[s,n]` SCALAR (one word)? Uses the field's CACHED `wsize` (like
## a64_struct_all_scalar) — panic-free even for a comptime-value-param type-fn (`uint(N)`), unlike a
## fresh layout resolve. Lets a scalar field of a struct that ALSO has an aggregate field (`s.n` where
## `S = { c : Col, n : u64 }`) read at its offset while a non-scalar field stays unhandled.
a64_field_is_scalar := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut r := false
  while f != 0 {
    fd := deref(fld_p(f))
    if streq(src, fd.ns, fd.nl, fs, fl) and field_words(decls, src, fd.ts, fd.tl, fd.wsize, a) == 1 { r = true }
    f = fd.next
  }
  r
}

## STANDARD BYTE-LAYOUT PLACE RESOLUTION (CLAYOUT S3a). A standard-byte struct local is still an
## inline frame value on this backend; only the FIELD offsets change from words to bytes. Keep this
## resolver deliberately narrower than the general place machinery: a plain local root followed by
## FIELD hops, with no params/globals/indexes. The other shapes retain their existing fail-loud paths.
## The separate scalar accessors avoid returning a new path struct (the frozen seed has a known scar for
## newly introduced multi-word return structs).
## THE ROOT is gated on the ORACLE (`layout_kind_is_byte`), never on `std_struct_has_direct_byte_layout`
## alone: that predicate is TRUE for a `@packed` struct carrying a byte array, so the bare form stole
## `@packed` roots from the packed emitter and read them at §6.1 offsets — measured, `@packed
## { data : [u8;3], inner : @packed { a : u8, b : u16 } }` answered `data[1]` for `o.inner.a`, a WRONG
## VALUE where the previous compiler was correct. EVERY HOP uses `layout_field_offset_bytes`, which
## reads each link in the tier it is actually WRITTEN in. Since CLAYOUT S3(b) that is §6.1 bytes for
## the byte-layout root AND for every nested child the one byte-precise whole-value writer can write
## (`std_struct_is_byte_writable`), plus `field_word_offset * 8` for a word-granular child, where the
## two models coincide anyway. A child in neither set has NO answer (-1) and its consumer stays
## fail-loud, which is what the unconditional `standard_field_byte_offset` this replaced got wrong.
a64_std_path_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if ex_is_field(e) {
    base := expr_field_base(e)
    bt := a64_std_path_ty(base, body_head, src, a, decls)
    if bt.n != 0 { ft := field_type_span(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) ; r = ft }
  }
  if not ex_is_field(e) {
    ns := ex_var_ns(e)
    nl := ex_var_nl(e)
    if nl != 0 {
      rs := a64_local_struct_ns(body_head, src, ns, nl, a)
      rn := a64_local_struct_nl(body_head, src, ns, nl, a)
      if rn != 0 { if layout_kind_is_byte(layout_kind(decls, src, rs, rn, a)) { r = CSpan(s = rs, n = rn) } }
    }
  }
  r
}

a64_std_path_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_field(e) { return false }
  base := expr_field_base(e)
  bt := a64_std_path_ty(base, body_head, src, a, decls)
  if bt.n == 0 { return false }
  layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) >= 0
}

a64_std_path_bo := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not a64_std_path_ok(e, body_head, src, a, decls) { return 0 - 1 }
  base := expr_field_base(e)
  mut pbo := i64(0)
  if ex_is_field(base) { pbo = a64_std_path_bo(base, body_head, src, a, decls) }
  bt := a64_std_path_ty(base, body_head, src, a, decls)
  pbo + layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a)
}

a64_std_path_root_off := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not a64_std_path_ok(e, body_head, src, a, decls) { return 0 - 1 }
  base := expr_field_base(e)
  if ex_is_field(base) { return a64_std_path_root_off(base, body_head, src, pcount, a, decls) }
  a64_local_off(body_head, src, ex_var_ns(base), ex_var_nl(base), pcount, a, decls)
}

## PARAMETER twin of the standard-byte path. A struct PARAM is passed by reference on AArch64, so its
## frame slot contains the caller's byte-image address rather than an inline frame offset. Keep this
## resolver separate from the local-only path above: all existing local/packed/word consumers retain
## their exact gates, while S3(e) gets only the byte-tier parameter consumer it needs.
a64_std_param_path_ty := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if ex_is_field(e) {
    base := expr_field_base(e)
    bt := a64_std_param_path_ty(base, params_head, src, a, decls)
    if bt.n != 0 { r = field_type_span(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) }
  }
  if not ex_is_field(e) {
    ns := ex_var_ns(e)
    nl := ex_var_nl(e)
    pidx := param_find(params_head, src, ns, nl, a)
    if pidx >= 0 {
      rs := a64_param_struct_ns(params_head, src, ns, nl, a, decls)
      rn := a64_param_struct_nl(params_head, src, ns, nl, a, decls)
      if rn != 0 and layout_kind_is_byte(layout_kind(decls, src, rs, rn, a)) { r = CSpan(s = rs, n = rn) }
    }
  }
  r
}

a64_std_param_path_ok := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_field(e) { return false }
  base := expr_field_base(e)
  bt := a64_std_param_path_ty(base, params_head, src, a, decls)
  if bt.n == 0 { return false }
  layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) >= 0
}

a64_std_param_path_bo := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not a64_std_param_path_ok(e, params_head, src, a, decls) { return 0 - 1 }
  base := expr_field_base(e)
  mut pbo := i64(0)
  if ex_is_field(base) { pbo = a64_std_param_path_bo(base, params_head, src, a, decls) }
  bt := a64_std_param_path_ty(base, params_head, src, a, decls)
  pbo + layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a)
}

a64_std_param_path_idx := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not a64_std_param_path_ok(e, params_head, src, a, decls) { return 0 - 1 }
  base := expr_field_base(e)
  if ex_is_field(base) { return a64_std_param_path_idx(base, params_head, src, a, decls) }
  param_find(params_head, src, ex_var_ns(base), ex_var_nl(base), a)
}

## STANDARD BYTE-LAYOUT ARRAY-ELEMENT PATH (CLAYOUT S3(d)). This is the cross-backend twin of
## lower::place::std_idx_path: the root is an INDEX of a byte-tier struct array, followed by zero or
## more FIELD hops. Each hop asks the shared `layout_field_offset_bytes` oracle, so a word-granular child
## still uses its historical offset when the models coincide, while a byte-writable child uses §6.1.
## The path is intentionally separate from `a64_std_path`: that resolver's root is a frame-local struct,
## and making it accept an Index would lose the distinction between a fixed frame offset and a runtime
## element address.
a64_std_idx_path_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if ex_is_index(e) {
    bt := a64_place_ty(ex_index_base(e), body_head, src, a, decls)
    if bt.n != 0 {
      et := a64_arrty_elem(src, bt.s, bt.n)
      if et.n != 0 and std_array_elem_byte_tier(decls, src, et.s, et.n, a) { r = et }
    }
    return r
  }
  if ex_is_field(e) {
    base := expr_field_base(e)
    bt := a64_std_idx_path_ty(base, body_head, src, a, decls)
    if bt.n != 0 {
      bo := layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a)
      if bo >= 0 { r = field_type_span(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) }
    }
  }
  r
}

a64_std_idx_path_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_index(e) and not ex_is_field(e) { return false }
  a64_std_idx_path_ty(e, body_head, src, a, decls).n != 0
}

a64_std_idx_path_bo := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not a64_std_idx_path_ok(e, body_head, src, a, decls) { return 0 - 1 }
  if ex_is_index(e) { return 0 }
  base := expr_field_base(e)
  bt := a64_std_idx_path_ty(base, body_head, src, a, decls)
  a64_std_idx_path_bo(base, body_head, src, a, decls) + layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a)
}

a64_std_idx_root_arr := fn(e : ptr(Expr)) -> ptr(Expr) {
  if ex_is_index(e) { return ex_index_base(e) }
  if ex_is_field(e) { return a64_std_idx_root_arr(expr_field_base(e)) }
  unchecked bitcast(ptr(Expr), 0)
}

a64_std_idx_root_idx := fn(e : ptr(Expr)) -> ptr(Expr) {
  if ex_is_index(e) { return ex_index_idx(e) }
  if ex_is_field(e) { return a64_std_idx_root_idx(expr_field_base(e)) }
  unchecked bitcast(ptr(Expr), 0)
}


## Emit one scalar value at a known frame byte offset. The standard-byte tier only reaches this helper
## for scalar leaves; aggregate values use the recursive writer below.
a64_std_store_scalar := fn(off : i64, width : usize, in out sb : rt::StrBuf) {
  if width == 1 { push_str(sb, "  strb w0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 2 { push_str(sb, "  strh w0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 4 { push_str(sb, "  str w0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 8 { push_str(sb, "  str x0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "  brk #0 // unsupported standard scalar width\n") }
}

## The WIDTH-based core of the standard-byte scalar load. CLAYOUT S3(c) needs it: the shared copy
## plan (`layout_copy_step`) carries a width + signedness, not a type span, because the plan is computed
## once in `lower_layout` for all four backends.
a64_std_load_width := fn(off : i64, width : usize, signed : bool, in out sb : rt::StrBuf) {
  if width == 1 and signed { push_str(sb, "  ldrsb x0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 1 and (not signed) { push_str(sb, "  ldrb w0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 2 and signed { push_str(sb, "  ldrsh x0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 2 and (not signed) { push_str(sb, "  ldrh w0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 4 and signed { push_str(sb, "  ldrsw x0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 4 and (not signed) { push_str(sb, "  ldr w0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 8 { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "  brk #0 // unsupported standard scalar width\n") }
}

## Pointer-relative scalar load for a composed place. `x0` already holds the byte address; unlike the
## frame-relative S3(b) helper above this is used only after the array-element place resolver has finished.
a64_std_load_width_x0 := fn(width : usize, signed : bool, in out sb : rt::StrBuf) {
  if width == 1 and signed { push_str(sb, "  ldrsb x0, [x0]\n") }
  if width == 1 and (not signed) { push_str(sb, "  ldrb w0, [x0]\n") }
  if width == 2 and signed { push_str(sb, "  ldrsh x0, [x0]\n") }
  if width == 2 and (not signed) { push_str(sb, "  ldrh w0, [x0]\n") }
  if width == 4 and signed { push_str(sb, "  ldrsw x0, [x0]\n") }
  if width == 4 and (not signed) { push_str(sb, "  ldr w0, [x0]\n") }
  if width == 8 { push_str(sb, "  ldr x0, [x0]\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "  brk #0 // unsupported standard scalar width\n") }
}

## CLAYOUT S3(c) — THE ONE BYTE-PRECISE WHOLE-VALUE COPIER, aarch64's spelling. `soff` is the
## child's §6.1 byte offset inside the frame (root local + the accumulated path offset, both ascending
## from x29) and `doff` the destination local's own frame offset; the destination's word `w` is at
## `doff + w*8`, its byte `k` at `doff + k`. WHICH of the two the destination is read at is decided by
## `std_copy_kind` in `lower_layout`, shared with x86_64's `emit_standard_copy` and the other two cross
## backends, so no backend invents its own offset. A word-granular child never reaches here: for it the
## existing word copy IS the byte copy, and it keeps its byte-identical emission.
a64_std_copy := fn(ts : usize, tl : usize, soff : i64, doff : i64, in out sb : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) {
  ck := std_copy_kind(decls, src, ts, tl, a)
  if ck == 0 { push_str(sb, "  brk #0 // whole-value copy outside the byte-precise copier's domain\n") }
  if ck == 1 {
    nb := i64(std_copy_image_bytes(decls, src, ts, tl, a))
    mut k := i64(0)
    while k < nb {
      push_str(sb, "  ldrb w0, [x29, #") ; push_int(sb, soff + k) ; push_str(sb, "]\n")
      push_str(sb, "  strb w0, [x29, #") ; push_int(sb, doff + k) ; push_str(sb, "]\n")
      k = k + 1
    }
  }
  if ck == 2 {
    ns := i64(layout_copy_nsteps(decls, src, ts, tl, a))
    mut i := i64(0)
    while i < ns {
      st := layout_copy_step(decls, src, ts, tl, i, a)
      if st.found { a64_std_load_width(soff + st.sbo, st.sz, st.signed, sb) }
      if st.found { push_str(sb, "  str x0, [x29, #") ; push_int(sb, doff + st.dwo * 8) ; push_str(sb, "]\n") }
      if not st.found { push_str(sb, "  brk #0 // byte-precise copy plan shorter than its own step count\n") }
      i = i + 1
    }
  }
}

a64_std_load_scalar := fn(off : i64, ts : usize, tl : usize, in out sb : rt::StrBuf, src : ptr(u8)) {
  width := scalar_byte_size(src, ts, tl)
  signed := tl != 0 and str_at((src + ts), 1) == "i"
  a64_std_load_width(off, width, signed, sb)
}

## Recursive constructor writer for a standard-byte struct local. Struct fields use the shared §6.1
## offsets; a direct byte array is written byte-by-byte, while a nested word-granular aggregate keeps
## its natural word fields at the standard field offset. This is intentionally a constructor-only
## consumer in S3(a); whole-value copies use the existing word copy once their byte offset is aligned.
a64_std_store_value := fn(pe : ptr(Expr), off : i64, ts : usize, tl : usize, wsize : usize, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  es := a64_arrty_elem(src, ts, tl)
  if es.n != 0 {
    mut bytearr := false
    if scalar_byte_size(src, es.s, es.n) == 1 { bytearr = true }
    if bytearr and ex_is_array_lit(pe) {
      mut g := ex_array_lit_ehead(pe)
      mut k := i64(0)
      while g != 0 {
        ga := deref(arg_p(g))
        emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  strb w0, [x29, #") ; push_int(sb, off + k) ; push_str(sb, "]\n")
        k = k + 1
        g = ga.next
      }
      return k
    }
    push_str(sb, "  brk #0 // unsupported standard array field construction\n")
    return i64(wsize)
  }
  bn := base_type_name(src, ts, tl)
  if struct_decl_of(decls, src, bn.s, bn.n) >= 0 {
  ## CLAYOUT S3(b) — THE CHILD MUST BE IN THE BYTE-PRECISE WHOLE-VALUE WRITER'S DOMAIN, which is
  ## `lower_layout::std_struct_is_byte_writable`: ONE predicate, asked by this recursion and by
  ## x86_64's `emit_standard_assign` recursion alike, so all four backends now build the same §6.1
  ## image and every reader resolves it through the same `layout_field_offset_bytes`. S3(a) had to gate
  ## this on `std_struct_is_word_granular` instead, because x86_64 delegated the same child to the WORD
  ## constructor `emit_struct_assign`: measured then on
  ## `struct { data : [u8;8], inner : struct { a : u16, b : u16 } }`, `o.inner.b` answered 22 here and
  ## 0 on x86_64, so all four were made to refuse (I11 permits a trap, never a wrong value). A child
  ## OUTSIDE the domain — one carrying a `str`, an enum, a union, a tuple or a non-byte array — still
  ## has no store here and still traps.
    if expr_is_struct_lit(pe) and std_struct_is_byte_writable(decls, src, ts, tl, a) { return a64_std_store_struct(pe, off, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    push_str(sb, "  brk #0 // unsupported standard aggregate field construction\n")
    return i64(struct_words(decls, src, ts, tl, a))
  }
  emit_a64_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  a64_std_store_scalar(off, scalar_byte_size(src, ts, tl), sb)
  i64(standard_type_byte_size(decls, src, ts, tl, wsize, a))
}

a64_std_store_struct := fn(pe : ptr(Expr), off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  sns := expr_struct_lit_ns(pe)
  snl := expr_struct_lit_nl(pe)
  di := struct_decl_of(decls, src, sns, snl)
  if di < 0 { push_str(sb, "  brk #0 // unknown standard struct literal\n") ; return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut g := ex_struct_lit_args(pe)
  while f != 0 and g != 0 {
    fd := deref(fld_p(f))
    ga := deref(arg_p(g))
    bo := standard_field_byte_offset(decls, src, sns, snl, fd.ns, fd.nl, a)
    ft := field_type_span(decls, src, sns, snl, fd.ns, fd.nl, a)
    if bo >= 0 and ft.n != 0 { _sw := a64_std_store_value(ga.e, off + bo, ft.s, ft.n, fd.wsize, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    if bo < 0 or ft.n == 0 { push_str(sb, "  brk #0 // unresolved standard struct field\n") }
    f = fd.next
    g = ga.next
  }
  i64(standard_type_byte_size(decls, src, sns, snl, 1, a))
}

## POINTER-relative counterpart of the standard-byte literal writer. The element address is kept at
## `[sp]` because evaluating a field value clobbers the scratch registers. This is used only by the
## byte-tier ARRAY-ELEMENT assignment; the pre-existing word-relative payload writer remains untouched
## for every word-tier element and every non-array aggregate path.
a64_std_store_value_atptr := fn(pe : ptr(Expr), off : i64, ts : usize, tl : usize, wsize : usize, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  es := a64_arrty_elem(src, ts, tl)
  if es.n != 0 {
    if scalar_byte_size(src, es.s, es.n) == 1 and ex_is_array_lit(pe) {
      mut g := ex_array_lit_ehead(pe)
      mut k := i64(0)
      while g != 0 {
        ga := deref(arg_p(g))
        emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  ldr x1, [sp]\n  strb w0, [x1, #") ; push_int(sb, off + k) ; push_str(sb, "]\n")
        k = k + 1
        g = ga.next
      }
      return k
    }
    push_str(sb, "  brk #0 // unsupported byte-tier array field construction at pointer\n")
    return i64(wsize)
  }
  bn := base_type_name(src, ts, tl)
  if struct_decl_of(decls, src, bn.s, bn.n) >= 0 {
    if expr_is_struct_lit(pe) and std_struct_is_byte_writable(decls, src, ts, tl, a) { return a64_std_store_struct_atptr(pe, off, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    push_str(sb, "  brk #0 // unsupported byte-tier aggregate construction at pointer\n")
    return i64(struct_words(decls, src, ts, tl, a))
  }
  emit_a64_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "  ldr x1, [sp]\n")
  width := scalar_byte_size(src, ts, tl)
  if width == 1 { push_str(sb, "  strb w0, [x1, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 2 { push_str(sb, "  strh w0, [x1, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 4 { push_str(sb, "  str w0, [x1, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width == 8 { push_str(sb, "  str x0, [x1, #") ; push_int(sb, off) ; push_str(sb, "]\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "  brk #0 // unsupported byte-tier scalar width at pointer\n") }
  i64(standard_type_byte_size(decls, src, ts, tl, wsize, a))
}

a64_std_store_struct_atptr := fn(pe : ptr(Expr), off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  sns := expr_struct_lit_ns(pe)
  snl := expr_struct_lit_nl(pe)
  di := struct_decl_of(decls, src, sns, snl)
  if di < 0 { push_str(sb, "  brk #0 // unknown byte-tier struct literal at pointer\n") ; return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut g := ex_struct_lit_args(pe)
  while f != 0 and g != 0 {
    fd := deref(fld_p(f))
    ga := deref(arg_p(g))
    bo := standard_field_byte_offset(decls, src, sns, snl, fd.ns, fd.nl, a)
    ft := field_type_span(decls, src, sns, snl, fd.ns, fd.nl, a)
    if bo >= 0 and ft.n != 0 { _sw := a64_std_store_value_atptr(ga.e, off + bo, ft.s, ft.n, fd.wsize, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    if bo < 0 or ft.n == 0 { push_str(sb, "  brk #0 // unresolved byte-tier field at pointer\n") }
    f = fd.next
    g = ga.next
  }
  i64(standard_type_byte_size(decls, src, sns, snl, 1, a))
}

## EnumLit shape accessors are shared through lower_ctx; enum resolution remains backend-local.
## The enum-type name (start / len) of the LOCAL `[ns,nl]` — from its first `:=` whose value is an
## EnumLit; 0/0 if not an enum local.
a64_local_enum_ns := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := head
  mut rs := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and expr_is_enum_lit(v) { rs = expr_enum_lit_ns(v) ; done = true }
        ## a local bound to an enum-RETURNING CALL takes the callee's returned enum type (§8 piece 3).
        if streq(src, ans, anl, ns, nl) and (not done) { cre := a64_call_ret_enum_span(v, a64_decls(), src, a) ; if cre.n != 0 { rs = cre.s ; done = true } }
        ## a local bound to a WIDE-enum-RETURNING CALL (> 8 words, x8 SRET) takes the callee's enum type too.
        if streq(src, ans, anl, ns, nl) and (not done) { cres := a64_call_ret_enum_sret_span(v, a64_decls(), src, a) ; if cres.n != 0 { rs = cres.s ; done = true } }
        ## a snapshot of a module GLOBAL enum (`s := STATE`) takes the global's enum type.
        if streq(src, ans, anl, ns, nl) and (not done) { ges := a64_global_agg_enum_span(a64_decls(), src, ex_var_ns(v), ex_var_nl(v)) ; if ges.n != 0 { rs = ges.s ; done = true } }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { s = nx }
      Stmt::CompIf(cc, th, el, nx) => { s = nx }
      Stmt::Loop(lb, lnx) => { s = lnx }
      Stmt::Unchecked(ub, unx) => { s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::IndexAssign(_iab, _iai, _iav, ianx) => { s = ianx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  rs
}
a64_local_enum_nl := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := head
  mut rn := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and expr_is_enum_lit(v) { rn = expr_enum_lit_nl(v) ; done = true }
        if streq(src, ans, anl, ns, nl) and (not done) { cre := a64_call_ret_enum_span(v, a64_decls(), src, a) ; if cre.n != 0 { rn = cre.n ; done = true } }
        ## a local bound to a WIDE-enum-RETURNING CALL (> 8 words, x8 SRET) takes the callee's enum width too.
        if streq(src, ans, anl, ns, nl) and (not done) { cres := a64_call_ret_enum_sret_span(v, a64_decls(), src, a) ; if cres.n != 0 { rn = cres.n ; done = true } }
        ## a snapshot of a module GLOBAL enum (`s := STATE`) takes the global's enum-type width.
        if streq(src, ans, anl, ns, nl) and (not done) { ges := a64_global_agg_enum_span(a64_decls(), src, ex_var_ns(v), ex_var_nl(v)) ; if ges.n != 0 { rn = ges.n ; done = true } }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { s = nx }
      Stmt::CompIf(cc, th, el, nx) => { s = nx }
      Stmt::Loop(lb, lnx) => { s = lnx }
      Stmt::Unchecked(ub, unx) => { s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::IndexAssign(_iab, _iai, _iav, ianx) => { s = ianx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  rn
}

## The enum-type name (start / len) of an enum-typed PARAM `[ns,nl]` — its `: T` annotation where T names
## an enum decl; 0/0 otherwise. An enum param is passed BY REFERENCE (its slot holds the base address of
## the caller's {disc, payload…} block); a `match <param>` derefs that pointer (§8 piece 3).
## GENERICS (§8): the effective type span of param `[ns,nl]` — its declared `pm.ts/tl`, with the
## type-param substituted to the instance concrete type (A64_SUB_ITS/ITL) when in-instance and the
## param's type IS the type-param `T`. Written INLINE at each param-type read (a shared CSpan-returning
## helper mis-lowers). Kept as two scalar accessors like the enum/struct span pairs around it.
a64_param_enum_ns := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> usize {
  mut p := params_head
  mut rs := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      mut ets := pm.ts
      mut etl := pm.tl
      if A64_SUB_GPL != 0 {
        if streq(src, pm.ts, pm.tl, A64_SUB_GPS, A64_SUB_GPL) { ets = A64_SUB_ITS ; etl = A64_SUB_ITL }
      }
      if enum_decl_of(decls, src, ets, etl) >= 0 { rs = ets }
    }
    p = pm.next
  }
  rs
}
a64_param_enum_nl := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> usize {
  mut p := params_head
  mut rn := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      mut ets := pm.ts
      mut etl := pm.tl
      if A64_SUB_GPL != 0 {
        if streq(src, pm.ts, pm.tl, A64_SUB_GPS, A64_SUB_GPL) { ets = A64_SUB_ITS ; etl = A64_SUB_ITL }
      }
      if enum_decl_of(decls, src, ets, etl) >= 0 { rn = etl }
    }
    p = pm.next
  }
  rn
}
## Are ALL payload args of an EnumLit `v` single-word scalars (not a struct/enum/str literal)? Gates the
## by-reference enum-value materialization (piece 3) to the scalar-payload case; a nested/str payload stays
## a LOUD trap.
a64_elit_payload_scalar := fn(v : ptr(Expr)) -> bool {
  mut g := ex_enum_lit_args(v)
  mut ok := true
  while g != 0 {
    ga := deref(arg_p(g))
    if expr_is_struct_lit(ga.e) or expr_is_enum_lit(ga.e) or expr_is_str_lit(ga.e) { ok = false }
    g = ga.next
  }
  ok
}

a64_alit_nel := fn(v : ptr(Expr)) -> i64 {
  mut r := 0
  match deref(v) { Expr::ArrayLit(al_n, al_e) => { r = i64(al_n) } _ => {} }
  r
}
## A tuple return type is captured by the parser as the balanced `(T0, …)` span, not as a named
## struct.  Keep this classifier local to the backend: the x86 lower already owns the canonical
## tuple-return machinery, while a64 only needs the ABI fact (component count).
a64_fn_returns_tuple := fn(d : Decl, src : ptr(u8)) -> bool {
  if d.ret_tl == 0 { return false }
  str_at((src + d.ret_ts), 1) == "("
}
a64_tuple_words := fn(src : ptr(u8), ts : usize, tl : usize) -> i64 {
  mut depth := 0
  mut commas := 0
  mut i := 0
  while i < tl {
    c := str_at((src + ts + i), 1)
    if c == "(" { depth = depth + 1 }
    else if c == ")" { depth = depth - 1 }
    else if c == "," and depth == 1 { commas = commas + 1 }
    i = i + 1
  }
  i64(commas + 1)
}
## Is the LOCAL `[ns,nl]` a range-SLICE view (its first `:=` value is an `Expr::Slice`)?
## Is the LOCAL `[ns,nl]` an ARRAY (its first `:=` value is an ArrayLit)?
a64_is_array_local := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  mut r := false
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if ex_is_array_lit(v) { r = true }
        ## A tuple-returning CALL binds the same word-array local shape as an ArrayLit; its callee
        ## leaves x0..xN and the assignment stores those words into the local slots.
        if (not r) and a64_call_ret_struct_span(v, a64_decls(), src, a).n != 0 { r = true }
        ## `mut xs : [E; N]` — an explicitly UNINITIALIZED fixed-array local. The parser plants a Num(0)
        ## sentinel, so its array-ness lives only in the source annotation (a64_ann_arr_nel).
        if (not r) and a64_ann_arr_nel(src, ans, anl, v) > 0 { r = true }
      }
      _ => {}
    }
  }
  r
}

## Element WORD stride of an ARRAY-LIT `v`: struct_words for a StructLit first element, 1+enum_max_arity
## for an EnumLit first element, else 1 (scalar). Drives multi-word aggregate-array LAYOUT + iteration —
## the aarch64 dual of x86_64's `ent.estride`. An empty array-lit → 1 (scalar-neutral).
a64_alit_stride := fn(v : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut w := 1
  eh := ex_array_lit_ehead(v)
  if eh != 0 {
    a0 := deref(arg_p(eh))
    e0 := a0.e
    if expr_is_struct_lit(e0) {
      if std_array_elem_byte_tier(decls, src, expr_struct_lit_ns(e0), expr_struct_lit_nl(e0), a) { w = i64(array_elem_word_reservation(decls, src, expr_struct_lit_ns(e0), expr_struct_lit_nl(e0), a)) }
      if not std_array_elem_byte_tier(decls, src, expr_struct_lit_ns(e0), expr_struct_lit_nl(e0), a) { require_no_byte_layout_array_elem(decls, src, expr_struct_lit_ns(e0), expr_struct_lit_nl(e0), a) ; w = i64(struct_words(decls, src, expr_struct_lit_ns(e0), expr_struct_lit_nl(e0), a)) }
    }
    if expr_is_enum_lit(e0) { w = 1 + i64(enum_max_arity(decls, src, expr_enum_lit_ns(e0), expr_enum_lit_nl(e0), a)) }
  }
  w
}
## The element STRUCT span (ns,nl) of the array LOCAL `[ns,nl]` — its first ArrayLit element's StructLit
## name — or {0,0} if not a struct-element array. Types an aggregate for-loop var so its `p.field` reads
## resolve through the element struct (the localok path). Same scan shape as `a64_is_array_local`.
a64_arr_elem_struct_span := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> CSpan {
  mut s := head
  mut r := CSpan(s = 0, n = 0)
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) {
          if ex_is_array_lit(v) {
            eh := ex_array_lit_ehead(v)
            if eh != 0 { a0 := deref(arg_p(eh)) ; e0 := a0.e ; if expr_is_struct_lit(e0) { r = CSpan(s = expr_struct_lit_ns(e0), n = expr_struct_lit_nl(e0)) } }
            done = true
          }
          ## a range-slice VIEW `s := base[lo..hi]` inherits its element struct from the base ARRAY.
          if ex_is_slice(v) {
            sb2 := ex_slice_base(v)
            r = a64_arr_elem_struct_span(head, src, ex_var_ns(sb2), ex_var_nl(sb2), a)
            done = true
          }
          ## `mut xs : [E; N]` — the UNINITIALIZED form: the element struct comes from the annotation.
          ## Only a real STRUCT element is reported (this resolver's contract); a scalar-element array
          ## keeps {0,0} so nothing types a `u64` element as an aggregate.
          if not done {
            ae := a64_ann_arr_elem(src, ans, anl, v)
            if ae.n != 0 { if struct_decl_of(a64_decls(), src, ae.s, ae.n) >= 0 { r = ae ; done = true } }
          }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { s = nx }
      Stmt::CompIf(cc, th, el, nx) => { s = nx }
      Stmt::Loop(lb, lnx) => { s = lnx }
      Stmt::Unchecked(ub, unx) => { s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::IndexAssign(_iab, _iai, _iav, ianx) => { s = ianx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  ## not a body local — a struct-element `Slice(P)` PARAM base takes its element struct from the annotation.
  if not done { ps := a64_slice_param_struct_span(a64_params(), src, ns, nl, a64_decls()) ; if ps.n != 0 { r = ps } }
  r
}
## Element WORD stride of the iterable base expr `e` (a Var naming an array LOCAL, or a slice VIEW over
## one) via its ArrayLit — the element words of an aggregate loop var's slot; 1 for a scalar/unknown base
## (so scalar iteration keeps its 1-word element and the frame layout is byte-identical to before).
a64_iter_stride := fn(head : ptr(mut Stmt), src : ptr(u8), e : ptr(Expr), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  bns := ex_var_ns(e)
  bnl := ex_var_nl(e)
  mut s := head
  mut r := 1
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, bns, bnl) {
          if ex_is_array_lit(v) { r = a64_alit_stride(v, src, a, decls) ; done = true }
          if ex_is_slice(v) { r = a64_iter_stride(head, src, ex_slice_base(v), a, decls) ; done = true }
          ## `mut xs : [E; N]` — the UNINITIALIZED form: the stride is the DECLARED element's word width.
          if not done {
            ae := a64_ann_arr_elem(src, ans, anl, v)
            if ae.n != 0 { aw := a64_tyname_words(src, ae.s, ae.n, a, decls) ; if aw > 0 { r = aw ; done = true } }
          }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { s = nx }
      Stmt::CompIf(cc, th, el, nx) => { s = nx }
      Stmt::Loop(lb, lnx) => { s = lnx }
      Stmt::Unchecked(ub, unx) => { s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::ExprStmt(ex, nx) => { s = nx }
      Stmt::FieldAssign(bns2, bnl2, fns2, fnl2, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::IndexAssign(_iab, _iai, _iav, ianx) => { s = ianx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  ## not a body local — a struct/enum-element `Slice(E)` PARAM base has its stride from the param annotation.
  if not done { ps := a64_slice_param_agg_stride(a64_params(), src, bns, bnl, a, decls) ; if ps > 0 { r = ps } }
  r
}
## The element COUNT of the array LOCAL `[ns,nl]` — its first `:=` ArrayLit's length, or 0 if none — the
## static bound for a `verify.checked` index guard (the aarch64 analogue of x86_64's `ent.snl`). Same
## scan shape as `a64_is_array_local`.
a64_array_nel := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> i64 {
  mut s := head
  mut r := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and ex_is_array_lit(v) { r = a64_alit_nel(v) ; done = true }
        if streq(src, ans, anl, ns, nl) and (not done) {
          cr := a64_call_ret_struct_span(v, a64_decls(), src, a)
          if cr.n != 0 and str_at((src + cr.s), 1) == "(" { r = a64_tuple_words(src, cr.s, cr.n) ; done = true }
        }
        ## `mut xs : [E; N]` — the UNINITIALIZED form: the static bound comes from the annotation.
        if streq(src, ans, anl, ns, nl) and (not done) {
          an := a64_ann_arr_nel(src, ans, anl, v)
          if an > 0 { r = an ; done = true }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { s = nx }
      Stmt::CompIf(cc, th, el, nx) => { s = nx }
      Stmt::Loop(lb, lnx) => { s = lnx }
      Stmt::Unchecked(ub, unx) => { s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::IndexAssign(_iab, _iai, _iav, ianx) => { s = ianx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  r
}

## The aarch64 verification mode (I11 / CG-6/CG-7), mirroring the x86_64 lower's `LCtx.vchk`: `checked`
## by default, cleared inside an `unchecked` scope (the `Expr::Unchecked` arm saves/clears/restores it),
## so a bounds guard is present in checked code and comptime-absent under `unchecked`. A separate global
## because the native backends run their own emit (they do not route through `lower.al`).
mut A64_CHK := true
## FN-return float flag (§8 float ABI): set per-fn in emit_a64_fn to whether the fn returns f64/f32, read
## by emit_a64_epilogue to move the result bits x0 → d0 (the SysV float return register) before `ret`.
## A module global (the A64_CHK pattern) to avoid threading a param through emit_a64_stmts/match_arms.
mut A64_RET_FLOAT := false
## FN-return bounded BYTE ARRAY length (§8): a `[u8; N]`, 1 <= N <= 8, is returned as one packed word
## in x0. A64 locals retain their existing one-word-per-element representation; the return path packs
## those bytes only at the ABI boundary. Other fixed arrays stay fail-loud.
mut A64_RET_BYTE_N := 0
## FN-return STRUCT span (§8 piece 2, register struct-return convention): when the current fn returns an
## all-scalar struct of 1..8 words, holds its type name span (0/0 otherwise). Set per-fn in emit_a64_fn;
## read by the Return stmt + trailing-value paths to route the value through emit_a64_struct_value (word
## k → x_k) instead of the scalar emit_a64_expr. The A64_CHK per-fn-global pattern.
mut A64_RET_STRUCT_NS := 0
mut A64_RET_STRUCT_NL := 0
## FN-return ENUM span (§8 piece 3, register enum-return convention): when the fn returns an enum of
## 1..8 words, holds its type name span (0/0 otherwise). Set per-fn in emit_a64_fn; read by Return +
## trailing-value to route the value through emit_a64_enum_value (word 0 = disc, word k+1 = payload).
mut A64_RET_ENUM_NS := 0
mut A64_RET_ENUM_NL := 0
## FN-return WIDE-STRUCT (SRET) span (§8 piece 2b, AAPCS64 indirect-result convention): when the fn returns
## a PLAIN struct of MORE than 8 words (too wide for the x0..x7 register struct-return), holds its type name
## span (0/0 otherwise). Set per-fn in emit_a64_fn. The caller passes the destination ADDRESS in x8 (the
## AAPCS64 indirect result register); the callee spills x8 to A64_SRET_SLOT on entry and, at each Return,
## copies the whole struct through it. The A64_CHK per-fn-global pattern.
mut A64_RET_SRET_NS := 0
mut A64_RET_SRET_NL := 0
## Frame byte offset where an SRET fn spills the incoming x8 (indirect result pointer) on entry, so it
## survives nested calls / register churn to each Return point. Valid only when A64_RET_SRET_NL != 0.
mut A64_SRET_SLOT := 0
## WIDE-ENUM SRET (§8 piece 3, > 8 words): a fn returning an enum wider than the x0..x7 register budget
## delivers via the SAME x8 indirect-result convention as a wide struct (A64_RET_SRET holds the enum type,
## enum_decl_of distinguishes it). This is the frame byte offset of a scratch block sized to the enum's
## full {disc, payload…} width, where a `return E.V(…)` LITERAL is materialized before it is word-copied
## through the x8 destination. Valid only when the return type is a wide enum. See emit_a64_enum_fn setup.
mut A64_ENUM_SRET_BLK := 0
## CALLER-side hand-off for an SRET binding `s := mk(…)`: when ON, the destination local's frame byte
## offset the call arm turns into `add x8, x29, #<off>` right before the `bl` (only for an SRET callee).
## Set (save/restore) around emit of the binding-RHS call; the call arm clears ON once it emits the x8.
mut A64_SRET_DST_ON := false
mut A64_SRET_DST := 0
## INDIRECT flavour of the hand-off (SRET TAIL-FORWARD, `return mk(…)` from a wide-struct-returning fn):
## the destination is not a frame BLOCK of ours but the caller's own result pointer, which this fn spilled
## at A64_SRET_SLOT. When ON, A64_SRET_DST names that SLOT and the call arm emits `ldr x8, [x29, #<slot>]`
## instead of `add x8, x29, #<off>` — the inner callee writes straight into the outer caller's destination,
## so nothing is copied afterwards. Cleared together with A64_SRET_DST_ON when the call arm consumes it.
mut A64_SRET_DST_IND := false
## LOOP break/continue targets (per-fn, the A64_CHK pattern — no threaded param). Each holds the label id
## of the nearest enclosing loop: `break` → `.Lbrk<A64_BRK>`, `continue` → `.Lcont<A64_CONT>`. Saved and
## restored around each loop body so nesting resolves to the innermost loop. Mirrors the x86 lower's
## `cx.brk`/`cx.cont`. A loop emits `.Lcont<id>:` at its CONTINUE point (a `while`'s guard re-entry, a
## `for`'s increment, a `loop`'s top) and `.Lbrk<id>:` at its exit; unused when the body has no break/continue.
mut A64_BRK := 0
mut A64_CONT := 0
## SLICE-ARG agg-block allocator (§8 slice-param CALLER materialization). A slice ARGUMENT `f(xs[lo..hi])`
## is passed BY REFERENCE: the anonymous `{ptr,len}` block must live in reserved frame words so its address
## can be passed. `emit_a64_fn` reserves 2 words per slice-arg occurrence (a64_slarg_count) ABOVE the
## locals, sets `A64_AGG` to the first reserved byte offset and `A64_AGG_LIM` to the frame top; each
## materialized slice arg grabs the next 16 bytes and bumps `A64_AGG`. An overflow past `A64_AGG_LIM`
## (an under-count) is a LOUD `brk`, never a silent frame corruption. Module globals (the A64_CHK pattern).
mut A64_AGG := 0
mut A64_AGG_LIM := 0
## MATCH-over-INDEX temp region (§8 enum slice-param): a `match s[i]` on an enum `Slice(E)` PARAM
## materializes the by-reference element's enum words (disc+payload) into this reserved frame region,
## then matches on it (emit_a64_match_arms reads a frame offset). Set per-fn in emit_a64_fn (byte offset
## of the region start), sized to the largest such match-over-index enum. 0 = no such match.
mut A64_MTMP := 0
## Current MATCH-ARM enum context (§8 piece 3b): the enum type + variant of the arm whose body is being
## emitted, so a `.field` / nested `match` / copy of an AGGREGATE payload BINDING can resolve the binding's
## type + frame offset. Set (save/restore) per arm in emit_a64_match_arms. 0 = not inside an aggregate-
## capable arm. The A64_CHK per-fn-global pattern (avoids threading the enum/variant through every emitter).
mut A64_ARM_ENS := 0
mut A64_ARM_ENL := 0
mut A64_ARM_VS := 0
mut A64_ARM_VL := 0
## Current COMPTIME-FOR-VARIANT loop variant (the variant name span the enclosing `wild == 2` unroll is
## emitting): a nested/inner match's `T.(v)` comptime-variant PATTERN arm (`wild == 3`) resolves `v` to
## THIS variant. Set (save/restore) per generated arm in the wild==2 expansion. 0 = not inside an unroll.
mut A64_CFVAR_S := 0
mut A64_CFVAR_L := 0
## The current COMPTIME-FOR-FIELD loop context (§8 field-derive core, `comptime for f in typeinfo(T).fields`):
## the loop-var NAME span (A64_CF_VAR_*), the CURRENT field's NAME span (A64_CF_FLD_*), and its TYPE span
## (A64_CF_TY_*). Set (save/restore) per field in the `Stmt::CompFor` field-unroll. `v.(f)` (an `Expr::
## CompField`) resolves to the field READ of `v` at A64_CF_FLD_*; `f.type` (an explicit type-arg) resolves
## to A64_CF_TY_* in a64_resolve_typearg. `A64_CF_VAR_L == 0` = NOT inside a field unroll (all reads inert).
mut A64_CF_VAR_S := 0
mut A64_CF_VAR_L := 0
mut A64_CF_FLD_S := 0
mut A64_CF_FLD_L := 0
mut A64_CF_TY_S := 0
mut A64_CF_TY_L := 0
## The byte offset of `<f>.offset` for the ACTIVE comptime field descriptor. The field loop is
## emitted only for a concrete struct instance (`A64_SUB_*`); reuse the shared layout calculators so
## packed, standard byte-array, and ordinary word-granular structs report the same offsets as value code.
## Return -1 for a non-active/dynamic descriptor shape; the caller keeps the existing fail-loud path.
a64_cf_offset_value := fn(e : ptr(Expr), src : ptr(u8), decls : ptr(rt::Vec), a : rt::Arena) -> i64 {
  if A64_CF_VAR_L == 0 or A64_SUB_ITL == 0 { return 0 - 1 }
  match deref(e) {
    Expr::Field(base, fs, fl) => {
      if str_at((src + fs), fl) != "offset" { return 0 - 1 }
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      if bnl == 0 or not streq(src, bns, bnl, A64_CF_VAR_S, A64_CF_VAR_L) { return 0 - 1 }
      ct := base_type_name(src, A64_SUB_ITS, A64_SUB_ITL)
      if ct.n == 0 { return 0 - 1 }
      ## THE ORACLE (`lower_layout::layout_kind`) picks the tier — the same decision the value
      ## paths and the x86 dual use, so four emitters cannot drift apart on one offset.
      lk := layout_kind(decls, src, ct.s, ct.n, a)
      if layout_kind_is_packed(lk) { return packed_field_byte_offset(decls, src, ct.s, ct.n, A64_CF_FLD_S, A64_CF_FLD_L, a) }
      if layout_kind_is_byte(lk) { return standard_field_byte_offset(decls, src, ct.s, ct.n, A64_CF_FLD_S, A64_CF_FLD_L, a) }
      fwo := field_word_offset(decls, src, ct.s, ct.n, A64_CF_FLD_S, A64_CF_FLD_L, a)
      if fwo >= 0 { return fwo * 8 }
      return 0 - 1
    }
    _ => { return 0 - 1 }
  }
}
## The comptime value of `<f>.mutable` for the ACTIVE field-derive descriptor. The parser erases the
## field-level `mut` marker, so use the same source-only recovery as the x86 lower. Return -1 when this
## expression is not exactly the active `Field(Var(f), "mutable")` shape; the caller then keeps the
## ordinary field machinery, whose unsupported path is a deliberate `brk` rather than a guessed value.
a64_cf_mutable_value := fn(e : ptr(Expr), src : ptr(u8)) -> i64 {
  if A64_CF_VAR_L == 0 { return 0 - 1 }
  mut r := 0 - 1
  match deref(e) {
    Expr::Field(base, fs, fl) => {
      if str_at((src + fs), fl) == "mutable" {
        bns := ex_var_ns(base)
        bnl := ex_var_nl(base)
        if bnl != 0 and streq(src, bns, bnl, A64_CF_VAR_S, A64_CF_VAR_L) {
          if local_is_mut(src, A64_CF_FLD_S) { r = 1 } else { r = 0 }
        }
      }
    }
    _ => {}
  }
  r
}
## The current match arm's payload BINDING-list head (pointer bits), so an IMPLICIT generic call in the
## body (`hash(p)`, p the payload binding) can infer its type-arg from the binding's payload type via the
## A64_ARM_* variant context. Set (save/restore) per arm in emit_a64_match_arms; 0 = not inside an arm.
mut A64_ARM_BINDS := 0
## The AGGREGATE payload-type span of binding `[ns,nl]` — non-0/0 ONLY when it is the CURRENT arm's SINGLE
## payload binding AND the variant's payload type is a struct / enum / str (§8 piece 3b). Such a binding is
## an aggregate living at frame offset `bind_base + 8` (word 1 of the scrutinee's {disc,payload} block); a
## scalar / multi-binding payload keeps the ordinary scalar bind path (0/0 here). Uses the A64_ARM_* arm
## context; `bind_base` (threaded) gives the frame offset.
a64_bind_agg_span := fn(bind_head : ptr(mut Bind), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut rs := 0
  mut rn := 0
  if A64_ARM_ENL != 0 {
    bidx := bind_list_index(bind_head, src, ns, nl, a)
    mut cnt := 0
    mut b := bind_head
    while unchecked bitcast(usize, b) != 0 { cnt = cnt + 1 ; b = bnd_next(b) }
    if bidx == 0 and cnt == 1 {
      pty := variant_payload_type(decls, src, A64_ARM_ENS, A64_ARM_ENL, A64_ARM_VS, A64_ARM_VL, a)
      isagg := pty.n != 0 and (struct_decl_of(decls, src, pty.s, pty.n) >= 0 or enum_decl_of(decls, src, pty.s, pty.n) >= 0 or str_at((src + pty.s), pty.n) == "str")
      if isagg { rs = pty.s ; rn = pty.n }
    }
  }
  CSpan(s = rs, n = rn)
}

## --- string literals + print (direct `write` syscall, like WASM's WASI path — NOT the x86_64 stdlib
## path, which the single-file native driver does not link). StringLit shape accessors are shared
## through lower_ctx; decoding and emission remain backend-local. ---
## Emit `.Lstr<lbl>: .byte …` for a print string: decode the raw inner span at `ss` into exactly `sl`
## bytes (the parser pre-subtracted escapes so `sl` is the decoded length). NO trailing newline — a
## println emits a separate newline write, and `{}`-template runs reference sub-ranges of this data.
emit_a64_str_bytes := fn(in out sb : rt::StrBuf, src : ptr(u8), ss : usize, sl : usize, lbl : usize) {
  push_str(sb, ".Lstr") ; push_int(sb, i64(lbl)) ; push_str(sb, ":\n  .byte ")
  raw := str_at((src + ss), sl * 4 + 16)
  mut k := 0
  mut em := 0
  mut any := false
  while em < sl {
    if any { push_str(sb, ", ") }
    if bytes(raw)[k] == 92 {
      if bytes(raw)[k + 1] == 120 {
        push_str(sb, "0x")
        push_str(sb, str_at((src + ss + k + 2), 2))
        k = k + 4
      } else { push_int(sb, i64(str_esc_byte(bytes(raw)[k + 1]))) ; k = k + 2 }
    }
    else { push_int(sb, i64(bytes(raw)[k])) ; k = k + 1 }
    any = true
    em += 1
  }
  if not any { push_str(sb, "0") }
  push_str(sb, "\n")
}

## Emit `write(1, .Lstr<lbl> + off, len)` — one literal run of a print template (or a whole literal).
emit_a64_print_run := fn(in out sb : rt::StrBuf, lbl : usize, off : i64, len : i64) {
  push_str(sb, "  mov x0, #1\n  adrp x1, .Lstr") ; push_int(sb, i64(lbl)) ; push_str(sb, "\n  add x1, x1, :lo12:.Lstr") ; push_int(sb, i64(lbl)) ; push_str(sb, "\n")
  if off != 0 { push_str(sb, "  add x1, x1, #") ; push_int(sb, off) ; push_str(sb, "\n") }
  push_str(sb, "  mov x2, #") ; push_int(sb, len) ; push_str(sb, "\n  mov x8, #64\n  svc #0\n")
}

## Emit a print template: scan the RAW format bytes tracking the DECODED offset (a simple escape = 2
## raw → 1 decoded byte, `\xHH` = 4 raw → 1 decoded byte); each literal run → emit_a64_print_run; each `{}` hole → evaluate the next arg into x0
## and `bl __print_u64` (unsigned decimal). A trailing newline (println) is a final 1-byte write of
## `.Lprnl`. Mirrors wat.al's emit_print_template.
emit_a64_print_template := fn(in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), ss : usize, sl : usize, lbl : usize, nl : bool, ah : ptr(mut Arg), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  raw := str_at((src + ss), sl * 4 + 16)
  firstarg := deref(arg_p(ah))
  mut argp := firstarg.next
  mut k := 0
  mut dpos := 0
  mut runstart := 0
  while dpos < sl {
    if bytes(raw)[k] == 123 and bytes(raw)[k + 1] == 125 {
      if dpos > runstart { emit_a64_print_run(sb, lbl, i64(runstart), i64(dpos - runstart)) }
      if argp != 0 {
        ga := deref(arg_p(argp))
        emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  bl __print_u64\n")
        argp = ga.next
      }
      k += 2
      dpos += 2
      runstart = dpos
    } else if bytes(raw)[k] == 92 {
      if bytes(raw)[k + 1] == 120 { k += 4 } else { k += 2 }
      dpos += 1
    } else {
      k += 1
      dpos += 1
    }
  }
  if sl > runstart { emit_a64_print_run(sb, lbl, i64(runstart), i64(sl - runstart)) }
  if nl { push_str(sb, "  mov x0, #1\n  adrp x1, .Lprnl\n  add x1, x1, :lo12:.Lprnl\n  mov x2, #1\n  mov x8, #64\n  svc #0\n") }
}

## The WORD size of a local whose first `:=` value is `v`: struct_words for a StructLit, 1+enum_max_arity
## for an EnumLit, element-count for an ArrayLit (scalar elements, 1 word each), else 1 scalar.
a64_val_words := fn(v : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut w := 1
  if expr_is_struct_lit(v) { w = i64(struct_words(decls, src, expr_struct_lit_ns(v), expr_struct_lit_nl(v), a)) }
  ## enum instance = 1 discriminant word + enum_max_arity payload words (enum_inst_words returns only
  ## the PAYLOAD words for a non-generic enum — it omits the discriminant — so add 1).
  if expr_is_enum_lit(v) { w = 1 + i64(enum_max_arity(decls, src, expr_enum_lit_ns(v), expr_enum_lit_nl(v), a)) }
  if ex_is_array_lit(v) { w = a64_alit_nel(v) * a64_alit_stride(v, src, a, decls) }
  ## a range-slice binds a 2-word {ptr, len} view.
  if ex_is_slice(v) { w = 2 }
  ## an aggregate-VAR copy `q := p` (RHS is a bare Var naming a struct/enum LOCAL): size `q` as the source
  ## local's full width (else it would reserve one scalar word and the copy would overrun the frame). Uses
  ## the A64_BODY head (this fn's body) since the sizing signature omits body_head. p's own binding is a
  ## StructLit/EnumLit → its width resolves directly; a plain scalar Var stays 1 word (byte-identical).
  vwns := ex_var_ns(v)
  vwnl := ex_var_nl(v)
  if vwnl != 0 and A64_BODY != 0 {
    lsn := a64_local_struct_nl(a64_body(), src, vwns, vwnl, a)
    if lsn != 0 { w = i64(struct_words(decls, src, a64_local_struct_ns(a64_body(), src, vwns, vwnl, a), lsn, a)) }
    len := a64_local_enum_nl(a64_body(), src, vwns, vwnl, a)
    if lsn == 0 and len != 0 { w = 1 + i64(enum_max_arity(decls, src, a64_local_enum_ns(a64_body(), src, vwns, vwnl, a), len, a)) }
    ## a snapshot of a module GLOBAL aggregate (`p := GLOBAL`): size p as the global's struct/enum width.
    gss := a64_global_agg_struct_span(decls, src, vwns, vwnl)
    if lsn == 0 and len == 0 and gss.n != 0 { w = i64(struct_words(decls, src, gss.s, gss.n, a)) }
    ges := a64_global_agg_enum_span(decls, src, vwns, vwnl)
    if lsn == 0 and len == 0 and gss.n == 0 and ges.n != 0 { w = 1 + i64(enum_max_arity(decls, src, ges.s, ges.n, a)) }
  }
  ## `x := xs[i]` — a whole-ELEMENT copy out of an array of scalar-only structs is sized as the ELEMENT
  ## struct's words (a scalar 1-word reservation would let the copy overrun into the next local).
  eisw := a64_index_elem_struct_span(v, src, a, decls)
  if eisw.n != 0 {
    if std_array_elem_byte_tier(decls, src, eisw.s, eisw.n, a) { w = i64(array_elem_word_reservation(decls, src, eisw.s, eisw.n, a)) }
    if not std_array_elem_byte_tier(decls, src, eisw.s, eisw.n, a) { w = i64(struct_words(decls, src, eisw.s, eisw.n, a)) }
  }
  ## a local bound to a struct-RETURNING CALL (`p := mk()`) is sized as the returned struct's words
  ## (§8 piece 2 register struct-return convention) so its `.field` reads resolve at their word offset.
  crsw := a64_binding_ret_struct_span(v, decls, src, a)
  if crsw.n != 0 { w = i64(struct_words(decls, src, crsw.s, crsw.n, a)) ; if str_at((src + crsw.s), 1) == "(" { w = a64_tuple_words(src, crsw.s, crsw.n) } }
  ## a local bound to a WIDE-struct-returning CALL (`s := mk()`, SRET) is sized as the returned struct's
  ## full words so the callee's write through x8 (and later `.field` reads) land inside the frame.
  srsw := a64_call_ret_sret_span(v, decls, src, a)
  if srsw.n != 0 { w = i64(struct_words(decls, src, srsw.s, srsw.n, a)) }
  ## a local bound to an enum-RETURNING CALL (`m := id(…)`) is sized as the enum's full width (§8 piece 3).
  crew := a64_call_ret_enum_span(v, decls, src, a)
  if crew.n != 0 { w = 1 + i64(enum_max_arity(decls, src, crew.s, crew.n, a)) }
  ## a local bound to a WIDE-enum-RETURNING CALL (`m := mk()`, > 8 words, x8 SRET) is sized as the enum's
  ## full width so the callee's write through x8 (and later `match` reads) land inside the frame.
  cresw := a64_call_ret_enum_sret_span(v, decls, src, a)
  if cresw.n != 0 { w = 1 + i64(enum_max_arity(decls, src, cresw.s, cresw.n, a)) }
  ## A standard-byte aggregate FIELD (for example `copy := o.inner`) is a live sub-place, not a
  ## scalar word. Its byte offset is handled by the copy arm, but the destination still needs the
  ## inner aggregate's full word width reserved in this inline-frame backend.
  if ex_is_field(v) and A64_BODY != 0 {
    sfp := a64_std_path_ty(v, a64_body(), src, a, decls)
    if a64_std_path_ok(v, a64_body(), src, a, decls) and sfp.n != 0 and std_ty_aggregate(sfp.s, sfp.n, decls, src) {
      sbn := base_type_name(src, sfp.s, sfp.n)
      if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { w = i64(struct_words(decls, src, sfp.s, sfp.n, a)) }
    }
  }
  w
}

## First Assign handle of name `[ns,nl]` anywhere in the fn tree (pre-order: top-level then nested
## while/if/match bodies), or 0. Value-returning recursion (no ptr(mut), no early-return-in-arm — the
## lean-lower scars); one distinct name → one handle → one slot. Mirrors wat.al's first_assign_handle.
a64_first_handle := fn(list : ptr(mut Stmt), ns : usize, nl : usize, src : ptr(u8), a : rt::Arena) -> usize {
  mut s := list
  mut res := 0
  while s != 0 and res == 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { if streq(src, ans, anl, ns, nl) { res = s } ; s = nx }
      Stmt::While(c, b, nx) => { res = a64_first_handle(b, ns, nl, src, a) ; s = nx }
      Stmt::If(c, th, el, nx) => { res = a64_first_handle(th, ns, nl, src, a) ; if res == 0 { res = a64_first_handle(el, ns, nl, src, a) } ; s = nx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 and res == 0 { am := deref(arm_p(arm)) ; res = a64_first_handle(am.body_stmts, ns, nl, src, a) ; arm = am.next } ; s = mnx }
      ## a `for i in lo..hi` DECLARES the loop var `i`: this For is its first handle; otherwise recurse the body.
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { if streq(src, fns, fnl, ns, nl) { res = s } else { res = a64_first_handle(fb, ns, nl, src, a) } ; s = nx }
      ## a `comptime for i in lo..hi` DECLARES the loop var `i` (like a range `for`): this CompForRange is
      ## its first handle; otherwise recurse the body. CONTINUE past (a `_ => s = 0` would mis-resolve a
      ## local declared after the unrolled loop → silent miscompile).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { if streq(src, rvs, rvl, ns, nl) { res = s } else { res = a64_first_handle(rb, ns, nl, src, a) } ; s = nx }
      ## a `comptime for f in typeinfo(T).fields` declares NO runtime local (its loop var is a comptime member
      ## name, not storage) — recurse the body for a local declared INSIDE it, then CONTINUE past (a `_ => s =
      ## 0` would stop the scan and mis-resolve a local declared after the unroll → silent miscompile).
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { res = a64_first_handle(rb, ns, nl, src, a) ; s = nx }
      ## a `comptime if` folds to ONE branch but its locals live in the fn frame — recurse BOTH branches
      ## (mirroring a64_local_scan's both-branch scan) and CONTINUE past it, so a local declared after a
      ## CompIf is still found (a `_ => s = 0` would stop the scan and mis-resolve it → silent miscompile).
      Stmt::CompIf(cc, th, el, nx) => { res = a64_first_handle(th, ns, nl, src, a) ; if res == 0 { res = a64_first_handle(el, ns, nl, src, a) } ; s = nx }
      Stmt::Loop(lb, lnx) => { res = a64_first_handle(lb, ns, nl, src, a) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { res = a64_first_handle(ub, ns, nl, src, a) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      ## an index/field-path assign declares no local, but MUST NOT terminate the scan (a leading
      ## `TABLE[2] = …` / `STATE.a.b = …` before the `mut` locals would otherwise hide them).
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      ## a `deref(p) = v` store declares no local but MUST NOT terminate the scan.
      Stmt::DerefAssign(dpe, dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  res
}

## Pre-order WORD scan for the frame layout, tree-wide: accumulate the word-size of each distinct
## (first-occurrence) local across the WHOLE fn tree (nested scopes too). If `target` (a first-occ Assign
## handle) is reached, return the NEGATIVE encoding `-(wordoff+1)`; else the running word count after
## this subtree. Value recursion + a `found` flag (no ptr(mut), no early-return-in-arm). Mirrors wat.al
## local_slot_scan; a struct/enum/array local advances by a64_val_words, a scalar by 1.
a64_local_scan := fn(list : ptr(mut Stmt), fn_head : ptr(mut Stmt), target : usize, before : i64, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut s := list
  mut b := before
  mut found := false
  mut result := 0
  while s != 0 and (not found) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if s == target { result = 0 - (b + 1) ; found = true }
        else {
          ## `mut xs : [E; N]` (no initializer): the parser's Num(0) sentinel would reserve ONE word, so
          ## the array's element stores would overrun the NEXT local — size the slot from the DECLARED
          ## array type instead. Gated to the fixed-array annotation form, so every other declaration
          ## keeps resolving its width from the VALUE exactly as before (byte-identical).
          if a64_first_handle(fn_head, ans, anl, src, a) == s {
            annw := a64_ann_arr_words(src, ans, anl, v, a, decls)
            if annw > 0 { b = b + annw } else { b = b + a64_val_words(v, src, a, decls) }
          }
          s = nx
        }
      }
      Stmt::While(c, body, nx) => {
        r := a64_local_scan(body, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = nx }
      }
      Stmt::If(c, th, el, nx) => {
        r := a64_local_scan(th, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true }
        else {
          r2 := a64_local_scan(el, fn_head, target, r, src, a, decls)
          if r2 < 0 { result = r2 ; found = true } else { b = r2 ; s = nx }
        }
      }
      Stmt::Match(msc, mah, mnx) => {
        mut arm := mah
        while arm != 0 and (not found) {
          am := deref(arm_p(arm))
          r := a64_local_scan(am.body_stmts, fn_head, target, b, src, a, decls)
          if r < 0 { result = r ; found = true } else { b = r ; arm = am.next }
        }
        if not found { s = mnx }
      }
      ## a `for … in …` loop var: a RANGE `for i in lo..hi` occupies ONE word; an ITERABLE `for x in xs`
      ## (null `fhi`) occupies TWO — the element var PLUS a hidden index at var-slot+1. First-occurrence
      ## at this For; then scan the body.
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        if s == target { result = 0 - (b + 1) ; found = true }
        else {
          if a64_first_handle(fn_head, fns, fnl, src, a) == s {
            ## a RANGE for `i` = 1 word; an ITERABLE for = the loop var's element words (a64_iter_stride,
            ## 1 for scalar) PLUS a hidden index word. Scalar stays 2 (stride 1 + 1) — byte-identical.
            if unchecked bitcast(usize, fhi) == 0 { b = b + a64_iter_stride(fn_head, src, flo, a, decls) + 1 } else { b = b + 1 }
          }
          r := a64_local_scan(fb, fn_head, target, b, src, a, decls)
          if r < 0 { result = r ; found = true } else { b = r ; s = nx }
        }
      }
      ## a `comptime for i in lo..hi` DECLARES a scalar loop var `i` = ONE word (like a RANGE for), reserved
      ## at its first-handle; then scan the body (emitted once per unroll iteration into these same slots).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => {
        if s == target { result = 0 - (b + 1) ; found = true }
        else {
          if a64_first_handle(fn_head, rvs, rvl, src, a) == s { b = b + 1 }
          r := a64_local_scan(rb, fn_head, target, b, src, a, decls)
          if r < 0 { result = r ; found = true } else { b = r ; s = nx }
        }
      }
      ## a `comptime for f in typeinfo(T).fields` declares NO scalar loop var (the member name is comptime),
      ## so reserve nothing for it; just scan the body (its locals live in the fn frame, reused per unroll
      ## iteration into the same slots) and CONTINUE past. Mirrors the Loop/Unchecked arms.
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => {
        r := a64_local_scan(rb, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = nx }
      }
      ## a `loop { }` / `unchecked { }` body is scanned like a while body — its locals are function-frame
      ## locals accumulated at the running offset; `break`/`continue` declare nothing (skip).
      Stmt::Loop(lb, lnx) => {
        r := a64_local_scan(lb, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = lnx }
      }
      Stmt::Unchecked(ub, unx) => {
        r := a64_local_scan(ub, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = unx }
      }
      ## a `comptime if` folds to ONE branch at emit time; its taken-branch locals live in the fn frame.
      ## Scan BOTH branches (a safe superset — an untaken branch's slots are merely reserved, never used),
      ## so whichever branch the emit selects finds its locals sized. Mirrors the `Stmt::If` scan.
      Stmt::CompIf(cc, th, el, nx) => {
        r := a64_local_scan(th, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true }
        else {
          r2 := a64_local_scan(el, fn_head, target, r, src, a, decls)
          if r2 < 0 { result = r2 ; found = true } else { b = r2 ; s = nx }
        }
      }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      ## index/field-path/deref assigns declare no local but MUST advance (see a64_first_handle).
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(dpe, dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  if found { result } else { b }
}

## Total WORDS of all distinct locals in the fn tree (target=0 never matches → returns the full count).
a64_count_locals := fn(head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  a64_local_scan(head, head, 0, 0, src, a, decls)
}

## Count SLICE ARGUMENTS (an `Expr::Slice` passed as a call argument) anywhere in an expression tree —
## the CALLER must materialize each into a reserved 2-word `{ptr,len}` agg block (a64_slarg_count reserves
## the frame words). Mirrors emit_a64_float_data_expr's traversal skeleton. Every counted site EXACTLY
## matches an emit-time materialization (the Call arm's slice-arg path), so reservation ≥ allocation.
a64_slarg_count_e := fn(e : ptr(Expr)) -> i64 {
  mut c := 0
  match deref(e) {
    Expr::Bin(op, l, r) => { c = a64_slarg_count_e(l) + a64_slarg_count_e(r) }
    Expr::If(cc, t, f) => { c = a64_slarg_count_e(cc) + a64_slarg_count_e(t) + a64_slarg_count_e(f) }
    Expr::Call(cs, cl, n, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; if ex_is_slice(ga.e) { c = c + 1 } ; c = c + a64_slarg_count_e(ga.e) ; g = ga.next } }
    Expr::Field(base, fs, fl) => { c = a64_slarg_count_e(base) }
    Expr::Index(base, idx) => { c = a64_slarg_count_e(base) + a64_slarg_count_e(idx) }
    Expr::Unchecked(inner) => { c = a64_slarg_count_e(inner) }
    Expr::StructLit(ss, sl, nf, fh) => { mut g := fh ; while g != 0 { ga := deref(arg_p(g)) ; c = c + a64_slarg_count_e(ga.e) ; g = ga.next } }
    Expr::ArrayLit(nel, eh) => { mut g := eh ; while g != 0 { ga := deref(arg_p(g)) ; c = c + a64_slarg_count_e(ga.e) ; g = ga.next } }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { mut g := ph ; while g != 0 { ga := deref(arg_p(g)) ; c = c + a64_slarg_count_e(ga.e) ; g = ga.next } }
    _ => {}
  }
  c
}
a64_slarg_count := fn(list : ptr(mut Stmt)) -> i64 {
  mut s := list
  mut c := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { c = c + a64_slarg_count_e(v) ; s = nx }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { c = c + a64_slarg_count_e(rv) } ; s = nx }
      Stmt::ExprStmt(e, nx) => { c = c + a64_slarg_count_e(e) ; s = nx }
      Stmt::While(cc, b, nx) => { c = c + a64_slarg_count_e(cc) + a64_slarg_count(b) ; s = nx }
      Stmt::If(cc, th, el, nx) => { c = c + a64_slarg_count_e(cc) + a64_slarg_count(th) + a64_slarg_count(el) ; s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { c = c + a64_slarg_count_e(fv) ; s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, ifv, ifnx) => { c = c + a64_slarg_count_e(ifv) ; s = ifnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { c = c + a64_slarg_count_e(iv) + a64_slarg_count_e(ii) ; s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { c = c + a64_slarg_count_e(fpv) ; s = fpnx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; c = c + a64_slarg_count(am.body_stmts) ; arm = am.next } ; s = mnx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { c = c + a64_slarg_count(fb) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { c = c + a64_slarg_count(rb) ; s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { c = c + a64_slarg_count(rb) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { c = c + a64_slarg_count(th) + a64_slarg_count(el) ; s = nx }
      Stmt::Loop(lb, lnx) => { c = c + a64_slarg_count(lb) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { c = c + a64_slarg_count(ub) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
  c
}

## Count the FRAME WORDS needed for anonymous aggregate-VALUE call arguments — a STRUCT LITERAL `S(…)`
## passed directly as a call argument (piece 1 of the §8 anonymous-aggregate materialization). Such a
## literal has no frame home, so the CALLER materializes its `struct_words` field words into a reserved
## A64_AGG block and passes the block ADDRESS by reference (emit_a64_aggval_arg). Mirrors a64_slarg_count
## but sums WORDS (each struct-lit reserves its full width). Tree-wide, so the reservation ≥ every
## emit-time allocation; an under-count would be a LOUD `brk` (never silent), an over-count wastes frame.
## A WIDE (SRET) struct/enum-returning CALL argument `f(mk(…))` counts here too: it has no destination
## local for the callee's x8 indirect-result pointer, so the caller reserves a block, hands ITS base down
## in x8 and then passes that same block by reference (emit_a64_sretcall_arg / emit_a64_enumsret_arg).
a64_aggval_words_e := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut c := 0
  match deref(e) {
    Expr::Bin(op, l, r) => { c = a64_aggval_words_e(l, src, a, decls) + a64_aggval_words_e(r, src, a, decls) }
    Expr::If(cc, t, f) => { c = a64_aggval_words_e(cc, src, a, decls) + a64_aggval_words_e(t, src, a, decls) + a64_aggval_words_e(f, src, a, decls) }
    Expr::Call(cs, cl, n, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; if expr_is_struct_lit(ga.e) { c = c + i64(struct_words(decls, src, expr_struct_lit_ns(ga.e), expr_struct_lit_nl(ga.e), a)) } ; if expr_is_enum_lit(ga.e) { c = c + 1 + i64(enum_max_arity(decls, src, expr_enum_lit_ns(ga.e), expr_enum_lit_nl(ga.e), a)) } ; crc := a64_call_ret_struct_span(ga.e, decls, src, a) ; if crc.n != 0 { c = c + i64(struct_words(decls, src, crc.s, crc.n, a)) } ; cre := a64_call_ret_enum_span(ga.e, decls, src, a) ; if cre.n != 0 { c = c + 1 + i64(enum_max_arity(decls, src, cre.s, cre.n, a)) } ; srr := a64_call_ret_sret_span(ga.e, decls, src, a) ; if srr.n != 0 { c = c + i64(struct_words(decls, src, srr.s, srr.n, a)) } ; ers := a64_call_ret_enum_sret_span(ga.e, decls, src, a) ; if ers.n != 0 { c = c + 1 + i64(enum_max_arity(decls, src, ers.s, ers.n, a)) } ; c = c + a64_aggval_words_e(ga.e, src, a, decls) ; g = ga.next } }
    Expr::Field(base, fs, fl) => { c = a64_aggval_words_e(base, src, a, decls) }
    Expr::Index(base, idx) => { c = a64_aggval_words_e(base, src, a, decls) + a64_aggval_words_e(idx, src, a, decls) }
    Expr::Unchecked(inner) => { c = a64_aggval_words_e(inner, src, a, decls) }
    Expr::StructLit(ss, sl, nf, fh) => { mut g := fh ; while g != 0 { ga := deref(arg_p(g)) ; c = c + a64_aggval_words_e(ga.e, src, a, decls) ; g = ga.next } }
    Expr::ArrayLit(nel, eh) => { mut g := eh ; while g != 0 { ga := deref(arg_p(g)) ; c = c + a64_aggval_words_e(ga.e, src, a, decls) ; g = ga.next } }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { mut g := ph ; while g != 0 { ga := deref(arg_p(g)) ; c = c + a64_aggval_words_e(ga.e, src, a, decls) ; g = ga.next } }
    _ => {}
  }
  c
}
a64_aggval_words := fn(list : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut s := list
  mut c := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { c = c + a64_aggval_words_e(v, src, a, decls) ; s = nx }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { c = c + a64_aggval_words_e(rv, src, a, decls) } ; s = nx }
      Stmt::ExprStmt(e, nx) => { c = c + a64_aggval_words_e(e, src, a, decls) ; s = nx }
      Stmt::While(cc, b, nx) => { c = c + a64_aggval_words_e(cc, src, a, decls) + a64_aggval_words(b, src, a, decls) ; s = nx }
      Stmt::If(cc, th, el, nx) => { c = c + a64_aggval_words_e(cc, src, a, decls) + a64_aggval_words(th, src, a, decls) + a64_aggval_words(el, src, a, decls) ; s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { c = c + a64_aggval_words_e(fv, src, a, decls) ; s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, ifv, ifnx) => { c = c + a64_aggval_words_e(ifv, src, a, decls) ; s = ifnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { c = c + a64_aggval_words_e(iv, src, a, decls) + a64_aggval_words_e(ii, src, a, decls) ; s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { c = c + a64_aggval_words_e(fpv, src, a, decls) ; s = fpnx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; c = c + a64_aggval_words(am.body_stmts, src, a, decls) ; arm = am.next } ; s = mnx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { c = c + a64_aggval_words(fb, src, a, decls) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { c = c + a64_aggval_words(rb, src, a, decls) ; s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { c = c + a64_aggval_words(rb, src, a, decls) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { c = c + a64_aggval_words(th, src, a, decls) + a64_aggval_words(el, src, a, decls) ; s = nx }
      Stmt::Loop(lb, lnx) => { c = c + a64_aggval_words(lb, src, a, decls) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { c = c + a64_aggval_words(ub, src, a, decls) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
  c
}

## The largest {disc, payload…} word count over this fn's ENUM PARAMS. An enum param is passed BY
## REFERENCE, and a `match <enum param>` first MATERIALIZES its words into the A64_MTMP frame temp
## (the `paramok` arms of both the value-Match and the statement-Match paths) before dispatching.
## a64_match_tmp_words only ever measured the match-over-INDEX scrutinee, so a fn whose only A64_MTMP
## user was an enum PARAM reserved NOTHING and the materialization wrote PAST the frame top into the
## CALLER's frame: for a WIDE enum (an 11-word `{disc, payload…}` written past a 32-byte frame) that
## clobbered the caller's saved x29/x30 AND the source block itself — a RAW SIGSEGV, not a clean trap.
## Measuring from the PARAM LIST rather than from the match sites also covers a match in the trailing
## VALUE position, which the statement scanner never visits. 0 for a fn with no enum param, so every
## other frame stays byte-identical (a64-only — the x86 self-build is untouched).
a64_param_enum_tmp_words := fn(params_head : ptr(mut Param), src : ptr(u8), decls : ptr(rt::Vec), a : rt::Arena) -> i64 {
  mut p := params_head
  mut mx := 0
  while p != 0 {
    pm := deref(param_p(p))
    mut ets := pm.ts
    mut etl := pm.tl
    if A64_SUB_GPL != 0 {
      if streq(src, pm.ts, pm.tl, A64_SUB_GPS, A64_SUB_GPL) { ets = A64_SUB_ITS ; etl = A64_SUB_ITL }
    }
    if etl != 0 {
      if enum_decl_of(decls, src, ets, etl) >= 0 {
        w := 1 + i64(enum_max_arity(decls, src, ets, etl, a))
        if w > mx { mx = w }
      }
    }
    p = pm.next
  }
  mx
}

## The largest enum-element word count (1+arity) over all `match s[i]` statements whose scrutinee is an
## INDEX into an enum `Slice(E)` PARAM, tree-wide — the words to reserve for the match-over-index temp
## region (A64_MTMP). 0 when there is no such match. Uses A64_PARAMS/A64_DECLS (set before this runs).
a64_match_tmp_words := fn(list : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> i64 {
  mut s := list
  mut mx := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Match(msc, mah, mnx) => {
        w := a64_match_index_enum_words(msc, src, a)
        if w > mx { mx = w }
        mut arm := mah
        while arm != 0 { am := deref(arm_p(arm)) ; bw := a64_match_tmp_words(am.body_stmts, src, a) ; if bw > mx { mx = bw } ; arm = am.next }
        s = mnx
      }
      Stmt::While(cc, b, nx) => { bw := a64_match_tmp_words(b, src, a) ; if bw > mx { mx = bw } ; s = nx }
      Stmt::If(cc, th, el, nx) => { bw := a64_match_tmp_words(th, src, a) ; if bw > mx { mx = bw } ; bw2 := a64_match_tmp_words(el, src, a) ; if bw2 > mx { mx = bw2 } ; s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { bw := a64_match_tmp_words(fb, src, a) ; if bw > mx { mx = bw } ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { bw := a64_match_tmp_words(rb, src, a) ; if bw > mx { mx = bw } ; s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { bw := a64_match_tmp_words(rb, src, a) ; if bw > mx { mx = bw } ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { bt := a64_match_tmp_words(th, src, a) ; if bt > mx { mx = bt } ; be := a64_match_tmp_words(el, src, a) ; if be > mx { mx = be } ; s = nx }
      Stmt::Loop(lb, lnx) => { bw := a64_match_tmp_words(lb, src, a) ; if bw > mx { mx = bw } ; s = lnx }
      Stmt::Unchecked(ub, unx) => { bw := a64_match_tmp_words(ub, src, a) ; if bw > mx { mx = bw } ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::Assign(ns, nl, v, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      _ => { s = 0 }
    }
  }
  mx
}
## Enum words to reserve in the match-temp region for `scrut` — the enum-element words (1+arity) if it is
## an INDEX into an enum `Slice(E)` PARAM, or (1 + max_arity) if it is a bare enum-PARAM Var (piece 3:
## a `match <enum param>` materializes the by-reference {disc, payload…} into the temp before matching),
## else 0.
a64_match_index_enum_words := fn(scrut : ptr(Expr), src : ptr(u8), a : rt::Arena) -> i64 {
  mut r := 0
  if ex_is_index(scrut) {
    ib := ex_index_base(scrut)
    es := a64_slice_param_enum_span(a64_params(), src, ex_var_ns(ib), ex_var_nl(ib), a64_decls())
    if es.n != 0 { r = a64_slice_param_agg_stride(a64_params(), src, ex_var_ns(ib), ex_var_nl(ib), a, a64_decls()) }
  }
  pel := a64_param_enum_nl(a64_params(), src, ex_var_ns(scrut), ex_var_nl(scrut), a64_decls())
  if pel != 0 { pw := 1 + i64(enum_max_arity(a64_decls(), src, a64_param_enum_ns(a64_params(), src, ex_var_ns(scrut), ex_var_nl(scrut), a64_decls()), pel, a)) ; if pw > r { r = pw } }
  r
}

## Frame BYTE offset (`[x29, #off]`) of the local `[ns,nl]`, or -1 — tree-wide, variable-size slots.
## Params occupy the first `pcount` words; the local's word index = pcount + (prior local words).
a64_local_off := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  target := a64_first_handle(head, ns, nl, src, a)
  r := a64_local_scan(head, head, target, pcount, src, a, decls)
  mut off := 0 - 1
  if r < 0 { off = 16 + ((0 - r) - 1) * 8 }
  off
}

a64_callee_defined := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, a : rt::Arena) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut ok := false
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn and streq(src, d.name_start, d.name_len, cs, cl) { ok = true }
    i += 1
  }
  ok
}

## Emit the `bl` target label for a call to `[cs,cl)`: the callee's `@extern("sym")` external symbol
## (Modules §7.2) when the callee is a bodyless import, else the bare call name. Resolves the callee among
## the kind-1 fn decls by name; a non-`@extern` callee keeps the source name (this backend's bare-label
## scheme — no module mangling).
a64_emit_bl_target := fn(in out sb : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) {
  cnt := rt::vec_len(deref(decls))
  mut es := 0
  mut en := 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and streq(src, d.name_start, d.name_len, cs, cl) {
      sym := extern_symbol(src, d.name_start, d.name_len)
      if sym.n != 0 { es = sym.s ; en = sym.n }
    }
    i += 1
  }
  if en != 0 { push_str(sb, str_at((src + es), en)) } else { push_str(sb, str_at((src + cs), cl)) }
}

## The generic type-param's NAME span (the `T` of `T : type`), 0/0 if `d` has none.
a64_tparam_name := fn(d : Decl, src : ptr(u8)) -> CSpan {
  mut p := d.params_head
  mut r := CSpan(s = 0, n = 0)
  while p != 0 { pm := deref(param_p(p)) ; if r.n == 0 and str_at((src + pm.ts), pm.tl) == "type" { r = CSpan(s = pm.ns, n = pm.nl) } ; p = pm.next }
  r
}
## Resolve the concrete type-arg span of a generic call `[cs,cl](args)` into A64_TA_S / A64_TA_N (0/0
## when unresolved → the caller uses the fail-loud stub). EXPLICIT: the arg at position 0 (a bare type
## name) when the full arg count INCLUDES the type-arg (`argc == arity`). IMPLICIT: inferred from value
## arg 0's type — a Var naming an enclosing PARAM yields that param's declared type span (`penv` = the
## enclosing fn's params_head). Then the ENCLOSING instance's own type-param is substituted (a nested
## generic call inside an instance). Writes globals (no multi-word return — the recursive-collection
## seed-truncation landmine).
a64_resolve_typearg := fn(decls : ptr(rt::Vec), src : ptr(u8), gi : i64, args_head : ptr(mut Arg), penv : ptr(mut Param), a : rt::Arena) {
  gd := deref(decl_get(decls, usize(gi)))
  argc := arg_list_count(args_head, a)
  mut ts := 0
  mut tl := 0
  if argc == i64(gd.arity) {
    ## EXPLICIT type-arg — at the type-param's source position (0 for a leading `T`, k for `gf(s, T, k)`).
    tpp := decl_tparam_pos(gd, src)
    ea := arg_expr_at(args_head, usize(tpp), a)
    ts = ex_var_ns(ea)
    tl = ex_var_nl(ea)
    ## a TUPLE `(T0, …)` type-arg parses as an ArrayLit (not a Var) — recover its full `(…)` source span
    ## (mono keys + the tag mangling both read it). Mirrors x86 type_arg_at. An ARRAY `[T; N]` type-arg is
    ## DEFERRED (needs an array VALUE-param by-ref path too): reject it (tl = 0) so the call falls to the
    ## fail-loud `brk` stub rather than emitting a wrong/undefined instance.
    if tl == 0 {
      tt := tuple_typearg_span(ea, src, a)
      ts = tt.s
      tl = tt.n
    }
    ## `f.type` (§8 field-derive) — the type-arg is `Field(Var(f), "type")` where `f` is the active
    ## comptime field-unroll loop var (A64_CF_VAR set): resolve to the CURRENT field's TYPE (A64_CF_TY),
    ## so `hash(f.type, v.(f))` routes into the per-field concrete instance. Mirrors x86's cf_ty type-arg.
    if tl == 0 and A64_CF_VAR_L != 0 and ex_is_field(ea) {
      cfb := expr_field_base(ea)
      cfbs := ex_var_ns(cfb)
      cfbl := ex_var_nl(cfb)
      cffs := expr_field_name_s(ea)
      cffl := expr_field_name_l(ea)
      if cfbl != 0 and streq(src, cfbs, cfbl, A64_CF_VAR_S, A64_CF_VAR_L) and str_at((src + cffs), cffl) == "type" {
        ts = A64_CF_TY_S
        tl = A64_CF_TY_L
      }
    }
  } else {
    ## IMPLICIT type-arg: infer from the VALUE arg whose param is declared as the type-param `T`. Find that
    ## param's value-arg index (params minus the type-param positions; default 0 — an `id(k)`-shaped call is
    ## unchanged), then read that arg's type: a Var naming an enclosing PARAM (its declared type — the prior
    ## behavior), a struct LITERAL (its bare struct name), or an enum LITERAL. This resolves `g(m, W(v=32))`
    ## (T inferred from the 2nd value arg, not arg 0) and keys the instance tag off the bare `W` (so the
    ## `(…)` field list is never mis-read as type-args → dedup with an explicit `g(W, …)`'s `h(w)`).
    tpn := a64_tparam_name(gd, src)
    mut infi := 0
    mut vi := 0
    mut p2 := gd.params_head
    mut foundp := false
    while p2 != 0 {
      pm2 := deref(param_p(p2))
      if str_at((src + pm2.ts), pm2.tl) == "type" {} else {
        if (not foundp) and tpn.n != 0 and streq(src, pm2.ts, pm2.tl, tpn.s, tpn.n) { infi = vi ; foundp = true }
        vi = vi + 1
      }
      p2 = pm2.next
    }
    a0 := arg_expr_at(args_head, usize(infi), a)
    vns := ex_var_ns(a0)
    vnl := ex_var_nl(a0)
    if vnl != 0 {
      mut p := penv
      while p != 0 { pm := deref(param_p(p)) ; if tl == 0 and streq(src, pm.ns, pm.nl, vns, vnl) { ts = pm.ts ; tl = pm.tl } ; p = pm.next }
    }
    if tl == 0 and expr_is_struct_lit(a0) { ts = expr_struct_lit_ns(a0) ; tl = expr_struct_lit_nl(a0) }
    if tl == 0 and expr_is_enum_lit(a0) { ts = expr_enum_lit_ns(a0) ; tl = expr_enum_lit_nl(a0) }
    ## a Var naming the CURRENT match arm's SINGLE payload BINDING (`hash(p)` inside `T.(var)(p) => …`):
    ## infer T from the variant's payload type (A64_ARM_* context). Verified against the arm's bind list
    ## (A64_ARM_BINDS) so an unrelated local is never mis-resolved. Enables the enum-derive recursion.
    if tl == 0 and vnl != 0 and A64_ARM_ENL != 0 and A64_ARM_BINDS != 0 {
      bh := unchecked bitcast(ptr(mut Bind), A64_ARM_BINDS)
      bidx := bind_list_index(bh, src, vns, vnl, a)
      mut bcnt := 0
      mut bb := bh
      while unchecked bitcast(usize, bb) != 0 { bcnt = bcnt + 1 ; bb = bnd_next(bb) }
      if bidx == 0 and bcnt == 1 {
        pty := variant_payload_type(decls, src, A64_ARM_ENS, A64_ARM_ENL, A64_ARM_VS, A64_ARM_VL, a)
        if pty.n != 0 { ts = pty.s ; tl = pty.n }
      }
    }
  }
  if A64_SUB_GPL != 0 and tl != 0 and streq(src, ts, tl, A64_SUB_GPS, A64_SUB_GPL) { ts = A64_SUB_ITS ; tl = A64_SUB_ITL }
  A64_TA_S = ts
  A64_TA_N = tl
  ## MULTI type-param (leading RUN, `pick3(A, B, C, …)`): resolve the 2nd/3rd EXPLICIT type-args (bare
  ## scalar names at source positions 1/2). Reset first so a single-type-param instance carries 0/0.
  A64_TA_S2 = 0
  A64_TA_N2 = 0
  A64_TA_S3 = 0
  A64_TA_N3 = 0
  lead := decl_leading_tparam_run(gd, src)
  cntt := decl_tparam_count(gd, src)
  if argc == i64(gd.arity) and cntt == lead and lead >= 2 {
    e1 := arg_expr_at(args_head, 1, a)
    mut s2 := ex_var_ns(e1)
    mut l2 := ex_var_nl(e1)
    if A64_SUB_GPL != 0 and l2 != 0 and streq(src, s2, l2, A64_SUB_GPS, A64_SUB_GPL) { s2 = A64_SUB_ITS ; l2 = A64_SUB_ITL }
    A64_TA_S2 = s2
    A64_TA_N2 = l2
  }
  if argc == i64(gd.arity) and cntt == lead and lead >= 3 {
    e2 := arg_expr_at(args_head, 2, a)
    mut s3 := ex_var_ns(e2)
    mut l3 := ex_var_nl(e2)
    if A64_SUB_GPL != 0 and l3 != 0 and streq(src, s3, l3, A64_SUB_GPS, A64_SUB_GPL) { s3 = A64_SUB_ITS ; l3 = A64_SUB_ITL }
    A64_TA_S3 = s3
    A64_TA_N3 = l3
  }
}
## Record instance (gi, ts, tl + the 2nd/3rd type-args from A64_TA_*2/*3) if new (dedup by gi + all
## type-arg text). The 2nd/3rd spans are read from the resolver's OUT globals (set by the immediately
## preceding a64_resolve_typearg). Bounded by the array size.
a64_inst_add := fn(src : ptr(u8), gi : usize, ts : usize, tl : usize) {
  mut i := 0
  mut found := false
  while i < A64_INST_N {
    same0 := A64_INST_GI[i] == gi and streq(src, A64_INST_TS[i], A64_INST_TL[i], ts, tl)
    same2 := streq(src, A64_INST_TS2[i], A64_INST_TL2[i], A64_TA_S2, A64_TA_N2)
    same3 := streq(src, A64_INST_TS3[i], A64_INST_TL3[i], A64_TA_S3, A64_TA_N3)
    if same0 and same2 and same3 { found = true }
    i = i + 1
  }
  if (not found) and A64_INST_N < 512 {
    A64_INST_GI[A64_INST_N] = gi
    A64_INST_TS[A64_INST_N] = ts
    A64_INST_TL[A64_INST_N] = tl
    A64_INST_TS2[A64_INST_N] = A64_TA_S2
    A64_INST_TL2[A64_INST_N] = A64_TA_N2
    A64_INST_TS3[A64_INST_N] = A64_TA_S3
    A64_INST_TL3[A64_INST_N] = A64_TA_N3
    A64_INST_N = A64_INST_N + 1
  }
}




## Resolve the concrete type named by a `typeinfo(X)` range-bound expression. The `.fields.len` and
## `.variants.len` forms leave one Field wrapper around the Call; `.n` passes the Call directly. Unlike
## the old range fold, this keeps the explicit X and substitutes whichever active generic parameter it
## names instead of always using A64_SUB_ITS.
a64_range_typeinfo_arg := fn(base : ptr(Expr), field_s : usize, src : ptr(u8)) -> CSpan {
  ## The lean backend's Expr::Call/Field shape can be rewritten by the generic-enum parser path, while
  ## the source spelling is stable. Recover the nearest `typeinfo(` before the outer member and slice its
  ## balanced argument; this also handles both `.n` and `.fields.len`/`.variants.len`.
  mut r := CSpan(s = 0, n = 0)
  mut q := field_s
  mut open := 0
  mut found := false
  while q > 0 and not found {
    q = q - 1
    if q + 9 <= field_s and str_at((src + q), 9) == "typeinfo(" { open = q + 9 ; found = true }
  }
  if found {
    mut p := open
    mut depth := 1
    while p < field_s and depth != 0 {
      c := str_at((src + p), 1)
      if c == "(" { depth = depth + 1 }
      else if c == ")" { depth = depth - 1 }
      if depth != 0 { p = p + 1 }
    }
    if depth == 0 {
      mut s := open
      mut n := p - open
      while n != 0 and (str_at((src + s), 1) == " " or str_at((src + s), 1) == "\n" or str_at((src + s), 1) == "\t") { s = s + 1 ; n = n - 1 }
      while n != 0 and (str_at((src + s + n - 1), 1) == " " or str_at((src + s + n - 1), 1) == "\n" or str_at((src + s + n - 1), 1) == "\t") { n = n - 1 }
      if A64_SUB_GPL != 0 and n != 0 and streq(src, s, n, A64_SUB_GPS, A64_SUB_GPL) { s = A64_SUB_ITS ; n = A64_SUB_ITL }
      else if A64_SUB_GPL2 != 0 and n != 0 and streq(src, s, n, A64_SUB_GPS2, A64_SUB_GPL2) { s = A64_SUB_ITS2 ; n = A64_SUB_ITL2 }
      else if A64_SUB_GPL3 != 0 and n != 0 and streq(src, s, n, A64_SUB_GPS3, A64_SUB_GPL3) { s = A64_SUB_ITS3 ; n = A64_SUB_ITL3 }
      r = CSpan(s = s, n = n)
    }
  }
  r
}

## Resolve a comptime-for RANGE BOUND to its constant value: a literal, or a module-level const `N := k`
## resolved by name (comptime_for_range's `0..N`). Mirrors the subset of the x86 lower's global_init_value
## the corpus range bounds use (literal + module const; no const arithmetic — range bounds carry none).
a64_comp_range_bound := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8)) -> i64 {
  mut r := 0
  match deref(e) {
    Expr::Num(x, s, n) => { r = i64(x) }
    Expr::BoolLit(x) => { r = i64(x) }
    Expr::Var(vs, vn) => {
      cnt := rt::vec_len(deref(decls))
      mut i := 0
      while i < cnt {
        d := deref(decl_get(decls, i))
        if d.kind == 0 and d.is_fn == false and streq(src, d.name_start, d.name_len, vs, vn) {
          if unchecked bitcast(usize, d.value) != 0 { r = ex_value_init(d.value) }
        }
        i = i + 1
      }
    }
    ## GENERICS (§8): `typeinfo(X).n` / `typeinfo(X).fields.len` / `typeinfo(X).variants.len` — the
    ## comptime MEMBER COUNT of the explicit X type argument, not automatically the current monomorph
    ## instance. STRUCT → field count, ENUM → variant count, TUPLE → component count, ARRAY → length N.
    Expr::Field(b, fs, fl) => {
      fnm := str_at((src + fs), fl)
      rt := a64_range_typeinfo_arg(b, fs, src)
      if (fnm == "n" or fnm == "len") and rt.n != 0 {
        itb := base_type_name(src, rt.s, rt.n)
        sd := struct_decl_of(decls, src, itb.s, itb.n)
        ed := enum_decl_of(decls, src, itb.s, itb.n)
        if sd >= 0 {
          sdd := deref(decl_get(decls, usize(sd)))
          mut fc := 0
          mut f := sdd.fields_head
          while f != 0 { fc = fc + 1 ; f = deref(fld_p(f)).next }
          r = i64(fc)
        } else if ed >= 0 {
          edd := deref(decl_get(decls, usize(ed)))
          mut vc := 0
          mut vf := edd.fields_head
          while vf != 0 { vc = vc + 1 ; vf = deref(fld_p(vf)).next }
          r = i64(vc)
        } else if str_at((src + rt.s), 1) == "(" {
          ## TUPLE component count = top-level commas + 1. Scanned inline over the `(…)` source span (NOT
          ## via `typearg_at`, whose LSpan return is truncated in this a64 emit context — a seed landmine).
          mut tdepth := 0
          mut tcnt := 1
          mut tp := rt.s + 1
          mut tgo := true
          while tgo {
            tc := str_at((src + tp), 1)
            if tc == ")" and tdepth == 0 { tgo = false }
            else {
              if tc == "(" or tc == "[" { tdepth = tdepth + 1 }
              else if (tc == ")" or tc == "]") and tdepth > 0 { tdepth = tdepth - 1 }
              else if tc == "," and tdepth == 0 { tcnt = tcnt + 1 }
              tp = tp + 1
            }
          }
          r = i64(tcnt)
        } else if str_at((src + rt.s), 1) == "[" {
          ## ARRAY `[E; N]` element COUNT = the length N (the `typeinfo([E;N]).n` `comptime for` bound the
          ## `Array(_)` eq/lt derive unrolls over). Scanned INLINE: find the top-level `;`, parse the digits.
          mut ndep := 0
          mut nsemi := rt.s + 1
          mut np := rt.s + 1
          mut ngo := true
          while ngo {
            nc := str_at((src + np), 1)
            if nc == "(" or nc == "[" { ndep = ndep + 1 }
            else if (nc == ")" or nc == "]") and ndep > 0 { ndep = ndep - 1 }
            else if nc == ";" and ndep == 0 { nsemi = np ; ngo = false }
            np = np + 1
          }
          mut nlp := nsemi + 1
          while str_at((src + nlp), 1) == " " { nlp = nlp + 1 }
          mut nval := 0
          mut ndg := true
          while ndg { nbs := bytes(str_at((src + nlp), 1)) ; nb := nbs[0] ; if nb >= 48 and nb <= 57 { nval = nval * 10 + i64(nb - 48) ; nlp = nlp + 1 } else { ndg = false } }
          r = nval
        }
      }
    }
    _ => {}
  }
  r
}

## The i-th argument expression of an arg list (0-based), or a null Expr ptr if absent — for `asm(…)`
## `{i}` positional-operand substitution.
a64_arg_at := fn(head : ptr(mut Stmt), i : usize, a : rt::Arena) -> ptr(Expr) {
  mut g := head
  mut k := 0
  mut res : usize = 0
  while g != 0 { ga := deref(arg_p(g)) ; if k == i { res = unchecked bitcast(usize, ga.e) } ; k = k + 1 ; g = ga.next }
  unchecked bitcast(ptr(Expr), res)
}

a64_is_global := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut found := false
  while i < cnt {
    d := deref(decl_get(decls, i))
    ## a scalar (Num/Bool) OR a float (FloatLit) module global — both live in `.data` and are read/written
    ## through their label (a float global's cell is a `.double`; its bits ride the integer global path).
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, ns, nl) { if ex_value_is_scalar(d.value) { found = true } ; if expr_is_float_lit(d.value) { found = true } }
    i += 1
  }
  found
}

## --- GLOBAL AGGREGATES (struct/array/enum module globals): `.data` layout + field-chain access. ---
## An aggregate global (struct/array/enum initializer) is laid in `.data` as ascending 8-byte cells
## (nested structs FLATTENED inline, like the x86 lower), addressed by its plain source-name label; a
## field chain rooted at it (`STATE.inner.a`, ANY depth) reads/writes the cell at LABEL + cum-off*8.
a64_value_is_agg := fn(v : ptr(Expr)) -> bool { expr_is_struct_lit(v) or expr_is_enum_lit(v) or ex_is_array_lit(v) }

## The VALUE expr of the module GLOBAL named `[ns,nl]` (a kind-0 arity-0 non-fn decl), else null.
a64_global_value := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> ptr(Expr) {
  cnt := rt::vec_len(deref(decls))
  mut res : usize = 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, ns, nl) { res = unchecked bitcast(usize, d.value) }
    i += 1
  }
  unchecked bitcast(ptr(Expr), res)
}

## The STRUCT-type span of the module GLOBAL named `[ns,nl]` IFF its initializer is a struct literal
## (`ORIGIN := Pt(…)` / `mut S := Pt(…)`), else {0,0}. Used to type + size a local snapshot `p := GLOBAL`.
a64_global_agg_struct_span := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> CSpan {
  gv := a64_global_value(decls, src, ns, nl)
  mut r := CSpan(s = 0, n = 0)
  if unchecked bitcast(usize, gv) != 0 { if expr_is_struct_lit(gv) { r = CSpan(s = expr_struct_lit_ns(gv), n = expr_struct_lit_nl(gv)) } }
  r
}
## The ENUM-type span of the module GLOBAL named `[ns,nl]` IFF its initializer is an enum literal
## (`mut STATE := Color.Green(40)`), else {0,0}. Used to type + size a local snapshot `s := GLOBAL`.
a64_global_agg_enum_span := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> CSpan {
  gv := a64_global_value(decls, src, ns, nl)
  mut r := CSpan(s = 0, n = 0)
  if unchecked bitcast(usize, gv) != 0 { if expr_is_enum_lit(gv) { r = CSpan(s = expr_enum_lit_ns(gv), n = expr_enum_lit_nl(gv)) } }
  r
}

## Emit the `.data` cells of an aggregate global INITIALIZER recursively (mirrors lower::emit_global_data_cells):
## a struct-lit emits its field args in order (a nested struct field flattens); an array-lit its elements; an
## enum-lit `[disc, payload…, pad]` to `1+enum_inst_words`; a float `.double`; anything else `.quad` of its int.
emit_a64_global_cells := fn(e : ptr(Expr), in out sb : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) {
  if expr_is_struct_lit(e) {
    mut g := ex_struct_lit_args(e)
    while g != 0 { ga := deref(arg_p(g)) ; emit_a64_global_cells(ga.e, sb, decls, src, a) ; g = ga.next }
  } else if ex_is_array_lit(e) {
    mut ag := ex_array_lit_ehead(e)
    while ag != 0 { aga := deref(arg_p(ag)) ; emit_a64_global_cells(aga.e, sb, decls, src, a) ; ag = aga.next }
  } else if expr_is_enum_lit(e) {
    push_str(sb, "  .quad ") ; push_int(sb, variant_index(decls, src, expr_enum_lit_ns(e), expr_enum_lit_nl(e), expr_enum_variant_ns(e), expr_enum_variant_nl(e), a)) ; push_str(sb, "\n")
    mut np := 0
    mut eg := ex_enum_lit_args(e)
    while eg != 0 { ega := deref(arg_p(eg)) ; push_str(sb, "  .quad ") ; push_int(sb, ex_value_init(ega.e)) ; push_str(sb, "\n") ; np += 1 ; eg = ega.next }
    emxw := i64(enum_inst_words(decls, src, expr_enum_lit_ns(e), expr_enum_lit_nl(e), a))
    mut padk := np
    while padk < emxw { push_str(sb, "  .quad 0\n") ; padk += 1 }
  } else if expr_is_float_lit(e) {
    push_str(sb, "  .double ") ; push_str(sb, str_at((src + expr_float_lit_ns(e)), expr_float_lit_nl(e))) ; push_str(sb, "\n")
  } else {
    push_str(sb, "  .quad ") ; push_int(sb, ex_value_init(e)) ; push_str(sb, "\n")
  }
}

## The STRUCT-type name span of the place expr `e` (a field chain rooted at a struct GLOBAL), else {0,0}.
## Recursion mirrors lower::global_place: a root Var → its struct-lit's type name; `base.f` → the field's
## type within base's (struct) type. A scalar leaf still yields its scalar type name (for the scalar gate).
a64_gchain_type := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => {
      gv := a64_global_value(decls, src, s, n)
      if unchecked bitcast(usize, gv) != 0 { if expr_is_struct_lit(gv) { r = CSpan(s = expr_struct_lit_ns(gv), n = expr_struct_lit_nl(gv)) } }
    }
    Expr::Field(base, fs, fl) => {
      bt := a64_gchain_type(base, decls, src, a)
      if bt.n != 0 { if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { r = field_type_span(decls, src, bt.s, bt.n, fs, fl, a) } }
    }
    _ => {}
  }
  r
}

## The cumulative WORD offset of the place `e` within its root struct global's `.data`, or -1 if `e` is
## not a struct-global field chain. Recursive: a root Var → 0; `base.f` → base-off + field_word_offset.
a64_gchain_woff := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> i64 {
  mut r := 0 - 1
  match deref(e) {
    Expr::Var(s, n) => {
      gv := a64_global_value(decls, src, s, n)
      if unchecked bitcast(usize, gv) != 0 { if expr_is_struct_lit(gv) { r = 0 } }
    }
    Expr::Field(base, fs, fl) => {
      boff := a64_gchain_woff(base, decls, src, a)
      bt := a64_gchain_type(base, decls, src, a)
      if boff >= 0 and bt.n != 0 { if struct_decl_of(decls, src, bt.s, bt.n) >= 0 {
        fwo := field_word_offset(decls, src, bt.s, bt.n, fs, fl, a)
        if fwo >= 0 { r = boff + fwo }
      } }
    }
    _ => {}
  }
  r
}

## The root VAR name span of a field chain (`STATE.a.b` → STATE), descending through `Field` bases.
a64_gchain_root := fn(e : ptr(Expr)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => { r = CSpan(s = s, n = n) }
    Expr::Field(base, fs, fl) => { r = a64_gchain_root(base) }
    _ => {}
  }
  r
}

## --- LOCAL AGGREGATES: nested field-chain access rooted at a struct LOCAL (`c.v.a`, ANY depth). ---
## The LOCAL analogue of a64_gchain_type/a64_gchain_woff: a struct local occupies `struct_words`
## CONTIGUOUS frame words (nested structs FLATTENED inline, like the global/x86 layout), so a field chain
## rooted at it reads/writes the slot at (root frame base + cum-word-off*8). These two resolvers descend
## the `Field(Field(…Var…),…)` chain the same way the global pair does, but root the type at the local's
## declared struct type (a64_local_struct_ns/nl) instead of a global's `.data` initializer.

## The STRUCT-type name span of the place `e` (a field chain rooted at a struct LOCAL), else {0,0}. A root
## Var → its local struct type name; `base.f` → the field's type within base's (struct) type. A scalar leaf
## still yields its scalar type name (for the scalar gate).
a64_lchain_type := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => {
      lsn := a64_local_struct_nl(body_head, src, s, n, a)
      if lsn != 0 { r = CSpan(s = a64_local_struct_ns(body_head, src, s, n, a), n = lsn) }
    }
    Expr::Field(base, fs, fl) => {
      bt := a64_lchain_type(base, body_head, src, a, decls)
      if bt.n != 0 { if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { r = field_type_span(decls, src, bt.s, bt.n, fs, fl, a) } }
    }
    _ => {}
  }
  r
}

## The cumulative WORD offset of the place `e` within its ROOT struct local's frame slots, or -1 if `e` is
## not a struct-local field chain. Recursive: a root Var → 0; `base.f` → base-off + field_word_offset.
a64_lchain_woff := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut r := 0 - 1
  match deref(e) {
    Expr::Var(s, n) => {
      if a64_local_struct_nl(body_head, src, s, n, a) != 0 { r = 0 }
    }
    Expr::Field(base, fs, fl) => {
      boff := a64_lchain_woff(base, body_head, src, a, decls)
      bt := a64_lchain_type(base, body_head, src, a, decls)
      if boff >= 0 and bt.n != 0 { if struct_decl_of(decls, src, bt.s, bt.n) >= 0 {
        fwo := field_word_offset(decls, src, bt.s, bt.n, fs, fl, a)
        if fwo >= 0 { r = boff + fwo }
      } }
    }
    _ => {}
  }
  r
}


## Is the module GLOBAL named `[ns,nl]` an ARRAY global (kind-0 arity-0 with an array-literal init)?
a64_is_array_global := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> bool {
  gv := a64_global_value(decls, src, ns, nl)
  if unchecked bitcast(usize, gv) == 0 { return false }
  ex_is_array_lit(gv)
}

## The element STRUCT span (ns,nl) of an ARRAY GLOBAL `[ns,nl]` — its initializer ArrayLit's FIRST
## element StructLit name — or {0,0}. The `.data` twin of `a64_arr_elem_struct_span` (which resolves a
## LOCAL array-lit through the fn body). Used to type `ARR[i]` element access on a struct array global.
a64_garr_elem_struct_span := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  gv := a64_global_value(decls, src, ns, nl)
  if unchecked bitcast(usize, gv) == 0 { return r }
  if not ex_is_array_lit(gv) { return r }
  eh := ex_array_lit_ehead(gv)
  if eh != 0 {
    ga0 := deref(arg_p(eh))
    ge0 := ga0.e
    if expr_is_struct_lit(ge0) { r = CSpan(s = expr_struct_lit_ns(ge0), n = expr_struct_lit_nl(ge0)) }
  }
  r
}

## True when the ARRAY-LIT `v` is HOMOGENEOUS in one named STRUCT — EVERY element is a StructLit of the
## SAME type. A TUPLE literal `(Pt(…), 12)` parses as an ArrayLit too (tuples reuse the aggregate
## surface), but its components have DIFFERENT widths, so a first-element stride would mis-address every
## component after the first — `t.1` would read the struct component's word 1. Element access below
## fires ONLY on a homogeneous struct array; a tuple keeps falling through to the fail-loud `brk`.
a64_alit_homog_slit := fn(v : ptr(Expr), src : ptr(u8)) -> bool {
  if unchecked bitcast(usize, v) == 0 { return false }
  if not ex_is_array_lit(v) { return false }
  eh := ex_array_lit_ehead(v)
  if eh == 0 { return false }
  h0 := deref(arg_p(eh))
  e0 := h0.e
  if not expr_is_struct_lit(e0) { return false }
  hs := expr_struct_lit_ns(e0)
  hn := expr_struct_lit_nl(e0)
  mut g := eh
  mut ok := true
  while g != 0 {
    ga := deref(arg_p(g))
    if not expr_is_struct_lit(ga.e) { ok = false }
    if expr_is_struct_lit(ga.e) {
      if not streq(src, expr_struct_lit_ns(ga.e), expr_struct_lit_nl(ga.e), hs, hn) { ok = false }
    }
    g = ga.next
  }
  ok
}

## AGGREGATE ARRAY ELEMENT (§8.3): the element STRUCT span of the array named `[ns,nl]` when it is a
## fixed array whose elements are a SCALAR-ONLY struct — either a LOCAL `arr := [S(..), …]` (resolved
## through A64_BODY) or an array GLOBAL — else {0,0}. ONE place decides the shape so frame SIZING
## (`a64_val_words`), local TYPING (`a64_local_struct_ns`/`_nl`) and the three emit paths (field read,
## whole-element copy, whole-element write) can never disagree — a disagreement here would size a
## destination for one word and copy `stride` words over the next local (a silent corruption).
## Non-scalar (nested-aggregate) element structs stay OUT: their field offsets need the flattened
## layout the element paths do not compute, so they keep falling through to the fail-loud `brk`.
a64_arrname_elem_struct_span := fn(src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if nl == 0 { return r }
  if A64_BODY != 0 {
    if a64_alit_homog_slit(a64_local_rhs(a64_body(), src, ns, nl, a), src) { r = a64_arr_elem_struct_span(a64_body(), src, ns, nl, a) }
    ## `mut xs : [E; N]` — the DECLARED (uninitialized) form has no array literal to read the element
    ## struct off, so take it from the annotation. A type form can never be a tuple, so the
    ## `a64_alit_homog_slit` heterogeneity guard has nothing to do here.
    if r.n == 0 {
      ats := a64_local_arrty_span(a64_body(), src, ns, nl, a)
      if ats.n != 0 { r = a64_arrty_elem(src, ats.s, ats.n) }
    }
  }
  if r.n == 0 {
    if a64_alit_homog_slit(a64_global_value(decls, src, ns, nl), src) { r = a64_garr_elem_struct_span(decls, src, ns, nl) }
  }
  if r.n != 0 {
    if struct_decl_of(decls, src, r.s, r.n) < 0 { r = CSpan(s = 0, n = 0) }
  }
  ## PLAIN (arity-0) struct elements only: a generic / comptime-value type-fn element would PANIC in
  ## `struct_words`. A NESTED-AGGREGATE element struct is now IN (it was excluded by an all-scalar gate):
  ## its whole-element copies/writes are width-correct word copies, and the two SCALAR-LEAF paths
  ## (`xs[i].f` read, `xs[i].f = e` write) each gate on THAT FIELD being scalar, so an aggregate field
  ## never silently reads/writes its word 0 — it routes to the deep-place composition or stays fail-loud.
  if r.n != 0 {
    if not struct_plain(decls, src, r.s, r.n) { r = CSpan(s = 0, n = 0) }
  }
  r
}

## The same, keyed on an INDEX expression `xs[i]` (its base must be a bare Var naming the array).
a64_index_elem_struct_span := fn(v : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if not ex_is_index(v) { return r }
  bx := ex_index_base(v)
  r = a64_arrname_elem_struct_span(src, ex_var_ns(bx), ex_var_nl(bx), a, decls)
  ## A bounded deep aggregate read (`xs[i].arr[j]`) has a non-Var base. Resolve only a plain,
  ## word-granular struct leaf; fixed-array PARAM roots use their Param metadata, while byte/packed/
  ## heterogeneous forms stay on old paths.
  if r.n == 0 and (not a64_ex_is_var(bx)) and A64_BODY != 0 and (not a64_place_root_inferred_local(bx, a64_body(), src, a, decls)) {
    d := a64_place_idx_ty(bx, a64_body(), src, a, decls)
    if d.n != 0 and struct_decl_of(decls, src, d.s, d.n) >= 0 and struct_plain(decls, src, d.s, d.n) {
      if std_struct_is_word_granular(decls, src, d.s, d.n, a) { r = d }
    }
  }
  r
}

## --- TYPED-DECLARATION (annotation) SOURCE-SCAN: `mut xs : [Cell; 3]` (Types §9.4) ---
## The parser keeps the `Stmt.Assign` shape for an explicitly uninitialized `name : T` and plants a
## `Num(0)` SENTINEL value (so no bootstrap-sensitive AST field is added), which leaves the element TYPE
## and COUNT recorded ONLY in the source. These scans recover them — the same source-scan technique
## `ann_scan_signed` uses for `iN` signedness — so the frame can SIZE such an array and the element
## paths can TYPE it. Without them a `mut xs : [S; N]` reserved ONE word and every access was fail-loud.


## `[E; N]` → the ELEMENT type span E (trimmed), else {0,0}.
a64_arrty_elem := fn(src : ptr(u8), ts : usize, tl : usize) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  semi := arrty_semi(src, ts, tl)
  if semi == 0 { return r }
  mut es := ts + 1
  mut go := true
  while go and es < semi { c := str_at((src + es), 1) ; if c == " " or c == "\t" { es = es + 1 } else { go = false } }
  mut ee := semi
  mut trim := true
  while trim and ee > es { t := str_at((src + ee - 1), 1) ; if t == " " or t == "\t" { ee = ee - 1 } else { trim = false } }
  if ee > es { r = CSpan(s = es, n = ee - es) }
  r
}

## The WORD width of the type named `[ts,tl)`: `struct_words` for a PLAIN struct, `1 + enum_max_arity`
## for an enum, `N * width(E)` for a nested `[E; N]`, 1 for a scalar; 0 = UNSUPPORTED (a generic /
## comptime-value type-fn whose layout resolve would PANIC without a binding, a `str`, or an unresolvable
## nested element). Every caller gates on `> 0`, so an unsupported type keeps the fail-loud default.
a64_tyname_words := fn(src : ptr(u8), ts : usize, tl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut r := 0
  if tl == 0 { return r }
  if struct_decl_of(decls, src, ts, tl) >= 0 {
    if not struct_plain(decls, src, ts, tl) { return r }
    ## CLAYOUT S3(d) — supported standard-byte elements reserve ceil(stride/8) words, while every
    ## other byte-layout shape keeps the existing located fence and every word-tier struct keeps the
    ## historical struct_words answer.
    if std_array_elem_byte_tier(decls, src, ts, tl, a) { r = i64(array_elem_word_reservation(decls, src, ts, tl, a)) ; return r }
    require_no_byte_layout_array_elem(decls, src, ts, tl, a)
    r = i64(struct_words(decls, src, ts, tl, a))
    return r
  }
  if enum_decl_of(decls, src, ts, tl) >= 0 {
    r = 1 + i64(enum_max_arity(decls, src, ts, tl, a))
    return r
  }
  es := a64_arrty_elem(src, ts, tl)
  if es.n != 0 {
    ew := a64_tyname_words(src, es.s, es.n, a, decls)
    nel := arrty_nel(src, ts, tl)
    if ew > 0 { if nel > 0 { r = nel * ew } }
    return r
  }
  if str_at((src + ts), tl) == "str" { return r }
  1
}

## The runtime ARRAY-ELEMENT STRIDE in BYTES. The byte-tier arm is the only intentional divergence from
## the old word model; keeping the fallback expressed through a64_tyname_words preserves historical
## word-element emission exactly.
a64_arr_elem_stride_bytes := fn(src : ptr(u8), ts : usize, tl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if std_array_elem_byte_tier(decls, src, ts, tl, a) { return i64(layout_elem_stride_bytes(decls, src, ts, tl, a)) }
  i64(a64_tyname_words(src, ts, tl, a, decls)) * 8
}

## The static element COUNT of a declaration `name : [E; N]` whose value is NOT an array literal (the
## explicitly uninitialized form), else 0 — so an INITIALIZED `xs : [E;N] = [..]` keeps every existing
## ArrayLit-driven answer byte-identical.
a64_ann_arr_nel := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr)) -> i64 {
  if ex_is_array_lit(v) { return 0 }
  an := ann_span(src, ns, nl)
  if an.n == 0 { return 0 }
  arrty_nel(src, an.s, an.n)
}

## The declared ELEMENT type span of the same, else {0,0}.
a64_ann_arr_elem := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if ex_is_array_lit(v) { return r }
  an := ann_span(src, ns, nl)
  if an.n != 0 { r = a64_arrty_elem(src, an.s, an.n) }
  r
}

## The frame WORDS of a declaration `name : [E; N]` with no array-literal initializer, else 0. Gated on
## the annotation being the FIXED-ARRAY form so nothing else (a struct / generic / scalar annotation)
## changes its `a64_val_words` sizing — those keep resolving from the value exactly as before.
a64_ann_arr_words := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if ex_is_array_lit(v) { return 0 }
  an := ann_span(src, ns, nl)
  if an.n == 0 { return 0 }
  if arrty_semi(src, an.s, an.n) == 0 { return 0 }
  a64_tyname_words(src, an.s, an.n, a, decls)
}

## The `: T` annotation at the DECLARATION SITE of the LOCAL `[ns,nl]` (an `Expr::Var` carries the span
## of its USE, not of the binding), or {0,0}. Same scan shape as `a64_is_array_local` — every Stmt kind
## is walked past, so a local declared after any statement is still found.
a64_local_ann_span := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { r = ann_span(src, ans, anl) }
      _ => {}
    }
  }
  r
}

## The DECLARED fixed-array type span of the local `[ns,nl]` (`mut xs : [Cell; 3]` → `[Cell; 3]`), or
## {0,0}. This is the only place a LOCAL's array TYPE (rather than its literal) is recovered.
a64_local_arrty_span := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  an := a64_local_ann_span(head, src, ns, nl, a)
  if an.n == 0 { return r }
  if arrty_semi(src, an.s, an.n) != 0 { r = an }
  r
}

## The deep-place resolver's inferred LOCAL root marker. Keep the admission narrower than the ordinary
## array-element paths: only an unannotated array-literal local whose homogeneous struct element has
## word-granular layout can use the composed address formula. Globals, params, annotated locals,
## packed/byte-tier, heterogeneous, and non-struct arrays continue through existing paths or stay loud.
a64_inferred_local_elem_span := fn(src : ptr(u8), body_head : ptr(mut Stmt), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if a64_is_array_local(body_head, src, ns, nl, a) and a64_local_ann_span(body_head, src, ns, nl, a).n == 0 {
    v := a64_local_rhs(body_head, src, ns, nl, a)
    if a64_alit_homog_slit(v, src) {
      es := a64_arr_elem_struct_span(body_head, src, ns, nl, a)
      if es.n != 0 and std_struct_is_word_granular(decls, src, es.s, es.n, a) { r = es }
    }
  }
  r
}

## Whether a deep place is rooted at the bounded inferred-local array admission above. The scalar
## `xs[i].cell.vals[j]` slice may compose through that root, but aggregate leaves remain fail-loud;
## keep this predicate separate so the shared type resolver does not accidentally open `xs[i].arr[j] = P(...)`.
a64_place_root_inferred_local := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if unchecked bitcast(usize, e) == 0 { return r }
  match deref(e) {
    Expr::Var(ns, nl) => {
      if a64_is_array_local(body_head, src, ns, nl, a) and a64_local_ann_span(body_head, src, ns, nl, a).n == 0 {
        if a64_inferred_local_elem_span(src, body_head, ns, nl, a, decls).n != 0 { r = true }
      }
    }
    Expr::Field(base, fs, fl) => { r = a64_place_root_inferred_local(base, body_head, src, a, decls) }
    Expr::Index(base, idx) => { r = a64_place_root_inferred_local(base, body_head, src, a, decls) }
    _ => {}
  }
  r
}

## The exact bounded aggregate-write base `xs[i].arr`: one FIELD directly on one INDEX of an inferred
## homogeneous local array. Keep this narrower than the recursive root predicate so nested fields,
## globals, parameters, annotated locals, and other deep aggregate forms retain their existing gates.
a64_inferred_local_agg_elem_base := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if ex_is_field(e) {
    fb := expr_field_base(e)
    if ex_is_index(fb) {
      root := ex_index_base(fb)
      if a64_ex_is_var(root) and a64_place_root_inferred_local(root, body_head, src, a, decls) { r = true }
    }
  }
  r
}

## --- DEEP AGGREGATE PLACES (Types §9.4): an ADDRESS composed from a frame-local root + N hops ---
## `xs[i].b.c.cx`, `xs[i].arr[j]`, `b.cells[i].m` — an arbitrary chain of FIELD and INDEX hops rooted at
## a struct, fixed-array LOCAL, or admitted fixed-array PARAM. The one-hop element paths address `element base + field offset` with a
## CLOSED formula; anything deeper (a second field hop, or an index into an inline `[T; N]` FIELD) has no
## such formula, so every such access was fail-loud. These resolvers COMPOSE it instead:
##   a64_place_ty        — the TYPE span AT each hop, so the next hop's field offset / element stride is known
##   a64_place_ok        — every hop resolvable and the root a real frame slot (else keep the `brk`)
##   emit_a64_place_addr — the address itself into x0: a FIELD hop is `add x0, x0, #woff*8`; an INDEX hop
##                         pushes the base, evaluates the index (which clobbers every scratch register),
##                         scales it by the element words and adds the popped base back
## The LEAF load/store is a SINGLE word, gated on the leaf type being SCALAR — an aggregate leaf stays
## fail-loud. Mirrors lower.al's resolve_idx_field_place / arr_field_elem composition. FRAME-LOCAL roots
## and this slice's explicit fixed-array PARAM roots are admitted (an inferred homogeneous struct-array
## global is also admitted); binds, other globals, generic arrays, and byte/packed roots remain rejected
## rather than guessing an addressing mode.
a64_ex_is_var := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::Var(_s, _n) => { r = true } _ => {} }
  r
}

## The TYPE span of the place `e` — a struct name, a `[E; N]` array-type span, or a scalar type name.
## A root Var takes its LOCAL's struct type, its DECLARED fixed-array type, or this slice's explicit
## fixed-array PARAM type; a Field hop takes the
## field's type within its (plain struct) base; an Index hop takes its base array type's element.
a64_place_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  ## ONE `mut` accumulator + a bare `return r`, never `return <nested-call>` for a struct result: that
  ## shape is the lean lower's documented mis-lower (the returned CSpan came back partly stale, so only
  ## SOME deep places resolved). Same reason the flags below are separate `mut` bools, not `and`-chains.
  mut r := CSpan(s = 0, n = 0)
  if unchecked bitcast(usize, e) == 0 { return r }
  if ex_is_field(e) {
    bt := a64_place_ty(expr_field_base(e), body_head, src, a, decls)
    mut fok := false
    if bt.n != 0 {
      if struct_decl_of(decls, src, bt.s, bt.n) >= 0 {
        if struct_plain(decls, src, bt.s, bt.n) { fok = true }
      }
    }
    if fok { r = field_type_span(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) }
    return r
  }
  if ex_is_index(e) {
    ibase := ex_index_base(e)
    ## An inferred ARRAY GLOBAL has no source `[E; N]` annotation to hand to a64_arrty_elem. Its
    ## homogeneous StructLit initializer is the equivalent type oracle for the deep global-root path.
    if a64_ex_is_var(ibase) and a64_is_array_global(decls, src, ex_var_ns(ibase), ex_var_nl(ibase)) {
      if a64_alit_homog_slit(a64_global_value(decls, src, ex_var_ns(ibase), ex_var_nl(ibase)), src) {
        r = a64_garr_elem_struct_span(decls, src, ex_var_ns(ibase), ex_var_nl(ibase))
      }
    }
    if r.n == 0 and a64_ex_is_var(ibase) {
      r = a64_inferred_local_elem_span(src, body_head, ex_var_ns(ibase), ex_var_nl(ibase), a, decls)
    }
    ## A fixed-array PARAM has no `[E; N]` type span in Param: `pm.ts/pm.tl` already name E and
    ## `pm.pps` carries N. Resolve `xs[i]` directly to E before the generic array-type fallback.
    if r.n == 0 and a64_ex_is_var(ibase) {
      pidx := param_find(a64_params(), src, ex_var_ns(ibase), ex_var_nl(ibase), a)
      if pidx >= 0 {
        plenp := a64_param_fixed_array_len(a64_params(), src, ex_var_ns(ibase), ex_var_nl(ibase))
        etp := a64_param_arr_elem_span(a64_params(), src, ex_var_ns(ibase), ex_var_nl(ibase))
        if plenp > 0 and etp.n != 0 { r = etp }
      }
    }
    if r.n == 0 {
      bt := a64_place_ty(ibase, body_head, src, a, decls)
      if bt.n != 0 { r = a64_arrty_elem(src, bt.s, bt.n) }
    }
    return r
  }
  vns := ex_var_ns(e)
  vnl := ex_var_nl(e)
  if vnl == 0 { return r }
  lsn := a64_local_struct_nl(body_head, src, vns, vnl, a)
  if lsn != 0 { r = CSpan(s = a64_local_struct_ns(body_head, src, vns, vnl, a), n = lsn) }
  if lsn == 0 { r = a64_local_arrty_span(body_head, src, vns, vnl, a) }
  ## For a fixed-array PARAM this returns the element span as a resolver marker. The index-hop helpers
  ## use the same PARAM metadata to validate `[E; N]` and obtain `N`; no synthetic array type span exists.
  if r.n == 0 { r = a64_param_arr_elem_span(a64_params(), src, vns, vnl) }
  r
}

## Can `base[…]` be addressed as an aggregate/array element? (`base` resolvable, its type a `[E; N]`
## form or an explicit fixed-array PARAM, and E's word width known.) The INDEX-hop half of a64_place_ok, split out so the statement
## forms — which carry the base and the index as SEPARATE fields, with no `Expr::Index` node to pass —
## can ask the same question.
a64_place_idx_ok := fn(base : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if not a64_place_ok(base, body_head, src, params_head, pcount, a, decls) { return r }
  if a64_ex_is_var(base) and a64_is_array_global(decls, src, ex_var_ns(base), ex_var_nl(base)) {
    if a64_alit_homog_slit(a64_global_value(decls, src, ex_var_ns(base), ex_var_nl(base)), src) {
      etg := a64_garr_elem_struct_span(decls, src, ex_var_ns(base), ex_var_nl(base))
      if etg.n != 0 and a64_tyname_words(src, etg.s, etg.n, a, decls) > 0 { r = true }
    }
  }
  if not r and a64_ex_is_var(base) {
    etl := a64_inferred_local_elem_span(src, body_head, ex_var_ns(base), ex_var_nl(base), a, decls)
    if etl.n != 0 and a64_tyname_words(src, etl.s, etl.n, a, decls) > 0 { r = true }
  }
  if not r {
    bt := a64_place_ty(base, body_head, src, a, decls)
    if bt.n == 0 { return r }
    if arrty_semi(src, bt.s, bt.n) == 0 { return r }
    et := a64_arrty_elem(src, bt.s, bt.n)
    if et.n == 0 { return r }
    if a64_tyname_words(src, et.s, et.n, a, decls) > 0 { r = true }
  }
  r
}

## The ELEMENT type span of `base[…]`, else {0,0} — the statement-form twin of a64_place_ty's Index hop.
a64_place_idx_ty := fn(base : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if a64_ex_is_var(base) {
    pidx := param_find(a64_params(), src, ex_var_ns(base), ex_var_nl(base), a)
    if pidx >= 0 {
      r = a64_param_arr_elem_span(a64_params(), src, ex_var_ns(base), ex_var_nl(base))
      return r
    }
    r = a64_inferred_local_elem_span(src, body_head, ex_var_ns(base), ex_var_nl(base), a, decls)
    if r.n != 0 { return r }
  }
  bt := a64_place_ty(base, body_head, src, a, decls)
  if bt.n != 0 { r = a64_arrty_elem(src, bt.s, bt.n) }
  r
}

## Is EVERY hop of the place `e` resolvable, with a frame-LOCAL root or this explicit fixed-array PARAM
## root? Match-bindings and globals remain rejected. The parameter admission is deliberately limited to a
## plain struct element with a known word layout; generic/heterogeneous/packed roots stay fail-loud.
a64_place_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if unchecked bitcast(usize, e) == 0 { return r }
  if ex_is_field(e) {
    fbase := expr_field_base(e)
    mut fbaseok := a64_place_ok(fbase, body_head, src, params_head, pcount, a, decls)
    ## Admit the parameter-root slice only when this field is the intermediate array in the bounded
    ## `xs[i].arr[j]` shape. A direct `a[i].x` field must retain its existing fail-loud behavior.
    if (not fbaseok) and ex_is_index(fbase) {
      pbase := ex_index_base(fbase)
      if a64_ex_is_var(pbase) {
        pidx := param_find(params_head, src, ex_var_ns(pbase), ex_var_nl(pbase), a)
        if pidx >= 0 {
          etp := a64_param_arr_elem_span(params_head, src, ex_var_ns(pbase), ex_var_nl(pbase))
          plenp := a64_param_fixed_array_len(params_head, src, ex_var_ns(pbase), ex_var_nl(pbase))
          if plenp > 0 and etp.n != 0 and struct_decl_of(decls, src, etp.s, etp.n) >= 0 and struct_plain(decls, src, etp.s, etp.n) {
            if std_struct_is_word_granular(decls, src, etp.s, etp.n, a) and a64_tyname_words(src, etp.s, etp.n, a, decls) > 0 {
              ft := field_type_span(decls, src, etp.s, etp.n, expr_field_name_s(e), expr_field_name_l(e), a)
              if ft.n != 0 and arrty_semi(src, ft.s, ft.n) != 0 { fbaseok = true }
            }
          }
        }
      }
    }
    if not fbaseok { return r }
    bt := a64_place_ty(fbase, body_head, src, a, decls)
    if bt.n == 0 { return r }
    if struct_decl_of(decls, src, bt.s, bt.n) < 0 { return r }
    if not struct_plain(decls, src, bt.s, bt.n) { return r }
    mut foffok := field_word_offset(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) >= 0
    if a64_std_idx_path_ok(e, body_head, src, a, decls) { foffok = layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) >= 0 }
    if foffok { r = true }
    return r
  }
  if ex_is_index(e) {
    if a64_place_idx_ok(ex_index_base(e), body_head, src, params_head, pcount, a, decls) { r = true }
    return r
  }
  vns := ex_var_ns(e)
  vnl := ex_var_nl(e)
  if vnl == 0 { return r }
  pidx := param_find(params_head, src, vns, vnl, a)
  if pidx >= 0 {
    et := a64_param_arr_elem_span(params_head, src, vns, vnl)
    plen := a64_param_fixed_array_len(params_head, src, vns, vnl)
    if plen > 0 and et.n != 0 and struct_decl_of(decls, src, et.s, et.n) >= 0 and struct_plain(decls, src, et.s, et.n) {
      if std_struct_is_word_granular(decls, src, et.s, et.n, a) and a64_tyname_words(src, et.s, et.n, a, decls) > 0 { r = true }
    }
    return r
  }
  if a64_is_array_global(decls, src, vns, vnl) { r = true ; return r }
  if A64_BODY != 0 {
    elt := a64_inferred_local_elem_span(src, body_head, vns, vnl, a, decls)
    if elt.n != 0 and a64_local_off(body_head, src, vns, vnl, pcount, a, decls) >= 0 { r = true ; return r }
  }
  pt := a64_place_ty(e, body_head, src, a, decls)
  if pt.n == 0 { return r }
  if a64_local_off(body_head, src, vns, vnl, pcount, a, decls) >= 0 { r = true }
  r
}

## Emit the ADDRESS of `base[idx]` into x0 (assumes a64_place_idx_ok). The base address is PUSHED before
## the index expression runs — that emit clobbers every scratch register — then the scaled index is added
## to the popped base. Bounds vs the array type's STATIC element count, dropped under `unchecked` (CG-7);
## `b.lo` also traps a negative i64 index (a huge unsigned).
emit_a64_place_idx_addr := fn(base : ptr(Expr), idx : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  mut et := CSpan(s = 0, n = 0)
  mut estride := i64(0)
  mut nel := i64(0)
  if a64_ex_is_var(base) {
    pidx := param_find(params_head, src, ex_var_ns(base), ex_var_nl(base), a)
    if pidx >= 0 {
      et = a64_param_arr_elem_span(params_head, src, ex_var_ns(base), ex_var_nl(base))
      if et.n != 0 { estride = a64_arr_elem_stride_bytes(src, et.s, et.n, a, decls) }
      nel = a64_param_fixed_array_len(params_head, src, ex_var_ns(base), ex_var_nl(base))
    }
  }
  if a64_ex_is_var(base) and a64_is_array_global(decls, src, ex_var_ns(base), ex_var_nl(base)) {
    gv := a64_global_value(decls, src, ex_var_ns(base), ex_var_nl(base))
    if a64_alit_homog_slit(gv, src) {
      et = a64_garr_elem_struct_span(decls, src, ex_var_ns(base), ex_var_nl(base))
      if et.n != 0 { estride = a64_arr_elem_stride_bytes(src, et.s, et.n, a, decls) }
      nel = a64_alit_nel(gv)
    }
  }
  if et.n == 0 and a64_ex_is_var(base) {
    elt := a64_inferred_local_elem_span(src, body_head, ex_var_ns(base), ex_var_nl(base), a, decls)
    if elt.n != 0 {
      et = elt
      estride = a64_arr_elem_stride_bytes(src, et.s, et.n, a, decls)
      nel = a64_array_nel(body_head, src, ex_var_ns(base), ex_var_nl(base), a)
    }
  }
  if et.n == 0 {
    bt := a64_place_ty(base, body_head, src, a, decls)
    et = a64_arrty_elem(src, bt.s, bt.n)
    estride = a64_arr_elem_stride_bytes(src, et.s, et.n, a, decls)
    nel = arrty_nel(src, bt.s, bt.n)
  }
  emit_a64_place_addr(base, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "  str x0, [sp, #-16]!\n")
  emit_a64_expr(idx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  if A64_CHK {
    if nel > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, nel) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
  }
  push_str(sb, "  mov x1, #") ; push_int(sb, estride) ; push_str(sb, "\n  mul x0, x0, x1\n  ldr x1, [sp], #16\n  add x0, x0, x1\n")
}

## Emit the ADDRESS of the place `e` into x0 (assumes a64_place_ok). Flat standalone ifs — an if/else-if
## chain as a fn body reads as a tail value-if under the lean lower.
emit_a64_place_addr := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  isf := ex_is_field(e)
  isi := ex_is_index(e)
  if isf {
    fbase := expr_field_base(e)
    bt := a64_place_ty(fbase, body_head, src, a, decls)
    mut boff := i64(field_word_offset(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a)) * 8
    if a64_std_idx_path_ok(e, body_head, src, a, decls) { boff = layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_name_s(e), expr_field_name_l(e), a) }
    emit_a64_place_addr(fbase, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    if boff > 0 { push_str(sb, "  add x0, x0, #") ; push_int(sb, boff) ; push_str(sb, "\n") }
  }
  if isi {
    emit_a64_place_idx_addr(ex_index_base(e), ex_index_idx(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  }
  if (not isf) and (not isi) {
    vns := ex_var_ns(e)
    vnl := ex_var_nl(e)
    pidx := param_find(params_head, src, vns, vnl, a)
    if pidx >= 0 {
      push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "]\n")
    }
    if pidx < 0 and a64_is_array_global(decls, src, vns, vnl) {
      gname := str_at((src + vns), vnl)
      push_str(sb, "  adrp x0, ") ; push_str(sb, gname) ; push_str(sb, "\n  add x0, x0, :lo12:") ; push_str(sb, gname) ; push_str(sb, "\n")
    }
    if pidx < 0 and not a64_is_array_global(decls, src, vns, vnl) {
      voff := a64_local_off(body_head, src, vns, vnl, pcount, a, decls)
      push_str(sb, "  add x0, x29, #") ; push_int(sb, voff) ; push_str(sb, "\n")
    }
  }
}

## Is parameter `idx` an OUT/IN-OUT SCALAR. Aggregates and pointers to aggregates already use their
## own by-reference representation, so `pmode == 2` must not add a second level of indirection there.
## This is the AArch64 counterpart of lower.al's callee_out_scalar/ek-8 distinction.
a64_param_is_out_scalar := fn(params_head : ptr(mut Param), src : ptr(u8), idx : i64, decls : ptr(rt::Vec)) -> bool {
  mut p := params_head
  mut i := 0
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    if i == idx {
      if pm.pmode == 2 {
        mut agg := false
        if struct_decl_of(decls, src, pm.ts, pm.tl) >= 0 { agg = true }
        if enum_decl_of(decls, src, pm.ts, pm.tl) >= 0 { agg = true }
        if str_at((src + pm.ts), pm.tl) == "str" { agg = true }
        if str_at((src + pm.ts), pm.tl) == "ptr" {
          if enum_decl_of(decls, src, pm.pps, pm.ppl) >= 0 { agg = true }
          if struct_decl_of(decls, src, pm.pps, pm.ppl) >= 0 { agg = true }
        }
        if not agg { r = true }
      }
    }
    i += 1
    p = pm.next
  }
  r
}

## Emit an OUT/IN-OUT scalar argument as a PLACE address in x0. A local or ordinary scalar parameter
## contributes its frame address; an OUT/IN-OUT parameter forwards the pointer already stored in its slot.
## Globals use their data label. The caller has already established that the callee parameter is scalar,
## so a non-Var form is retained as the existing value path rather than widening this backend slice.
a64_emit_out_scalar_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  mut done := false
  match deref(e) {
    Expr::Var(ns, nl) => {
      pidx := param_find(params_head, src, ns, nl, a)
      if pidx >= 0 {
        isout := a64_param_is_out_scalar(params_head, src, pidx, decls)
        if isout { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "]\n") ; done = true }
        if not isout { push_str(sb, "  add x0, x29, #") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "\n") ; done = true }
      }
      if not done {
        off := a64_local_off(body_head, src, ns, nl, pcount, a, decls)
        if off >= 0 { push_str(sb, "  add x0, x29, #") ; push_int(sb, off) ; push_str(sb, "\n") ; done = true }
      }
      if not done {
        isglob := a64_is_global(decls, src, ns, nl, a)
        if isglob {
          gname := str_at((src + ns), nl)
          push_str(sb, "  adrp x0, ") ; push_str(sb, gname) ; push_str(sb, "\n  add x0, x0, :lo12:") ; push_str(sb, gname) ; push_str(sb, "\n")
          done = true
        }
      }
      if not done { emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    }
    _ => { emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
  }
}

## Is the place `e` a fully-composable DEEP place with a SCALAR one-word leaf? The single gate every deep
## read/write site shares: address composable + the leaf a scalar type. An aggregate leaf (a whole
## struct/array through a deep chain) stays fail-loud — it needs multi-word delivery, not a `ldr`/`str`.
a64_deep_scalar_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if not a64_place_ok(e, body_head, src, params_head, pcount, a, decls) { return r }
  ty := a64_place_ty(e, body_head, src, a, decls)
  if ty.n == 0 { return r }
  if ty_is_scalar(ty.s, ty.n, decls, src) { r = true }
  r
}






## Is the typed LOCAL named `[ns,nl)` a signed `iN`? Scans the body for the first Assign binding it,
## then source-scans its annotation (an inferred `:=` local → false, the unsigned default).
a64_local_ann_signed := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  mut r := false
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { if ann_scan_signed(src, ans + anl) { r = true } }
      _ => {}
    }
  }
  r
}

## Is expression `e` a KNOWN-SIGNED operand (param `: iN`, local `: iN`, or an `iN(x)` conversion)?
## The default (inferred locals, `uN` types, literals) is UNSIGNED — so `/`/`%` route to `udiv`/`divu`
## unless proven signed, exactly like the x86_64 `is_signed_expr` rule. Nothing else is signed by default.
## The `:=` RHS expr of a top-level local named `[ns,nl)` (0 if not found) — mirrors a64_local_ann_signed's
## walk, returning the value instead of its annotation-signedness. Lets a signedness query recover a local's
## inferred type from a `shl`/`shr`/`rotl`/`rotr` RHS (which returns the left operand's type — x86 does this
## in `infer_local_scalar_type`; the non-x86 backends read source annotations, so an UN-annotated
## `b := shr(s, 1)` looked unsigned → `b / 2` chose `udiv` → a SILENT non-x86 miscompile).
a64_local_rhs := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> ptr(Expr) {
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  mut r := unchecked bitcast(ptr(Expr), 0)
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { r = v }
      _ => {}
    }
  }
  r
}
## `v` is a bit shift/rotate call whose LEFT operand is signed → the shift result is signed (OP-6: shl/shr/
## rotl/rotr return the left operand's type).
a64_shift_call_signed := fn(v : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(v) {
    Expr::Call(cs, cl, na, ah) => {
      cn := str_at((src + cs), cl)
      if cn == "shl" or cn == "shr" or cn == "rotl" or cn == "rotr" { if a64_operand_signed(arg_expr_at(ah, 0, a), params_head, body_head, src, a) { r = true } }
    }
    _ => {}
  }
  r
}
a64_operand_signed := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(e) {
    Expr::Var(s, n) => {
      if param_ann_signed(params_head, src, s, n, a) { r = true }
      if a64_local_ann_signed(body_head, src, s, n, a) { r = true }
      ## un-annotated `b := shr(<signed>, n)` — recover the signed result type from the shift RHS.
      if r == false { rhs := a64_local_rhs(body_head, src, s, n, a); if unchecked bitcast(usize, rhs) != 0 { if a64_shift_call_signed(rhs, params_head, body_head, src, a) { r = true } } }
    }
    Expr::Call(cs, cl, na, ah) => { cn := str_at((src + cs), cl) ; if cn == "i8" or cn == "i16" or cn == "i32" or cn == "i64" or cn == "isize" { r = true } }
    _ => {}
  }
  r
}

a64_local_ann_unsigned := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  mut r := false
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { if ann_scan_unsigned(src, ans + anl) { r = true } }
      _ => {}
    }
  }
  r
}
## `v` is the `:=` RHS of an UN-annotated local and it is an `unchecked (<inner>)` SCOPE —
## which changes only the VERIFICATION mode of the expression it wraps, never its TYPE, so the inner's
## unsignedness IS the binding's. The SHAPE GATE that keeps the peel narrow: only an `unchecked`-shaped
## init participates; every other inferred init stays untyped exactly as before. (x86_64's dual is the
## `Expr::Unchecked` arm of `lower::infer_local_scalar_type`, filtered by `unsigned_ty_only`; here the
## predicate is already proof-only, so the filter is structural rather than a type-name test.)
a64_unchecked_init_unsigned := fn(v : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(v) {
    Expr::Unchecked(inner) => { r = a64_operand_unsigned(inner, params_head, body_head, src, a) }
    _ => {}
  }
  r
}
a64_operand_unsigned := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(e) {
    Expr::Var(s, n) => {
      if param_ann_unsigned(params_head, src, s, n, a) { r = true }
      if a64_local_ann_unsigned(body_head, src, s, n, a) { r = true }
      ## un-annotated `s := unchecked (<init>)` — recover the unsignedness the wrapper swallowed
      ## (mirrors the SIGNED side's `a64_shift_call_signed` recovery two functions above).
      if r == false { rhs := a64_local_rhs(body_head, src, s, n, a); if unchecked bitcast(usize, rhs) != 0 { if a64_unchecked_init_unsigned(rhs, params_head, body_head, src, a) { r = true } } }
    }
    Expr::Call(cs, cl, na, ah) => { cn := str_at((src + cs), cl) ; if cn == "u8" or cn == "u16" or cn == "u32" or cn == "u64" or cn == "usize" { r = true } }
    ## The two SHAPES that CARRY an operand's unsignedness but have no annotation of their own, so the
    ## source scan above could never prove them unsigned and the comparison fell back to the always-
    ## SIGNED condition (`lt`/`gt`/`le`/`ge`) — a `u64` word above 2^63 then ordered as NEGATIVE and
    ## `0 < 18446744073709551610` answered FALSE (a valid binary, a normal exit, a wrong value):
    ##
    ##   • `unchecked (<inner>)` — a VERIFICATION scope. It changes the overflow-checking
    ##     mode of the expression it wraps, NEVER its type, so the inner's signedness IS its own.
    ##   • an ARITHMETIC `Bin` (`+ - * / %` and the bit ops `& | ^`) whose BOTH operands are provably
    ##     unsigned, or whose other operand is a bare integer literal: the literal inherits the proven
    ##     operand's unsigned type, so the result is unsigned. COMPARISONS are excluded — they yield
    ##     `bool`, not the operand type.
    ##
    ## Both are PROOF-ONLY and ONE-DIRECTIONAL: they can move an operand signed → unsigned, never the
    ## reverse, so the always-signed default still covers every operand the scan misses. A bare literal
    ## has no signedness of its own and takes the proven partner's type; unary negation remains the
    ## parsed arithmetic shape `Unchecked(Bin(17, Num(0), x))` and therefore follows that same type.
    ## The x86_64 dual is `lower::unsigned_thru_unchecked`.
    Expr::Unchecked(inner) => { r = a64_operand_unsigned(inner, params_head, body_head, src, a) }
    Expr::Bin(op, bl, br) => {
      if op == 16 or op == 17 or op == 18 or op == 19 or op == 29 or op == 34 or op == 35 or op == 36 {
        ul := a64_operand_unsigned(bl, params_head, body_head, src, a)
        ur := a64_operand_unsigned(br, params_head, body_head, src, a)
        if ul and ur { r = true }
        if ul and ex_is_num_lit(br) { r = true }
        if ur and ex_is_num_lit(bl) { r = true }
      }
    }
    _ => {}
  }
  r
}
## An ORDERING comparison (`<`/`>`/`<=`/`>=`) is PROVABLY UNSIGNED iff BOTH operands are provably
## unsigned, OR one operand is provably unsigned and the other is a bare integer LITERAL. Requiring
## the NON-LITERAL side to be PROVEN unsigned keeps the conservative character — it only ever moves
## signed → unsigned, never the reverse — so a mixed/unknown pair still keeps the signed default.
a64_cmp_unsigned := fn(l : ptr(Expr), r : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  ul := a64_operand_unsigned(l, params_head, body_head, src, a)
  ur := a64_operand_unsigned(r, params_head, body_head, src, a)
  if ul and ur { return true }
  if ul and ex_is_num_lit(r) { return true }
  if ur and ex_is_num_lit(l) { return true }
  false
}

a64_local_narrow := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> str {
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  mut r := ""
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { r = ann_scan_narrow(src, ans + anl) }
      _ => {}
    }
  }
  r
}
## Narrow type name of operand `e` (param `: uN`, local `: uN`, or an `uN(x)` conversion), or "".
a64_operand_narrow := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> str {
  mut r := ""
  match deref(e) {
    Expr::Var(s, n) => {
      mut p := params_head
      while p != 0 { pm := deref(param_p(p)) ; if streq(src, pm.ns, pm.nl, s, n) { nn := scalar_name_narrow(src, pm.ts, pm.tl) ; if nn != "" { r = nn } } ; p = pm.next }
      if r == "" { r = a64_local_narrow(body_head, src, s, n, a) }
    }
    Expr::Call(cs, cl, na, ah) => { r = scalar_name_narrow(src, cs, cl) }
    _ => {}
  }
  r
}

emit_a64_arith := fn(op : u8, dsigned : bool, narrow : bool, in out sb : rt::StrBuf) {
  ## CHECKED div-by-zero (I11 / CG-7): `sdiv`/`msub`-remainder by 0 on AArch64 returns 0 (NO hardware
  ## trap, unlike x86_64 `idivq` #DE), a silent wrong result. Trap (`brk`) when the divisor x1 is 0.
  ## Dropped under `unchecked` (A64_CHK false). The `1f`/`1:` pair is self-contained (x1 already holds
  ## the fully-evaluated divisor at this point). Mirrors x86_64's routed num.al div guard.
  if A64_CHK {
    if op == 19 or op == 29 {
      push_str(sb, "  cbnz x1, 1f\n  brk #0\n1:\n")
      ## CHECKED `MIN / -1` (I11 / CG-8 division overflow, CG-13 one mechanism): a SIGNED `sdiv` of
      ## INT64_MIN by -1 has no representable quotient — AArch64 silently yields INT64_MIN (no fault),
      ## so the guard is the only thing that stops a wrong value. `cmn x1, #1` sets Z iff x1 == -1;
      ## `negs x2, x0` (= `subs x2, xzr, x0`) sets V iff x0 == INT64_MIN. Same `brk #0` as every other
      ## guard in the family. x2 is dead scratch here (the `%` path overwrites it with the quotient).
      if dsigned { push_str(sb, "  cmn x1, #1\n  b.ne 1f\n  negs x2, x0\n  b.vc 1f\n  brk #0\n1:\n") }
    }
  }
  ## CHECKED overflow on `+` (I11 / CG-8): `adds` sets NZCV; trap (`brk`) on unsigned CARRY (`b.cc`
  ## skips when clear) or, for a signed `iN` operand, signed OVERFLOW (`b.vc`). Dropped under
  ## `unchecked` (A64_CHK false) and skipped for a narrow width (its §4 wrap is the value model).
  ## POINTER offsetting routes through `rt::addr` (unchecked), so address arithmetic never reaches here.
  if op == 16 {
    if A64_CHK and (not narrow) {
      push_str(sb, "  adds x0, x0, x1\n")
      if dsigned { push_str(sb, "  b.vc 1f\n  brk #0\n1:\n") } else { push_str(sb, "  b.cc 1f\n  brk #0\n1:\n") }
    } else {
      push_str(sb, "  add x0, x0, x1\n")
    }
  }
  ## CHECKED underflow/overflow on `-` (I11 / CG-8): `subs` sets NZCV — unsigned BORROW is C CLEAR
  ## (`b.cs` skips when set = no borrow) or signed OVERFLOW is V (`b.vc`). Pointer DIFFERENCE routes
  ## through `rt::off` (unchecked). Dropped under `unchecked`; narrow wraps.
  if op == 17 {
    if A64_CHK and (not narrow) {
      push_str(sb, "  subs x0, x0, x1\n")
      if dsigned { push_str(sb, "  b.vc 1f\n  brk #0\n1:\n") } else { push_str(sb, "  b.cs 1f\n  brk #0\n1:\n") }
    } else {
      push_str(sb, "  sub x0, x0, x1\n")
    }
  }
  ## CHECKED overflow on `*` (I11 / CG-8): the low product is `mul`; overflow is read from the HIGH half
  ## — UNSIGNED via `umulh` (nonzero high → overflow, `cbz` skips when zero); SIGNED via `smulh` compared
  ## to the low product's sign-extension (`asr #63`). Dropped under `unchecked`; narrow wraps.
  if op == 18 {
    if A64_CHK and (not narrow) {
      if dsigned { push_str(sb, "  smulh x2, x0, x1\n  mul x0, x0, x1\n  asr x3, x0, #63\n  cmp x2, x3\n  b.eq 1f\n  brk #0\n1:\n") }
      else { push_str(sb, "  umulh x2, x0, x1\n  mul x0, x0, x1\n  cbz x2, 1f\n  brk #0\n1:\n") }
    } else {
      push_str(sb, "  mul x0, x0, x1\n")
    }
  }
  ## Divide `/` (19) / remainder `%` (29): SIGNED `sdiv` only when an operand is a known `iN` (`dsigned`);
  ## otherwise UNSIGNED `udiv` — the Alatyr scalar default. AArch64 has no single unsigned-remainder op,
  ## so `%` is `udiv`/`sdiv` + `msub`. Formerly always `sdiv`, which read a high-bit `u64` as negative
  ## (a silent wrong result vs the x86_64 `divq` path).
  if op == 19 {
    if dsigned { push_str(sb, "  sdiv x0, x0, x1\n") } else { push_str(sb, "  udiv x0, x0, x1\n") }
  }
  if op == 29 {
    if dsigned { push_str(sb, "  sdiv x2, x0, x1\n  msub x0, x2, x1, x0\n") } else { push_str(sb, "  udiv x2, x0, x1\n  msub x0, x2, x1, x0\n") }
  }
  if op == 34 { push_str(sb, "  and x0, x0, x1\n") }
  if op == 40 { push_str(sb, "  and x0, x0, x1\n") }
  if op == 35 { push_str(sb, "  orr x0, x0, x1\n") }
  if op == 41 { push_str(sb, "  orr x0, x0, x1\n") }
  if op == 36 { push_str(sb, "  eor x0, x0, x1\n") }
  known := op == 16 or op == 17 or op == 18 or op == 19 or op == 29 or op == 34 or op == 35 or op == 36 or op == 40 or op == 41
  if not known { push_str(sb, "  brk #0\n") }
}

## Emit the width-narrowing of the value in x0 for `name(x)` — mirrors x86_64 `emit_int_narrow_reg`:
## ZERO-extend the low N bits for a `uN`, SIGN-extend for an `iN` (so `u8(810)` → 42, `i8(200)` → -56).
## Native widths (u64/i64/usize/isize) emit nothing (the bits already fill the 64-bit register).
a64_emit_narrow := fn(name : str, in out sb : rt::StrBuf) {
  if name == "u8" { push_str(sb, "  uxtb x0, w0\n") }
  else if name == "u16" { push_str(sb, "  uxth x0, w0\n") }
  else if name == "u32" { push_str(sb, "  mov w0, w0\n") }
  else if name == "i8" { push_str(sb, "  sxtb x0, w0\n") }
  else if name == "i16" { push_str(sb, "  sxth x0, w0\n") }
  else if name == "i32" { push_str(sb, "  sxtw x0, w0\n") }
}
## CHECKED narrow-width OVERFLOW trap (I11 / CG-6/CG-8) — the aarch64 dual of the x86_64
## `emit_int_narrow_reg` guard: the 64-bit result in x0 must fit the narrow type, else `brk #0`.
## UNSIGNED `uN` overflows iff any bit above bit N is set (`lsr` nonzero); SIGNED `iN` overflows iff
## the sign-extension of the low N bits differs from the full value. Emitted BEFORE the value-model
## wrap, gated by the caller on `A64_CHK` (checked) and a non-`0 - x` negation.
a64_emit_narrow_trap := fn(name : str, in out sb : rt::StrBuf) {
  if name == "u8" { push_str(sb, "  lsr x2, x0, #8\n  cbz x2, 1f\n  brk #0\n1:\n") }
  else if name == "u16" { push_str(sb, "  lsr x2, x0, #16\n  cbz x2, 1f\n  brk #0\n1:\n") }
  else if name == "u32" { push_str(sb, "  lsr x2, x0, #32\n  cbz x2, 1f\n  brk #0\n1:\n") }
  else if name == "i8" { push_str(sb, "  sxtb x2, w0\n  cmp x2, x0\n  b.eq 1f\n  brk #0\n1:\n") }
  else if name == "i16" { push_str(sb, "  sxth x2, w0\n  cmp x2, x0\n  b.eq 1f\n  brk #0\n1:\n") }
  else if name == "i32" { push_str(sb, "  sxtw x2, w0\n  cmp x2, x0\n  b.eq 1f\n  brk #0\n1:\n") }
}

## Is a module GLOBAL `[ns,nl)` float-typed? A `: f64`/`: f32` annotation OR an inferred FloatLit init
## (`mut F := 40.0`). Guards `deref(d.value)` on a null value (some decls carry no value expr).
a64_global_is_float := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut r := false
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    if d.kind == 0 and d.name_len != 0 {
      if streq(src, d.name_start, d.name_len, ns, nl) {
        if ann_scan_float(src, d.name_start + d.name_len) { r = true }
        if unchecked bitcast(usize, d.value) != 0 { if expr_is_float_lit(d.value) { r = true } }
      }
    }
    i += 1
  }
  r
}
## Is the idx-th PARAM float-typed? (drives the ABI trap.)
a64_param_is_float := fn(params_head : ptr(mut Param), src : ptr(u8), idx : i64, a : rt::Arena) -> bool {
  mut p := params_head
  mut i := 0
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    ## AAPCS64 out/in-out and aggregate parameters arrive as INTEGER addresses, even when their
    ## source element/type is float. Keep the caller and callee on the GPR path; the value bits are
    ## still handled by the normal scalar float detector after the pointer is dereferenced.
    if i == idx {
      if pm.pmode == 0 { if scalar_name_is_float(src, pm.ts, pm.tl) { r = true } }
    }
    i += 1
    p = pm.next
  }
  r
}

## The STRUCT span a CALL `f(…)` returns by value, or 0/0 — non-zero ONLY when `v` is a call to a DEFINED
## fn whose return type is an ALL-SCALAR struct of 1..8 words (the §8 register struct-return convention,
## piece 2: the callee delivers word k in x_k, x0..x7). Used to (a) SIZE a struct-returning-call-bound
## LOCAL, (b) resolve its `.field` reads, and (c) materialize a struct-returning-call ARGUMENT by
## reference. Restricting to all-scalar ≤8-word keeps the convention self-consistent; a wider/str/float
## return stays a LOUD trap.
a64_call_ret_struct_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  cs := expr_call_name_ns(v)
  cl := expr_call_name_nl(v)
  mut rs := 0
  mut rn := 0
  if cl != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
      if d.is_fn and d.name_len != 0 and streq(src, d.name_start, d.name_len, cs, cl) {
        bn := base_type_name(src, d.ret_ts, d.ret_tl)
        ## GENERICS (§8): a generic callee returning `T` — resolve the call's EXPLICIT type-arg (arg 0)
        ## so `p := id(P, …)` sees the concrete struct `P`. Byte-compare; `ebs/ebn` = effective base span.
        mut ebs := bn.s
        mut ebn := bn.n
        if d.is_generic {
          tpn := a64_tparam_name(d, src)
          mut retmatch := false
          if tpn.n != 0 {
            if d.ret_tl == tpn.n {
              rrb := bytes(str_at((src + d.ret_ts), d.ret_tl))
              grb := bytes(str_at((src + tpn.s), tpn.n))
              mut eqk := true
              mut bj := 0
              while bj < d.ret_tl { if rrb[bj] != grb[bj] { eqk = false } ; bj = bj + 1 }
              retmatch = eqk
            }
          }
          if retmatch {
            ah := ex_call_argh(v)
            if arg_list_count(ah, a) == i64(d.arity) {
              ea := arg_expr_at(ah, 0, a)
              ebs = ex_var_ns(ea)
              ebn = ex_var_nl(ea)
            }
          }
        }
        ## Any PLAIN struct of 1..8 words rides the register struct-return (word k → x_k) — the delivery is
        ## a type-agnostic word copy, so a struct with an ENUM / str field (not all-scalar) works too. The
        ## arity-0 guard in a64_ret_struct_words keeps a comptime-value-param type-fn (`uint(N)`) out.
        if ebn != 0 and a64_ret_struct_words(decls, src, ebs, ebn, a) >= 1 { rs = ebs ; rn = ebn }
        ## Tuple returns use the same register delivery as small structs, but have no Decl-backed
        ## layout.  Preserve the full return span so the binding path can count/store components.
        if a64_fn_returns_tuple(d, src) {
          tw := a64_tuple_words(src, d.ret_ts, d.ret_tl)
          if tw >= 1 and tw <= 7 { rs = d.ret_ts ; rn = d.ret_tl }
        }
      }
      i = i + 1
    }
  }
  CSpan(s = rs, n = rn)
}
## The WIDE-struct span a CALL `v` returns via SRET (§8 piece 2b): the callee is a fn whose return type is
## a PLAIN struct of > 8 words. Mirrors a64_call_ret_struct_span's callee lookup but with the SRET (wide)
## gate; only a direct call to a plain (non-generic) struct-returning fn is recognized (generic SRET is
## out of scope and stays trapping). Used to SIZE + TYPE such a binding local and to route its delivery.
a64_call_ret_sret_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  cs := expr_call_name_ns(v)
  cl := expr_call_name_nl(v)
  mut rs := 0
  mut rn := 0
  if cl != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
      if d.is_fn and d.name_len != 0 and streq(src, d.name_start, d.name_len, cs, cl) {
        bn := base_type_name(src, d.ret_ts, d.ret_tl)
        if bn.n != 0 and a64_ret_sret_words(decls, src, bn.s, bn.n, a) >= 1 { rs = bn.s ; rn = bn.n }
      }
      i = i + 1
    }
  }
  CSpan(s = rs, n = rn)
}
## Does the fn NAMED `[cs,cl]` return a wide struct via SRET? The call-arm predicate (it has the callee
## name, not the call Expr) for injecting the `add x8, x29, #dst` indirect-result setup before the `bl`.
a64_fn_returns_sret := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, a : rt::Arena) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut r := false
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    if d.is_fn and d.name_len != 0 and streq(src, d.name_start, d.name_len, cs, cl) {
      bn := base_type_name(src, d.ret_ts, d.ret_tl)
      if bn.n != 0 and a64_ret_sret_words(decls, src, bn.s, bn.n, a) >= 1 { r = true }
      ## a WIDE-ENUM callee (> 8 words) also delivers through the x8 indirect result, so it needs the same
      ## `add x8, x29, #dst` hand-off before the `bl` (the enum analogue of the wide-struct SRET gate).
      if bn.n != 0 and a64_ret_enum_sret_words(decls, src, bn.s, bn.n, a) >= 1 { r = true }
    }
    i = i + 1
  }
  r
}
## The struct span a BINDING RHS `v` delivers by register: a direct struct-returning CALL, OR a struct-
## valued if-EXPRESSION whose then-branch is such a call (`x := if c {f()} else {g()}`). Used to SIZE +
## TYPE + DELIVER such a local. Only the then-branch is inspected: a well-typed if-expr's branches share
## one value type, so the else-branch delivers the same struct; the If arm emits both branch calls (each
## leaving word k in x_k) and only one runs, so after the join x0..x_(w-1) hold the struct. Non-if / non-
## struct-call bindings resolve exactly as the direct-call span (byte-identical), so this is additive.
a64_binding_ret_struct_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  mut r := a64_call_ret_struct_span(v, decls, src, a)
  if r.n == 0 and a64_is_if(v) { r = a64_call_ret_struct_span(a64_if_then(v), decls, src, a) }
  ## a struct-valued match-EXPRESSION `x := match e { A => S(…) … }`: its value type is the struct its
  ## FIRST arm delivers — a struct LITERAL (its declared type) or a struct-returning call. All arms share
  ## one value type, so the first fixes the binding's width/type; delivery visits every arm.
  if r.n == 0 and a64_is_match(v) {
    ah := a64_match_armh(v)
    if unchecked bitcast(usize, ah) != 0 {
      am := deref(arm_p(ah))
      if expr_is_struct_lit(am.body) { r = CSpan(s = expr_struct_lit_ns(am.body), n = expr_struct_lit_nl(am.body)) }
      if r.n == 0 { r = a64_call_ret_struct_span(am.body, decls, src, a) }
    }
  }
  r
}
## The ENUM span a CALL `f(…)` returns by value, or 0/0 — non-zero ONLY when `v` is a call to a DEFINED
## fn whose return type is an enum of 1..8 words (§8 piece 3 register enum-return convention: the callee
## delivers word 0 = disc, word k+1 = payload in x0..x7). Used to size an enum-returning-call-bound LOCAL,
## resolve its `match`, and materialize an enum-returning-call ARGUMENT by reference. Word-copy delivery
## works for any payload; a downstream struct/str-payload match still fails loud.
a64_call_ret_enum_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  cs := expr_call_name_ns(v)
  cl := expr_call_name_nl(v)
  mut rs := 0
  mut rn := 0
  if cl != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
      if d.is_fn and d.name_len != 0 and streq(src, d.name_start, d.name_len, cs, cl) {
        bn := base_type_name(src, d.ret_ts, d.ret_tl)
        ## GENERICS (§8): a generic callee returning its type-param `T` — resolve the call's EXPLICIT
        ## type-arg (arg 0) as the concrete return type, so `o := id(Opt, …)` sees `Opt`. Byte-compare
        ## (not str ==, unreliable in emit paths). `ebs/ebn` = the effective base-name span.
        mut ebs := bn.s
        mut ebn := bn.n
        if d.is_generic {
          tpn := a64_tparam_name(d, src)
          mut retmatch := false
          if tpn.n != 0 {
            if d.ret_tl == tpn.n {
              rrb := bytes(str_at((src + d.ret_ts), d.ret_tl))
              grb := bytes(str_at((src + tpn.s), tpn.n))
              mut eqk := true
              mut bj := 0
              while bj < d.ret_tl { if rrb[bj] != grb[bj] { eqk = false } ; bj = bj + 1 }
              retmatch = eqk
            }
          }
          if retmatch {
            ah := ex_call_argh(v)
            if arg_list_count(ah, a) == i64(d.arity) {
              ea := arg_expr_at(ah, 0, a)
              ebs = ex_var_ns(ea)
              ebn = ex_var_nl(ea)
            }
          }
        }
        if ebn != 0 and enum_decl_of(decls, src, ebs, ebn) >= 0 {
          w := 1 + i64(enum_max_arity(decls, src, ebs, ebn, a))
          if w >= 1 and w <= 8 { rs = ebs ; rn = ebn }
        }
      }
      i = i + 1
    }
  }
  CSpan(s = rs, n = rn)
}
## The WIDE-ENUM span a CALL `f(…)` returns by value, or 0/0 — the > 8-word (SRET) analogue of
## a64_call_ret_enum_span: non-zero ONLY when `v` is a direct call to a DEFINED (non-generic) fn whose
## return type is an enum WIDER than the 8-register budget (§8 piece 3, wide enum). Such a call delivers
## through the x8 indirect result (the callee writes the whole {disc, payload…} block into the caller-
## supplied destination); used to SIZE + TYPE the bound local and to route its x8 hand-off. A generic
## wide-enum return is out of scope here (stays trapping), mirroring a64_call_ret_sret_span's plain gate.
a64_call_ret_enum_sret_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  cs := expr_call_name_ns(v)
  cl := expr_call_name_nl(v)
  mut rs := 0
  mut rn := 0
  if cl != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
      if d.is_fn and d.name_len != 0 and streq(src, d.name_start, d.name_len, cs, cl) {
        bn := base_type_name(src, d.ret_ts, d.ret_tl)
        if bn.n != 0 and a64_ret_enum_sret_words(decls, src, bn.s, bn.n, a) >= 1 { rs = bn.s ; rn = bn.n }
      }
      i = i + 1
    }
  }
  CSpan(s = rs, n = rn)
}
## The params_head of the DEFINED callee `[cs,cl)` (a fn decl), or 0 — for the float-ABI call-arg
## register routing (route arg i to d<float-idx> or x<int-idx> per the callee's param class).
a64_callee_params := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) -> usize {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut r := 0
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    if d.is_fn and d.name_len != 0 { if streq(src, d.name_start, d.name_len, cs, cl) { r = d.params_head } }
    i += 1
  }
  r
}

## Is source argument `pidx` of the named callee an OUT/IN-OUT scalar? The caller must pass a PLACE
## address in an integer register, including the forwarding case where the caller's own parameter slot
## already contains that address.
a64_callee_out_scalar := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, pidx : i64) -> bool {
  cp := a64_callee_params(decls, src, cs, cl)
  mut r := false
  if cp != 0 {
    ph := unchecked bitcast(ptr(mut Param), cp)
    r = a64_param_is_out_scalar(ph, src, pidx, decls)
  }
  r
}
## Count of FLOAT params at positions `[0, idx)` of `params_head` — arg `idx`'s within-class float
## register index (its int index is `idx − this`). Both caller + callee use this identical counter.
a64_float_params_before := fn(params_head : ptr(mut Param), src : ptr(u8), idx : i64, a : rt::Arena) -> i64 {
  mut p := params_head
  mut i := 0
  mut c := 0
  while p != 0 {
    pm := deref(param_p(p))
    if i < idx { if scalar_name_is_float(src, pm.ts, pm.tl) { c += 1 } }
    i += 1
    p = pm.next
  }
  c
}
## Is expr `e` a FLOAT value? DEPTH-BOUNDED (cap 24) so a mutually/self-referential local chain can
## never loop (→ false, conservative-sound). IEEE bits ride the integer path; only arith/conv/ABI touch FP.
## Does the LOCAL `[ns,nl)` name a float ARRAY (`xs := [<FloatLit>, …]`)? Mirrors the WORKING
## `a64_is_array_local` (`done` set only on the array-lit match, so a non-array same-name assign does
## not stop the scan early), then checks the first element is a float via the shared detector.
a64_array_is_float := fn(body_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec)) -> bool {
  mut s := body_head
  mut r := false
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and ex_is_array_lit(v) {
          eh := ex_array_lit_ehead(v)
          if eh != 0 { fe := arg_p(eh) ; if a64_is_float_expr(deref(fe).e, body_head, src, a, params_head, decls, 0) { r = true } }
          done = true
        }
        ## a slice-VIEW binding (`fv := base[lo..hi]`) inherits its backing array's element float-ness —
        ## recurse on the slice base (mirrors a64_iter_stride) so `fv[i]` reads via the xmm/float path.
        if streq(src, ans, anl, ns, nl) and ex_is_slice(v) {
          sb2 := ex_slice_base(v)
          if a64_array_is_float(body_head, src, ex_var_ns(sb2), ex_var_nl(sb2), a, params_head, decls) { r = true }
          done = true
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { s = nx }
      Stmt::CompIf(cc, th, el, nx) => { s = nx }
      Stmt::Loop(lb, lnx) => { s = lnx }
      Stmt::Unchecked(ub, unx) => { s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      _ => { s = 0 }
    }
  }
  r
}
a64_is_float_local := fn(body_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec), dep : i64) -> bool {
  if dep > 24 { return false }
  mut r := false
  d := lower_layout::local_decl_assign(body_head, src, ns, nl)
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { if ann_scan_float(src, ans + anl) { r = true } ; if a64_is_float_expr(v, body_head, src, a, params_head, decls, dep + 1) { r = true } }
      _ => {}
    }
  }
  r
}
a64_int_const_expr := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Num(_v, _s, _n) => { r = true }
    Expr::Bin(op, l, rr) => {
      if (op == 16 or op == 17 or op == 18) and a64_int_const_expr(l) and a64_int_const_expr(rr) { r = true }
    }
    _ => {}
  }
  r
}
a64_direct_float_num := fn(e : ptr(Expr), src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut r := false
  if ann_scan_float(src, ns + nl) { if a64_int_const_expr(e) { r = true } }
  r
}
a64_is_float_expr := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec), dep : i64) -> bool {
  if dep > 24 { return false }
  mut r := false
  match deref(e) {
    Expr::FloatLit(fs, fl) => { r = true }
    Expr::Var(ns, nl) => {
      if a64_is_float_local(body_head, src, ns, nl, a, params_head, decls, dep + 1) { r = true }
      if named_param_is_float(params_head, src, ns, nl, a) { r = true }
      if a64_global_is_float(decls, src, ns, nl) { r = true }
    }
    Expr::Bin(op, l, rr) => {
      if op == 16 or op == 17 or op == 18 or op == 19 {
        if a64_is_float_expr(l, body_head, src, a, params_head, decls, dep + 1) { r = true }
        if a64_is_float_expr(rr, body_head, src, a, params_head, decls, dep + 1) { r = true }
      }
    }
    Expr::Call(cs, cl, n, ah) => {
      nm := str_at((src + cs), cl)
      if nm == "f64" { r = true }
      if nm == "f32" { r = true }
      if callee_ret_is_float(decls, src, cs, cl) { r = true }
    }
    ## a struct FIELD of declared type f64/f32 (base a struct local or by-ref struct param).
    Expr::Field(base, fs, fl) => {
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      if bnl != 0 {
        lstl := a64_local_struct_nl(body_head, src, bns, bnl, a)
        if lstl != 0 { if field_type_is_float(decls, src, a64_local_struct_ns(body_head, src, bns, bnl, a), lstl, fs, fl, a) { r = true } }
        pstl := a64_param_struct_nl(params_head, src, bns, bnl, a, decls)
        if pstl != 0 { if field_type_is_float(decls, src, a64_param_struct_ns(params_head, src, bns, bnl, a, decls), pstl, fs, fl, a) { r = true } }
      }
    }
    ## an ARRAY element `xs[i]` whose array local has float elements.
    Expr::Index(base, idx) => {
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      if bnl != 0 { if a64_array_is_float(body_head, src, bns, bnl, a, params_head, decls) { r = true } }
    }
    _ => {}
  }
  r
}


a64_cond := fn(op : u8) -> str {
  if op == 20 { return "eq" }
  if op == 28 { return "ne" }
  if op == 24 { return "lt" }
  if op == 25 { return "gt" }
  if op == 26 { return "le" }
  if op == 27 { return "ge" }
  return "eq"
}
## UNSIGNED ordering condition codes — the DUAL of the signed `a64_cond`, used when BOTH operands are
## provably unsigned (`a64_cmp_unsigned`): `<`=lo, `>`=hi, `<=`=ls, `>=`=hs. So a `u64`/`usize`
## comparison whose operands straddle 2^63 (`0 < u64::MAX`) reads TRUE instead of treating the high-bit
## operand as negative. Equality (`eq`/`ne`) is sign-agnostic and unchanged.
a64_ucond := fn(op : u8) -> str {
  if op == 20 { return "eq" }
  if op == 28 { return "ne" }
  if op == 24 { return "lo" }
  if op == 25 { return "hi" }
  if op == 26 { return "ls" }
  if op == 27 { return "hs" }
  return "eq"
}
## FLOAT comparison condition codes (after `fcmp`): `<`=mi, `<=`=ls, `>`=gt, `>=`=ge — ordered result +
## correct NaN semantics (unordered C=1,V=1 reads false for all ordered / `eq`, true for `ne`).
a64_fcond := fn(op : u8) -> str {
  if op == 20 { return "eq" }
  if op == 28 { return "ne" }
  if op == 24 { return "mi" }
  if op == 25 { return "gt" }
  if op == 26 { return "ls" }
  if op == 27 { return "ge" }
  return "eq"
}
## Is `e` a FLOAT comparison? A FRESH match binds its own operands (the outer Bin arm's destructured
## l/r mis-lower when passed to the detector — pass the whole ptr).
a64_is_float_cmp := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Bin(op, l, rr) => {
      if ex_is_cmp_op(op) {
        if a64_is_float_expr(l, body_head, src, a, params_head, decls, 0) { r = true }
        if a64_is_float_expr(rr, body_head, src, a, params_head, decls, 0) { r = true }
      }
    }
    _ => {}
  }
  r
}

## Is `e` a bare PLACE whose x0 word is an aggregate BASE ADDRESS (a struct/array/slice PARAM, whose
## frame slot holds the caller's block address) or only word 0 of a wider value (an ENUM local/param,
## whose word 0 is the DISCRIMINANT)? Either way the word is NOT the value, so a `cmp x0, x1` over it
## answers on addresses / discriminants alone — the one forbidden outcome, a SILENT MISCOMPILE
## (`E.A(5) == E.A(9)` read EQUAL; two field-equal struct params read UNEQUAL). A bare struct/array
## LOCAL already fail-louds in the Var arm, which is why only these shapes survived. Var-only by
## construction: an INDEX/FIELD operand already holds a loaded scalar and must keep comparing.
a64_is_agg_place := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  ns := ex_var_ns(e)
  nl := ex_var_nl(e)
  if nl == 0 { return false }
  if a64_local_struct_nl(body_head, src, ns, nl, a) != 0 { return true }
  if a64_param_struct_nl(params_head, src, ns, nl, a, decls) != 0 { return true }
  if a64_local_enum_nl(body_head, src, ns, nl, a) != 0 { return true }
  if a64_param_enum_nl(params_head, src, ns, nl, decls) != 0 { return true }
  if a64_is_array_local(body_head, src, ns, nl, a) { return true }
  if is_slice_local(body_head, src, ns, nl, a) { return true }
  false
}
## The INDEX twin: `xs[i]` over an AGGREGATE-ELEMENT array yields the ELEMENT's base address (elements
## are by-reference), so `ps[0] == ps[1]` compared addresses — two field-EQUAL elements read UNEQUAL.
## A SCALAR-element array (`xs[0] == ys[0]`) yields a loaded value and stays on the ordinary compare.
a64_is_agg_index := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_index(e) { return false }
  es := a64_index_elem_struct_span(e, src, a, decls)
  es.n != 0
}
## Is `e` a bare AGGREGATE comparison (Stdlib §2.6)? A FRESH match binds its own operands (the outer
## Bin arm's destructured l/r mis-lower when passed to a detector — pass the whole ptr), exactly like
## `a64_is_float_cmp`. aarch64 has no structural `base::derive::eq`/`lt` (x86_64 routes bare aggregate
## compares there), and the injected-generic mono path is gated off on this backend — so there is
## nothing correct to route to and the construct must stay LOUD (`brk #0`).
a64_is_agg_cmp := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Bin(op, l, rr) => {
      if ex_is_cmp_op(op) {
        if a64_is_agg_place(l, params_head, body_head, src, a, decls) { r = true }
        if a64_is_agg_place(rr, params_head, body_head, src, a, decls) { r = true }
        if a64_is_agg_index(l, src, a, decls) { r = true }
        if a64_is_agg_index(rr, src, a, decls) { r = true }
      }
    }
    _ => {}
  }
  r
}

## Emit code computing expression `e` into x0. `bind_head`/`bind_base` carry the ACTIVE match-arm
## payload bindings (0/0 outside a match arm): a Var naming a bound payload loads the scrutinee's word
## `bind_base + (bindidx+1)*8`.
a64_emit_lambda_label := fn(in out sb : rt::StrBuf, src : ptr(u8), ms : usize, ml : usize, fnpos : usize) {
  if not lower::is_root_mod(ms, ml) {
    if ml == 0 { push_str(sb, "main") } else { push_str(sb, str_at((src + ms), ml)) }
    push_str(sb, "__")
  }
  push_str(sb, "lam")
  push_int(sb, i64(fnpos))
}

a64_bound_lambda := fn(body : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> i64 {
  mut fnpos : usize = 0
  mut found := false
  mut rhs := unchecked bitcast(ptr(Expr), 0)
  bind := lower_layout::local_decl_assign(body, src, ns, nl)
  if unchecked bitcast(usize, bind) != 0 {
    st := deref(stmt_p(Stmt, bind))
    match st {
      Stmt::Assign(as, al, v, nx) => {
        rhs = v
      }
      _ => {}
    }
  }
  if unchecked bitcast(usize, rhs) != 0 {
    fr := lower::fnref_info(rhs)
    if fr.is_r { fnpos = fr.fnpos; found = true }
  }
  if not found { return 0 - 1 }
  mut i := 0
  while i < rt::vec_len(deref(decls)) {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and d.name_len == 0 and d.name_start == fnpos { return i64(i) }
    i = i + 1
  }
  return 0 - 1
}

emit_a64_expr := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  match deref(e) {
    Expr::FnRef(fnpos, fms, fml) => {
      push_str(sb, "  adrp x0, ") ; a64_emit_lambda_label(sb, src, fms, fml, fnpos)
      push_str(sb, "\n  add x0, x0, :lo12:") ; a64_emit_lambda_label(sb, src, fms, fml, fnpos) ; push_str(sb, "\n")
    }
    Expr::Num(v, s, n) => { push_str(sb, "  ldr x0, =") ; push_int(sb, i64(v)) ; push_str(sb, "\n") }
    ## FLOAT literal: load its IEEE bits from the `.Lflt<start>` `.double` into d0, move to x0.
    Expr::FloatLit(fs, fl) => {
      push_str(sb, "  adrp x9, .Lflt") ; push_int(sb, i64(fs))
      push_str(sb, "\n  ldr d0, [x9, :lo12:.Lflt") ; push_int(sb, i64(fs))
      push_str(sb, "]\n  fmov x0, d0\n")
    }
    Expr::BoolLit(v) => { push_str(sb, "  ldr x0, =") ; push_int(sb, i64(v)) ; push_str(sb, "\n") }
    Expr::Var(ns, nl) => {
      ## BIND > PARAM > GLOBAL > LOCAL, flat standalone ifs. A payload binding aliases scrutinee word
      ## bindidx+1. A bare struct-local Var has no scalar value → fail-loud; only `p.f` reads a struct.
      bidx := bind_list_index(bind_head, src, ns, nl, a)
      isstruct := a64_local_struct_nl(body_head, src, ns, nl, a) != 0
      isarray := a64_is_array_local(body_head, src, ns, nl, a)
      isagg := isstruct or isarray
      pidx := param_find(params_head, src, ns, nl, a)
      isout := pidx >= 0 and a64_param_is_out_scalar(params_head, src, pidx, decls)
      isglob := a64_is_global(decls, src, ns, nl, a)
      mut voff := a64_local_off(body_head, src, ns, nl, pcount, a, decls)
      if pidx >= 0 { voff = 16 + pidx * 8 }
      useframe := (bidx < 0) and (not isagg) and (not isout) and ((pidx >= 0) or (voff >= 0 and (not isglob)))
      gname := str_at((src + ns), nl)
      if bidx >= 0 { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, bind_base + (bidx + 1) * 8) ; push_str(sb, "]\n") }
      if isout { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, voff) ; push_str(sb, "]\n  ldr x0, [x0]\n") }
      if useframe { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, voff) ; push_str(sb, "]\n") }
      if (bidx < 0) and (not isagg) and (not isout) and (not useframe) and isglob {
        push_str(sb, "  adrp x0, ") ; push_str(sb, gname) ; push_str(sb, "\n  add x0, x0, :lo12:") ; push_str(sb, gname) ; push_str(sb, "\n  ldr x0, [x0]\n")
      }
      if (bidx < 0) and (not isagg) and (not isout) and (not useframe) and (not isglob) { push_str(sb, "  brk #0 // unresolved var\n") }
      if (bidx < 0) and isagg { push_str(sb, "  brk #0 // bare struct/array value (copy/arg deferred)\n") }
    }
    Expr::Field(base, fs, fl) => {
      ## `f.offset` — a comptime FIELD descriptor read. Fold it before ordinary field lowering sees
      ## the erased loop variable as a runtime name; unresolved forms keep the existing trap path.
      cfo := a64_cf_offset_value(e, src, decls, a)
      if cfo >= 0 {
        push_str(sb, "  ldr x0, =") ; push_int(sb, cfo) ; push_str(sb, "\n")
        return
      }
      ## `f.mutable` — a comptime FIELD descriptor read. It has no runtime storage; emit the exact
      ## source-level mutability bit before ordinary field machinery sees `f` as a runtime variable.
      ## Non-matching shapes return -1 and continue into the existing fail-loud field paths.
      cfm := a64_cf_mutable_value(e, src)
      if cfm >= 0 {
        push_str(sb, "  ldr x0, =") ; push_int(sb, cfm) ; push_str(sb, "\n")
        return
      }
      ## `p.f`: a struct LOCAL reads at (frame base + field word offset); a struct PARAM (passed
      ## by-reference: its slot holds the base ADDRESS) loads the addr then dereferences at the field.
      ## Flat standalone ifs.
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      stys := a64_local_struct_ns(body_head, src, bns, bnl, a)
      styn := a64_local_struct_nl(body_head, src, bns, bnl, a)
      poff := a64_local_off(body_head, src, bns, bnl, pcount, a, decls)
      ## STANDARD BYTE-LAYOUT — resolve a scalar leaf through a local root using cumulative byte
      ## offsets. An aggregate leaf is deliberately still a value-position trap; aggregate copies use
      ## the assignment path, which has a real destination block to copy into.
      mut stdty := a64_std_path_ty(e, body_head, src, a, decls)
      mut stdpath := a64_std_path_ok(e, body_head, src, a, decls)
      mut stdparampath := false
      if not stdpath {
        if a64_std_param_path_ok(e, params_head, src, a, decls) {
          stdty = a64_std_param_path_ty(e, params_head, src, a, decls)
          stdpath = true
          stdparampath = true
        }
      }
      mut stdhandled := false
      if stdpath {
        mut sbo := i64(0)
        if stdparampath { sbo = a64_std_param_path_bo(e, params_head, src, a, decls) }
        if not stdparampath { sbo = a64_std_path_bo(e, body_head, src, a, decls) }
        if not std_ty_aggregate(stdty.s, stdty.n, decls, src) {
          if stdparampath {
            spidx := a64_std_param_path_idx(e, params_head, src, a, decls)
            push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, 16 + spidx * 8) ; push_str(sb, "]\n")
            if sbo != 0 { push_str(sb, "  add x0, x0, #") ; push_int(sb, sbo) ; push_str(sb, "\n") }
            a64_std_load_width_x0(scalar_byte_size(src, stdty.s, stdty.n), stdty.n != 0 and str_at((src + stdty.s), 1) == "i", sb)
          }
          if not stdparampath {
            sroot := a64_std_path_root_off(e, body_head, src, pcount, a, decls)
            a64_std_load_scalar(sroot + sbo, stdty.s, stdty.n, sb, src)
          }
        }
        if std_ty_aggregate(stdty.s, stdty.n, decls, src) { push_str(sb, "  brk #0 // standard aggregate field needs a value consumer\n") }
        stdhandled = true
      }
      ## gate on THIS FIELD being scalar (not the whole struct) — so a scalar field of a struct that also
      ## has an aggregate field (`s.n` where `S = { c : Col, n : u64 }`) reads at its layout word offset,
      ## which already accounts for the wide enum field. An aggregate field stays unhandled here (field not
      ## scalar → localok false), routed to the aggregate/match paths as before. wsize-based (panic-free).
      localok := (not stdhandled) and bnl != 0 and styn != 0 and poff >= 0 and a64_field_is_scalar(decls, src, stys, styn, fs, fl, a)
      pidx := param_find(params_head, src, bns, bnl, a)
      pstys := a64_param_struct_ns(params_head, src, bns, bnl, a, decls)
      pstyn := a64_param_struct_nl(params_head, src, bns, bnl, a, decls)
      paramok := (not localok) and pidx >= 0 and pstyn != 0 and a64_struct_all_scalar(decls, src, pstys, pstyn, a)
      if localok {
        woff := field_word_offset(decls, src, stys, styn, fs, fl, a)
        push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, poff + woff * 8) ; push_str(sb, "]\n")
      }
      if paramok {
        woff := field_word_offset(decls, src, pstys, pstyn, fs, fl, a)
        push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "]\n  ldr x0, [x2, #") ; push_int(sb, woff * 8) ; push_str(sb, "]\n")
      }
      ## `s[i].field`: FIELD over an INDEX into a struct-element `Slice(P)` PARAM. The param slot holds a
      ## POINTER to the caller's `{ptr,len}` block; element i is by-reference at block.word0 (data ptr) +
      ## i*stride*8; the field is at (element base + woff*8). Bounds vs block.word1 (dropped under unchecked).
      mut fldidxdone := false
      if ex_is_index(base) {
        ibase := ex_index_base(base)
        ins := ex_var_ns(ibase)
        inl := ex_var_nl(ibase)
        ipidx := param_find(params_head, src, ins, inl, a)
        psp := a64_slice_param_struct_span(params_head, src, ins, inl, decls)
        if ipidx >= 0 and psp.n != 0 and a64_struct_all_scalar(decls, src, psp.s, psp.n, a) {
          fldidxdone = true
          stride := a64_slice_param_agg_stride(params_head, src, ins, inl, a, decls)
          woff := field_word_offset(decls, src, psp.s, psp.n, fs, fl, a)
          pslot := 16 + ipidx * 8
          emit_a64_expr(ex_index_idx(base), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if A64_CHK { push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslot) ; push_str(sb, "]\n  ldr x1, [x3, #8]\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
          push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslot) ; push_str(sb, "]\n  ldr x2, [x3]\n")
          push_str(sb, "  mov x1, #") ; push_int(sb, stride * 8) ; push_str(sb, "\n  mul x0, x0, x1\n  add x2, x2, x0\n")
          push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, woff * 8) ; push_str(sb, "]\n")
        }
        ## `xs[i].f` on a fixed ARRAY of scalar-only STRUCTS — a LOCAL array-lit (frame base `x29 + aoff`)
        ## or an array GLOBAL (label base). Element i is `stride` words wide at base + i*stride*8, the
        ## scalar field at (element base + woff*8). Bounds vs the STATIC element count via `b.lo` (a
        ## negative i64 index is a huge unsigned → traps); dropped under `unchecked` (CG-7).
        if not fldidxdone {
          esp := a64_arrname_elem_struct_span(src, ins, inl, a, decls)
          eisla := esp.n != 0 and a64_is_array_local(body_head, src, ins, inl, a)
          eisga := esp.n != 0 and (not eisla) and a64_is_array_global(decls, src, ins, inl)
          eaoff := a64_local_off(body_head, src, ins, inl, pcount, a, decls)
          ## THIS FIELD must be SCALAR (one word): an element struct may now carry a nested aggregate
          ## field, and a one-word `ldr` at its offset would silently read only its word 0. A non-scalar
          ## field falls through to the deep-place composition below / the fail-loud default.
          efscal := esp.n != 0 and a64_field_is_scalar(decls, src, esp.s, esp.n, fs, fl, a)
          if efscal and ((eisla and eaoff >= 0) or eisga) {
            fldidxdone = true
            mut estrb := i64(struct_words(decls, src, esp.s, esp.n, a)) * 8
            mut ewofb := i64(field_word_offset(decls, src, esp.s, esp.n, fs, fl, a)) * 8
            mut ebyte := false
            if std_array_elem_byte_tier(decls, src, esp.s, esp.n, a) {
              estrb = i64(layout_elem_stride_bytes(decls, src, esp.s, esp.n, a))
              ewofb = layout_field_offset_bytes(decls, src, esp.s, esp.n, fs, fl, a)
              ebyte = true
            }
            mut enel := 0
            if eisla { enel = a64_array_nel(body_head, src, ins, inl, a) }
            if eisga { enel = a64_alit_nel(a64_global_value(decls, src, ins, inl)) }
            emit_a64_expr(ex_index_idx(base), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if A64_CHK {
              if enel > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, enel) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
            }
            push_str(sb, "  mov x1, #") ; push_int(sb, estrb) ; push_str(sb, "\n  mul x0, x0, x1\n")
            if eisla { push_str(sb, "  add x2, x0, x29\n  add x2, x2, #") ; push_int(sb, eaoff) ; push_str(sb, "\n")
              if ebyte {
                ftb := field_type_span(decls, src, esp.s, esp.n, fs, fl, a)
                fw := scalar_byte_size(src, ftb.s, ftb.n)
                fsigned := ftb.n != 0 and str_at((src + ftb.s), 1) == "i"
                if fw == 1 and fsigned { push_str(sb, "  ldrsb x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 1 and (not fsigned) { push_str(sb, "  ldrb w0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 2 and fsigned { push_str(sb, "  ldrsh x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 2 and (not fsigned) { push_str(sb, "  ldrh w0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 4 and fsigned { push_str(sb, "  ldrsw x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 4 and (not fsigned) { push_str(sb, "  ldr w0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 8 { push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
              }
              if not ebyte { push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
            }
            if eisga {
              gen := str_at((src + ins), inl)
              push_str(sb, "  adrp x2, ") ; push_str(sb, gen) ; push_str(sb, "\n  add x2, x2, :lo12:") ; push_str(sb, gen) ; push_str(sb, "\n  add x2, x2, x0\n")
              if ebyte {
                ftb := field_type_span(decls, src, esp.s, esp.n, fs, fl, a)
                fw := scalar_byte_size(src, ftb.s, ftb.n)
                fsigned := ftb.n != 0 and str_at((src + ftb.s), 1) == "i"
                if fw == 1 and fsigned { push_str(sb, "  ldrsb x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 1 and (not fsigned) { push_str(sb, "  ldrb w0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 2 and fsigned { push_str(sb, "  ldrsh x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 2 and (not fsigned) { push_str(sb, "  ldrh w0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 4 and fsigned { push_str(sb, "  ldrsw x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 4 and (not fsigned) { push_str(sb, "  ldr w0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
                if fw == 8 { push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
              }
              if not ebyte { push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, ewofb) ; push_str(sb, "]\n") }
            }
          }
        }
      }
      ## `s.len` on a range-slice local — the runtime length lives in word1 (frame byte offset poff+8).
      mut isslicelen := false
      if bnl != 0 {
        if is_slice_local(body_head, src, bns, bnl, a) {
          if str_at((src + fs), fl) == "len" { isslicelen = true }
        }
      }
      if isslicelen { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, poff + 8) ; push_str(sb, "]\n") }
      ## `G.f` / `G.a.b.c` — a SCALAR field of a struct GLOBAL at ANY depth: resolve the cumulative `.data`
      ## word offset (nested structs flattened) and load at LABEL + off*8. gchainok is disjoint from the
      ## local/param paths (a global has no frame slot, so localok/paramok are false for it).
      gtype := a64_gchain_type(e, decls, src, a)
      gwoff := a64_gchain_woff(e, decls, src, a)
      groot := a64_gchain_root(e)
      gchainok := gwoff >= 0 and gtype.n != 0 and ty_is_scalar(gtype.s, gtype.n, decls, src)
      if gchainok {
        gcn := str_at((src + groot.s), groot.n)
        push_str(sb, "  adrp x0, ") ; push_str(sb, gcn) ; push_str(sb, "\n  add x0, x0, :lo12:") ; push_str(sb, gcn) ; push_str(sb, "\n  ldr x0, [x0, #") ; push_int(sb, gwoff * 8) ; push_str(sb, "]\n")
      }
      ## `c.v.a` — a SCALAR field of a NESTED struct LOCAL at ANY depth ≥ 2 (the base is itself a Field).
      ## Resolve the cumulative frame WORD offset (nested structs flattened) through the chain rooted at a
      ## struct local and load at (root frame base + off*8). Gated on the base being a Field → disjoint from
      ## the 1-level localok (which fires only when the base is a Var).
      lroot := a64_gchain_root(e)
      ltype := a64_lchain_type(e, body_head, src, a, decls)
      lwoff := a64_lchain_woff(e, body_head, src, a, decls)
      lrootoff := a64_local_off(body_head, src, lroot.s, lroot.n, pcount, a, decls)
      lchainok := (not stdhandled) and ex_is_field(base) and lwoff >= 0 and lrootoff >= 0 and ltype.n != 0 and ty_is_scalar(ltype.s, ltype.n, decls, src)
      if lchainok { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, lrootoff + lwoff * 8) ; push_str(sb, "]\n") }
      ## DEEP place read — `xs[i].b.c.cx` (a field chain off an array ELEMENT), `xs[i].arr[j]` reached
      ## through a further field, `b.cells[i].m` (an inline `[Struct; N]` FIELD of a struct local). None of
      ## these has a closed frame-offset formula (the element base is a RUNTIME address), so the address is
      ## COMPOSED hop by hop and the scalar leaf loaded from it. Last resort: every path above must have
      ## declined, so nothing that already emits changes shape.
      ## `pt.f` / `s.len` where the base is an AGGREGATE payload BINDING (§8 piece 3b) — the binding lives at
      ## frame offset `bind_base + 8` (word 1 of the scrutinee's {disc,payload} block). A STRUCT binding reads
      ## its field at that base + field word offset; a `str` binding reads `.len` at base + 8 (word 1).
      bagg := a64_bind_agg_span(bind_head, src, bns, bnl, a, decls)
      mut bindaggok := false
      if bagg.n != 0 and struct_decl_of(decls, src, bagg.s, bagg.n) >= 0 and a64_struct_all_scalar(decls, src, bagg.s, bagg.n, a) {
        bindaggok = true
        bwoff := field_word_offset(decls, src, bagg.s, bagg.n, fs, fl, a)
        push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, bind_base + 8 + bwoff * 8) ; push_str(sb, "]\n")
      }
      if bagg.n != 0 and (not bindaggok) and str_at((src + bagg.s), bagg.n) == "str" and str_at((src + fs), fl) == "len" {
        bindaggok = true
        push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, bind_base + 8 + 8) ; push_str(sb, "]\n")
      }
      ## DEEP place read — `xs[i].b.c.cx` (a field chain off an array ELEMENT), `xs[i].arr[j]` reached
      ## through a further field, `b.cells[i].m` (an inline `[Struct; N]` FIELD of a struct local). None has
      ## a closed frame-offset formula (the element base is a RUNTIME address), so the address is COMPOSED
      ## hop by hop and the scalar leaf loaded from it. Placed LAST — AFTER every other flag is bound (it
      ## reads them all) — and it signals success through the EXISTING `fldidxdone` ("an index-rooted access
      ## already handled this") so the fail-loud condition below needs no new term. Nested ifs, never one
      ## long `and`-chain binding: that shape stops this fn type-checking under the lean lower.
      if (not stdhandled) and (not localok) and (not paramok) and (not isslicelen) {
        if (not fldidxdone) and (not gchainok) and (not bindaggok) and (not lchainok) {
          if a64_deep_scalar_ok(e, body_head, src, params_head, pcount, a, decls) {
            emit_a64_place_addr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if a64_std_idx_path_ok(e, body_head, src, a, decls) {
              dtyb := a64_std_idx_path_ty(e, body_head, src, a, decls)
              a64_std_load_width_x0(scalar_byte_size(src, dtyb.s, dtyb.n), dtyb.n != 0 and str_at((src + dtyb.s), 1) == "i", sb)
            }
            if not a64_std_idx_path_ok(e, body_head, src, a, decls) { push_str(sb, "  ldr x0, [x0]\n") }
            fldidxdone = true
          }
        }
      }
      if (not stdhandled) and (not localok) and (not paramok) and (not isslicelen) and (not fldidxdone) and (not gchainok) and (not bindaggok) and (not lchainok) { push_str(sb, "  brk #0 // unsupported field access\n") }
    }
    ## `v.(f)` (Expr::CompField) — a member access named by the comptime field-unroll loop var `f`. When
    ## `f` is the active loop var (A64_CF_VAR set), reduce to a scalar field READ of `v` at the CURRENT
    ## field (A64_CF_FLD name span): a struct LOCAL reads at (frame base + field word offset); a struct
    ## PARAM (by-reference — the slot holds the base ADDRESS, T substituted to the instance struct) loads
    ## the addr then dereferences at the field. Flat standalone ifs (an if/else-if chain crashes the a64
    ## backend). A non-scalar field / non-struct base is DEFERRED (fail-loud, never a silent miscompile).
    Expr::CompField(base, idx) => {
      cvn_s := ex_var_ns(idx)
      cvn_l := ex_var_nl(idx)
      cfactive := A64_CF_VAR_L != 0 and cvn_l != 0 and streq(src, cvn_s, cvn_l, A64_CF_VAR_S, A64_CF_VAR_L)
      cfs := A64_CF_FLD_S
      cfl := A64_CF_FLD_L
      cbns := ex_var_ns(base)
      cbnl := ex_var_nl(base)
      cstys := a64_local_struct_ns(body_head, src, cbns, cbnl, a)
      cstyn := a64_local_struct_nl(body_head, src, cbns, cbnl, a)
      cpoff := a64_local_off(body_head, src, cbns, cbnl, pcount, a, decls)
      clocalok := cfactive and cbnl != 0 and cstyn != 0 and cpoff >= 0 and a64_field_is_scalar(decls, src, cstys, cstyn, cfs, cfl, a)
      cpidx := param_find(params_head, src, cbns, cbnl, a)
      cpstys := a64_param_struct_ns(params_head, src, cbns, cbnl, a, decls)
      cpstyn := a64_param_struct_nl(params_head, src, cbns, cbnl, a, decls)
      cparamok := cfactive and (not clocalok) and cpidx >= 0 and cpstyn != 0 and a64_struct_all_scalar(decls, src, cpstys, cpstyn, a)
      if clocalok {
        cwoff := field_word_offset(decls, src, cstys, cstyn, cfs, cfl, a)
        push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, cpoff + cwoff * 8) ; push_str(sb, "]\n")
      }
      if cparamok {
        cwoff := field_word_offset(decls, src, cpstys, cpstyn, cfs, cfl, a)
        push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, 16 + cpidx * 8) ; push_str(sb, "]\n  ldr x0, [x2, #") ; push_int(sb, cwoff * 8) ; push_str(sb, "]\n")
      }
      if (not clocalok) and (not cparamok) { push_str(sb, "  brk #0 // unsupported comptime-field access\n") }
    }
    ## `ptr(<place>)` — the ADDRESS of a SCALAR place into x0 (spec MEM-7/MEM-8, scoped reference). A
    ## scalar frame local / by-value scalar param → `add x0, x29, #voff` (the slot's address); a mutable
    ## scalar module global → its `.data` label. A STRUCT/ARRAY-local place (isagg) is struct-through-
    ## pointer — DEFERRED, fail-loud. Any non-Var inner also fail-loud. Mirrors the Var value path's
    ## PARAM > GLOBAL > LOCAL resolution (flat standalone ifs), taking the address instead of loading.
    Expr::AddrOf(inner) => {
      ## CLAYOUT S3(d) — `ptr(xs[i])` is the observable stride probe and the address form needed by
      ## callers that hand an array element to an unchecked byte comparison. Compose the real element
      ## place before the legacy Var-only scalar path; word-tier places retain their existing resolver.
      mut deepaddr := false
      if ex_is_index(inner) {
        if a64_std_idx_path_ok(inner, body_head, src, a, decls) and a64_place_idx_ok(ex_index_base(inner), body_head, src, params_head, pcount, a, decls) {
          emit_a64_place_idx_addr(ex_index_base(inner), ex_index_idx(inner), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          deepaddr = true
        }
      }
      if ex_is_field(inner) and a64_std_idx_path_ok(inner, body_head, src, a, decls) and a64_place_ok(inner, body_head, src, params_head, pcount, a, decls) {
        emit_a64_place_addr(inner, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        deepaddr = true
      }
      ins := ex_var_ns(inner)
      inl := ex_var_nl(inner)
      isstruct := a64_local_struct_nl(body_head, src, ins, inl, a) != 0
      isarray := a64_is_array_local(body_head, src, ins, inl, a)
      isagg := isstruct or isarray
      pidx := param_find(params_head, src, ins, inl, a)
      isglob := a64_is_global(decls, src, ins, inl, a)
      mut voff := a64_local_off(body_head, src, ins, inl, pcount, a, decls)
      if pidx >= 0 { voff = 16 + pidx * 8 }
      useframe := inl != 0 and (not isagg) and ((pidx >= 0) or (voff >= 0 and (not isglob)))
      useglob := inl != 0 and (not isagg) and (not useframe) and isglob
      gname := str_at((src + ins), inl)
      if useframe { push_str(sb, "  add x0, x29, #") ; push_int(sb, voff) ; push_str(sb, "\n") }
      if useglob { push_str(sb, "  adrp x0, ") ; push_str(sb, gname) ; push_str(sb, "\n  add x0, x0, :lo12:") ; push_str(sb, gname) ; push_str(sb, "\n") }
      if (not deepaddr) and (not useframe) and (not useglob) { push_str(sb, "  brk #0 // unsupported addr-of\n") }
    }
    ## `deref(<scalar ptr>)` — LOAD one word through the pointer. The pointer value (a frame slot holding
    ## an address, or `ptr(x)` inline) → x0, then `ldr x0, [x0]`. SCALAR only: a struct-through-pointer
    ## read is spelled `deref(p).field` = `Field(Deref(p), …)`, which the Field arm handles/fail-louds —
    ## this arm never sees it. A whole-struct `deref(p)` copy is DEFERRED (would need multi-word staging).
    Expr::Deref(inner) => {
      emit_a64_expr(inner, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  ldr x0, [x0]\n")
    }
    Expr::Bin(op, l, r) => {
      ## Stdlib §2.6 BARE AGGREGATE COMPARISON — fail loud BEFORE the operands are materialized. Each
      ## operand word is an aggregate base address (struct/array/slice param) or an enum's word-0
      ## discriminant, so the `cmp x0, x1` below answers on the wrong bits. The `brk #0` traps first;
      ## everything after it is dead. See `a64_is_agg_cmp` for why routing is not an option here.
      if a64_is_agg_cmp(e, body_head, src, a, params_head, decls) { push_str(sb, "  brk #0 // bare aggregate comparison needs structural eq/lt (Stdlib 2.6)\n") }
      emit_a64_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  str x0, [sp, #-16]!\n")
      emit_a64_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  mov x1, x0\n")
      push_str(sb, "  ldr x0, [sp], #16\n")
      iscmp := ex_is_cmp_op(op)
      mut isflt := false
      if a64_is_float_expr(e, body_head, src, a, params_head, decls, 0) { isflt = true }
      if op == 42 {
        ## Boolean `not` — the parser yields `Bin(42, operand, Num(0))` (the right slot is a DUMMY, so
        ## the operand is evaluated exactly once and x1 already holds 0). x0 := (x0 == 0), the aarch64
        ## dual of the x86_64 `cmpq $0 / sete` and wat's `i64.eqz`. Handled BEFORE the cmp/float chain
        ## because 42 is not a `ex_is_cmp_op` kind and `not (0.0 < x)` reads FLOAT through
        ## `a64_is_float_expr`, which would have sent it to the FP-arith arm. Without this the arith
        ## fallthrough's `known` test failed and emitted `brk #0` — the second blocker (after the
        ## `.Lflt` rodata gap) that kept every `math_*` test from running, since `std::math::sqrt`
        ## opens with `if not (0.0 < x) { return 0.0 }`.
        push_str(sb, "  cmp x0, #0\n  cset x0, eq\n")
      } else if iscmp {
        if a64_is_float_cmp(e, body_head, src, a, params_head, decls) {
          ## FLOAT comparison: fcmp on the reinterpreted operands, cset with the float condition code.
          fc := a64_fcond(op)
          push_str(sb, "  fmov d0, x0\n  fmov d1, x1\n  fcmp d0, d1\n  cset x0, ") ; push_str(sb, fc) ; push_str(sb, "\n")
        } else {
          ## SIGNED setcc (`a64_cond`) is the DEFAULT — kept for every signed/unknown operand. When
          ## BOTH operands are PROVABLY unsigned, switch to the UNSIGNED codes (`a64_ucond`) so a
          ## `u64`/`usize` comparison across 2^63 is correct (mirrors the x86_64 `is_unsigned_cmp` gate).
          ucmp := a64_cmp_unsigned(l, r, params_head, body_head, src, a)
          mut cnd := a64_cond(op)
          if ucmp { cnd = a64_ucond(op) }
          push_str(sb, "  cmp x0, x1\n  cset x0, ") ; push_str(sb, cnd) ; push_str(sb, "\n")
        }
      } else if isflt {
        ## FLOAT arithmetic: bits in x0/x1 → d0/d1, FP op, bits back to x0. Detect on the whole Bin `e`
        ## (destructured `l`/`r` mis-lower through the detector). `+`/`-`/`*`/`/` only.
        push_str(sb, "  fmov d0, x0\n  fmov d1, x1\n")
        if op == 16 { push_str(sb, "  fadd d0, d0, d1\n") }
        if op == 17 { push_str(sb, "  fsub d0, d0, d1\n") }
        if op == 18 { push_str(sb, "  fmul d0, d0, d1\n") }
        if op == 19 { push_str(sb, "  fdiv d0, d0, d1\n") }
        push_str(sb, "  fmov x0, d0\n")
      } else {
        dl := a64_operand_signed(l, params_head, body_head, src, a)
        dr := a64_operand_signed(r, params_head, body_head, src, a)
        dsigned := dl or dr
        ## NARROW-WIDTH WRAP (§4 value model): truncate a narrow-typed (uN/iN, N<64) +/-/* result to its
        ## width — the x86_64 built-in dual. Computed BEFORE the arith so the checked overflow guard
        ## (native-width only) can be skipped for a narrow op.
        mut nw := ""
        if op == 16 or op == 17 or op == 18 {
          nw = a64_operand_narrow(l, params_head, body_head, src, a)
          if nw == "" { nw = a64_operand_narrow(r, params_head, body_head, src, a) }
        }
        emit_a64_arith(op, dsigned, (nw != "") or ex_is_zero_lit(l), sb)
        if nw != "" {
          if A64_CHK and (not ex_is_zero_lit(l)) { a64_emit_narrow_trap(nw, sb) }
          a64_emit_narrow(nw, sb)
        }
        ## narrow `~`/`^`: mask the xor result to the operand width (the `x^(-1)` desugar carries 64-bit
        ## ones, so a narrow `~` would otherwise keep the high bits). Same-width `^` = identity mask.
        if op == 36 {
          mut xw := a64_operand_narrow(l, params_head, body_head, src, a)
          if xw == "" { xw = a64_operand_narrow(r, params_head, body_head, src, a) }
          if xw != "" { a64_emit_narrow(xw, sb) }
        }
      }
    }
    Expr::If(c, th, el) => {
      id := a64_next_label()
      emit_a64_expr(c, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  cbz x0, .Lelse") ; push_int(sb, id) ; push_str(sb, "\n")
      emit_a64_expr(th, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  b .Lend") ; push_int(sb, id) ; push_str(sb, "\n")
      push_str(sb, ".Lelse") ; push_int(sb, id) ; push_str(sb, ":\n")
      emit_a64_expr(el, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, ".Lend") ; push_int(sb, id) ; push_str(sb, ":\n")
    }
    Expr::Call(cs, cl, nargs, args_head) => {
      nm := str_at((src + cs), cl)
      ## `print`/`println` whose FIRST arg is a string literal → template emission (a plain literal is
      ## a template with no `{}` holes). Literal runs → write(1,…) syscalls; `{}` holes → the arg via
      ## `__print_u64`; println → a trailing newline write. Anything else falls through (trap).
      mut sarg := unchecked bitcast(ptr(Expr), 0)
      if args_head != 0 { ga0 := deref(arg_p(args_head)) ; sarg = ga0.e }
      ispln := nm == "println"
      isprint := (nm == "print" or ispln) and args_head != 0 and expr_is_str_lit(sarg)
      isconv := scalar_name_is_int_conv(nm)
      mut isfconv := false
      if nm == "f64" { isfconv = true }
      if nm == "f32" { isfconv = true }
      if isprint {
        emit_a64_print_template(sb, a, src, expr_str_lit_ns(sarg), expr_str_lit_nl(sarg), expr_str_lit_label(sarg), ispln, args_head, params_head, pcount, body_head, decls, bind_head, bind_base)
      } else if (isconv or isfconv) and args_head != 0 {
        ## CONVERSION `uN(x)`/`iN(x)`/`fN(x)` — value bits in x0; FP conversions round-trip via a d-register.
        ## int→float `scvtf`; float→int `fcvtzu`/`fcvtzs` (truncating) + narrow; int→int the plain narrow.
        gc0 := deref(arg_p(args_head))
        argisf := a64_is_float_expr(gc0.e, body_head, src, a, params_head, decls, 0)
        emit_a64_expr(gc0.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if isfconv {
          if not argisf { push_str(sb, "  scvtf d0, x0\n  fmov x0, d0\n") }
        } else {
          if argisf {
            push_str(sb, "  fmov d0, x0\n")
            if str_at((src + cs), 1) == "u" { push_str(sb, "  fcvtzu x0, d0\n") } else { push_str(sb, "  fcvtzs x0, d0\n") }
            a64_emit_narrow(nm, sb)
          } else {
            a64_emit_narrow(nm, sb)
          }
        }
      } else if nm == "asm" and args_head != 0 and expr_is_str_lit(sarg) {
        ## `asm("<GAS>", op…)` raw escape (spec ch.80 §4/§11): emit the AArch64-GAS template, with the
        ## positional-`{i}` scheme — each `{i}` → the bare decimal value of operand `i` (a comptime
        ## IMMEDIATE; the template supplies any `#`, so `mov x0, #{0}` with `42` → `mov x0, #42`). A register
        ## operand would need aarch64 register-name exemption in `check` — a follow-up; immediate-only here.
        ss := expr_str_lit_ns(sarg)
        sl := expr_str_lit_nl(sarg)
        push_str(sb, "  ")
        mut j := 0
        while j < sl {
          c := str_at((src + ss + j), 1)
          d0 := if j + 1 < sl { dec_digit_val(str_at((src + ss + j + 1), 1)) } else { -1 }
          if c == "{" and d0 >= 0 {
            mut k := j + 1
            mut idx := 0
            while k < sl and dec_digit_val(str_at((src + ss + k), 1)) >= 0 { idx = idx * 10 + usize(dec_digit_val(str_at((src + ss + k), 1))) ; k = k + 1 }
            oe := a64_arg_at(args_head, idx + 1, a)   ## operand idx = arg idx+1 (arg 0 is the template)
            push_int(sb, ex_value_init(oe))
            if k < sl and str_at((src + ss + k), 1) == "}" { k = k + 1 }
            j = k
          } else {
            push_str(sb, c)
            j += 1
          }
        }
        push_str(sb, "\n")
      } else if nm == "shl" or nm == "shr" or nm == "rotl" or nm == "rotr" {
        ## bit shift/rotate ops (OP-6): eval v → x0 (pushed), count → x1, then the AArch64 op. `shr` picks
        ## `lsr`(logical)/`asr`(arithmetic) by the value's signedness (a64_operand_signed, like `/`). AArch64
        ## has `ror` (rotate right) but no rotate-LEFT insn, so `rotl(v, n)` = `ror(v, 64 - n)`. A SHIFT count
        ## `n ≥ 64` is a checked over-width trap (`brk #0`; I11), dropped under `unchecked` (A64_CHK false);
        ## rotation is total (the CPU masks the count). Native-64 operands (narrow-width masking = follow-up).
        sv := arg_expr_at(args_head, 0, a)
        sn := arg_expr_at(args_head, 1, a)
        emit_a64_expr(sv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  str x0, [sp, #-16]!\n")
        emit_a64_expr(sn, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  mov x1, x0\n  ldr x0, [sp], #16\n")
        ssigned := a64_operand_signed(sv, params_head, body_head, src, a)
        if A64_CHK and (nm == "shl" or nm == "shr") { push_str(sb, "  cmp x1, #64\n  b.lo 1f\n  brk #0\n1:\n") }
        if nm == "shl" { push_str(sb, "  lsl x0, x0, x1\n") }
        if nm == "shr" and ssigned { push_str(sb, "  asr x0, x0, x1\n") }
        if nm == "shr" and (not ssigned) { push_str(sb, "  lsr x0, x0, x1\n") }
        if nm == "rotr" { push_str(sb, "  ror x0, x0, x1\n") }
        if nm == "rotl" { push_str(sb, "  mov x2, #64\n  sub x1, x2, x1\n  ror x0, x0, x1\n") }
      } else if nm == "len" and args_head != 0 and a64_len_recv_slice(sarg, params_head, src, body_head, decls, a) {
        ## `s.len()` (UFCS-desugared to `Call("len", [s])`) on a slice receiver — the runtime length. A
        ## slice PARAM (`sarg` a Var whose param is `Slice(E)`, scalar E) holds a POINTER to the caller's
        ## `{ptr,len}` block, so len = word1 of the block = `[[x29,pslot]+8]` (a DOUBLE deref). A local slice
        ## VIEW holds `{ptr,len}` inline, so len = word1 at its frame slot `[x29, aoff+8]`.
        rns := ex_var_ns(sarg)
        rnl := ex_var_nl(sarg)
        pidxL := param_find(params_head, src, rns, rnl, a)
        isparam := pidxL >= 0 and a64_slice_param_scalar(params_head, src, rns, rnl, a, decls)
        aoffL := a64_local_off(body_head, src, rns, rnl, pcount, a, decls)
        if isparam { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, 16 + pidxL * 8) ; push_str(sb, "]\n  ldr x0, [x0, #8]\n") }
        if not isparam { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, aoffL + 8) ; push_str(sb, "]\n") }
      } else if gen_call_ok(decls, src, cs, cl) {
        ## GENERICS (§8 mono): route a generic call to its monomorphized instance `<fn>__<tag>`. Resolve
        ## the type-arg (explicit `f(u64,…)` / implicit `id(k)`) — the SAME `a64_call_typearg` the collector
        ## used, so the emitted `bl` label matches a defined instance. An EXPLICIT type-arg (argc == arity)
        ## is ERASED from the runtime args (skip arg 0). Scalar value args ride x0.. positionally (float /
        ## aggregate args are a follow-up — the corpus's supported generics are scalar). An unresolved
        ## type-arg falls to a fail-loud `brk` (never a silent miscompile).
        gi := generic_gi(decls, src, cs, cl)
        a64_resolve_typearg(decls, src, gi, args_head, params_head, a)
        tas := A64_TA_S
        tan := A64_TA_N
        gd := deref(decl_get(decls, usize(gi)))
        ## A bounded byte-array return has an x0 carrier but no A64 fixed-array parameter ABI yet. Keep
        ## it out of the generic scalar/by-reference path: passing the carrier as a pointer produced a
        ## silent wrong value in the preflight consumer seam. Direct indexing and return-forwarding are
        ## handled separately; a direct byte-array return used as an argument remains fail-loud.
        mut bytearg := false
        mut barg := args_head
        while barg != 0 {
          bga := deref(arg_p(barg))
          if fixed_array_byte_return_len(bga.e, decls, src, a) >= 1 { bytearg = true }
          barg = bga.next
        }
        ## The enabled injected slice is deliberately scalar-u64 only. An aggregate Slice(T) needs
        ## element-width/aggregate ABI support that this bounded fix does not provide; reject it
        ## loudly instead of allowing a partial instance to silently read or write the wrong word.
        mut gtypeok := tan != 0
        if gd.is_generic and gd.mod_len == 11 and str_at((src + gd.mod_start), gd.mod_len) == "base__slice" and gd.name_len == 4 and str_at((src + gd.name_start), gd.name_len) == "sort" {
          if tan != 3 { gtypeok = false }
          else if str_at((src + tas), tan) != "u64" { gtypeok = false }
        }
        if not gtypeok or bytearg {
          if not gtypeok { push_str(sb, "  brk #0 // generic call: unsupported type-arg\n") }
          if bytearg { push_str(sb, "  brk #0 // bounded byte-array return argument ABI is unsupported\n") }
        } else {
          ## RECORD the instance so the mono loop emits `<fn>__<tag>` (dedup). Recorded at the emit
          ## call site — the proven resolution path — so the label here matches a defined instance.
          a64_inst_add(src, usize(gi), tas, tan)
          argc := arg_list_count(args_head, a)
          ## ERASE the comptime type-arg(s) when passed explicitly (argc == arity): a LEADING RUN of `lead`
          ## type-params erases source indices [0, lead) (`erase_lead`); a single NON-LEADING type-param
          ## erases its one position (`erase_one`, `gf(s, T, k)`). Implicit calls carry none. The loop walks
          ## ALL args by index and keeps arg `gidx` iff `gidx >= erase_lead and gidx != erase_one`.
          mut erase_lead := 0
          mut erase_one := usize(argc) + 1
          if argc == i64(gd.arity) {
            cntc := decl_tparam_count(gd, src)
            leadc := decl_leading_tparam_run(gd, src)
            if cntc == leadc { erase_lead = usize(leadc) }
            if cntc == 1 and leadc == 0 { erase_one = usize(decl_tparam_pos(gd, src)) }
          }
          ## push each kept VALUE arg → its class register. A struct / enum LITERAL arg is materialized into
          ## an A64_AGG block and passed BY REFERENCE (its address in x0) — same as the ordinary-call path —
          ## so a generic instantiated at a struct/enum type still receives a well-formed by-ref param.
          ## Scalar args ride x0 directly. (Float aggregate elements + >8 args are a later slice.) FLAT
          ## separate ifs inside the guard (mirrors the >8-arg loop; an if/else-if chain here miscompiles).
          mut nv := i64(0)
          mut g := args_head
          mut gidx := 0
          while g != 0 {
            ga := deref(arg_p(g))
            keeparg := gidx >= erase_lead and gidx != erase_one
            if keeparg {
              gavns := ex_var_ns(ga.e)
              gavnl := ex_var_nl(ga.e)
              gisarr := gavnl != 0 and a64_is_array_local(body_head, src, gavns, gavnl, a)
              gisstruct := (not gisarr) and gavnl != 0 and a64_local_struct_nl(body_head, src, gavns, gavnl, a) != 0
              ## A local range-slice is an inline `{ptr,len}` frame value. Generic Slice(T) parameters
              ## receive its ADDRESS, just like struct/array/enum aggregate parameters; passing the
              ## loaded data pointer makes the instance read arr[1] as its length (a silent wrong result).
              gisslice := (not gisarr) and (not gisstruct) and gavnl != 0 and is_slice_local(body_head, src, gavns, gavnl, a)
              ## an ENUM LOCAL is by-reference too (the callee's enum param slot holds a POINTER to the
              ## {disc, payload…} block) — without this its word 0, the DISCRIMINANT, was passed AS the
              ## pointer and the instance dereferenced it: a raw SIGSEGV, not a clean `brk`.
              gisenum := (not gisarr) and (not gisstruct) and (not gisslice) and gavnl != 0 and a64_local_enum_nl(body_head, src, gavns, gavnl, a) != 0
              isslit := expr_is_struct_lit(ga.e)
              iselit := (not isslit) and expr_is_enum_lit(ga.e)
              isaggref := (not isslit) and (not iselit) and (gisarr or gisstruct or gisenum or gisslice)
              isplain := (not isslit) and (not iselit) and (not isaggref)
              if isslit { emit_a64_aggval_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if iselit { emit_a64_enumval_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if isaggref { gaoff := a64_local_off(body_head, src, gavns, gavnl, pcount, a, decls) ; push_str(sb, "  add x0, x29, #") ; push_int(sb, gaoff) ; push_str(sb, "\n") }
              if isplain { emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              push_str(sb, "  str x0, [sp, #-16]!\n")
              nv = nv + 1
            }
            gidx = gidx + 1
            g = ga.next
          }
          mut ai := nv - 1
          while ai >= 0 { push_str(sb, "  ldr x") ; push_int(sb, ai) ; push_str(sb, ", [sp], #16\n") ; ai = ai - 1 }
          ## INLINE `bl <fn>__<tag>` (same reason the def label is inline — no span-through-params helper).
          push_str(sb, "  bl ")
          push_str(sb, str_at((src + gd.name_start), gd.name_len))
          push_str(sb, "__")
          ## type TAG (see the def-label site) — TUPLE inline / ARRAY via `a64_emit_arr_tag` / bare,
          ## matching the def so the `bl` label resolves.
          if str_at((src + tas), 1) == "[" {
            ## ARRAY tag `Array_<elem>_<N>` — inline element scan + scalar `parse_arr_len` (matches def).
            push_str(sb, "Array_")
            mut cadep := 0
            mut casemi := tas + 1
            mut cap := tas + 1
            mut cago := true
            while cago and cap < tas + tan {
              cac := str_at((src + cap), 1)
              if cac == "(" or cac == "[" { cadep = cadep + 1 }
              else if (cac == ")" or cac == "]") and cadep > 0 { cadep = cadep - 1 }
              else if cac == ";" and cadep == 0 { casemi = cap ; cago = false }
              cap = cap + 1
            }
            mut caes := tas + 1
            while caes < casemi and str_at((src + caes), 1) == " " { caes = caes + 1 }
            mut caet := casemi
            while caet > caes and str_at((src + caet - 1), 1) == " " { caet = caet - 1 }
            push_str(sb, str_at((src + caes), caet - caes))
            push_str(sb, "_")
            mut calp := casemi + 1
            while calp < tas + tan {
              calc := str_at((src + calp), 1)
              if calc != " " and calc != "]" { push_str(sb, calc) }
              calp = calp + 1
            }
          } else if str_at((src + tas), 1) == "(" {
            ## TUPLE tag — inline top-level-comma split (matches the def-label site; no typearg_at).
            push_str(sb, "Tuple")
            mut cdepth := 0
            mut ccs := tas + 1
            mut cp := tas + 1
            mut cgo := true
            while cgo {
              cc := str_at((src + cp), 1)
              csep := cc == "," and cdepth == 0
              cend := cc == ")" and cdepth == 0
              if cc == "(" or cc == "[" { cdepth = cdepth + 1 }
              else if (cc == ")" or cc == "]") and cdepth > 0 { cdepth = cdepth - 1 }
              if csep or cend {
                mut b1 := ccs
                while b1 < cp and str_at((src + b1), 1) == " " { b1 = b1 + 1 }
                mut b2 := cp
                while b2 > b1 and str_at((src + b2 - 1), 1) == " " { b2 = b2 - 1 }
                push_str(sb, "_")
                push_str(sb, str_at((src + b1), b2 - b1))
                ccs = cp + 1
              }
              if cend { cgo = false }
              cp = cp + 1
            }
          } else {
            push_str(sb, str_at((src + tas), tan))
          }
          ## MULTI type-param: append `__<2nd>` / `__<3rd>` (bare scalar names) — matches the def label.
          if A64_TA_N2 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + A64_TA_S2), A64_TA_N2)) }
          if A64_TA_N3 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + A64_TA_S3), A64_TA_N3)) }
          push_str(sb, "\n")
        }
      } else if a64_bound_lambda(body_head, src, cs, cl, decls) >= 0 {
        td := deref(decl_get(decls, usize(a64_bound_lambda(body_head, src, cs, cl, decls))))
        mut bad := arg_list_count(args_head, a) > 8
        if not ty_is_scalar(td.ret_ts, td.ret_tl, decls, src) { bad = true }
        if scalar_name_is_float(src, td.ret_ts, td.ret_tl) { bad = true }
        mut pp := td.params_head
        while pp != 0 {
          pm := deref(param_p(pp))
          if pm.pmode != 0 or (not ty_is_scalar(pm.ts, pm.tl, decls, src)) or scalar_name_is_float(src, pm.ts, pm.tl) { bad = true }
          pp = pm.next
        }
        mut fg := args_head
        while fg != 0 { fa := deref(arg_p(fg)) ; if a64_is_float_expr(fa.e, body_head, src, a, params_head, decls, 0) { bad = true } ; fg = fa.next }
        if bad {
          push_str(sb, "  brk #0 // local lambda direct call supports <=8 integer scalar args/return\n")
        } else {
          mut g := args_head
          while g != 0 { ga := deref(arg_p(g)) ; emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) ; push_str(sb, "  str x0, [sp, #-16]!\n") ; g = ga.next }
          mut n := arg_list_count(args_head, a)
          while n > 0 { n -= 1 ; push_str(sb, "  ldr x") ; push_int(sb, n) ; push_str(sb, ", [sp], #16\n") }
          push_str(sb, "  bl ") ; a64_emit_lambda_label(sb, src, td.mod_start, td.mod_len, td.name_start) ; push_str(sb, "\n")
        }
      } else if not a64_callee_defined(decls, src, cs, cl, a) {
        push_str(sb, "  brk #0 // undefined/builtin callee\n")
      } else if arg_list_count(args_head, a) > 8 {
        ## >8 args of a class (AAPCS64): first 8 int in x0-x7, first 8 float in d0-d7 (independent
        ## counters); an arg whose class index reaches 8 overflows to the outgoing stack block. Stack
        ## slots are class-agnostic raw 8-byte words (the value model carries a float's bits in a GPR).
        ## Stack args go at [sp + k*8]; register args use the push-to-scratch / pop dance, skipping them.
        n := arg_list_count(args_head, a)
        cparams := a64_callee_params(decls, src, cs, cl)
        ## a struct-LITERAL or struct-RETURNING-CALL arg needs the A64_AGG by-reference materialization,
        ## which the >8-arg overflow path does NOT perform (it would pass a struct-return's first word as a
        ## scalar = silent miscompile). Trap FIRST (loud, never silent); the corpus has no such call.
        mut aggarg := false
        mut gsc := args_head
        while gsc != 0 { gsa := deref(arg_p(gsc)) ; if expr_is_struct_lit(gsa.e) or expr_is_enum_lit(gsa.e) or (a64_call_ret_struct_span(gsa.e, decls, src, a).n != 0) or (a64_call_ret_enum_span(gsa.e, decls, src, a).n != 0) or (a64_call_ret_sret_span(gsa.e, decls, src, a).n != 0) or (a64_call_ret_enum_sret_span(gsa.e, decls, src, a).n != 0) { aggarg = true } ; gsc = gsa.next }
        if aggarg { push_str(sb, "  brk #0 // >8-arg call with aggregate-value/struct-return arg (unsupported)\n") }
        mut nstk := 0
        mut ci := 0
        while ci < n {
          fb0 := a64_float_params_before(cparams, src, ci, a)
          mut cls := ci - fb0
          if a64_param_is_float(cparams, src, ci, a) { cls = fb0 }
          if cls >= 8 { nstk = nstk + 1 }
          ci = ci + 1
        }
        stacksz := ((nstk * 8 + 15) / 16) * 16
        if stacksz > 0 { push_str(sb, "  sub sp, sp, #") ; push_int(sb, stacksz) ; push_str(sb, "\n") }
        mut gs := args_head
        mut gi := 0
        mut k := 0
        while gs != 0 {
          ga := deref(arg_p(gs))
          fbs := a64_float_params_before(cparams, src, gi, a)
          mut clss := gi - fbs
          if a64_param_is_float(cparams, src, gi, a) { clss = fbs }
          if clss >= 8 {
            isoutS := a64_callee_out_scalar(decls, src, cs, cl, gi)
            if isoutS { a64_emit_out_scalar_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if not isoutS {
              ansS := ex_var_ns(ga.e)
              anlS := ex_var_nl(ga.e)
              ## an ENUM LOCAL is by-reference too (see the isagg gate on the ordinary-call path) — passing
              ## its word 0 (the discriminant) AS the pointer is a raw SIGSEGV in the callee.
              isaggS := anlS != 0 and ((a64_local_struct_nl(body_head, src, ansS, anlS, a) != 0) or (a64_local_enum_nl(body_head, src, ansS, anlS, a) != 0) or a64_is_array_local(body_head, src, ansS, anlS, a))
              aoffS := a64_local_off(body_head, src, ansS, anlS, pcount, a, decls)
              if isaggS and aoffS >= 0 { push_str(sb, "  add x0, x29, #") ; push_int(sb, aoffS) ; push_str(sb, "\n") }
              if not (isaggS and aoffS >= 0) { emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            }
            push_str(sb, "  str x0, [sp, #") ; push_int(sb, k * 8) ; push_str(sb, "]\n")
            k = k + 1
          }
          gi = gi + 1
          gs = ga.next
        }
        mut gr := args_head
        mut gj := 0
        while gr != 0 {
          ga := deref(arg_p(gr))
          fbr := a64_float_params_before(cparams, src, gj, a)
          mut clsr := gj - fbr
          if a64_param_is_float(cparams, src, gj, a) { clsr = fbr }
          if clsr < 8 {
            isoutR := a64_callee_out_scalar(decls, src, cs, cl, gj)
            if isoutR { a64_emit_out_scalar_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if not isoutR {
              ansR := ex_var_ns(ga.e)
              anlR := ex_var_nl(ga.e)
              isaggR := anlR != 0 and ((a64_local_struct_nl(body_head, src, ansR, anlR, a) != 0) or (a64_local_enum_nl(body_head, src, ansR, anlR, a) != 0) or a64_is_array_local(body_head, src, ansR, anlR, a))
              aoffR := a64_local_off(body_head, src, ansR, anlR, pcount, a, decls)
              if isaggR and aoffR >= 0 { push_str(sb, "  add x0, x29, #") ; push_int(sb, aoffR) ; push_str(sb, "\n") }
              if not (isaggR and aoffR >= 0) { emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            }
            push_str(sb, "  str x0, [sp, #-16]!\n")
          }
          gj = gj + 1
          gr = ga.next
        }
        mut ii := n - 1
        while ii >= 0 {
          fbp := a64_float_params_before(cparams, src, ii, a)
          mut clsp := ii - fbp
          isfp := a64_param_is_float(cparams, src, ii, a)
          if isfp { clsp = fbp }
          reg := clsp < 8
          if reg and isfp { push_str(sb, "  ldr x9, [sp], #16\n  fmov d") ; push_int(sb, fbp) ; push_str(sb, ", x9\n") }
          if reg and (not isfp) { push_str(sb, "  ldr x") ; push_int(sb, ii - fbp) ; push_str(sb, ", [sp], #16\n") }
          ii = ii - 1
        }
        ## WIDE-STRUCT SRET (§8 piece 2b): a binding `s := mk(…)` whose callee returns a > 8-word struct
        ## passes the destination address in x8 before the `bl` (the >8-arg-count dual of the register path).
        ## A64_SRET_DST_IND = the TAIL-FORWARD flavour: A64_SRET_DST names the frame slot HOLDING the pointer.
        if A64_SRET_DST_ON and a64_fn_returns_sret(decls, src, cs, cl, a) {
          if A64_SRET_DST_IND { push_str(sb, "  ldr x8, [x29, #") ; push_int(sb, A64_SRET_DST) ; push_str(sb, "]\n") }
          if not A64_SRET_DST_IND { push_str(sb, "  add x8, x29, #") ; push_int(sb, A64_SRET_DST) ; push_str(sb, "\n") }
          A64_SRET_DST_ON = false
          A64_SRET_DST_IND = false
        }
        push_str(sb, "  bl ") ; a64_emit_bl_target(sb, decls, src, cs, cl) ; push_str(sb, "\n")
        if stacksz > 0 { push_str(sb, "  add sp, sp, #") ; push_int(sb, stacksz) ; push_str(sb, "\n") }
        if callee_ret_is_float(decls, src, cs, cl) { push_str(sb, "  fmov x0, d0\n") }
      } else {
        mut g := args_head
        mut gidx := 0
        while g != 0 {
          ga := deref(arg_p(g))
          ## a struct/array LOCAL argument is passed BY REFERENCE — its base address (x29 + slot), not
          ## a scalar value (a bare aggregate Var otherwise traps). Read-only in the callee (a field
          ## write through a struct param is trapped there). A SLICE argument `xs[lo..hi]` is materialized
          ## into a reserved `{ptr,len}` agg block and its ADDRESS passed (§8 slice-param caller).
          ans := ex_var_ns(ga.e)
          anl := ex_var_nl(ga.e)
          isslicearg := ex_is_slice(ga.e)
          isbytearg := fixed_array_byte_return_len(ga.e, decls, src, a) >= 1
          ## an anonymous STRUCT-LITERAL VALUE arg (`f(S(…))`) — materialized into an A64_AGG block and
          ## passed BY REFERENCE (§8 anonymous-aggregate materialization, piece 1).
          isaggval := expr_is_struct_lit(ga.e)
          ## an anonymous ENUM-LITERAL VALUE arg (`f(E.V(…))`) — materialized into an A64_AGG block and
          ## passed BY REFERENCE (§8 piece 3).
          isenumval := expr_is_enum_lit(ga.e)
          ## a struct-RETURNING CALL arg (`f(mk(…))`) — its register-returned words are materialized into an
          ## A64_AGG block and passed BY REFERENCE (§8 piece 2).
          iscallretarg := (not isaggval) and (not isenumval) and a64_call_ret_struct_span(ga.e, decls, src, a).n != 0
          ## an enum-RETURNING CALL arg — register-returned {disc,payload} words materialized by-ref (§8 piece 3).
          isenumretarg := (not isaggval) and (not isenumval) and (not iscallretarg) and a64_call_ret_enum_span(ga.e, decls, src, a).n != 0
          ## a WIDE (SRET) struct-returning CALL arg (`f(mk(…))`, > 8 words) — disjoint from iscallretarg (the
          ## ≤8-word register gate). The callee delivers through the x8 indirect result, and in ARGUMENT
          ## position there is no destination local for it, so a block is reserved, handed down as x8, and
          ## then passed by reference. Without this the call fell through to the scalar path = RAW SIGSEGV.
          issretarg := (not isaggval) and (not isenumval) and (not iscallretarg) and (not isenumretarg) and a64_call_ret_sret_span(ga.e, decls, src, a).n != 0
          ## the wide-ENUM (> 8 words, x8 SRET) analogue — same shape, same latent raw fault.
          isesretarg := (not isaggval) and (not isenumval) and (not iscallretarg) and (not isenumretarg) and (not issretarg) and a64_call_ret_enum_sret_span(ga.e, decls, src, a).n != 0
          ## a struct/array/slice-VIEW LOCAL arg is passed BY REFERENCE (its frame base address). A slice
          ## VIEW local is already a `{ptr,len}` block, so its address IS the by-ref `Slice(E)` argument.
          ## …and an ENUM LOCAL too (`v := E.V(…)` / `v := mk()` then `f(v)`): a callee's enum param slot
          ## holds a POINTER to the caller's {disc, payload…} block (a64_param_enum_ns / the `match <enum
          ## param>` materialization), exactly like a struct param. Without this the local fell to the
          ## scalar path and its word 0 — the DISCRIMINANT — was passed AS the pointer, so the callee
          ## dereferenced e.g. 0: a RAW SIGSEGV (both narrow and wide enums), not a clean `brk`.
          isenumlocal := anl != 0 and a64_local_enum_nl(body_head, src, ans, anl, a) != 0
          isagg := (not isslicearg) and (not isaggval) and (not isenumval) and (not iscallretarg) and (not isenumretarg) and (not issretarg) and (not isesretarg) and anl != 0 and ((a64_local_struct_nl(body_head, src, ans, anl, a) != 0) or isenumlocal or a64_is_array_local(body_head, src, ans, anl, a) or is_slice_local(body_head, src, ans, anl, a))
          aoff := a64_local_off(body_head, src, ans, anl, pcount, a, decls)
          if isbytearg { push_str(sb, "  brk #0 // bounded byte-array return argument ABI is unsupported\n") }
          if isslicearg { emit_a64_slice_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if isaggval { emit_a64_aggval_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if isenumval { emit_a64_enumval_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if iscallretarg { emit_a64_callret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if isenumretarg { emit_a64_enumret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if issretarg { emit_a64_sretcall_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if isesretarg { emit_a64_enumsret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          isout := a64_callee_out_scalar(decls, src, cs, cl, gidx)
          if isout { a64_emit_out_scalar_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if isagg and aoff >= 0 { push_str(sb, "  add x0, x29, #") ; push_int(sb, aoff) ; push_str(sb, "\n") }
          if (not isbytearg) and (not isout) and (not isslicearg) and (not isaggval) and (not isenumval) and (not iscallretarg) and (not isenumretarg) and (not issretarg) and (not isesretarg) and (not (isagg and aoff >= 0)) { emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          push_str(sb, "  str x0, [sp, #-16]!\n")
          gidx += 1
          g = ga.next
        }
        ## FLOAT ABI: pop args (reverse — top of stack is the last arg) routing each to its class register
        ## per the CALLEE's param types — a float param i → d<float-idx>, an int param i → x<int-idx>
        ## (independent counters, matching the callee's prologue). A non-float / undeclared-param callee
        ## routes everything to x<i> (byte-identical to the prior positional pop). A float RETURN comes
        ## back in d0 → move to x0 so it rides the integer path in the caller.
        n := arg_list_count(args_head, a)
        cparams := a64_callee_params(decls, src, cs, cl)
        mut i := n - 1
        while i >= 0 {
          if a64_param_is_float(cparams, src, i, a) {
            fb := a64_float_params_before(cparams, src, i, a)
            push_str(sb, "  ldr x9, [sp], #16\n  fmov d") ; push_int(sb, fb) ; push_str(sb, ", x9\n")
          } else {
            fb := a64_float_params_before(cparams, src, i, a)
            push_str(sb, "  ldr x") ; push_int(sb, i - fb) ; push_str(sb, ", [sp], #16\n")
          }
          i = i - 1
        }
        ## WIDE-STRUCT SRET (§8 piece 2b): for a binding `s := mk(…)` whose callee returns a > 8-word struct,
        ## pass the destination local's address in x8 (the AAPCS64 indirect result register) right before the
        ## `bl`; the callee writes the whole struct through it. Consume the one-shot hand-off (clear ON).
        ## A64_SRET_DST_IND = the TAIL-FORWARD flavour (`return mk(…)`): A64_SRET_DST is the frame slot that
        ## HOLDS the destination pointer (our own spilled x8), so LOAD it rather than taking a frame address.
        if A64_SRET_DST_ON and a64_fn_returns_sret(decls, src, cs, cl, a) {
          if A64_SRET_DST_IND { push_str(sb, "  ldr x8, [x29, #") ; push_int(sb, A64_SRET_DST) ; push_str(sb, "]\n") }
          if not A64_SRET_DST_IND { push_str(sb, "  add x8, x29, #") ; push_int(sb, A64_SRET_DST) ; push_str(sb, "\n") }
          A64_SRET_DST_ON = false
          A64_SRET_DST_IND = false
        }
        ## MOD §7.2: a call to an `@extern` callee branches to its EXTERNAL symbol, not the source name.
        push_str(sb, "  bl ") ; a64_emit_bl_target(sb, decls, src, cs, cl) ; push_str(sb, "\n")
        if callee_ret_is_float(decls, src, cs, cl) { push_str(sb, "  fmov x0, d0\n") }
      }
    }
    Expr::Match(scrut, arms) => {
      ## value `match e { E::V(x) => …, _ => … }`: dispatch on the enum LOCAL's discriminant, result in x0.
      sns := ex_var_ns(scrut)
      snl := ex_var_nl(scrut)
      ens := a64_local_enum_ns(body_head, src, sns, snl, a)
      enl := a64_local_enum_nl(body_head, src, sns, snl, a)
      eoff := a64_local_off(body_head, src, sns, snl, pcount, a, decls)
      endid := a64_next_label()
      ok := snl != 0 and enl != 0 and eoff >= 0
      ## a `match <enum PARAM>` (§8 piece 3): the param slot holds a POINTER to the caller's {disc,payload…}
      ## block; materialize its words into the A64_MTMP frame temp, then match on that offset.
      pidxM := param_find(params_head, src, sns, snl, a)
      penlM := a64_param_enum_nl(params_head, src, sns, snl, decls)
      paramok := (not ok) and pidxM >= 0 and penlM != 0
      ## a nested `match <enum payload BINDING>` (§8 piece 3b): the binding is an enum living at frame offset
      ## `bind_base + 8` (word 1 of the enclosing scrutinee's block) — match DIRECTLY at that offset.
      bagg := a64_bind_agg_span(bind_head, src, sns, snl, a, decls)
      bindok := (not ok) and (not paramok) and bagg.n != 0 and enum_decl_of(decls, src, bagg.s, bagg.n) >= 0
      if ok {
        ## value position: no frame (a statement-body arm here is deferred → frame = -1).
        emit_a64_match_arms(arms, ens, enl, eoff, endid, sb, a, src, params_head, pcount, body_head, decls, 0 - 1)
        push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
      }
      if paramok {
        pensM := a64_param_enum_ns(params_head, src, sns, snl, decls)
        wM := 1 + i64(enum_max_arity(decls, src, pensM, penlM, a))
        push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, 16 + pidxM * 8) ; push_str(sb, "]\n")
        mut km := 0
        while km < wM { push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, km * 8) ; push_str(sb, "]\n  str x0, [x29, #") ; push_int(sb, A64_MTMP + km * 8) ; push_str(sb, "]\n") ; km = km + 1 }
        emit_a64_match_arms(arms, pensM, penlM, A64_MTMP, endid, sb, a, src, params_head, pcount, body_head, decls, 0 - 1)
        push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
      }
      if bindok {
        emit_a64_match_arms(arms, bagg.s, bagg.n, bind_base + 8, endid, sb, a, src, params_head, pcount, body_head, decls, 0 - 1)
        push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
      }
      ## a `match s.f` where `s` is a LOCAL struct and `f` is an ENUM FIELD (§8 generic_struct_return): the
      ## enum lives INLINE in the struct's frame slot at (s_off + field_word_offset(f)*8) — match DIRECTLY
      ## at that frame offset with the field's declared enum type. Uses single-match Field accessors (never
      ## matching the enclosing-arm-bound `scrut` inline — the nested-match-on-bound-child miscompile).
      mut fldok := false
      if ex_is_field(scrut) {
        fbase := expr_field_base(scrut)
        fbns := ex_var_ns(fbase)
        fbnl := ex_var_nl(fbase)
        ffs := expr_field_name_s(scrut)
        ffl := expr_field_name_l(scrut)
        fstys := a64_local_struct_ns(body_head, src, fbns, fbnl, a)
        fstyn := a64_local_struct_nl(body_head, src, fbns, fbnl, a)
        fsoff := a64_local_off(body_head, src, fbns, fbnl, pcount, a, decls)
        ## PLAIN (arity-0) struct base only — field_type_span/field_word_offset resolve layout, which a
        ## comptime-value-param type-fn (`uint(N)`) can't do here (would panic). Gate BEFORE those calls.
        fplain := fbnl != 0 and fstyn != 0 and fsoff >= 0 and struct_plain(decls, src, fstys, fstyn)
        mut ffts := CSpan(s = 0, n = 0)
        mut fwoff := i64(0)
        if fplain { ffts = field_type_span(decls, src, fstys, fstyn, ffs, ffl, a) ; fwoff = field_word_offset(decls, src, fstys, fstyn, ffs, ffl, a) }
        fen := fplain and ffts.n != 0 and enum_decl_of(decls, src, ffts.s, ffts.n) >= 0
        if fen {
          fldok = true
          emit_a64_match_arms(arms, ffts.s, ffts.n, fsoff + fwoff * 8, endid, sb, a, src, params_head, pcount, body_head, decls, 0 - 1)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
      }
      if (not ok) and (not paramok) and (not bindok) and (not fldok) { push_str(sb, "  brk #0 // unsupported match\n") }
    }
    Expr::Index(ibase, iidx) => {
      ## `a[i]` for an ARRAY local: element addr = x29 + base_off + i*8 (scaled), load. i is runtime.
      bns := ex_var_ns(ibase)
      bnl := ex_var_nl(ibase)
      mut isslice := false
      if bnl != 0 { if is_slice_local(body_head, src, bns, bnl, a) { isslice = true } }
      isarr := (not isslice) and bnl != 0 and a64_is_array_local(body_head, src, bns, bnl, a)
      pidxI := param_find(params_head, src, bns, bnl, a)
      isparamslice := (not isslice) and (not isarr) and pidxI >= 0 and a64_slice_param_scalar(params_head, src, bns, bnl, a, decls)
      tupn := if (not isslice) and (not isarr) and (not isparamslice) and pidxI >= 0 { param_tuple_allscalar_n(params_head, src, bns, bnl, decls, a) } else { 0 }
      aoff := a64_local_off(body_head, src, bns, bnl, pcount, a, decls)
      ## DEEP index read — `xs[i].arr[j]` (an index into an inline `[T; N]` FIELD of an array element) and
      ## `b.cells[i]`-shaped bases: the base is NOT a bare Var, so no closed frame formula exists. Tried
      ## LAST in the chain, so every array/slice/param shape above keeps its exact emit.
      dielem := a64_place_idx_ty(ibase, body_head, src, a, decls)
      mut deepidx := false
      if dielem.n != 0 {
        if ty_is_scalar(dielem.s, dielem.n, decls, src) {
          if a64_place_idx_ok(ibase, body_head, src, params_head, pcount, a, decls) { deepidx = true }
        }
      }
      mut stdarr := a64_std_path_ty(ibase, body_head, src, a, decls)
      mut stdpathok := a64_std_path_ok(ibase, body_head, src, a, decls)
      mut stdparamidx := false
      if not stdpathok {
        if a64_std_param_path_ok(ibase, params_head, src, a, decls) {
          stdarr = a64_std_param_path_ty(ibase, params_head, src, a, decls)
          stdpathok = true
          stdparamidx = true
        }
      }
      mut stdidx := false
      stdel := a64_arrty_elem(src, stdarr.s, stdarr.n)
      if stdpathok and stdel.n != 0 and scalar_byte_size(src, stdel.s, stdel.n) == 1 { stdidx = true }
      stdidxarr := a64_std_idx_path_ty(ibase, body_head, src, a, decls)
      mut stdidxelem := false
      stdidxel := a64_arrty_elem(src, stdidxarr.s, stdidxarr.n)
      if a64_std_idx_path_ok(ibase, body_head, src, a, decls) and stdidxel.n != 0 and scalar_byte_size(src, stdidxel.s, stdidxel.n) == 1 { stdidxelem = true }
      byte_ret_n := fixed_array_byte_return_len(ibase, decls, src, a)
      if stdidxelem {
        ## `xs[i].data[j]` (and the same shape through deeper byte-writable fields): outer element address
        ## is byte-strided, the cumulative field path is byte-offset, and the inner byte array has stride 1.
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  str x0, [sp, #-16]!\n")
        emit_a64_place_idx_addr(a64_std_idx_root_arr(ibase), a64_std_idx_root_idx(ibase), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        siboE := a64_std_idx_path_bo(ibase, body_head, src, a, decls)
        if siboE != 0 { push_str(sb, "  add x0, x0, #") ; push_int(sb, siboE) ; push_str(sb, "\n") }
        push_str(sb, "  ldr x1, [sp], #16\n")
        if A64_CHK {
          snelE := arrty_nel(src, stdidxarr.s, stdidxarr.n)
          if snelE > 0 { push_str(sb, "  mov x2, #") ; push_int(sb, snelE) ; push_str(sb, "\n  cmp x1, x2\n  b.lo 1f\n  brk #0\n1:\n") }
        }
        push_str(sb, "  add x0, x0, x1\n")
        if stdidxel.n != 0 and str_at((src + stdidxel.s), 1) == "i" { push_str(sb, "  ldrsb x0, [x0]\n") }
        if stdidxel.n == 0 or str_at((src + stdidxel.s), 1) != "i" { push_str(sb, "  ldrb w0, [x0]\n") }
      } else if stdidx {
        ## STANDARD BYTE-LAYOUT `[u8; N]` FIELD index: the containing local is inline, so compose the
        ## root frame offset + field byte offset and use a byte load instead of the historical word stride.
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if A64_CHK {
          snel := arrty_nel(src, stdarr.s, stdarr.n)
          if snel > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, snel) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
        }
        if stdparamidx {
          spidxI := a64_std_param_path_idx(ibase, params_head, src, a, decls)
          push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, 16 + spidxI * 8) ; push_str(sb, "]\n")
        }
        if not stdparamidx {
          push_str(sb, "  add x2, x29, #") ; push_int(sb, a64_std_path_root_off(ibase, body_head, src, pcount, a, decls)) ; push_str(sb, "\n")
        }
        mut sibo := i64(0)
        if stdparamidx { sibo = a64_std_param_path_bo(ibase, params_head, src, a, decls) }
        if not stdparamidx { sibo = a64_std_path_bo(ibase, body_head, src, a, decls) }
        if sibo != 0 { push_str(sb, "  add x2, x2, #") ; push_int(sb, sibo) ; push_str(sb, "\n") }
        push_str(sb, "  ldrb w0, [x2, x0]\n")
      }
      else if byte_ret_n >= 1 {
        ## BYTES bounded direct read: the call returns a little-endian packed carrier in x0. Preserve it
        ## across the index expression, check the static bound in checked mode, then extract byte `k`.
        ## This is read-only; unsupported fixed-array return shapes remain on the located trap path.
        emit_a64_expr(ibase, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  str x0, [sp, #-16]!\n")
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if A64_CHK {
          push_str(sb, "  mov x1, #") ; push_int(sb, byte_ret_n) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n")
        }
        push_str(sb, "  lsl x1, x0, #3\n  ldr x2, [sp], #16\n  lsr x0, x2, x1\n  and x0, x0, #255\n")
      }
      else if tupn > 0 {
        ## `t.N` (= Index(Var(t), Num(N))) on an ALL-SCALAR tuple PARAM: the param slot (`16 + pidxI*8`)
        ## holds a POINTER to the caller's tuple words (passed by-reference). Each component is one word,
        ## so element i is at `[tupleptr + i*8]`. Bounds vs the static component count (dropped under
        ## `unchecked`). Reload the pointer AFTER the index expr (which may clobber scratch).
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        pslotT := 16 + pidxI * 8
        if A64_CHK { push_str(sb, "  mov x1, #") ; push_int(sb, tupn) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
        push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, pslotT) ; push_str(sb, "]\n  ldr x0, [x2, x0, lsl #3]\n")
      }
      else if isparamslice {
        ## `s[i]` on a scalar `Slice(E)` PARAM: the param slot (`16 + pidxI*8`) holds a POINTER to the
        ## caller's `{ptr,len}` block. DOUBLE deref: block word1 (`[blk+8]`) = runtime len for the bounds
        ## check; block word0 (`[blk]`) = data ptr; element i at `[dataptr + i*8]`. Reload the block AFTER
        ## the index expr (which may clobber scratch). Bounds dropped under `unchecked` (CG-7).
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        pslotI := 16 + pidxI * 8
        if A64_CHK {
          push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslotI) ; push_str(sb, "]\n  ldr x1, [x3, #8]\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n")
        }
        push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslotI) ; push_str(sb, "]\n  ldr x2, [x3]\n  ldr x0, [x2, x0, lsl #3]\n")
      }
      else if isslice and aoff >= 0 {
        ## `s[i]` on a range-slice VIEW: bounds vs the RUNTIME len (word1 at aoff+8), then load ELEMENT i
        ## through the data pointer (word0 at aoff): addr = ptr + i*8. `b.lo` skips on idx < len (a
        ## negative i64 index is a huge unsigned → traps). Bounds dropped under `unchecked` (CG-7).
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if A64_CHK {
          push_str(sb, "  ldr x1, [x29, #") ; push_int(sb, aoff + 8) ; push_str(sb, "]\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n")
        }
        push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, aoff) ; push_str(sb, "]\n  ldr x0, [x2, x0, lsl #3]\n")
      }
      else if isarr and aoff >= 0 {
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        ## CHECKED BOUNDS (I11 / CG-7): the index is in x0; trap (`brk`) when it is out of the array's
        ## static element count. `b.lo` (unsigned lower) skips on `idx < N`, so a negative i64 index (huge
        ## unsigned) also traps. `x1` is scratch (the load below uses x2/x0). Dropped under `unchecked`.
        if A64_CHK {
          anel := a64_array_nel(body_head, src, bns, bnl, a)
          if anel > 0 {
            push_str(sb, "  mov x1, #") ; push_int(sb, anel) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n")
          }
        }
        push_str(sb, "  add x2, x29, #") ; push_int(sb, aoff) ; push_str(sb, "\n  ldr x0, [x2, x0, lsl #3]\n")
      }
      else if bnl != 0 and a64_is_array_global(decls, src, bns, bnl) {
        ## `TABLE[i]` on an ARRAY GLOBAL: element i at LABEL + i*8. Bounds vs the static element count
        ## (dropped under `unchecked`). x2 = base label address, x0 = index.
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if A64_CHK {
          gnelR := i64(a64_alit_nel(a64_global_value(decls, src, bns, bnl)))
          if gnelR > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, gnelR) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
        }
        gcn := str_at((src + bns), bnl)
        push_str(sb, "  adrp x2, ") ; push_str(sb, gcn) ; push_str(sb, "\n  add x2, x2, :lo12:") ; push_str(sb, gcn) ; push_str(sb, "\n  ldr x0, [x2, x0, lsl #3]\n")
      }
      else if pidxI >= 0 and a64_param_gen_arr_stride(params_head, src, bns, bnl, a, decls) > 0 {
        ## `a[i]` on a GENERIC array PARAM (`a : T`, T → `[E; N]` scalar element in this instance): the
        ## param slot (`16 + pidxI*8`) holds the array BASE ADDRESS (passed by-reference by the caller),
        ## so element i (1 word) is at `[base + i*8]`. Bounds vs the static N (from the instance array
        ## type) dropped under `unchecked`. Reload the base AFTER the index expr (it may clobber scratch).
        emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        pslotG := 16 + pidxI * 8
        if A64_CHK {
          gnelP := sub_arr_len(src, A64_SUB_ITS, A64_SUB_ITL)
          if gnelP > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, gnelP) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
        }
        push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, pslotG) ; push_str(sb, "]\n  ldr x0, [x2, x0, lsl #3]\n")
      }
      else if deepidx {
        emit_a64_place_idx_addr(ibase, iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  ldr x0, [x0]\n")
      }
      else { push_str(sb, "  brk #0 // unsupported index\n") }
    }
    Expr::Unchecked(inner) => {
      ov := A64_CHK
      A64_CHK = false
      emit_a64_expr(inner, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      A64_CHK = ov
    }
    _ => { push_str(sb, "  brk #0 // unsupported expr\n") }
  }
}

## Emit a SCALAR statement-match arm chain. The caller has already evaluated the integer scrutinee into
## x0; compare it against each literal without clobbering x0, then emit the selected body. A wildcard
## always matches. Unsupported pattern kinds remain a loud brk. This is deliberately separate from the
## enum-discriminant chain below: scalar matches have no payload frame context and no variant lookup.
emit_a64_scalar_match_arms := fn(arm : usize, endid : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), frame : i64) {
  mut ar := arm
  while ar != 0 {
    am := deref(arm_p(ar))
    aid := a64_next_label()
    if am.wild == 0 {
      push_str(sb, "  ldr x1, =") ; push_int(sb, am.lit) ; push_str(sb, "\n  cmp x0, x1\n  b.ne .Lscalararmskip") ; push_int(sb, aid) ; push_str(sb, "\n")
    } else if am.wild != 1 {
      push_str(sb, "  brk #0 // unsupported scalar match pattern on aarch64\n")
    }
    hasexpr := am.body_stmts == 0
    dostmt := (am.body_stmts != 0) and (frame >= 0)
    if hasexpr { emit_a64_expr(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, 0) }
    if dostmt { emit_a64_stmts(am.body_stmts, sb, a, src, params_head, pcount, body_head, decls, frame, am.binds_head, 0) }
    if (not hasexpr) and (not dostmt) { push_str(sb, "  brk #0 // scalar match statement body in value position deferred\n") }
    push_str(sb, "  b .Lmend") ; push_int(sb, endid) ; push_str(sb, "\n")
    if am.wild == 0 { push_str(sb, ".Lscalararmskip") ; push_int(sb, aid) ; push_str(sb, ":\n") }
    ar = am.next
  }
  push_str(sb, "  brk #0 // no matching scalar arm\n")
}

## Emit a match arm chain: compare the scrutinee discriminant (word 0 at frame byte offset `eoff`) to
## each arm's variant index; on a match emit the arm body (payload bindings active — `am.binds_head`,
## base `eoff`) and branch to `.Lmend<endid>`. An EXPRESSION-body arm (`am.body_stmts == 0`) leaves its
## value in x0; a STATEMENT-body arm runs its statements via emit_a64_stmts (side effects; needs a real
## `frame` for a Return — a NEGATIVE `frame` marks value-position where a stmt body is deferred →
## fail-loud). A wildcard always matches. No match → trailing brk. Flat while loop.
emit_a64_match_arms := fn(arm : usize, ens : usize, enl : usize, eoff : i64, endid : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), frame : i64) {
  mut ar := arm
  while ar != 0 {
    am := deref(arm_p(ar))
    ## RANGE pattern arm (`wild == 5`/`6`, Control Flow §5.4) — x86_64-only in v1. Fail LOUD here (a
    ## `brk #0` trap dominates the dead compare that follows), never a silent miscompile: the a64
    ## sweep requires a trap (exit >= 128) or an assemble-reject, not a valid binary with a wrong exit.
    if am.wild == 5 or am.wild == 6 { push_str(sb, "  brk #0 // range-pattern match arm not supported on aarch64 (x86_64 only)\n") }
    ## COMPTIME-VARIANT TEMPLATE arm (`wild == 2`, from `comptime for var in typeinfo(T).variants { T.(var)(p)
    ## => body }`): UNROLL into one concrete variant arm per variant of the scrutinee's enum (mirrors x86
    ## expand_variant_arms). Each generated arm dispatches on that variant's discriminant and reuses the
    ## template's payload binding + body; the loop var name is erased (each arm carries the variant's own
    ## name). Only meaningful in a mono instance where the scrutinee enum `ens/enl` is concrete.
    if am.wild == 2 {
      edi := enum_decl_of(decls, src, ens, enl)
      if edi >= 0 {
        edd := deref(decl_get(decls, usize(edi)))
        mut vf := edd.fields_head
        mut vc := 0
        while vf != 0 {
          vfm := deref(fld_p(vf))
          vvidx := variant_index(decls, src, ens, enl, vfm.ns, vfm.nl, a)
          ## label id unique PER MATCH SITE (`endid`) + per variant (`vc`): a nested/sibling match over the
          ## SAME enum would collide on a variant-keyed id (both iterate the same variant list). Compound
          ## `.LarmskipV<endid>_<vc>` keeps the two dispatch chains disjoint.
          push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, eoff) ; push_str(sb, "]\n")
          push_str(sb, "  ldr x1, =") ; push_int(sb, vvidx) ; push_str(sb, "\n  cmp x0, x1\n  b.ne .LarmskipV") ; push_int(sb, endid) ; push_str(sb, "_") ; push_int(sb, vc) ; push_str(sb, "\n")
          hasexprV := am.body_stmts == 0
          dostmtV := (am.body_stmts != 0) and (frame >= 0)
          oensV := A64_ARM_ENS ; oenlV := A64_ARM_ENL ; ovsV := A64_ARM_VS ; ovlV := A64_ARM_VL
          ocvs := A64_CFVAR_S ; ocvl := A64_CFVAR_L ; obV := A64_ARM_BINDS
          A64_ARM_ENS = ens ; A64_ARM_ENL = enl ; A64_ARM_VS = vfm.ns ; A64_ARM_VL = vfm.nl
          A64_CFVAR_S = vfm.ns ; A64_CFVAR_L = vfm.nl ; A64_ARM_BINDS = unchecked bitcast(usize, am.binds_head)
          if hasexprV { emit_a64_expr(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, eoff) }
          if dostmtV { emit_a64_stmts(am.body_stmts, sb, a, src, params_head, pcount, body_head, decls, frame, am.binds_head, eoff) }
          if (not hasexprV) and (not dostmtV) { push_str(sb, "  brk #0 // statement-body match arm in value position deferred\n") }
          A64_ARM_ENS = oensV ; A64_ARM_ENL = oenlV ; A64_ARM_VS = ovsV ; A64_ARM_VL = ovlV
          A64_CFVAR_S = ocvs ; A64_CFVAR_L = ocvl ; A64_ARM_BINDS = obV
          push_str(sb, "  b .Lmend") ; push_int(sb, endid) ; push_str(sb, "\n")
          push_str(sb, ".LarmskipV") ; push_int(sb, endid) ; push_str(sb, "_") ; push_int(sb, vc) ; push_str(sb, ":\n")
          vc = vc + 1
          vf = vfm.next
        }
      }
    }
    ## FLAT (no nesting): label id from the ARM handle (unique). A non-wild arm compares + skips.
    hasexpr := am.body_stmts == 0
    dostmt := (am.body_stmts != 0) and (frame >= 0)
    aid := a64_next_label()
    ## a `wild == 3` arm is a `T.(v)` comptime-variant PATTERN: its variant name is the enclosing unroll's
    ## CURRENT variant (`A64_CFVAR_*`), not the arm's own `vs/vl` (which still hold the loop-var name `v`).
    mut evs := am.vs
    mut evl := am.vl
    if am.wild == 3 { evs = A64_CFVAR_S ; evl = A64_CFVAR_L }
    vidx := variant_index(decls, src, ens, enl, evs, evl, a)
    if am.wild != 1 and am.wild != 2 {
      push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, eoff) ; push_str(sb, "]\n")
      push_str(sb, "  ldr x1, =") ; push_int(sb, vidx) ; push_str(sb, "\n  cmp x0, x1\n  b.ne .Larmskip") ; push_int(sb, aid) ; push_str(sb, "\n")
    }
    ## record THIS arm's enum context (§8 piece 3b) so an aggregate payload BINDING inside the body
    ## (`pt.x`, nested `match i`) resolves its type + frame offset; save/restore around the body for nesting.
    oens := A64_ARM_ENS
    oenl := A64_ARM_ENL
    ovs := A64_ARM_VS
    ovl := A64_ARM_VL
    obN := A64_ARM_BINDS
    A64_ARM_ENS = ens
    A64_ARM_ENL = enl
    A64_ARM_VS = evs
    A64_ARM_VL = evl
    A64_ARM_BINDS = unchecked bitcast(usize, am.binds_head)
    if am.wild != 2 and hasexpr { emit_a64_expr(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, eoff) }
    if am.wild != 2 and dostmt { emit_a64_stmts(am.body_stmts, sb, a, src, params_head, pcount, body_head, decls, frame, am.binds_head, eoff) }
    if am.wild != 2 and (not hasexpr) and (not dostmt) { push_str(sb, "  brk #0 // statement-body match arm in value position deferred\n") }
    A64_ARM_ENS = oens
    A64_ARM_ENL = oenl
    A64_ARM_VS = ovs
    A64_ARM_VL = ovl
    A64_ARM_BINDS = obN
    if am.wild != 2 { push_str(sb, "  b .Lmend") ; push_int(sb, endid) ; push_str(sb, "\n") }
    if am.wild != 1 and am.wild != 2 { push_str(sb, ".Larmskip") ; push_int(sb, aid) ; push_str(sb, ":\n") }
    ar = am.next
  }
  push_str(sb, "  brk #0 // no matching arm\n")
}

## Materialize a SLICE ARGUMENT `xs[lo..hi]` into a reserved agg block and leave the block's ADDRESS in
## x0 (the by-reference slice-arg convention — the callee's `Slice(T)` param derefs this pointer). The
## block is byte-identical to the slice-VIEW binding: word0 = &base[lo] (= x29 + array-base-off + lo*8),
## word1 = hi - lo. Only a scalar-element frame ARRAY-LOCAL base is supported (the x86 `estride==1` case);
## anything else — or an agg-region overflow (an under-count) — is a LOUD `brk`, never silent corruption.
emit_a64_slice_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  sbase := ex_slice_base(e)
  bns := ex_var_ns(sbase)
  bnl := ex_var_nl(sbase)
  aoff := a64_local_off(body_head, src, bns, bnl, pcount, a, decls)
  sliceok := bnl != 0 and a64_is_array_local(body_head, src, bns, bnl, a) and aoff >= 0 and (A64_AGG + 16) <= A64_AGG_LIM
  if sliceok {
    blk := A64_AGG
    ## word1 = hi - lo → [x29, blk+8]
    emit_a64_expr(ex_slice_hi(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, "  str x0, [sp, #-16]!\n")
    emit_a64_expr(ex_slice_lo(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, "  mov x1, x0\n  ldr x0, [sp], #16\n  sub x0, x0, x1\n  str x0, [x29, #")
    push_int(sb, blk + 8) ; push_str(sb, "]\n")
    ## word0 = &base[lo] = x29 + aoff + lo*estride*8 → [x29, blk] (estride = the base array's element
    ## words — 1 for a scalar array, byte-identical `lsl #3`; struct/enum element scales lo by estride*8).
    estrideSA := a64_iter_stride(body_head, src, sbase, a, decls)
    emit_a64_expr(ex_slice_lo(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    if estrideSA == 1 { push_str(sb, "  lsl x0, x0, #3\n") }
    if estrideSA != 1 { push_str(sb, "  mov x1, #") ; push_int(sb, estrideSA * 8) ; push_str(sb, "\n  mul x0, x0, x1\n") }
    push_str(sb, "  add x0, x0, x29\n  add x0, x0, #")
    push_int(sb, aoff) ; push_str(sb, "\n  str x0, [x29, #")
    push_int(sb, blk) ; push_str(sb, "]\n")
    ## arg value = the block's ADDRESS
    push_str(sb, "  add x0, x29, #") ; push_int(sb, blk) ; push_str(sb, "\n")
    A64_AGG = A64_AGG + 16
  }
  if not sliceok { push_str(sb, "  brk #0 // unsupported slice argument\n") }
}

## Materialize a STRUCT LITERAL `S(f = v, …)` passed as a call ARGUMENT into a reserved A64_AGG block and
## leave the block's ADDRESS in x0 (the by-reference aggregate-argument convention — the analog of x86's
## `emit_arg` struct-ctor case + `emit_struct_assign` into an agg-temp). Each field value → x0 → the block
## word `[x29, blk + k*8]` (positional = declaration = word order, exactly as the `Assign` struct-construct
## path writes a struct LOCAL, so the callee's by-reference field READ reads identical layout). Scalar-field
## structs only (a64_struct_all_scalar) — matching the local-construct guard; str/float-field literals stay
## a LOUD `brk`. Bumps A64_AGG by the struct's words; an overflow past A64_AGG_LIM (an under-reservation)
## is a loud `brk`, never silent frame corruption. Distinct blocks (monotonic bump) → multiple / nested
## aggregate-value args in one call never alias.
emit_a64_aggval_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ns := expr_struct_lit_ns(e)
  nl := expr_struct_lit_nl(e)
  words := i64(struct_words(decls, src, ns, nl, a))
  ok := nl != 0 and (A64_AGG + words * 8) <= A64_AGG_LIM
  if ok {
    blk := A64_AGG
    ## Write each field VALUE at its running byte offset via the shared multi-word payload writer, which
    ## returns the words it occupied — so a field that is itself an ENUM (`S(c = Col.G(9), n = 2)`) or a
    ## nested struct/str lands in full and the following fields stay aligned (fields in declaration order).
    ## An all-scalar struct is byte-identical to the old positional store (each field falls to the scalar
    ## fallback = one word). The block reserves the struct's FULL width; its address rides x0 (by-ref arg).
    mut off := blk
    mut g := ex_struct_lit_args(e)
    while g != 0 {
      ga := deref(arg_p(g))
      w := emit_a64_store_payload_at(ga.e, off, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      off = off + w * 8
      g = ga.next
    }
    push_str(sb, "  add x0, x29, #") ; push_int(sb, blk) ; push_str(sb, "\n")
    A64_AGG = A64_AGG + words * 8
  }
  if not ok { push_str(sb, "  brk #0 // unsupported aggregate-value argument\n") }
}

## Materialize an ENUM LITERAL `E.V(p…)` passed as a call ARGUMENT into a reserved A64_AGG block and leave
## the block's ADDRESS in x0 (the by-reference aggregate-argument convention, §8 piece 3). Word 0 = the
## variant discriminant; payload arg k → block word k+1 (positional, matching the enum-LOCAL construct in
## the Assign path, so the callee's by-reference `match` reads identical layout). The block reserves the
## enum's FULL width (1 + max_arity) so the callee can copy the whole {disc, payload…} block safely; the
## unset trailing payload slots of a narrow variant are never read (the matched arm reads only its own
## payload words). Scalar payload only (a64_elit_payload_scalar); a nested/str payload stays a LOUD `brk`.
## Store ONE enum/struct payload VALUE `pe` into the frame at byte offset `off`, returning the WORDS it
## occupies (§8 piece 3b). A scalar → 1 word; a STRUCT literal (all-scalar) → its fields at off+k*8; a
## nested ENUM literal → its {disc, payload…} recursively (full width 1+max_arity); a `str` literal →
## {ptr, len} (2 words). This is the shared multi-word enum-payload writer used by the enum-LOCAL construct
## and the enum-VALUE call-arg materialization. A non-scalar struct field payload is a LOUD `brk` (its
## reserved width is still returned so following offsets stay consistent).
emit_a64_store_payload_at := fn(pe : ptr(Expr), off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  if expr_is_struct_lit(pe) {
    ## A STRUCT literal: write each field at its RUNNING byte offset via the same multi-word writer, so a
    ## field that is itself a nested STRUCT (or enum/str) lands in full and the following fields stay
    ## aligned (fields in declaration order). An all-scalar struct is byte-identical to the old positional
    ## store (each field falls to the scalar fallback = one word at off + k*8). This recursion is what lets
    ## a NESTED struct literal (`C(b = B(a = A(v=…),…),…)`) materialize at ANY depth.
    sns := expr_struct_lit_ns(pe)
    snl := expr_struct_lit_nl(pe)
    mut g := ex_struct_lit_args(pe)
    mut o2 := off
    while g != 0 {
      ga := deref(arg_p(g))
      w := emit_a64_store_payload_at(ga.e, o2, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      o2 = o2 + w * 8
      g = ga.next
    }
    return i64(struct_words(decls, src, sns, snl, a))
  }
  if expr_is_enum_lit(pe) {
    pens := expr_enum_lit_ns(pe)
    penl := expr_enum_lit_nl(pe)
    pvidx := variant_index(decls, src, pens, penl, expr_enum_variant_ns(pe), expr_enum_variant_nl(pe), a)
    push_str(sb, "  ldr x0, =") ; push_int(sb, pvidx) ; push_str(sb, "\n  str x0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n")
    mut g := ex_enum_lit_args(pe)
    mut wo := 1
    while g != 0 {
      ga := deref(arg_p(g))
      cw := emit_a64_store_payload_at(ga.e, off + wo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      wo = wo + cw
      g = ga.next
    }
    return 1 + i64(enum_max_arity(decls, src, pens, penl, a))
  }
  ## An ARRAY literal (a `[E; N]` FIELD's value, e.g. `S(pad = 9, arr = [10, 20, 30])`): write each
  ## element at its RUNNING byte offset through the same writer, so a STRUCT/enum element lands in full
  ## and the following elements stay aligned. Advancing by the width each element actually reports means
  ## a heterogeneous literal (a TUPLE, which parses as an ArrayLit too) also lays out correctly.
  if ex_is_array_lit(pe) {
    mut ag := ex_array_lit_ehead(pe)
    mut ao := off
    mut atot := 0
    while ag != 0 {
      aga := deref(arg_p(ag))
      aw := emit_a64_store_payload_at(aga.e, ao, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      ao = ao + aw * 8
      atot = atot + aw
      ag = aga.next
    }
    return atot
  }
  if expr_is_str_lit(pe) {
    ## a `str` payload ({ptr,len}) needs its `.Lstr` rodata emitted for the enum-value data walk (not yet
    ## wired for non-print str-lits) — fail LOUD rather than store a dangling pointer. Reserve 2 words.
    push_str(sb, "  brk #0 // str enum payload (deferred)\n")
    return 2
  }
  emit_a64_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "  str x0, [x29, #") ; push_int(sb, off) ; push_str(sb, "]\n")
  return 1
}

## The POINTER-relative twin of `emit_a64_store_payload_at`: store the (possibly nested) aggregate value
## `pe` at `[<the address held at the TOP OF THE STACK> + off]`, returning the words written. The base
## address is re-loaded from `[sp]` immediately before EVERY word store because the nested value emits
## clobber every scratch register (they are stack-BALANCED, so `[sp]` still holds the base each time).
## This is what lets a whole-ELEMENT write `xs[i] = S(…)` deliver a NESTED struct / `[T; N]`-field
## literal at a RUNTIME index: the one-word-per-argument positional store it replaces dropped every word
## of an aggregate field past the first AND mis-aligned every field after it. For an ALL-SCALAR literal
## the emitted text is byte-identical to that positional store.
emit_a64_store_payload_atptr := fn(pe : ptr(Expr), off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  if expr_is_struct_lit(pe) {
    sns := expr_struct_lit_ns(pe)
    snl := expr_struct_lit_nl(pe)
    mut g := ex_struct_lit_args(pe)
    mut o2 := off
    while g != 0 {
      ga := deref(arg_p(g))
      w := emit_a64_store_payload_atptr(ga.e, o2, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      o2 = o2 + w * 8
      g = ga.next
    }
    return i64(struct_words(decls, src, sns, snl, a))
  }
  if expr_is_enum_lit(pe) {
    pens := expr_enum_lit_ns(pe)
    penl := expr_enum_lit_nl(pe)
    pvidx := variant_index(decls, src, pens, penl, expr_enum_variant_ns(pe), expr_enum_variant_nl(pe), a)
    push_str(sb, "  ldr x0, =") ; push_int(sb, pvidx) ; push_str(sb, "\n  ldr x1, [sp]\n  str x0, [x1, #") ; push_int(sb, off) ; push_str(sb, "]\n")
    mut g := ex_enum_lit_args(pe)
    mut wo := 1
    while g != 0 {
      ga := deref(arg_p(g))
      cw := emit_a64_store_payload_atptr(ga.e, off + wo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      wo = wo + cw
      g = ga.next
    }
    return 1 + i64(enum_max_arity(decls, src, pens, penl, a))
  }
  if ex_is_array_lit(pe) {
    mut ag := ex_array_lit_ehead(pe)
    mut ao := off
    mut atot := 0
    while ag != 0 {
      aga := deref(arg_p(ag))
      aw := emit_a64_store_payload_atptr(aga.e, ao, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      ao = ao + aw * 8
      atot = atot + aw
      ag = aga.next
    }
    return atot
  }
  if expr_is_str_lit(pe) {
    push_str(sb, "  brk #0 // str element payload (deferred)\n")
    return 2
  }
  emit_a64_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "  ldr x1, [sp]\n  str x0, [x1, #") ; push_int(sb, off) ; push_str(sb, "]\n")
  return 1
}

emit_a64_enumval_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ens := expr_enum_lit_ns(e)
  enl := expr_enum_lit_nl(e)
  vidx := variant_index(decls, src, ens, enl, expr_enum_variant_ns(e), expr_enum_variant_nl(e), a)
  words := 1 + i64(enum_max_arity(decls, src, ens, enl, a))
  ok := vidx >= 0 and (A64_AGG + words * 8) <= A64_AGG_LIM
  if ok {
    blk := A64_AGG
    A64_AGG = A64_AGG + words * 8
    push_str(sb, "  ldr x0, =") ; push_int(sb, vidx) ; push_str(sb, "\n  str x0, [x29, #") ; push_int(sb, blk) ; push_str(sb, "]\n")
    ## payload args (scalar / struct / nested-enum / str) written past the disc at word 1.. by the shared
    ## multi-word writer, so an aggregate or nested-enum payload lands in full (§8 piece 3b).
    mut g := ex_enum_lit_args(e)
    mut wo := 1
    while g != 0 {
      ga := deref(arg_p(g))
      cw := emit_a64_store_payload_at(ga.e, blk + wo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      wo = wo + cw
      g = ga.next
    }
    push_str(sb, "  add x0, x29, #") ; push_int(sb, blk) ; push_str(sb, "\n")
  }
  if not ok { push_str(sb, "  brk #0 // unsupported enum-value argument\n") }
}

## Deliver a struct VALUE `e` into the return registers word k → x_k (x0..x7) — the §8 register
## struct-return convention (piece 2). Handles: a StructLit `S(…)` (push each field value, then pop in
## REVERSE into x_(nf-1)..x0 so word k lands in x_k, exactly like x86's emit_struct_value StructLit arm);
## a tail struct-returning CALL (the callee already delivered the regs — just emit the call); a struct
## Var LOCAL (read its frame words → x_k) or struct PARAM (by-reference — its slot holds the base ptr, read
## through it). All-scalar, ≤8 words; anything else is a LOUD `brk`.
emit_a64_struct_value := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ## Tuple literals are Expr::ArrayLit, not StructLit.  Deliver scalar components in reverse stack
  ## order so component k lands in xk, exactly matching the x86 tuple-return convention.
  if ex_is_array_lit(e) {
    nel := a64_alit_nel(e)
    if nel >= 1 and nel <= 7 {
      mut g := ex_array_lit_ehead(e)
      mut k := 0
      while g != 0 {
        ga := deref(arg_p(g))
        emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  str x0, [sp, #-16]!\n")
        k = k + 1
        g = ga.next
      }
      mut j := k
      while j > 0 {
        j = j - 1
        push_str(sb, "  ldr x") ; push_int(sb, j) ; push_str(sb, ", [sp], #16\n")
      }
    }
    if nel < 1 or nel > 7 { push_str(sb, "  brk #0 // unsupported tuple return width\n") }
    return
  }
  if expr_is_struct_lit(e) {
    slns := expr_struct_lit_ns(e)
    slnl := expr_struct_lit_nl(e)
    ## an ALL-SCALAR struct literal: push each 1-word field, pop in REVERSE so word k → x_k (unchanged).
    if a64_struct_all_scalar(decls, src, slns, slnl, a) {
      mut g := ex_struct_lit_args(e)
      mut k := 0
      while g != 0 {
        ga := deref(arg_p(g))
        emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  str x0, [sp, #-16]!\n")
        k += 1
        g = ga.next
      }
      mut j := k
      while j > 0 {
        j = j - 1
        push_str(sb, "  ldr x") ; push_int(sb, j) ; push_str(sb, ", [sp], #16\n")
      }
    }
    ## a struct literal WITH an aggregate field (an enum/str field): materialize the full {…} into an
    ## A64_AGG block by field (the multi-word writer), then load its words → x_k. Only ≤8 words reach here.
    if not a64_struct_all_scalar(decls, src, slns, slnl, a) {
      w := i64(struct_words(decls, src, slns, slnl, a))
      emit_a64_aggval_arg(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  mov x9, x0\n")
      mut k := 0
      while k < w { push_str(sb, "  ldr x") ; push_int(sb, k) ; push_str(sb, ", [x9, #") ; push_int(sb, k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
    }
    return
  }
  ## a struct-valued if-EXPRESSION `if c { … } else { … }`: dispatch on the condition, deliver each
  ## branch's struct value into x0..x_(w-1) via this same routine. Both branches share the value type,
  ## so after the join the return registers hold the branch that ran. (Enables `return if c {S(…)}
  ## else {S(…)}` and, via the binding store below, `x := if c {…} else {…}` with non-call branches.)
  if a64_is_if(e) {
    id := a64_next_label()
    emit_a64_expr(a64_if_cond(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, "  cbz x0, .Lsvelse") ; push_int(sb, id) ; push_str(sb, "\n")
    emit_a64_struct_value(a64_if_then(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, "  b .Lsvend") ; push_int(sb, id) ; push_str(sb, "\n")
    push_str(sb, ".Lsvelse") ; push_int(sb, id) ; push_str(sb, ":\n")
    emit_a64_struct_value(a64_if_else(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, ".Lsvend") ; push_int(sb, id) ; push_str(sb, ":\n")
    return
  }
  ## a struct-valued match-EXPRESSION over an ENUM LOCAL scrutinee `match o { V(p) => S(…) … }`: dispatch
  ## on the discriminant (like emit_a64_match_arms) but DELIVER each arm's struct value into the return
  ## registers via this routine. Only SIMPLE arms (variant/wildcard, expression body); the enum scrutinee
  ## must be a resolvable LOCAL. Anything else falls through to the fail-loud `brk` below (never silent).
  if a64_is_match(e) {
    escrut := a64_match_scrut(e)
    armhead := a64_match_armh(e)
    esns := ex_var_ns(escrut)
    esnl := ex_var_nl(escrut)
    eens := a64_local_enum_ns(body_head, src, esns, esnl, a)
    eenl := a64_local_enum_nl(body_head, src, esns, esnl, a)
    eeoff := a64_local_off(body_head, src, esns, esnl, pcount, a, decls)
    if esnl != 0 and eenl != 0 and eeoff >= 0 and a64_match_arms_simple(armhead) {
      endid := a64_next_label()
      mut ar := armhead
      while ar != 0 {
        am := deref(arm_p(ar))
        aid := a64_next_label()
        vidx := variant_index(decls, src, eens, eenl, am.vs, am.vl, a)
        if am.wild != 1 { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, eeoff) ; push_str(sb, "]\n  ldr x1, =") ; push_int(sb, vidx) ; push_str(sb, "\n  cmp x0, x1\n  b.ne .Lsvarmskip") ; push_int(sb, aid) ; push_str(sb, "\n") }
        oens := A64_ARM_ENS ; oenl := A64_ARM_ENL ; ovs := A64_ARM_VS ; ovl := A64_ARM_VL ; obN := A64_ARM_BINDS
        A64_ARM_ENS = eens ; A64_ARM_ENL = eenl ; A64_ARM_VS = am.vs ; A64_ARM_VL = am.vl ; A64_ARM_BINDS = unchecked bitcast(usize, am.binds_head)
        emit_a64_struct_value(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, eeoff)
        A64_ARM_ENS = oens ; A64_ARM_ENL = oenl ; A64_ARM_VS = ovs ; A64_ARM_VL = ovl ; A64_ARM_BINDS = obN
        push_str(sb, "  b .Lsvmend") ; push_int(sb, endid) ; push_str(sb, "\n")
        if am.wild != 1 { push_str(sb, ".Lsvarmskip") ; push_int(sb, aid) ; push_str(sb, ":\n") }
        ar = am.next
      }
      push_str(sb, "  brk #0 // no matching arm\n")
      push_str(sb, ".Lsvmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
      return
    }
  }
  crs := a64_call_ret_struct_span(e, decls, src, a)
  if crs.n != 0 {
    emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    return
  }
  ns := ex_var_ns(e)
  nl := ex_var_nl(e)
  mut done := false
  if nl != 0 {
    sns := a64_local_struct_ns(body_head, src, ns, nl, a)
    snl := a64_local_struct_nl(body_head, src, ns, nl, a)
    poff := a64_local_off(body_head, src, ns, nl, pcount, a, decls)
    if snl != 0 and poff >= 0 {
      w := i64(struct_words(decls, src, sns, snl, a))
      mut k := 0
      while k < w { push_str(sb, "  ldr x") ; push_int(sb, k) ; push_str(sb, ", [x29, #") ; push_int(sb, poff + k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
      done = true
    }
    if not done {
      pidx := param_find(params_head, src, ns, nl, a)
      psns := a64_param_struct_ns(params_head, src, ns, nl, a, decls)
      psnl := a64_param_struct_nl(params_head, src, ns, nl, a, decls)
      if pidx >= 0 and psnl != 0 {
        w := i64(struct_words(decls, src, psns, psnl, a))
        push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "]\n")
        mut k := 0
        while k < w { push_str(sb, "  ldr x") ; push_int(sb, k) ; push_str(sb, ", [x9, #") ; push_int(sb, k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
        done = true
      }
    }
  }
  if not done { push_str(sb, "  brk #0 // unsupported struct return value\n") }
}

## Deliver a WIDE-struct return VALUE `e` (§8 piece 2b SRET) THROUGH the indirect result pointer: reload
## the caller-supplied destination (spilled at A64_SRET_SLOT) into x9, then word-copy the struct into
## [x9 + k*8]. Supports a struct LOCAL var (`return v`) and a struct LITERAL (`return S(…)`); anything
## else keeps the fail-loud `brk` (never a silent wrong value). x10 is the copy scratch (x8/x9 reserved).
emit_a64_sret_store := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  mut done := false
  ## `return v` — v is a struct LOCAL: copy its frame slots into the destination.
  ns := ex_var_ns(e)
  nl := ex_var_nl(e)
  ## WIDE-ENUM SRET (§8 piece 3, > 8 words): the return type is an enum (A64_RET_SRET names it, distinguished
  ## by enum_decl_of) — deliver its {disc, payload…} block through the x8 destination (reloaded to x9 from
  ## A64_SRET_SLOT). Two shapes: `return v` where v is an enum LOCAL (word-copy its slots), and `return E.V(…)`
  ## where the literal is materialized into the A64_ENUM_SRET_BLK scratch first, then word-copied through x9.
  if enum_decl_of(decls, src, A64_RET_SRET_NS, A64_RET_SRET_NL) >= 0 {
    ew := 1 + i64(enum_max_arity(decls, src, A64_RET_SRET_NS, A64_RET_SRET_NL, a))
    ## `return v` — v is an enum LOCAL (incl. one bound to a wide-enum call): word-copy its frame slots.
    if nl != 0 {
      lenl := a64_local_enum_nl(body_head, src, ns, nl, a)
      loff := a64_local_off(body_head, src, ns, nl, pcount, a, decls)
      if lenl != 0 and loff >= 0 {
        push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, A64_SRET_SLOT) ; push_str(sb, "]\n")
        mut ek := 0
        while ek < ew { push_str(sb, "  ldr x10, [x29, #") ; push_int(sb, loff + ek * 8) ; push_str(sb, "]\n  str x10, [x9, #") ; push_int(sb, ek * 8) ; push_str(sb, "]\n") ; ek = ek + 1 }
        done = true
      }
    }
    ## `return E.V(payload…)` — materialize {disc, payload…} into the enum-SRET scratch via the shared
    ## multi-word writer (disc at word 0, payload from word 1), then word-copy the block through x9. The
    ## dest pointer x9 is reloaded AFTER materialization (which clobbers x0/x1/x9), so it stays live.
    if (not done) and expr_is_enum_lit(e) {
      blk := A64_ENUM_SRET_BLK
      vidx := variant_index(decls, src, expr_enum_lit_ns(e), expr_enum_lit_nl(e), expr_enum_variant_ns(e), expr_enum_variant_nl(e), a)
      push_str(sb, "  ldr x0, =") ; push_int(sb, vidx) ; push_str(sb, "\n  str x0, [x29, #") ; push_int(sb, blk) ; push_str(sb, "]\n")
      mut g := ex_enum_lit_args(e)
      mut wo := i64(1)
      while g != 0 {
        ga := deref(arg_p(g))
        cw := emit_a64_store_payload_at(ga.e, blk + wo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        wo = wo + cw
        g = ga.next
      }
      push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, A64_SRET_SLOT) ; push_str(sb, "]\n")
      mut ek := 0
      while ek < ew { push_str(sb, "  ldr x10, [x29, #") ; push_int(sb, blk + ek * 8) ; push_str(sb, "]\n  str x10, [x9, #") ; push_int(sb, ek * 8) ; push_str(sb, "]\n") ; ek = ek + 1 }
      done = true
    }
    ## `return mk(…)` — WIDE-ENUM SRET TAIL-FORWARD (the enum analogue of the wide-STRUCT arm below): the
    ## return VALUE is itself a call to a wide-enum-returning fn, so BOTH sides deliver through an x8
    ## indirect result. Rather than stage the inner {disc, payload…} block in a scratch and copy it through
    ## our own destination, hand the INNER call our OWN destination pointer directly: the one-shot
    ## A64_SRET_DST hand-off in its INDIRECT flavour makes the call arm emit `ldr x8, [x29, #<slot>]` (our
    ## spilled incoming x8) right before the `bl` — a64_fn_returns_sret already recognizes a wide-ENUM
    ## callee — so the callee writes straight into the outer caller's block. Nothing is copied afterwards
    ## and no extra frame is reserved. Was a fail-loud `brk` (no arm matched a call return value).
    if not done {
      ers := a64_call_ret_enum_sret_span(e, decls, src, a)
      if ers.n != 0 {
        A64_SRET_DST_ON = true
        A64_SRET_DST = A64_SRET_SLOT
        A64_SRET_DST_IND = true
        emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        A64_SRET_DST_ON = false
        A64_SRET_DST_IND = false
        done = true
      }
    }
    if not done { push_str(sb, "  brk #0 // unsupported wide-enum (SRET) return value\n") }
    return
  }
  if (not done) and nl != 0 {
    sns := a64_local_struct_ns(body_head, src, ns, nl, a)
    snl := a64_local_struct_nl(body_head, src, ns, nl, a)
    poff := a64_local_off(body_head, src, ns, nl, pcount, a, decls)
    if snl != 0 and poff >= 0 {
      w := i64(struct_words(decls, src, sns, snl, a))
      push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, A64_SRET_SLOT) ; push_str(sb, "]\n")
      mut k := 0
      while k < w { push_str(sb, "  ldr x10, [x29, #") ; push_int(sb, poff + k * 8) ; push_str(sb, "]\n  str x10, [x9, #") ; push_int(sb, k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
      done = true
    }
  }
  ## `return S(f = …, …)` — an ALL-SCALAR struct LITERAL: evaluate each field into x0 and store it straight
  ## into the destination at its word offset (x9 = dest, reloaded once; x0/x1/x9 scratch used by field emit
  ## do not disturb x9 between stores because it is reloaded per-field-free — reload once and keep x9 live).
  if (not done) and expr_is_struct_lit(e) {
    slns := expr_struct_lit_ns(e)
    slnl := expr_struct_lit_nl(e)
    if a64_struct_all_scalar(decls, src, slns, slnl, a) {
      push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, A64_SRET_SLOT) ; push_str(sb, "]\n  str x9, [sp, #-16]!\n")
      mut g := ex_struct_lit_args(e)
      mut k := 0
      while g != 0 {
        ga := deref(arg_p(g))
        emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  ldr x9, [sp]\n  str x0, [x9, #") ; push_int(sb, k * 8) ; push_str(sb, "]\n")
        k = k + 1
        g = ga.next
      }
      push_str(sb, "  add sp, sp, #16\n")
      done = true
    }
  }
  ## `return mk(…)` — SRET TAIL-FORWARD: the return VALUE is itself a call to a wide-struct-returning fn, so
  ## BOTH sides deliver through an x8 indirect result. Rather than stage the inner result in a scratch block
  ## and copy it through our own destination, hand the INNER call our OWN destination pointer directly: the
  ## one-shot A64_SRET_DST hand-off in its INDIRECT flavour makes the call arm emit `ldr x8, [x29, #<slot>]`
  ## (our spilled incoming x8) right before the `bl`, so the callee writes straight into the outer caller's
  ## block. Nothing is copied afterwards and no extra frame is reserved. x29 is untouched by the inner call's
  ## argument push/pop dance, and the load happens AFTER those pops, so the pointer reaches the `bl` intact.
  ## Was a fail-loud `brk` (no arm matched a call return value).
  if not done {
    frs := a64_call_ret_sret_span(e, decls, src, a)
    if frs.n != 0 {
      A64_SRET_DST_ON = true
      A64_SRET_DST = A64_SRET_SLOT
      A64_SRET_DST_IND = true
      emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      A64_SRET_DST_ON = false
      A64_SRET_DST_IND = false
      done = true
    }
  }
  if not done { push_str(sb, "  brk #0 // unsupported wide-struct (SRET) return value\n") }
}

## Deliver an ENUM VALUE `e` into the return registers word 0 = disc, word k+1 = payload → x_k (§8 piece 3
## register enum-return convention). Handles an EnumLit (push disc + each payload, pop reverse into x_k),
## a tail enum-returning CALL (callee already delivered), and an enum Var LOCAL / by-reference PARAM (read
## the {disc, payload…} words → x_k). A narrow variant leaves the unused high regs uninitialized — the
## caller stores the enum's full width but a matched arm never reads past its own payload. ≤8 words.
emit_a64_enum_value := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  if expr_is_enum_lit(e) {
    vidx := variant_index(decls, src, expr_enum_lit_ns(e), expr_enum_lit_nl(e), expr_enum_variant_ns(e), expr_enum_variant_nl(e), a)
    push_str(sb, "  ldr x0, =") ; push_int(sb, vidx) ; push_str(sb, "\n  str x0, [sp, #-16]!\n")
    mut g := ex_enum_lit_args(e)
    mut k := 1
    while g != 0 {
      ga := deref(arg_p(g))
      emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  str x0, [sp, #-16]!\n")
      k = k + 1
      g = ga.next
    }
    mut j := k
    while j > 0 {
      j = j - 1
      push_str(sb, "  ldr x") ; push_int(sb, j) ; push_str(sb, ", [sp], #16\n")
    }
    return
  }
  cre := a64_call_ret_enum_span(e, decls, src, a)
  if cre.n != 0 {
    emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    return
  }
  ns := ex_var_ns(e)
  nl := ex_var_nl(e)
  mut done := false
  if nl != 0 {
    lens := a64_local_enum_ns(body_head, src, ns, nl, a)
    lenl := a64_local_enum_nl(body_head, src, ns, nl, a)
    loff := a64_local_off(body_head, src, ns, nl, pcount, a, decls)
    if lenl != 0 and loff >= 0 {
      w := 1 + i64(enum_max_arity(decls, src, lens, lenl, a))
      mut k := 0
      while k < w { push_str(sb, "  ldr x") ; push_int(sb, k) ; push_str(sb, ", [x29, #") ; push_int(sb, loff + k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
      done = true
    }
    if not done {
      pidx := param_find(params_head, src, ns, nl, a)
      penl := a64_param_enum_nl(params_head, src, ns, nl, decls)
      if pidx >= 0 and penl != 0 {
        pens := a64_param_enum_ns(params_head, src, ns, nl, decls)
        w := 1 + i64(enum_max_arity(decls, src, pens, penl, a))
        push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "]\n")
        mut k := 0
        while k < w { push_str(sb, "  ldr x") ; push_int(sb, k) ; push_str(sb, ", [x9, #") ; push_int(sb, k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
        done = true
      }
    }
  }
  if not done { push_str(sb, "  brk #0 // unsupported enum return value\n") }
}

## Materialize a struct-RETURNING CALL `f(…)` passed as a call ARGUMENT into a reserved A64_AGG block and
## leave the block ADDRESS in x0 (the by-reference aggregate-argument convention, §8 piece 2). The callee
## delivers word k in x_k (x0..x_(w-1)); store them into the block, then hand its address by reference —
## exactly like emit_a64_aggval_arg but sourcing the words from the register struct-return.
emit_a64_callret_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  crs := a64_call_ret_struct_span(e, decls, src, a)
  words := i64(struct_words(decls, src, crs.s, crs.n, a))
  ok := crs.n != 0 and (A64_AGG + words * 8) <= A64_AGG_LIM
  if ok {
    blk := A64_AGG
    emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    mut k := 0
    while k < words { push_str(sb, "  str x") ; push_int(sb, k) ; push_str(sb, ", [x29, #") ; push_int(sb, blk + k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
    push_str(sb, "  add x0, x29, #") ; push_int(sb, blk) ; push_str(sb, "\n")
    A64_AGG = A64_AGG + words * 8
  }
  if not ok { push_str(sb, "  brk #0 // unsupported struct-returning-call argument\n") }
}

## Materialize an enum-RETURNING CALL `f(…)` passed as a call ARGUMENT into a reserved A64_AGG block and
## leave the block ADDRESS in x0 (§8 piece 3). The callee delivers word 0 = disc, word k+1 = payload in
## x0..x_(w-1); store them into the block (full enum width), then pass its address by reference.
emit_a64_enumret_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  cre := a64_call_ret_enum_span(e, decls, src, a)
  words := 1 + i64(enum_max_arity(decls, src, cre.s, cre.n, a))
  ok := cre.n != 0 and (A64_AGG + words * 8) <= A64_AGG_LIM
  if ok {
    blk := A64_AGG
    emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    mut k := 0
    while k < words { push_str(sb, "  str x") ; push_int(sb, k) ; push_str(sb, ", [x29, #") ; push_int(sb, blk + k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
    push_str(sb, "  add x0, x29, #") ; push_int(sb, blk) ; push_str(sb, "\n")
    A64_AGG = A64_AGG + words * 8
  }
  if not ok { push_str(sb, "  brk #0 // unsupported enum-returning-call argument\n") }
}

## Materialize a WIDE (SRET) struct-returning CALL `f(…)` passed as a call ARGUMENT into a reserved A64_AGG
## block and leave the block ADDRESS in x0 (§8 piece 2b, argument position). Unlike the ≤8-word register
## struct-return there are no result registers to store from: the callee writes the whole struct through the
## AAPCS64 x8 indirect-result pointer, and in argument position there is NO destination local to point it at.
## So reserve the block FIRST, hand its base down as the callee's x8 (the A64_SRET_DST one-shot, saved and
## restored so a nested SRET argument allocates its own distinct block), then pass that same block by
## reference — the aggregate-parameter ABI. Was a RAW SIGSEGV: the call fell through to the scalar argument
## path with no x8 wired at all, so the callee wrote 9+ words through whatever x8 happened to hold.
emit_a64_sretcall_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  srs := a64_call_ret_sret_span(e, decls, src, a)
  words := i64(struct_words(decls, src, srs.s, srs.n, a))
  ok := srs.n != 0 and (A64_AGG + words * 8) <= A64_AGG_LIM
  if ok {
    blk := A64_AGG
    A64_AGG = A64_AGG + words * 8
    oon := A64_SRET_DST_ON ; oof := A64_SRET_DST ; oid := A64_SRET_DST_IND
    A64_SRET_DST_ON = true ; A64_SRET_DST = blk ; A64_SRET_DST_IND = false
    emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    A64_SRET_DST_ON = oon ; A64_SRET_DST = oof ; A64_SRET_DST_IND = oid
    push_str(sb, "  add x0, x29, #") ; push_int(sb, blk) ; push_str(sb, "\n")
  }
  if not ok { push_str(sb, "  brk #0 // unsupported wide (SRET) struct-returning-call argument\n") }
}

## The wide-ENUM analogue of emit_a64_sretcall_arg (§8 piece 3, > 8 words): an enum-returning CALL wider than
## the 8-register budget also delivers through x8, so as a call ARGUMENT it needs the same reserved block +
## x8 hand-off + by-reference pass. Same latent raw-SIGSEGV shape, closed the same way.
emit_a64_enumsret_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ers := a64_call_ret_enum_sret_span(e, decls, src, a)
  words := 1 + i64(enum_max_arity(decls, src, ers.s, ers.n, a))
  ok := ers.n != 0 and (A64_AGG + words * 8) <= A64_AGG_LIM
  if ok {
    blk := A64_AGG
    A64_AGG = A64_AGG + words * 8
    oon := A64_SRET_DST_ON ; oof := A64_SRET_DST ; oid := A64_SRET_DST_IND
    A64_SRET_DST_ON = true ; A64_SRET_DST = blk ; A64_SRET_DST_IND = false
    emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    A64_SRET_DST_ON = oon ; A64_SRET_DST = oof ; A64_SRET_DST_IND = oid
    push_str(sb, "  add x0, x29, #") ; push_int(sb, blk) ; push_str(sb, "\n")
  }
  if not ok { push_str(sb, "  brk #0 // unsupported wide (SRET) enum-returning-call argument\n") }
}

## Deliver the bounded `[u8; N]` return carrier in x0. A64's existing local-array representation is
## word-granular, so pack the low byte of each local element at this ABI boundary. A direct call already
## returns the same carrier in x0 and is forwarded unchanged. This is deliberately limited to the shared
## `[u8; N]`, 1 <= N <= 8, classifier; every other array shape remains a located trap.
emit_a64_byte_array_value := fn(e : ptr(Expr), in out sb : rt::StrBuf, nel : i64, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  mut done := false
  match deref(e) {
    Expr::Var(ns, nl) => {
      off := a64_local_off(body_head, src, ns, nl, pcount, a, decls)
      arrlocal := a64_is_array_local(body_head, src, ns, nl, a)
      mut localok := nel >= 1 and nel <= 8
      if off < 0 { localok = false }
      if not arrlocal { localok = false }
      if localok {
        push_str(sb, "  mov x0, #0\n")
        mut k := 0
        while k < nel {
          push_str(sb, "  ldr x1, [x29, #") ; push_int(sb, off + k * 8) ; push_str(sb, "]\n  and x1, x1, #255\n")
          if k > 0 { push_str(sb, "  lsl x1, x1, #") ; push_int(sb, k * 8) ; push_str(sb, "\n") }
          push_str(sb, "  orr x0, x0, x1\n")
          k = k + 1
        }
        done = true
      }
    }
    Expr::Call(cs, cl, nargs, args_head) => {
      if fixed_array_byte_return_len(e, decls, src, a) == nel {
        emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        done = true
      }
    }
    _ => {}
  }
  if not done { push_str(sb, "  brk #0 // unsupported bounded byte-array return value\n") }
}

emit_a64_epilogue := fn(frame : i64, in out sb : rt::StrBuf) {
  ## a float-returning fn delivers its result in d0 (SysV): move the value bits (x0) into d0 before ret.
  if A64_RET_FLOAT { push_str(sb, "  fmov d0, x0\n") }
  push_str(sb, "  mov sp, x29\n")
  ## AArch64 pair load/store immediates top out at +504 bytes. Keep the old post-index form for the
  ## common small frame so its emission stays byte-identical; larger frames restore the pair at offset 0
  ## and advance SP through a register-sized immediate. x9 is caller-saved and is free at the epilogue.
  if frame <= 504 {
    push_str(sb, "  ldp x29, x30, [sp], #") ; push_int(sb, frame) ; push_str(sb, "\n")
  }
  if frame > 504 {
    push_str(sb, "  ldp x29, x30, [sp]\n")
    push_str(sb, "  mov x9, #") ; push_int(sb, frame) ; push_str(sb, "\n")
    push_str(sb, "  add sp, sp, x9\n")
  }
  push_str(sb, "  ret\n")
}

emit_a64_stmts := fn(list_head : usize, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), frame : i64, bind_head : ptr(mut Bind), bind_base : i64) {
  mut s := list_head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        ## FLAT (no nesting): a StructLit constructs fields into p's slots; an EnumLit constructs
        ## {disc, payload…}; anything else is the scalar store (PARAM > GLOBAL > LOCAL). Guards
        ## (`isslit`/`iselit`/`useframe`) keep the paths disjoint.
        isslit := expr_is_struct_lit(v)
        iselit := expr_is_enum_lit(v)
        isalit := ex_is_array_lit(v)
        isslice := ex_is_slice(v)
        ## an aggregate-VAR copy `q := p` — RHS is a bare Var naming a struct/enum LOCAL. Word-copy the whole
        ## aggregate from p's slots into q's (a scalar store would drop all but word 0). `copyw` = the source
        ## local's full width; `soff` = its frame base. 0 = not an agg-var copy (a scalar Var stays the store).
        vcns := ex_var_ns(v)
        vcnl := ex_var_nl(v)
        mut copyw := i64(0)
        mut soff := i64(0) - 1
        if vcnl != 0 {
          csl := a64_local_struct_nl(body_head, src, vcns, vcnl, a)
          if csl != 0 { copyw = i64(struct_words(decls, src, a64_local_struct_ns(body_head, src, vcns, vcnl, a), csl, a)) }
          cel := a64_local_enum_nl(body_head, src, vcns, vcnl, a)
          if copyw == 0 and cel != 0 { copyw = 1 + i64(enum_max_arity(decls, src, a64_local_enum_ns(body_head, src, vcns, vcnl, a), cel, a)) }
          if copyw > 0 { soff = a64_local_off(body_head, src, vcns, vcnl, pcount, a, decls) }
        }
        ## A standard-byte aggregate FIELD copy (`copy := o.inner`) starts at a byte offset inside the
        ## inline root. S3(a) permits this first aligned nested aggregate consumer; an unaligned field
        ## remains fail-loud rather than becoming an unaligned multi-word copy.
        ## CLAYOUT S3(b) — AND THE CHILD MUST BE WORD-GRANULAR, because this copy is `copyw` whole
        ## WORDS into a destination local that is read back at WORD offsets. S3(b) made a SUB-WORD child
        ## constructible, which for the first time puts a byte-precise 4-byte child in front of this
        ## word copy: measured without the guard, `copy := o.inner` over
        ## `struct { data : [u8;8], inner : struct { a : u16, b : u16 } }` returned exit 1 here
        ## (`copy.a` read as 0) where the pre-S3(b) compiler TRAPPED — a wrong value where there had
        ## been a trap, which I11 forbids. The byte-precise whole-value COPIER is its own consumer; until
        ## it lands this is a located `brk`.
        ## CLAYOUT S3(c) — AND WHEN IT IS NOT WORD-GRANULAR, THE BYTE-PRECISE COPIER TAKES IT.
        ## `std_copy_kind` (shared, `lower_layout`) says whether the child has a byte-precise copy and
        ## of which shape; `stdbc` then switches the copy LOOP below from words to that plan, leaving
        ## every `(not iscopy)` guard in this arm untouched (the source place must still not be
        ## evaluated as a value — `emit_a64_expr` has no aggregate-field load and would emit a `brk`).
        ## Only a child OUTSIDE the copier's domain — one carrying a `str`, an enum, a union, a tuple
        ## or a non-byte array — is still a located `brk`.
        mut stdcopy := false
        mut stdbc := false
        mut stdbcts := 0
        mut stdbctl := 0
        if ex_is_field(v) {
          sfp := a64_std_path_ty(v, body_head, src, a, decls)
          if a64_std_path_ok(v, body_head, src, a, decls) and sfp.n != 0 and std_ty_aggregate(sfp.s, sfp.n, decls, src) {
            sbn := base_type_name(src, sfp.s, sfp.n)
            sbo := a64_std_path_bo(v, body_head, src, a, decls)
            sroot := a64_std_path_root_off(v, body_head, src, pcount, a, decls)
            wgok := std_struct_is_word_granular(decls, src, sfp.s, sfp.n, a)
            mut bck := 0
            if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 and (not wgok) { bck = std_copy_kind(decls, src, sfp.s, sfp.n, a) }
            if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 and sbo >= 0 and (sbo / 8) * 8 == sbo and sroot >= 0 and wgok {
              copyw = i64(struct_words(decls, src, sfp.s, sfp.n, a))
              soff = sroot + sbo
              stdcopy = copyw > 0
            }
            if bck != 0 and sbo >= 0 and sroot >= 0 {
              copyw = i64(struct_words(decls, src, sfp.s, sfp.n, a))
              soff = sroot + sbo
              stdbc = copyw > 0
              stdbcts = sfp.s
              stdbctl = sfp.n
            }
            if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 and (not wgok) and (not stdbc) { push_str(sb, "  brk #0 // standard byte-layout aggregate field extract outside the byte-precise copier's domain\n") }
          }
        }
        iscopy := copyw > 0 and soff >= 0
        ## a module-GLOBAL aggregate snapshot `p := GLOBAL` — RHS is a bare Var naming a module struct/enum
        ## GLOBAL/CONST (not a local). Word-copy the global's ascending `.data` cells (loaded via its label)
        ## into p's slots. `gcopyw` = the global's flattened width; disjoint from iscopy (a local source).
        mut gcopyw := i64(0)
        if vcnl != 0 and copyw == 0 {
          gss := a64_global_agg_struct_span(decls, src, vcns, vcnl)
          if gss.n != 0 { gcopyw = i64(struct_words(decls, src, gss.s, gss.n, a)) }
          ges := a64_global_agg_enum_span(decls, src, vcns, vcnl)
          if gcopyw == 0 and ges.n != 0 { gcopyw = 1 + i64(enum_max_arity(decls, src, ges.s, ges.n, a)) }
        }
        isgcopy := gcopyw > 0
        ## a local bound to a struct-RETURNING CALL `p := mk()` (§8 piece 2): the callee delivers word k in
        ## x_k, so store all the returned words into p's slots (not the single-word scalar store).
        crs := a64_binding_ret_struct_span(v, decls, src, a)
        iscr := crs.n != 0
        ## a local bound to an enum-RETURNING CALL `m := id(…)` (§8 piece 3): the callee delivers word 0 =
        ## disc, word k+1 = payload in x0.., so store the full enum width into m's slots.
        cre := a64_call_ret_enum_span(v, decls, src, a)
        iscre := cre.n != 0
        ## a local bound to a WIDE-struct-returning CALL `s := mk()` (§8 piece 2b SRET): the callee writes the
        ## whole struct through x8, so pass s's address in x8 and emit nothing after the call (disjoint from
        ## iscr — a64_binding_ret_struct_span uses the ≤8-word gate, so a wide callee leaves iscr false).
        srs := a64_call_ret_sret_span(v, decls, src, a)
        issret := srs.n != 0
        ## a local bound to a WIDE-enum-returning CALL `m := mk()` (§8 piece 3, > 8 words, x8 SRET): the callee
        ## writes the whole {disc, payload…} block through x8, so pass m's address in x8 and emit nothing after
        ## the call — the enum analogue of issret (disjoint from iscre, which uses the ≤8-word register gate).
        cres := a64_call_ret_enum_sret_span(v, decls, src, a)
        isenumsret := cres.n != 0
        ## a whole-ELEMENT copy `x := xs[i]` out of a word-granular struct array (a LOCAL array-lit,
        ## array GLOBAL, or composed deep place). The element is `eixw` words wide at base + i*eixw*8;
        ## x's own slots (sized to the same width by `a64_val_words`) receive the copy. 0 = not this shape
        ## (a scalar `x := xs[i]` over a scalar array keeps the ordinary one-word store).
        eixp := a64_index_elem_struct_span(v, src, a, decls)
        mut eixw := i64(0)
        mut eixbyte := false
        mut eixla := false
        mut eixga := false
        mut eixoff := i64(0) - 1
        mut eixnel := i64(0)
        mut eixdeep := false
        if eixp.n != 0 {
          eibx := ex_index_base(v)
          eins := ex_var_ns(eibx)
          einl := ex_var_nl(eibx)
          eixla = a64_is_array_local(body_head, src, eins, einl, a)
          eixga = (not eixla) and a64_is_array_global(decls, src, eins, einl)
          if eixla { eixoff = a64_local_off(body_head, src, eins, einl, pcount, a, decls) ; eixnel = a64_array_nel(body_head, src, eins, einl, a) }
          if eixga { eixnel = a64_alit_nel(a64_global_value(decls, src, eins, einl)) }
          if (eixla and eixoff >= 0) or eixga {
            if std_array_elem_byte_tier(decls, src, eixp.s, eixp.n, a) { eixw = i64(array_elem_word_reservation(decls, src, eixp.s, eixp.n, a)) ; eixbyte = true }
            if not std_array_elem_byte_tier(decls, src, eixp.s, eixp.n, a) { eixw = i64(struct_words(decls, src, eixp.s, eixp.n, a)) }
          }
          if eixw == 0 and (not a64_ex_is_var(eibx)) {
            if a64_place_idx_ok(eibx, body_head, src, params_head, pcount, a, decls) {
              if std_struct_is_word_granular(decls, src, eixp.s, eixp.n, a) { eixw = i64(struct_words(decls, src, eixp.s, eixp.n, a)) ; eixdeep = true }
            }
          }
        }
        iseix := eixw > 0
        isagg := isslit or iselit or isalit or isslice
        if (not isagg) and (not iscr) and (not iscre) and (not issret) and (not isenumsret) and (not iscopy) and (not isgcopy) and (not iseix) {
          if a64_direct_float_num(v, src, ns, nl) {
            emit_a64_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  scvtf d0, x0\n  fmov x0, d0\n")
          } else { emit_a64_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        }
        pidx := param_find(params_head, src, ns, nl, a)
        isout := pidx >= 0 and a64_param_is_out_scalar(params_head, src, pidx, decls)
        isglob := a64_is_global(decls, src, ns, nl, a)
        poff := a64_local_off(body_head, src, ns, nl, pcount, a, decls)
        mut voff := poff
        if pidx >= 0 { voff = 16 + pidx * 8 }
        useframe := (not isagg) and (not iscr) and (not iscre) and (not issret) and (not isenumsret) and (not iscopy) and (not isgcopy) and (not iseix) and ((pidx >= 0) or (voff >= 0 and (not isglob)))
        gname := str_at((src + ns), nl)
        if useframe and isout { push_str(sb, "  ldr x1, [x29, #") ; push_int(sb, voff) ; push_str(sb, "]\n  str x0, [x1]\n") }
        if useframe and (not isout) { push_str(sb, "  str x0, [x29, #") ; push_int(sb, voff) ; push_str(sb, "]\n") }
        ## agg-var copy: word-copy p's slots (soff) into q's slots (poff). Only when q has a frame home.
        if iscopy and poff >= 0 and (not stdbc) {
          mut cwk := i64(0)
          while cwk < copyw { push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, soff + cwk * 8) ; push_str(sb, "]\n  str x0, [x29, #") ; push_int(sb, poff + cwk * 8) ; push_str(sb, "]\n") ; cwk = cwk + 1 }
        }
        ## CLAYOUT S3(c): the same copy, but byte-precise — the child's §6.1 image at `soff` into the
        ## destination's own tier at `poff`, per the shared plan.
        if iscopy and poff >= 0 and stdbc { a64_std_copy(stdbcts, stdbctl, soff, poff, sb, decls, src, a) }
        if iscopy and poff < 0 { push_str(sb, "  brk #0 // agg-var copy to unresolved local\n") }
        ## global-aggregate snapshot: load the global's `.data` base by label, word-copy its cells into p's
        ## slots. Loads reflect the global's CURRENT words at the copy point (a later write to the global does
        ## not touch the independent local), matching the by-value snapshot semantics.
        if isgcopy and poff >= 0 {
          gsrc := str_at((src + vcns), vcnl)
          push_str(sb, "  adrp x9, ") ; push_str(sb, gsrc) ; push_str(sb, "\n  add x9, x9, :lo12:") ; push_str(sb, gsrc) ; push_str(sb, "\n")
          mut gwk := i64(0)
          while gwk < gcopyw { push_str(sb, "  ldr x0, [x9, #") ; push_int(sb, gwk * 8) ; push_str(sb, "]\n  str x0, [x29, #") ; push_int(sb, poff + gwk * 8) ; push_str(sb, "]\n") ; gwk = gwk + 1 }
        }
        if isgcopy and poff < 0 { push_str(sb, "  brk #0 // global-agg snapshot to unresolved local\n") }
        ## element copy: index → x0, scale by the element width, add the frame/label base into x2, then
        ## word-copy the element into x's slots. x2 survives the copy (no emit call in the loop).
        if iseix and poff >= 0 {
          if eixdeep {
            emit_a64_place_idx_addr(ex_index_base(v), ex_index_idx(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  mov x2, x0\n")
            mut eckd := i64(0)
            while eckd < eixw {
              push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, eckd * 8) ; push_str(sb, "]\n  str x0, [x29, #") ; push_int(sb, poff + eckd * 8) ; push_str(sb, "]\n")
              eckd = eckd + 1
            }
          }
          if not eixdeep {
            emit_a64_expr(ex_index_idx(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if A64_CHK {
              if eixnel > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, eixnel) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
            }
            if eixbyte {
              emit_a64_place_idx_addr(ex_index_base(v), ex_index_idx(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
              push_str(sb, "  mov x2, x0\n")
              nbix := i64(std_copy_image_bytes(decls, src, eixp.s, eixp.n, a))
              mut eckb := i64(0)
              while eckb < nbix {
                push_str(sb, "  ldrb w0, [x2, #") ; push_int(sb, eckb) ; push_str(sb, "]\n  strb w0, [x29, #") ; push_int(sb, poff + eckb) ; push_str(sb, "]\n")
                eckb = eckb + 1
              }
            }
            if not eixbyte {
              push_str(sb, "  mov x1, #") ; push_int(sb, eixw * 8) ; push_str(sb, "\n  mul x0, x0, x1\n")
              if eixla { push_str(sb, "  add x2, x0, x29\n  add x2, x2, #") ; push_int(sb, eixoff) ; push_str(sb, "\n") }
              if eixga {
                eign := str_at((src + ex_var_ns(ex_index_base(v))), ex_var_nl(ex_index_base(v)))
                push_str(sb, "  adrp x2, ") ; push_str(sb, eign) ; push_str(sb, "\n  add x2, x2, :lo12:") ; push_str(sb, eign) ; push_str(sb, "\n  add x2, x2, x0\n")
              }
              mut eck := i64(0)
              while eck < eixw {
                push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, eck * 8) ; push_str(sb, "]\n  str x0, [x29, #") ; push_int(sb, poff + eck * 8) ; push_str(sb, "]\n")
                eck = eck + 1
              }
            }
          }
        }
        if iseix and poff < 0 { push_str(sb, "  brk #0 // array-element copy to unresolved local\n") }
        if (not isagg) and (not iscr) and (not iscre) and (not issret) and (not isenumsret) and (not iscopy) and (not isgcopy) and (not iseix) and (not useframe) and isglob {
          push_str(sb, "  adrp x9, ") ; push_str(sb, gname) ; push_str(sb, "\n  add x9, x9, :lo12:") ; push_str(sb, gname) ; push_str(sb, "\n  str x0, [x9]\n")
        }
        if (not isagg) and (not iscr) and (not iscre) and (not issret) and (not isenumsret) and (not iscopy) and (not isgcopy) and (not iseix) and (not useframe) and (not isglob) { push_str(sb, "  brk #0 // assign to unresolved var\n") }
        ## WIDE-STRUCT SRET bind `s := mk(…)`: set the one-shot destination hand-off (s's frame offset), emit
        ## the call — the call arm turns it into `add x8, x29, #poff` before the `bl`, and the callee writes
        ## the whole struct through x8 straight into s's slots (nothing to store after the call). A global /
        ## unresolved destination is unsupported here (would need a temp) → fail loud.
        if issret {
          if poff >= 0 {
            oon := A64_SRET_DST_ON ; oof := A64_SRET_DST
            A64_SRET_DST_ON = true ; A64_SRET_DST = poff
            emit_a64_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            A64_SRET_DST_ON = oon ; A64_SRET_DST = oof
          }
          if poff < 0 { push_str(sb, "  brk #0 // SRET call result to unresolved local\n") }
        }
        ## WIDE-ENUM SRET bind `m := mk(…)` (> 8 words): identical x8 hand-off to the wide-struct SRET path —
        ## set the one-shot destination (m's frame offset), emit the call (the call arm turns it into
        ## `add x8, x29, #poff` before the `bl`), and the callee writes the whole {disc, payload…} block into
        ## m's slots (nothing to store after). A global / unresolved destination is unsupported → fail loud.
        if isenumsret {
          if poff >= 0 {
            eon := A64_SRET_DST_ON ; eof := A64_SRET_DST
            A64_SRET_DST_ON = true ; A64_SRET_DST = poff
            emit_a64_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            A64_SRET_DST_ON = eon ; A64_SRET_DST = eof
          }
          if poff < 0 { push_str(sb, "  brk #0 // wide-enum SRET call result to unresolved local\n") }
        }
        ## struct-value bind: deliver the RHS struct into x0..x_(w-1) via the register struct-value path
        ## (a struct-returning call, or an if-/match-EXPRESSION whose branches/arms deliver a struct), then
        ## store each word to p's slot. emit_a64_struct_value is byte-equivalent to the old direct-call emit
        ## for the call case and additionally handles the if/match delivery.
        if iscr {
          mut crw := i64(struct_words(decls, src, crs.s, crs.n, a))
          if str_at((src + crs.s), 1) == "(" { crw = a64_tuple_words(src, crs.s, crs.n) }
          if poff >= 0 {
            emit_a64_struct_value(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            mut k := 0
            while k < crw { push_str(sb, "  str x") ; push_int(sb, k) ; push_str(sb, ", [x29, #") ; push_int(sb, poff + k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
          }
          if poff < 0 { push_str(sb, "  brk #0 // struct-call result to unresolved local\n") }
        }
        ## enum-returning-call bind: emit the call (delivers word 0 = disc, word k+1 = payload), store the
        ## full enum width into m's slots.
        if iscre {
          crew := 1 + i64(enum_max_arity(decls, src, cre.s, cre.n, a))
          if poff >= 0 {
            emit_a64_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            mut k := 0
            while k < crew { push_str(sb, "  str x") ; push_int(sb, k) ; push_str(sb, ", [x29, #") ; push_int(sb, poff + k * 8) ; push_str(sb, "]\n") ; k = k + 1 }
          }
          if poff < 0 { push_str(sb, "  brk #0 // enum-call result to unresolved local\n") }
        }
        ## struct construct: store each positional field value at base + k*8.
        stys := expr_struct_lit_ns(v)
        styn := expr_struct_lit_nl(v)
        slitstd := isslit and poff >= 0 and layout_kind_is_byte(layout_kind(decls, src, stys, styn, a))
        if slitstd { _stdw := a64_std_store_struct(v, poff, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        slitok := isslit and (not slitstd) and poff >= 0 and a64_struct_all_scalar(decls, src, stys, styn, a)
        if slitok {
          mut g := ex_struct_lit_args(v)
          mut k := 0
          while g != 0 {
            ga := deref(arg_p(g))
            emit_a64_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  str x0, [x29, #") ; push_int(sb, poff + k * 8) ; push_str(sb, "]\n")
            k += 1
            g = ga.next
          }
        }
        ## a NESTED struct literal (a field is itself a struct/enum — not all-scalar): materialize the full
        ## FLATTENED value directly into p's frame slots by writing each field at its RUNNING byte offset via
        ## the recursive multi-word writer (so a nested struct/enum field lands in full and later fields stay
        ## aligned). Disjoint from slitok (that gate requires all-scalar). Only fires for a real struct decl.
        slitnest := isslit and (not slitstd) and (not slitok) and poff >= 0 and struct_decl_of(decls, src, stys, styn) >= 0
        if slitnest {
          mut sg := ex_struct_lit_args(v)
          mut soff := poff
          while sg != 0 {
            sga := deref(arg_p(sg))
            sw := emit_a64_store_payload_at(sga.e, soff, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            soff = soff + sw * 8
            sg = sga.next
          }
        }
        if isslit and (not slitstd) and (not slitok) and (not slitnest) { push_str(sb, "  brk #0 // unsupported struct construct\n") }
        ## enum construct: store variant discriminant at word 0, then each payload arg at word 1+.
        vidx := variant_index(decls, src, expr_enum_lit_ns(v), expr_enum_lit_nl(v), expr_enum_variant_ns(v), expr_enum_variant_nl(v), a)
        ## enum local construct `s := E.V(p…)`: disc at word 0, then each payload arg via the shared
        ## multi-word writer (scalar / struct / nested-enum / str payloads — §8 piece 3b).
        elitok := iselit and poff >= 0 and vidx >= 0
        if elitok {
          push_str(sb, "  ldr x0, =") ; push_int(sb, vidx) ; push_str(sb, "\n  str x0, [x29, #") ; push_int(sb, poff) ; push_str(sb, "]\n")
          mut eg := ex_enum_lit_args(v)
          mut ewo := 1
          while eg != 0 {
            ega := deref(arg_p(eg))
            ecw := emit_a64_store_payload_at(ega.e, poff + ewo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            ewo = ewo + ecw
            eg = ega.next
          }
        }
        if iselit and (not elitok) { push_str(sb, "  brk #0 // unsupported enum construct\n") }
        ## array construct `a := [e0, …]`: store each element at base + k*estride*8. A SCALAR element
        ## (estride 1) is one word; a STRUCT element (a StructLit) stores each positional field at base +
        ## (k*estride + fk)*8; an ENUM element (an EnumLit) stores the discriminant at (k*estride)*8 then
        ## each payload word at +1,+2,… (the aggregate-array layout — x86's stride).
        alitok := isalit and poff >= 0
        mut alitbyte := false
        if alitok {
          ag0 := ex_array_lit_ehead(v)
          if ag0 != 0 {
            aga0 := deref(arg_p(ag0))
            if expr_is_struct_lit(aga0.e) and std_array_elem_byte_tier(decls, src, expr_struct_lit_ns(aga0.e), expr_struct_lit_nl(aga0.e), a) {
              alitbyte = true
              astrideB := i64(layout_elem_stride_bytes(decls, src, expr_struct_lit_ns(aga0.e), expr_struct_lit_nl(aga0.e), a))
              mut abg := ag0
              mut abo := poff
              while abg != 0 {
                abga := deref(arg_p(abg))
                if expr_is_struct_lit(abga.e) { _abs := a64_std_store_struct(abga.e, abo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
                if not expr_is_struct_lit(abga.e) { push_str(sb, "  brk #0 // mixed byte-tier array literal\n") }
                abo = abo + astrideB
                abg = abga.next
              }
            }
          }
        }
        if alitok and (not alitbyte) {
          estrideA := a64_alit_stride(v, src, a, decls)
          mut ag := ex_array_lit_ehead(v)
          mut ak := 0
          while ag != 0 {
            aga := deref(arg_p(ag))
            ## Use the same recursive payload writer for each word-tier element. Besides scalar fields it
            ## materializes nested array/struct fields (the `Row.arr` setup in the bounded deep-place
            ## fixture) at their full running offsets; the byte-tier branch above remains separate.
            _alitw := emit_a64_store_payload_at(aga.e, poff + ak * estrideA * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            ak += 1
            ag = aga.next
          }
        }
        if isalit and (not alitok) { push_str(sb, "  brk #0 // unsupported array construct\n") }
        ## range-slice binding `s := base[lo..hi]` — store a 2-word {ptr, len} view (word0 = &base[lo] =
        ## x29 + base-array byte-off + lo*8; word1 = hi - lo). Bounds are re-evaluated per use (pure).
        ## Only a scalar frame-array base is supported (`aoff >= 0`); anything else is fail-loud.
        if isslice {
          sbase := ex_slice_base(v)
          bns := ex_var_ns(sbase)
          bnl := ex_var_nl(sbase)
          aoff := a64_local_off(body_head, src, bns, bnl, pcount, a, decls)
          sliceok := poff >= 0 and bnl != 0 and a64_is_array_local(body_head, src, bns, bnl, a) and aoff >= 0
          if sliceok {
            ## word1 = hi - lo
            emit_a64_expr(ex_slice_hi(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  str x0, [sp, #-16]!\n")
            emit_a64_expr(ex_slice_lo(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  mov x1, x0\n  ldr x0, [sp], #16\n  sub x0, x0, x1\n  str x0, [x29, #")
            push_int(sb, poff + 8) ; push_str(sb, "]\n")
            ## word0 = &base[lo] = x29 + aoff + lo*estride*8 (estride = the base array's element words —
            ## 1 for a scalar array, byte-identical `lsl #3`; struct/enum element scales lo by estride*8).
            estrideS := a64_iter_stride(body_head, src, sbase, a, decls)
            emit_a64_expr(ex_slice_lo(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if estrideS == 1 { push_str(sb, "  lsl x0, x0, #3\n") }
            if estrideS != 1 { push_str(sb, "  mov x1, #") ; push_int(sb, estrideS * 8) ; push_str(sb, "\n  mul x0, x0, x1\n") }
            push_str(sb, "  add x0, x0, x29\n  add x0, x0, #")
            push_int(sb, aoff) ; push_str(sb, "\n  str x0, [x29, #")
            push_int(sb, poff) ; push_str(sb, "]\n")
          }
          if not sliceok { push_str(sb, "  brk #0 // unsupported slice binding\n") }
        }
        s = nx
      }
      Stmt::IndexAssign(ibase, iidx, ival, nx) => {
        ## `a[i] = v` for an ARRAY local: value → x0 (pushed), index → x0, element addr = x29 + base +
        ## i*8 (scaled), store.
        bns := ex_var_ns(ibase)
        bnl := ex_var_nl(ibase)
        mut isslice := false
        mut issliceparam := false
        mut sliceparamidx := i64(0) - 1
        if bnl != 0 {
          if is_slice_local(body_head, src, bns, bnl, a) { isslice = true }
          sliceparamidx = param_find(params_head, src, bns, bnl, a)
          if sliceparamidx >= 0 and a64_slice_param_scalar(params_head, src, bns, bnl, a, decls) {
            ## This write form is currently word-tier only. Resolve the active generic T before
            ## checking width; otherwise Slice(u8) would incorrectly receive an 8-byte store.
            pes := a64_slice_param_elem_span(params_head, src, bns, bnl)
            mut pets := pes.s
            mut petn := pes.n
            if A64_SUB_GPL != 0 and streq(src, pets, petn, A64_SUB_GPS, A64_SUB_GPL) { pets = A64_SUB_ITS ; petn = A64_SUB_ITL }
            if pets != 0 and scalar_byte_size(src, pets, petn) == 8 { issliceparam = true }
          }
        }
        isarr := bnl != 0 and a64_is_array_local(body_head, src, bns, bnl, a)
        aoff := a64_local_off(body_head, src, bns, bnl, pcount, a, decls)
        ## `xs[i] = v` — a whole-ELEMENT write into a fixed array of scalar-only STRUCTS (a LOCAL
        ## array-lit or an array GLOBAL). MUST be tested BEFORE the scalar `isarr` path: that path
        ## scales the index by 8 and stores ONE word, which for a multi-word element would land on the
        ## wrong element AND drop every field but the first — a silent miscompile.
        easp := a64_arrname_elem_struct_span(src, bns, bnl, a, decls)
        eaisla := easp.n != 0 and a64_is_array_local(body_head, src, bns, bnl, a)
        eaisga := easp.n != 0 and (not eaisla) and a64_is_array_global(decls, src, bns, bnl)
        ## the RHS must be a struct LITERAL of that type, or a bare Var naming a struct LOCAL (frame copy).
        eaislit := easp.n != 0 and expr_is_struct_lit(ival)
        eavnl := ex_var_nl(ival)
        mut eavoff := i64(0) - 1
        if easp.n != 0 and (not eaislit) and eavnl != 0 {
          if a64_local_struct_nl(body_head, src, ex_var_ns(ival), eavnl, a) != 0 { eavoff = a64_local_off(body_head, src, ex_var_ns(ival), eavnl, pcount, a, decls) }
        }
        eaok := (eaisla or eaisga) and (eaislit or eavoff >= 0) and ((not eaisla) or aoff >= 0)
        mut eabyte := false
        if easp.n != 0 and std_array_elem_byte_tier(decls, src, easp.s, easp.n, a) { eabyte = true }
        ## the DEEP write shape: the base is not a bare array Var (`xs[i].arr[j] = v`), addressed by
        ## composition with a SCALAR one-word leaf. Tried last, after every closed-formula path.
        diaty := a64_place_idx_ty(ibase, body_head, src, a, decls)
        mut deepia := false
        if diaty.n != 0 {
          if ty_is_scalar(diaty.s, diaty.n, decls, src) {
            if a64_place_idx_ok(ibase, body_head, src, params_head, pcount, a, decls) { deepia = true }
          }
        }
        mut deepagg := false
        mut deepagglit := false
        mut deepaggvar := false
        mut inferredagg := false
        if diaty.n != 0 and struct_decl_of(decls, src, diaty.s, diaty.n) >= 0 and struct_plain(decls, src, diaty.s, diaty.n) {
          inferredagg = a64_inferred_local_agg_elem_base(ibase, body_head, src, a, decls)
          mut deepaggadmit := not a64_place_root_inferred_local(ibase, body_head, src, a, decls)
          if inferredagg { deepaggadmit = true }
          if std_struct_is_word_granular(decls, src, diaty.s, diaty.n, a) and a64_place_idx_ok(ibase, body_head, src, params_head, pcount, a, decls) and deepaggadmit {
            deepagg = true
            if expr_is_struct_lit(ival) {
              if streq(src, expr_struct_lit_ns(ival), expr_struct_lit_nl(ival), diaty.s, diaty.n) { deepagglit = true }
            }
            if eavnl != 0 {
              if eavoff < 0 and a64_local_struct_nl(body_head, src, ex_var_ns(ival), eavnl, a) != 0 { eavoff = a64_local_off(body_head, src, ex_var_ns(ival), eavnl, pcount, a, decls) }
              if eavoff >= 0 and streq(src, a64_local_struct_ns(body_head, src, ex_var_ns(ival), eavnl, a), a64_local_struct_nl(body_head, src, ex_var_ns(ival), eavnl, a), diaty.s, diaty.n) { deepaggvar = true }
            }
          }
        }
        ## The new inferred-local admission is deliberately literal-only: aggregate VAR reads/copies
        ## remain the existing fail-loud residual, and the previously admitted non-inferred roots keep
        ## their existing literal/VAR behavior.
        if inferredagg and (not deepagglit) { deepagg = false ; deepaggvar = false }
        stdidxAssignTy := a64_std_idx_path_ty(ibase, body_head, src, a, decls)
        stdidxAssignEl := a64_arrty_elem(src, stdidxAssignTy.s, stdidxAssignTy.n)
        mut stdidxassign := false
        if a64_std_idx_path_ok(ibase, body_head, src, a, decls) and stdidxAssignEl.n != 0 and scalar_byte_size(src, stdidxAssignEl.s, stdidxAssignEl.n) == 1 { stdidxassign = true }
        if stdidxassign {
          ## `xs[i].data[j] = v`: evaluate the value and the inner byte index before composing the
          ## outer byte-tier element address; both are kept on the stack across the outer index emit.
          emit_a64_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_place_idx_addr(a64_std_idx_root_arr(ibase), a64_std_idx_root_idx(ibase), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          siboA := a64_std_idx_path_bo(ibase, body_head, src, a, decls)
          if siboA != 0 { push_str(sb, "  add x0, x0, #") ; push_int(sb, siboA) ; push_str(sb, "\n") }
          push_str(sb, "  ldr x1, [sp], #16\n")
          if A64_CHK {
            snelA := arrty_nel(src, stdidxAssignTy.s, stdidxAssignTy.n)
            if snelA > 0 { push_str(sb, "  mov x2, #") ; push_int(sb, snelA) ; push_str(sb, "\n  cmp x1, x2\n  b.lo 1f\n  brk #0\n1:\n") }
          }
          push_str(sb, "  add x0, x0, x1\n  ldr x2, [sp], #16\n  strb w2, [x0]\n")
        }
        else if eaok {
          eaw := i64(struct_words(decls, src, easp.s, easp.n, a))
          mut eanel := 0
          if eaisla { eanel = a64_array_nel(body_head, src, bns, bnl, a) }
          if eaisga { eanel = a64_alit_nel(a64_global_value(decls, src, bns, bnl)) }
          ## element ADDRESS once → kept on the stack (each field emit clobbers the scratch registers).
          emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if A64_CHK {
            if eanel > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, eanel) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
          }
          mut estrideB := eaw * 8
          if eabyte { estrideB = i64(layout_elem_stride_bytes(decls, src, easp.s, easp.n, a)) }
          push_str(sb, "  mov x1, #") ; push_int(sb, estrideB) ; push_str(sb, "\n  mul x0, x0, x1\n")
          if eaisla { push_str(sb, "  add x0, x0, x29\n  add x0, x0, #") ; push_int(sb, aoff) ; push_str(sb, "\n") }
          if eaisga {
            eagn := str_at((src + bns), bnl)
            push_str(sb, "  adrp x2, ") ; push_str(sb, eagn) ; push_str(sb, "\n  add x2, x2, :lo12:") ; push_str(sb, eagn) ; push_str(sb, "\n  add x0, x0, x2\n")
          }
          push_str(sb, "  str x0, [sp, #-16]!\n")
          if eaislit and eabyte { _stdp := a64_std_store_struct_atptr(ival, 0, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if eaislit and (not eabyte) {
            ## each field at its RUNNING byte offset through the pointer-relative multi-word writer, so a
            ## NESTED struct / `[T; N]` field of the element literal lands in FULL and the fields after it
            ## stay aligned. Byte-identical to the old one-word-per-argument store for an all-scalar element.
            mut efg := ex_struct_lit_args(ival)
            mut efo := i64(0)
            while efg != 0 {
              efa := deref(arg_p(efg))
              efw := emit_a64_store_payload_atptr(efa.e, efo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
              efo = efo + efw * 8
              efg = efa.next
            }
          }
          if (not eaislit) and eabyte {
            nbp := i64(std_copy_image_bytes(decls, src, easp.s, easp.n, a))
            mut ebk := i64(0)
            while ebk < nbp {
              push_str(sb, "  ldrb w0, [x29, #") ; push_int(sb, eavoff + ebk) ; push_str(sb, "]\n  ldr x1, [sp]\n  strb w0, [x1, #") ; push_int(sb, ebk) ; push_str(sb, "]\n")
              ebk = ebk + 1
            }
          }
          if (not eaislit) and (not eabyte) {
            mut evk := i64(0)
            while evk < eaw {
              push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, eavoff + evk * 8) ; push_str(sb, "]\n  ldr x1, [sp]\n  str x0, [x1, #") ; push_int(sb, evk * 8) ; push_str(sb, "]\n")
              evk = evk + 1
            }
          }
          push_str(sb, "  add sp, sp, #16\n")
        }
        else if easp.n != 0 { push_str(sb, "  brk #0 // unsupported aggregate array-element assign\n") }
        else if isslice and aoff >= 0 {
          ## `s[i] = v` through a range-slice VIEW: store v at ptr (word0) + i*8. Bounds vs the runtime
          ## len (word1 at aoff+8) with x9 scratch (x0=index, x1=value, x2=ptr are live). Dropped under
          ## `unchecked`. Writing through the view mutates the backing array (x86 parity).
          emit_a64_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if A64_CHK {
            push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, aoff + 8) ; push_str(sb, "]\n  cmp x0, x9\n  b.lo 1f\n  brk #0\n1:\n")
          }
          push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, aoff) ; push_str(sb, "]\n")
          push_str(sb, "  ldr x1, [sp], #16\n  str x1, [x2, x0, lsl #3]\n")
        }
        else if issliceparam {
          ## `s[i] = v` through a scalar Slice(T) PARAM: the parameter slot points at the caller's
          ## `{ptr,len}` block, so load the length and data pointer through it before storing.
          emit_a64_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if A64_CHK {
            push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, 16 + sliceparamidx * 8) ; push_str(sb, "]\n  ldr x9, [x9, #8]\n  cmp x0, x9\n  b.lo 1f\n  brk #0\n1:\n")
          }
          push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, 16 + sliceparamidx * 8) ; push_str(sb, "]\n  ldr x2, [x2]\n")
          push_str(sb, "  ldr x1, [sp], #16\n  str x1, [x2, x0, lsl #3]\n")
        }
        else if isarr and aoff >= 0 {
          emit_a64_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  add x2, x29, #") ; push_int(sb, aoff) ; push_str(sb, "\n")
          push_str(sb, "  ldr x1, [sp], #16\n  str x1, [x2, x0, lsl #3]\n")
        }
        else if bnl != 0 and a64_is_array_global(decls, src, bns, bnl) {
          ## `TABLE[i] = v` on an ARRAY GLOBAL: store v at LABEL + i*8 (value pushed, index → x0, base
          ## label → x2). Bounds vs the static element count (dropped under `unchecked`).
          emit_a64_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if A64_CHK {
            gnelW := i64(a64_alit_nel(a64_global_value(decls, src, bns, bnl)))
            if gnelW > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, gnelW) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
          }
          gcn := str_at((src + bns), bnl)
          push_str(sb, "  adrp x2, ") ; push_str(sb, gcn) ; push_str(sb, "\n  add x2, x2, :lo12:") ; push_str(sb, gcn) ; push_str(sb, "\n  ldr x1, [sp], #16\n  str x1, [x2, x0, lsl #3]\n")
        }
        else if deepagg {
          ## `xs[i].arr[j] = P(...)` — the bounded aggregate-leaf path. The destination address is kept on
          ## the stack while a literal's fields or a source aggregate address is evaluated; exactly the P
          ## word image is then written, never the first word alone.
          eaw := i64(struct_words(decls, src, diaty.s, diaty.n, a))
          if deepagglit {
            emit_a64_place_idx_addr(ibase, iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  str x0, [sp, #-16]!\n")
            mut efg := ex_struct_lit_args(ival)
            mut efo := i64(0)
            while efg != 0 {
              efa := deref(arg_p(efg))
              efw := emit_a64_store_payload_atptr(efa.e, efo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
              efo = efo + efw * 8
              efg = efa.next
            }
            push_str(sb, "  add sp, sp, #16\n")
          }
          if deepaggvar {
            emit_a64_place_idx_addr(ibase, iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  str x0, [sp, #-16]!\n")
            push_str(sb, "  add x0, x29, #") ; push_int(sb, eavoff) ; push_str(sb, "\n")
            push_str(sb, "  str x0, [sp, #-16]!\n")
            mut evk := i64(0)
            while evk < eaw {
              push_str(sb, "  ldr x1, [sp]\n  ldr x0, [sp, #16]\n  ldr x2, [x1, #") ; push_int(sb, evk * 8) ; push_str(sb, "]\n  str x2, [x0, #") ; push_int(sb, evk * 8) ; push_str(sb, "]\n")
              evk = evk + 1
            }
            push_str(sb, "  add sp, sp, #32\n")
          }
          if (not deepagglit) and (not deepaggvar) { push_str(sb, "  brk #0 // unsupported deep aggregate RHS\n") }
        }
        else if deepia {
          ## `xs[i].arr[j] = v` — a DEEP element WRITE (the base is a FIELD, not a bare Var, so no closed
          ## frame formula exists). Value → x0 and PUSHED first: the address composition below evaluates
          ## the index and clobbers every scratch register. The composition is stack-BALANCED, so the
          ## pushed value is still at `[sp]` when the address lands in x0.
          emit_a64_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_place_idx_addr(ibase, iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  ldr x1, [sp], #16\n  str x1, [x0]\n")
        }
        else { push_str(sb, "  brk #0 // unsupported index assign\n") }
        s = nx
      }
      ## `xs[i].f = e` — a scalar FIELD write into an ELEMENT of a fixed array of scalar-only structs
      ## (a LOCAL array-lit or an array GLOBAL): the WRITE dual of the `xs[i].f` read. Evaluate the value
      ## → x0 and PUSH it (the index expr clobbers every scratch register), form the element base in x2,
      ## then store the popped value at (element base + woff*8). Bounds vs the STATIC element count
      ## (dropped under `unchecked`, CG-7). Any other shape stays fail-loud.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => {
        fins := ex_var_ns(ifb)
        finl := ex_var_nl(ifb)
        fesp := a64_arrname_elem_struct_span(src, fins, finl, a, decls)
        fla := fesp.n != 0 and a64_is_array_local(body_head, src, fins, finl, a)
        fga := fesp.n != 0 and (not fla) and a64_is_array_global(decls, src, fins, finl)
        faoff := a64_local_off(body_head, src, fins, finl, pcount, a, decls)
        ## THIS FIELD must be SCALAR — an element struct may now carry a nested aggregate field, and a
        ## one-word `str` at its offset would silently write only its word 0 (leaving the rest stale).
        ffscal := fesp.n != 0 and a64_field_is_scalar(decls, src, fesp.s, fesp.n, iffs, iffl, a)
        ifok := ffscal and ((fla and faoff >= 0) or fga)
        mut fbyte := false
        if fesp.n != 0 and std_array_elem_byte_tier(decls, src, fesp.s, fesp.n, a) { fbyte = true }
        if ifok {
          fstr := i64(struct_words(decls, src, fesp.s, fesp.n, a))
          fwof := field_word_offset(decls, src, fesp.s, fesp.n, iffs, iffl, a)
          mut fstrb := fstr * 8
          mut fwoffb := fwof * 8
          if fbyte { fstrb = i64(layout_elem_stride_bytes(decls, src, fesp.s, fesp.n, a)) ; fwoffb = layout_field_offset_bytes(decls, src, fesp.s, fesp.n, iffs, iffl, a) }
          mut fnel := 0
          if fla { fnel = a64_array_nel(body_head, src, fins, finl, a) }
          if fga { fnel = a64_alit_nel(a64_global_value(decls, src, fins, finl)) }
          emit_a64_expr(ifv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_expr(ifi, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if A64_CHK {
            if fnel > 0 { push_str(sb, "  mov x1, #") ; push_int(sb, fnel) ; push_str(sb, "\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
          }
          push_str(sb, "  mov x1, #") ; push_int(sb, fstrb) ; push_str(sb, "\n  mul x0, x0, x1\n")
          if fla { push_str(sb, "  add x2, x0, x29\n  add x2, x2, #") ; push_int(sb, faoff) ; push_str(sb, "\n") }
          if fga {
            fgn := str_at((src + fins), finl)
            push_str(sb, "  adrp x2, ") ; push_str(sb, fgn) ; push_str(sb, "\n  add x2, x2, :lo12:") ; push_str(sb, fgn) ; push_str(sb, "\n  add x2, x2, x0\n")
          }
          push_str(sb, "  ldr x0, [sp], #16\n")
          if fbyte {
            ftf := field_type_span(decls, src, fesp.s, fesp.n, iffs, iffl, a)
            fwf := scalar_byte_size(src, ftf.s, ftf.n)
            if fwf == 1 { push_str(sb, "  strb w0, [x2, #") ; push_int(sb, fwoffb) ; push_str(sb, "]\n") }
            if fwf == 2 { push_str(sb, "  strh w0, [x2, #") ; push_int(sb, fwoffb) ; push_str(sb, "]\n") }
            if fwf == 4 { push_str(sb, "  str w0, [x2, #") ; push_int(sb, fwoffb) ; push_str(sb, "]\n") }
            if fwf == 8 { push_str(sb, "  str x0, [x2, #") ; push_int(sb, fwoffb) ; push_str(sb, "]\n") }
          }
          if not fbyte { push_str(sb, "  str x0, [x2, #") ; push_int(sb, fwoffb) ; push_str(sb, "]\n") }
        }
        ## `b.cells[i].m = v` — the DEEP dual: the indexed base is an inline `[Struct; N]` FIELD (or any
        ## composable place), so the element address is COMPOSED and the scalar field stored at its word
        ## offset within the element. Value evaluated and PUSHED first (the composition clobbers scratch).
        difty := a64_place_idx_ty(ifb, body_head, src, a, decls)
        mut deepif := false
        if (not ifok) and difty.n != 0 {
          if struct_decl_of(decls, src, difty.s, difty.n) >= 0 {
            if a64_field_is_scalar(decls, src, difty.s, difty.n, iffs, iffl, a) {
              if a64_place_idx_ok(ifb, body_head, src, params_head, pcount, a, decls) { deepif = true }
            }
          }
        }
        if deepif {
          mut dwof := i64(field_word_offset(decls, src, difty.s, difty.n, iffs, iffl, a)) * 8
          if layout_kind_is_byte(layout_kind(decls, src, difty.s, difty.n, a)) { dwof = layout_field_offset_bytes(decls, src, difty.s, difty.n, iffs, iffl, a) }
          emit_a64_expr(ifv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_place_idx_addr(ifb, ifi, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  ldr x1, [sp], #16\n")
          if layout_kind_is_byte(layout_kind(decls, src, difty.s, difty.n, a)) {
            dft := field_type_span(decls, src, difty.s, difty.n, iffs, iffl, a)
            dfw := scalar_byte_size(src, dft.s, dft.n)
            if dfw == 1 { push_str(sb, "  strb w1, [x0, #") ; push_int(sb, dwof) ; push_str(sb, "]\n") }
            if dfw == 2 { push_str(sb, "  strh w1, [x0, #") ; push_int(sb, dwof) ; push_str(sb, "]\n") }
            if dfw == 4 { push_str(sb, "  str w1, [x0, #") ; push_int(sb, dwof) ; push_str(sb, "]\n") }
            if dfw == 8 { push_str(sb, "  str x1, [x0, #") ; push_int(sb, dwof) ; push_str(sb, "]\n") }
          }
          if not layout_kind_is_byte(layout_kind(decls, src, difty.s, difty.n, a)) { push_str(sb, "  str x1, [x0, #") ; push_int(sb, dwof) ; push_str(sb, "]\n") }
        }
        if (not ifok) and (not deepif) { push_str(sb, "  brk #0 // unsupported array-element field assign\n") }
        s = ifnx
      }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => {
        ## `p.f = v` for a struct LOCAL p: evaluate v → x0, store at (p base + field word offset). Gate on
        ## THIS FIELD being scalar (not the whole struct all-scalar) — mirroring the Field-READ localok fix —
        ## so a scalar field of a struct that ALSO has an aggregate field (`c.z` where `C = { b : B, z }`)
        ## stores at its layout word offset (which already accounts for the wide nested field).
        stys := a64_local_struct_ns(body_head, src, bns, bnl, a)
        styn := a64_local_struct_nl(body_head, src, bns, bnl, a)
        poff := a64_local_off(body_head, src, bns, bnl, pcount, a, decls)
        mut stdhandled := false
        if styn != 0 and poff >= 0 and layout_kind_is_byte(layout_kind(decls, src, stys, styn, a)) {
          sbo := standard_field_byte_offset(decls, src, stys, styn, fns, fnl, a)
          sft := field_type_span(decls, src, stys, styn, fns, fnl, a)
          if sbo >= 0 and sft.n != 0 {
            if std_ty_aggregate(sft.s, sft.n, decls, src) {
              if expr_is_struct_lit(fv) { _stdw := a64_std_store_struct(fv, poff + sbo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if not expr_is_struct_lit(fv) { push_str(sb, "  brk #0 // unsupported standard aggregate field assign\n") }
              stdhandled = true
            }
            if not std_ty_aggregate(sft.s, sft.n, decls, src) {
              emit_a64_expr(fv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
              a64_std_store_scalar(poff + sbo, scalar_byte_size(src, sft.s, sft.n), sb)
              stdhandled = true
            }
          }
        }
        if not stdhandled { emit_a64_expr(fv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        ok := (not stdhandled) and styn != 0 and poff >= 0 and a64_field_is_scalar(decls, src, stys, styn, fns, fnl, a)
        if ok {
          woff := field_word_offset(decls, src, stys, styn, fns, fnl, a)
          push_str(sb, "  str x0, [x29, #") ; push_int(sb, poff + woff * 8) ; push_str(sb, "]\n")
        }
        ## `q.f = v` for a struct PARAM q (by-reference: `in out q : Box(T)` / a by-value struct param) —
        ## the param slot holds the base ADDRESS, so store v at `[base + field word offset]`. Mirrors the
        ## Field-READ paramok path; resolves the generic-struct param type via a64_param_struct_ns/nl.
        pidxFA := param_find(params_head, src, bns, bnl, a)
        pstys := a64_param_struct_ns(params_head, src, bns, bnl, a, decls)
        pstyn := a64_param_struct_nl(params_head, src, bns, bnl, a, decls)
        paramok := (not ok) and pidxFA >= 0 and pstyn != 0 and a64_struct_all_scalar(decls, src, pstys, pstyn, a)
        if paramok {
          woffP := field_word_offset(decls, src, pstys, pstyn, fns, fnl, a)
          push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, 16 + pidxFA * 8) ; push_str(sb, "]\n  str x0, [x2, #") ; push_int(sb, woffP * 8) ; push_str(sb, "]\n")
        }
        ## `G.f = v` for a struct GLOBAL G: store x0 at LABEL + field word offset. gv is the global's
        ## struct-lit init; the field must be scalar (a whole-aggregate field write is the FieldPathAssign /
        ## deferred path). Disjoint from the local path (a global has no frame slot → poff < 0 → ok false).
        gv := a64_global_value(decls, src, bns, bnl)
        mut gok := false
        if unchecked bitcast(usize, gv) != 0 { if expr_is_struct_lit(gv) {
          gstys := expr_struct_lit_ns(gv)
          gstyn := expr_struct_lit_nl(gv)
          gfts := field_type_span(decls, src, gstys, gstyn, fns, fnl, a)
          if ty_is_scalar(gfts.s, gfts.n, decls, src) {
            gwoff := field_word_offset(decls, src, gstys, gstyn, fns, fnl, a)
            if gwoff >= 0 {
              gok = true
              gcn := str_at((src + bns), bnl)
              push_str(sb, "  adrp x9, ") ; push_str(sb, gcn) ; push_str(sb, "\n  add x9, x9, :lo12:") ; push_str(sb, gcn) ; push_str(sb, "\n  str x0, [x9, #") ; push_int(sb, gwoff * 8) ; push_str(sb, "]\n")
            }
          }
        } }
        if (not stdhandled) and (not ok) and (not gok) and (not paramok) { push_str(sb, "  brk #0 // unsupported field assign\n") }
        s = nx
      }
      ## `G.a.b.c = v` — a nested scalar-field WRITE of a struct GLOBAL at ANY depth. `place` is the field
      ## chain expr; resolve the cumulative `.data` word offset (nested structs flattened) and store x0.
      Stmt::FieldPathAssign(place, fpv, nx) => {
        emit_a64_expr(fpv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        gtype := a64_gchain_type(place, decls, src, a)
        gwoff := a64_gchain_woff(place, decls, src, a)
        groot := a64_gchain_root(place)
        gpok := gwoff >= 0 and gtype.n != 0 and ty_is_scalar(gtype.s, gtype.n, decls, src)
        if gpok {
          gcn := str_at((src + groot.s), groot.n)
          push_str(sb, "  adrp x9, ") ; push_str(sb, gcn) ; push_str(sb, "\n  add x9, x9, :lo12:") ; push_str(sb, gcn) ; push_str(sb, "\n  str x0, [x9, #") ; push_int(sb, gwoff * 8) ; push_str(sb, "]\n")
        }
        ## `c.v.a = e` — the LOCAL dual: a nested scalar-field WRITE of a struct LOCAL at ANY depth. Resolve
        ## the cumulative frame WORD offset (nested structs flattened) through the chain rooted at a struct
        ## local and store x0 at (root frame base + off*8). Disjoint from gpok (a global has no frame slot →
        ## lrootoff < 0; a local has no global initializer → gtype.n == 0).
        stdft := a64_std_path_ty(place, body_head, src, a, decls)
        stdfpok := a64_std_path_ok(place, body_head, src, a, decls) and stdft.n != 0 and (not std_ty_aggregate(stdft.s, stdft.n, decls, src))
        if stdfpok {
          sroot := a64_std_path_root_off(place, body_head, src, pcount, a, decls)
          sbo := a64_std_path_bo(place, body_head, src, a, decls)
          a64_std_store_scalar(sroot + sbo, scalar_byte_size(src, stdft.s, stdft.n), sb)
        }
        lroot := a64_gchain_root(place)
        ltype := a64_lchain_type(place, body_head, src, a, decls)
        lwoff := a64_lchain_woff(place, body_head, src, a, decls)
        lrootoff := a64_local_off(body_head, src, lroot.s, lroot.n, pcount, a, decls)
        lpok := (not stdfpok) and lwoff >= 0 and lrootoff >= 0 and ltype.n != 0 and ty_is_scalar(ltype.s, ltype.n, decls, src)
        if lpok { push_str(sb, "  str x0, [x29, #") ; push_int(sb, lrootoff + lwoff * 8) ; push_str(sb, "]\n") }
        ## `xs[i].b.c.cx = v` — the DEEP dual: the chain is rooted at an array ELEMENT (a RUNTIME address),
        ## so no cumulative frame offset exists. The value is already in x0 — PUSH it, compose the leaf
        ## address (that emit clobbers every scratch register), pop the value and store one word.
        mut deepfp := false
        if (not stdfpok) and (not gpok) and (not lpok) {
          if a64_deep_scalar_ok(place, body_head, src, params_head, pcount, a, decls) { deepfp = true }
        }
        if deepfp {
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_place_addr(place, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  ldr x1, [sp], #16\n")
          if a64_std_idx_path_ok(place, body_head, src, a, decls) {
            ptyb := a64_std_idx_path_ty(place, body_head, src, a, decls)
            pwb := scalar_byte_size(src, ptyb.s, ptyb.n)
            if pwb == 1 { push_str(sb, "  strb w1, [x0]\n") }
            if pwb == 2 { push_str(sb, "  strh w1, [x0]\n") }
            if pwb == 4 { push_str(sb, "  str w1, [x0]\n") }
            if pwb == 8 { push_str(sb, "  str x1, [x0]\n") }
          }
          if not a64_std_idx_path_ok(place, body_head, src, a, decls) { push_str(sb, "  str x1, [x0]\n") }
        }
        if (not stdfpok) and (not gpok) and (not lpok) and (not deepfp) { push_str(sb, "  brk #0 // unsupported field-path assign\n") }
        s = nx
      }
      Stmt::Return(rv, nx) => {
        ## a struct-returning fn (§8 piece 2) or enum-returning fn (§8 piece 3) delivers the value via the
        ## register convention (word k → x_k); a scalar/float fn uses the ordinary value emit.
        if A64_RET_BYTE_N >= 1 { emit_a64_byte_array_value(rv, sb, A64_RET_BYTE_N, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        if A64_RET_SRET_NL != 0 { emit_a64_sret_store(rv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        if A64_RET_STRUCT_NL != 0 { emit_a64_struct_value(rv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        if A64_RET_ENUM_NL != 0 { emit_a64_enum_value(rv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        if A64_RET_BYTE_N == 0 and A64_RET_STRUCT_NL == 0 and A64_RET_ENUM_NL == 0 and A64_RET_SRET_NL == 0 { emit_a64_expr(rv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        emit_a64_epilogue(frame, sb)
        s = nx
      }
      Stmt::While(c, b, nx) => {
        id := a64_next_label()
        ob := A64_BRK
        oc := A64_CONT
        A64_BRK = id
        A64_CONT = id
        push_str(sb, ".Lwtop") ; push_int(sb, id) ; push_str(sb, ":\n")
        emit_a64_expr(c, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  cbz x0, .Lwend") ; push_int(sb, id) ; push_str(sb, "\n")
        emit_a64_stmts(b, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        ## `continue` target: re-enter the guard (re-evaluate the condition).
        push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
        push_str(sb, "  b .Lwtop") ; push_int(sb, id) ; push_str(sb, "\n")
        push_str(sb, ".Lwend") ; push_int(sb, id) ; push_str(sb, ":\n")
        ## `break` target (fall-through exit).
        push_str(sb, ".Lbrk") ; push_int(sb, id) ; push_str(sb, ":\n")
        A64_BRK = ob
        A64_CONT = oc
        s = nx
      }
      Stmt::If(c, th, el, nx) => {
        id := a64_next_label()
        emit_a64_expr(c, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  cbz x0, .Lielse") ; push_int(sb, id) ; push_str(sb, "\n")
        emit_a64_stmts(th, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        push_str(sb, "  b .Liend") ; push_int(sb, id) ; push_str(sb, "\n")
        push_str(sb, ".Lielse") ; push_int(sb, id) ; push_str(sb, ":\n")
        emit_a64_stmts(el, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        push_str(sb, ".Liend") ; push_int(sb, id) ; push_str(sb, ":\n")
        s = nx
      }
      Stmt::ExprStmt(e, nx) => {
        emit_a64_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        s = nx
      }
      Stmt::Match(scrut, arms, nx) => {
        ## statement / tail value-match: dispatch on the enum LOCAL's discriminant (result in x0 — for
        ## a value-returning fn whose body ends in `match e {…}` this yields the fn value).
        sns := ex_var_ns(scrut)
        snl := ex_var_nl(scrut)
        ens := a64_local_enum_ns(body_head, src, sns, snl, a)
        enl := a64_local_enum_nl(body_head, src, sns, snl, a)
        eoff := a64_local_off(body_head, src, sns, snl, pcount, a, decls)
        endid := a64_next_label()
        ## `match s[i]` on an enum `Slice(E)` PARAM: the element is by-reference (param-slot deref data ptr
        ## + i*stride*8). Materialize its enum words (disc+payload) into the reserved A64_MTMP region, then
        ## match on that frame offset (emit_a64_match_arms reads `[x29, eoff]` + payload binds off eoff).
        mut idxmatch := false
        if ex_is_index(scrut) {
          ib := ex_index_base(scrut)
          ins := ex_var_ns(ib)
          inl := ex_var_nl(ib)
          ipidx := param_find(params_head, src, ins, inl, a)
          ees := a64_slice_param_enum_span(params_head, src, ins, inl, decls)
          if ipidx >= 0 and ees.n != 0 {
            idxmatch = true
            stride := a64_slice_param_agg_stride(params_head, src, ins, inl, a, decls)
            pslot := 16 + ipidx * 8
            emit_a64_expr(ex_index_idx(scrut), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if A64_CHK { push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslot) ; push_str(sb, "]\n  ldr x1, [x3, #8]\n  cmp x0, x1\n  b.lo 1f\n  brk #0\n1:\n") }
            push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslot) ; push_str(sb, "]\n  ldr x2, [x3]\n  mov x1, #") ; push_int(sb, stride * 8) ; push_str(sb, "\n  mul x0, x0, x1\n  add x2, x2, x0\n")
            mut ck := 0
            while ck < stride {
              push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, ck * 8) ; push_str(sb, "]\n  str x0, [x29, #") ; push_int(sb, A64_MTMP + ck * 8) ; push_str(sb, "]\n")
              ck = ck + 1
            }
            emit_a64_match_arms(arms, ees.s, ees.n, A64_MTMP, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
            push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
          }
        }
        ok := (not idxmatch) and snl != 0 and enl != 0 and eoff >= 0
        ## a `match <enum PARAM>` (§8 piece 3): materialize the by-reference {disc,payload…} block into
        ## A64_MTMP, then match on that offset (with the real `frame` for statement-body arms / Return).
        pidxM := param_find(params_head, src, sns, snl, a)
        penlM := a64_param_enum_nl(params_head, src, sns, snl, decls)
        paramok := (not idxmatch) and (not ok) and pidxM >= 0 and penlM != 0
        ## a nested `match <enum payload BINDING>` (§8 piece 3b): the binding is an enum at frame offset
        ## `bind_base + 8` — match directly there (`X(i) => { match i { … } }`).
        bagg := a64_bind_agg_span(bind_head, src, sns, snl, a, decls)
        bindok := (not idxmatch) and (not ok) and (not paramok) and bagg.n != 0 and enum_decl_of(decls, src, bagg.s, bagg.n) >= 0
        if ok {
          ## statement position: pass the real `frame` so a statement-body arm's stmts (and any Return)
          ## lower correctly.
          emit_a64_match_arms(arms, ens, enl, eoff, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
        if paramok {
          pensM := a64_param_enum_ns(params_head, src, sns, snl, decls)
          wM := 1 + i64(enum_max_arity(decls, src, pensM, penlM, a))
          push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, 16 + pidxM * 8) ; push_str(sb, "]\n")
          mut km := 0
          while km < wM { push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, km * 8) ; push_str(sb, "]\n  str x0, [x29, #") ; push_int(sb, A64_MTMP + km * 8) ; push_str(sb, "]\n") ; km = km + 1 }
          emit_a64_match_arms(arms, pensM, penlM, A64_MTMP, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
        if bindok {
          emit_a64_match_arms(arms, bagg.s, bagg.n, bind_base + 8, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
        mut scalar_shape := true
        mut scalar_arm := arms
        while scalar_arm != 0 {
          sam := deref(arm_p(scalar_arm))
          if sam.wild != 1 and (sam.wild != 0 or sam.vs != 0 or sam.vl != 0) { scalar_shape = false }
          scalar_arm = sam.next
        }
        if (not ok) and (not idxmatch) and (not paramok) and (not bindok) and scalar_shape {
          emit_a64_expr(scrut, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          emit_a64_scalar_match_arms(arms, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
        if (not ok) and (not idxmatch) and (not paramok) and (not bindok) and (not scalar_shape) { push_str(sb, "  brk #0 // unsupported match statement\n") }
        s = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        ## RANGE `for i in lo..hi { … }`: `i` lives at its frame slot (a64_local_off). i := lo; loop while
        ## i < hi (SIGNED, x86 parity via setl); body; i += 1; back-edge.
        if unchecked bitcast(usize, fhi) == 0 {
          ## ITERABLE `for x in <arr/slice-view> { … }`: `x` binds each ELEMENT. `x` lives at its frame slot
          ## (voff); a hidden index rides the NEXT reserved word (voff+8 — the local scan reserves TWO words
          ## for an iterable For). Bound: an INLINE scalar/float array (elements at x29+aoff+i*8, static count)
          ## or a scalar slice VIEW (word0 = data ptr @ aoff, word1 = runtime len @ aoff+8; element at
          ## ptr+i*8). Element word is copied BY VALUE (a float rides its bits). Anything else (slice PARAM /
          ## Vec / non-var) traps loud. `__i = 0; while __i < len { x = elem[__i] ; body ; __i += 1 }`.
          bns := ex_var_ns(flo)
          bnl := ex_var_nl(flo)
          voff := a64_local_off(body_head, src, fns, fnl, pcount, a, decls)
          ioff := voff + 8
          aoff := a64_local_off(body_head, src, bns, bnl, pcount, a, decls)
          mut isslice := false
          if bnl != 0 { if is_slice_local(body_head, src, bns, bnl, a) { isslice = true } }
          mut isarr := false
          if (not isslice) and bnl != 0 { if a64_is_array_local(body_head, src, bns, bnl, a) { isarr = true } }
          pidxF := param_find(params_head, src, bns, bnl, a)
          ## `for x in s` over a scalar `Slice(E)` PARAM: the param slot holds a POINTER to the caller's
          ## `{ptr,len}` block, so len = `[blk+8]` and data ptr = `[blk]` (a DOUBLE deref) — one extra load
          ## versus the inline local VIEW. Not a local, so `aoff` is -1; gate on the param slot instead.
          mut isparamslice := false
          if (not isslice) and (not isarr) and pidxF >= 0 { if a64_slice_param_scalar(params_head, src, bns, bnl, a, decls) { isparamslice = true } }
          ## guard the `16 + pidxF*8` slot offset behind pidxF >= 0 (a param): the frozen seed emits an
          ## UNSIGNED carry check for the `+`, so a negative pidxF (a local base — pidxF == -1) would
          ## spuriously trap the compiler's own checked add. Same idiom as the Var/Assign param-slot compute.
          mut pslotF := 0
          if pidxF >= 0 { pslotF = 16 + pidxF * 8 }
          nel := a64_array_nel(body_head, src, bns, bnl, a)
          id := a64_next_label()
          ob := A64_BRK
          oc := A64_CONT
          A64_BRK = id
          A64_CONT = id
          ## AGGREGATE (struct-element) iteration over an ARRAY local or a slice VIEW of one: the loop var
          ## occupies `estrideF` words (its element struct) + a hidden index word at voff+estrideF*8. Each
          ## iteration COPIES the estrideF-word element into the loop var's slots (`p.field` then reads
          ## localok). Element base = ARRAY: x29+aoff + i*estrideF*8; VIEW: [x29,aoff] (word0 ptr) + same.
          estrideF := a64_iter_stride(body_head, src, flo, a, decls)
          mut isaggarr := false
          if isarr and estrideF > 1 { isaggarr = true }
          mut isaggslice := false
          if isslice and estrideF > 1 { isaggslice = true }
          ## a struct/enum-element `Slice(E)` PARAM base: the param slot holds a POINTER to the caller's
          ## `{ptr,len}` block; element base = block.word0 (data ptr) + i*stride*8. `aoff` is -1 (a param
          ## is not a body local), so gate on the param slot, not aoff.
          mut isaggparam := false
          if (not isslice) and (not isarr) and pidxF >= 0 { if a64_slice_param_agg_stride(params_head, src, bns, bnl, a, decls) > 0 { isaggparam = true } }
          mut okfi := false
          if voff >= 0 and ((isslice and not isaggslice) or (isarr and not isaggarr)) and aoff >= 0 { okfi = true }
          if voff >= 0 and isparamslice { okfi = true }
          mut aggdone := false
          canagg := voff >= 0 and (((isaggarr or isaggslice) and aoff >= 0) or isaggparam)
          if canagg {
            aggdone = true
            ioffA := voff + estrideF * 8
            push_str(sb, "  mov x0, #0\n  str x0, [x29, #") ; push_int(sb, ioffA) ; push_str(sb, "]\n")
            push_str(sb, ".Lfitop") ; push_int(sb, id) ; push_str(sb, ":\n")
            push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, ioffA) ; push_str(sb, "]\n")
            ## count (loop bound) → x1: ARRAY = static nel; VIEW = word1 at aoff+8; PARAM = block.word1
            if isaggarr { push_str(sb, "  mov x1, #") ; push_int(sb, nel) ; push_str(sb, "\n") }
            if isaggslice { push_str(sb, "  ldr x1, [x29, #") ; push_int(sb, aoff + 8) ; push_str(sb, "]\n") }
            if isaggparam { push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslotF) ; push_str(sb, "]\n  ldr x1, [x3, #8]\n") }
            push_str(sb, "  cmp x0, x1\n  b.ge .Lfiend") ; push_int(sb, id) ; push_str(sb, "\n")
            ## element base → x2, then x2 += i*estrideF*8
            if isaggarr { push_str(sb, "  add x2, x29, #") ; push_int(sb, aoff) ; push_str(sb, "\n") }
            if isaggslice { push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, aoff) ; push_str(sb, "]\n") }
            if isaggparam { push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslotF) ; push_str(sb, "]\n  ldr x2, [x3]\n") }
            push_str(sb, "  mov x1, #") ; push_int(sb, estrideF * 8) ; push_str(sb, "\n  mul x0, x0, x1\n  add x2, x2, x0\n")
            ## copy estrideF words into the loop var's slots (voff + k*8)
            mut ck := 0
            while ck < estrideF {
              push_str(sb, "  ldr x0, [x2, #") ; push_int(sb, ck * 8) ; push_str(sb, "]\n  str x0, [x29, #") ; push_int(sb, voff + ck * 8) ; push_str(sb, "]\n")
              ck = ck + 1
            }
            emit_a64_stmts(fb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
            push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
            push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, ioffA) ; push_str(sb, "]\n  add x0, x0, #1\n  str x0, [x29, #") ; push_int(sb, ioffA) ; push_str(sb, "]\n")
            push_str(sb, "  b .Lfitop") ; push_int(sb, id) ; push_str(sb, "\n")
            push_str(sb, ".Lfiend") ; push_int(sb, id) ; push_str(sb, ":\n")
          }
          if okfi {
            push_str(sb, "  mov x0, #0\n  str x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n")
            push_str(sb, ".Lfitop") ; push_int(sb, id) ; push_str(sb, ":\n")
            push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n")
            ## len (loop bound) → x1
            if isparamslice { push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslotF) ; push_str(sb, "]\n  ldr x1, [x3, #8]\n") }
            if isslice { push_str(sb, "  ldr x1, [x29, #") ; push_int(sb, aoff + 8) ; push_str(sb, "]\n") }
            if isarr { push_str(sb, "  mov x1, #") ; push_int(sb, nel) ; push_str(sb, "\n") }
            push_str(sb, "  cmp x0, x1\n  b.ge .Lfiend") ; push_int(sb, id) ; push_str(sb, "\n")
            ## data pointer → x2
            if isparamslice { push_str(sb, "  ldr x3, [x29, #") ; push_int(sb, pslotF) ; push_str(sb, "]\n  ldr x2, [x3]\n") }
            if isslice { push_str(sb, "  ldr x2, [x29, #") ; push_int(sb, aoff) ; push_str(sb, "]\n") }
            if isarr { push_str(sb, "  add x2, x29, #") ; push_int(sb, aoff) ; push_str(sb, "\n") }
            push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n  ldr x0, [x2, x0, lsl #3]\n")
            push_str(sb, "  str x0, [x29, #") ; push_int(sb, voff) ; push_str(sb, "]\n")
            emit_a64_stmts(fb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
            push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
            push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n  add x0, x0, #1\n  str x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n")
            push_str(sb, "  b .Lfitop") ; push_int(sb, id) ; push_str(sb, "\n")
            push_str(sb, ".Lfiend") ; push_int(sb, id) ; push_str(sb, ":\n")
          }
          if (not okfi) and (not aggdone) {
            push_str(sb, "  brk #0 // unsupported for-in-iterable\n")
          }
          ## `break` target (fall-through exit) + restore the enclosing loop's break/continue ids.
          push_str(sb, ".Lbrk") ; push_int(sb, id) ; push_str(sb, ":\n")
          A64_BRK = ob
          A64_CONT = oc
        } else {
          ioff := a64_local_off(body_head, src, fns, fnl, pcount, a, decls)
          id := a64_next_label()
          ob := A64_BRK
          oc := A64_CONT
          A64_BRK = id
          A64_CONT = id
          emit_a64_expr(flo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n")
          push_str(sb, ".Lftop") ; push_int(sb, id) ; push_str(sb, ":\n")
          push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n  str x0, [sp, #-16]!\n")
          emit_a64_expr(fhi, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  mov x1, x0\n  ldr x0, [sp], #16\n  cmp x0, x1\n  b.ge .Lfend") ; push_int(sb, id) ; push_str(sb, "\n")
          emit_a64_stmts(fb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
          ## `continue` target: the INCREMENT (so the loop index still advances).
          push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
          push_str(sb, "  ldr x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n  add x0, x0, #1\n  str x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n")
          push_str(sb, "  b .Lftop") ; push_int(sb, id) ; push_str(sb, "\n")
          push_str(sb, ".Lfend") ; push_int(sb, id) ; push_str(sb, ":\n")
          push_str(sb, ".Lbrk") ; push_int(sb, id) ; push_str(sb, ":\n")
          A64_BRK = ob
          A64_CONT = oc
        }
        s = nx
      }
      ## Infinite `loop { body }`: a top label, the body (with `break` → `.Lbrk<id>`, `continue` →
      ## `.Lcont<id>` = the top), an unconditional back-edge, then the exit. `id` from the body handle.
      Stmt::Loop(lb, lnx) => {
        id := a64_next_label()
        ob := A64_BRK
        oc := A64_CONT
        A64_BRK = id
        A64_CONT = id
        push_str(sb, ".Lltop") ; push_int(sb, id) ; push_str(sb, ":\n")
        emit_a64_stmts(lb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
        push_str(sb, "  b .Lltop") ; push_int(sb, id) ; push_str(sb, "\n")
        push_str(sb, ".Lbrk") ; push_int(sb, id) ; push_str(sb, ":\n")
        A64_BRK = ob
        A64_CONT = oc
        s = lnx
      }
      ## `break` → the nearest enclosing loop's exit; `continue` → its continue target. The front end
      ## rejects break/continue outside a loop, so A64_BRK/A64_CONT are real ids inside a loop body.
      ## Only the NEAREST-loop unlabeled form is modelled; a LABELED `break name`/`continue name`
      ## (`_bd`/`_cd != 0`) or a loop-EXPRESSION `break <expr>` (`_bv != 0`, §7.2) fail-loud (`brk #0`)
      ## rather than silently branch to the wrong loop / drop the value.
      Stmt::Break(bv, bd, bnx) => {
        if bd != 0 or unchecked bitcast(usize, bv) != 0 { push_str(sb, "  brk #0\n") }
        else { push_str(sb, "  b .Lbrk") ; push_int(sb, A64_BRK) ; push_str(sb, "\n") }
        s = bnx
      }
      Stmt::Continue(cd, cnx) => {
        if cd != 0 { push_str(sb, "  brk #0\n") }
        else { push_str(sb, "  b .Lcont") ; push_int(sb, A64_CONT) ; push_str(sb, "\n") }
        s = cnx
      }
      ## `unchecked { body }` (Grammar §130 statement form): lower the body with checked verification OFF
      ## (overflow/bounds guards dropped), then restore. Mirrors the `Expr::Unchecked` toggle + x86 lower.
      Stmt::Unchecked(ub, unx) => {
        ov := A64_CHK
        A64_CHK = false
        emit_a64_stmts(ub, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        A64_CHK = ov
        s = unx
      }
      ## `deref(<scalar ptr>) = v` — STORE one word through the pointer (spec MEM-8). Value → x0 (pushed);
      ## pointer → x1; `str x0, [x1]`. SCALAR value only: a struct/enum LITERAL value store is DEFERRED
      ## (multi-word), fail-loud. Mirrors the x86 DerefAssign scalar fast path.
      Stmt::DerefAssign(pe, val, nx) => {
        isslitv := expr_is_struct_lit(val)
        iselitv := expr_is_enum_lit(val)
        isalitv := ex_is_array_lit(val)
        isslicev := ex_is_slice(val)
        if isslitv or iselitv or isalitv or isslicev { push_str(sb, "  brk #0 // unsupported deref-assign (aggregate value)\n") }
        else {
          emit_a64_expr(val, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  str x0, [sp, #-16]!\n")
          emit_a64_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  mov x1, x0\n  ldr x0, [sp], #16\n  str x0, [x1]\n")
        }
        s = nx
      }
      ## `comptime if <cond> { then } else { else }` — fold the condition and emit ONLY the taken branch's
      ## statements (arch/verify predicates). Conforms to the x86 lower: `target.arch == Arch.x86_64` folds
      ## TRUE. An unfoldable condition (a `match typeinfo(T)` — needs the mono context the a64 path lacks)
      ## emits a fail-loud `brk` (never a silent miscompile). No runtime branch: the erased condition
      ## disappears, the taken branch's statements emit inline.
      Stmt::CompIf(cc, th, el, nx) => {
        cv := a64_comp_cond_fold(cc, src)
        if cv == 1 { emit_a64_stmts(th, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base) }
        if cv == 0 { emit_a64_stmts(el, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base) }
        if cv < 0 { push_str(sb, "  brk #0 // comptime-if: unfoldable condition (needs mono context)\n") }
        s = nx
      }
      ## `comptime match typeinfo(T) { <Kind>(_) => …, _ => … }` (§8 mono) — fold on T's KIND inside a
      ## mono INSTANCE (A64_SUB active) and emit ONLY the matching arm's statements (or the `_` arm). An
      ## inner `comptime match <scalar-kind>` (a Scalar arm's body) keys off the SAME instance type — its
      ## scrutinee is ignored (like x86), so a lone `_` arm is chosen when no numeric sub-kind matches.
      ## Mirrors x86 `emit_stmts`' non-payload `Stmt::CompMatch` path (brand-underlying rebind deferred).
      ## Outside an instance (A64_SUB_ITL == 0) it stays a fail-loud `brk` (never a silent miscompile).
      Stmt::CompMatch(cmsc, cmah, cmnx) => {
        if A64_SUB_ITL == 0 { push_str(sb, "  brk #0 // comptime-match: needs mono context\n") }
        else {
          kind := ct_type_kind(A64_SUB_ITS, A64_SUB_ITL, decls, src)
          nkind := ct_scalar_num_kind(A64_SUB_ITS, A64_SUB_ITL, src)
          mut chosen := 0
          mut cwild := 0
          mut carm := cmah
          while carm != 0 {
            cam := deref(arm_p(carm))
            if cam.wild != 0 { cwild = carm }
            else if ct_kind_of_name(src, cam.vs, cam.vl) == kind { chosen = carm }
            else if ct_num_kind_of_name(src, cam.vs, cam.vl) == nkind { chosen = carm }
            carm = cam.next
          }
          if chosen == 0 { chosen = cwild }
          if chosen != 0 {
            cam2 := deref(arm_p(chosen))
            emit_a64_stmts(cam2.body_stmts, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
          }
        }
        s = cmnx
      }
      ## `comptime for i in lo .. hi { body }` — UNROLL at emit time: for each constant k in [lo, hi), store
      ## k into the loop var's frame slot then emit the body (no runtime loop; the control flow is erased).
      ## Bounds are compile-time integer constants (a64_comp_range_bound: literal / module const). Mirrors
      ## the x86 lower's CompForRange numeric unroll. A null hi (the §7.1 pack form) is unsupported here.
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => {
        if unchecked bitcast(usize, rhi) == 0 { push_str(sb, "  brk #0 // comptime-for pack unroll unsupported\n") }
        else {
          ioff := a64_local_off(body_head, src, rvs, rvl, pcount, a, decls)
          if ioff < 0 { push_str(sb, "  brk #0 // comptime-for loop var unresolved\n") }
          else {
            lo := a64_comp_range_bound(rlo, decls, src)
            hi := a64_comp_range_bound(rhi, decls, src)
            if hi - lo > 100000 { push_str(sb, "  brk #0 // comptime-for range exceeds the unroll budget\n") }
            else {
              mut k := lo
              while k < hi {
                push_str(sb, "  ldr x0, =") ; push_int(sb, k) ; push_str(sb, "\n  str x0, [x29, #") ; push_int(sb, ioff) ; push_str(sb, "]\n")
                emit_a64_stmts(rb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
                k = k + 1
              }
            }
          }
        }
        s = nx
      }
      ## `comptime for f in typeinfo(T).fields { body }` (§8 field-derive core) — UNROLL over the concrete
      ## target struct's fields (from the explicit typeinfo argument, or a mono substitution): for each field, bind the comptime loop
      ## context (A64_CF_* = loop-var name / field name / field type) then emit the body once. Inside, a
      ## `v.(f)` (Expr::CompField) resolves to a field READ and `f.type` (an explicit type-arg) to the field
      ## type. Only for a STRUCT target (`.variants` — cisvar 1 — is the match-arm unroll's job; a tuple/array/
      ## unresolved target stays a fail-loud `brk`, never a silent miscompile). Saved/restored (single-level).
      Stmt::CompFor(cvs, cvl, cisvar, cbody, nx) => {
        mut cfdone := false
        mut cts := A64_SUB_ITS
        mut ctl := A64_SUB_ITL
        cia := compfor_iter_arg(src, cvs, cvl)
        if cia.n != 0 {
          cts = cia.s
          ctl = cia.n
          if A64_SUB_GPL != 0 and streq(src, cts, ctl, A64_SUB_GPS, A64_SUB_GPL) { cts = A64_SUB_ITS ; ctl = A64_SUB_ITL }
          else if A64_SUB_GPL2 != 0 and streq(src, cts, ctl, A64_SUB_GPS2, A64_SUB_GPL2) { cts = A64_SUB_ITS2 ; ctl = A64_SUB_ITL2 }
          else if A64_SUB_GPL3 != 0 and streq(src, cts, ctl, A64_SUB_GPS3, A64_SUB_GPL3) { cts = A64_SUB_ITS3 ; ctl = A64_SUB_ITL3 }
        }
        if ctl != 0 and cisvar == 0 {
          bn := base_type_name(src, cts, ctl)
          sdi := struct_decl_of(decls, src, bn.s, bn.n)
          if sdi >= 0 {
            sd := deref(decl_get(decls, usize(sdi)))
            ov_vs := A64_CF_VAR_S ; ov_vl := A64_CF_VAR_L
            ov_fs := A64_CF_FLD_S ; ov_fl := A64_CF_FLD_L
            ov_ts := A64_CF_TY_S ; ov_tl := A64_CF_TY_L
            mut fd := sd.fields_head
            while fd != 0 {
              fdd := deref(fld_p(fd))
              A64_CF_VAR_S = cvs ; A64_CF_VAR_L = cvl
              A64_CF_FLD_S = fdd.ns ; A64_CF_FLD_L = fdd.nl
              A64_CF_TY_S = fdd.ts ; A64_CF_TY_L = fdd.tl
              emit_a64_stmts(cbody, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
              fd = fdd.next
            }
            A64_CF_VAR_S = ov_vs ; A64_CF_VAR_L = ov_vl
            A64_CF_FLD_S = ov_fs ; A64_CF_FLD_L = ov_fl
            A64_CF_TY_S = ov_ts ; A64_CF_TY_L = ov_tl
            cfdone = true
          }
        }
        if not cfdone { push_str(sb, "  brk #0 // comptime-for fields: needs a struct mono instance\n") }
        s = nx
      }
      _ => { push_str(sb, "  brk #0 // unsupported statement\n") ; s = 0 }
    }
  }
}


a64_fn_is_generic := fn(params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena) -> bool {
  mut p := params_head
  mut g := false
  while p != 0 {
    pm := deref(param_p(p))
    tn := str_at((src + pm.ts), pm.tl)
    if tn == "type" { g = true }
    p = pm.next
  }
  g
}

## Is the fn named `[ns, ns+nl)` an `@abi(naked)` fn (spec ch.80)? Source-scan `name := @abi(naked) fn …`
## (mirrors the x86_64 lower's `fn_is_naked`; the marker is arch-agnostic). A naked fn emits its raw body
## with NO prologue/epilogue — its asm() lines are the whole function.
a64_fn_is_naked := fn(src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut p := ns + nl
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return false }
  p += 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  str_at((src + p), 11) == "@abi(naked)"
}

## Emit one function. A GENERIC fn (a `type` param) is a fail-loud `brk #0` (no monomorphization).
## Emit the `@export("sym")` alias for a fn whose name starts at `name_s` (Modules §6.3): a `.global sym`
## directive + a `sym:` label naming the SAME entry, so the linker sees `sym`. No-op when not exported.
emit_a64_export := fn(in out sb : rt::StrBuf, src : ptr(u8), name_s : usize, name_l : usize) {
  exn := export_name(src, name_s, name_l)
  if exn.n != 0 {
    push_str(sb, ".global ") ; push_str(sb, str_at((src + exn.s), exn.n)) ; push_str(sb, "\n")
    push_str(sb, str_at((src + exn.s), exn.n)) ; push_str(sb, ":\n")
  }
}
emit_a64_fn := fn(d : Decl, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), decls : ptr(rt::Vec)) {
  ## an `@extern` fn (Modules §7.2) is a bodyless import — its definition lives elsewhere; emit nothing
  ## (a call to it is routed to the external symbol by `a64_emit_bl_target`). Skipping the body also
  ## avoids a bogus local label colliding with the external symbol at link.
  if extern_symbol(src, d.name_start, d.name_len).n != 0 { return }
  fname := str_at((src + d.name_start), d.name_len)
  isgen := a64_fn_is_generic(d.params_head, src, a)
  ## GENERICS (§8 mono): a generic fn emits NO standalone body — each instance is emitted separately.
  ## In INSTANCE mode (A64_SUB_ITL set by `emit_a64_program`'s mono pass) with a single LEADING type-param,
  ## skip that type-param (its effective value params = `params_head.next`), set the substitution NAME
  ## (`A64_SUB_GPS/GPL`, read by `a64_comp_cond_fold`), and emit `<fn>__<tag>`. A non-instance generic (no
  ## active substitution) keeps the fail-loud stub. `ephead` is the effective (value) param list head.
  A64_SUB_GPS = 0
  A64_SUB_GPL = 0
  A64_SUB_GPS2 = 0
  A64_SUB_GPL2 = 0
  A64_SUB_GPS3 = 0
  A64_SUB_GPL3 = 0
  mut ephead := d.params_head
  mut inst := false
  ## frame-slot index of a NON-LEADING type-param to skip in the spill loop (-1 = none / leading).
  mut a64_tp_skip := i64(0) - 1
  if isgen {
    cnt := decl_tparam_count(d, src)
    lead := decl_leading_tparam_run(d, src)
    ## SUPPORTED: a single type-param (any position), OR a leading RUN of 2..3 type-params (cnt == lead).
    gok := A64_SUB_ITL != 0 and cnt >= 1 and cnt <= 3 and (cnt == lead or cnt == 1)
    if not gok {
      push_str(sb, fname) ; push_str(sb, ":\n  brk #0 // generic fn: monomorphization unsupported\n  ret\n")
      return
    }
    inst = true
    ## LEADING RUN (cnt == lead, 1..3): DROP the run; substitute each type-param NAME → its instance type
    ## (GPS/GPL, GPS2/GPL2, GPS3/GPL3). `ephead` = the first value param after the run. The single-leading
    ## case (cnt==lead==1) is byte-identical to the original. FLAT ifs — this is a very large fn.
    mut pp := d.params_head
    mut li := i64(0)
    while li < lead {
      pm := deref(param_p(pp))
      if li == 0 { A64_SUB_GPS = pm.ns ; A64_SUB_GPL = pm.nl }
      if li == 1 { A64_SUB_GPS2 = pm.ns ; A64_SUB_GPL2 = pm.nl }
      if li == 2 { A64_SUB_GPS3 = pm.ns ; A64_SUB_GPL3 = pm.nl }
      pp = pm.next
      li = li + 1
    }
    if cnt == lead { ephead = pp }
    ## NON-LEADING single type-param (cnt==1, lead==0, `gf(s : P, T : type, k)`): keep the FULL param list
    ## (field/name resolution + frame slots unchanged) but SKIP the type-param's slot in the spill loop.
    if cnt == 1 and lead == 0 {
      tpn := a64_tparam_name(d, src)
      A64_SUB_GPS = tpn.s
      A64_SUB_GPL = tpn.n
      a64_tp_skip = decl_tparam_pos(d, src)
    }
  }
  pcount := count_params(ephead, a)
  ## stash this fn's params so the frame scanners can recognize a slice PARAM base (set BEFORE
  ## a64_count_locals, which sizes an aggregate slice-param loop var via a64_iter_stride).
  A64_PARAMS = unchecked bitcast(usize, ephead)
  A64_DECLS = unchecked bitcast(usize, decls)
  A64_BODY = unchecked bitcast(usize, d.body_stmts)
  nloc := a64_count_locals(d.body_stmts, src, a, decls)
  ## SLICE-ARG agg blocks (§8 slice-param caller): 2 reserved words per slice argument in the body + tail.
  nsargs := a64_slarg_count(d.body_stmts) + a64_slarg_count_e(d.value)
  ## ANONYMOUS AGGREGATE-VALUE args (§8, piece 1): a struct-literal passed by value → its full words,
  ## reserved in the SAME A64_AGG region (above the slice-arg blocks), tree-wide over body + tail.
  naggw := a64_aggval_words(d.body_stmts, src, a, decls) + a64_aggval_words_e(d.value, src, a, decls)
  ## MATCH-over-INDEX temp (§8 enum slice-param): reserve the largest such match's enum words (once per fn).
  mut mtmp := a64_match_tmp_words(d.body_stmts, src, a)
  ## …and the SAME region is written by a `match <enum PARAM>` materialization, which the statement
  ## scanner above never measured (it only knows the match-over-INDEX scrutinee, and it never visits the
  ## trailing VALUE at all). Size it from the PARAM LIST instead — see a64_param_enum_tmp_words.
  pemt := a64_param_enum_tmp_words(ephead, src, decls, a)
  if pemt > mtmp { mtmp = pemt }
  ## WIDE-STRUCT SRET (§8 piece 2b): a fn returning a plain struct of > 8 words reserves ONE extra frame
  ## word ABOVE everything to spill the incoming x8 (indirect result pointer). Computed from the DECLARED
  ## return type (a generic `T` return is not a plain struct here → 0, so generic SRET stays trapping),
  ## keeping the reservation consistent with the A64_RET_SRET detection below. 0 for every non-SRET fn →
  ## the frame + all offsets stay byte-identical (this whole path is a64-only; the x86 self-build is neutral).
  sretbn := base_type_name(src, d.ret_ts, d.ret_tl)
  mut sret_extra := 0
  if sretbn.n != 0 and a64_ret_sret_words(decls, src, sretbn.s, sretbn.n, a) >= 1 { sret_extra = 1 }
  ## WIDE-ENUM SRET (§8 piece 3, > 8 words): a fn returning an enum wider than the 8-register budget also
  ## delivers via the x8 indirect result, so it needs the SAME x8-spill slot (sret_extra = 1) PLUS a scratch
  ## block sized to the enum's full {disc, payload…} width, where a `return E.V(…)` literal is materialized
  ## before the word-copy through x8. Computed from the DECLARED return type (0 for every other fn → the
  ## frame + all offsets stay byte-identical; this whole path is a64-only, so the x86 self-build is neutral).
  mut esret_w := 0
  if sretbn.n != 0 { esret_w = a64_ret_enum_sret_words(decls, src, sretbn.s, sretbn.n, a) }
  if esret_w >= 1 { sret_extra = 1 }
  ## frame = saved {x29,x30} (16) + one WORD per param + the locals' total words + the slice-arg blocks +
  ## the aggregate-value blocks + the match-temp region + the SRET pointer slot + the wide-enum scratch,
  ## rounded up to 16.
  mut frame := 16 + (pcount + nloc + 2 * nsargs + naggw + mtmp + sret_extra + esret_w) * 8
  if frame % 16 != 0 { frame = frame + 8 }
  ## the SRET pointer slot sits ABOVE the match-temp region (only used by an SRET fn — struct OR wide enum).
  ## Kept in a LOCAL for the prologue store below: reading the A64_SRET_SLOT module GLOBAL back inside this
  ## very large fn mis-lowers under the frozen seed (the same landmine that forces the inline generic tag
  ## emit + the inline byte-compare above), so the prologue uses `sret_slot` while the global feeds the
  ## small emit_a64_sret_store fn (where a global read lowers correctly).
  sret_slot := 16 + (pcount + nloc + 2 * nsargs + naggw + mtmp) * 8
  A64_SRET_SLOT = sret_slot
  ## the wide-enum-SRET materialization scratch sits right ABOVE the x8-spill slot (only read when returning
  ## a wide enum — see emit_a64_sret_store's enum branch); byte offset stays consistent with the frame above.
  A64_ENUM_SRET_BLK = 16 + (pcount + nloc + 2 * nsargs + naggw + mtmp + sret_extra) * 8
  ## the agg region begins right ABOVE the locals (slice-arg blocks then aggregate-value blocks share the
  ## A64_AGG bump allocator); the match-temp region sits above that. The allocator hands out blocks up to
  ## A64_AGG_LIM (the match-temp start), never into it.
  A64_AGG = 16 + (pcount + nloc) * 8
  A64_AGG_LIM = 16 + (pcount + nloc + 2 * nsargs + naggw) * 8
  A64_MTMP = 16 + (pcount + nloc + 2 * nsargs + naggw) * 8
  ## `@abi(naked)` (spec ch.80): emit label + raw body ONLY (no prologue/param-spill/epilogue). The body
  ## is asm() lines over the AArch64 registers; the trailing value (a closing `asm("ret")`) is emitted too.
  if a64_fn_is_naked(src, d.name_start, d.name_len) {
    emit_a64_export(sb, src, d.name_start, d.name_len)
    if d.kind == 5 { push_str(sb, "__test") ; push_int(sb, i64(A64_TEST_DECL_INDEX)) } else if d.name_len == 0 { a64_emit_lambda_label(sb, src, d.mod_start, d.mod_len, d.name_start) } else { push_str(sb, fname) } ; push_str(sb, ":\n")
    emit_a64_stmts(d.body_stmts, sb, a, src, ephead, pcount, d.body_stmts, decls, frame, 0, 0)
    if not ex_is_no_tail(d.value) { emit_a64_expr(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    return
  }
  ## FLOAT ABI (SysV / AAPCS64): float params arrive in d0–d7, integer params in x0–x7 (INDEPENDENT
  ## register counters), and a float return is delivered in d0. `A64_RET_FLOAT` drives the epilogue's
  ## x0 → d0 move for a float-returning fn. The prologue spills each param to its frame slot from the
  ## right class register (float from d<fidx>, int from x<iidx>). >8 args of a class → stack (deferred).
  ## GENERICS (§8 mono): a generic instance whose RETURN type is the type-param `T` (`id(T, v : T) -> T`)
  ## returns the concrete instance type — substitute the return span so the struct/enum-return ABI
  ## classification below fires (an `id__Opt` returns the 2-word `Opt`, not a scalar). Gated on an active
  ## substitution + an exact type-param match, so a non-instance / non-`T` return is byte-identical.
  mut rts := d.ret_ts
  mut rtl := d.ret_tl
  ## GENERICS (§8): substitute the return span when it IS the type-param `T`, via an inline BYTE compare
  ## — NOT `streq`/`str ==`, which mis-lowers inside this very large fn under the frozen seed (it returns
  ## false for two byte-identical spans at different offsets; it works only in small fns). Gated on an
  ## active substitution so a non-instance / non-`T` return keeps `rts = d.ret_ts` (byte-identical).
  if inst {
    if A64_SUB_GPL != 0 {
      if d.ret_tl == A64_SUB_GPL {
        rbs := bytes(str_at((src + d.ret_ts), d.ret_tl))
        gbs := bytes(str_at((src + A64_SUB_GPS), A64_SUB_GPL))
        mut alleq := true
        mut bi := 0
        while bi < d.ret_tl { if rbs[bi] != gbs[bi] { alleq = false } ; bi = bi + 1 }
        if alleq { rts = A64_SUB_ITS ; rtl = A64_SUB_ITL }
      }
    }
  }
  A64_RET_FLOAT = scalar_name_is_float(src, rts, rtl)
  A64_RET_BYTE_N = 0
  mut byte_ret_n := 0
  byte_ret_span_n := fixed_array_byte_return_len_span(src, rts, rtl)
  if byte_ret_span_n >= 1 { byte_ret_n = byte_ret_span_n ; A64_RET_BYTE_N = byte_ret_span_n }
  ## STRUCT-RETURN convention (§8 piece 2): if the fn returns a 1..8-word struct, record its span so
  ## Return / trailing-value deliver word k → x_k (via emit_a64_struct_value). The delivery is a
  ## type-agnostic word copy, so a struct with an ENUM / str field (not all-scalar) is delivered too.
  A64_RET_STRUCT_NS = 0
  A64_RET_STRUCT_NL = 0
  rsbn := base_type_name(src, rts, rtl)
  if rsbn.n != 0 and a64_ret_struct_words(decls, src, rsbn.s, rsbn.n, a) >= 1 { A64_RET_STRUCT_NS = rsbn.s ; A64_RET_STRUCT_NL = rsbn.n }
  if a64_fn_returns_tuple(d, src) {
    tw := a64_tuple_words(src, rts, rtl)
    if tw >= 1 and tw <= 7 { A64_RET_STRUCT_NS = rts ; A64_RET_STRUCT_NL = rtl }
  }
  ## WIDE-STRUCT SRET convention (§8 piece 2b): a fn returning a PLAIN struct of > 8 words delivers via the
  ## indirect result pointer (x8) — record its span so Return copies the value into [x8] instead of the
  ## register path. Computed from the DECLARED type (matches the frame reservation above); mutually
  ## exclusive with the 1..8-word register struct-return (a64_ret_struct_words / a64_ret_sret_words disjoint).
  A64_RET_SRET_NS = 0
  A64_RET_SRET_NL = 0
  sbn := base_type_name(src, d.ret_ts, d.ret_tl)
  if sbn.n != 0 and a64_ret_sret_words(decls, src, sbn.s, sbn.n, a) >= 1 { A64_RET_SRET_NS = sbn.s ; A64_RET_SRET_NL = sbn.n }
  ## WIDE-ENUM SRET (§8 piece 3, > 8 words): a fn returning an enum wider than the register budget ALSO
  ## routes through the SAME A64_RET_SRET span (emit_a64_sret_store's enum branch distinguishes it by
  ## enum_decl_of). Disjoint from A64_RET_ENUM below (the ≤8-word register gate) and from the wide-struct
  ## case above (a64_ret_sret_words is struct-only), so at most one of these three fires per fn.
  if sbn.n != 0 and a64_ret_enum_sret_words(decls, src, sbn.s, sbn.n, a) >= 1 { A64_RET_SRET_NS = sbn.s ; A64_RET_SRET_NL = sbn.n }
  ## ENUM-RETURN convention (§8 piece 3): a fn returning an enum of 1..8 words delivers word 0 = disc,
  ## word k+1 = payload → x_k (via emit_a64_enum_value). Otherwise 0/0.
  A64_RET_ENUM_NS = 0
  A64_RET_ENUM_NL = 0
  if rsbn.n != 0 and enum_decl_of(decls, src, rsbn.s, rsbn.n) >= 0 {
    rew := 1 + i64(enum_max_arity(decls, src, rsbn.s, rsbn.n, a))
    if rew >= 1 and rew <= 8 { A64_RET_ENUM_NS = rsbn.s ; A64_RET_ENUM_NL = rsbn.n }
  }
  if inst {
    ## GENERICS (§8): the instance label `<fn>__<tag>` (bare-name scheme; no `@export` on an instance).
    ## Emitted INLINE (reading A64_SUB_ITS/ITL directly) — a helper taking the span through extra params
    ## is miscompiled by the frozen seed (the type-arg args arrive as stack garbage).
    push_str(sb, str_at((src + d.name_start), d.name_len))
    push_str(sb, "__")
    ## type TAG, emitted INLINE (a helper taking the span through params is miscompiled by the seed):
    ## TUPLE `(T0,…)` → `Tuple_<T0>_…`; ARRAY `[E; N]` → `Array_<E>_<N>`; else the bare scalar name.
    if str_at((src + A64_SUB_ITS), 1) == "[" {
      ## ARRAY tag `Array_<elem>_<N>` — element span (`[`..top-level `;`, trimmed) scanned INLINE (a
      ## span-through-params helper is miscompiled by the seed — landmine); the length N via the scalar
      ## `parse_arr_len` (a 3-scalar-arg call, safe like `base_type_name` above).
      push_str(sb, "Array_")
      mut adep := 0
      mut asemi := A64_SUB_ITS + 1
      mut ap := A64_SUB_ITS + 1
      mut ago := true
      while ago and ap < A64_SUB_ITS + A64_SUB_ITL {
        ac := str_at((src + ap), 1)
        if ac == "(" or ac == "[" { adep = adep + 1 }
        else if (ac == ")" or ac == "]") and adep > 0 { adep = adep - 1 }
        else if ac == ";" and adep == 0 { asemi = ap ; ago = false }
        ap = ap + 1
      }
      mut aes := A64_SUB_ITS + 1
      while aes < asemi and str_at((src + aes), 1) == " " { aes = aes + 1 }
      mut aet := asemi
      while aet > aes and str_at((src + aet - 1), 1) == " " { aet = aet - 1 }
      push_str(sb, str_at((src + aes), aet - aes))
      push_str(sb, "_")
      ## length N — the digit chars between the `;` and the closing `]`, pushed INLINE (spaces + `]`
      ## skipped). NOT `parse_arr_len` / any helper: passing `A64_SUB_ITS/ITL` as args corrupts them to
      ## stack garbage in this emit path (the seed span-forwarding landmine).
      mut alp := asemi + 1
      while alp < A64_SUB_ITS + A64_SUB_ITL {
        alc := str_at((src + alp), 1)
        if alc != " " and alc != "]" { push_str(sb, alc) }
        alp = alp + 1
      }
    } else if str_at((src + A64_SUB_ITS), 1) == "(" {
      ## TUPLE tag `Tuple_<c0>_<c1>_…` — split the `(…)` span on top-level commas, INLINE (no typearg_at:
      ## its LSpan return truncates in this emit context — the seed landmine).
      push_str(sb, "Tuple")
      mut ddepth := 0
      mut dcs := A64_SUB_ITS + 1
      mut dp := A64_SUB_ITS + 1
      mut dgo := true
      while dgo {
        dc := str_at((src + dp), 1)
        dsep := dc == "," and ddepth == 0
        dend := dc == ")" and ddepth == 0
        if dc == "(" or dc == "[" { ddepth = ddepth + 1 }
        else if (dc == ")" or dc == "]") and ddepth > 0 { ddepth = ddepth - 1 }
        if dsep or dend {
          mut a1 := dcs
          while a1 < dp and str_at((src + a1), 1) == " " { a1 = a1 + 1 }
          mut a2 := dp
          while a2 > a1 and str_at((src + a2 - 1), 1) == " " { a2 = a2 - 1 }
          push_str(sb, "_")
          push_str(sb, str_at((src + a1), a2 - a1))
          dcs = dp + 1
        }
        if dend { dgo = false }
        dp = dp + 1
      }
    } else {
      push_str(sb, str_at((src + A64_SUB_ITS), A64_SUB_ITL))
    }
    ## MULTI type-param: append `__<2nd>` / `__<3rd>` (bare scalar names; the resolver rejects array/tuple
    ## for the 2nd/3rd). Matches the call-site tag so the `bl <fn>__<t0>__<t1>__<t2>` label resolves.
    if A64_SUB_ITL2 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + A64_SUB_ITS2), A64_SUB_ITL2)) }
    if A64_SUB_ITL3 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + A64_SUB_ITS3), A64_SUB_ITL3)) }
    push_str(sb, ":\n")
  } else {
    emit_a64_export(sb, src, d.name_start, d.name_len)
    if d.kind == 5 { push_str(sb, "__test") ; push_int(sb, i64(A64_TEST_DECL_INDEX)) } else if d.name_len == 0 { a64_emit_lambda_label(sb, src, d.mod_start, d.mod_len, d.name_start) } else { push_str(sb, fname) } ; push_str(sb, ":\n")
  }
  ## AArch64's pre-index pair-store has the same +504-byte upper bound as the epilogue's post-index
  ## pair-load. For larger frames, reserve the exact byte count through x9, then save the pair at the
  ## frame base; all frame offsets remain unchanged because x29 still names the new SP.
  if frame <= 504 {
    push_str(sb, "  stp x29, x30, [sp, #-") ; push_int(sb, frame) ; push_str(sb, "]!\n")
  }
  if frame > 504 {
    push_str(sb, "  mov x9, #") ; push_int(sb, frame) ; push_str(sb, "\n")
    push_str(sb, "  sub sp, sp, x9\n")
    push_str(sb, "  stp x29, x30, [sp]\n")
  }
  push_str(sb, "  mov x29, sp\n")
  ## WIDE-STRUCT SRET: spill the incoming indirect-result pointer (x8) to its reserved frame slot so it
  ## survives nested calls / register churn to each Return, where the whole struct is copied through it.
  ## Uses the `sret_slot` LOCAL (a global read here mis-lowers in this very large fn — see above).
  if A64_RET_SRET_NL != 0 { push_str(sb, "  str x8, [x29, #") ; push_int(sb, sret_slot) ; push_str(sb, "]\n") }
  ## >8 args of a class OVERFLOW to the caller's outgoing stack block. At entry those bytes sat at
  ## [old_sp + k*8]; after `stp …,[sp,#-frame]!` (x29 = new sp) they are at [x29 + frame + k*8] (k =
  ## source order among overflow params). A stack param is a raw 8-byte word (class-agnostic — the
  ## value model carries a float's bits in a GPR): load it into x9 and spill to the param's slot.
  ## >8 args of a class OVERFLOW to the caller's outgoing stack block. At entry those bytes sat at
  ## [old_sp + k*8]; after `stp ...,[sp,#-frame]!` (x29 = new sp) they are at [x29 + frame + k*8] (k =
  ## source order among overflow params). A stack param is a raw 8-byte word (class-agnostic — the
  ## value model carries a float's bits in a GPR): load it into x9 and spill to the param's slot.
  mut pi := 0
  mut p_iidx := 0
  mut p_fidx := 0
  mut p_k := 0
  while pi < pcount {
    ## a NON-LEADING comptime type-param (pi == a64_tp_skip) consumes NO incoming register and has no
    ## spill (its frame slot stays garbage — the body never reads it by name); the register counters skip
    ## past it. FLAT ifs (a `(not skipp) and …` prefix, no nesting) — this is a very large fn.
    skipp := i64(pi) == a64_tp_skip
    isfp := a64_param_is_float(ephead, src, pi, a)
    fromreg := (isfp and p_fidx < 8) or ((not isfp) and p_iidx < 8)
    if (not skipp) and isfp and p_fidx < 8 { push_str(sb, "  str d") ; push_int(sb, p_fidx) ; push_str(sb, ", [x29, #") ; push_int(sb, 16 + pi * 8) ; push_str(sb, "]\n") }
    if (not skipp) and (not isfp) and p_iidx < 8 { push_str(sb, "  str x") ; push_int(sb, p_iidx) ; push_str(sb, ", [x29, #") ; push_int(sb, 16 + pi * 8) ; push_str(sb, "]\n") }
    if (not skipp) and (not fromreg) { push_str(sb, "  ldr x9, [x29, #") ; push_int(sb, frame + p_k * 8) ; push_str(sb, "]\n  str x9, [x29, #") ; push_int(sb, 16 + pi * 8) ; push_str(sb, "]\n") ; p_k += 1 }
    if (not skipp) and isfp { p_fidx += 1 }
    if (not skipp) and (not isfp) { p_iidx += 1 }
    pi += 1
  }
  void := d.ret_tl == 0
  emit_a64_stmts(d.body_stmts, sb, a, src, ephead, pcount, d.body_stmts, decls, frame, 0, 0)
  has_tail := not ex_is_no_tail(d.value)
  ## A void function may still end in a value-position CALL whose result is discarded by the language.
  ## Its side effect is real; dropping Decl.value here loses the final `bl` (not merely a return value).
  if void and has_tail { emit_a64_expr(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
  ## emit the trailing expression as the fn value — UNLESS it is the no-tail sentinel (the body's last
  ## statement, e.g. a tail match, already left the value in x0; emitting -1 would clobber it).
  if (not void) and has_tail {
    ## a WIDE-struct (SRET) fn's trailing value delivers THROUGH the x8 indirect-result pointer (§8 piece
    ## 2b — same as the explicit-Return path at Stmt::Return); a 1..8-word struct-returning fn's trailing
    ## value delivers word k → x_k (§8 piece 2); an enum-returning fn delivers disc+payload (§8 piece 3);
    ## otherwise the scalar emit. These four are mutually exclusive (see the A64_RET_* set-up in this fn).
    if byte_ret_n >= 1 { emit_a64_byte_array_value(d.value, sb, byte_ret_n, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    if A64_RET_SRET_NL != 0 { emit_a64_sret_store(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    if A64_RET_STRUCT_NL != 0 { emit_a64_struct_value(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    if A64_RET_ENUM_NL != 0 { emit_a64_enum_value(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    if byte_ret_n == 0 and A64_RET_STRUCT_NL == 0 and A64_RET_ENUM_NL == 0 and A64_RET_SRET_NL == 0 { emit_a64_expr(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
  }
  emit_a64_epilogue(frame, sb)
  A64_SUB_GPS = 0
  A64_SUB_GPL = 0
}

## Emit a complete runnable AArch64 GAS program: `_start` (call main, exit(x0)) + every fn + `.data`.
## If `e` is a `print`/`println` call with a single string-literal arg, emit its `.Lstr<lbl>` data.
a64_str_data_if_print := fn(e : ptr(Expr), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  match deref(e) {
    Expr::Call(cs, cl, nargs, args_head) => {
      nm := str_at((src + cs), cl)
      ispln := nm == "println"
      isp := (nm == "print" or ispln) and args_head != 0
      mut sarg := unchecked bitcast(ptr(Expr), 0)
      if args_head != 0 { ga := deref(arg_p(args_head)) ; sarg = ga.e }
      ok := isp and expr_is_str_lit(sarg)
      if ok { emit_a64_str_bytes(sb, src, expr_str_lit_ns(sarg), expr_str_lit_nl(sarg), expr_str_lit_label(sarg)) }
    }
    _ => {}
  }
}

## Walk a statement list (recursing into while/if/match bodies) emitting `.Lstr<lbl>` data for every
## print/println string literal — the labels the write syscalls reference.
emit_a64_str_data := fn(list : ptr(mut Stmt), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  mut s := list
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::ExprStmt(e, nx) => { a64_str_data_if_print(e, sb, src, a) ; s = nx }
      Stmt::While(c, b, nx) => { emit_a64_str_data(b, sb, src, a) ; s = nx }
      Stmt::If(c, th, el, nx) => { emit_a64_str_data(th, sb, src, a) ; emit_a64_str_data(el, sb, src, a) ; s = nx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; emit_a64_str_data(am.body_stmts, sb, src, a) ; arm = am.next } ; s = mnx }
      Stmt::Assign(ns, nl, v, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { emit_a64_str_data(fb, sb, src, a) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { emit_a64_str_data(rb, sb, src, a) ; s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { emit_a64_str_data(rb, sb, src, a) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { emit_a64_str_data(th, sb, src, a) ; emit_a64_str_data(el, sb, src, a) ; s = nx }
      Stmt::Loop(lb, lnx) => { emit_a64_str_data(lb, sb, src, a) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { emit_a64_str_data(ub, sb, src, a) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
}

## FLOAT rodata: `.Lflt<start>: .double <text>` for every FloatLit reachable from `e`.
emit_a64_float_data_expr := fn(e : ptr(Expr), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  match deref(e) {
    Expr::FloatLit(fs, fl) => { if a64_flt_first(fs) { push_str(sb, ".align 3\n.Lflt") ; push_int(sb, i64(fs)) ; push_str(sb, ":\n  .double ") ; push_str(sb, str_at((src + fs), fl)) ; push_str(sb, "\n") } }
    Expr::Bin(op, l, r) => { emit_a64_float_data_expr(l, sb, src, a) ; emit_a64_float_data_expr(r, sb, src, a) }
    Expr::If(c, t, f) => { emit_a64_float_data_expr(c, sb, src, a) ; emit_a64_float_data_expr(t, sb, src, a) ; emit_a64_float_data_expr(f, sb, src, a) }
    Expr::Call(cs, cl, n, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; emit_a64_float_data_expr(ga.e, sb, src, a) ; g = ga.next } }
    Expr::Field(base, fs, fl) => { emit_a64_float_data_expr(base, sb, src, a) }
    Expr::Index(base, idx) => { emit_a64_float_data_expr(base, sb, src, a) ; emit_a64_float_data_expr(idx, sb, src, a) }
    Expr::Unchecked(inner) => { emit_a64_float_data_expr(inner, sb, src, a) }
    ## FloatLits inside a struct / array / enum LITERAL — recurse so their `.Lflt` cells emit.
    Expr::StructLit(ss, sl, nf, fh) => { mut g := fh ; while g != 0 { ga := deref(arg_p(g)) ; emit_a64_float_data_expr(ga.e, sb, src, a) ; g = ga.next } }
    Expr::ArrayLit(nel, eh) => { mut g := eh ; while g != 0 { ga := deref(arg_p(g)) ; emit_a64_float_data_expr(ga.e, sb, src, a) ; g = ga.next } }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { mut g := ph ; while g != 0 { ga := deref(arg_p(g)) ; emit_a64_float_data_expr(ga.e, sb, src, a) ; g = ga.next } }
    _ => {}
  }
}
emit_a64_float_data := fn(list : ptr(mut Stmt), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  mut s := list
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { emit_a64_float_data_expr(v, sb, src, a) ; s = nx }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { emit_a64_float_data_expr(rv, sb, src, a) } ; s = nx }
      Stmt::ExprStmt(e, nx) => { emit_a64_float_data_expr(e, sb, src, a) ; s = nx }
      Stmt::While(c, b, nx) => { emit_a64_float_data_expr(c, sb, src, a) ; emit_a64_float_data(b, sb, src, a) ; s = nx }
      Stmt::If(c, th, el, nx) => { emit_a64_float_data_expr(c, sb, src, a) ; emit_a64_float_data(th, sb, src, a) ; emit_a64_float_data(el, sb, src, a) ; s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { emit_a64_float_data_expr(fv, sb, src, a) ; s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, ifv, ifnx) => { emit_a64_float_data_expr(ifv, sb, src, a) ; s = ifnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { emit_a64_float_data_expr(iv, sb, src, a) ; s = nx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; emit_a64_float_data(am.body_stmts, sb, src, a) ; arm = am.next } ; s = mnx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { emit_a64_float_data_expr(flo, sb, src, a) ; if unchecked bitcast(usize, fhi) != 0 { emit_a64_float_data_expr(fhi, sb, src, a) } ; emit_a64_float_data(fb, sb, src, a) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { emit_a64_float_data_expr(rlo, sb, src, a) ; if unchecked bitcast(usize, rhi) != 0 { emit_a64_float_data_expr(rhi, sb, src, a) } ; emit_a64_float_data(rb, sb, src, a) ; s = nx }
      Stmt::CompFor(cvs, cvl, cisv, rb, nx) => { emit_a64_float_data(rb, sb, src, a) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { emit_a64_float_data(th, sb, src, a) ; emit_a64_float_data(el, sb, src, a) ; s = nx }
      Stmt::Loop(lb, lnx) => { emit_a64_float_data(lb, sb, src, a) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { emit_a64_float_data(ub, sb, src, a) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
}

## TOOL-5 — substring filter over the source-level test description. This mirrors the native runner's
## selection rule but keeps the cross backend independent of the x86 driver emitter.
a64_test_selected := fn(src : ptr(u8), start : usize, len : usize) -> bool {
  if A64_TEST_FILTER_N == 0 { return true }
  desc := str_at((src + start), len)
  needle := str_at(unchecked bitcast(ptr(u8), A64_TEST_FILTER_P), A64_TEST_FILTER_N)
  if needle.len > desc.len { return false }
  mut i := 0
  while i + needle.len <= desc.len {
    if str_at(unchecked bitcast(usize, desc.ptr) + i, needle.len) == needle { return true }
    i += 1
  }
  false
}

a64_test_is_result := fn(src : ptr(u8), d : Decl) -> bool {
  if d.ret_tl < 6 { return false }
  str_at((src + d.ret_ts), 6) == "Result"
}

a64_emit_test_desc := fn(in out sb : rt::StrBuf, src : ptr(u8), start : usize, len : usize, idx : usize) {
  push_str(sb, ".La64testdesc") ; push_int(sb, i64(idx)) ; push_str(sb, ":\n  .byte ")
  if len == 0 { push_str(sb, "0\n") } else {
    mut i := 0
    while i < len {
      if i != 0 { push_str(sb, ", ") }
      push_int(sb, i64(bytes(str_at((src + start), len))[i]))
      i += 1
    }
    push_byte(sb, 10)
  }
}

a64_emit_test_report := fn(in out sb : rt::StrBuf, idx : usize, dlen : usize, kind : usize) {
  push_str(sb, "  mov x0, #1\n  adrp x1, .La64testprefix\n  add x1, x1, :lo12:.La64testprefix\n  mov x2, #5\n  mov x8, #64\n  svc #0\n  mov x0, #1\n  adrp x1, .La64testdesc")
  push_int(sb, i64(idx))
  push_str(sb, "\n  add x1, x1, :lo12:.La64testdesc") ; push_int(sb, i64(idx))
  push_str(sb, "\n  mov x2, #") ; push_int(sb, i64(dlen))
  push_str(sb, "\n  mov x8, #64\n  svc #0\n  mov x0, #1\n  adrp x1, .La64test")
  if kind == 0 { push_str(sb, "ok") }
  if kind == 1 { push_str(sb, "soft") }
  if kind == 2 { push_str(sb, "trap") }
  push_str(sb, "\n  add x1, x1, :lo12:.La64test")
  if kind == 0 { push_str(sb, "ok") }
  if kind == 1 { push_str(sb, "soft") }
  if kind == 2 { push_str(sb, "trap") }
  push_str(sb, "\n  mov x2, #")
  if kind == 0 { push_int(sb, 5) }
  if kind != 0 { push_int(sb, 14) }
  push_str(sb, "\n  mov x8, #64\n  svc #0\n")
}

## A small sequential runner for AArch64 Linux. Each test still gets its own child, so a trap cannot
## abort later tests; `-k` controls whether a normal failure stops launching new children. The runner is
## intentionally emitted here, beside the ABI it speaks, rather than translating the x86 register code.
a64_emit_test_runner := fn(decls : ptr(rt::Vec), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  push_str(sb, ".section .rodata\n.La64testprefix: .byte 116, 101, 115, 116, 32\n.La64testok: .byte 58, 32, 111, 107, 10\n.La64testsoft: .byte 58, 32, 70, 65, 73, 76, 32, 40, 115, 111, 102, 116, 41, 10\n.La64testtrap: .byte 58, 32, 70, 65, 73, 76, 32, 40, 116, 114, 97, 112, 41, 10\n")
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 5 and a64_test_selected(src, d.name_start, d.name_len) { a64_emit_test_desc(sb, src, d.name_start, d.name_len, i) }
    i += 1
  }
  push_str(sb, ".text\n.global _start\n_start:\n  mov x19, #0\n")
  i = 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 5 and a64_test_selected(src, d.name_start, d.name_len) {
      push_str(sb, "  mov x0, #17\n  mov x1, #0\n  mov x2, #0\n  mov x3, #0\n  mov x4, #0\n  mov x8, #220\n  svc #0\n  cbz x0, .La64child") ; push_int(sb, i64(i)) ; push_str(sb, "\n  cmp x0, #0\n  b.lt .La64forkfail") ; push_int(sb, i64(i)) ; push_str(sb, "\n  mov x20, x0\n  sub sp, sp, #16\n  mov x0, x20\n  mov x1, sp\n  mov x2, #0\n  mov x3, #0\n  mov x8, #260\n  svc #0\n  cmp x0, #0\n  b.lt .La64waitfail") ; push_int(sb, i64(i)) ; push_str(sb, "\n  ldr x2, [sp]\n  add sp, sp, #16\n  and x3, x2, #127\n  cbnz x3, .La64trap") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      if a64_test_is_result(src, d) {
        push_str(sb, "  lsr x3, x2, #8\n  and x3, x3, #255\n  cbnz x3, .La64soft") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      }
      a64_emit_test_report(sb, i, d.name_len, 0)
      push_str(sb, "  b .La64next") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      push_str(sb, ".La64soft") ; push_int(sb, i64(i)) ; push_str(sb, ":\n")
      a64_emit_test_report(sb, i, d.name_len, 1)
      push_str(sb, "  add x19, x19, #1\n")
      if not A64_TEST_KEEP { push_str(sb, "  b .La64done\n") } else { push_str(sb, "  b .La64next") ; push_int(sb, i64(i)) ; push_str(sb, "\n") }
      push_str(sb, ".La64trap") ; push_int(sb, i64(i)) ; push_str(sb, ":\n")
      a64_emit_test_report(sb, i, d.name_len, 2)
      push_str(sb, "  add x19, x19, #1\n")
      if not A64_TEST_KEEP { push_str(sb, "  b .La64done\n") } else { push_str(sb, "  b .La64next") ; push_int(sb, i64(i)) ; push_str(sb, "\n") }
      push_str(sb, ".La64forkfail") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  b .La64trap") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      push_str(sb, ".La64waitfail") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  add sp, sp, #16\n  b .La64trap") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      push_str(sb, ".La64child") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  bl __test") ; push_int(sb, i64(i))
      if a64_test_is_result(src, d) {
        push_str(sb, "\n  cmp x0, #0\n  b.eq .La64childok") ; push_int(sb, i64(i)) ; push_str(sb, "\n  mov x0, #1\n  b .La64childexit") ; push_int(sb, i64(i)) ; push_str(sb, "\n.La64childok") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  mov x0, #0\n")
      } else { push_str(sb, "\n  mov x0, #0\n") }
      push_str(sb, ".La64childexit") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  mov x8, #93\n  svc #0\n")
      push_str(sb, ".La64next") ; push_int(sb, i64(i)) ; push_str(sb, ":\n")
    }
    i += 1
  }
  push_str(sb, ".La64done:\n  mov x0, x19\n  mov x8, #93\n  svc #0\n")
}

pub emit_a64_program := fn(decls : ptr(rt::Vec), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  ## COMPTIME `when`-GUARD gating (Comptime §7.1/§9; CT-5) — BEFORE any callee resolution or emission,
  ## exactly where x86 `lower::emit_program` runs it. A decl gated on another arch is neutered to an
  ## as-if-absent no-op here, so an arch-gated raw-`asm` body (`lib/std/thread.al`) never reaches `as`.
  apply_when_guards(decls, src, a64_target_arch())
  if A64_TEST_MODE { a64_emit_test_runner(decls, sb, src, a) }
  if not A64_TEST_MODE { push_str(sb, ".text\n.global _start\n_start:\n  bl main\n  mov x8, #93\n  svc #0\n") }
  cnt := rt::vec_len(deref(decls))
  ## GENERICS (§8 mono): instances are RECORDED DURING EMIT — every generic CALL site (`emit_a64_expr`)
  ## resolves its type-arg and appends via `a64_inst_add` (dedup) into the fixed A64_INST_* arrays.
  ## Emitting the non-generic fns seeds the set; the mono loop below emits each instance, and an
  ## instance's own generic calls append further instances (transitive), the loop re-reading
  ## `A64_INST_N` until it converges. (Recording at the emit call site reuses the proven type-arg
  ## resolution and matches the emitted `bl` labels exactly.)
  A64_INST_N = 0
  ## the float-literal pool is per PROGRAM, like the instance set (see A64_FLT_OFF).
  A64_FLT_N = 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 or (A64_TEST_MODE and d.kind == 5 and a64_test_selected(src, d.name_start, d.name_len)) {
      if d.kind == 5 { A64_TEST_DECL_INDEX = i }
      emit_a64_fn(d, sb, a, src, decls)
    }
    i += 1
  }
  ## emit one monomorphized instance per RECORDED (generic-fn, type) pair, with the instance
  ## substitution active (A64_SUB_ITS/ITL); `emit_a64_fn` skips the leading type-param. The loop
  ## re-reads `A64_INST_N` so instances discovered while emitting an earlier instance are also emitted.
  mut mi := 0
  while mi < A64_INST_N {
    mgi := A64_INST_GI[mi]
    A64_SUB_ITS = A64_INST_TS[mi]
    A64_SUB_ITL = A64_INST_TL[mi]
    A64_SUB_ITS2 = A64_INST_TS2[mi]
    A64_SUB_ITL2 = A64_INST_TL2[mi]
    A64_SUB_ITS3 = A64_INST_TS3[mi]
    A64_SUB_ITL3 = A64_INST_TL3[mi]
    gdi := deref(decl_get(decls, mgi))
    emit_a64_fn(gdi, sb, a, src, decls)
    A64_SUB_ITS = 0
    A64_SUB_ITL = 0
    A64_SUB_ITS2 = 0
    A64_SUB_ITL2 = 0
    A64_SUB_ITS3 = 0
    A64_SUB_ITL3 = 0
    mi = mi + 1
  }
  ## `__print_u64`: render x0 as unsigned decimal into `.Lnumbuf` (backward from the end) and write it
  ## to fd 1. Numeric local labels (1:/1b). Value 0 prints one '0' (loop body runs before the cbnz).
  push_str(sb, "__print_u64:\n  adrp x3, .Lnumbuf\n  add x3, x3, :lo12:.Lnumbuf\n  add x4, x3, #24\n  mov x5, x4\n  mov x6, #10\n")
  push_str(sb, "1:\n  udiv x7, x0, x6\n  msub x8, x7, x6, x0\n  add x8, x8, #48\n  sub x5, x5, #1\n  strb w8, [x5]\n  mov x0, x7\n  cbnz x0, 1b\n")
  push_str(sb, "  mov x0, #1\n  mov x1, x5\n  sub x2, x4, x5\n  mov x8, #64\n  svc #0\n  ret\n")
  ## `.data`: a print newline byte + a 24-byte itoa buffer, one `.quad` cell per module-level SCALAR
  ## global (8-byte aligned), then the print strings.
  push_str(sb, ".data\n.Lprnl:\n  .byte 10\n.align 3\n.Lnumbuf:\n  .zero 24\n")
  mut gi := 0
  while gi < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), gi)))
    ## `name_len != 0` on all three arms: a `when`-guarded decl that folded FALSE for this target was
    ## neutered to a NAMELESS kind-0 no-op (`lower_layout::apply_when_guards`), and a nameless global cell would
    ## emit an EMPTY label (`.align 3` / `:` / `.quad …`) that `as` rejects. As-if-absent means no cell.
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 and ex_value_is_scalar(d.value) {
      gname := str_at((src + d.name_start), d.name_len)
      push_str(sb, ".align 3\n") ; push_str(sb, gname) ; push_str(sb, ":\n  .quad ") ; push_int(sb, ex_value_init(d.value)) ; push_str(sb, "\n")
    }
    ## a FLOAT-valued global (`mut F := 40.0`) — its `.data` cell is a `.double` (IEEE bits), not a
    ## `.quad`. Guard `d.value` on null (some kind-0 decls carry no value expr) before touching it.
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 {
      if unchecked bitcast(usize, d.value) != 0 {
        if expr_is_float_lit(d.value) {
          gname := str_at((src + d.name_start), d.name_len)
          push_str(sb, ".align 3\n") ; push_str(sb, gname) ; push_str(sb, ":\n  .double ") ; push_str(sb, str_at((src + expr_float_lit_ns(d.value)), expr_float_lit_nl(d.value))) ; push_str(sb, "\n")
        }
      }
    }
    ## an AGGREGATE global (struct/array/enum initializer) — its `.data` cells are emitted RECURSIVELY as
    ## ascending 8-byte cells (nested struct fields flattened inline), addressed by its plain-name label.
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 {
      if unchecked bitcast(usize, d.value) != 0 {
        if a64_value_is_agg(d.value) {
          gname := str_at((src + d.name_start), d.name_len)
          push_str(sb, ".align 3\n") ; push_str(sb, gname) ; push_str(sb, ":\n")
          emit_a64_global_cells(d.value, sb, decls, src, a)
        }
      }
    }
    gi += 1
  }
  mut si := 0
  while si < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), si)))
    if d.kind == 1 { emit_a64_str_data(d.body_stmts, sb, src, a) }
    si += 1
  }
  ## FLOAT rodata — one `.Lflt<start>: .double` cell per FloatLit in every fn body. The walk MUST
  ## cover the TRAILING RETURN EXPRESSION (`d.value`) as well as the statement list: a fn whose whole
  ## body IS an expression has an EMPTY `body_stmts`, so its FloatLits had no cell emitted at all
  ## while `emit_a64_expr`'s FloatLit arm still emitted `adrp x9, .Lflt<start>` — every `math_*` test
  ## then died at `ld` on an undefined `.Lflt…` coming out of `std::math::abs`
  ## (`fn(x : f64) -> f64 { if x < 0.0 { 0.0 - x } else { x } }`, a pure trailing `if` expression).
  ## `d.value` is the `Num(-1)` no-tail sentinel when a fn has no trailing expr, and may be null on a
  ## decl that carries no value — both guarded, mirroring `emit_a64_fn`'s own tail emit.
  mut fdi := 0
  while fdi < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), fdi)))
    if d.kind == 1 {
      emit_a64_float_data(d.body_stmts, sb, src, a)
      if unchecked bitcast(usize, d.value) != 0 {
        if not ex_is_no_tail(d.value) { emit_a64_float_data_expr(d.value, sb, src, a) }
      }
    }
    fdi += 1
  }
}
