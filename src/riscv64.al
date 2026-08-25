## selfhost::riscv64 (backend breadth), item 3: riscv64 (RV64 Linux GAS).
##
## A FOURTH backend against the SAME parsed `Decl` model the x86_64 lower, the WASM backend, and the
## aarch64 backend consume. Scope mirrors aarch64.al's scalar kernel + scalar globals: every function
## (kind 1), value or void, up to 8 `i64` value params, local `:=` + reassignment (top-level), literals
## (`Num`/`BoolLit`), params/locals/scalar-globals (`Var`), arithmetic + comparison + bitwise/boolean
## `Bin`, value + statement `if`, `while`, direct calls, `return`, call-as-statement. Emits a
## `.global _start` that calls `main` and turns the a0 result into the RV64 `exit` syscall (nr 93 in
## a7, `ecall`); assembled by `riscv64-unknown-linux-gnu-{as,ld}` and run under `qemu-riscv64`, the
## exit code is checked exactly like the native x86_64 / wasmtime / aarch64 paths.
##
## CODEGEN MODEL: the same naive STACK MACHINE as aarch64 — every expression computes into a0; a binary
## op pushes lhs (`sd a0, -16(sp)!` via addi+sd), evaluates rhs into a0, pops lhs (rhs → a1), combines.
## Locals/params live in the frame at `(16 + slot*8)(s0)`. Anything outside the kernel (structs,
## enums, arrays, strings, enum match, nested new `:=`, >8 args, generics) emits `ebreak` — a fail-loud trap
## (SIGTRAP → exit 133 under qemu), never a silently-wrong result. The lean-lower workarounds baked into
## aarch64.al are preserved here (standalone ifs not else-if chains as a fn body; bind inline str-call
## results to a local; flat resolution not nested if/else; <=6-param helpers).
##
## ADDITIVE: nothing in the self-build invokes `emit_rv_program`, so the x86_64 GAS the tree emits for
## itself is byte-for-byte unchanged and the TOOL-1 fixpoint (seed==Stage1==Stage2) is unaffected.
(Arg, Arm, Bind, Decl, Expr, FieldDecl, Param, Stmt) := ast
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
field_type_is_float := lower_layout::field_type_is_float
variant_payload_type := lower_layout::variant_payload_type
## MOD §6.3/§7.2 — the source-scan symbol helpers shared with the x86_64 lower (see aarch64.al): the
## `@export("sym")` alias + `@extern("sym")` external symbol, reused so the symbol rules stay identical.
(CSpan) := lower_ctx
(export_name, extern_symbol, field_type_span, compfor_iter_arg) := lower

## TOOL-5 cross-target mode. See the AArch64 twin for the boundary rationale; only scalar facts cross
## from the driver so the frozen self-host lower does not copy a selection aggregate.
mut RV_TEST_MODE : bool = false
mut RV_TEST_FILTER_P : usize = 0
mut RV_TEST_FILTER_N : usize = 0
mut RV_TEST_KEEP : bool = false
mut RV_TEST_DECL_INDEX : usize = 0
pub set_cross_test_mode := fn(mode : usize) -> i64 {
  RV_TEST_MODE = mode != 0
  return 0
}
pub set_cross_test_filter := fn(p : usize, n : usize) -> i64 {
  RV_TEST_FILTER_P = p
  RV_TEST_FILTER_N = n
  return 0
}
pub set_cross_test_options := fn(keep : usize) -> i64 {
  RV_TEST_KEEP = keep != 0
  return 0
}

decl_at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
## a direct typed accessor for decl `i` (encapsulates the usize-handle recovery).
decl_get := fn(decls : ptr(rt::Vec), i : usize) -> ptr(Decl) { hh := rt::vec_get(deref(decls), i) ; return decl_at(Decl, hh) }

node_ptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}

streq := fn(src : ptr(u8), a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool {
  str_at((src + a_s), a_n) == str_at((src + b_s), b_n)   ## src+off = pointer arith (I11/CG-8)
}

## GENERICS (§8 mono): a PER-PROGRAM-EMISSION label counter. A generic fn body is emitted once PER INSTANCE,
## so the same AST node is emitted multiple times — a handle-derived label id would then DUPLICATE across
## instances (assembler rejects). A monotonic counter gives every label site a fresh id at each emission.
## RV_NL is reset at the start of emit_rv_program: labels are unique across nested control flow and all
## generic instances in one program, while repeated program emissions in one process remain byte-identical.
## rv64 emit is dormant in the x86 self-build, so this global never advances there (x86 fixpoint neutral).
mut RV_NL := 0
rv_next_label := fn() -> i64 { r := RV_NL ; RV_NL = RV_NL + 1 ; r }

rv_count_params := fn(params_head : ptr(mut Param), a : rt::Arena) -> i64 {
  mut p := params_head
  mut k := 0
  while p != 0 { pm := deref(param_p(p)) ; k = k + 1 ; p = pm.next }
  i64(k)
}

rv_param_find := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> i64 {
  mut p := params_head
  mut idx := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { return i64(idx) }
    idx += 1
    p = pm.next
  }
  return -1
}

## --- struct support (mirror of aarch64.al; separate usize accessors, never a returned struct) ---
rv_is_slit := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) { Expr::StructLit(ss, sn, nf, ah) => { r = true } _ => {} }
  r
}
rv_slit_ns := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::StructLit(ss, sn, nf, ah) => { r = ss } _ => {} }
  r
}
rv_slit_nl := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::StructLit(ss, sn, nf, ah) => { r = sn } _ => {} }
  r
}


## THIS BACKEND'S OWN ARCH IDENTITY (Tooling §2.7). `target.*` is the RESOLVED SELECTED machine model —
## the machine being compiled FOR — so when this emitter runs, `target.arch` IS `Arch.riscv64`. It used
## to fold as `x86_64` "so the sweep compares like-for-like", which made `target.arch == Arch.x86_64`
## TRUE while emitting RISC-V instructions: a conformance defect that also made every library arch gate
## inert. ONE accessor so the `comptime if` fold and the `when`-guard fold can never drift apart.
rv_target_arch := fn() -> str { "riscv64" }

## Fold a `comptime if <cond>` predicate at emit time — the rv64 dual of the x86 lower's `decl_guard_fold`.
## 1 = TRUE (emit the then-branch), 0 = FALSE (emit the else-branch), -1 = cannot fold (a typeinfo /
## type-param predicate — emit NEITHER; deferred, it needs the monomorphization context the rv64 path
## lacks). Same SHAPE as `decl_guard_fold`/`comptime_cond_eval` on the x86 path, folded against THIS
## target: `target.arch == Arch.riscv64` folds TRUE and any other arch FALSE (`rv_target_arch()`),
## composed with `and`/`or`/`not` (op codes 40/41/42). A `verify.checked`
## / `match typeinfo(T)` predicate is unfoldable here (-1). FLAT ifs + self-recursion (no nested match).
rv_comp_cond_fold := fn(cond : ptr(Expr), src : ptr(u8)) -> i64 {
  mut r := 0 - 1
  match deref(cond) {
    Expr::Bin(op, l, rr) => {
      an := arch_rhs_span(rr, src)
      if an.n != 0 {
        eq := str_at((src + an.s), an.n) == rv_target_arch()
        if op == 20 { if eq { r = 1 } else { r = 0 } }
        if op == 28 { if eq { r = 0 } else { r = 1 } }
      }
      ## TYPE-name equality `T == <type>` / `T != <type>` inside a mono INSTANCE (RV_SUB active, §8):
      ## the LHS names the instance's type-param, the RHS is a bare type name → compare the concrete
      ## instance type's base name. Mirrors the x86 comptime_cond_eval type-eq arm.
      if an.n == 0 and (op == 20 or op == 28) and RV_SUB_GPL != 0 {
        lvs := ex_var_ns(l)
        lvn := ex_var_nl(l)
        rvs := ex_var_ns(rr)
        rvn := ex_var_nl(rr)
        if lvn != 0 and rvn != 0 and streq(src, lvs, lvn, RV_SUB_GPS, RV_SUB_GPL) {
          itb := base_type_name(src, RV_SUB_ITS, RV_SUB_ITL)
          teq := streq(src, itb.s, itb.n, rvs, rvn)
          if op == 20 { if teq { r = 1 } else { r = 0 } }
          if op == 28 { if teq { r = 0 } else { r = 1 } }
        }
      }
      if an.n == 0 and op == 42 {
        lv := rv_comp_cond_fold(l, src)
        if lv == 1 { r = 0 }
        if lv == 0 { r = 1 }
      }
      if an.n == 0 and op == 40 {
        lv := rv_comp_cond_fold(l, src)
        rv := rv_comp_cond_fold(rr, src)
        if lv == 0 or rv == 0 { r = 0 }
        if lv == 1 and rv == 1 { r = 1 }
      }
      if an.n == 0 and op == 41 {
        lv := rv_comp_cond_fold(l, src)
        rv := rv_comp_cond_fold(rr, src)
        if lv == 1 or rv == 1 { r = 1 }
        if lv == 0 and rv == 0 { r = 0 }
      }
    }
    ## `verify.checked` (CT-11): the current verification mode (RV_CHK — checked by default, cleared
    ## inside `unchecked {}`). Mirrors x86 comptime_cond_eval's `cx.vchk` arm.
    Expr::Field(b, fs, fl) => {
      if ex_var_nl(b) != 0 and str_at((src + ex_var_ns(b)), ex_var_nl(b)) == "verify" {
        if RV_CHK { r = 1 } else { r = 0 }
      }
    }
    ## `match typeinfo(T) { <Kind>(_) => true; _ => false }` used as a comptime-if CONDITION (§8): fold
    ## by T's KIND inside a mono INSTANCE (RV_SUB active). The FIRST arm's variant name is the tested
    ## kind; a match → 1, else 0.
    Expr::Match(scrut, arms_head) => {
      if RV_SUB_ITL != 0 {
        kind := ct_type_kind(RV_SUB_ITS, RV_SUB_ITL, rv_decls(), src)
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



rv_local_struct_ns := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := head
  mut rs := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and rv_is_slit(v) { rs = rv_slit_ns(v) ; done = true }
        ## a local bound to a struct-RETURNING CALL takes the callee's returned struct type (§8 piece 2).
        if streq(src, ans, anl, ns, nl) and (not done) { crs := rv_call_ret_struct_span(v, rv_decls(), src, a) ; if crs.n != 0 { rs = crs.s ; done = true } }
        ## a local bound to a WIDE-struct-returning CALL (`s := mk()`, LP64 indirect result) takes the same
        ## returned struct type — it IS the destination the callee wrote through, so `.field` resolves here.
        if streq(src, ans, anl, ns, nl) and (not done) { crt := rv_call_ret_sret_span(v, rv_decls(), src, a) ; if crt.n != 0 { rs = crt.s ; done = true } }
        ## an aggregate-VAR copy `q := p` takes p's struct type (resolve the source local recursively).
        if streq(src, ans, anl, ns, nl) and (not done) {
          cvns := ex_var_ns(v) ; cvnl := ex_var_nl(v)
          if cvnl != 0 and (not streq(src, cvns, cvnl, ns, nl)) {
            if rv_local_struct_nl(head, src, cvns, cvnl, a) != 0 { rs = rv_local_struct_ns(head, src, cvns, cvnl, a) ; done = true }
          }
        }
        ## a standard-byte aggregate field copy `q := p.inner` takes the leaf struct type. The source
        ## field's byte offset is handled by the emitter; this scan only gives q the right frame shape.
        if streq(src, ans, anl, ns, nl) and (not done) and ex_is_field(v) {
          sfp := rv_std_path_ty(v, head, src, a, rv_decls())
          if rv_std_path_ok(v, head, src, a, rv_decls()) and sfp.n != 0 {
            sbn := base_type_name(src, sfp.s, sfp.n)
            if struct_decl_of(rv_decls(), src, sbn.s, sbn.n) >= 0 { rs = sbn.s ; done = true }
          }
        }
        ## `x := xs[i]` — an ELEMENT copy out of an array of structs takes the ELEMENT struct's type, so
        ## `x.field` reads resolve against x's own (element-wide) frame slots.
        if streq(src, ans, anl, ns, nl) and (not done) { eis := rv_index_elem_struct_span(v, src, a, rv_decls()) ; if eis.n != 0 { rs = eis.s ; done = true } }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        ## an ITERABLE for over a struct-element array types its loop var as the element struct, so
        ## `p.field` reads resolve through localok (base = the loop var's copied element slots).
        if streq(src, fns, fnl, ns, nl) and unchecked bitcast(usize, fhi) == 0 {
          es := rv_arr_elem_struct_span(head, src, ex_var_ns(flo), ex_var_nl(flo), a)
          if es.n != 0 { rs = es.s ; done = true }
        }
        s = nx
      }
      ## comptime-for/if loop vars are scalar / their locals are fn-frame level — a struct-element type
      ## scan just advances past them (matching the `for`/`if` arms above; no top-level local is hidden).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
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
rv_local_struct_nl := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := head
  mut rn := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and rv_is_slit(v) { rn = rv_slit_nl(v) ; done = true }
        if streq(src, ans, anl, ns, nl) and (not done) { crs := rv_call_ret_struct_span(v, rv_decls(), src, a) ; if crs.n != 0 { rn = crs.n ; done = true } }
        ## a WIDE-struct-returning CALL bind (`s := mk()`, LP64 indirect result) — same span, see the _ns twin.
        if streq(src, ans, anl, ns, nl) and (not done) { crt := rv_call_ret_sret_span(v, rv_decls(), src, a) ; if crt.n != 0 { rn = crt.n ; done = true } }
        ## an aggregate-VAR copy `q := p` takes p's struct type (resolve the source local recursively).
        if streq(src, ans, anl, ns, nl) and (not done) {
          cvns := ex_var_ns(v) ; cvnl := ex_var_nl(v)
          if cvnl != 0 and (not streq(src, cvns, cvnl, ns, nl)) {
            if rv_local_struct_nl(head, src, cvns, cvnl, a) != 0 { rn = rv_local_struct_nl(head, src, cvns, cvnl, a) ; done = true }
          }
        }
        ## a standard-byte aggregate field copy `q := p.inner` takes the leaf struct type.
        if streq(src, ans, anl, ns, nl) and (not done) and ex_is_field(v) {
          sfp := rv_std_path_ty(v, head, src, a, rv_decls())
          if rv_std_path_ok(v, head, src, a, rv_decls()) and sfp.n != 0 {
            sbn := base_type_name(src, sfp.s, sfp.n)
            if struct_decl_of(rv_decls(), src, sbn.s, sbn.n) >= 0 { rn = sbn.n ; done = true }
          }
        }
        ## `x := xs[i]` — an ELEMENT copy takes the ELEMENT struct's type (see the _ns twin).
        if streq(src, ans, anl, ns, nl) and (not done) { eis := rv_index_elem_struct_span(v, src, a, rv_decls()) ; if eis.n != 0 { rn = eis.n ; done = true } }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        if streq(src, fns, fnl, ns, nl) and unchecked bitcast(usize, fhi) == 0 {
          es := rv_arr_elem_struct_span(head, src, ex_var_ns(flo), ex_var_nl(flo), a)
          if es.n != 0 { rn = es.n ; done = true }
        }
        s = nx
      }
      ## comptime-for/if loop vars are scalar / their locals are fn-frame level — a struct-element type
      ## scan just advances past them (matching the `for`/`if` arms above; no top-level local is hidden).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
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

## Struct-type name (start/len) of a struct-typed PARAM (its `: T` annotation naming a struct), 0/0
## otherwise — passed by-reference (slot holds the base addr; read-only, a field write is trapped).
rv_param_struct_ns := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> usize {
  mut p := params_head
  mut rs := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      ## GENERICS (§8): substitute the type-param with the instance type so a `v : T` STRUCT param is
      ## recognized (in-instance only). Then strip a generic application (`Box(T)` → `Box`).
      mut ets := pm.ts
      mut etl := pm.tl
      if RV_SUB_GPL != 0 { if streq(src, pm.ts, pm.tl, RV_SUB_GPS, RV_SUB_GPL) { ets = RV_SUB_ITS ; etl = RV_SUB_ITL } }
      bt := base_type_name(src, ets, etl)
      if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { rs = bt.s }
    }
    p = pm.next
  }
  rs
}
rv_param_struct_nl := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> usize {
  mut p := params_head
  mut rn := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      mut ets := pm.ts
      mut etl := pm.tl
      if RV_SUB_GPL != 0 { if streq(src, pm.ts, pm.tl, RV_SUB_GPS, RV_SUB_GPL) { ets = RV_SUB_ITS ; etl = RV_SUB_ITL } }
      bt := base_type_name(src, ets, etl)
      if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { rn = bt.n }
    }
    p = pm.next
  }
  rn
}
## GENERICS (§8 mono): is param `[ns,nl]` a GENERIC array VALUE-param (`a : T`, T → `[E; N]` in the active
## instance)? Returns the element STRIDE in words (1 = scalar element only; a struct/enum element is a
## documented follow-up → 0). The param slot holds the array BASE ADDRESS (by-reference), so `a[i]` loads
## at `[base + i*stride*8]`. 0 = not a generic array param. Mirrors a64_param_gen_arr_stride.
rv_param_gen_arr_stride := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if RV_SUB_GPL == 0 { return 0 }
  if str_at((src + RV_SUB_ITS), 1) != "[" { return 0 }
  mut p := params_head
  mut isgen := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { if streq(src, pm.ts, pm.tl, RV_SUB_GPS, RV_SUB_GPL) { isgen = true } }
    p = pm.next
  }
  if not isgen { return 0 }
  ## element type span = `[`..top-level `;`, trimmed of surrounding spaces
  mut adep := 0
  mut asemi := RV_SUB_ITS + 1
  mut ap := RV_SUB_ITS + 1
  mut ago := true
  while ago and ap < RV_SUB_ITS + RV_SUB_ITL {
    ac := str_at((src + ap), 1)
    if ac == "(" or ac == "[" { adep = adep + 1 }
    else if (ac == ")" or ac == "]") and adep > 0 { adep = adep - 1 }
    else if ac == ";" and adep == 0 { asemi = ap ; ago = false }
    ap = ap + 1
  }
  mut aes := RV_SUB_ITS + 1
  while aes < asemi and str_at((src + aes), 1) == " " { aes = aes + 1 }
  mut aet := asemi
  while aet > aes and str_at((src + aet - 1), 1) == " " { aet = aet - 1 }
  ## SCALAR element only (stride 1 word); a struct/enum element is a documented follow-up.
  if struct_decl_of(decls, src, aes, aet - aes) >= 0 { return 0 }
  if enum_decl_of(decls, src, aes, aet - aes) >= 0 { return 0 }
  1
}
## GENERICS (§8 mono): the element COUNT N of the active instance array type `[E; N]` (RV_SUB_ITS/ITL),
## for the CG-7 bounds check on a generic array param index. 0 if the instance type is not an array.
## Inline `;`-scan + digit parse over the globals (scalar return — safe in the emit path). Mirrors a64_sub_arr_len.
rv_sub_arr_len := fn(src : ptr(u8)) -> i64 {
  if str_at((src + RV_SUB_ITS), 1) != "[" { return 0 }
  mut ndep := 0
  mut nsemi := RV_SUB_ITS + 1
  mut np := RV_SUB_ITS + 1
  mut ngo := true
  while ngo and np < RV_SUB_ITS + RV_SUB_ITL {
    nc := str_at((src + np), 1)
    if nc == "(" or nc == "[" { ndep = ndep + 1 }
    else if (nc == ")" or nc == "]") and ndep > 0 { ndep = ndep - 1 }
    else if nc == ";" and ndep == 0 { nsemi = np ; ngo = false }
    np = np + 1
  }
  mut nlp := nsemi + 1
  mut nval := 0
  while nlp < RV_SUB_ITS + RV_SUB_ITL {
    nbs := bytes(str_at((src + nlp), 1))
    nb := nbs[0]
    if nb >= 48 and nb <= 57 { nval = nval * 10 + i64(nb - 48) }
    nlp = nlp + 1
  }
  nval
}
## The ELEMENT-type span of a `Slice(E)` PARAM named `[s,n)`, by scanning SOURCE forward from the param
## name (`: Slice(E)`) — the riscv64 twin of lower.al's `slice_param_elem_span` / aarch64's a64_slice_elem_span.
rv_slice_elem_span := fn(src : ptr(u8), s : usize, n : usize) -> CSpan {
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
## data ptr, word1 = runtime len), so a read double-derefs. Struct/enum element is a follow-up (false → trap).
rv_slice_param_scalar := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut p := params_head
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      es := rv_slice_elem_span(src, pm.ns, pm.nl)
      if es.n != 0 {
        if struct_decl_of(decls, src, es.s, es.n) < 0 and enum_decl_of(decls, src, es.s, es.n) < 0 { r = true }
      }
    }
    p = pm.next
  }
  r
}
## The CURRENT fn's params + decls, stashed as module globals at the top of emit_rv_fn (the RV_CHK/RV_AGG
## pattern) so the per-fn FRAME SCANNERS (rv_iter_stride / rv_arr_elem_struct_span), which take no
## params_head, can recognize a slice PARAM base — needed to size + type a struct/enum-element loop var.
mut RV_PARAMS := 0
rv_params := fn() -> ptr(mut Param) { unchecked bitcast(ptr(mut Param), RV_PARAMS) }
mut RV_DECLS := 0
rv_decls := fn() -> ptr(rt::Vec) { unchecked bitcast(ptr(rt::Vec), RV_DECLS) }
## the CURRENT fn's body head, stashed for the frame scanners (rv_val_words) whose signature omits
## body_head — needed to size a bare-Var aggregate-copy RHS `q := p` as p's local width.
mut RV_BODY := 0
rv_body := fn() -> ptr(mut Stmt) { unchecked bitcast(ptr(mut Stmt), RV_BODY) }
## --- GENERICS (§8 monomorphization on riscv64; mirror of aarch64) ------------------------------
## The instance substitution (`T`'s name span → the concrete type span) rides module globals, set
## per-instance in emit_rv_program's mono pass and read by rv_comp_cond_fold (`comptime if T == …`).
## Zero → no substitution. _2/_3 carry the 2nd/3rd type-param of a leading run (pick3(A,B,C,…)).
mut RV_SUB_GPS := 0    ## the generic type-param NAME span start …
mut RV_SUB_GPL := 0    ## … and length (0 = no active substitution)
mut RV_SUB_ITS := 0    ## the instance's concrete type span start …
mut RV_SUB_ITL := 0    ## … and length (non-zero while emitting an instance = instance mode)
mut RV_SUB_GPS2 := 0
mut RV_SUB_GPL2 := 0
mut RV_SUB_ITS2 := 0
mut RV_SUB_ITL2 := 0
mut RV_SUB_GPS3 := 0
mut RV_SUB_GPL3 := 0
mut RV_SUB_ITS3 := 0
mut RV_SUB_ITL3 := 0
## Instances RECORDED DURING EMIT at each generic call site (rv_inst_add) and consumed to emit one
## `<fn>__<tag>` body per (generic-fn, type) pair. gi = the generic decl index; ts/tl = concrete type.
mut RV_INST_GI : [usize; 512] = [0; 512]
mut RV_INST_TS : [usize; 512] = [0; 512]
mut RV_INST_TL : [usize; 512] = [0; 512]
mut RV_INST_TS2 : [usize; 512] = [0; 512]
mut RV_INST_TL2 : [usize; 512] = [0; 512]
mut RV_INST_TS3 : [usize; 512] = [0; 512]
mut RV_INST_TL3 : [usize; 512] = [0; 512]
mut RV_INST_N := 0
## The emitted FLOAT-LITERAL pool for the current program: the source offsets whose
## `.Lflt<offset>: .double <text>` cell has ALREADY been written, `RV_FLT_N` live entries.
##
## A `.Lflt` label IS its literal's source-span start — a `FloatLit` carries no separate label field
## (unlike a `StrLit`, whose label index the driver RENUMBERS per HOF clone). So when the driver's
## FN-6 §6.2 D-cap path DEEP-CLONES a higher-order fn whose body holds a float literal, the clone
## copies the span start VERBATIM (it cannot be bumped — the same offset also indexes the literal's
## decimal TEXT), and the original H and its `__hoflam<fnpos>` clone are two decls carrying the same
## offset. The rodata walk visits decls, so it wrote the cell ONCE PER DECL while every `la t0,
## .Lflt<off>` reference resolved to one name: two definitions of one symbol, which `as` refuses
## ("symbol `.Lflt<off>' is already defined"). Both loads name the SAME offset and read the SAME
## text, so ONE shared cell is correct — record each distinct offset here and emit it at most once.
## x86_64 already does this in `lower::emit_rodata_expr` (a threaded `seen` Vec); a64/rv64 derive the
## label from the same span field, which is why the SAME number duplicates on both of them.
##
## Fixed BSS array (not arena-bump) so the storage is not tied to a by-value arena copy, matching
## RV_INST_*. 1024 is far beyond any single program's distinct float literals (all of `lib/` holds
## fewer than a hundred). On overflow the cell is emitted UNCONDITIONALLY: a missing cell is an
## undefined-symbol LINK error in code that would otherwise have run, whereas the unfiltered duplicate
## is exactly the status quo — both are loud, and the loud failure that keeps working programs working
## wins.
mut RV_FLT_OFF : [usize; 1024] = [0; 1024]
mut RV_FLT_N := 0
## True when `off` has NOT been emitted yet, recording it; false when this cell is already in the pool.
rv_flt_first := fn(off : usize) -> bool {
  mut i := 0
  mut found := false
  while i < RV_FLT_N {
    if RV_FLT_OFF[i] == off { found = true }
    i = i + 1
  }
  if found { return false }
  if RV_FLT_N < 1024 {
    RV_FLT_OFF[RV_FLT_N] = off
    RV_FLT_N = RV_FLT_N + 1
  }
  return true
}
## Resolved type-arg of the current generic call (rv_resolve_typearg out-globals; no multi-word return).
mut RV_TA_S := 0
mut RV_TA_N := 0
mut RV_TA_S2 := 0
mut RV_TA_N2 := 0
mut RV_TA_S3 := 0
mut RV_TA_N3 := 0
## Comptime FIELD/VARIANT unroll context (mirror A64_CF_*; inert when *_L == 0). RV_CF_VAR = the unroll
## loop var, RV_CF_FLD = current field name, RV_CF_TY = current field type span; RV_ARM_BINDS = the
## current match arm's bind list head (for payload-binding type inference in rv_resolve_typearg).
mut RV_CFVAR_S := 0
mut RV_CFVAR_L := 0
mut RV_CF_VAR_S := 0
mut RV_CF_VAR_L := 0
mut RV_CF_FLD_S := 0
mut RV_CF_FLD_L := 0
mut RV_CF_TY_S := 0
mut RV_CF_TY_L := 0
mut RV_ARM_BINDS := 0
## The byte offset of `<f>.offset` for the ACTIVE comptime field descriptor. The field loop is
## emitted only for a concrete struct instance (`RV_SUB_*`); reuse the shared layout calculators so
## packed, standard byte-array, and ordinary word-granular structs report the same offsets as value code.
## Return -1 for a non-active/dynamic descriptor shape; the caller keeps the existing fail-loud path.
rv_cf_offset_value := fn(e : ptr(Expr), src : ptr(u8), decls : ptr(rt::Vec), a : rt::Arena) -> i64 {
  if RV_CF_VAR_L == 0 or RV_SUB_ITL == 0 { return 0 - 1 }
  match deref(e) {
    Expr::Field(base, fs, fl) => {
      if str_at((src + fs), fl) != "offset" { return 0 - 1 }
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      if bnl == 0 or not streq(src, bns, bnl, RV_CF_VAR_S, RV_CF_VAR_L) { return 0 - 1 }
      ct := base_type_name(src, RV_SUB_ITS, RV_SUB_ITL)
      if ct.n == 0 { return 0 - 1 }
      ## THE ORACLE (`lower_layout::layout_kind`) picks the tier — the same decision the value
      ## paths and the x86 dual use, so four emitters cannot drift apart on one offset.
      lk := layout_kind(decls, src, ct.s, ct.n, a)
      if layout_kind_is_packed(lk) { return packed_field_byte_offset(decls, src, ct.s, ct.n, RV_CF_FLD_S, RV_CF_FLD_L, a) }
      if layout_kind_is_byte(lk) { return standard_field_byte_offset(decls, src, ct.s, ct.n, RV_CF_FLD_S, RV_CF_FLD_L, a) }
      fwo := field_word_offset(decls, src, ct.s, ct.n, RV_CF_FLD_S, RV_CF_FLD_L, a)
      if fwo >= 0 { return fwo * 8 }
      return 0 - 1
    }
    _ => { return 0 - 1 }
  }
}

rv_field_base := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(e) { Expr::Field(fb, ffs, ffl) => { r = fb } _ => {} }
  r
}
rv_field_fns := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::Field(fb, ffs, ffl) => { r = ffs } _ => {} }
  r
}
rv_field_fnl := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::Field(fb, ffs, ffl) => { r = ffl } _ => {} }
  r
}
## The generic type-param's NAME span (the `T` of `T : type`), 0/0 if `d` has none.
rv_tparam_name := fn(d : Decl, src : ptr(u8)) -> CSpan {
  mut p := d.params_head
  mut r := CSpan(s = 0, n = 0)
  while p != 0 { pm := deref(param_p(p)) ; if r.n == 0 and str_at((src + pm.ts), pm.tl) == "type" { r = CSpan(s = pm.ns, n = pm.nl) } ; p = pm.next }
  r
}
## Resolve the concrete type-arg span of a generic call into RV_TA_S/RV_TA_N (0/0 = unresolved → the
## caller uses the fail-loud stub). EXPLICIT: arg 0 (bare type name) when argc == arity. IMPLICIT:
## inferred from the value arg whose param is the type-param (a Var naming an enclosing PARAM / a struct
## / enum literal / a match-arm payload binding). Writes globals (no multi-word return). Tuple/array
## type-args are DEFERRED (rejected → fail-loud), matching the a64 slice at its introduction.
rv_resolve_typearg := fn(decls : ptr(rt::Vec), src : ptr(u8), gi : i64, args_head : ptr(mut Arg), penv : ptr(mut Param), a : rt::Arena) {
  gd := deref(decl_get(decls, usize(gi)))
  argc := arg_list_count(args_head, a)
  mut ts := 0
  mut tl := 0
  if argc == i64(gd.arity) {
    ## EXPLICIT type-arg — at the type-param's source position.
    tpp := decl_tparam_pos(gd, src)
    ea := arg_expr_at(args_head, usize(tpp), a)
    ts = ex_var_ns(ea)
    tl = ex_var_nl(ea)
    ## a TUPLE `(T0, …)` / ARRAY `[E; N]` type-arg parses as an ArrayLit (not a Var) — recover its full
    ## source span (mono keys + the tag mangling both read it). Mirrors x86 type_arg_at.
    if tl == 0 {
      tt := tuple_typearg_span(ea, src, a)
      ts = tt.s
      tl = tt.n
    }
    ## `f.type` (§8 field-derive) — the type-arg is `Field(Var(f), "type")` where `f` is the active
    ## comptime field-unroll loop var (RV_CF_VAR set): resolve to the CURRENT field's TYPE (RV_CF_TY).
    if tl == 0 and RV_CF_VAR_L != 0 and ex_is_field(ea) {
      cfb := rv_field_base(ea)
      cfbs := ex_var_ns(cfb)
      cfbl := ex_var_nl(cfb)
      cffs := rv_field_fns(ea)
      cffl := rv_field_fnl(ea)
      if cfbl != 0 and streq(src, cfbs, cfbl, RV_CF_VAR_S, RV_CF_VAR_L) and str_at((src + cffs), cffl) == "type" {
        ts = RV_CF_TY_S
        tl = RV_CF_TY_L
      }
    }
  } else {
    ## IMPLICIT type-arg: infer from the VALUE arg whose param is declared as the type-param `T`.
    tpn := rv_tparam_name(gd, src)
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
    if tl == 0 and rv_is_slit(a0) { ts = rv_slit_ns(a0) ; tl = rv_slit_nl(a0) }
    if tl == 0 and rv_is_elit(a0) { ts = rv_elit_ens(a0) ; tl = rv_elit_enl(a0) }
    ## a Var naming the CURRENT match arm's SINGLE payload BINDING: infer T from the variant's payload type.
    if tl == 0 and vnl != 0 and RV_ARM_ENL != 0 and RV_ARM_BINDS != 0 {
      bh := unchecked bitcast(ptr(mut Bind), RV_ARM_BINDS)
      bidx := bind_list_index(bh, src, vns, vnl, a)
      mut bcnt := 0
      mut bb := bh
      while unchecked bitcast(usize, bb) != 0 { bcnt = bcnt + 1 ; bb = bnd_next(bb) }
      if bidx == 0 and bcnt == 1 {
        pty := variant_payload_type(decls, src, RV_ARM_ENS, RV_ARM_ENL, RV_ARM_VS, RV_ARM_VL, a)
        if pty.n != 0 { ts = pty.s ; tl = pty.n }
      }
    }
  }
  if RV_SUB_GPL != 0 and tl != 0 and streq(src, ts, tl, RV_SUB_GPS, RV_SUB_GPL) { ts = RV_SUB_ITS ; tl = RV_SUB_ITL }
  RV_TA_S = ts
  RV_TA_N = tl
  ## MULTI type-param (leading RUN): resolve the 2nd/3rd EXPLICIT type-args (bare scalar names).
  RV_TA_S2 = 0
  RV_TA_N2 = 0
  RV_TA_S3 = 0
  RV_TA_N3 = 0
  lead := decl_leading_tparam_run(gd, src)
  cntt := decl_tparam_count(gd, src)
  if argc == i64(gd.arity) and cntt == lead and lead >= 2 {
    e1 := arg_expr_at(args_head, 1, a)
    mut s2 := ex_var_ns(e1)
    mut l2 := ex_var_nl(e1)
    if RV_SUB_GPL != 0 and l2 != 0 and streq(src, s2, l2, RV_SUB_GPS, RV_SUB_GPL) { s2 = RV_SUB_ITS ; l2 = RV_SUB_ITL }
    RV_TA_S2 = s2
    RV_TA_N2 = l2
  }
  if argc == i64(gd.arity) and cntt == lead and lead >= 3 {
    e2 := arg_expr_at(args_head, 2, a)
    mut s3 := ex_var_ns(e2)
    mut l3 := ex_var_nl(e2)
    if RV_SUB_GPL != 0 and l3 != 0 and streq(src, s3, l3, RV_SUB_GPS, RV_SUB_GPL) { s3 = RV_SUB_ITS ; l3 = RV_SUB_ITL }
    RV_TA_S3 = s3
    RV_TA_N3 = l3
  }
}
## Record instance (gi, ts, tl + the 2nd/3rd type-args from RV_TA_*2/*3) if new (dedup by gi + all
## type-arg text). Bounded by the array size.
rv_inst_add := fn(src : ptr(u8), gi : usize, ts : usize, tl : usize) {
  mut i := 0
  mut found := false
  while i < RV_INST_N {
    same0 := RV_INST_GI[i] == gi and streq(src, RV_INST_TS[i], RV_INST_TL[i], ts, tl)
    same2 := streq(src, RV_INST_TS2[i], RV_INST_TL2[i], RV_TA_S2, RV_TA_N2)
    same3 := streq(src, RV_INST_TS3[i], RV_INST_TL3[i], RV_TA_S3, RV_TA_N3)
    if same0 and same2 and same3 { found = true }
    i = i + 1
  }
  if (not found) and RV_INST_N < 512 {
    RV_INST_GI[RV_INST_N] = gi
    RV_INST_TS[RV_INST_N] = ts
    RV_INST_TL[RV_INST_N] = tl
    RV_INST_TS2[RV_INST_N] = RV_TA_S2
    RV_INST_TL2[RV_INST_N] = RV_TA_N2
    RV_INST_TS3[RV_INST_N] = RV_TA_S3
    RV_INST_TL3[RV_INST_N] = RV_TA_N3
    RV_INST_N = RV_INST_N + 1
  }
}
## The element-type span E of the `Slice(E)` PARAM `[ns,nl]`, or {0,0}.
rv_slice_param_elem_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize) -> CSpan {
  mut p := params_head
  mut r := CSpan(s = 0, n = 0)
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { r = rv_slice_elem_span(src, pm.ns, pm.nl) }
    p = pm.next
  }
  r
}
## Element WORD stride of the `Slice(E)` PARAM `[ns,nl]`: struct_words for struct E, 1+enum_max_arity for
## enum E, else 0 (not an aggregate slice param).
rv_slice_param_agg_stride := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  es := rv_slice_param_elem_span(params_head, src, ns, nl)
  mut r := 0
  if es.n != 0 {
    if struct_decl_of(decls, src, es.s, es.n) >= 0 { r = i64(struct_words(decls, src, es.s, es.n, a)) }
    if enum_decl_of(decls, src, es.s, es.n) >= 0 { r = 1 + i64(enum_max_arity(decls, src, es.s, es.n, a)) }
  }
  r
}
## Element STRUCT span of the `Slice(P)` PARAM `[ns,nl]` (P a struct), else {0,0}.
rv_slice_param_struct_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> CSpan {
  es := rv_slice_param_elem_span(params_head, src, ns, nl)
  mut r := CSpan(s = 0, n = 0)
  if es.n != 0 { if struct_decl_of(decls, src, es.s, es.n) >= 0 { r = es } }
  r
}
## Element ENUM span of the `Slice(E)` PARAM `[ns,nl]` (E an enum), else {0,0}.
rv_slice_param_enum_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> CSpan {
  es := rv_slice_param_elem_span(params_head, src, ns, nl)
  mut r := CSpan(s = 0, n = 0)
  if es.n != 0 { if enum_decl_of(decls, src, es.s, es.n) >= 0 { r = es } }
  r
}

## Is the `.len()` receiver a slice this backend can read — a scalar `Slice(E)` PARAM or a local slice VIEW?
rv_len_recv_slice := fn(recv : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), body_head : ptr(mut Stmt), decls : ptr(rt::Vec), a : rt::Arena) -> bool {
  rns := ex_var_ns(recv)
  rnl := ex_var_nl(recv)
  mut r := false
  if rnl != 0 {
    if rv_slice_param_scalar(params_head, src, rns, rnl, a, decls) { r = true }
    if rv_is_slice_local(body_head, src, rns, rnl, a) { r = true }
  }
  r
}
rv_struct_all_scalar := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
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
    ## (which would emit a scalar `ebreak`). subst changes the span ONLY for an aggregate type-arg; a scalar
    ## type-arg / a plain (non-generic) / a comptime-value type-fn stay put → byte-identical everywhere else.
    ft := field_type_span(decls, src, s, n, fd.ns, fd.nl, a)
    changed := ft.n != 0 and (ft.s != fd.ts or ft.n != fd.tl)
    if changed { ok = false }
    if (not changed) and field_words(decls, src, fd.ts, fd.tl, fd.wsize, a) != 1 { ok = false }
    f = fd.next
  }
  ok
}
## Is field `[fs,fl]` of struct `[s,n]` SCALAR (one word, via the field's CACHED wsize)? Lets a scalar
## field of a struct that ALSO has an aggregate field (`s.n` where `S = { c : Col, n : u64 }`) read/write
## at its layout word offset while a non-scalar field stays unhandled.
## The word count of a struct `[s,n]` eligible for the register struct-return ABI (word k → a_k): a PLAIN
## (arity-0) struct of 1..8 words, else 0. The arity-0 gate excludes a comptime-VALUE-param type-fn like
## `uint(N)` (its layout would need a binding the rv path lacks → PANIC) and a generic type-fn (`Box(T)`);
## a plain struct — INCLUDING one with an enum/str field (delivery is a type-agnostic word copy, not
## all-scalar) — resolves safely. Replaces the earlier rv_struct_all_scalar gate on the struct-return ABI.
rv_ret_struct_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  if unchecked bitcast(usize, d.params_head) != 0 { return 0 }
  w := i64(struct_words(decls, src, s, n, a))
  if w >= 1 and w <= 8 { return w }
  0
}
## The word count of a PLAIN struct `[s,n]` returned via the RISC-V LP64 INDIRECT RESULT (SRET): a plain
## (arity-0) struct WIDER than the 8-word register-return budget → its word count, else 0. Disjoint by
## construction from rv_ret_struct_words (1..8 words), so at most one return convention fires per type.
## The arity-0 gate keeps a comptime-value-param / generic type-fn out (its layout needs a binding the rv
## path lacks). LP64: the caller passes the destination address in a0 (the implicit first argument), the
## real arguments shift to a1..a7, and the callee writes the aggregate through that pointer.
rv_ret_sret_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> i64 {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  if unchecked bitcast(usize, d.params_head) != 0 { return 0 }
  w := i64(struct_words(decls, src, s, n, a))
  if w > 8 { return w }
  0
}
## The full {disc, payload…} word count of an ENUM `[s,n]` returned via the LP64 INDIRECT RESULT (SRET) —
## the enum analogue of rv_ret_sret_words: 1 + max_arity when `[s,n]` names an enum decl AND the total width
## EXCEEDS the 8-word register enum-return budget, else 0. A ≤8-word enum keeps the register convention
## (RV_RET_ENUM, word 0 = disc → a0); a wider one is delivered through the a0 result pointer like a wide
## struct. Disjoint by construction from rv_ret_struct_words / rv_ret_sret_words (both struct-only).
rv_ret_enum_sret_words := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> i64 {
  if enum_decl_of(decls, src, s, n) < 0 { return 0 }
  w := 1 + i64(enum_max_arity(decls, src, s, n, a))
  if w > 8 { return w }
  0
}
rv_field_is_scalar := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> bool {
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

## STANDARD BYTE-LAYOUT PLACE RESOLUTION (CLAYOUT S3a). A standard-byte struct local remains an
## inline frame value on RV64; only the FIELD offsets change from words to bytes. Keep this tier narrow:
## a plain local root followed by FIELD hops, with no params/globals/indexes. Other shapes retain their
## existing fail-loud paths.
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
rv_std_path_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if ex_is_field(e) {
    base := rv_field_base(e)
    bt := rv_std_path_ty(base, body_head, src, a, decls)
    if bt.n != 0 { r = field_type_span(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) }
  }
  if not ex_is_field(e) {
    ns := ex_var_ns(e)
    nl := ex_var_nl(e)
    if nl != 0 {
      rs := rv_local_struct_ns(body_head, src, ns, nl, a)
      rn := rv_local_struct_nl(body_head, src, ns, nl, a)
      if rn != 0 and layout_kind_is_byte(layout_kind(decls, src, rs, rn, a)) { r = CSpan(s = rs, n = rn) }
    }
  }
  r
}

rv_std_path_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_field(e) { return false }
  base := rv_field_base(e)
  bt := rv_std_path_ty(base, body_head, src, a, decls)
  if bt.n == 0 { return false }
  layout_field_offset_bytes(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) >= 0
}

rv_std_path_bo := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not rv_std_path_ok(e, body_head, src, a, decls) { return 0 - 1 }
  base := rv_field_base(e)
  mut pbo := i64(0)
  if ex_is_field(base) { pbo = rv_std_path_bo(base, body_head, src, a, decls) }
  bt := rv_std_path_ty(base, body_head, src, a, decls)
  pbo + layout_field_offset_bytes(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a)
}

rv_std_path_root_off := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not rv_std_path_ok(e, body_head, src, a, decls) { return 0 - 1 }
  base := rv_field_base(e)
  if ex_is_field(base) { return rv_std_path_root_off(base, body_head, src, pcount, a, decls) }
  rv_local_off(body_head, src, ex_var_ns(base), ex_var_nl(base), pcount, a, decls)
}

## PARAMETER twin of the standard-byte path. RV64 struct parameters are passed by reference, with the
## frame slot holding the caller's byte-image address. Keep the parameter resolver separate from the
## local-only path so only the S3(e) byte-tier consumer widens; packed, word-tier and unsupported shapes
## retain their existing fail-loud routes.
rv_std_param_path_ty := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if ex_is_field(e) {
    base := rv_field_base(e)
    bt := rv_std_param_path_ty(base, params_head, src, a, decls)
    if bt.n != 0 { r = field_type_span(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) }
  }
  if not ex_is_field(e) {
    ns := ex_var_ns(e)
    nl := ex_var_nl(e)
    pidx := rv_param_find(params_head, src, ns, nl, a)
    if pidx >= 0 {
      rs := rv_param_struct_ns(params_head, src, ns, nl, a, decls)
      rn := rv_param_struct_nl(params_head, src, ns, nl, a, decls)
      if rn != 0 and layout_kind_is_byte(layout_kind(decls, src, rs, rn, a)) { r = CSpan(s = rs, n = rn) }
    }
  }
  r
}

rv_std_param_path_ok := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_field(e) { return false }
  base := rv_field_base(e)
  bt := rv_std_param_path_ty(base, params_head, src, a, decls)
  if bt.n == 0 { return false }
  layout_field_offset_bytes(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) >= 0
}

rv_std_param_path_bo := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not rv_std_param_path_ok(e, params_head, src, a, decls) { return 0 - 1 }
  base := rv_field_base(e)
  mut pbo := i64(0)
  if ex_is_field(base) { pbo = rv_std_param_path_bo(base, params_head, src, a, decls) }
  bt := rv_std_param_path_ty(base, params_head, src, a, decls)
  pbo + layout_field_offset_bytes(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a)
}

rv_std_param_path_idx := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not rv_std_param_path_ok(e, params_head, src, a, decls) { return 0 - 1 }
  base := rv_field_base(e)
  if ex_is_field(base) { return rv_std_param_path_idx(base, params_head, src, a, decls) }
  rv_param_find(params_head, src, ex_var_ns(base), ex_var_nl(base), a)
}

## STANDARD BYTE-LAYOUT ARRAY-ELEMENT PATH (CLAYOUT S3(d)). The root is an INDEX of a
## byte-tier struct array, followed by zero or more FIELD hops. The runtime element base is resolved
## separately from the cumulative field byte offset so the historical word-tier place path stays intact.
rv_std_idx_path_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if ex_is_index(e) {
    bt := rv_place_ty(ex_index_base(e), body_head, src, a, decls)
    if bt.n != 0 {
      et := rv_arrty_elem(src, bt.s, bt.n)
      if et.n != 0 and std_array_elem_byte_tier(decls, src, et.s, et.n, a) { r = et }
    }
    return r
  }
  if ex_is_field(e) {
    base := rv_field_base(e)
    bt := rv_std_idx_path_ty(base, body_head, src, a, decls)
    if bt.n != 0 {
      bo := layout_field_offset_bytes(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a)
      if bo >= 0 { r = field_type_span(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) }
    }
  }
  r
}

rv_std_idx_path_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_index(e) and not ex_is_field(e) { return false }
  rv_std_idx_path_ty(e, body_head, src, a, decls).n != 0
}

rv_std_idx_path_bo := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not rv_std_idx_path_ok(e, body_head, src, a, decls) { return 0 - 1 }
  if ex_is_index(e) { return 0 }
  base := rv_field_base(e)
  bt := rv_std_idx_path_ty(base, body_head, src, a, decls)
  rv_std_idx_path_bo(base, body_head, src, a, decls) + layout_field_offset_bytes(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a)
}

rv_std_idx_root_arr := fn(e : ptr(Expr)) -> ptr(Expr) {
  if ex_is_index(e) { return ex_index_base(e) }
  if ex_is_field(e) { return rv_std_idx_root_arr(rv_field_base(e)) }
  unchecked bitcast(ptr(Expr), 0)
}

rv_std_idx_root_idx := fn(e : ptr(Expr)) -> ptr(Expr) {
  if ex_is_index(e) { return ex_index_idx(e) }
  if ex_is_field(e) { return rv_std_idx_root_idx(rv_field_base(e)) }
  unchecked bitcast(ptr(Expr), 0)
}


rv_std_store_scalar := fn(off : i64, width : usize, in out sb : rt::StrBuf) {
  if width == 1 { push_str(sb, "  sb a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 2 { push_str(sb, "  sh a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 4 { push_str(sb, "  sw a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 8 { push_str(sb, "  sd a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "  ebreak # unsupported standard scalar width\n") }
}

## The WIDTH-based core of the standard-byte scalar load. CLAYOUT S3(c) needs it: the shared copy
## plan (`layout_copy_step`) carries a width + signedness, not a type span, because the plan is computed
## once in `lower_layout` for all four backends.
rv_std_load_width := fn(off : i64, width : usize, signed : bool, in out sb : rt::StrBuf) {
  if width == 1 and signed { push_str(sb, "  lb a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 1 and (not signed) { push_str(sb, "  lbu a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 2 and signed { push_str(sb, "  lh a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 2 and (not signed) { push_str(sb, "  lhu a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 4 and signed { push_str(sb, "  lw a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 4 and (not signed) { push_str(sb, "  lwu a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width == 8 { push_str(sb, "  ld a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "  ebreak # unsupported standard scalar width\n") }
}

rv_std_load_scalar := fn(off : i64, ts : usize, tl : usize, in out sb : rt::StrBuf, src : ptr(u8)) {
  width := scalar_byte_size(src, ts, tl)
  signed := tl != 0 and str_at((src + ts), 1) == "i"
  rv_std_load_width(off, width, signed, sb)
}

## Pointer-relative scalar load for a composed array-element place. The place resolver leaves the byte
## address in a0; the destination may be a0 as well, so no scratch register or frame offset is needed.
rv_std_load_width_a0 := fn(width : usize, signed : bool, in out sb : rt::StrBuf) {
  if width == 1 and signed { push_str(sb, "  lb a0, 0(a0)\n") }
  if width == 1 and (not signed) { push_str(sb, "  lbu a0, 0(a0)\n") }
  if width == 2 and signed { push_str(sb, "  lh a0, 0(a0)\n") }
  if width == 2 and (not signed) { push_str(sb, "  lhu a0, 0(a0)\n") }
  if width == 4 and signed { push_str(sb, "  lw a0, 0(a0)\n") }
  if width == 4 and (not signed) { push_str(sb, "  lwu a0, 0(a0)\n") }
  if width == 8 { push_str(sb, "  ld a0, 0(a0)\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "  ebreak # unsupported standard scalar width at place\n") }
}

## CLAYOUT S3(c) — THE ONE BYTE-PRECISE WHOLE-VALUE COPIER, riscv64's spelling. `soff` is the
## child's §6.1 byte offset inside the frame (ascending from s0), `doff` the destination local's own
## frame offset; the destination's word `w` is at `doff + w*8`, its byte `k` at `doff + k`. WHICH of the
## two it is read at is decided by `std_copy_kind` in `lower_layout`, shared with the other three
## backends. A word-granular child never reaches here — its word copy IS its byte copy.
rv_std_copy := fn(ts : usize, tl : usize, soff : i64, doff : i64, in out sb : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) {
  ck := std_copy_kind(decls, src, ts, tl, a)
  if ck == 0 { push_str(sb, "  ebreak # whole-value copy outside the byte-precise copier's domain\n") }
  if ck == 1 {
    nb := i64(std_copy_image_bytes(decls, src, ts, tl, a))
    mut k := i64(0)
    while k < nb {
      push_str(sb, "  lbu a0, ") ; push_int(sb, soff + k) ; push_str(sb, "(s0)\n")
      push_str(sb, "  sb a0, ") ; push_int(sb, doff + k) ; push_str(sb, "(s0)\n")
      k = k + 1
    }
  }
  if ck == 2 {
    ns := i64(layout_copy_nsteps(decls, src, ts, tl, a))
    mut i := i64(0)
    while i < ns {
      st := layout_copy_step(decls, src, ts, tl, i, a)
      if st.found { rv_std_load_width(soff + st.sbo, st.sz, st.signed, sb) }
      if st.found { push_str(sb, "  sd a0, ") ; push_int(sb, doff + st.dwo * 8) ; push_str(sb, "(s0)\n") }
      if not st.found { push_str(sb, "  ebreak # byte-precise copy plan shorter than its own step count\n") }
      i = i + 1
    }
  }
}

## Recursive constructor writer for a standard-byte struct local. Direct byte arrays are stored one byte
## at a time; nested word-granular structs retain their own natural word fields at the containing byte
## offset. Whole-value copies stay on the existing word-copy path once their byte offset is aligned.
rv_std_store_value := fn(pe : ptr(Expr), off : i64, ts : usize, tl : usize, wsize : usize, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  es := rv_arrty_elem(src, ts, tl)
  if es.n != 0 {
    mut bytearr := false
    if scalar_byte_size(src, es.s, es.n) == 1 { bytearr = true }
    if bytearr and ex_is_array_lit(pe) {
      mut g := ex_array_lit_ehead(pe)
      mut k := i64(0)
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  sb a0, ") ; push_int(sb, off + k) ; push_str(sb, "(s0)\n")
        k = k + 1
        g = ga.next
      }
      return k
    }
    push_str(sb, "  ebreak # unsupported standard array field construction\n")
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
    if rv_is_slit(pe) and std_struct_is_byte_writable(decls, src, ts, tl, a) { return rv_std_store_struct(pe, off, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    push_str(sb, "  ebreak # unsupported standard aggregate field construction\n")
    return i64(struct_words(decls, src, ts, tl, a))
  }
  emit_rv_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  rv_std_store_scalar(off, scalar_byte_size(src, ts, tl), sb)
  i64(standard_type_byte_size(decls, src, ts, tl, wsize, a))
}

rv_std_store_struct := fn(pe : ptr(Expr), off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  sns := rv_slit_ns(pe)
  snl := rv_slit_nl(pe)
  di := struct_decl_of(decls, src, sns, snl)
  if di < 0 { push_str(sb, "  ebreak # unknown standard struct literal\n") ; return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut g := ex_struct_lit_args(pe)
  while f != 0 and g != 0 {
    fd := deref(fld_p(f))
    ga := deref(arg_p(g))
    bo := standard_field_byte_offset(decls, src, sns, snl, fd.ns, fd.nl, a)
    ft := field_type_span(decls, src, sns, snl, fd.ns, fd.nl, a)
    if bo >= 0 and ft.n != 0 { _sw := rv_std_store_value(ga.e, off + bo, ft.s, ft.n, fd.wsize, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    if bo < 0 or ft.n == 0 { push_str(sb, "  ebreak # unresolved standard struct field\n") }
    f = fd.next
    g = ga.next
  }
  i64(standard_type_byte_size(decls, src, sns, snl, 1, a))
}

## Pointer-relative counterpart of the standard-byte literal writer. The element base is kept at 0(sp)
## while each literal expression is emitted. This is intentionally used only for a byte-tier array
## element whole-assignment; the established frame-relative writer above remains unchanged.
rv_std_store_value_atptr := fn(pe : ptr(Expr), off : i64, ts : usize, tl : usize, wsize : usize, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  es := rv_arrty_elem(src, ts, tl)
  if es.n != 0 {
    if scalar_byte_size(src, es.s, es.n) == 1 and ex_is_array_lit(pe) {
      mut g := ex_array_lit_ehead(pe)
      mut k := i64(0)
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  ld a1, 0(sp)\n  sb a0, ") ; push_int(sb, off + k) ; push_str(sb, "(a1)\n")
        k = k + 1
        g = ga.next
      }
      return k
    }
    push_str(sb, "  ebreak # unsupported byte-tier array field construction at pointer\n")
    return i64(wsize)
  }
  bn := base_type_name(src, ts, tl)
  if struct_decl_of(decls, src, bn.s, bn.n) >= 0 {
    if rv_is_slit(pe) and std_struct_is_byte_writable(decls, src, ts, tl, a) { return rv_std_store_struct_atptr(pe, off, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    push_str(sb, "  ebreak # unsupported byte-tier aggregate construction at pointer\n")
    return i64(wsize)
  }
  emit_rv_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "  ld a1, 0(sp)\n")
  width := scalar_byte_size(src, ts, tl)
  if width == 1 { push_str(sb, "  sb a0, ") ; push_int(sb, off) ; push_str(sb, "(a1)\n") }
  if width == 2 { push_str(sb, "  sh a0, ") ; push_int(sb, off) ; push_str(sb, "(a1)\n") }
  if width == 4 { push_str(sb, "  sw a0, ") ; push_int(sb, off) ; push_str(sb, "(a1)\n") }
  if width == 8 { push_str(sb, "  sd a0, ") ; push_int(sb, off) ; push_str(sb, "(a1)\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "  ebreak # unsupported byte-tier scalar width at pointer\n") }
  i64(standard_type_byte_size(decls, src, ts, tl, wsize, a))
}

rv_std_store_struct_atptr := fn(pe : ptr(Expr), off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  sns := rv_slit_ns(pe)
  snl := rv_slit_nl(pe)
  di := struct_decl_of(decls, src, sns, snl)
  if di < 0 { push_str(sb, "  ebreak # unknown byte-tier struct literal at pointer\n") ; return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut g := ex_struct_lit_args(pe)
  while f != 0 and g != 0 {
    fd := deref(fld_p(f))
    ga := deref(arg_p(g))
    bo := standard_field_byte_offset(decls, src, sns, snl, fd.ns, fd.nl, a)
    ft := field_type_span(decls, src, sns, snl, fd.ns, fd.nl, a)
    if bo >= 0 and ft.n != 0 { _sw := rv_std_store_value_atptr(ga.e, off + bo, ft.s, ft.n, fd.wsize, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    if bo < 0 or ft.n == 0 { push_str(sb, "  ebreak # unresolved byte-tier field at pointer\n") }
    f = fd.next
    g = ga.next
  }
  i64(standard_type_byte_size(decls, src, sns, snl, 1, a))
}
## --- enum accessors (mirror aarch64; separate usize returns) ---
rv_is_elit := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) { Expr::EnumLit(es, en, vs, vn, nf, ah) => { r = true } _ => {} }
  r
}
rv_elit_ens := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::EnumLit(es, en, vs, vn, nf, ah) => { r = es } _ => {} }
  r
}
rv_elit_enl := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::EnumLit(es, en, vs, vn, nf, ah) => { r = en } _ => {} }
  r
}
rv_elit_vns := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::EnumLit(es, en, vs, vn, nf, ah) => { r = vs } _ => {} }
  r
}
rv_elit_vnl := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::EnumLit(es, en, vs, vn, nf, ah) => { r = vn } _ => {} }
  r
}
rv_local_enum_ns := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := head
  mut rs := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and rv_is_elit(v) { rs = rv_elit_ens(v) ; done = true }
        ## a local bound to an enum-RETURNING CALL takes the callee's returned enum type (§8 piece 3).
        if streq(src, ans, anl, ns, nl) and (not done) { cre := rv_call_ret_enum_span(v, rv_decls(), src, a) ; if cre.n != 0 { rs = cre.s ; done = true } }
        ## a local bound to a WIDE-enum-RETURNING CALL (> 8 words, a0 SRET) takes the callee's enum type too.
        if streq(src, ans, anl, ns, nl) and (not done) { cres := rv_call_ret_enum_sret_span(v, rv_decls(), src, a) ; if cres.n != 0 { rs = cres.s ; done = true } }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
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
rv_local_enum_nl := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := head
  mut rn := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and rv_is_elit(v) { rn = rv_elit_enl(v) ; done = true }
        if streq(src, ans, anl, ns, nl) and (not done) { cre := rv_call_ret_enum_span(v, rv_decls(), src, a) ; if cre.n != 0 { rn = cre.n ; done = true } }
        ## a local bound to a WIDE-enum-RETURNING CALL (> 8 words, a0 SRET) takes the callee's enum width too.
        if streq(src, ans, anl, ns, nl) and (not done) { cres := rv_call_ret_enum_sret_span(v, rv_decls(), src, a) ; if cres.n != 0 { rn = cres.n ; done = true } }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
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
## The enum-type name (start / len) of an enum-typed PARAM `[ns,nl]` (T names an enum decl), else 0/0. An
## enum param is passed BY REFERENCE (slot holds the base address of the {disc, payload…} block); a
## `match <param>` derefs it (§8 piece 3).
rv_param_enum_ns := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> usize {
  mut p := params_head
  mut rs := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      ## GENERICS (§8): substitute the type-param with the instance type so a `v : T` ENUM param is
      ## recognized (in-instance only). base_type_name strips a generic application (`Opt(T)` → `Opt`).
      mut ets := pm.ts
      mut etl := pm.tl
      if RV_SUB_GPL != 0 { if streq(src, pm.ts, pm.tl, RV_SUB_GPS, RV_SUB_GPL) { ets = RV_SUB_ITS ; etl = RV_SUB_ITL } }
      bt := base_type_name(src, ets, etl)
      if enum_decl_of(decls, src, bt.s, bt.n) >= 0 { rs = bt.s }
    }
    p = pm.next
  }
  rs
}
rv_param_enum_nl := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> usize {
  mut p := params_head
  mut rn := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      mut ets := pm.ts
      mut etl := pm.tl
      if RV_SUB_GPL != 0 { if streq(src, pm.ts, pm.tl, RV_SUB_GPS, RV_SUB_GPL) { ets = RV_SUB_ITS ; etl = RV_SUB_ITL } }
      bt := base_type_name(src, ets, etl)
      if enum_decl_of(decls, src, bt.s, bt.n) >= 0 { rn = bt.n }
    }
    p = pm.next
  }
  rn
}
## Are ALL payload args of an EnumLit `v` single-word scalars (not a struct/enum/str literal)? Gates the
## by-reference enum-value materialization (piece 3) to the scalar-payload case.
rv_elit_payload_scalar := fn(v : ptr(Expr)) -> bool {
  mut g := ex_enum_lit_args(v)
  mut ok := true
  while g != 0 { ga := deref(arg_p(g)) ; if rv_is_slit(ga.e) or rv_is_elit(ga.e) or rv_is_strlit(ga.e) { ok = false } ; g = ga.next }
  ok
}

rv_alit_nel := fn(v : ptr(Expr)) -> i64 {
  mut r := 0
  match deref(v) { Expr::ArrayLit(al_n, al_e) => { r = i64(al_n) } _ => {} }
  r
}
## Tuple return types are balanced `(T0, …)` spans, not named structs.  The x86 lower owns the
## canonical tuple machinery; RV64 only needs the component count to select its register ABI.
rv_fn_returns_tuple := fn(d : Decl, src : ptr(u8)) -> bool {
  if d.ret_tl == 0 { return false }
  str_at((src + d.ret_ts), 1) == "("
}
rv_tuple_words := fn(src : ptr(u8), ts : usize, tl : usize) -> i64 {
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
rv_is_slice_local := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  mut r := false
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { if ex_is_slice(v) { r = true } }
      _ => {}
    }
  }
  r
}
rv_is_array_local := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  mut r := false
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if ex_is_array_lit(v) { r = true }
        if (not r) and rv_call_ret_struct_span(v, rv_decls(), src, a).n != 0 { r = true }
        ## `mut xs : [E; N]` — an explicitly UNINITIALIZED fixed-array local. The parser plants a Num(0)
        ## sentinel, so its array-ness lives only in the source annotation (rv_ann_arr_nel).
        if (not r) and rv_ann_arr_nel(src, ans, anl, v) > 0 { r = true }
      }
      _ => {}
    }
  }
  r
}

## The element COUNT of the array LOCAL `[ns,nl]` (its first `:=` ArrayLit length), 0 if none — the
## static bound for a `verify.checked` index guard (riscv64 analogue of x86_64's `ent.snl`). Same scan
## shape as `rv_is_array_local`.
rv_array_nel := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> i64 {
  mut s := head
  mut r := 0
  mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and ex_is_array_lit(v) { r = rv_alit_nel(v) ; done = true }
        if streq(src, ans, anl, ns, nl) and (not done) {
          cr := rv_call_ret_struct_span(v, rv_decls(), src, a)
          if cr.n != 0 and str_at((src + cr.s), 1) == "(" { r = rv_tuple_words(src, cr.s, cr.n) ; done = true }
        }
        ## `mut xs : [E; N]` — the UNINITIALIZED form: the static bound comes from the annotation.
        if streq(src, ans, anl, ns, nl) and (not done) {
          an := rv_ann_arr_nel(src, ans, anl, v)
          if an > 0 { r = an ; done = true }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
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

## Element WORD stride of an ARRAY-LIT `v`: struct_words for a StructLit first element, 1+enum_max_arity
## for an EnumLit first element, else 1 (scalar). Drives multi-word aggregate-array LAYOUT + iteration —
## the riscv64 dual of x86_64's `ent.estride`. An empty array-lit → 1 (scalar-neutral).
rv_alit_stride := fn(v : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut w := 1
  eh := ex_array_lit_ehead(v)
  if eh != 0 {
    a0 := deref(arg_p(eh))
    e0 := a0.e
    if rv_is_slit(e0) {
      if std_array_elem_byte_tier(decls, src, rv_slit_ns(e0), rv_slit_nl(e0), a) { w = i64(array_elem_word_reservation(decls, src, rv_slit_ns(e0), rv_slit_nl(e0), a)) }
      if not std_array_elem_byte_tier(decls, src, rv_slit_ns(e0), rv_slit_nl(e0), a) { require_no_byte_layout_array_elem(decls, src, rv_slit_ns(e0), rv_slit_nl(e0), a) ; w = i64(struct_words(decls, src, rv_slit_ns(e0), rv_slit_nl(e0), a)) }
    }
    if rv_is_elit(e0) { w = 1 + i64(enum_max_arity(decls, src, rv_elit_ens(e0), rv_elit_enl(e0), a)) }
  }
  w
}
## The element STRUCT span (ns,nl) of the array LOCAL `[ns,nl]` — its first ArrayLit element's StructLit
## name — or {0,0}. Types an aggregate for-loop var so `p.field` reads resolve through the element struct.
rv_arr_elem_struct_span := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> CSpan {
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
            if eh != 0 { a0 := deref(arg_p(eh)) ; e0 := a0.e ; if rv_is_slit(e0) { r = CSpan(s = rv_slit_ns(e0), n = rv_slit_nl(e0)) } }
            done = true
          }
          ## a range-slice VIEW `s := base[lo..hi]` inherits its element struct from the base ARRAY.
          if ex_is_slice(v) {
            sb2 := ex_slice_base(v)
            r = rv_arr_elem_struct_span(head, src, ex_var_ns(sb2), ex_var_nl(sb2), a)
            done = true
          }
          ## `mut xs : [E; N]` — the UNINITIALIZED form: the element struct comes from the annotation.
          ## Only a real STRUCT element is reported (this resolver's contract); a scalar-element array
          ## keeps {0,0} so nothing types a `u64` element as an aggregate.
          if not done {
            ae := rv_ann_arr_elem(src, ans, anl, v)
            if ae.n != 0 { if struct_decl_of(rv_decls(), src, ae.s, ae.n) >= 0 { r = ae ; done = true } }
          }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
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
  if not done { ps := rv_slice_param_struct_span(rv_params(), src, ns, nl, rv_decls()) ; if ps.n != 0 { r = ps } }
  r
}
## Element WORD stride of the iterable base expr `e` (a Var naming an array LOCAL, or a slice VIEW over
## one) via its ArrayLit; 1 for a scalar/unknown base (so scalar iteration keeps its 1-word element).
rv_iter_stride := fn(head : ptr(mut Stmt), src : ptr(u8), e : ptr(Expr), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
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
          if ex_is_array_lit(v) { r = rv_alit_stride(v, src, a, decls) ; done = true }
          if ex_is_slice(v) { r = rv_iter_stride(head, src, ex_slice_base(v), a, decls) ; done = true }
          ## `mut xs : [E; N]` — the UNINITIALIZED form: the stride is the DECLARED element's word width.
          if not done {
            ae := rv_ann_arr_elem(src, ans, anl, v)
            if ae.n != 0 { aw := rv_tyname_words(src, ae.s, ae.n, a, decls) ; if aw > 0 { r = aw ; done = true } }
          }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
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
  if not done { ps := rv_slice_param_agg_stride(rv_params(), src, bns, bnl, a, decls) ; if ps > 0 { r = ps } }
  r
}

## The riscv64 verification mode (I11 / CG-6/CG-7), mirroring the x86_64 lower's `LCtx.vchk` and
## aarch64's `A64_CHK`: `checked` by default, cleared inside an `unchecked` scope. Its own global
## because the native backends run their own emit (not routed through `lower.al`).
mut RV_CHK := true
## LOOP break/continue targets (per-fn, the RV_CHK pattern — no threaded param). Each holds the label id
## of the nearest enclosing loop: `break` → `.Lbrk<RV_BRK>`, `continue` → `.Lcont<RV_CONT>`. Saved and
## restored around each loop body so nesting resolves to the innermost. Mirrors x86 `cx.brk`/`cx.cont`.
mut RV_BRK := 0
mut RV_CONT := 0

## --- string literals + print (direct `write` syscall) — mirror of aarch64 ---
rv_is_strlit := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) { Expr::StrLit(ss, sl, lbl) => { r = true } _ => {} }
  r
}
rv_strlit_ss := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::StrLit(ss, sl, lbl) => { r = ss } _ => {} }
  r
}
rv_strlit_sl := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::StrLit(ss, sl, lbl) => { r = sl } _ => {} }
  r
}
rv_strlit_lbl := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::StrLit(ss, sl, lbl) => { r = lbl } _ => {} }
  r
}
emit_rv_str_bytes := fn(in out sb : rt::StrBuf, src : ptr(u8), ss : usize, sl : usize, lbl : usize) {
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

## Emit `write(1, .Lstr<lbl> + off, len)` — one literal run of a print template.
emit_rv_print_run := fn(in out sb : rt::StrBuf, lbl : usize, off : i64, len : i64) {
  push_str(sb, "  li a0, 1\n  la a1, .Lstr") ; push_int(sb, i64(lbl)) ; push_str(sb, "\n")
  if off != 0 { push_str(sb, "  addi a1, a1, ") ; push_int(sb, off) ; push_str(sb, "\n") }
  push_str(sb, "  li a2, ") ; push_int(sb, len) ; push_str(sb, "\n  li a7, 64\n  ecall\n")
}

## Emit a print template (RV): literal runs → emit_rv_print_run; `{}` holes → the arg via __print_u64;
## trailing newline (println) → a 1-byte write of .Lprnl. Mirrors wat.al's emit_print_template.
emit_rv_print_template := fn(in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), ss : usize, sl : usize, lbl : usize, nl : bool, ah : ptr(mut Arg), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  raw := str_at((src + ss), sl * 4 + 16)
  firstarg := deref(arg_p(ah))
  mut argp := firstarg.next
  mut k := 0
  mut dpos := 0
  mut runstart := 0
  while dpos < sl {
    if bytes(raw)[k] == 123 and bytes(raw)[k + 1] == 125 {
      if dpos > runstart { emit_rv_print_run(sb, lbl, i64(runstart), i64(dpos - runstart)) }
      if argp != 0 {
        ga := deref(arg_p(argp))
        emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  call __print_u64\n")
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
  if sl > runstart { emit_rv_print_run(sb, lbl, i64(runstart), i64(sl - runstart)) }
  if nl { push_str(sb, "  li a0, 1\n  la a1, .Lprnl\n  li a2, 1\n  li a7, 64\n  ecall\n") }
}

rv_val_words := fn(v : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut w := 1
  if rv_is_slit(v) { w = i64(struct_words(decls, src, rv_slit_ns(v), rv_slit_nl(v), a)) }
  ## enum instance = 1 discriminant word + enum_max_arity payload words (enum_inst_words omits the disc).
  if rv_is_elit(v) { w = 1 + i64(enum_max_arity(decls, src, rv_elit_ens(v), rv_elit_enl(v), a)) }
  if ex_is_array_lit(v) { w = rv_alit_nel(v) * rv_alit_stride(v, src, a, decls) }
  ## a range-slice binds a 2-word {ptr, len} view.
  if ex_is_slice(v) { w = 2 }
  ## a standard-byte aggregate Field RHS (`q := p.inner`) is copied as the leaf struct's word width;
  ## the source byte offset is handled by the Assign emitter.
  if ex_is_field(v) and RV_BODY != 0 {
    sfp := rv_std_path_ty(v, rv_body(), src, a, decls)
    if rv_std_path_ok(v, rv_body(), src, a, decls) and sfp.n != 0 {
      sbn := base_type_name(src, sfp.s, sfp.n)
      if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { w = i64(struct_words(decls, src, sbn.s, sbn.n, a)) }
    }
  }
  ## an aggregate-VAR copy `q := p` (RHS is a bare Var naming a struct/enum LOCAL): size `q` as the source
  ## local's full width (else it reserves one scalar word and the copy overruns the frame). Uses RV_BODY
  ## (this fn's body) since the sizing signature omits body_head. A plain scalar Var stays 1 word.
  vwns := ex_var_ns(v)
  vwnl := ex_var_nl(v)
  if vwnl != 0 and RV_BODY != 0 {
    lsn := rv_local_struct_nl(rv_body(), src, vwns, vwnl, a)
    if lsn != 0 { w = i64(struct_words(decls, src, rv_local_struct_ns(rv_body(), src, vwns, vwnl, a), lsn, a)) }
    len := rv_local_enum_nl(rv_body(), src, vwns, vwnl, a)
    if lsn == 0 and len != 0 { w = 1 + i64(enum_max_arity(decls, src, rv_local_enum_ns(rv_body(), src, vwns, vwnl, a), len, a)) }
  }
  ## `x := xs[i]` — a whole-ELEMENT copy out of an array of scalar-only structs is sized as the ELEMENT
  ## struct's words (a scalar 1-word reservation would let the copy overrun into the next local).
  eisw := rv_index_elem_struct_span(v, src, a, decls)
  if eisw.n != 0 {
    if std_array_elem_byte_tier(decls, src, eisw.s, eisw.n, a) { w = i64(array_elem_word_reservation(decls, src, eisw.s, eisw.n, a)) }
    if not std_array_elem_byte_tier(decls, src, eisw.s, eisw.n, a) { w = i64(struct_words(decls, src, eisw.s, eisw.n, a)) }
  }
  ## a local bound to a struct-RETURNING CALL (`p := mk()`) is sized as the returned struct's words
  ## (§8 piece 2 register struct-return convention) so its `.field` reads resolve.
  crsw := rv_call_ret_struct_span(v, decls, src, a)
  if crsw.n != 0 { w = i64(struct_words(decls, src, crsw.s, crsw.n, a)) ; if str_at((src + crsw.s), 1) == "(" { w = rv_tuple_words(src, crsw.s, crsw.n) } }
  ## a local bound to an enum-RETURNING CALL (`m := id(…)`) is sized as the enum's full width (§8 piece 3).
  crew := rv_call_ret_enum_span(v, decls, src, a)
  if crew.n != 0 { w = 1 + i64(enum_max_arity(decls, src, crew.s, crew.n, a)) }
  ## a local bound to a WIDE-struct-returning CALL (`s := mk()`, LP64 indirect result) IS the destination
  ## the callee writes through, so it must be sized as the returned struct's full (> 8) word count.
  crtw := rv_call_ret_sret_span(v, decls, src, a)
  if crtw.n != 0 { w = i64(struct_words(decls, src, crtw.s, crtw.n, a)) }
  ## a local bound to a WIDE-ENUM-returning CALL (`m := mk()`, > 8 words) IS the destination the callee
  ## writes through, so it must be sized as the enum's FULL {disc, payload…} width (an under-size would
  ## let the callee's in-place write spill over the next local — a silent corruption).
  cretw := rv_call_ret_enum_sret_span(v, decls, src, a)
  if cretw.n != 0 { w = 1 + i64(enum_max_arity(decls, src, cretw.s, cretw.n, a)) }
  w
}

## First Assign handle of name tree-wide (pre-order, incl. nested while/if/match bodies), or 0. Value
## recursion, no ptr(mut), no early-return-in-arm. Mirror of aarch64/wat.al.
rv_first_handle := fn(list : ptr(mut Stmt), ns : usize, nl : usize, src : ptr(u8), a : rt::Arena) -> usize {
  mut s := list
  mut res := 0
  while s != 0 and res == 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { if streq(src, ans, anl, ns, nl) { res = s } ; s = nx }
      Stmt::While(c, b, nx) => { res = rv_first_handle(b, ns, nl, src, a) ; s = nx }
      Stmt::If(c, th, el, nx) => { res = rv_first_handle(th, ns, nl, src, a) ; if res == 0 { res = rv_first_handle(el, ns, nl, src, a) } ; s = nx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 and res == 0 { am := deref(arm_p(arm)) ; res = rv_first_handle(am.body_stmts, ns, nl, src, a) ; arm = am.next } ; s = mnx }
      ## a `for i in lo..hi` DECLARES the loop var `i`: this For is its first handle; otherwise recurse the body.
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { if streq(src, fns, fnl, ns, nl) { res = s } else { res = rv_first_handle(fb, ns, nl, src, a) } ; s = nx }
      ## a `comptime for i in lo..hi` DECLARES the loop var `i` (like a range `for`): this CompForRange is
      ## its first handle; otherwise recurse the body. CONTINUE past (a `_ => s = 0` would mis-resolve a
      ## local declared after the unrolled loop → silent miscompile).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { if streq(src, rvs, rvl, ns, nl) { res = s } else { res = rv_first_handle(rb, ns, nl, src, a) } ; s = nx }
      ## a `comptime if` folds to ONE branch but its locals live in the fn frame — recurse BOTH branches
      ## (mirroring rv_local_scan's both-branch scan) and CONTINUE past it, so a local declared after a
      ## CompIf is still found (a `_ => s = 0` would stop the scan and mis-resolve it → silent miscompile).
      Stmt::CompIf(cc, th, el, nx) => { res = rv_first_handle(th, ns, nl, src, a) ; if res == 0 { res = rv_first_handle(el, ns, nl, src, a) } ; s = nx }
      Stmt::Loop(lb, lnx) => { res = rv_first_handle(lb, ns, nl, src, a) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { res = rv_first_handle(ub, ns, nl, src, a) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      ## an index/field-path assign declares no local but MUST NOT terminate the scan (a leading
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

## Pre-order WORD scan (tree-wide): accumulate each distinct first-occ local's word-size; return
## `-(wordoff+1)` when `target` is reached, else the running count. Value recursion + `found` flag.
rv_local_scan := fn(list : ptr(mut Stmt), fn_head : ptr(mut Stmt), target : usize, before : i64, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
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
          if rv_first_handle(fn_head, ans, anl, src, a) == s {
            annw := rv_ann_arr_words(src, ans, anl, v, a, decls)
            if annw > 0 { b = b + annw } else { b = b + rv_val_words(v, src, a, decls) }
          }
          s = nx
        }
      }
      Stmt::While(c, body, nx) => {
        r := rv_local_scan(body, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = nx }
      }
      Stmt::If(c, th, el, nx) => {
        r := rv_local_scan(th, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true }
        else {
          r2 := rv_local_scan(el, fn_head, target, r, src, a, decls)
          if r2 < 0 { result = r2 ; found = true } else { b = r2 ; s = nx }
        }
      }
      Stmt::Match(msc, mah, mnx) => {
        mut arm := mah
        while arm != 0 and (not found) {
          am := deref(arm_p(arm))
          r := rv_local_scan(am.body_stmts, fn_head, target, b, src, a, decls)
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
          if rv_first_handle(fn_head, fns, fnl, src, a) == s {
            ## an ITERABLE for = the loop var's element words (rv_iter_stride, 1 for scalar) + a hidden index
            ## word; a RANGE for = 1 word. Scalar stays 2 (stride 1 + 1) — frame layout byte-identical.
            if unchecked bitcast(usize, fhi) == 0 { b = b + rv_iter_stride(fn_head, src, flo, a, decls) + 1 } else { b = b + 1 }
          }
          r := rv_local_scan(fb, fn_head, target, b, src, a, decls)
          if r < 0 { result = r ; found = true } else { b = r ; s = nx }
        }
      }
      ## a `comptime for i in lo..hi` DECLARES a scalar loop var `i` = ONE word (like a RANGE for), reserved
      ## at its first-handle; then scan the body (emitted once per unroll iteration into these same slots).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => {
        if s == target { result = 0 - (b + 1) ; found = true }
        else {
          if rv_first_handle(fn_head, rvs, rvl, src, a) == s { b = b + 1 }
          r := rv_local_scan(rb, fn_head, target, b, src, a, decls)
          if r < 0 { result = r ; found = true } else { b = r ; s = nx }
        }
      }
      ## `loop { }` / `unchecked { }` body scanned like a while body (function-frame locals at the running
      ## offset); `break`/`continue` declare nothing (skip).
      Stmt::Loop(lb, lnx) => {
        r := rv_local_scan(lb, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = lnx }
      }
      Stmt::Unchecked(ub, unx) => {
        r := rv_local_scan(ub, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = unx }
      }
      ## a `comptime if` folds to ONE branch at emit time; its taken-branch locals live in the fn frame.
      ## Scan BOTH branches (a safe superset — an untaken branch's slots are merely reserved), so whichever
      ## branch the emit selects finds its locals sized. Mirrors the `Stmt::If` scan.
      Stmt::CompIf(cc, th, el, nx) => {
        r := rv_local_scan(th, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true }
        else {
          r2 := rv_local_scan(el, fn_head, target, r, src, a, decls)
          if r2 < 0 { result = r2 ; found = true } else { b = r2 ; s = nx }
        }
      }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      ## index/field-path/deref assigns declare no local but MUST advance (see rv_first_handle).
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(dpe, dval, dnx) => { s = dnx }
      _ => { s = 0 }
    }
  }
  if found { result } else { b }
}

rv_count_locals := fn(head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  rv_local_scan(head, head, 0, 0, src, a, decls)
}

## Count SLICE ARGUMENTS (an `Expr::Slice` passed as a call arg) in an expr tree — the CALLER materializes
## each into a reserved 2-word `{ptr,len}` agg block. Mirrors aarch64's a64_slarg_count_e; every counted
## site matches an emit-time materialization so reservation >= allocation.
rv_slarg_count_e := fn(e : ptr(Expr)) -> i64 {
  mut c := 0
  match deref(e) {
    Expr::Bin(op, l, r) => { c = rv_slarg_count_e(l) + rv_slarg_count_e(r) }
    Expr::If(cc, t, f) => { c = rv_slarg_count_e(cc) + rv_slarg_count_e(t) + rv_slarg_count_e(f) }
    Expr::Call(cs, cl, n, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; if ex_is_slice(ga.e) { c = c + 1 } ; c = c + rv_slarg_count_e(ga.e) ; g = ga.next } }
    Expr::Field(base, fs, fl) => { c = rv_slarg_count_e(base) }
    Expr::Index(base, idx) => { c = rv_slarg_count_e(base) + rv_slarg_count_e(idx) }
    Expr::Unchecked(inner) => { c = rv_slarg_count_e(inner) }
    Expr::StructLit(ss, sl, nf, fh) => { mut g := fh ; while g != 0 { ga := deref(arg_p(g)) ; c = c + rv_slarg_count_e(ga.e) ; g = ga.next } }
    Expr::ArrayLit(nel, eh) => { mut g := eh ; while g != 0 { ga := deref(arg_p(g)) ; c = c + rv_slarg_count_e(ga.e) ; g = ga.next } }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { mut g := ph ; while g != 0 { ga := deref(arg_p(g)) ; c = c + rv_slarg_count_e(ga.e) ; g = ga.next } }
    _ => {}
  }
  c
}
rv_slarg_count := fn(list : ptr(mut Stmt)) -> i64 {
  mut s := list
  mut c := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { c = c + rv_slarg_count_e(v) ; s = nx }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { c = c + rv_slarg_count_e(rv) } ; s = nx }
      Stmt::ExprStmt(e, nx) => { c = c + rv_slarg_count_e(e) ; s = nx }
      Stmt::While(cc, b, nx) => { c = c + rv_slarg_count_e(cc) + rv_slarg_count(b) ; s = nx }
      Stmt::If(cc, th, el, nx) => { c = c + rv_slarg_count_e(cc) + rv_slarg_count(th) + rv_slarg_count(el) ; s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { c = c + rv_slarg_count_e(fv) ; s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, ifv, ifnx) => { c = c + rv_slarg_count_e(ifv) ; s = ifnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { c = c + rv_slarg_count_e(iv) + rv_slarg_count_e(ii) ; s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { c = c + rv_slarg_count_e(fpv) ; s = fpnx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; c = c + rv_slarg_count(am.body_stmts) ; arm = am.next } ; s = mnx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { c = c + rv_slarg_count(fb) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { c = c + rv_slarg_count(rb) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { c = c + rv_slarg_count(th) + rv_slarg_count(el) ; s = nx }
      Stmt::Loop(lb, lnx) => { c = c + rv_slarg_count(lb) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { c = c + rv_slarg_count(ub) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
  c
}

## Count the FRAME WORDS needed for anonymous aggregate-VALUE call arguments — a STRUCT LITERAL `S(…)`
## passed directly as a call argument (§8 anonymous-aggregate materialization, piece 1). Such a literal
## has no frame home, so the caller materializes its `struct_words` field words into a reserved RV_AGG
## block and passes the block ADDRESS by reference (emit_rv_aggval_arg). Mirrors rv_slarg_count but sums
## WORDS; tree-wide so reservation ≥ every emit-time allocation (an under-count is a LOUD `ebreak`).
rv_aggval_words_e := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut c := 0
  match deref(e) {
    Expr::Bin(op, l, r) => { c = rv_aggval_words_e(l, src, a, decls) + rv_aggval_words_e(r, src, a, decls) }
    Expr::If(cc, t, f) => { c = rv_aggval_words_e(cc, src, a, decls) + rv_aggval_words_e(t, src, a, decls) + rv_aggval_words_e(f, src, a, decls) }
    Expr::Call(cs, cl, n, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; if rv_is_slit(ga.e) { c = c + i64(struct_words(decls, src, rv_slit_ns(ga.e), rv_slit_nl(ga.e), a)) } ; if rv_is_elit(ga.e) { c = c + 1 + i64(enum_max_arity(decls, src, rv_elit_ens(ga.e), rv_elit_enl(ga.e), a)) } ; crc := rv_call_ret_struct_span(ga.e, decls, src, a) ; if crc.n != 0 { c = c + i64(struct_words(decls, src, crc.s, crc.n, a)) } ; cre := rv_call_ret_enum_span(ga.e, decls, src, a) ; if cre.n != 0 { c = c + 1 + i64(enum_max_arity(decls, src, cre.s, cre.n, a)) } ; srr := rv_call_ret_sret_span(ga.e, decls, src, a) ; if srr.n != 0 { c = c + i64(struct_words(decls, src, srr.s, srr.n, a)) } ; esr := rv_call_ret_enum_sret_span(ga.e, decls, src, a) ; if esr.n != 0 { c = c + 1 + i64(enum_max_arity(decls, src, esr.s, esr.n, a)) } ; c = c + rv_aggval_words_e(ga.e, src, a, decls) ; g = ga.next } }
    Expr::Field(base, fs, fl) => { c = rv_aggval_words_e(base, src, a, decls) }
    Expr::Index(base, idx) => { c = rv_aggval_words_e(base, src, a, decls) + rv_aggval_words_e(idx, src, a, decls) }
    Expr::Unchecked(inner) => { c = rv_aggval_words_e(inner, src, a, decls) }
    Expr::StructLit(ss, sl, nf, fh) => { mut g := fh ; while g != 0 { ga := deref(arg_p(g)) ; c = c + rv_aggval_words_e(ga.e, src, a, decls) ; g = ga.next } }
    Expr::ArrayLit(nel, eh) => { mut g := eh ; while g != 0 { ga := deref(arg_p(g)) ; c = c + rv_aggval_words_e(ga.e, src, a, decls) ; g = ga.next } }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { mut g := ph ; while g != 0 { ga := deref(arg_p(g)) ; c = c + rv_aggval_words_e(ga.e, src, a, decls) ; g = ga.next } }
    _ => {}
  }
  c
}
rv_aggval_words := fn(list : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut s := list
  mut c := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { c = c + rv_aggval_words_e(v, src, a, decls) ; s = nx }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { c = c + rv_aggval_words_e(rv, src, a, decls) } ; s = nx }
      Stmt::ExprStmt(e, nx) => { c = c + rv_aggval_words_e(e, src, a, decls) ; s = nx }
      Stmt::While(cc, b, nx) => { c = c + rv_aggval_words_e(cc, src, a, decls) + rv_aggval_words(b, src, a, decls) ; s = nx }
      Stmt::If(cc, th, el, nx) => { c = c + rv_aggval_words_e(cc, src, a, decls) + rv_aggval_words(th, src, a, decls) + rv_aggval_words(el, src, a, decls) ; s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { c = c + rv_aggval_words_e(fv, src, a, decls) ; s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, ifv, ifnx) => { c = c + rv_aggval_words_e(ifv, src, a, decls) ; s = ifnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { c = c + rv_aggval_words_e(iv, src, a, decls) + rv_aggval_words_e(ii, src, a, decls) ; s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { c = c + rv_aggval_words_e(fpv, src, a, decls) ; s = fpnx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; c = c + rv_aggval_words(am.body_stmts, src, a, decls) ; arm = am.next } ; s = mnx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { c = c + rv_aggval_words(fb, src, a, decls) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { c = c + rv_aggval_words(rb, src, a, decls) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { c = c + rv_aggval_words(th, src, a, decls) + rv_aggval_words(el, src, a, decls) ; s = nx }
      Stmt::Loop(lb, lnx) => { c = c + rv_aggval_words(lb, src, a, decls) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { c = c + rv_aggval_words(ub, src, a, decls) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
  c
}

## Count WIDE-SRET calls whose result is deliberately discarded by a statement. Unlike an SRET call used as
## an aggregate argument, a bare `f(…)` has no destination local, so the caller must reserve a temporary block
## and hand its address down. This scanner mirrors emit_rv_sret_discard; without it the temporary allocator can
## run past the frame even though the call itself is otherwise correctly routed.
rv_sret_discard_words_e := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut c := 0
  srs := rv_call_ret_sret_span(e, decls, src, a)
  if srs.n != 0 { c = i64(struct_words(decls, src, srs.s, srs.n, a)) }
  if srs.n == 0 {
    ers := rv_call_ret_enum_sret_span(e, decls, src, a)
    if ers.n != 0 { c = 1 + i64(enum_max_arity(decls, src, ers.s, ers.n, a)) }
  }
  c
}
rv_sret_discard_words := fn(list : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut s := list
  mut c := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { c = c + rv_sret_discard_words_e(e, src, a, decls) ; s = nx }
      Stmt::While(cc, b, nx) => { c = c + rv_sret_discard_words(b, src, a, decls) ; s = nx }
      Stmt::If(cc, th, el, nx) => { c = c + rv_sret_discard_words(th, src, a, decls) + rv_sret_discard_words(el, src, a, decls) ; s = nx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; c = c + rv_sret_discard_words(am.body_stmts, src, a, decls) ; arm = am.next } ; s = mnx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { c = c + rv_sret_discard_words(fb, src, a, decls) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { c = c + rv_sret_discard_words(rb, src, a, decls) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { c = c + rv_sret_discard_words(th, src, a, decls) + rv_sret_discard_words(el, src, a, decls) ; s = nx }
      Stmt::Loop(lb, lnx) => { c = c + rv_sret_discard_words(lb, src, a, decls) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { c = c + rv_sret_discard_words(ub, src, a, decls) ; s = unx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, ifv, ifnx) => { s = ifnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(dpe, dval, dnx) => { s = dnx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
  c
}

## The largest {disc, payload…} word count over this fn's ENUM PARAMS. An enum param is passed BY
## REFERENCE, and a `match <enum param>` first MATERIALIZES its words into the RV_MTMP frame temp (the
## `paramok` arms of both the value-Match and the statement-Match paths) before dispatching. The scanner
## below (rv_match_tmp_words) only ever visits Stmt::Match, so a `match <enum param>` in the TRAILING
## VALUE position reserved NOTHING and the materialization wrote PAST the frame top into the CALLER's
## frame — for a WIDE enum that clobbers the caller's saved s0/ra AND the source block: a RAW SIGSEGV,
## not a clean trap. Measuring from the PARAM LIST covers every match site, statement or value.
## 0 for a fn with no enum param, so every other frame stays byte-identical.
rv_param_enum_tmp_words := fn(params_head : ptr(mut Param), src : ptr(u8), decls : ptr(rt::Vec), a : rt::Arena) -> i64 {
  mut p := params_head
  mut mx := 0
  while p != 0 {
    pm := deref(param_p(p))
    mut ets := pm.ts
    mut etl := pm.tl
    if RV_SUB_GPL != 0 {
      if streq(src, pm.ts, pm.tl, RV_SUB_GPS, RV_SUB_GPL) { ets = RV_SUB_ITS ; etl = RV_SUB_ITL }
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

## The largest enum-element word count over all `match s[i]` on an enum `Slice(E)` PARAM (tree-wide) —
## the match-over-index temp region size. Uses RV_PARAMS/RV_DECLS.
rv_match_tmp_words := fn(list : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> i64 {
  mut s := list
  mut mx := 0
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Match(msc, mah, mnx) => {
        w := rv_match_index_enum_words(msc, src, a)
        if w > mx { mx = w }
        mut arm := mah
        while arm != 0 { am := deref(arm_p(arm)) ; bw := rv_match_tmp_words(am.body_stmts, src, a) ; if bw > mx { mx = bw } ; arm = am.next }
        s = mnx
      }
      Stmt::While(cc, b, nx) => { bw := rv_match_tmp_words(b, src, a) ; if bw > mx { mx = bw } ; s = nx }
      Stmt::If(cc, th, el, nx) => { bw := rv_match_tmp_words(th, src, a) ; if bw > mx { mx = bw } ; bw2 := rv_match_tmp_words(el, src, a) ; if bw2 > mx { mx = bw2 } ; s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { bw := rv_match_tmp_words(fb, src, a) ; if bw > mx { mx = bw } ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { bw := rv_match_tmp_words(rb, src, a) ; if bw > mx { mx = bw } ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { bt := rv_match_tmp_words(th, src, a) ; if bt > mx { mx = bt } ; be := rv_match_tmp_words(el, src, a) ; if be > mx { mx = be } ; s = nx }
      Stmt::Loop(lb, lnx) => { bw := rv_match_tmp_words(lb, src, a) ; if bw > mx { mx = bw } ; s = lnx }
      Stmt::Unchecked(ub, unx) => { bw := rv_match_tmp_words(ub, src, a) ; if bw > mx { mx = bw } ; s = unx }
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
rv_match_index_enum_words := fn(scrut : ptr(Expr), src : ptr(u8), a : rt::Arena) -> i64 {
  mut r := 0
  if ex_is_index(scrut) {
    ib := ex_index_base(scrut)
    es := rv_slice_param_enum_span(rv_params(), src, ex_var_ns(ib), ex_var_nl(ib), rv_decls())
    if es.n != 0 { r = rv_slice_param_agg_stride(rv_params(), src, ex_var_ns(ib), ex_var_nl(ib), a, rv_decls()) }
  }
  ## a `match <enum PARAM>` (piece 3) materializes the by-reference block into the temp before matching.
  pel := rv_param_enum_nl(rv_params(), src, ex_var_ns(scrut), ex_var_nl(scrut), rv_decls())
  if pel != 0 { pw := 1 + i64(enum_max_arity(rv_decls(), src, rv_param_enum_ns(rv_params(), src, ex_var_ns(scrut), ex_var_nl(scrut), rv_decls()), pel, a)) ; if pw > r { r = pw } }
  r
}

rv_local_off := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  target := rv_first_handle(head, ns, nl, src, a)
  r := rv_local_scan(head, head, target, pcount, src, a, decls)
  mut off := 0 - 1
  if r < 0 { off = 16 + ((0 - r) - 1) * 8 }
  off
}

rv_callee_defined := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, a : rt::Arena) -> bool {
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




## Resolve the concrete type named by a `typeinfo(X)` range-bound expression. The `.fields.len` and
## `.variants.len` forms leave one Field wrapper around the Call; `.n` passes the Call directly. Unlike
## the old range fold, this keeps the explicit X and substitutes whichever active generic parameter it
## names instead of always using RV_SUB_ITS.
rv_range_typeinfo_arg := fn(base : ptr(Expr), field_s : usize, src : ptr(u8)) -> CSpan {
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
      if RV_SUB_GPL != 0 and n != 0 and streq(src, s, n, RV_SUB_GPS, RV_SUB_GPL) { s = RV_SUB_ITS ; n = RV_SUB_ITL }
      else if RV_SUB_GPL2 != 0 and n != 0 and streq(src, s, n, RV_SUB_GPS2, RV_SUB_GPL2) { s = RV_SUB_ITS2 ; n = RV_SUB_ITL2 }
      else if RV_SUB_GPL3 != 0 and n != 0 and streq(src, s, n, RV_SUB_GPS3, RV_SUB_GPL3) { s = RV_SUB_ITS3 ; n = RV_SUB_ITL3 }
      r = CSpan(s = s, n = n)
    }
  }
  r
}

## The mutability bit of `<f>.mutable` for the ACTIVE comptime field descriptor (Comptime §5.1). Field
## mutability is a source-level marker, so recover it from the current field name exactly as x86 does.
## -1 means this is not an active mutable query; the ordinary field path then remains fail-loud.
rv_cf_mutable_value := fn(e : ptr(Expr), src : ptr(u8)) -> i64 {
  if RV_CF_VAR_L == 0 { return 0 - 1 }
  match deref(e) {
    Expr::Field(base, fs, fl) => {
      if str_at((src + fs), fl) != "mutable" { return 0 - 1 }
      vn_s := ex_var_ns(base)
      vn_l := ex_var_nl(base)
      if vn_l == 0 or not streq(src, vn_s, vn_l, RV_CF_VAR_S, RV_CF_VAR_L) { return 0 - 1 }
      if ast::local_is_mut(src, RV_CF_FLD_S) { return 1 }
      return 0
    }
    _ => { return 0 - 1 }
  }
}

## Resolve a comptime-for RANGE BOUND to its constant value: a literal, or a module-level const `N := k`
## resolved by name (comptime_for_range's `0..N`). Mirrors the subset of the x86 lower's global_init_value
## the corpus range bounds use (literal + module const; no const arithmetic — range bounds carry none).
rv_comp_range_bound := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8)) -> i64 {
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
      rt := rv_range_typeinfo_arg(b, fs, src)
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

## The i-th arg expr of an arg list (0-based), null Expr ptr if absent — for `asm(…)` `{i}` substitution.
rv_arg_at := fn(head : ptr(mut Stmt), i : usize, a : rt::Arena) -> ptr(Expr) {
  mut g := head
  mut k := 0
  mut res : usize = 0
  while g != 0 { ga := deref(arg_p(g)) ; if k == i { res = unchecked bitcast(usize, ga.e) } ; k = k + 1 ; g = ga.next }
  unchecked bitcast(ptr(Expr), res)
}

rv_is_global := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut found := false
  while i < cnt {
    d := deref(decl_get(decls, i))
    ## a scalar (Num/Bool) OR a float (FloatLit) module global — both live in `.data`, read/written via label.
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, ns, nl) { if ex_value_is_scalar(d.value) { found = true } ; if rv_is_floatlit(d.value) { found = true } }
    i += 1
  }
  found
}

## --- GLOBAL AGGREGATES (struct/array/enum module globals): `.data` layout + field-chain access. ---
## Mirrors aarch64.al: an aggregate global is laid in `.data` as ascending 8-byte cells (nested structs
## flattened inline, like the x86 lower), addressed by its plain source-name label; a field chain rooted
## at it reads/writes at LABEL + cumulative-word-offset*8 (scalar leaf only).
rv_value_is_agg := fn(v : ptr(Expr)) -> bool { rv_is_slit(v) or rv_is_elit(v) or ex_is_array_lit(v) }

rv_global_value := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> ptr(Expr) {
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

## Emit the `.data` cells of an aggregate global INITIALIZER recursively (mirrors lower::emit_global_data_cells):
## a struct-lit emits its field args in order (nested struct flattens); an array-lit its elements; an enum-lit
## `[disc, payload…, pad]` to `1+enum_inst_words`; a float `.double`; anything else `.quad` of its int value.
emit_rv_global_cells := fn(e : ptr(Expr), in out sb : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) {
  if rv_is_slit(e) {
    mut g := ex_struct_lit_args(e)
    while g != 0 { ga := deref(arg_p(g)) ; emit_rv_global_cells(ga.e, sb, decls, src, a) ; g = ga.next }
  } else if ex_is_array_lit(e) {
    mut ag := ex_array_lit_ehead(e)
    while ag != 0 { aga := deref(arg_p(ag)) ; emit_rv_global_cells(aga.e, sb, decls, src, a) ; ag = aga.next }
  } else if rv_is_elit(e) {
    push_str(sb, "  .quad ") ; push_int(sb, variant_index(decls, src, rv_elit_ens(e), rv_elit_enl(e), rv_elit_vns(e), rv_elit_vnl(e), a)) ; push_str(sb, "\n")
    mut np := 0
    mut eg := ex_enum_lit_args(e)
    while eg != 0 { ega := deref(arg_p(eg)) ; push_str(sb, "  .quad ") ; push_int(sb, ex_value_init(ega.e)) ; push_str(sb, "\n") ; np += 1 ; eg = ega.next }
    emxw := i64(enum_inst_words(decls, src, rv_elit_ens(e), rv_elit_enl(e), a))
    mut padk := np
    while padk < emxw { push_str(sb, "  .quad 0\n") ; padk += 1 }
  } else if rv_is_floatlit(e) {
    push_str(sb, "  .double ") ; push_str(sb, str_at((src + rv_floatlit_ss(e)), rv_floatlit_sl(e))) ; push_str(sb, "\n")
  } else {
    push_str(sb, "  .quad ") ; push_int(sb, ex_value_init(e)) ; push_str(sb, "\n")
  }
}

## STRUCT-type name span of the place expr `e` (a field chain rooted at a struct GLOBAL), else {0,0}.
rv_gchain_type := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => {
      gv := rv_global_value(decls, src, s, n)
      if unchecked bitcast(usize, gv) != 0 { if rv_is_slit(gv) { r = CSpan(s = rv_slit_ns(gv), n = rv_slit_nl(gv)) } }
    }
    Expr::Field(base, fs, fl) => {
      bt := rv_gchain_type(base, decls, src, a)
      if bt.n != 0 { if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { r = field_type_span(decls, src, bt.s, bt.n, fs, fl, a) } }
    }
    _ => {}
  }
  r
}

## Cumulative WORD offset of the place `e` within its root struct global's `.data`, or -1 if not a chain.
rv_gchain_woff := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> i64 {
  mut r := 0 - 1
  match deref(e) {
    Expr::Var(s, n) => {
      gv := rv_global_value(decls, src, s, n)
      if unchecked bitcast(usize, gv) != 0 { if rv_is_slit(gv) { r = 0 } }
    }
    Expr::Field(base, fs, fl) => {
      boff := rv_gchain_woff(base, decls, src, a)
      bt := rv_gchain_type(base, decls, src, a)
      if boff >= 0 and bt.n != 0 { if struct_decl_of(decls, src, bt.s, bt.n) >= 0 {
        fwo := field_word_offset(decls, src, bt.s, bt.n, fs, fl, a)
        if fwo >= 0 { r = boff + fwo }
      } }
    }
    _ => {}
  }
  r
}

## Root VAR name span of a field chain (`STATE.a.b` → STATE), descending through `Field` bases.
rv_gchain_root := fn(e : ptr(Expr)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => { r = CSpan(s = s, n = n) }
    Expr::Field(base, fs, fl) => { r = rv_gchain_root(base) }
    _ => {}
  }
  r
}

## The struct-type span of a nested field chain rooted at a struct LOCAL (`c.b.a` → the type of a),
## or 0/0. Recursive: a root Var → its local struct type; `base.f` → the field-type of base's struct.
rv_lchain_type := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => {
      lsn := rv_local_struct_nl(body_head, src, s, n, a)
      if lsn != 0 { r = CSpan(s = rv_local_struct_ns(body_head, src, s, n, a), n = lsn) }
    }
    Expr::Field(base, fs, fl) => {
      bt := rv_lchain_type(base, body_head, src, a, decls)
      if bt.n != 0 { if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { r = field_type_span(decls, src, bt.s, bt.n, fs, fl, a) } }
    }
    _ => {}
  }
  r
}
## The cumulative WORD offset of the place `e` within its ROOT struct local's frame slots, or -1. A root
## Var → 0; `base.f` → base-off + field_word_offset (nested structs flattened inline, down-growing).
rv_lchain_woff := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut r := 0 - 1
  match deref(e) {
    Expr::Var(s, n) => {
      if rv_local_struct_nl(body_head, src, s, n, a) != 0 { r = 0 }
    }
    Expr::Field(base, fs, fl) => {
      boff := rv_lchain_woff(base, body_head, src, a, decls)
      bt := rv_lchain_type(base, body_head, src, a, decls)
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
rv_is_array_global := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> bool {
  gv := rv_global_value(decls, src, ns, nl)
  if unchecked bitcast(usize, gv) == 0 { return false }
  ex_is_array_lit(gv)
}

## The element STRUCT span (ns,nl) of an ARRAY GLOBAL `[ns,nl]` — its initializer ArrayLit's FIRST
## element StructLit name — or {0,0}. The `.data` twin of `rv_arr_elem_struct_span` (which resolves a
## LOCAL array-lit through the fn body). Used to type `ARR[i]` element access on a struct array global.
rv_garr_elem_struct_span := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  gv := rv_global_value(decls, src, ns, nl)
  if unchecked bitcast(usize, gv) == 0 { return r }
  if not ex_is_array_lit(gv) { return r }
  eh := ex_array_lit_ehead(gv)
  if eh != 0 {
    ga0 := deref(arg_p(eh))
    ge0 := ga0.e
    if rv_is_slit(ge0) { r = CSpan(s = rv_slit_ns(ge0), n = rv_slit_nl(ge0)) }
  }
  r
}

## True when the ARRAY-LIT `v` is HOMOGENEOUS in one named STRUCT — EVERY element is a StructLit of the
## SAME type. A TUPLE literal `(Pt(…), 12)` parses as an ArrayLit too (tuples reuse the aggregate
## surface), but its components have DIFFERENT widths, so a first-element stride would mis-address every
## component after the first — `t.1` would read the struct component's word 1. Element access below
## fires ONLY on a homogeneous struct array; a tuple keeps falling through to the fail-loud `ebreak`.
rv_alit_homog_slit := fn(v : ptr(Expr), src : ptr(u8)) -> bool {
  if unchecked bitcast(usize, v) == 0 { return false }
  if not ex_is_array_lit(v) { return false }
  eh := ex_array_lit_ehead(v)
  if eh == 0 { return false }
  h0 := deref(arg_p(eh))
  e0 := h0.e
  if not rv_is_slit(e0) { return false }
  hs := rv_slit_ns(e0)
  hn := rv_slit_nl(e0)
  mut g := eh
  mut ok := true
  while g != 0 {
    ga := deref(arg_p(g))
    if not rv_is_slit(ga.e) { ok = false }
    if rv_is_slit(ga.e) {
      if not streq(src, rv_slit_ns(ga.e), rv_slit_nl(ga.e), hs, hn) { ok = false }
    }
    g = ga.next
  }
  ok
}

## AGGREGATE ARRAY ELEMENT (§8.3): the element STRUCT span of the array named `[ns,nl]` when it is a
## fixed array whose elements are a SCALAR-ONLY struct — either a LOCAL `arr := [S(..), …]` (resolved
## through RV_BODY) or an array GLOBAL — else {0,0}. ONE place decides the shape so frame SIZING
## (`rv_val_words`), local TYPING (`rv_local_struct_ns`/`_nl`) and the three emit paths (field read,
## whole-element copy, whole-element write) can never disagree — a disagreement here would size a
## destination for one word and copy `stride` words over the next local (a silent corruption).
## Non-scalar (nested-aggregate) element structs stay OUT: their field offsets need the flattened
## layout the element paths do not compute, so they keep falling through to the fail-loud `ebreak`.
rv_arrname_elem_struct_span := fn(src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if nl == 0 { return r }
  if RV_BODY != 0 {
    if rv_alit_homog_slit(rv_local_rhs(rv_body(), src, ns, nl, a), src) { r = rv_arr_elem_struct_span(rv_body(), src, ns, nl, a) }
    ## `mut xs : [E; N]` — the DECLARED (uninitialized) form has no array literal to read the element
    ## struct off, so take it from the annotation. A type form can never be a tuple, so the
    ## `rv_alit_homog_slit` heterogeneity guard has nothing to do here.
    if r.n == 0 {
      ats := rv_local_arrty_span(rv_body(), src, ns, nl, a)
      if ats.n != 0 { r = rv_arrty_elem(src, ats.s, ats.n) }
    }
  }
  if r.n == 0 {
    if rv_alit_homog_slit(rv_global_value(decls, src, ns, nl), src) { r = rv_garr_elem_struct_span(decls, src, ns, nl) }
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
rv_index_elem_struct_span := fn(v : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if not ex_is_index(v) { return r }
  bx := ex_index_base(v)
  r = rv_arrname_elem_struct_span(src, ex_var_ns(bx), ex_var_nl(bx), a, decls)
  r
}

## --- TYPED-DECLARATION (annotation) SOURCE-SCAN: `mut xs : [Cell; 3]` (Types §9.4) ---
## The parser keeps the `Stmt.Assign` shape for an explicitly uninitialized `name : T` and plants a
## `Num(0)` SENTINEL value (so no bootstrap-sensitive AST field is added), which leaves the element TYPE
## and COUNT recorded ONLY in the source. These scans recover them — the same source-scan technique
## `ann_scan_signed` uses for `iN` signedness — so the frame can SIZE such an array and the element
## paths can TYPE it. Without them a `mut xs : [S; N]` reserved ONE word and every access was fail-loud.


## The `: T` annotation span that FOLLOWS the declaration name `[ns,nl)`, or {0,0} for `:=` (inferred),
## a missing annotation, or a malformed one. `[`/`(` nesting is tracked so `[Cell; 3]` spans whole; the
## span ENDS at a depth-0 `=` (an INITIALIZED `name : T = v` still yields its annotation), newline, `;`
## or `}`. Mirrors ast::local_type_span but returns the rv `CSpan` (no new struct return type here).
rv_ann_span := fn(src : ptr(u8), ns : usize, nl : usize) -> CSpan {
  mut p := ns + nl
  lim := p + 512
  mut go := true
  while go { c := str_at((src + p), 1) ; if c == " " or c == "\t" or c == "\r" { p = p + 1 } else { go = false } }
  if str_at((src + p), 1) != ":" { return CSpan(s = 0, n = 0) }
  p = p + 1
  go = true
  while go { c := str_at((src + p), 1) ; if c == " " or c == "\t" or c == "\r" { p = p + 1 } else { go = false } }
  if str_at((src + p), 1) == "=" { return CSpan(s = 0, n = 0) }
  ts := p
  mut depth := 0
  mut term := false
  while p < lim and (not term) {
    c := str_at((src + p), 1)
    if c == "(" or c == "[" { depth = depth + 1 }
    if c == ")" or c == "]" { if depth > 0 { depth = depth - 1 } }
    stop := depth == 0 and (c == "=" or c == "\n" or c == ";" or c == "}")
    if stop { term = true } else { p = p + 1 }
  }
  if not term { return CSpan(s = 0, n = 0) }
  mut te := p
  mut trim := true
  while trim and te > ts {
    t := str_at((src + te - 1), 1)
    if t == " " or t == "\t" or t == "\r" { te = te - 1 } else { trim = false }
  }
  if te <= ts { return CSpan(s = 0, n = 0) }
  CSpan(s = ts, n = te - ts)
}


## `[E; N]` → the ELEMENT type span E (trimmed), else {0,0}.
rv_arrty_elem := fn(src : ptr(u8), ts : usize, tl : usize) -> CSpan {
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

## `[E; N]` → the static element COUNT N, else 0 (not a fixed-array type, or a non-literal length — a
## `[T; <comptime expr>]` stays 0 so every dependent path falls back to the fail-loud default).
rv_arrty_nel := fn(src : ptr(u8), ts : usize, tl : usize) -> i64 {
  semi := arrty_semi(src, ts, tl)
  if semi == 0 { return 0 }
  mut p := semi + 1
  lim := ts + tl
  mut go := true
  while go and p < lim { c := str_at((src + p), 1) ; if c == " " or c == "\t" { p = p + 1 } else { go = false } }
  mut n := 0
  mut any := false
  mut scan := true
  while scan and p < lim {
    d := dec_digit_val(str_at((src + p), 1))
    if d >= 0 { n = n * 10 + d ; any = true ; p = p + 1 } else { scan = false }
  }
  if not any { return 0 }
  n
}

## The WORD width of the type named `[ts,tl)`: `struct_words` for a PLAIN struct, `1 + enum_max_arity`
## for an enum, `N * width(E)` for a nested `[E; N]`, 1 for a scalar; 0 = UNSUPPORTED (a generic /
## comptime-value type-fn whose layout resolve would PANIC without a binding, a `str`, or an unresolvable
## nested element). Every caller gates on `> 0`, so an unsupported type keeps the fail-loud default.
rv_tyname_words := fn(src : ptr(u8), ts : usize, tl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut r := 0
  if tl == 0 { return r }
  if struct_decl_of(decls, src, ts, tl) >= 0 {
    if not struct_plain(decls, src, ts, tl) { return r }
    if std_array_elem_byte_tier(decls, src, ts, tl, a) { r = i64(array_elem_word_reservation(decls, src, ts, tl, a)) ; return r }
    require_no_byte_layout_array_elem(decls, src, ts, tl, a)
    r = i64(struct_words(decls, src, ts, tl, a))
    return r
  }
  if enum_decl_of(decls, src, ts, tl) >= 0 {
    r = 1 + i64(enum_max_arity(decls, src, ts, tl, a))
    return r
  }
  es := rv_arrty_elem(src, ts, tl)
  if es.n != 0 {
    ew := rv_tyname_words(src, es.s, es.n, a, decls)
    nel := rv_arrty_nel(src, ts, tl)
    if ew > 0 { if nel > 0 { r = nel * ew } }
    return r
  }
  if str_at((src + ts), tl) == "str" { return r }
  1
}

## Runtime ARRAY-ELEMENT STRIDE in BYTES. Reservation remains word-denominated; only byte-tier
## elements use their exact Types §6.4 stride here.
rv_arr_elem_stride_bytes := fn(src : ptr(u8), ts : usize, tl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if std_array_elem_byte_tier(decls, src, ts, tl, a) { return i64(layout_elem_stride_bytes(decls, src, ts, tl, a)) }
  i64(rv_tyname_words(src, ts, tl, a, decls)) * 8
}

## The static element COUNT of a declaration `name : [E; N]` whose value is NOT an array literal (the
## explicitly uninitialized form), else 0 — so an INITIALIZED `xs : [E;N] = [..]` keeps every existing
## ArrayLit-driven answer byte-identical.
rv_ann_arr_nel := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr)) -> i64 {
  if ex_is_array_lit(v) { return 0 }
  an := rv_ann_span(src, ns, nl)
  if an.n == 0 { return 0 }
  rv_arrty_nel(src, an.s, an.n)
}

## The declared ELEMENT type span of the same, else {0,0}.
rv_ann_arr_elem := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  if ex_is_array_lit(v) { return r }
  an := rv_ann_span(src, ns, nl)
  if an.n != 0 { r = rv_arrty_elem(src, an.s, an.n) }
  r
}

## The frame WORDS of a declaration `name : [E; N]` with no array-literal initializer, else 0. Gated on
## the annotation being the FIXED-ARRAY form so nothing else (a struct / generic / scalar annotation)
## changes its `rv_val_words` sizing — those keep resolving from the value exactly as before.
rv_ann_arr_words := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if ex_is_array_lit(v) { return 0 }
  an := rv_ann_span(src, ns, nl)
  if an.n == 0 { return 0 }
  if arrty_semi(src, an.s, an.n) == 0 { return 0 }
  rv_tyname_words(src, an.s, an.n, a, decls)
}

## The `: T` annotation at the DECLARATION SITE of the LOCAL `[ns,nl]` (an `Expr::Var` carries the span
## of its USE, not of the binding), or {0,0}. Same scan shape as `rv_is_array_local` — every Stmt kind
## is walked past, so a local declared after any statement is still found.
rv_local_ann_span := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { r = rv_ann_span(src, ans, anl) }
      _ => {}
    }
  }
  r
}

## The DECLARED fixed-array type span of the local `[ns,nl]` (`mut xs : [Cell; 3]` → `[Cell; 3]`), or
## {0,0}. This is the only place a LOCAL's array TYPE (rather than its literal) is recovered.
rv_local_arrty_span := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  an := rv_local_ann_span(head, src, ns, nl, a)
  if an.n == 0 { return r }
  if arrty_semi(src, an.s, an.n) != 0 { r = an }
  r
}

## --- DEEP AGGREGATE PLACES (Types §9.4): an ADDRESS composed from a frame-local root + N hops ---
## `xs[i].b.c.cx`, `xs[i].arr[j]`, `b.cells[i].m` — an arbitrary chain of FIELD and INDEX hops rooted at
## a struct or fixed-array LOCAL. The one-hop element paths address `element base + field offset` with a
## CLOSED formula; anything deeper (a second field hop, or an index into an inline `[T; N]` FIELD) has no
## such formula, so every such access was fail-loud. These resolvers COMPOSE it instead:
##   rv_place_ty        — the TYPE span AT each hop, so the next hop's field offset / element stride is known
##   rv_place_ok        — every hop resolvable and the root a real frame slot (else keep the `ebreak`)
##   emit_rv_place_addr — the address itself into a0: a FIELD hop adds `woff*8`; an INDEX hop pushes the
##                        base, evaluates the index (which clobbers every scratch register), scales it by
##                        the element words and adds the popped base back
## The LEAF load/store is a SINGLE word, gated on the leaf type being SCALAR — an aggregate leaf stays
## fail-loud. Mirrors lower.al's resolve_idx_field_place / arr_field_elem composition. FRAME-LOCAL roots
## only (a param / bind / global root is rejected): those keep their existing shallow paths, and a deep
## chain over one still traps rather than guessing an addressing mode.

## The TYPE span of the place `e` — a struct name, a `[E; N]` array-type span, or a scalar type name.
## A root Var takes its LOCAL's struct type, else its DECLARED fixed-array type; a Field hop takes the
## field's type within its (plain struct) base; an Index hop takes its base array type's element.
rv_place_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  ## ONE `mut` accumulator + a bare `return r`, never `return <nested-call>` for a struct result: that
  ## shape is the lean lower's documented mis-lower. Same reason the flags below are separate `mut` bools.
  mut r := CSpan(s = 0, n = 0)
  if unchecked bitcast(usize, e) == 0 { return r }
  if ex_is_field(e) {
    bt := rv_place_ty(rv_field_base(e), body_head, src, a, decls)
    mut fok := false
    if bt.n != 0 {
      if struct_decl_of(decls, src, bt.s, bt.n) >= 0 {
        if struct_plain(decls, src, bt.s, bt.n) { fok = true }
      }
    }
    if fok { r = field_type_span(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) }
    return r
  }
  if ex_is_index(e) {
    bt := rv_place_ty(ex_index_base(e), body_head, src, a, decls)
    if bt.n != 0 { r = rv_arrty_elem(src, bt.s, bt.n) }
    return r
  }
  vns := ex_var_ns(e)
  vnl := ex_var_nl(e)
  if vnl == 0 { return r }
  lsn := rv_local_struct_nl(body_head, src, vns, vnl, a)
  if lsn != 0 { r = CSpan(s = rv_local_struct_ns(body_head, src, vns, vnl, a), n = lsn) }
  if lsn == 0 { r = rv_local_arrty_span(body_head, src, vns, vnl, a) }
  r
}

## Can `base[…]` be addressed as an aggregate/array element? (`base` resolvable, its type a `[E; N]`
## form, and E's word width known.) The INDEX-hop half of rv_place_ok, split out so the statement
## forms — which carry the base and the index as SEPARATE fields, with no `Expr::Index` node to pass —
## can ask the same question.
rv_place_idx_ok := fn(base : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if not rv_place_ok(base, body_head, src, params_head, pcount, a, decls) { return r }
  bt := rv_place_ty(base, body_head, src, a, decls)
  if bt.n == 0 { return r }
  if arrty_semi(src, bt.s, bt.n) == 0 { return r }
  et := rv_arrty_elem(src, bt.s, bt.n)
  if et.n == 0 { return r }
  if rv_arr_elem_stride_bytes(src, et.s, et.n, a, decls) > 0 { r = true }
  r
}

## The ELEMENT type span of `base[…]`, else {0,0} — the statement-form twin of rv_place_ty's Index hop.
rv_place_idx_ty := fn(base : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  bt := rv_place_ty(base, body_head, src, a, decls)
  if bt.n != 0 { r = rv_arrty_elem(src, bt.s, bt.n) }
  r
}

## Is EVERY hop of the place `e` resolvable, with a frame-LOCAL root? A param / match-binding / global
## root is rejected (their storage is by-reference or label-based, addressed by the existing paths).
rv_place_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if unchecked bitcast(usize, e) == 0 { return r }
  if ex_is_field(e) {
    fbase := rv_field_base(e)
    if not rv_place_ok(fbase, body_head, src, params_head, pcount, a, decls) { return r }
    bt := rv_place_ty(fbase, body_head, src, a, decls)
    if bt.n == 0 { return r }
    if struct_decl_of(decls, src, bt.s, bt.n) < 0 { return r }
    if not struct_plain(decls, src, bt.s, bt.n) { return r }
    mut foffok := field_word_offset(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) >= 0
    if rv_std_idx_path_ok(e, body_head, src, a, decls) { foffok = layout_field_offset_bytes(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) >= 0 }
    if foffok { r = true }
    return r
  }
  if ex_is_index(e) {
    if rv_place_idx_ok(ex_index_base(e), body_head, src, params_head, pcount, a, decls) { r = true }
    return r
  }
  vns := ex_var_ns(e)
  vnl := ex_var_nl(e)
  if vnl == 0 { return r }
  if rv_param_find(params_head, src, vns, vnl, a) >= 0 { return r }
  pt := rv_place_ty(e, body_head, src, a, decls)
  if pt.n == 0 { return r }
  if rv_local_off(body_head, src, vns, vnl, pcount, a, decls) >= 0 { r = true }
  r
}

## Emit the ADDRESS of `base[idx]` into a0 (assumes rv_place_idx_ok). The base address is PUSHED before
## the index expression runs — that emit clobbers every scratch register — then the scaled index is added
## to the popped base. Bounds vs the array type's STATIC element count, dropped under `unchecked` (CG-7);
## `bltu` also traps a negative i64 index (a huge unsigned).
emit_rv_place_idx_addr := fn(base : ptr(Expr), idx : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  bt := rv_place_ty(base, body_head, src, a, decls)
  et := rv_arrty_elem(src, bt.s, bt.n)
  estride := rv_arr_elem_stride_bytes(src, et.s, et.n, a, decls)
  nel := rv_arrty_nel(src, bt.s, bt.n)
  emit_rv_place_addr(base, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
  emit_rv_expr(idx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  if RV_CHK {
    if nel > 0 { push_str(sb, "  li a1, ") ; push_int(sb, nel) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
  }
  push_str(sb, "  li a1, ") ; push_int(sb, estride) ; push_str(sb, "\n  mul a0, a0, a1\n  ld a1, 0(sp)\n  addi sp, sp, 16\n  add a0, a0, a1\n")
}

## Emit the ADDRESS of the place `e` into a0 (assumes rv_place_ok). Flat standalone ifs — an if/else-if
## chain as a fn body reads as a tail value-if under the lean lower. `li`+`add` (never a bare `addi`)
## for both the frame base and a field offset: an `addi` immediate is only 12 bits, and a deep frame or
## a wide struct can exceed it — a truncated immediate would be a SILENT wrong address.
emit_rv_place_addr := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  isf := ex_is_field(e)
  isi := ex_is_index(e)
  if isf {
    fbase := rv_field_base(e)
    bt := rv_place_ty(fbase, body_head, src, a, decls)
    mut boff := i64(field_word_offset(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a)) * 8
    if rv_std_idx_path_ok(e, body_head, src, a, decls) { boff = layout_field_offset_bytes(decls, src, bt.s, bt.n, rv_field_fns(e), rv_field_fnl(e), a) }
    emit_rv_place_addr(fbase, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    if boff > 0 { push_str(sb, "  li a1, ") ; push_int(sb, boff) ; push_str(sb, "\n  add a0, a0, a1\n") }
  }
  if isi {
    emit_rv_place_idx_addr(ex_index_base(e), ex_index_idx(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  }
  if (not isf) and (not isi) {
    voff := rv_local_off(body_head, src, ex_var_ns(e), ex_var_nl(e), pcount, a, decls)
    push_str(sb, "  li a0, ") ; push_int(sb, voff) ; push_str(sb, "\n  add a0, a0, s0\n")
  }
}

## Is the place `e` a fully-composable DEEP place with a SCALAR one-word leaf? The single gate every deep
## read/write site shares: address composable + the leaf a scalar type. An aggregate leaf (a whole
## struct/array through a deep chain) stays fail-loud — it needs multi-word delivery, not a `ld`/`sd`.
rv_deep_scalar_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if not rv_place_ok(e, body_head, src, params_head, pcount, a, decls) { return r }
  ty := rv_place_ty(e, body_head, src, a, decls)
  if ty.n == 0 { return r }
  if ty_is_scalar(ty.s, ty.n, decls, src) { r = true }
  r
}


rv_local_ann_signed := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
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
## The `:=` RHS expr of a top-level local (0 if not found) — lets a signedness query recover an un-annotated
## `b := shr(s, 1)`'s type from the shift RHS (OP-6: shl/shr/rotl/rotr return the left operand's type). The
## non-x86 backends read source annotations, so without this `b / 2` chose unsigned `divu` → silent miscompile.
rv_local_rhs := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> ptr(Expr) {
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
rv_shift_call_signed := fn(v : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(v) {
    Expr::Call(cs, cl, na, ah) => {
      cn := str_at((src + cs), cl)
      if cn == "shl" or cn == "shr" or cn == "rotl" or cn == "rotr" { if rv_operand_signed(arg_expr_at(ah, 0, a), params_head, body_head, src, a) { r = true } }
    }
    _ => {}
  }
  r
}
rv_operand_signed := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(e) {
    Expr::Var(s, n) => {
      if param_ann_signed(params_head, src, s, n, a) { r = true }
      if rv_local_ann_signed(body_head, src, s, n, a) { r = true }
      if r == false { rhs := rv_local_rhs(body_head, src, s, n, a); if unchecked bitcast(usize, rhs) != 0 { if rv_shift_call_signed(rhs, params_head, body_head, src, a) { r = true } } }
    }
    Expr::Call(cs, cl, na, ah) => { cn := str_at((src + cs), cl) ; if cn == "i8" or cn == "i16" or cn == "i32" or cn == "i64" or cn == "isize" { r = true } }
    _ => {}
  }
  r
}

rv_local_ann_unsigned := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
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
rv_unchecked_init_unsigned := fn(v : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(v) {
    Expr::Unchecked(inner) => { r = rv_operand_unsigned(inner, params_head, body_head, src, a) }
    _ => {}
  }
  r
}
rv_operand_unsigned := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(e) {
    Expr::Var(s, n) => {
      if param_ann_unsigned(params_head, src, s, n, a) { r = true }
      if rv_local_ann_unsigned(body_head, src, s, n, a) { r = true }
      ## un-annotated `s := unchecked (<init>)` — recover the unsignedness the wrapper swallowed
      ## (mirrors the SIGNED side's `rv_shift_call_signed` recovery two functions above).
      if r == false { rhs := rv_local_rhs(body_head, src, s, n, a); if unchecked bitcast(usize, rhs) != 0 { if rv_unchecked_init_unsigned(rhs, params_head, body_head, src, a) { r = true } } }
    }
    Expr::Call(cs, cl, na, ah) => { cn := str_at((src + cs), cl) ; if cn == "u8" or cn == "u16" or cn == "u32" or cn == "u64" or cn == "usize" { r = true } }
    ## The two SHAPES that CARRY an operand's unsignedness but have no annotation of their own, so the
    ## source scan above could never prove them unsigned and the comparison fell back to the always-
    ## SIGNED `slt` — a `u64` word above 2^63 then ordered as NEGATIVE and `0 < 18446744073709551610`
    ## answered FALSE (a valid binary, a normal exit, a wrong value):
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
    Expr::Unchecked(inner) => { r = rv_operand_unsigned(inner, params_head, body_head, src, a) }
    Expr::Bin(op, bl, br) => {
      if op == 16 or op == 17 or op == 18 or op == 19 or op == 29 or op == 34 or op == 35 or op == 36 {
        ul := rv_operand_unsigned(bl, params_head, body_head, src, a)
        ur := rv_operand_unsigned(br, params_head, body_head, src, a)
        if ul and ur { r = true }
        if ul and ex_is_num_lit(br) { r = true }
        if ur and ex_is_num_lit(bl) { r = true }
      }
    }
    _ => {}
  }
  r
}
## PROVABLY UNSIGNED ordering comparison iff BOTH operands are provably unsigned, OR one operand is
## provably unsigned and the other is a bare integer LITERAL. Requiring the NON-LITERAL side to be
## PROVEN unsigned keeps the conservative character: it only ever moves signed → unsigned, never the
## reverse, so a mixed/unknown pair still keeps the signed default.
rv_cmp_unsigned := fn(l : ptr(Expr), r : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  ul := rv_operand_unsigned(l, params_head, body_head, src, a)
  ur := rv_operand_unsigned(r, params_head, body_head, src, a)
  if ul and ur { return true }
  if ul and ex_is_num_lit(r) { return true }
  if ur and ex_is_num_lit(l) { return true }
  false
}

rv_local_narrow := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> str {
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
rv_operand_narrow := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> str {
  mut r := ""
  match deref(e) {
    Expr::Var(s, n) => {
      mut p := params_head
      while p != 0 { pm := deref(param_p(p)) ; if streq(src, pm.ns, pm.nl, s, n) { nn := scalar_name_narrow(src, pm.ts, pm.tl) ; if nn != "" { r = nn } } ; p = pm.next }
      if r == "" { r = rv_local_narrow(body_head, src, s, n, a) }
    }
    Expr::Call(cs, cl, na, ah) => { r = scalar_name_narrow(src, cs, cl) }
    _ => {}
  }
  r
}

rv_emit_arith := fn(op : u8, dsigned : bool, narrow : bool, in out sb : rt::StrBuf) {
  ## CHECKED div-by-zero (I11 / CG-7): RV64 `div`/`rem` by 0 does NOT trap (returns all-ones / the
  ## dividend per the ISA), a silent wrong result unlike x86_64 `idivq` #DE. Trap (`ebreak`) when the
  ## divisor a1 is 0. Dropped under `unchecked` (RV_CHK false). `1f`/`1:` is self-contained (a1 already
  ## holds the fully-evaluated divisor). Mirrors x86_64's routed num.al div guard.
  if RV_CHK {
    if op == 19 or op == 29 {
      push_str(sb, "  bnez a1, 1f\n  ebreak\n1:\n")
      ## CHECKED `MIN / -1` (I11 / CG-8 division overflow, CG-13 one mechanism): RV64 `div`/`rem` of
      ## INT64_MIN by -1 does NOT trap — the ISA defines the quotient as INT64_MIN (and the remainder 0),
      ## a wrong value for a checked divide. Trap (`ebreak`) when a1 == -1 AND a0 == INT64_MIN
      ## (`li a3, 1; slli a3, a3, 63` materializes INT64_MIN; no 64-bit immediate compare exists).
      ## a2/a3 are dead scratch. Dropped under `unchecked` with the div-by-zero guard above.
      if dsigned { push_str(sb, "  li a2, -1\n  bne a1, a2, 1f\n  li a3, 1\n  slli a3, a3, 63\n  bne a0, a3, 1f\n  ebreak\n1:\n") }
    }
  }
  ## CHECKED overflow on `+` (I11 / CG-8): RISC-V has no flags, so mirror num.al's comparison. Sum in
  ## a2; UNSIGNED overflow iff sum <u a (`sltu`); SIGNED overflow iff (out^a)&(out^b) has its sign bit
  ## set (`bgez` skips when clear). Trap (`ebreak`). Dropped under `unchecked` (RV_CHK false) and skipped
  ## for a narrow width. POINTER offsetting routes through `rt::addr` (unchecked). a2/a3/a4 dead scratch.
  if op == 16 {
    if RV_CHK and (not narrow) {
      push_str(sb, "  add a2, a0, a1\n")
      if dsigned { push_str(sb, "  xor a3, a2, a0\n  xor a4, a2, a1\n  and a3, a3, a4\n  mv a0, a2\n  bgez a3, 1f\n  ebreak\n1:\n") }
      else { push_str(sb, "  sltu a3, a2, a0\n  mv a0, a2\n  beqz a3, 1f\n  ebreak\n1:\n") }
    } else {
      push_str(sb, "  add a0, a0, a1\n")
    }
  }
  ## CHECKED underflow/overflow on `-` (I11 / CG-8): no flags — UNSIGNED borrow iff a0 <u a1 (`sltu`,
  ## computed BEFORE the sub); SIGNED overflow iff (a^b)&(a^out) sign-bit set. Trap (`ebreak`). Pointer
  ## DIFFERENCE routes through `rt::off` (unchecked). Dropped under `unchecked`; narrow wraps.
  if op == 17 {
    if RV_CHK and (not narrow) {
      if dsigned { push_str(sb, "  sub a2, a0, a1\n  xor a3, a0, a1\n  xor a4, a0, a2\n  and a3, a3, a4\n  mv a0, a2\n  bgez a3, 1f\n  ebreak\n1:\n") }
      else { push_str(sb, "  sltu a3, a0, a1\n  sub a0, a0, a1\n  beqz a3, 1f\n  ebreak\n1:\n") }
    } else {
      push_str(sb, "  sub a0, a0, a1\n")
    }
  }
  ## CHECKED overflow on `*` (I11 / CG-8): the high half — UNSIGNED via `mulhu` (nonzero → overflow),
  ## SIGNED via `mulh` compared to the low product's sign-extension (`srai 63`). `mul` gives the low
  ## word. Trap (`ebreak`). Dropped under `unchecked`; narrow wraps.
  if op == 18 {
    if RV_CHK and (not narrow) {
      if dsigned { push_str(sb, "  mulh a2, a0, a1\n  mul a0, a0, a1\n  srai a3, a0, 63\n  beq a2, a3, 1f\n  ebreak\n1:\n") }
      else { push_str(sb, "  mulhu a2, a0, a1\n  mul a0, a0, a1\n  beqz a2, 1f\n  ebreak\n1:\n") }
    } else {
      push_str(sb, "  mul a0, a0, a1\n")
    }
  }
  ## Divide `/` (19) / remainder `%` (29): SIGNED `div`/`rem` only when an operand is a known `iN`
  ## (`dsigned`); otherwise UNSIGNED `divu`/`remu` — the Alatyr scalar default. Formerly always the
  ## signed forms, which read a high-bit `u64` as negative (a silent wrong result vs x86_64 `divq`).
  if op == 19 {
    if dsigned { push_str(sb, "  div a0, a0, a1\n") } else { push_str(sb, "  divu a0, a0, a1\n") }
  }
  if op == 29 {
    if dsigned { push_str(sb, "  rem a0, a0, a1\n") } else { push_str(sb, "  remu a0, a0, a1\n") }
  }
  if op == 34 { push_str(sb, "  and a0, a0, a1\n") }
  if op == 40 { push_str(sb, "  and a0, a0, a1\n") }
  if op == 35 { push_str(sb, "  or a0, a0, a1\n") }
  if op == 41 { push_str(sb, "  or a0, a0, a1\n") }
  if op == 36 { push_str(sb, "  xor a0, a0, a1\n") }
  known := op == 16 or op == 17 or op == 18 or op == 19 or op == 29 or op == 34 or op == 35 or op == 36 or op == 40 or op == 41
  if not known { push_str(sb, "  ebreak\n") }
}

## Emit `a0 <- (a0 <cmp> a1) ? 1 : 0` for a comparison op byte (RV64 has no flag/cset — build 0/1 from
## slt/seqz/snez, standalone ifs). Ordering (`<`/`>`/`<=`/`>=`) uses SIGNED `slt` by DEFAULT; when `uns`
## (BOTH operands provably unsigned, `rv_cmp_unsigned`) it uses UNSIGNED `sltu` so a `u64`/`usize`
## comparison across 2^63 (`0 < u64::MAX`) is correct instead of reading the high-bit operand as
## negative — the exact `slt`→`sltu` dual, mirroring the x86_64 `is_unsigned_cmp` gate. `eq`/`ne` are
## sign-agnostic and unchanged.
rv_emit_cmp := fn(op : u8, uns : bool, in out sb : rt::StrBuf) {
  if op == 20 { push_str(sb, "  sub a0, a0, a1\n  seqz a0, a0\n") }
  if op == 28 { push_str(sb, "  sub a0, a0, a1\n  snez a0, a0\n") }
  if op == 24 { if uns { push_str(sb, "  sltu a0, a0, a1\n") } else { push_str(sb, "  slt a0, a0, a1\n") } }
  if op == 25 { if uns { push_str(sb, "  sltu a0, a1, a0\n") } else { push_str(sb, "  slt a0, a1, a0\n") } }
  if op == 26 { if uns { push_str(sb, "  sltu a0, a1, a0\n  xori a0, a0, 1\n") } else { push_str(sb, "  slt a0, a1, a0\n  xori a0, a0, 1\n") } }
  if op == 27 { if uns { push_str(sb, "  sltu a0, a0, a1\n  xori a0, a0, 1\n") } else { push_str(sb, "  slt a0, a0, a1\n  xori a0, a0, 1\n") } }
}

## Width-narrowing of the value in a0 for `name(x)` (mirrors x86_64 emit_int_narrow_reg): ZERO-extend
## the low N bits for a `uN`, SIGN-extend for an `iN`. RV64I has no byte/half extend op, so zero-extend
## is a shift-left/shift-right-logical pair and sign-extend a shift-left/shift-right-arithmetic pair
## (`i32` uses `addiw …, 0`, the canonical RV64 sign-extend-word). Native widths emit nothing.
rv_emit_narrow := fn(name : str, in out sb : rt::StrBuf) {
  if name == "u8" { push_str(sb, "  andi a0, a0, 255\n") }
  else if name == "u16" { push_str(sb, "  slli a0, a0, 48\n  srli a0, a0, 48\n") }
  else if name == "u32" { push_str(sb, "  slli a0, a0, 32\n  srli a0, a0, 32\n") }
  else if name == "i8" { push_str(sb, "  slli a0, a0, 56\n  srai a0, a0, 56\n") }
  else if name == "i16" { push_str(sb, "  slli a0, a0, 48\n  srai a0, a0, 48\n") }
  else if name == "i32" { push_str(sb, "  addiw a0, a0, 0\n") }
}
## CHECKED narrow-width OVERFLOW trap (I11 / CG-6/CG-8) — the RV64 dual of `emit_int_narrow_reg`: the
## 64-bit result in a0 must fit the narrow type, else `ebreak`. UNSIGNED `uN` overflows iff any bit above
## bit N is set (`srli` nonzero); SIGNED `iN` overflows iff the sign-extension of the low N bits differs
## from a0. Emitted BEFORE the value-model wrap; the caller gates on `RV_CHK` and a non-`0 - x` negation.
rv_emit_narrow_trap := fn(name : str, in out sb : rt::StrBuf) {
  if name == "u8" { push_str(sb, "  srli a2, a0, 8\n  beqz a2, 1f\n  ebreak\n1:\n") }
  else if name == "u16" { push_str(sb, "  srli a2, a0, 16\n  beqz a2, 1f\n  ebreak\n1:\n") }
  else if name == "u32" { push_str(sb, "  srli a2, a0, 32\n  beqz a2, 1f\n  ebreak\n1:\n") }
  else if name == "i8" { push_str(sb, "  slli a2, a0, 56\n  srai a2, a2, 56\n  beq a2, a0, 1f\n  ebreak\n1:\n") }
  else if name == "i16" { push_str(sb, "  slli a2, a0, 48\n  srai a2, a2, 48\n  beq a2, a0, 1f\n  ebreak\n1:\n") }
  else if name == "i32" { push_str(sb, "  addiw a2, a0, 0\n  beq a2, a0, 1f\n  ebreak\n1:\n") }
}

## ── FLOAT value model (rv64 dual of the aarch64 float path) — IEEE bits ride the integer path (a0 /
## frame slot / .data cell); only arith/conversion/ABI touch the FP (ft/fa) registers. ──────────────
rv_floatlit_ss := fn(e : ptr(Expr)) -> usize { mut r := 0 ; match deref(e) { Expr::FloatLit(fs, fl) => { r = fs } _ => {} } ; r }
rv_floatlit_sl := fn(e : ptr(Expr)) -> usize { mut r := 0 ; match deref(e) { Expr::FloatLit(fs, fl) => { r = fl } _ => {} } ; r }
rv_is_floatlit := fn(e : ptr(Expr)) -> bool { mut r := false ; match deref(e) { Expr::FloatLit(fs, fl) => { r = true } _ => {} } ; r }
## Is module GLOBAL `[ns,nl)` float (`: f64` annotation OR inferred FloatLit init)? Null-guards d.value.
rv_global_is_float := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut r := false
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    if d.kind == 0 and d.name_len != 0 {
      if streq(src, d.name_start, d.name_len, ns, nl) {
        if ann_scan_float(src, d.name_start + d.name_len) { r = true }
        if unchecked bitcast(usize, d.value) != 0 { if rv_is_floatlit(d.value) { r = true } }
      }
    }
    i += 1
  }
  r
}
rv_param_is_float := fn(params_head : ptr(mut Param), src : ptr(u8), idx : i64, a : rt::Arena) -> bool {
  mut p := params_head ; mut i := 0 ; mut r := false
  while p != 0 { pm := deref(param_p(p)) ; if i == idx { if pm.pmode == 0 and scalar_name_is_float(src, pm.ts, pm.tl) { r = true } } ; i += 1 ; p = pm.next }
  r
}
## An OUT/IN-OUT scalar parameter is a pointer slot even when its declared scalar is f64/f32. Keep this
## single predicate shared by the caller address path, the callee Var/Assign paths, and the forwarding
## case where an OUT parameter is passed on to another OUT parameter. Aggregate OUT params already use
## their type-driven by-reference paths, so pmode 2 alone must not steal those paths.
rv_param_out_scalar := fn(params_head : ptr(mut Param), src : ptr(u8), decls : ptr(rt::Vec), idx : i64) -> bool {
  mut p := params_head
  mut i := 0
  while p != 0 {
    pm := deref(param_p(p))
    if i == idx {
      if pm.pmode != 2 { return false }
      if struct_decl_of(decls, src, pm.ts, pm.tl) >= 0 { return false }
      if enum_decl_of(decls, src, pm.ts, pm.tl) >= 0 { return false }
      if str_at((src + pm.ts), pm.tl) == "str" { return false }
      if str_at((src + pm.ts), pm.tl) == "ptr" {
        if enum_decl_of(decls, src, pm.pps, pm.ppl) >= 0 { return false }
        if struct_decl_of(decls, src, pm.pps, pm.ppl) >= 0 { return false }
      }
      return true
    }
    i += 1
    p = pm.next
  }
  false
}
rv_callee_params := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) -> usize {
  cnt := rt::vec_len(deref(decls)) ; mut i := 0 ; mut r := 0
  while i < cnt { d := deref(decl_at(Decl, rt::vec_get(deref(decls), i))) ; if d.is_fn and d.name_len != 0 { if streq(src, d.name_start, d.name_len, cs, cl) { r = d.params_head } } ; i += 1 }
  r
}
## Emit one scalar OUT/IN-OUT argument as a place address. A caller's own OUT parameter forwards the
## pointer stored in its slot; an ordinary scalar param/local contributes the address of its slot. This
## is the RV64 dual of lower::emit_out_scalar_arg and keeps the caller-side ABI decision in one place.
rv_emit_out_scalar_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  mut done := false
  match deref(e) {
    Expr::Var(ns, nl) => {
      pidx := rv_param_find(params_head, src, ns, nl, a)
      mut off := rv_local_off(body_head, src, ns, nl, pcount, a, decls)
      if pidx >= 0 { off = 16 + pidx * 8 }
      if pidx >= 0 {
        if rv_param_out_scalar(params_head, src, decls, pidx) { push_str(sb, "  ld a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n") ; done = true }
        if not rv_param_out_scalar(params_head, src, decls, pidx) { push_str(sb, "  addi a0, s0, ") ; push_int(sb, off) ; push_str(sb, "\n") ; done = true }
      }
      isagg := nl != 0 and (rv_local_struct_nl(body_head, src, ns, nl, a) != 0 or rv_is_array_local(body_head, src, ns, nl, a))
      if pidx < 0 and off >= 0 and not isagg { push_str(sb, "  addi a0, s0, ") ; push_int(sb, off) ; push_str(sb, "\n") ; done = true }
      if pidx < 0 and rv_is_global(decls, src, ns, nl) { push_str(sb, "  la a0, ") ; push_str(sb, str_at((src + ns), nl)) ; push_str(sb, "\n") ; done = true }
    }
    _ => {}
  }
  if not done { emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
}
## The ENUM span a CALL `f(…)` returns by value, or 0/0 — non-zero ONLY for a call to a DEFINED fn whose
## return type is an enum of 1..8 words (§8 piece 3 register enum-return convention: word 0 = disc, word
## k+1 = payload in a0..a7). Sizes an enum-returning-call-bound LOCAL + materializes such an ARG by ref.
rv_call_ret_enum_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  cs := rv_call_ns(v)
  cl := rv_call_nl(v)
  mut rs := 0
  mut rn := 0
  if cl != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
      if d.is_fn and d.name_len != 0 and streq(src, d.name_start, d.name_len, cs, cl) {
        bn := base_type_name(src, d.ret_ts, d.ret_tl)
        ## GENERICS (§8): a generic callee returning `T` — resolve the EXPLICIT type-arg (arg 0) so
        ## `m := id(E, …)` sees the concrete enum `E`. Byte-compare; ebs/ebn = effective base span.
        mut ebs := bn.s
        mut ebn := bn.n
        if d.is_generic {
          tpn := rv_tparam_name(d, src)
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
## The STRUCT span a CALL `f(…)` returns by value, or 0/0 — non-zero ONLY when `v` is a call to a DEFINED
## fn whose return type is an ALL-SCALAR struct of 1..8 words (the §8 register struct-return convention,
## piece 2: the callee delivers word k in a_k, a0..a7). Used to size a struct-returning-call-bound LOCAL,
## resolve its `.field` reads, and materialize a struct-returning-call ARGUMENT by reference. Restricting
## to all-scalar ≤8-word keeps the convention self-consistent; a wider/str/float return stays a LOUD trap.
rv_call_ns := fn(e : ptr(Expr)) -> usize { mut r := 0 ; match deref(e) { Expr::Call(cs, cl, n, ah) => { r = cs } _ => {} } ; r }
rv_call_nl := fn(e : ptr(Expr)) -> usize { mut r := 0 ; match deref(e) { Expr::Call(cs, cl, n, ah) => { r = cl } _ => {} } ; r }
rv_call_ret_struct_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  cs := rv_call_ns(v)
  cl := rv_call_nl(v)
  mut rs := 0
  mut rn := 0
  if cl != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
      if d.is_fn and d.name_len != 0 and streq(src, d.name_start, d.name_len, cs, cl) {
        bn := base_type_name(src, d.ret_ts, d.ret_tl)
        ## GENERICS (§8): a generic callee returning `T` — resolve the call's EXPLICIT type-arg (arg 0) so
        ## `p := id(P, …)` sees the concrete struct `P`. Byte-compare; ebs/ebn = effective base span.
        mut ebs := bn.s
        mut ebn := bn.n
        if d.is_generic {
          tpn := rv_tparam_name(d, src)
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
        ## Any PLAIN struct of 1..8 words rides the register struct-return (word k → a_k) — the delivery is a
        ## type-agnostic word copy, so a struct with an ENUM / str field (not all-scalar) works too. The
        ## arity-0 guard in rv_ret_struct_words keeps a comptime-value-param type-fn (`uint(N)`) out.
        if ebn != 0 and rv_ret_struct_words(decls, src, ebs, ebn, a) >= 1 { rs = ebs ; rn = ebn }
        if rv_fn_returns_tuple(d, src) {
          tw := rv_tuple_words(src, d.ret_ts, d.ret_tl)
          if tw >= 1 and tw <= 7 { rs = d.ret_ts ; rn = d.ret_tl }
        }
      }
      i = i + 1
    }
  }
  CSpan(s = rs, n = rn)
}
## The WIDE-struct span a CALL `f(…)` returns via the LP64 INDIRECT RESULT (SRET), or 0/0 — non-zero ONLY
## for a direct call to a DEFINED, NON-GENERIC fn of arity <= 7 whose return type is a plain struct wider
## than 8 words. The arity gate keeps the shifted argument registers inside a1..a7 (a0 carries the result
## pointer); a generic callee is out of scope (its instance return type is not resolved here) and stays a
## LOUD trap. Disjoint from rv_call_ret_struct_span (1..8 words) by the width split.
rv_call_ret_sret_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  cs := rv_call_ns(v)
  cl := rv_call_nl(v)
  mut rs := 0
  mut rn := 0
  if cl != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
      ok := d.is_fn and d.name_len != 0
      if ok and streq(src, d.name_start, d.name_len, cs, cl) {
        bn := base_type_name(src, d.ret_ts, d.ret_tl)
        mut ebs := bn.s
        mut ebn := bn.n
        if d.is_generic {
          tpn := rv_tparam_name(d, src)
          mut retmatch := false
          if tpn.n != 0 and d.ret_tl == tpn.n {
            rrb := bytes(str_at((src + d.ret_ts), d.ret_tl))
            grb := bytes(str_at((src + tpn.s), tpn.n))
            mut eqk := true
            mut bj := 0
            while bj < d.ret_tl { if rrb[bj] != grb[bj] { eqk = false } ; bj = bj + 1 }
            retmatch = eqk
          }
          if retmatch {
            ah := ex_call_argh(v)
            if arg_list_count(ah, a) == i64(d.arity) {
              ea := arg_expr_at(ah, usize(decl_tparam_pos(d, src)), a)
              ebs = ex_var_ns(ea)
              ebn = ex_var_nl(ea)
              if ebn == 0 { tt := tuple_typearg_span(ea, src, a) ; ebs = tt.s ; ebn = tt.n }
            }
          }
        }
        if ebn != 0 and rv_ret_sret_words(decls, src, ebs, ebn, a) >= 1 { rs = ebs ; rn = ebn }
      }
      i = i + 1
    }
  }
  CSpan(s = rs, n = rn)
}
## The WIDE-ENUM span a CALL `f(…)` returns via the LP64 INDIRECT RESULT, or 0/0 — the enum analogue of
## rv_call_ret_sret_span: non-zero ONLY for a direct call to a DEFINED, NON-GENERIC fn of arity <= 7 whose
## return type is an enum whose {disc, payload…} width EXCEEDS the 8-register budget. Such a call delivers
## through the a0 result pointer (the callee writes the whole block into the caller-supplied destination);
## used to SIZE + TYPE the bound local and to route the a0 hand-off. Disjoint from rv_call_ret_enum_span
## (the 1..8-word register gate) by the width split; a generic wide-enum return stays a LOUD trap.
rv_call_ret_enum_sret_span := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> CSpan {
  cs := rv_call_ns(v)
  cl := rv_call_nl(v)
  mut rs := 0
  mut rn := 0
  if cl != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
      ok := d.is_fn and d.name_len != 0
      if ok and streq(src, d.name_start, d.name_len, cs, cl) {
        bn := base_type_name(src, d.ret_ts, d.ret_tl)
        mut ebs := bn.s
        mut ebn := bn.n
        if d.is_generic {
          tpn := rv_tparam_name(d, src)
          mut retmatch := false
          if tpn.n != 0 and d.ret_tl == tpn.n {
            rrb := bytes(str_at((src + d.ret_ts), d.ret_tl))
            grb := bytes(str_at((src + tpn.s), tpn.n))
            mut eqk := true
            mut bj := 0
            while bj < d.ret_tl { if rrb[bj] != grb[bj] { eqk = false } ; bj = bj + 1 }
            retmatch = eqk
          }
          if retmatch {
            ah := ex_call_argh(v)
            if arg_list_count(ah, a) == i64(d.arity) {
              ea := arg_expr_at(ah, usize(decl_tparam_pos(d, src)), a)
              ebs = ex_var_ns(ea)
              ebn = ex_var_nl(ea)
              if ebn == 0 { tt := tuple_typearg_span(ea, src, a) ; ebs = tt.s ; ebn = tt.n }
            }
          }
        }
        if ebn != 0 and rv_ret_enum_sret_words(decls, src, ebs, ebn, a) >= 1 { rs = ebs ; rn = ebn }
      }
      i = i + 1
    }
  }
  CSpan(s = rs, n = rn)
}
rv_float_params_before := fn(params_head : ptr(mut Param), src : ptr(u8), idx : i64, a : rt::Arena) -> i64 {
  mut p := params_head ; mut i := 0 ; mut c := 0
  while p != 0 { pm := deref(param_p(p)) ; if i < idx { if scalar_name_is_float(src, pm.ts, pm.tl) { c += 1 } } ; i += 1 ; p = pm.next }
  c
}
## Does the LOCAL `[ns,nl)` name a float ARRAY (`xs := [<FloatLit>, …]`)? Mirrors rv_is_array_local's
## done-logic; first element float via the shared detector.
rv_array_is_float := fn(body_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec)) -> bool {
  mut s := body_head ; mut r := false ; mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and ex_is_array_lit(v) {
          eh := ex_array_lit_ehead(v)
          if eh != 0 { fe := arg_p(eh) ; if rv_is_float_expr(deref(fe).e, body_head, src, a, params_head, decls, 0) { r = true } }
          done = true
        }
        ## a slice-VIEW binding (`fv := base[lo..hi]`) inherits its backing array's element float-ness —
        ## recurse on the slice base (mirrors rv_iter_stride) so `fv[i]` reads via the float path.
        if streq(src, ans, anl, ns, nl) and ex_is_slice(v) {
          sb2 := ex_slice_base(v)
          if rv_array_is_float(body_head, src, ex_var_ns(sb2), ex_var_nl(sb2), a, params_head, decls) { r = true }
          done = true
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { s = nx }
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
rv_is_float_local := fn(body_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec), dep : i64) -> bool {
  if dep > 24 { return false }
  mut r := false
  d := lower_layout::local_decl_assign(body_head, src, ns, nl)
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { if ann_scan_float(src, ans + anl) { r = true } ; if rv_is_float_expr(v, body_head, src, a, params_head, decls, dep + 1) { r = true } }
      _ => {}
    }
  }
  r
}
rv_int_const_expr := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Num(_v, _s, _n) => { r = true }
    Expr::Bin(op, l, rr) => {
      if (op == 16 or op == 17 or op == 18) and rv_int_const_expr(l) and rv_int_const_expr(rr) { r = true }
    }
    _ => {}
  }
  r
}
rv_direct_float_num := fn(e : ptr(Expr), src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut r := false
  if ann_scan_float(src, ns + nl) { if rv_int_const_expr(e) { r = true } }
  r
}
rv_is_float_expr := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec), dep : i64) -> bool {
  if dep > 24 { return false }
  mut r := false
  match deref(e) {
    Expr::FloatLit(fs, fl) => { r = true }
    Expr::Var(ns, nl) => {
      if rv_is_float_local(body_head, src, ns, nl, a, params_head, decls, dep + 1) { r = true }
      if named_param_is_float(params_head, src, ns, nl, a) { r = true }
      if rv_global_is_float(decls, src, ns, nl) { r = true }
    }
    Expr::Bin(op, l, rr) => {
      if op == 16 or op == 17 or op == 18 or op == 19 {
        if rv_is_float_expr(l, body_head, src, a, params_head, decls, dep + 1) { r = true }
        if rv_is_float_expr(rr, body_head, src, a, params_head, decls, dep + 1) { r = true }
      }
    }
    Expr::Call(cs, cl, n, ah) => { nm := str_at((src + cs), cl) ; if nm == "f64" { r = true } ; if nm == "f32" { r = true } ; if callee_ret_is_float(decls, src, cs, cl) { r = true } }
    ## a struct FIELD of declared type f64/f32 (base a struct local or by-ref struct param).
    Expr::Field(base, fs, fl) => {
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      if bnl != 0 {
        lstl := rv_local_struct_nl(body_head, src, bns, bnl, a)
        if lstl != 0 { if field_type_is_float(decls, src, rv_local_struct_ns(body_head, src, bns, bnl, a), lstl, fs, fl, a) { r = true } }
        pstl := rv_param_struct_nl(params_head, src, bns, bnl, a, decls)
        if pstl != 0 { if field_type_is_float(decls, src, rv_param_struct_ns(params_head, src, bns, bnl, a, decls), pstl, fs, fl, a) { r = true } }
      }
    }
    ## an ARRAY element `xs[i]` whose array local has float elements.
    Expr::Index(base, idx) => {
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      if bnl != 0 { if rv_array_is_float(body_head, src, bns, bnl, a, params_head, decls) { r = true } }
    }
    _ => {}
  }
  r
}
## FN-return float flag (float ABI): result bits a0 → fa0 in the epilogue for a float-returning fn.
mut RV_RET_FLOAT := false
## FN-return STRUCT span (§8 piece 2, register struct-return convention): when the current fn returns an
## all-scalar struct of 1..8 words, holds its type name span (0/0 otherwise). Set per-fn in emit_rv_fn;
## read by the Return + trailing-value paths to route the value through emit_rv_struct_value (word k → a_k).
mut RV_RET_STRUCT_NS := 0
mut RV_RET_STRUCT_NL := 0
## FN-return ENUM span (§8 piece 3): when the fn returns an enum of 1..8 words, holds its type span (0/0
## otherwise). Read by Return + trailing-value to route the value through emit_rv_enum_value (word 0 = disc).
mut RV_RET_ENUM_NS := 0
mut RV_RET_ENUM_NL := 0
## FN-return WIDE-STRUCT (SRET) span: when the current fn returns a plain struct WIDER than the 8-word
## register budget, holds its type name span (0/0 otherwise). LP64 indirect result: the caller hands the
## destination address in a0, the prologue spills it to RV_SRET_SLOT, and each Return / the trailing value
## copies the struct THROUGH that pointer (emit_rv_sret_store). Mutually exclusive with RV_RET_STRUCT.
mut RV_RET_SRET_NS := 0
mut RV_RET_SRET_NL := 0
## Frame byte offset where an SRET fn spills the incoming result pointer (a0), so it survives nested calls
## and register churn to every Return point. Valid only while RV_RET_SRET_NL != 0.
mut RV_SRET_SLOT := 0
## WIDE-ENUM SRET (> 8 words): a fn returning an enum wider than the register budget delivers via the SAME
## LP64 indirect result (its span rides RV_RET_SRET_*, distinguished by enum_decl_of), so it reuses
## RV_SRET_SLOT for the incoming pointer and ADDITIONALLY needs a frame scratch block, sized to the enum's
## full {disc, payload…} width, where a `return E.V(…)` literal is materialized before the word-copy
## through the destination. Valid only while the current fn returns a wide enum.
mut RV_ENUM_SRET_BLK := 0
## CALLER-side hand-off for an SRET binding `s := mk(…)`: when ON, RV_SRET_DST is the frame byte offset of
## the destination local that the call arm turns into `addi a0, s0, <off>` right before the `call`. Cleared
## while the ARGUMENTS are emitted so a nested call cannot consume the same destination.
mut RV_SRET_DST_ON := false
mut RV_SRET_DST := 0
## INDIRECT flavour of the hand-off (the SRET TAIL-FORWARD `return mk(…)`): the destination is not a frame
## BLOCK of ours but the pointer the OUTER caller handed us, spilled at RV_SRET_SLOT. When ON, RV_SRET_DST
## names that SLOT and the call arm emits `ld a0, <slot>(s0)` instead of `addi a0, s0, <off>`, so the inner
## callee writes straight into the outer caller's block and nothing is copied afterwards.
mut RV_SRET_DST_IND := false
## SLICE-ARG agg-block allocator (§8 slice-param CALLER materialization; see aarch64's A64_AGG). `emit_rv_fn`
## reserves 2 words per slice-arg occurrence above the locals, sets RV_AGG to the first reserved byte offset
## and RV_AGG_LIM to the frame top; each materialized slice arg grabs the next 16 bytes. Overflow = loud ebreak.
mut RV_AGG := 0
mut RV_AGG_LIM := 0
## MATCH-over-INDEX temp region (§8 enum slice-param): a `match s[i]` on an enum `Slice(E)` PARAM
## materializes the by-reference element's enum words into this reserved frame region, then matches on it.
mut RV_MTMP := 0
## Current MATCH-ARM enum context (§8 piece 3b) — set/restored per arm in emit_rv_match_arms so an
## aggregate payload BINDING (`pt.x`, nested `match i`) resolves its type + frame offset (bind_base + 8).
mut RV_ARM_ENS := 0
mut RV_ARM_ENL := 0
mut RV_ARM_VS := 0
mut RV_ARM_VL := 0
## The AGGREGATE payload-type span of binding `[ns,nl]` — non-0/0 only when it is the CURRENT arm's SINGLE
## payload binding AND the variant payload type is a struct / enum / str (§8 piece 3b).
rv_bind_agg_span := fn(bind_head : ptr(mut Bind), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> CSpan {
  mut rs := 0
  mut rn := 0
  if RV_ARM_ENL != 0 {
    bidx := bind_list_index(bind_head, src, ns, nl, a)
    mut cnt := 0
    mut b := bind_head
    while unchecked bitcast(usize, b) != 0 { cnt = cnt + 1 ; b = bnd_next(b) }
    if bidx == 0 and cnt == 1 {
      pty := variant_payload_type(decls, src, RV_ARM_ENS, RV_ARM_ENL, RV_ARM_VS, RV_ARM_VL, a)
      isagg := pty.n != 0 and (struct_decl_of(decls, src, pty.s, pty.n) >= 0 or enum_decl_of(decls, src, pty.s, pty.n) >= 0 or str_at((src + pty.s), pty.n) == "str")
      if isagg { rs = pty.s ; rn = pty.n }
    }
  }
  CSpan(s = rs, n = rn)
}
## Is `e` a FLOAT comparison (cmp-op Bin over float operands)? Fresh match (destructured outer l/r
## mis-lower through the detector — pass the ptr).
rv_is_float_cmp := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Bin(op, l, rr) => {
      if ex_is_cmp_op(op) {
        if rv_is_float_expr(l, body_head, src, a, params_head, decls, 0) { r = true }
        if rv_is_float_expr(rr, body_head, src, a, params_head, decls, 0) { r = true }
      }
    }
    _ => {}
  }
  r
}
## Is `e` a bare PLACE whose a0 word is an aggregate BASE ADDRESS (a struct/array/slice PARAM, whose
## frame slot holds the caller's block address) or only word 0 of a wider value (an ENUM local/param,
## whose word 0 is the DISCRIMINANT)? Either way the word is NOT the value, so the `sub`/`sltu` compare
## below answers on addresses / discriminants alone — a SILENT MISCOMPILE (`E.A(5) == E.A(9)` read
## EQUAL; two field-equal struct params read UNEQUAL). A bare struct/array LOCAL already fail-louds in
## the Var arm, which is why only these shapes survived. Var-only: an INDEX/FIELD operand already
## holds a loaded scalar and must keep comparing.
rv_is_agg_place := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  ns := ex_var_ns(e)
  nl := ex_var_nl(e)
  if nl == 0 { return false }
  if rv_local_struct_nl(body_head, src, ns, nl, a) != 0 { return true }
  if rv_param_struct_nl(params_head, src, ns, nl, a, decls) != 0 { return true }
  if rv_local_enum_nl(body_head, src, ns, nl, a) != 0 { return true }
  if rv_param_enum_nl(params_head, src, ns, nl, decls) != 0 { return true }
  if rv_is_array_local(body_head, src, ns, nl, a) { return true }
  if rv_is_slice_local(body_head, src, ns, nl, a) { return true }
  false
}
## The INDEX twin: `xs[i]` over an AGGREGATE-ELEMENT array yields the ELEMENT's base address (elements
## are by-reference), so `ps[0] == ps[1]` compared addresses — two field-EQUAL elements read UNEQUAL.
## A SCALAR-element array (`xs[0] == ys[0]`) yields a loaded value and stays on the ordinary compare.
rv_is_agg_index := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_index(e) { return false }
  es := rv_index_elem_struct_span(e, src, a, decls)
  es.n != 0
}
## Is `e` a bare AGGREGATE comparison (Stdlib §2.6)? A FRESH match binds its own operands (the outer
## Bin arm's destructured l/r mis-lower when passed to a detector — pass the whole ptr), exactly like
## `rv_is_float_cmp`. riscv64 has no structural `base::derive::eq`/`lt` (x86_64 routes bare aggregate
## compares there), and the injected-generic mono path is gated off on this backend — so there is
## nothing correct to route to and the construct must stay LOUD (`ebreak`).
rv_is_agg_cmp := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Bin(op, l, rr) => {
      if ex_is_cmp_op(op) {
        if rv_is_agg_place(l, params_head, body_head, src, a, decls) { r = true }
        if rv_is_agg_place(rr, params_head, body_head, src, a, decls) { r = true }
        if rv_is_agg_index(l, src, a, decls) { r = true }
        if rv_is_agg_index(rr, src, a, decls) { r = true }
      }
    }
    _ => {}
  }
  r
}
## Emit a FLOAT comparison: operand bits a0/a1 → ft0/ft1, then RV's ordered feq.d/flt.d/fle.d (0/1 in
## a0). `>`/`>=` swap operands; `!=` is `not feq`. All ordered (NaN → 0), so `!=` correctly gives 1 for NaN.
rv_emit_fcmp := fn(op : u8, in out sb : rt::StrBuf) {
  push_str(sb, "  fmv.d.x ft0, a0\n  fmv.d.x ft1, a1\n")
  if op == 20 { push_str(sb, "  feq.d a0, ft0, ft1\n") }
  if op == 28 { push_str(sb, "  feq.d a0, ft0, ft1\n  xori a0, a0, 1\n") }
  if op == 24 { push_str(sb, "  flt.d a0, ft0, ft1\n") }
  if op == 26 { push_str(sb, "  fle.d a0, ft0, ft1\n") }
  if op == 25 { push_str(sb, "  flt.d a0, ft1, ft0\n") }
  if op == 27 { push_str(sb, "  fle.d a0, ft1, ft0\n") }
}


## Emit code computing expression `e` into a0. `bind_head`/`bind_base` carry active match-arm payload
## bindings (0/0 outside a match arm): a bound Var loads scrutinee word bind_base+(bindidx+1)*8.
rv_emit_lambda_label := fn(in out sb : rt::StrBuf, src : ptr(u8), ms : usize, ml : usize, fnpos : usize) {
  if not lower::is_root_mod(ms, ml) {
    if ml == 0 { push_str(sb, "main") } else { push_str(sb, str_at((src + ms), ml)) }
    push_str(sb, "__")
  }
  push_str(sb, "lam")
  push_int(sb, i64(fnpos))
}

rv_bound_lambda := fn(body : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> i64 {
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

emit_rv_expr := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  match deref(e) {
    Expr::FnRef(fnpos, fms, fml) => {
      push_str(sb, "  la a0, ") ; rv_emit_lambda_label(sb, src, fms, fml, fnpos) ; push_str(sb, "\n")
    }
    Expr::Num(v, s, n) => { push_str(sb, "  li a0, ") ; push_int(sb, i64(v)) ; push_str(sb, "\n") }
    ## FLOAT literal: load its IEEE bits from the `.Lflt<start>` `.double` into ft0, move to a0.
    Expr::FloatLit(fs, fl) => {
      push_str(sb, "  la t0, .Lflt") ; push_int(sb, i64(fs))
      push_str(sb, "\n  fld ft0, 0(t0)\n  fmv.x.d a0, ft0\n")
    }
    Expr::BoolLit(v) => { push_str(sb, "  li a0, ") ; push_int(sb, i64(v)) ; push_str(sb, "\n") }
    Expr::Var(ns, nl) => {
      ## BIND > PARAM > GLOBAL > LOCAL, flat standalone ifs. A bare struct-local Var has no scalar value → brk.
      bidx := bind_list_index(bind_head, src, ns, nl, a)
      isstruct := rv_local_struct_nl(body_head, src, ns, nl, a) != 0
      isarray := rv_is_array_local(body_head, src, ns, nl, a)
      isagg := isstruct or isarray
      pidx := rv_param_find(params_head, src, ns, nl, a)
      isglob := rv_is_global(decls, src, ns, nl, a)
      mut voff := rv_local_off(body_head, src, ns, nl, pcount, a, decls)
      if pidx >= 0 { voff = 16 + pidx * 8 }
      mut outscalar := false
      if pidx >= 0 { if rv_param_out_scalar(params_head, src, decls, pidx) { outscalar = true } }
      useframe := (bidx < 0) and (not isagg) and (not outscalar) and ((pidx >= 0) or (voff >= 0 and (not isglob)))
      gname := str_at((src + ns), nl)
      if bidx >= 0 { push_str(sb, "  ld a0, ") ; push_int(sb, bind_base + (bidx + 1) * 8) ; push_str(sb, "(s0)\n") }
      if outscalar { push_str(sb, "  ld t1, ") ; push_int(sb, voff) ; push_str(sb, "(s0)\n  ld a0, 0(t1)\n") }
      if useframe { push_str(sb, "  ld a0, ") ; push_int(sb, voff) ; push_str(sb, "(s0)\n") }
      if (bidx < 0) and (not isagg) and (not outscalar) and (not useframe) and isglob {
        push_str(sb, "  la a0, ") ; push_str(sb, gname) ; push_str(sb, "\n  ld a0, 0(a0)\n")
      }
      if (bidx < 0) and (not isagg) and (not outscalar) and (not useframe) and (not isglob) { push_str(sb, "  ebreak\n") }
      if (bidx < 0) and isagg { push_str(sb, "  ebreak\n") }
    }
    Expr::Field(base, fs, fl) => {
      ## `f.offset` — a comptime FIELD descriptor read. Fold it before ordinary field lowering sees
      ## the erased loop variable as a runtime name; unresolved forms keep the existing trap path.
      cfo := rv_cf_offset_value(e, src, decls, a)
      if cfo >= 0 {
        push_str(sb, "  li a0, ") ; push_int(sb, cfo) ; push_str(sb, "\n")
        return
      }
      ## `f.mutable` — a comptime FIELD descriptor read. It has no runtime storage; emit the source-level
      ## mutability bit as an immediate before ordinary field machinery sees `f` as a runtime variable.
      cfm := rv_cf_mutable_value(e, src)
      if cfm >= 0 {
        push_str(sb, "  li a0, ") ; push_int(sb, cfm) ; push_str(sb, "\n")
        return
      }
      ## `p.f`: a struct LOCAL reads at (frame base + field word offset); a struct PARAM (by-reference:
      ## slot holds the base ADDRESS) loads the addr into t1 then dereferences at the field. Flat.
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      stys := rv_local_struct_ns(body_head, src, bns, bnl, a)
      styn := rv_local_struct_nl(body_head, src, bns, bnl, a)
      poff := rv_local_off(body_head, src, bns, bnl, pcount, a, decls)
      ## Standard-byte local path: the root remains inline in the frame, but every FIELD hop uses the
      ## shared byte offset oracle. Aggregate leaves are consumed by whole-value copy/constructor paths;
      ## a scalar leaf is loaded directly at root frame offset + cumulative byte offset.
      mut stdty := rv_std_path_ty(e, body_head, src, a, decls)
      mut stdpath := rv_std_path_ok(e, body_head, src, a, decls) and stdty.n != 0
      mut stdparampath := false
      if not stdpath {
        if rv_std_param_path_ok(e, params_head, src, a, decls) {
          stdty = rv_std_param_path_ty(e, params_head, src, a, decls)
          stdpath = true
          stdparampath = true
        }
      }
      mut stdhandled := false
      if stdpath {
        if std_ty_aggregate(stdty.s, stdty.n, decls, src) { push_str(sb, "  ebreak # unsupported standard aggregate field read\n") }
        if not std_ty_aggregate(stdty.s, stdty.n, decls, src) {
          mut sbo := i64(0)
          if stdparampath { sbo = rv_std_param_path_bo(e, params_head, src, a, decls) }
          if not stdparampath { sbo = rv_std_path_bo(e, body_head, src, a, decls) }
          if stdparampath {
            spidx := rv_std_param_path_idx(e, params_head, src, a, decls)
            push_str(sb, "  ld a0, ") ; push_int(sb, 16 + spidx * 8) ; push_str(sb, "(s0)\n")
            if sbo != 0 { push_str(sb, "  li t1, ") ; push_int(sb, sbo) ; push_str(sb, "\n  add a0, a0, t1\n") }
            rv_std_load_width_a0(scalar_byte_size(src, stdty.s, stdty.n), stdty.n != 0 and str_at((src + stdty.s), 1) == "i", sb)
          }
          if not stdparampath {
            sroot := rv_std_path_root_off(e, body_head, src, pcount, a, decls)
            rv_std_load_scalar(sroot + sbo, stdty.s, stdty.n, sb, src)
          }
        }
        stdhandled = true
      }
      ## gate on THIS FIELD being scalar (not the whole struct) — a scalar field of a struct that also has
      ## an aggregate field reads at its layout word offset (which already accounts for the wide field).
      localok := (not stdhandled) and bnl != 0 and styn != 0 and poff >= 0 and rv_field_is_scalar(decls, src, stys, styn, fs, fl, a)
      pidx := rv_param_find(params_head, src, bns, bnl, a)
      pstys := rv_param_struct_ns(params_head, src, bns, bnl, a, decls)
      pstyn := rv_param_struct_nl(params_head, src, bns, bnl, a, decls)
      paramok := (not stdhandled) and (not localok) and pidx >= 0 and pstyn != 0 and rv_struct_all_scalar(decls, src, pstys, pstyn, a)
      if localok {
        woff := field_word_offset(decls, src, stys, styn, fs, fl, a)
        push_str(sb, "  ld a0, ") ; push_int(sb, poff + woff * 8) ; push_str(sb, "(s0)\n")
      }
      if paramok {
        woff := field_word_offset(decls, src, pstys, pstyn, fs, fl, a)
        push_str(sb, "  ld t1, ") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "(s0)\n  ld a0, ") ; push_int(sb, woff * 8) ; push_str(sb, "(t1)\n")
      }
      ## `s[i].field`: FIELD over an INDEX into a struct-element `Slice(P)` PARAM. Element i is by-reference
      ## at block.word0 (data ptr) + i*stride*8; the field is at (element base + woff*8). Bounds vs word1.
      mut fldidxdone := false
      if ex_is_index(base) {
        ibx := ex_index_base(base)
        ins := ex_var_ns(ibx)
        inl := ex_var_nl(ibx)
        ipidx := rv_param_find(params_head, src, ins, inl, a)
        psp := rv_slice_param_struct_span(params_head, src, ins, inl, decls)
        if ipidx >= 0 and psp.n != 0 and rv_struct_all_scalar(decls, src, psp.s, psp.n, a) {
          fldidxdone = true
          stride := rv_slice_param_agg_stride(params_head, src, ins, inl, a, decls)
          woff := field_word_offset(decls, src, psp.s, psp.n, fs, fl, a)
          pslot := 16 + ipidx * 8
          emit_rv_expr(ex_index_idx(base), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if RV_CHK { push_str(sb, "  ld a3, ") ; push_int(sb, pslot) ; push_str(sb, "(s0)\n  ld a1, 8(a3)\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
          push_str(sb, "  ld a3, ") ; push_int(sb, pslot) ; push_str(sb, "(s0)\n  ld a2, 0(a3)\n")
          push_str(sb, "  li a1, ") ; push_int(sb, stride * 8) ; push_str(sb, "\n  mul a0, a0, a1\n  add a2, a2, a0\n")
          push_str(sb, "  ld a0, ") ; push_int(sb, woff * 8) ; push_str(sb, "(a2)\n")
        }
        ## `xs[i].f` on a fixed ARRAY of scalar-only STRUCTS — a LOCAL array-lit (frame base `s0 + aoff`)
        ## or an array GLOBAL (label base). Element i is `stride` words wide at base + i*stride*8, the
        ## scalar field at (element base + woff*8). Bounds vs the STATIC element count via `bltu` (a
        ## negative i64 index is a huge unsigned → traps); dropped under `unchecked` (CG-7).
        if not fldidxdone {
          esp := rv_arrname_elem_struct_span(src, ins, inl, a, decls)
          eisla := esp.n != 0 and rv_is_array_local(body_head, src, ins, inl, a)
          eisga := esp.n != 0 and (not eisla) and rv_is_array_global(decls, src, ins, inl)
          eaoff := rv_local_off(body_head, src, ins, inl, pcount, a, decls)
          ## THIS FIELD must be SCALAR (one word): an element struct may now carry a nested aggregate
          ## field, and a one-word `ld` at its offset would silently read only its word 0. A non-scalar
          ## field falls through to the deep-place composition below / the fail-loud default.
          efscal := esp.n != 0 and rv_field_is_scalar(decls, src, esp.s, esp.n, fs, fl, a)
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
            if eisla { enel = rv_array_nel(body_head, src, ins, inl, a) }
            if eisga { enel = rv_alit_nel(rv_global_value(decls, src, ins, inl)) }
            emit_rv_expr(ex_index_idx(base), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if RV_CHK {
              if enel > 0 { push_str(sb, "  li a1, ") ; push_int(sb, enel) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
            }
            push_str(sb, "  li a1, ") ; push_int(sb, estrb) ; push_str(sb, "\n  mul a0, a0, a1\n")
            if eisla {
              push_str(sb, "  add a2, a0, s0\n  li a1, ") ; push_int(sb, eaoff) ; push_str(sb, "\n  add a2, a2, a1\n")
              if ebyte {
                ftb := field_type_span(decls, src, esp.s, esp.n, fs, fl, a)
                fw := scalar_byte_size(src, ftb.s, ftb.n)
                fsigned := ftb.n != 0 and str_at((src + ftb.s), 1) == "i"
                if fw == 1 and fsigned { push_str(sb, "  lb a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 1 and (not fsigned) { push_str(sb, "  lbu a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 2 and fsigned { push_str(sb, "  lh a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 2 and (not fsigned) { push_str(sb, "  lhu a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 4 and fsigned { push_str(sb, "  lw a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 4 and (not fsigned) { push_str(sb, "  lwu a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 8 { push_str(sb, "  ld a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
              }
              if not ebyte { push_str(sb, "  ld a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
            }
            if eisga {
              push_str(sb, "  la a2, ") ; push_str(sb, str_at((src + ins), inl)) ; push_str(sb, "\n  add a2, a2, a0\n")
              if ebyte {
                ftb := field_type_span(decls, src, esp.s, esp.n, fs, fl, a)
                fw := scalar_byte_size(src, ftb.s, ftb.n)
                fsigned := ftb.n != 0 and str_at((src + ftb.s), 1) == "i"
                if fw == 1 and fsigned { push_str(sb, "  lb a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 1 and (not fsigned) { push_str(sb, "  lbu a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 2 and fsigned { push_str(sb, "  lh a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 2 and (not fsigned) { push_str(sb, "  lhu a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 4 and fsigned { push_str(sb, "  lw a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 4 and (not fsigned) { push_str(sb, "  lwu a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
                if fw == 8 { push_str(sb, "  ld a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
              }
              if not ebyte { push_str(sb, "  ld a0, ") ; push_int(sb, ewofb) ; push_str(sb, "(a2)\n") }
            }
          }
        }
      }
      ## `s.len` on a range-slice local — the runtime length lives in word1 (frame byte offset poff+8).
      mut isslicelen := false
      if bnl != 0 {
        if rv_is_slice_local(body_head, src, bns, bnl, a) {
          if str_at((src + fs), fl) == "len" { isslicelen = true }
        }
      }
      if isslicelen { push_str(sb, "  ld a0, ") ; push_int(sb, poff + 8) ; push_str(sb, "(s0)\n") }
      ## `G.f` / `G.a.b.c` — a SCALAR field of a struct GLOBAL at ANY depth: resolve the cumulative `.data`
      ## word offset (nested structs flattened) and load at LABEL + off*8. Disjoint from local/param paths.
      gtype := rv_gchain_type(e, decls, src, a)
      gwoff := rv_gchain_woff(e, decls, src, a)
      groot := rv_gchain_root(e)
      gchainok := gwoff >= 0 and gtype.n != 0 and ty_is_scalar(gtype.s, gtype.n, decls, src)
      if gchainok {
        gcn := str_at((src + groot.s), groot.n)
        push_str(sb, "  la a0, ") ; push_str(sb, gcn) ; push_str(sb, "\n  ld a0, ") ; push_int(sb, gwoff * 8) ; push_str(sb, "(a0)\n")
      }
      ## `c.v.a` — a SCALAR field of a NESTED struct LOCAL at ANY depth >= 2 (the base is itself a Field).
      ## Resolve the cumulative frame WORD offset (nested structs flattened) through the chain rooted at a
      ## struct local and load at (root frame base + off*8). Gated on the base being a Field → disjoint from
      ## the 1-level localok (which fires only when the base is a Var).
      lroot := rv_gchain_root(e)
      ltype := rv_lchain_type(e, body_head, src, a, decls)
      lwoff := rv_lchain_woff(e, body_head, src, a, decls)
      lrootoff := rv_local_off(body_head, src, lroot.s, lroot.n, pcount, a, decls)
      lchainok := (not stdhandled) and ex_is_field(base) and lwoff >= 0 and lrootoff >= 0 and ltype.n != 0 and ty_is_scalar(ltype.s, ltype.n, decls, src)
      if lchainok { push_str(sb, "  ld a0, ") ; push_int(sb, lrootoff + lwoff * 8) ; push_str(sb, "(s0)\n") }
      ## `pt.f` / `s.len` where the base is an AGGREGATE payload BINDING (§8 piece 3b) at frame offset
      ## `bind_base + 8` — a STRUCT binding reads its field there; a `str` binding reads `.len` at base + 8.
      bagg := rv_bind_agg_span(bind_head, src, bns, bnl, a, decls)
      mut bindaggok := false
      if bagg.n != 0 and struct_decl_of(decls, src, bagg.s, bagg.n) >= 0 and rv_struct_all_scalar(decls, src, bagg.s, bagg.n, a) {
        bindaggok = true
        bwoff := field_word_offset(decls, src, bagg.s, bagg.n, fs, fl, a)
        push_str(sb, "  ld a0, ") ; push_int(sb, bind_base + 8 + bwoff * 8) ; push_str(sb, "(s0)\n")
      }
      if bagg.n != 0 and (not bindaggok) and str_at((src + bagg.s), bagg.n) == "str" and str_at((src + fs), fl) == "len" {
        bindaggok = true
        push_str(sb, "  ld a0, ") ; push_int(sb, bind_base + 8 + 8) ; push_str(sb, "(s0)\n")
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
          if rv_deep_scalar_ok(e, body_head, src, params_head, pcount, a, decls) {
            emit_rv_place_addr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if rv_std_idx_path_ok(e, body_head, src, a, decls) {
              dtyb := rv_std_idx_path_ty(e, body_head, src, a, decls)
              rv_std_load_width_a0(scalar_byte_size(src, dtyb.s, dtyb.n), dtyb.n != 0 and str_at((src + dtyb.s), 1) == "i", sb)
            }
            if not rv_std_idx_path_ok(e, body_head, src, a, decls) { push_str(sb, "  ld a0, 0(a0)\n") }
            fldidxdone = true
          }
        }
      }
      if (not stdhandled) and (not localok) and (not paramok) and (not isslicelen) and (not fldidxdone) and (not gchainok) and (not lchainok) and (not bindaggok) { push_str(sb, "  ebreak\n") }
    }
    ## `v.(f)` (Expr::CompField) — a member access named by the comptime field-unroll loop var `f`. When
    ## `f` is the active loop var (RV_CF_VAR set), reduce to a scalar field READ of `v` at the CURRENT field
    ## (RV_CF_FLD name span): a struct LOCAL reads at (frame base + field word offset); a struct PARAM
    ## (by-reference, T substituted) loads the addr then dereferences. Flat standalone ifs.
    Expr::CompField(base, idx) => {
      cvn_s := ex_var_ns(idx)
      cvn_l := ex_var_nl(idx)
      cfactive := RV_CF_VAR_L != 0 and cvn_l != 0 and streq(src, cvn_s, cvn_l, RV_CF_VAR_S, RV_CF_VAR_L)
      cfs := RV_CF_FLD_S
      cfl := RV_CF_FLD_L
      cbns := ex_var_ns(base)
      cbnl := ex_var_nl(base)
      cstys := rv_local_struct_ns(body_head, src, cbns, cbnl, a)
      cstyn := rv_local_struct_nl(body_head, src, cbns, cbnl, a)
      cpoff := rv_local_off(body_head, src, cbns, cbnl, pcount, a, decls)
      clocalok := cfactive and cbnl != 0 and cstyn != 0 and cpoff >= 0 and rv_field_is_scalar(decls, src, cstys, cstyn, cfs, cfl, a)
      cpidx := rv_param_find(params_head, src, cbns, cbnl, a)
      cpstys := rv_param_struct_ns(params_head, src, cbns, cbnl, a, decls)
      cpstyn := rv_param_struct_nl(params_head, src, cbns, cbnl, a, decls)
      cparamok := cfactive and (not clocalok) and cpidx >= 0 and cpstyn != 0 and rv_struct_all_scalar(decls, src, cpstys, cpstyn, a)
      if clocalok {
        cwoff := field_word_offset(decls, src, cstys, cstyn, cfs, cfl, a)
        push_str(sb, "  ld a0, ") ; push_int(sb, cpoff + cwoff * 8) ; push_str(sb, "(s0)\n")
      }
      if cparamok {
        cwoff := field_word_offset(decls, src, cpstys, cpstyn, cfs, cfl, a)
        push_str(sb, "  ld t1, ") ; push_int(sb, 16 + cpidx * 8) ; push_str(sb, "(s0)\n  ld a0, ") ; push_int(sb, cwoff * 8) ; push_str(sb, "(t1)\n")
      }
      if (not clocalok) and (not cparamok) { push_str(sb, "  ebreak\n") }
    }
    ## `ptr(<place>)` — the ADDRESS of a SCALAR place into a0 (spec MEM-7/MEM-8, scoped reference). A
    ## scalar frame local / by-value scalar param → `addi a0, s0, voff` (the slot's address); a mutable
    ## scalar module global → its `.data` label (`la`). A STRUCT/ARRAY-local place (isagg) is struct-
    ## through-pointer — DEFERRED, fail-loud (`ebreak`). Any non-Var inner also fail-loud. Mirrors the Var
    ## value path's PARAM > GLOBAL > LOCAL resolution (flat standalone ifs), taking the address.
    Expr::AddrOf(inner) => {
      ins := ex_var_ns(inner)
      inl := ex_var_nl(inner)
      isstruct := rv_local_struct_nl(body_head, src, ins, inl, a) != 0
      isarray := rv_is_array_local(body_head, src, ins, inl, a)
      isagg := isstruct or isarray
      pidx := rv_param_find(params_head, src, ins, inl, a)
      isglob := rv_is_global(decls, src, ins, inl, a)
      mut voff := rv_local_off(body_head, src, ins, inl, pcount, a, decls)
      if pidx >= 0 { voff = 16 + pidx * 8 }
      mut outscalar := false
      if pidx >= 0 { if rv_param_out_scalar(params_head, src, decls, pidx) { outscalar = true } }
      useframe := inl != 0 and (not isagg) and (not outscalar) and ((pidx >= 0) or (voff >= 0 and (not isglob)))
      useglob := inl != 0 and (not isagg) and (not useframe) and isglob
      gname := str_at((src + ins), inl)
      if outscalar { push_str(sb, "  ld a0, ") ; push_int(sb, voff) ; push_str(sb, "(s0)\n") }
      if useframe { push_str(sb, "  addi a0, s0, ") ; push_int(sb, voff) ; push_str(sb, "\n") }
      if useglob { push_str(sb, "  la a0, ") ; push_str(sb, gname) ; push_str(sb, "\n") }
      if (not outscalar) and (not useframe) and (not useglob) { push_str(sb, "  ebreak\n") }
    }
    ## `deref(<scalar ptr>)` — LOAD one word through the pointer. Pointer value → a0, then `ld a0, 0(a0)`.
    ## SCALAR only: a struct-through-pointer read is `deref(p).field` = `Field(Deref(p), …)` (Field arm);
    ## a whole-struct `deref(p)` copy is DEFERRED (multi-word). This arm never sees those.
    Expr::Deref(inner) => {
      emit_rv_expr(inner, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  ld a0, 0(a0)\n")
    }
    Expr::Bin(op, l, r) => {
      ## Stdlib §2.6 BARE AGGREGATE COMPARISON — fail loud BEFORE the operands are materialized. Each
      ## operand word is an aggregate base address (struct/array/slice param) or an enum's word-0
      ## discriminant, so the compare below answers on the wrong bits. The `ebreak` traps first;
      ## everything after it is dead. See `rv_is_agg_cmp` for why routing is not an option here.
      if rv_is_agg_cmp(e, body_head, src, a, params_head, decls) { push_str(sb, "  ebreak\n") }
      emit_rv_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
      emit_rv_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  mv a1, a0\n")
      push_str(sb, "  ld a0, 0(sp)\n  addi sp, sp, 16\n")
      iscmp := ex_is_cmp_op(op)
      mut isflt := false
      if rv_is_float_expr(e, body_head, src, a, params_head, decls, 0) { isflt = true }
      mut isfcmp := false
      if rv_is_float_cmp(e, body_head, src, a, params_head, decls) { isfcmp = true }
      ## Boolean `not` — the parser yields `Bin(42, operand, Num(0))` (the right slot is a DUMMY, so
      ## the operand is evaluated exactly once and a1 already holds 0). a0 := (a0 == 0), the riscv64
      ## dual of the x86_64 `cmpq $0 / sete` and wat's `i64.eqz`. It must gate the three arms below:
      ## 42 is not a `ex_is_cmp_op` kind and `not (0.0 < x)` reads FLOAT through `rv_is_float_expr`, so it
      ## would otherwise land in the FP-arith arm, and `rv_emit_arith`'s `known` test would `ebreak`.
      isnot := op == 42
      if isnot { push_str(sb, "  seqz a0, a0\n") }
      if iscmp and isfcmp and (not isnot) { rv_emit_fcmp(op, sb) }
      if iscmp and (not isfcmp) and (not isnot) { rv_emit_cmp(op, rv_cmp_unsigned(l, r, params_head, body_head, src, a), sb) }
      if (not iscmp) and isflt and (not isnot) {
        ## FLOAT arithmetic: bits in a0/a1 → ft0/ft1, FP op, bits back to a0. Detect on the whole Bin `e`
        ## (destructured operands mis-lower through the detector). `+`/`-`/`*`/`/` only.
        push_str(sb, "  fmv.d.x ft0, a0\n  fmv.d.x ft1, a1\n")
        if op == 16 { push_str(sb, "  fadd.d ft0, ft0, ft1\n") }
        if op == 17 { push_str(sb, "  fsub.d ft0, ft0, ft1\n") }
        if op == 18 { push_str(sb, "  fmul.d ft0, ft0, ft1\n") }
        if op == 19 { push_str(sb, "  fdiv.d ft0, ft0, ft1\n") }
        push_str(sb, "  fmv.x.d a0, ft0\n")
      }
      if (not iscmp) and (not isflt) and (not isnot) {
        dl := rv_operand_signed(l, params_head, body_head, src, a)
        dr := rv_operand_signed(r, params_head, body_head, src, a)
        dsigned := dl or dr
        ## NARROW-WIDTH WRAP (§4 value model): truncate a narrow-typed (uN/iN, N<64) +/-/* result.
        ## Computed BEFORE the arith so the checked overflow guard (native-width only) can skip a narrow op.
        mut nw := ""
        if op == 16 or op == 17 or op == 18 {
          nw = rv_operand_narrow(l, params_head, body_head, src, a)
          if nw == "" { nw = rv_operand_narrow(r, params_head, body_head, src, a) }
        }
        rv_emit_arith(op, dsigned, (nw != "") or ex_is_zero_lit(l), sb)
        if nw != "" {
          if RV_CHK and (not ex_is_zero_lit(l)) { rv_emit_narrow_trap(nw, sb) }
          rv_emit_narrow(nw, sb)
        }
        ## narrow `~`/`^`: mask the xor result to the operand width (the `x^(-1)` desugar carries 64-bit
        ## ones, so a narrow `~` would otherwise keep the high bits). Same-width `^` = identity mask.
        if op == 36 {
          mut xw := rv_operand_narrow(l, params_head, body_head, src, a)
          if xw == "" { xw = rv_operand_narrow(r, params_head, body_head, src, a) }
          if xw != "" { rv_emit_narrow(xw, sb) }
        }
      }
    }
    Expr::If(c, th, el) => {
      id := rv_next_label()
      emit_rv_expr(c, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  beqz a0, .Lelse") ; push_int(sb, id) ; push_str(sb, "\n")
      emit_rv_expr(th, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  j .Lend") ; push_int(sb, id) ; push_str(sb, "\n")
      push_str(sb, ".Lelse") ; push_int(sb, id) ; push_str(sb, ":\n")
      emit_rv_expr(el, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, ".Lend") ; push_int(sb, id) ; push_str(sb, ":\n")
    }
    Expr::Call(cs, cl, nargs, args_head) => {
      nm := str_at((src + cs), cl)
      srs_call := rv_call_ret_sret_span(e, decls, src, a)
      ers_call := rv_call_ret_enum_sret_span(e, decls, src, a)
      direct_sretcall := srs_call.n != 0 or ers_call.n != 0
      ## print/println whose FIRST arg is a string literal → template emission (a plain literal has no
      ## `{}` holes). Runs → write syscalls; holes → arg via __print_u64; println → trailing newline.
      mut sarg := unchecked bitcast(ptr(Expr), 0)
      if args_head != 0 { ga0 := deref(arg_p(args_head)) ; sarg = ga0.e }
      ispln := nm == "println"
      isprint := (nm == "print" or ispln) and args_head != 0 and rv_is_strlit(sarg)
      isconv := scalar_name_is_int_conv(nm)
      mut isfconv := false
      if nm == "f64" { isfconv = true }
      if nm == "f32" { isfconv = true }
      if isprint {
        emit_rv_print_template(sb, a, src, rv_strlit_ss(sarg), rv_strlit_sl(sarg), rv_strlit_lbl(sarg), ispln, args_head, params_head, pcount, body_head, decls, bind_head, bind_base)
      } else if (isconv or isfconv) and args_head != 0 {
        ## CONVERSION `uN(x)`/`iN(x)`/`fN(x)` — value bits in a0; FP conversions round-trip via an f-reg.
        ## int→float `fcvt.d.l` (signed, matching x86 cvtsi2sd); float→int `fcvt.lu.d`/`fcvt.l.d` (rtz,
        ## truncating) + the width narrow; int→int the plain narrow.
        gc0 := deref(arg_p(args_head))
        argisf := rv_is_float_expr(gc0.e, body_head, src, a, params_head, decls, 0)
        emit_rv_expr(gc0.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if isfconv {
          if not argisf { push_str(sb, "  fcvt.d.l ft0, a0\n  fmv.x.d a0, ft0\n") }
        } else {
          if argisf {
            push_str(sb, "  fmv.d.x ft0, a0\n")
            if str_at((src + cs), 1) == "u" { push_str(sb, "  fcvt.lu.d a0, ft0, rtz\n") } else { push_str(sb, "  fcvt.l.d a0, ft0, rtz\n") }
            rv_emit_narrow(nm, sb)
          } else {
            rv_emit_narrow(nm, sb)
          }
        }
      } else if nm == "asm" and args_head != 0 and rv_is_strlit(sarg) {
        ## `asm("<GAS>", op…)` raw escape (spec ch.80 §4/§11): emit the RV64-GAS template with the
        ## positional-`{i}` scheme — each `{i}` → the bare decimal value of operand `i` (a comptime IMMEDIATE;
        ## RV64 immediates are bare, e.g. `li a0, {0}` with `42` → `li a0, 42`). Register operands would need
        ## RV64 register-name exemption in `check` — a follow-up; immediate-only here.
        ss := rv_strlit_ss(sarg)
        sl := rv_strlit_sl(sarg)
        push_str(sb, "  ")
        mut j := 0
        while j < sl {
          c := str_at((src + ss + j), 1)
          d0 := if j + 1 < sl { dec_digit_val(str_at((src + ss + j + 1), 1)) } else { -1 }
          if c == "{" and d0 >= 0 {
            mut k := j + 1
            mut idx := 0
            while k < sl and dec_digit_val(str_at((src + ss + k), 1)) >= 0 { idx = idx * 10 + usize(dec_digit_val(str_at((src + ss + k), 1))) ; k = k + 1 }
            oe := rv_arg_at(args_head, idx + 1, a)
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
        ## bit shift/rotate ops (OP-6): eval v -> a0 (pushed), count -> a1, then the op. `shr` picks
        ## `srl`(logical)/`sra`(arithmetic) by the value's signedness (rv_operand_signed). RV64I (base) has
        ## NO rotate insn (that is the Zbb ext), so rotate is EMULATED: rotr(v,n) = (v>>n)|(v<<(64-n)),
        ## rotl(v,n) = (v<<n)|(v>>(64-n)), via srl/sll + a `64-n` count in t1 and t0/t2 scratch. A SHIFT count
        ## n>=64 is a checked over-width trap (ebreak; I11), dropped under `unchecked` (RV_CHK false); rotation
        ## is total (RV64 masks the count mod 64). Native-64 operands (narrow-width masking = follow-up).
        rsv := arg_expr_at(args_head, 0, a)
        rsn := arg_expr_at(args_head, 1, a)
        emit_rv_expr(rsv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
        emit_rv_expr(rsn, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  mv a1, a0\n  ld a0, 0(sp)\n  addi sp, sp, 16\n")
        rssigned := rv_operand_signed(rsv, params_head, body_head, src, a)
        if RV_CHK and (nm == "shl" or nm == "shr") { push_str(sb, "  li t0, 64\n  bltu a1, t0, 1f\n  ebreak\n1:\n") }
        if nm == "shl" { push_str(sb, "  sll a0, a0, a1\n") }
        if nm == "shr" and rssigned { push_str(sb, "  sra a0, a0, a1\n") }
        if nm == "shr" and (not rssigned) { push_str(sb, "  srl a0, a0, a1\n") }
        if nm == "rotr" { push_str(sb, "  srl t0, a0, a1\n  li t1, 64\n  sub t1, t1, a1\n  sll t2, a0, t1\n  or a0, t0, t2\n") }
        if nm == "rotl" { push_str(sb, "  sll t0, a0, a1\n  li t1, 64\n  sub t1, t1, a1\n  srl t2, a0, t1\n  or a0, t0, t2\n") }
      } else if nm == "len" and args_head != 0 and rv_len_recv_slice(sarg, params_head, src, body_head, decls, a) {
        ## `s.len()` (UFCS-desugared to `Call("len", [s])`) on a slice receiver — the runtime length. A slice
        ## PARAM holds a POINTER to the `{ptr,len}` block, so len = word1 = `8(block)` (DOUBLE deref); a local
        ## VIEW holds `{ptr,len}` inline, so len = word1 at `aoff+8(s0)`.
        rns := ex_var_ns(sarg)
        rnl := ex_var_nl(sarg)
        pidxL := rv_param_find(params_head, src, rns, rnl, a)
        mut isparam := false
        if pidxL >= 0 { if rv_slice_param_scalar(params_head, src, rns, rnl, a, decls) { isparam = true } }
        aoffL := rv_local_off(body_head, src, rns, rnl, pcount, a, decls)
        if isparam { push_str(sb, "  ld t1, ") ; push_int(sb, 16 + pidxL * 8) ; push_str(sb, "(s0)\n  ld a0, 8(t1)\n") }
        if (not isparam) and aoffL >= 0 { push_str(sb, "  ld a0, ") ; push_int(sb, aoffL + 8) ; push_str(sb, "(s0)\n") }
        if (not isparam) and aoffL < 0 { push_str(sb, "  ebreak\n") }
      } else if gen_call_ok(decls, src, cs, cl) {
        ## GENERICS (§8 mono): route a generic call to its monomorphized instance `<fn>__<tag>`. Resolve
        ## the type-arg (SAME resolution the collector used, so the emitted label matches a defined
        ## instance) and RECORD it (rv_inst_add). An EXPLICIT type-arg (argc == arity) is ERASED from the
        ## runtime args. Scalar value args ride a0.. positionally. Unresolved → fail-loud ebreak.
        gi := generic_gi(decls, src, cs, cl)
        rv_resolve_typearg(decls, src, gi, args_head, params_head, a)
        tas := RV_TA_S
        tan := RV_TA_N
        if tan == 0 {
          push_str(sb, "  ebreak\n")
        } else {
          rv_inst_add(src, usize(gi), tas, tan)
          gd := deref(decl_get(decls, usize(gi)))
          argc := arg_list_count(args_head, a)
          ## ERASE the comptime type-arg(s) when passed explicitly (argc == arity): a LEADING RUN erases
          ## source indices [0, lead); a single NON-LEADING type-param erases its one position.
          mut erase_lead := 0
          mut erase_one := usize(argc) + 1
          if argc == i64(gd.arity) {
            cntc := decl_tparam_count(gd, src)
            leadc := decl_leading_tparam_run(gd, src)
            if cntc == leadc { erase_lead = usize(leadc) }
            if cntc == 1 and leadc == 0 { erase_one = usize(decl_tparam_pos(gd, src)) }
          }
          gwide := direct_sretcall
          sret_on_g := RV_SRET_DST_ON
          sret_ind_g := RV_SRET_DST_IND
          sret_dst_g := RV_SRET_DST
          sret_dst0_g := RV_SRET_DST
          if gwide { RV_SRET_DST_ON = false ; RV_SRET_DST_IND = false }
          mut gparams := gd.params_head
          mut gskip := erase_lead
          while gskip > 0 and gparams != 0 { gpm := deref(param_p(gparams)) ; gparams = gpm.next ; gskip = gskip - 1 }
          mut gkeep := i64(0)
          mut gkc := 0
          mut gk := args_head
          while gk != 0 { gka := deref(arg_p(gk)) ; if gkc >= erase_lead and gkc != erase_one { gkeep = gkeep + 1 } ; gkc = gkc + 1 ; gk = gka.next }
          mut gstacksz := 0
          if gwide { gstacksz = ((gkeep * 8 + 15) / 16) * 16 ; if gstacksz > 0 { push_str(sb, "  addi sp, sp, -") ; push_int(sb, gstacksz) ; push_str(sb, "\n") } }
          ## push each kept VALUE arg → the stack; a struct/enum LITERAL is materialized into an RV_AGG
          ## block and passed BY REFERENCE (its address in a0); a struct/array LOCAL by-ref (s0+off);
          ## scalar args ride a0 directly. FLAT separate ifs inside the guard.
          mut nv := i64(0)
          mut gstackk := 0
          mut gpush := 0
          mut g := args_head
          mut gidx := 0
          while g != 0 {
            ga := deref(arg_p(g))
            keeparg := gidx >= erase_lead and gidx != erase_one
            if keeparg {
              gavns := ex_var_ns(ga.e)
              gavnl := ex_var_nl(ga.e)
              gisarr := gavnl != 0 and rv_is_array_local(body_head, src, gavns, gavnl, a)
              gisstruct := (not gisarr) and gavnl != 0 and rv_local_struct_nl(body_head, src, gavns, gavnl, a) != 0
              isslit := rv_is_slit(ga.e)
              iselit := (not isslit) and rv_is_elit(ga.e)
              iscallret := (not isslit) and (not iselit) and rv_call_ret_struct_span(ga.e, decls, src, a).n != 0
              isenumret := (not isslit) and (not iselit) and (not iscallret) and rv_call_ret_enum_span(ga.e, decls, src, a).n != 0
              issretarg := (not isslit) and (not iselit) and (not iscallret) and (not isenumret) and rv_call_ret_sret_span(ga.e, decls, src, a).n != 0
              isesretarg := (not isslit) and (not iselit) and (not iscallret) and (not isenumret) and (not issretarg) and rv_call_ret_enum_sret_span(ga.e, decls, src, a).n != 0
              isaggref := (not isslit) and (not iselit) and (not iscallret) and (not isenumret) and (not issretarg) and (not isesretarg) and (gisarr or gisstruct)
              isplain := (not isslit) and (not iselit) and (not iscallret) and (not isenumret) and (not issretarg) and (not isesretarg) and (not isaggref)
              if isslit { emit_rv_aggval_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if iselit { emit_rv_enumval_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if iscallret { emit_rv_callret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if isenumret { emit_rv_enumret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if issretarg { emit_rv_sretcall_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if isesretarg { emit_rv_enumsret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if isaggref { gaoff := rv_local_off(body_head, src, gavns, gavnl, pcount, a, decls) ; push_str(sb, "  addi a0, s0, ") ; push_int(sb, gaoff) ; push_str(sb, "\n") }
              if isplain { emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if gwide {
                gfb := rv_float_params_before(gparams, src, nv, a)
                gif := rv_param_is_float(gparams, src, nv, a)
                mut gcls := nv - gfb
                if gif { gcls = gfb }
                if not gif { gcls = gcls + 1 }
                if gcls >= 8 { push_str(sb, "  sd a0, ") ; push_int(sb, gpush * 16 + gstackk * 8) ; push_str(sb, "(sp)\n") ; gstackk = gstackk + 1 }
                if gcls < 8 { push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n") ; gpush = gpush + 1 }
              }
              if not gwide { push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n") }
              nv = nv + 1
            }
            gidx = gidx + 1
            g = ga.next
          }
          if not gwide {
            mut ai := nv - 1
            while ai >= 0 { push_str(sb, "  ld a") ; push_int(sb, ai) ; push_str(sb, ", 0(sp)\n  addi sp, sp, 16\n") ; ai = ai - 1 }
          }
          if gwide {
            mut gri := argc - 1
            while gri >= 0 {
              grkeep := gri >= i64(erase_lead) and usize(gri) != erase_one
              if grkeep {
                mut gruntime := gri
                if erase_lead > 0 { gruntime = gruntime - i64(erase_lead) }
                if erase_one <= usize(gri) { gruntime = gruntime - 1 }
                grfb := rv_float_params_before(gparams, src, gruntime, a)
                grif := rv_param_is_float(gparams, src, gruntime, a)
                mut grcls := gruntime - grfb
                if grif { grcls = grfb }
                if not grif { grcls = grcls + 1 }
                if grcls < 8 and grif { push_str(sb, "  ld t1, 0(sp)\n  addi sp, sp, 16\n  fmv.d.x fa") ; push_int(sb, grfb) ; push_str(sb, ", t1\n") }
                if grcls < 8 and (not grif) { push_str(sb, "  ld a") ; push_int(sb, grcls) ; push_str(sb, ", 0(sp)\n  addi sp, sp, 16\n") }
              }
              gri = gri - 1
            }
          }
          if gwide and sret_on_g and (not sret_ind_g) { push_str(sb, "  addi a0, s0, ") ; push_int(sb, sret_dst_g) ; push_str(sb, "\n") }
          if gwide and sret_on_g and sret_ind_g { push_str(sb, "  ld a0, ") ; push_int(sb, sret_dst_g) ; push_str(sb, "(s0)\n") }
          if gwide and (not sret_on_g) { push_str(sb, "  ebreak\n") }
          ## INLINE `call <fn>__<tag>` (same reason the def label is inline — no span-through-params helper).
          push_str(sb, "  call ")
          push_str(sb, str_at((src + gd.name_start), gd.name_len))
          push_str(sb, "__")
          if str_at((src + tas), 1) == "[" {
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
          if RV_TA_N2 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + RV_TA_S2), RV_TA_N2)) }
          if RV_TA_N3 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + RV_TA_S3), RV_TA_N3)) }
          push_str(sb, "\n")
          if gwide and gstacksz > 0 { push_str(sb, "  addi sp, sp, ") ; push_int(sb, gstacksz) ; push_str(sb, "\n") }
          if gwide { RV_SRET_DST_ON = sret_on_g ; RV_SRET_DST_IND = sret_ind_g ; RV_SRET_DST = sret_dst0_g }
        }
      } else if rv_bound_lambda(body_head, src, cs, cl, decls) >= 0 {
        td := deref(decl_get(decls, usize(rv_bound_lambda(body_head, src, cs, cl, decls))))
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
        while fg != 0 { fa := deref(arg_p(fg)) ; if rv_is_float_expr(fa.e, body_head, src, a, params_head, decls, 0) { bad = true } ; fg = fa.next }
        if bad {
          push_str(sb, "  ebreak # local lambda direct call supports <=8 integer scalar args/return\n")
        } else {
          mut g := args_head
          while g != 0 { ga := deref(arg_p(g)) ; emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) ; push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n") ; g = ga.next }
          mut n := arg_list_count(args_head, a)
          while n > 0 { n = n - 1 ; push_str(sb, "  ld a") ; push_int(sb, n) ; push_str(sb, ", 0(sp)\n  addi sp, sp, 16\n") }
          push_str(sb, "  call ") ; rv_emit_lambda_label(sb, src, td.mod_start, td.mod_len, td.name_start) ; push_str(sb, "\n")
        }
      } else if not rv_callee_defined(decls, src, cs, cl, a) {
        push_str(sb, "  ebreak\n")
      } else if arg_list_count(args_head, a) > 8 or (direct_sretcall and arg_list_count(args_head, a) > 7) {
        ## >8 args of a class (LP64D): first 8 int in a0-a7, first 8 float in fa0-fa7 (independent
        ## counters); an arg whose class index reaches 8 overflows to the outgoing stack block. Stack
        ## slots are class-agnostic raw 8-byte words (the value model carries a float's bits in a GPR).
        ## Overflow args go at k*8(sp); register args use the push-to-scratch / pop dance, skipping them.
        n := arg_list_count(args_head, a)
        sretcall_over := direct_sretcall
        mut ashift_over := 0
        if sretcall_over { ashift_over = 1 }
        sret_on_over := RV_SRET_DST_ON
        sret_ind_over := RV_SRET_DST_IND
        sret_dst_over := RV_SRET_DST
        RV_SRET_DST_ON = false
        RV_SRET_DST_IND = false
        cparams := rv_callee_params(decls, src, cs, cl)
        ## a struct-LITERAL or struct-RETURNING-CALL arg needs the RV_AGG by-reference materialization, which
        ## the >8-arg overflow path does NOT perform. Trap FIRST (loud, never silent); the corpus has none.
        mut aggarg := false
        mut gsc := args_head
        while gsc != 0 { gsa := deref(arg_p(gsc)) ; if rv_is_slit(gsa.e) or rv_is_elit(gsa.e) or (rv_call_ret_struct_span(gsa.e, decls, src, a).n != 0) or (rv_call_ret_enum_span(gsa.e, decls, src, a).n != 0) or (rv_call_ret_sret_span(gsa.e, decls, src, a).n != 0) or (rv_call_ret_enum_sret_span(gsa.e, decls, src, a).n != 0) { aggarg = true } ; gsc = gsa.next }
        if aggarg { push_str(sb, "  ebreak\n") }
        mut nstk := 0
        mut ci := 0
        while ci < n {
          fb0 := rv_float_params_before(cparams, src, ci, a)
          mut cls := ci - fb0
          if rv_param_is_float(cparams, src, ci, a) { cls = fb0 }
          if (not rv_param_is_float(cparams, src, ci, a)) { cls = cls + ashift_over }
          if cls >= 8 { nstk = nstk + 1 }
          ci = ci + 1
        }
        stacksz := ((nstk * 8 + 15) / 16) * 16
        if stacksz > 0 { push_str(sb, "  addi sp, sp, -") ; push_int(sb, stacksz) ; push_str(sb, "\n") }
        mut gs := args_head
        mut gi := 0
        mut k := 0
        while gs != 0 {
          ga := deref(arg_p(gs))
          fbs := rv_float_params_before(cparams, src, gi, a)
          mut clss := gi - fbs
          if rv_param_is_float(cparams, src, gi, a) { clss = fbs }
          if (not rv_param_is_float(cparams, src, gi, a)) { clss = clss + ashift_over }
          if clss >= 8 {
            outargS := rv_param_out_scalar(cparams, src, decls, gi)
            if outargS { rv_emit_out_scalar_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if not outargS {
              ansS := ex_var_ns(ga.e)
              anlS := ex_var_nl(ga.e)
              isaggS := anlS != 0 and ((rv_local_struct_nl(body_head, src, ansS, anlS, a) != 0) or (rv_local_enum_nl(body_head, src, ansS, anlS, a) != 0) or rv_is_array_local(body_head, src, ansS, anlS, a))
              aoffS := rv_local_off(body_head, src, ansS, anlS, pcount, a, decls)
              if isaggS and aoffS >= 0 { push_str(sb, "  addi a0, s0, ") ; push_int(sb, aoffS) ; push_str(sb, "\n") }
              if not (isaggS and aoffS >= 0) { emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            }
            push_str(sb, "  sd a0, ") ; push_int(sb, k * 8) ; push_str(sb, "(sp)\n")
            k = k + 1
          }
          gi = gi + 1
          gs = ga.next
        }
        mut gr := args_head
        mut gj := 0
        while gr != 0 {
          ga := deref(arg_p(gr))
          fbr := rv_float_params_before(cparams, src, gj, a)
          mut clsr := gj - fbr
          if rv_param_is_float(cparams, src, gj, a) { clsr = fbr }
          if (not rv_param_is_float(cparams, src, gj, a)) { clsr = clsr + ashift_over }
          if clsr < 8 {
            outargR := rv_param_out_scalar(cparams, src, decls, gj)
            if outargR { rv_emit_out_scalar_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if not outargR {
              ansR := ex_var_ns(ga.e)
              anlR := ex_var_nl(ga.e)
              isaggR := anlR != 0 and ((rv_local_struct_nl(body_head, src, ansR, anlR, a) != 0) or (rv_local_enum_nl(body_head, src, ansR, anlR, a) != 0) or rv_is_array_local(body_head, src, ansR, anlR, a))
              aoffR := rv_local_off(body_head, src, ansR, anlR, pcount, a, decls)
              if isaggR and aoffR >= 0 { push_str(sb, "  addi a0, s0, ") ; push_int(sb, aoffR) ; push_str(sb, "\n") }
              if not (isaggR and aoffR >= 0) { emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            }
            push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          }
          gj = gj + 1
          gr = ga.next
        }
        mut ii := n - 1
        while ii >= 0 {
          fbp := rv_float_params_before(cparams, src, ii, a)
          mut clsp := ii - fbp
          isfp := rv_param_is_float(cparams, src, ii, a)
          if isfp { clsp = fbp }
          if not isfp { clsp = clsp + ashift_over }
          reg := clsp < 8
          if reg and isfp { push_str(sb, "  ld t1, 0(sp)\n  addi sp, sp, 16\n  fmv.d.x fa") ; push_int(sb, fbp) ; push_str(sb, ", t1\n") }
          if reg and (not isfp) { push_str(sb, "  ld a") ; push_int(sb, ii - fbp + ashift_over) ; push_str(sb, ", 0(sp)\n  addi sp, sp, 16\n") }
          ii = ii - 1
        }
        if sretcall_over and sret_on_over and (not sret_ind_over) { push_str(sb, "  addi a0, s0, ") ; push_int(sb, sret_dst_over) ; push_str(sb, "\n") }
        if sretcall_over and sret_on_over and sret_ind_over { push_str(sb, "  ld a0, ") ; push_int(sb, sret_dst_over) ; push_str(sb, "(s0)\n") }
        if sretcall_over and (not sret_on_over) { push_str(sb, "  ebreak\n") }
        push_str(sb, "  call ") ; rv_emit_call_target(sb, decls, src, cs, cl) ; push_str(sb, "\n")
        if stacksz > 0 { push_str(sb, "  addi sp, sp, ") ; push_int(sb, stacksz) ; push_str(sb, "\n") }
        if callee_ret_is_float(decls, src, cs, cl) { push_str(sb, "  fmv.x.d a0, fa0\n") }
        RV_SRET_DST_ON = sret_on_over
        RV_SRET_DST_IND = sret_ind_over
      } else {
        ## LP64 INDIRECT RESULT (SRET): a callee returning a plain struct WIDER than the 8-word register
        ## budget takes the destination address in a0 (the implicit first argument), so the real arguments
        ## shift one integer register up (a1..a7). `mysret` needs a destination handed down by the binding
        ## arm (`s := mk(…)`); clear the hand-off while the ARGUMENTS are emitted so a nested call cannot
        ## consume the same destination, and restore it after the call.
        sretcall := direct_sretcall
        mysret := sretcall and RV_SRET_DST_ON
        mydst := RV_SRET_DST
        ## the INDIRECT flavour (`return mk(…)`): mydst is the frame SLOT holding the destination pointer.
        myind := RV_SRET_DST_IND
        sret_on0 := RV_SRET_DST_ON
        sret_ind0 := RV_SRET_DST_IND
        RV_SRET_DST_ON = false
        RV_SRET_DST_IND = false
        mut ashift := 0
        if sretcall { ashift = 1 }
        cparams := rv_callee_params(decls, src, cs, cl)
        mut g := args_head
        mut gidx := 0
        while g != 0 {
          ga := deref(arg_p(g))
          ## a struct/array LOCAL arg is passed BY REFERENCE — its base address (s0 + slot). A SLICE arg
          ## `xs[lo..hi]` is materialized into a reserved `{ptr,len}` agg block and its ADDRESS passed.
          ans := ex_var_ns(ga.e)
          anl := ex_var_nl(ga.e)
          isslicearg := ex_is_slice(ga.e)
          ## an anonymous STRUCT-LITERAL VALUE arg (`f(S(…))`) — materialized into an RV_AGG block and
          ## passed BY REFERENCE (§8 anonymous-aggregate materialization, piece 1).
          isaggval := rv_is_slit(ga.e)
          ## an anonymous ENUM-LITERAL VALUE arg (`f(E.V(…))`) — materialized into an RV_AGG block and
          ## passed BY REFERENCE (§8 piece 3).
          isenumval := rv_is_elit(ga.e)
          ## a struct-RETURNING CALL arg (`f(mk(…))`) — register-returned words materialized into an RV_AGG
          ## block and passed BY REFERENCE (§8 piece 2).
          iscallretarg := (not isaggval) and (not isenumval) and rv_call_ret_struct_span(ga.e, decls, src, a).n != 0
          ## an enum-RETURNING CALL arg — register-returned {disc,payload} words materialized by-ref (§8 piece 3).
          isenumretarg := (not isaggval) and (not isenumval) and (not iscallretarg) and rv_call_ret_enum_span(ga.e, decls, src, a).n != 0
          ## a WIDE (SRET) struct-returning CALL arg (`f(mk(…))`, > 8 words) — disjoint from iscallretarg (the
          ## 1..8-word register gate) by the width split. The callee delivers through the LP64 indirect result
          ## in a0, and in ARGUMENT position there is no destination local to point it at, so a block is
          ## reserved, handed down as a0, and then passed BY REFERENCE (emit_rv_sretcall_arg). Without this
          ## the call fell through to the `sretcall and (not mysret)` fail-loud `ebreak`.
          issretarg := (not isaggval) and (not isenumval) and (not iscallretarg) and (not isenumretarg) and rv_call_ret_sret_span(ga.e, decls, src, a).n != 0
          ## the wide-ENUM (> 8 words, a0 SRET) analogue — same shape, same reserved-block hand-off.
          isesretarg := (not isaggval) and (not isenumval) and (not iscallretarg) and (not isenumretarg) and (not issretarg) and rv_call_ret_enum_sret_span(ga.e, decls, src, a).n != 0
          ## a struct/array/slice-VIEW LOCAL arg is passed BY REFERENCE (frame base address). A slice VIEW
          ## local is already a `{ptr,len}` block, so its address IS the by-ref `Slice(E)` argument.
          ## …and an ENUM LOCAL too (`v := E.V(…)` / `v := mk()` then `f(v)`): a callee's enum param slot
          ## holds a POINTER to the caller's {disc, payload…} block (rv_param_enum_ns / the `match <enum
          ## param>` materialization), exactly like a struct param. Without this the local fell to the
          ## scalar path and its word 0 — the DISCRIMINANT — was passed AS the pointer, so the callee
          ## dereferenced e.g. 0: a RAW SIGSEGV (narrow and wide enums alike), not a clean `ebreak`.
          isenumlocal := anl != 0 and rv_local_enum_nl(body_head, src, ans, anl, a) != 0
          isagg := (not isslicearg) and (not isaggval) and (not isenumval) and (not iscallretarg) and (not isenumretarg) and (not issretarg) and (not isesretarg) and anl != 0 and ((rv_local_struct_nl(body_head, src, ans, anl, a) != 0) or isenumlocal or rv_is_array_local(body_head, src, ans, anl, a) or rv_is_slice_local(body_head, src, ans, anl, a))
          aoff := rv_local_off(body_head, src, ans, anl, pcount, a, decls)
          outarg := rv_param_out_scalar(cparams, src, decls, gidx)
          if outarg { rv_emit_out_scalar_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if not outarg {
            if isslicearg { emit_rv_slice_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if isaggval { emit_rv_aggval_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if isenumval { emit_rv_enumval_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if iscallretarg { emit_rv_callret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if isenumretarg { emit_rv_enumret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if issretarg { emit_rv_sretcall_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if isesretarg { emit_rv_enumsret_arg(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            if isagg and aoff >= 0 { push_str(sb, "  addi a0, s0, ") ; push_int(sb, aoff) ; push_str(sb, "\n") }
            if (not isslicearg) and (not isaggval) and (not isenumval) and (not iscallretarg) and (not isenumretarg) and (not issretarg) and (not isesretarg) and (not (isagg and aoff >= 0)) { emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          }
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          gidx += 1
          g = ga.next
        }
        ## FLOAT ABI: pop args (reverse) routing each to its class register per the CALLEE's param types —
        ## a float param i → fa<float-idx>, an int param i → a<int-idx> (independent counters, matching the
        ## callee prologue). A float RETURN comes back in fa0 → move to a0 for the integer path.
        n := arg_list_count(args_head, a)
        mut i := n - 1
        while i >= 0 {
          if rv_param_is_float(cparams, src, i, a) {
            fb := rv_float_params_before(cparams, src, i, a)
            push_str(sb, "  ld t1, 0(sp)\n  addi sp, sp, 16\n  fmv.d.x fa") ; push_int(sb, fb) ; push_str(sb, ", t1\n")
          } else {
            fb := rv_float_params_before(cparams, src, i, a)
            push_str(sb, "  ld a") ; push_int(sb, i - fb + ashift) ; push_str(sb, ", 0(sp)\n  addi sp, sp, 16\n")
          }
          i = i - 1
        }
        ## the indirect-result pointer goes in LAST (the pops above filled a1..a7). DIRECT flavour: the
        ## destination is a frame block of ours (`addi a0, s0, <off>`). INDIRECT flavour (tail-forward):
        ## RELOAD the pointer the outer caller gave us from its spill slot (`ld a0, <slot>(s0)`) — s0 is
        ## untouched by the argument push/pop dance above, so the pointer reaches the `call` intact.
        if mysret and (not myind) { push_str(sb, "  addi a0, s0, ") ; push_int(sb, mydst) ; push_str(sb, "\n") }
        if mysret and myind { push_str(sb, "  ld a0, ") ; push_int(sb, mydst) ; push_str(sb, "(s0)\n") }
        ## an SRET callee reached with NO destination in scope (a bare call statement, a nested SRET call)
        ## is unsupported — trap LOUD rather than call with a garbage result pointer.
        if sretcall and (not mysret) { push_str(sb, "  ebreak\n") }
        ## MOD §7.2: a call to an `@extern` callee branches to its EXTERNAL symbol, not the source name.
        push_str(sb, "  call ") ; rv_emit_call_target(sb, decls, src, cs, cl) ; push_str(sb, "\n")
        RV_SRET_DST_ON = sret_on0
        RV_SRET_DST_IND = sret_ind0
        if callee_ret_is_float(decls, src, cs, cl) { push_str(sb, "  fmv.x.d a0, fa0\n") }
      }
    }
    Expr::Match(scrut, arms) => {
      sns := ex_var_ns(scrut)
      snl := ex_var_nl(scrut)
      ens := rv_local_enum_ns(body_head, src, sns, snl, a)
      enl := rv_local_enum_nl(body_head, src, sns, snl, a)
      eoff := rv_local_off(body_head, src, sns, snl, pcount, a, decls)
      endid := rv_next_label()
      ok := snl != 0 and enl != 0 and eoff >= 0
      ## a `match <enum PARAM>` (§8 piece 3): the param slot holds a POINTER to the {disc,payload…} block;
      ## materialize its words into RV_MTMP, then match on that offset.
      pidxM := rv_param_find(params_head, src, sns, snl, a)
      penlM := rv_param_enum_nl(params_head, src, sns, snl, decls)
      paramok := (not ok) and pidxM >= 0 and penlM != 0
      ## a nested `match <enum payload BINDING>` (§8 piece 3b): match directly at frame offset bind_base + 8.
      bagg := rv_bind_agg_span(bind_head, src, sns, snl, a, decls)
      bindok := (not ok) and (not paramok) and bagg.n != 0 and enum_decl_of(decls, src, bagg.s, bagg.n) >= 0
      if ok {
        emit_rv_match_arms(arms, ens, enl, eoff, endid, sb, a, src, params_head, pcount, body_head, decls, 0 - 1)
        push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
      }
      if paramok {
        pensM := rv_param_enum_ns(params_head, src, sns, snl, decls)
        wM := 1 + i64(enum_max_arity(decls, src, pensM, penlM, a))
        push_str(sb, "  ld t0, ") ; push_int(sb, 16 + pidxM * 8) ; push_str(sb, "(s0)\n")
        mut km := 0
        while km < wM { push_str(sb, "  ld a0, ") ; push_int(sb, km * 8) ; push_str(sb, "(t0)\n  sd a0, ") ; push_int(sb, RV_MTMP + km * 8) ; push_str(sb, "(s0)\n") ; km = km + 1 }
        emit_rv_match_arms(arms, pensM, penlM, RV_MTMP, endid, sb, a, src, params_head, pcount, body_head, decls, 0 - 1)
        push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
      }
      if bindok {
        emit_rv_match_arms(arms, bagg.s, bagg.n, bind_base + 8, endid, sb, a, src, params_head, pcount, body_head, decls, 0 - 1)
        push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
      }
      ## a `match s.f` where `s` is a LOCAL struct and `f` is an ENUM FIELD: the enum lives INLINE in the
      ## struct's frame slot at (s_off + field_word_offset(f)*8) — match DIRECTLY at that offset with the
      ## field's declared enum type. Single-match Field accessors (never matching the bound scrut inline).
      mut fldok := false
      if ex_is_field(scrut) {
        fbase := rv_field_base(scrut)
        fbns := ex_var_ns(fbase)
        fbnl := ex_var_nl(fbase)
        ffs := rv_field_fns(scrut)
        ffl := rv_field_fnl(scrut)
        fstys := rv_local_struct_ns(body_head, src, fbns, fbnl, a)
        fstyn := rv_local_struct_nl(body_head, src, fbns, fbnl, a)
        fsoff := rv_local_off(body_head, src, fbns, fbnl, pcount, a, decls)
        ## PLAIN (arity-0) struct base only — gate BEFORE field_type_span/field_word_offset (a comptime-
        ## value-param type-fn would panic).
        fplain := fbnl != 0 and fstyn != 0 and fsoff >= 0 and struct_plain(decls, src, fstys, fstyn)
        mut ffts := CSpan(s = 0, n = 0)
        mut fwoff := i64(0)
        if fplain { ffts = field_type_span(decls, src, fstys, fstyn, ffs, ffl, a) ; fwoff = field_word_offset(decls, src, fstys, fstyn, ffs, ffl, a) }
        fen := fplain and ffts.n != 0 and enum_decl_of(decls, src, ffts.s, ffts.n) >= 0
        if fen {
          fldok = true
          emit_rv_match_arms(arms, ffts.s, ffts.n, fsoff + fwoff * 8, endid, sb, a, src, params_head, pcount, body_head, decls, 0 - 1)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
      }
      if (not ok) and (not paramok) and (not bindok) and (not fldok) { push_str(sb, "  ebreak\n") }
    }
    Expr::Index(ibase, iidx) => {
      ## `a[i]` for an ARRAY local: addr = s0 + i*8, element at (base_off)(addr). i is runtime.
      bns := ex_var_ns(ibase)
      bnl := ex_var_nl(ibase)
      mut isslice := false
      if bnl != 0 { if rv_is_slice_local(body_head, src, bns, bnl, a) { isslice = true } }
      isarr := (not isslice) and bnl != 0 and rv_is_array_local(body_head, src, bns, bnl, a)
      pidxI := rv_param_find(params_head, src, bns, bnl, a)
      mut isparamslice := false
      if (not isslice) and (not isarr) and pidxI >= 0 { if rv_slice_param_scalar(params_head, src, bns, bnl, a, decls) { isparamslice = true } }
      tupn := if (not isslice) and (not isarr) and (not isparamslice) and pidxI >= 0 { param_tuple_allscalar_n(params_head, src, bns, bnl, decls, a) } else { 0 }
      aoff := rv_local_off(body_head, src, bns, bnl, pcount, a, decls)
      ## DEEP index read — `xs[i].arr[j]` (an index into an inline `[T; N]` FIELD of an array element) and
      ## `b.cells[i]`-shaped bases: the base is NOT a bare Var, so no closed frame formula exists. Tried
      ## LAST in the chain, so every array/slice/param shape above keeps its exact emit.
      dielem := rv_place_idx_ty(ibase, body_head, src, a, decls)
      mut deepidx := false
      if dielem.n != 0 {
        if ty_is_scalar(dielem.s, dielem.n, decls, src) {
          if rv_place_idx_ok(ibase, body_head, src, params_head, pcount, a, decls) { deepidx = true }
        }
      }
      mut stdarr := rv_std_path_ty(ibase, body_head, src, a, decls)
      mut stdpathok := rv_std_path_ok(ibase, body_head, src, a, decls)
      mut stdparamidx := false
      if not stdpathok {
        if rv_std_param_path_ok(ibase, params_head, src, a, decls) {
          stdarr = rv_std_param_path_ty(ibase, params_head, src, a, decls)
          stdpathok = true
          stdparamidx = true
        }
      }
      stdel := rv_arrty_elem(src, stdarr.s, stdarr.n)
      mut stdidx := false
      if stdpathok and stdel.n != 0 {
        if scalar_byte_size(src, stdel.s, stdel.n) == 1 { stdidx = true }
      }
      stdidxarr := rv_std_idx_path_ty(ibase, body_head, src, a, decls)
      stdidxel := rv_arrty_elem(src, stdidxarr.s, stdidxarr.n)
      mut stdidxelem := false
      if rv_std_idx_path_ok(ibase, body_head, src, a, decls) and stdidxel.n != 0 and scalar_byte_size(src, stdidxel.s, stdidxel.n) == 1 { stdidxelem = true }
      if stdidxelem {
        ## `xs[i].data[j]`: preserve the inner index while composing the byte-strided outer element,
        ## add the byte field path, then perform a one-byte signed/unsigned load.
        emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
        emit_rv_place_idx_addr(rv_std_idx_root_arr(ibase), rv_std_idx_root_idx(ibase), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        siboE := rv_std_idx_path_bo(ibase, body_head, src, a, decls)
        if siboE != 0 { push_str(sb, "  li a1, ") ; push_int(sb, siboE) ; push_str(sb, "\n  add a0, a0, a1\n") }
        push_str(sb, "  ld a1, 0(sp)\n  addi sp, sp, 16\n")
        if RV_CHK {
          snelE := rv_arrty_nel(src, stdidxarr.s, stdidxarr.n)
          if snelE > 0 { push_str(sb, "  li a2, ") ; push_int(sb, snelE) ; push_str(sb, "\n  bltu a1, a2, 1f\n  ebreak\n1:\n") }
        }
        push_str(sb, "  add a0, a0, a1\n")
        if stdidxel.n != 0 and str_at((src + stdidxel.s), 1) == "i" { push_str(sb, "  lb a0, 0(a0)\n") }
        if stdidxel.n == 0 or str_at((src + stdidxel.s), 1) != "i" { push_str(sb, "  lbu a0, 0(a0)\n") }
      }
      else if stdidx {
        ## Byte-array field read (`p.bytes[i]`): standard field offset is a byte offset and the element
        ## stride is one byte, unlike the legacy word-array path below.
        emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if RV_CHK {
          snel := rv_arrty_nel(src, stdarr.s, stdarr.n)
          if snel > 0 { push_str(sb, "  li a1, ") ; push_int(sb, snel) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
        }
        mut sboI := i64(0)
        if stdparamidx { sboI = rv_std_param_path_bo(ibase, params_head, src, a, decls) }
        if not stdparamidx { sboI = rv_std_path_bo(ibase, body_head, src, a, decls) }
        if stdparamidx {
          spidxI := rv_std_param_path_idx(ibase, params_head, src, a, decls)
          push_str(sb, "  ld t3, ") ; push_int(sb, 16 + spidxI * 8) ; push_str(sb, "(s0)\n")
          if sboI != 0 { push_str(sb, "  li t4, ") ; push_int(sb, sboI) ; push_str(sb, "\n  add t3, t3, t4\n") }
        }
        if not stdparamidx {
          srootI := rv_std_path_root_off(ibase, body_head, src, pcount, a, decls)
          push_str(sb, "  li t3, ") ; push_int(sb, srootI) ; push_str(sb, "\n  add t3, t3, s0\n")
          if sboI != 0 { push_str(sb, "  li t4, ") ; push_int(sb, sboI) ; push_str(sb, "\n  add t3, t3, t4\n") }
        }
        push_str(sb, "  add t3, t3, a0\n  lbu a0, 0(t3)\n")
      }
      else if tupn > 0 {
        ## `t.N` (= Index(Var(t), Num(N))) on an ALL-SCALAR tuple PARAM: the param slot (`16 + pidxI*8`(s0))
        ## holds a POINTER to the caller's tuple words (by-reference). Each component is one word, so element
        ## i is at `0(tupleptr + i*8)`. Bounds vs the static component count (dropped under `unchecked`).
        emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        pslotT := 16 + pidxI * 8
        if RV_CHK { push_str(sb, "  li a1, ") ; push_int(sb, tupn) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
        push_str(sb, "  slli a0, a0, 3\n  ld t3, ") ; push_int(sb, pslotT) ; push_str(sb, "(s0)\n  add t3, t3, a0\n  ld a0, 0(t3)\n")
      }
      else if isparamslice {
        ## `s[i]` on a scalar `Slice(E)` PARAM: the param slot (`16 + pidxI*8`(s0)) holds a POINTER to the
        ## caller's `{ptr,len}` block. DOUBLE deref: block word1 (`8(t3)`) = runtime len (bounds check);
        ## block word0 (`0(t3)`) = data ptr; element i at `0(ptr + i*8)`. Reload the block AFTER the index
        ## expr (may clobber scratch). Bounds dropped under `unchecked`.
        emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        pslotI := 16 + pidxI * 8
        if RV_CHK {
          push_str(sb, "  ld t3, ") ; push_int(sb, pslotI) ; push_str(sb, "(s0)\n  ld a1, 8(t3)\n  bltu a0, a1, 1f\n  ebreak\n1:\n")
        }
        push_str(sb, "  slli a0, a0, 3\n  ld t3, ") ; push_int(sb, pslotI) ; push_str(sb, "(s0)\n  ld a2, 0(t3)\n  add a2, a2, a0\n  ld a0, 0(a2)\n")
      }
      else if isslice and aoff >= 0 {
        ## `s[i]` on a range-slice VIEW: bounds vs the RUNTIME len (word1 at aoff+8), then load ELEMENT i
        ## through the data pointer (word0 at aoff): addr = ptr + i*8. `bltu` skips on idx < len (a negative
        ## i64 index is a huge unsigned → traps). Bounds dropped under `unchecked` (CG-7).
        emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if RV_CHK {
          push_str(sb, "  ld a1, ") ; push_int(sb, aoff + 8) ; push_str(sb, "(s0)\n  bltu a0, a1, 1f\n  ebreak\n1:\n")
        }
        push_str(sb, "  slli a0, a0, 3\n  ld a2, ") ; push_int(sb, aoff) ; push_str(sb, "(s0)\n  add a2, a2, a0\n  ld a0, 0(a2)\n")
      }
      else if isarr and aoff >= 0 {
        emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        ## CHECKED BOUNDS (I11 / CG-7): the index is in a0; trap (`ebreak`) when it is out of the array's
        ## static count. `bltu` (unsigned) skips on `idx < N`, so a negative i64 index (huge unsigned) also
        ## traps. `a1` is scratch (the address math below uses a0/s0). Dropped under `unchecked`.
        if RV_CHK {
          rnel := rv_array_nel(body_head, src, bns, bnl, a)
          if rnel > 0 {
            push_str(sb, "  li a1, ") ; push_int(sb, rnel) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n")
          }
        }
        push_str(sb, "  slli a0, a0, 3\n  add a0, a0, s0\n  ld a0, ") ; push_int(sb, aoff) ; push_str(sb, "(a0)\n")
      }
      else if bnl != 0 and rv_is_array_global(decls, src, bns, bnl) {
        ## `TABLE[i]` on an ARRAY GLOBAL: element i at LABEL + i*8. Bounds vs the static element count
        ## (dropped under `unchecked`). a2 = base label addr, a0 = index scaled.
        emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        if RV_CHK {
          gnelR := rv_alit_nel(rv_global_value(decls, src, bns, bnl))
          if gnelR > 0 { push_str(sb, "  li a1, ") ; push_int(sb, gnelR) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
        }
        gcn := str_at((src + bns), bnl)
        push_str(sb, "  slli a0, a0, 3\n  la a2, ") ; push_str(sb, gcn) ; push_str(sb, "\n  add a2, a2, a0\n  ld a0, 0(a2)\n")
      }
      else if pidxI >= 0 and rv_param_gen_arr_stride(params_head, src, bns, bnl, a, decls) > 0 {
        ## `a[i]` on a GENERIC array PARAM (`a : T`, T → `[E; N]` scalar element in this instance): the
        ## param slot (`16 + pidxI*8`(s0)) holds the array BASE ADDRESS (passed by-reference by the caller),
        ## so element i (1 word) is at `[base + i*8]`. Bounds vs the static N (from the instance array type)
        ## dropped under `unchecked`. Reload the base AFTER the index expr (it may clobber scratch).
        emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        pslotG := 16 + pidxI * 8
        if RV_CHK {
          gnelP := rv_sub_arr_len(src)
          if gnelP > 0 { push_str(sb, "  li a1, ") ; push_int(sb, gnelP) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
        }
        push_str(sb, "  slli a0, a0, 3\n  ld t3, ") ; push_int(sb, pslotG) ; push_str(sb, "(s0)\n  add t3, t3, a0\n  ld a0, 0(t3)\n")
      }
      else if deepidx {
        emit_rv_place_idx_addr(ibase, iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  ld a0, 0(a0)\n")
      }
      else { push_str(sb, "  ebreak\n") }
    }
    Expr::Unchecked(inner) => {
      ov := RV_CHK
      RV_CHK = false
      emit_rv_expr(inner, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      RV_CHK = ov
    }
    _ => { push_str(sb, "  ebreak\n") }
  }
}

## Emit a SCALAR statement-match arm chain (RV). The caller has already evaluated the integer scrutinee
## into a0; compare it against each literal without clobbering a0, then emit the selected body. A wildcard
## always matches. Unsupported pattern kinds remain a loud ebreak and never become a wrong value.
emit_rv_scalar_match_arms := fn(arm : usize, endid : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), frame : i64) {
  mut ar := arm
  while ar != 0 {
    am := deref(arm_p(ar))
    aid := rv_next_label()
    if am.wild == 0 {
      push_str(sb, "  li a1, ") ; push_int(sb, am.lit) ; push_str(sb, "\n  bne a0, a1, .Lscalararmskip") ; push_int(sb, aid) ; push_str(sb, "\n")
    } else if am.wild != 1 {
      push_str(sb, "  ebreak # unsupported scalar match pattern on riscv64\n")
    }
    hasexpr := am.body_stmts == 0
    dostmt := (am.body_stmts != 0) and (frame >= 0)
    if hasexpr { emit_rv_expr(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, 0) }
    if dostmt { emit_rv_stmts(am.body_stmts, sb, a, src, params_head, pcount, body_head, decls, frame, am.binds_head, 0) }
    if (not hasexpr) and (not dostmt) { push_str(sb, "  ebreak # scalar match statement body in value position deferred\n") }
    push_str(sb, "  j .Lmend") ; push_int(sb, endid) ; push_str(sb, "\n")
    if am.wild == 0 { push_str(sb, ".Lscalararmskip") ; push_int(sb, aid) ; push_str(sb, ":\n") }
    ar = am.next
  }
  push_str(sb, "  ebreak # no matching scalar arm\n")
}

## Emit a match arm chain (RV): compare the scrutinee discriminant (word 0 at `eoff(s0)`) to each arm's
## variant index; on match emit the body (payload bindings active: am.binds_head@eoff) and jump to
## `.Lmend<endid>`. An EXPRESSION-body arm leaves its value in a0; a STATEMENT-body arm runs via
## emit_rv_stmts (needs a real `frame`; NEGATIVE `frame` = value position → stmt body deferred). Wildcard
## always matches. FLAT: label id from the arm handle. No match → trailing ebreak.
emit_rv_match_arms := fn(arm : usize, ens : usize, enl : usize, eoff : i64, endid : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), frame : i64) {
  mut ar := arm
  while ar != 0 {
    am := deref(arm_p(ar))
    ## RANGE pattern arm (`wild == 5`/`6`, Control Flow §5.4) — x86_64-only in v1. Fail LOUD here (an
    ## `ebreak` trap dominates the dead compare that follows), never a silent miscompile: the rv64
    ## sweep requires a trap or assemble-reject, not a valid binary with a wrong exit.
    if am.wild == 5 or am.wild == 6 { push_str(sb, "  ebreak # range-pattern match arm not supported on riscv64 (x86_64 only)\n") }
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
          ## SAME enum would collide on a variant-keyed id. Compound `.LarmskipV<endid>_<vc>` keeps them disjoint.
          push_str(sb, "  ld a0, ") ; push_int(sb, eoff) ; push_str(sb, "(s0)\n")
          push_str(sb, "  li a1, ") ; push_int(sb, vvidx) ; push_str(sb, "\n  bne a0, a1, .LarmskipV") ; push_int(sb, endid) ; push_str(sb, "_") ; push_int(sb, vc) ; push_str(sb, "\n")
          hasexprV := am.body_stmts == 0
          dostmtV := (am.body_stmts != 0) and (frame >= 0)
          oensV := RV_ARM_ENS ; oenlV := RV_ARM_ENL ; ovsV := RV_ARM_VS ; ovlV := RV_ARM_VL
          ocvs := RV_CFVAR_S ; ocvl := RV_CFVAR_L ; obV := RV_ARM_BINDS
          RV_ARM_ENS = ens ; RV_ARM_ENL = enl ; RV_ARM_VS = vfm.ns ; RV_ARM_VL = vfm.nl
          RV_CFVAR_S = vfm.ns ; RV_CFVAR_L = vfm.nl ; RV_ARM_BINDS = unchecked bitcast(usize, am.binds_head)
          if hasexprV { emit_rv_expr(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, eoff) }
          if dostmtV { emit_rv_stmts(am.body_stmts, sb, a, src, params_head, pcount, body_head, decls, frame, am.binds_head, eoff) }
          if (not hasexprV) and (not dostmtV) { push_str(sb, "  ebreak\n") }
          RV_ARM_ENS = oensV ; RV_ARM_ENL = oenlV ; RV_ARM_VS = ovsV ; RV_ARM_VL = ovlV
          RV_CFVAR_S = ocvs ; RV_CFVAR_L = ocvl ; RV_ARM_BINDS = obV
          push_str(sb, "  j .Lmend") ; push_int(sb, endid) ; push_str(sb, "\n")
          push_str(sb, ".LarmskipV") ; push_int(sb, endid) ; push_str(sb, "_") ; push_int(sb, vc) ; push_str(sb, ":\n")
          vc = vc + 1
          vf = vfm.next
        }
      }
    }
    ## FLAT (no nesting): PER-EMISSION label id (rv_next_label — globally unique). A per-ARM-handle id
    ## would COLLIDE when the same arm is emitted more than once (a nested match inside a wild==2 unroll
    ## is re-emitted per variant). A non-wild arm compares + skips.
    hasexpr := am.body_stmts == 0
    dostmt := (am.body_stmts != 0) and (frame >= 0)
    aid := rv_next_label()
    ## a `wild == 3` arm is a `T.(v)` comptime-variant PATTERN: its variant name is the enclosing unroll's
    ## CURRENT variant (`RV_CFVAR_*`), not the arm's own `vs/vl` (which still hold the loop-var name `v`).
    mut evs := am.vs
    mut evl := am.vl
    if am.wild == 3 { evs = RV_CFVAR_S ; evl = RV_CFVAR_L }
    vidx := variant_index(decls, src, ens, enl, evs, evl, a)
    if am.wild != 1 and am.wild != 2 {
      push_str(sb, "  ld a0, ") ; push_int(sb, eoff) ; push_str(sb, "(s0)\n")
      push_str(sb, "  li a1, ") ; push_int(sb, vidx) ; push_str(sb, "\n  bne a0, a1, .Larmskip") ; push_int(sb, aid) ; push_str(sb, "\n")
    }
    ## record THIS arm's enum context (§8 piece 3b) for aggregate payload-binding resolution; save/restore.
    oens := RV_ARM_ENS
    oenl := RV_ARM_ENL
    ovs := RV_ARM_VS
    ovl := RV_ARM_VL
    obN := RV_ARM_BINDS
    RV_ARM_ENS = ens
    RV_ARM_ENL = enl
    RV_ARM_VS = evs
    RV_ARM_VL = evl
    RV_ARM_BINDS = unchecked bitcast(usize, am.binds_head)
    if am.wild != 2 and hasexpr { emit_rv_expr(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, eoff) }
    if am.wild != 2 and dostmt { emit_rv_stmts(am.body_stmts, sb, a, src, params_head, pcount, body_head, decls, frame, am.binds_head, eoff) }
    if am.wild != 2 and (not hasexpr) and (not dostmt) { push_str(sb, "  ebreak\n") }
    RV_ARM_ENS = oens
    RV_ARM_ENL = oenl
    RV_ARM_VS = ovs
    RV_ARM_VL = ovl
    RV_ARM_BINDS = obN
    if am.wild != 2 { push_str(sb, "  j .Lmend") ; push_int(sb, endid) ; push_str(sb, "\n") }
    if am.wild != 1 and am.wild != 2 { push_str(sb, ".Larmskip") ; push_int(sb, aid) ; push_str(sb, ":\n") }
    ar = am.next
  }
  push_str(sb, "  ebreak\n")
}

## Function epilogue: restore ra/s0, pop the frame, return.
## Materialize a SLICE ARGUMENT `xs[lo..hi]` into a reserved agg block and leave the block ADDRESS in a0 (the
## by-reference slice-arg convention). word0 = &base[lo] (= s0 + array-base-off + lo*8), word1 = hi - lo —
## byte-identical to the slice-VIEW binding. Only a scalar-element frame ARRAY-LOCAL base; else / overflow = ebreak.
emit_rv_slice_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  sbase := ex_slice_base(e)
  bns := ex_var_ns(sbase)
  bnl := ex_var_nl(sbase)
  aoff := rv_local_off(body_head, src, bns, bnl, pcount, a, decls)
  sliceok := bnl != 0 and rv_is_array_local(body_head, src, bns, bnl, a) and aoff >= 0 and (RV_AGG + 16) <= RV_AGG_LIM
  if sliceok {
    blk := RV_AGG
    ## word1 = hi - lo → blk+8(s0)
    emit_rv_expr(ex_slice_hi(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
    emit_rv_expr(ex_slice_lo(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, "  mv a1, a0\n  ld a0, 0(sp)\n  addi sp, sp, 16\n  sub a0, a0, a1\n  sd a0, ")
    push_int(sb, blk + 8) ; push_str(sb, "(s0)\n")
    ## word0 = &base[lo] = s0 + aoff + lo*estride*8 → blk(s0) (estride from base array; 1 = scalar, `slli 3`).
    estrideSA := rv_iter_stride(body_head, src, sbase, a, decls)
    emit_rv_expr(ex_slice_lo(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    if estrideSA == 1 { push_str(sb, "  slli a0, a0, 3\n") }
    if estrideSA != 1 { push_str(sb, "  li a1, ") ; push_int(sb, estrideSA * 8) ; push_str(sb, "\n  mul a0, a0, a1\n") }
    push_str(sb, "  add a0, a0, s0\n  addi a0, a0, ")
    push_int(sb, aoff) ; push_str(sb, "\n  sd a0, ")
    push_int(sb, blk) ; push_str(sb, "(s0)\n")
    ## arg value = the block's ADDRESS
    push_str(sb, "  addi a0, s0, ") ; push_int(sb, blk) ; push_str(sb, "\n")
    RV_AGG = RV_AGG + 16
  }
  if not sliceok { push_str(sb, "  ebreak\n") }
}

## Materialize a STRUCT LITERAL `S(f = v, …)` passed as a call ARGUMENT into a reserved RV_AGG block and
## leave the block's ADDRESS in a0 (the by-reference aggregate-argument convention — §8 anonymous-aggregate
## materialization, piece 1). Each field value → a0 → the block word `blk + k*8(s0)` (positional =
## declaration = word order, exactly as the `Assign` struct-construct path writes a struct LOCAL, so the
## callee's by-reference field READ reads identical layout). Scalar-field structs only (rv_struct_all_scalar);
## str/float-field literals stay a LOUD `ebreak`. Bumps RV_AGG by the struct's words; an overflow past
## RV_AGG_LIM (an under-reservation) is a loud `ebreak`. Distinct blocks (monotonic bump) → no aliasing.
emit_rv_aggval_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ns := rv_slit_ns(e)
  nl := rv_slit_nl(e)
  words := i64(struct_words(decls, src, ns, nl, a))
  ok := nl != 0 and (RV_AGG + words * 8) <= RV_AGG_LIM
  if ok {
    blk := RV_AGG
    ## Write each field VALUE at its running byte offset via the shared multi-word payload writer, which
    ## returns the words it occupied — so a field that is itself an ENUM (`S(c = Col.G(9), n = 2)`) or a
    ## nested struct/str lands in full and following fields stay aligned. An all-scalar struct is byte-
    ## identical to the old positional store. The block reserves the struct's FULL width; addr rides a0.
    mut off := blk
    mut g := ex_struct_lit_args(e)
    while g != 0 {
      ga := deref(arg_p(g))
      w := emit_rv_store_payload_at(ga.e, off, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      off = off + w * 8
      g = ga.next
    }
    push_str(sb, "  addi a0, s0, ") ; push_int(sb, blk) ; push_str(sb, "\n")
    RV_AGG = RV_AGG + words * 8
  }
  if not ok { push_str(sb, "  ebreak\n") }
}

## Materialize an ENUM LITERAL `E.V(p…)` passed as a call ARGUMENT into a reserved RV_AGG block and leave
## the block's ADDRESS in a0 (by-reference aggregate-argument convention, §8 piece 3). Word 0 = variant
## disc; payload arg k → block word k+1 (matching the enum-LOCAL construct in the Assign path). Reserves
## the enum's FULL width (1 + max_arity) so the callee can copy the whole block. Scalar payload only.
## Store ONE enum/struct payload VALUE `pe` into the frame at byte offset `off`, returning the WORDS it
## occupies (§8 piece 3b): scalar → 1; struct literal (all-scalar) → its fields; nested enum literal →
## {disc, payload…} recursively (full width); str literal → deferred loud `ebreak` (2 words reserved).
emit_rv_store_payload_at := fn(pe : ptr(Expr), off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  if rv_is_slit(pe) {
    ## A STRUCT literal: write each field at its RUNNING byte offset via the same multi-word writer, so a
    ## field that is itself a nested STRUCT (or enum) lands in full and following fields stay aligned. An
    ## all-scalar struct is byte-identical to a positional store. Lets a NESTED struct literal materialize.
    sns := rv_slit_ns(pe)
    snl := rv_slit_nl(pe)
    mut g := ex_struct_lit_args(pe)
    mut o2 := off
    while g != 0 {
      ga := deref(arg_p(g))
      w := emit_rv_store_payload_at(ga.e, o2, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      o2 = o2 + w * 8
      g = ga.next
    }
    return i64(struct_words(decls, src, sns, snl, a))
  }
  if rv_is_elit(pe) {
    pens := rv_elit_ens(pe)
    penl := rv_elit_enl(pe)
    pvidx := variant_index(decls, src, pens, penl, rv_elit_vns(pe), rv_elit_vnl(pe), a)
    push_str(sb, "  li a0, ") ; push_int(sb, pvidx) ; push_str(sb, "\n  sd a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n")
    mut g := ex_enum_lit_args(pe)
    mut wo := 1
    while g != 0 {
      ga := deref(arg_p(g))
      cw := emit_rv_store_payload_at(ga.e, off + wo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
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
      aw := emit_rv_store_payload_at(aga.e, ao, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      ao = ao + aw * 8
      atot = atot + aw
      ag = aga.next
    }
    return atot
  }
  if rv_is_strlit(pe) {
    push_str(sb, "  ebreak\n")
    return 2
  }
  emit_rv_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "  sd a0, ") ; push_int(sb, off) ; push_str(sb, "(s0)\n")
  return 1
}

## The POINTER-relative twin of `emit_rv_store_payload_at`: store the (possibly nested) aggregate value
## `pe` at `[<the address held at the TOP OF THE STACK> + off]`, returning the words written. The base
## address is re-loaded from `0(sp)` immediately before EVERY word store because the nested value emits
## clobber every scratch register (they are stack-BALANCED, so `0(sp)` still holds the base each time).
## This is what lets a whole-ELEMENT write `xs[i] = S(…)` deliver a NESTED struct / `[T; N]`-field
## literal at a RUNTIME index: the one-word-per-argument positional store it replaces dropped every word
## of an aggregate field past the first AND mis-aligned every field after it. For an ALL-SCALAR literal
## the emitted text is byte-identical to that positional store.
emit_rv_store_payload_atptr := fn(pe : ptr(Expr), off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  if rv_is_slit(pe) {
    sns := rv_slit_ns(pe)
    snl := rv_slit_nl(pe)
    mut g := ex_struct_lit_args(pe)
    mut o2 := off
    while g != 0 {
      ga := deref(arg_p(g))
      w := emit_rv_store_payload_atptr(ga.e, o2, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      o2 = o2 + w * 8
      g = ga.next
    }
    return i64(struct_words(decls, src, sns, snl, a))
  }
  if rv_is_elit(pe) {
    pens := rv_elit_ens(pe)
    penl := rv_elit_enl(pe)
    pvidx := variant_index(decls, src, pens, penl, rv_elit_vns(pe), rv_elit_vnl(pe), a)
    push_str(sb, "  li a0, ") ; push_int(sb, pvidx) ; push_str(sb, "\n  ld a1, 0(sp)\n  sd a0, ") ; push_int(sb, off) ; push_str(sb, "(a1)\n")
    mut g := ex_enum_lit_args(pe)
    mut wo := 1
    while g != 0 {
      ga := deref(arg_p(g))
      cw := emit_rv_store_payload_atptr(ga.e, off + wo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
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
      aw := emit_rv_store_payload_atptr(aga.e, ao, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      ao = ao + aw * 8
      atot = atot + aw
      ag = aga.next
    }
    return atot
  }
  if rv_is_strlit(pe) {
    ## a `str` element payload ({ptr,len}) needs its `.Lstr` rodata emitted — fail LOUD rather than
    ## store a dangling pointer. Reserve 2 words.
    push_str(sb, "  ebreak\n")
    return 2
  }
  emit_rv_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "  ld a1, 0(sp)\n  sd a0, ") ; push_int(sb, off) ; push_str(sb, "(a1)\n")
  return 1
}

emit_rv_enumval_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ens := rv_elit_ens(e)
  enl := rv_elit_enl(e)
  vidx := variant_index(decls, src, ens, enl, rv_elit_vns(e), rv_elit_vnl(e), a)
  words := 1 + i64(enum_max_arity(decls, src, ens, enl, a))
  ok := vidx >= 0 and (RV_AGG + words * 8) <= RV_AGG_LIM
  if ok {
    blk := RV_AGG
    RV_AGG = RV_AGG + words * 8
    push_str(sb, "  li a0, ") ; push_int(sb, vidx) ; push_str(sb, "\n  sd a0, ") ; push_int(sb, blk) ; push_str(sb, "(s0)\n")
    mut g := ex_enum_lit_args(e)
    mut wo := 1
    while g != 0 {
      ga := deref(arg_p(g))
      cw := emit_rv_store_payload_at(ga.e, blk + wo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      wo = wo + cw
      g = ga.next
    }
    push_str(sb, "  addi a0, s0, ") ; push_int(sb, blk) ; push_str(sb, "\n")
  }
  if not ok { push_str(sb, "  ebreak\n") }
}

## Deliver a struct VALUE `e` into the return registers word k → a_k (a0..a7) — the §8 register
## struct-return convention (piece 2). Handles a StructLit (push each field, pop reverse into a_k), a
## tail struct-returning CALL (the callee already delivered the regs), a struct Var LOCAL (read frame words
## → a_k) or struct PARAM (by-reference — its slot holds the base ptr, read through it). All-scalar, ≤8 words.
emit_rv_struct_value := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ## Tuple literals are ArrayLit nodes. Stage scalar components, then reverse-pop into a0..a6.
  if ex_is_array_lit(e) {
    nel := rv_alit_nel(e)
    if nel >= 1 and nel <= 7 {
      mut g := ex_array_lit_ehead(e)
      mut k := 0
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
        k = k + 1
        g = ga.next
      }
      mut j := k
      while j > 0 {
        j = j - 1
        push_str(sb, "  ld a") ; push_int(sb, j) ; push_str(sb, ", 0(sp)\n  addi sp, sp, 16\n")
      }
    }
    if nel < 1 or nel > 7 { push_str(sb, "  ebreak // unsupported tuple return width\n") }
    return
  }
  if rv_is_slit(e) {
    slns := rv_slit_ns(e)
    slnl := rv_slit_nl(e)
    ## an ALL-SCALAR struct literal: push each 1-word field, pop in REVERSE so word k → a_k (unchanged).
    if rv_struct_all_scalar(decls, src, slns, slnl, a) {
      mut g := ex_struct_lit_args(e)
      mut k := 0
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
        k += 1
        g = ga.next
      }
      mut j := k
      while j > 0 {
        j = j - 1
        push_str(sb, "  ld a") ; push_int(sb, j) ; push_str(sb, ", 0(sp)\n  addi sp, sp, 16\n")
      }
    }
    ## a struct literal WITH an aggregate field (an enum/str field): materialize the full {…} into an
    ## RV_AGG block by field (the multi-word writer), then load its words → a_k. Only ≤8 words reach here.
    if not rv_struct_all_scalar(decls, src, slns, slnl, a) {
      w := i64(struct_words(decls, src, slns, slnl, a))
      emit_rv_aggval_arg(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  mv t0, a0\n")
      mut k := 0
      while k < w { push_str(sb, "  ld a") ; push_int(sb, k) ; push_str(sb, ", ") ; push_int(sb, k * 8) ; push_str(sb, "(t0)\n") ; k = k + 1 }
    }
    return
  }
  crs := rv_call_ret_struct_span(e, decls, src, a)
  if crs.n != 0 {
    emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    return
  }
  ns := ex_var_ns(e)
  nl := ex_var_nl(e)
  mut done := false
  if nl != 0 {
    sns := rv_local_struct_ns(body_head, src, ns, nl, a)
    snl := rv_local_struct_nl(body_head, src, ns, nl, a)
    poff := rv_local_off(body_head, src, ns, nl, pcount, a, decls)
    if snl != 0 and poff >= 0 {
      w := i64(struct_words(decls, src, sns, snl, a))
      mut k := 0
      while k < w { push_str(sb, "  ld a") ; push_int(sb, k) ; push_str(sb, ", ") ; push_int(sb, poff + k * 8) ; push_str(sb, "(s0)\n") ; k = k + 1 }
      done = true
    }
    if not done {
      pidx := rv_param_find(params_head, src, ns, nl, a)
      psnl := rv_param_struct_nl(params_head, src, ns, nl, a, decls)
      if pidx >= 0 and psnl != 0 {
        psns := rv_param_struct_ns(params_head, src, ns, nl, a, decls)
        w := i64(struct_words(decls, src, psns, psnl, a))
        push_str(sb, "  ld t0, ") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "(s0)\n")
        mut k := 0
        while k < w { push_str(sb, "  ld a") ; push_int(sb, k) ; push_str(sb, ", ") ; push_int(sb, k * 8) ; push_str(sb, "(t0)\n") ; k = k + 1 }
        done = true
      }
    }
  }
  if not done { push_str(sb, "  ebreak\n") }
}

## Deliver a WIDE-struct return VALUE `e` THROUGH the LP64 indirect-result pointer (the caller-supplied
## destination, spilled at RV_SRET_SLOT). Three shapes: an ALL-SCALAR struct LITERAL (evaluate each field,
## store it at its word offset — the pointer is RELOADED per field because the field expression may clobber
## scratch), a struct LOCAL (word-copy its frame slots), and a by-reference struct PARAM (word-copy through
## its slot pointer). Anything else is a LOUD `ebreak` (never a silent partial write). LP64 also returns the
## destination pointer in a0, so the epilogue leaves it there.
emit_rv_sret_store := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ns := ex_var_ns(e)
  nl := ex_var_nl(e)
  ## WIDE-ENUM SRET (> 8 words): the fn's return type is an ENUM (RV_RET_SRET names it — distinguished from
  ## the wide-STRUCT case by enum_decl_of), so deliver its {disc, payload…} block through the LP64 indirect
  ## result. The destination pointer is reloaded into t1 from RV_SRET_SLOT; t0 is the copy scratch. Three
  ## shapes: `return v` (an enum LOCAL — word-copy its frame slots), `return E.V(payload…)` (materialize the
  ## literal into the RV_ENUM_SRET_BLK scratch via the shared multi-word writer, THEN word-copy — the writer
  ## clobbers a0/t0/t1, so the destination is reloaded after it), and `return mk(…)` (TAIL-FORWARD: hand the
  ## inner wide-enum callee our OWN destination pointer via the INDIRECT one-shot, so it writes straight into
  ## the outer caller's block). Anything else is a LOUD `ebreak`, never a silent partial write. Taken FIRST
  ## because struct_words below would not resolve an enum type name.
  if enum_decl_of(decls, src, RV_RET_SRET_NS, RV_RET_SRET_NL) >= 0 {
    eslot := RV_SRET_SLOT
    ew := 1 + i64(enum_max_arity(decls, src, RV_RET_SRET_NS, RV_RET_SRET_NL, a))
    mut edone := false
    if nl != 0 {
      lenl := rv_local_enum_nl(body_head, src, ns, nl, a)
      loff := rv_local_off(body_head, src, ns, nl, pcount, a, decls)
      if lenl != 0 and loff >= 0 {
        push_str(sb, "  ld t1, ") ; push_int(sb, eslot) ; push_str(sb, "(s0)\n")
        mut ek := 0
        while ek < ew { push_str(sb, "  ld t0, ") ; push_int(sb, loff + ek * 8) ; push_str(sb, "(s0)\n  sd t0, ") ; push_int(sb, ek * 8) ; push_str(sb, "(t1)\n") ; ek = ek + 1 }
        edone = true
      }
    }
    if (not edone) and rv_is_elit(e) {
      eblk := RV_ENUM_SRET_BLK
      evidx := variant_index(decls, src, rv_elit_ens(e), rv_elit_enl(e), rv_elit_vns(e), rv_elit_vnl(e), a)
      push_str(sb, "  li a0, ") ; push_int(sb, evidx) ; push_str(sb, "\n  sd a0, ") ; push_int(sb, eblk) ; push_str(sb, "(s0)\n")
      mut eg := ex_enum_lit_args(e)
      mut ewo := 1
      while eg != 0 {
        ega := deref(arg_p(eg))
        ecw := emit_rv_store_payload_at(ega.e, eblk + ewo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        ewo = ewo + ecw
        eg = ega.next
      }
      push_str(sb, "  ld t1, ") ; push_int(sb, eslot) ; push_str(sb, "(s0)\n")
      mut eq := 0
      while eq < ew { push_str(sb, "  ld t0, ") ; push_int(sb, eblk + eq * 8) ; push_str(sb, "(s0)\n  sd t0, ") ; push_int(sb, eq * 8) ; push_str(sb, "(t1)\n") ; eq = eq + 1 }
      edone = true
    }
    if not edone {
      ers := rv_call_ret_enum_sret_span(e, decls, src, a)
      if ers.n != 0 {
        eon := RV_SRET_DST_ON
        eof := RV_SRET_DST
        eid := RV_SRET_DST_IND
        RV_SRET_DST_ON = true
        RV_SRET_DST = eslot
        RV_SRET_DST_IND = true
        emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        RV_SRET_DST_ON = eon
        RV_SRET_DST = eof
        RV_SRET_DST_IND = eid
        edone = true
      }
    }
    if not edone { push_str(sb, "  ebreak\n") }
    ## LP64 also returns the destination pointer in a0.
    if edone { push_str(sb, "  ld a0, ") ; push_int(sb, eslot) ; push_str(sb, "(s0)\n") }
    return
  }
  w := i64(struct_words(decls, src, RV_RET_SRET_NS, RV_RET_SRET_NL, a))
  slot := RV_SRET_SLOT
  mut done := false
  if rv_is_slit(e) {
    if rv_struct_all_scalar(decls, src, rv_slit_ns(e), rv_slit_nl(e), a) {
      mut g := ex_struct_lit_args(e)
      mut k := 0
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  ld t1, ") ; push_int(sb, slot) ; push_str(sb, "(s0)\n  sd a0, ") ; push_int(sb, k * 8) ; push_str(sb, "(t1)\n")
        k = k + 1
        g = ga.next
      }
      done = true
    }
  }
  if (not done) and nl != 0 {
    snl := rv_local_struct_nl(body_head, src, ns, nl, a)
    poff := rv_local_off(body_head, src, ns, nl, pcount, a, decls)
    if snl != 0 and poff >= 0 {
      push_str(sb, "  ld t1, ") ; push_int(sb, slot) ; push_str(sb, "(s0)\n")
      mut k := 0
      while k < w { push_str(sb, "  ld t0, ") ; push_int(sb, poff + k * 8) ; push_str(sb, "(s0)\n  sd t0, ") ; push_int(sb, k * 8) ; push_str(sb, "(t1)\n") ; k = k + 1 }
      done = true
    }
    if not done {
      pidx := rv_param_find(params_head, src, ns, nl, a)
      psnl := rv_param_struct_nl(params_head, src, ns, nl, a, decls)
      if pidx >= 0 and psnl != 0 {
        push_str(sb, "  ld t1, ") ; push_int(sb, slot) ; push_str(sb, "(s0)\n  ld t2, ") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "(s0)\n")
        mut k := 0
        while k < w { push_str(sb, "  ld t0, ") ; push_int(sb, k * 8) ; push_str(sb, "(t2)\n  sd t0, ") ; push_int(sb, k * 8) ; push_str(sb, "(t1)\n") ; k = k + 1 }
        done = true
      }
    }
  }
  ## `return mk(…)` — SRET TAIL-FORWARD: the return VALUE is itself a call to a wide-struct-returning fn, so
  ## BOTH sides deliver through the LP64 indirect result. Rather than stage the inner result in a scratch
  ## block and copy it through our own destination, hand the INNER call our OWN destination pointer: the
  ## one-shot RV_SRET_DST hand-off in its INDIRECT flavour makes the call arm emit `ld a0, <slot>(s0)` (our
  ## spilled incoming pointer) right before the `call`, so the callee writes straight into the outer caller's
  ## block. Nothing is copied afterwards and no extra frame block is reserved.
  if not done {
    frs := rv_call_ret_sret_span(e, decls, src, a)
    if frs.n != 0 {
      son := RV_SRET_DST_ON
      sof := RV_SRET_DST
      sid := RV_SRET_DST_IND
      RV_SRET_DST_ON = true
      RV_SRET_DST = slot
      RV_SRET_DST_IND = true
      emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      RV_SRET_DST_ON = son
      RV_SRET_DST = sof
      RV_SRET_DST_IND = sid
      done = true
    }
  }
  if not done { push_str(sb, "  ebreak\n") }
  if done { push_str(sb, "  ld a0, ") ; push_int(sb, slot) ; push_str(sb, "(s0)\n") }
}

## Deliver an ENUM VALUE `e` into the return registers word 0 = disc, word k+1 = payload → a_k (§8 piece 3).
## Handles an EnumLit (push disc + payload, pop reverse into a_k), a tail enum-returning CALL, and an enum
## Var LOCAL / by-reference PARAM. A narrow variant leaves unused high regs uninitialized (never read). ≤8 words.
emit_rv_enum_value := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  if rv_is_elit(e) {
    vidx := variant_index(decls, src, rv_elit_ens(e), rv_elit_enl(e), rv_elit_vns(e), rv_elit_vnl(e), a)
    push_str(sb, "  li a0, ") ; push_int(sb, vidx) ; push_str(sb, "\n  addi sp, sp, -16\n  sd a0, 0(sp)\n")
    mut g := ex_enum_lit_args(e)
    mut k := 1
    while g != 0 {
      ga := deref(arg_p(g))
      emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
      k = k + 1
      g = ga.next
    }
    mut j := k
    while j > 0 {
      j = j - 1
      push_str(sb, "  ld a") ; push_int(sb, j) ; push_str(sb, ", 0(sp)\n  addi sp, sp, 16\n")
    }
    return
  }
  cre := rv_call_ret_enum_span(e, decls, src, a)
  if cre.n != 0 {
    emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    return
  }
  ns := ex_var_ns(e)
  nl := ex_var_nl(e)
  mut done := false
  if nl != 0 {
    lens := rv_local_enum_ns(body_head, src, ns, nl, a)
    lenl := rv_local_enum_nl(body_head, src, ns, nl, a)
    loff := rv_local_off(body_head, src, ns, nl, pcount, a, decls)
    if lenl != 0 and loff >= 0 {
      w := 1 + i64(enum_max_arity(decls, src, lens, lenl, a))
      mut k := 0
      while k < w { push_str(sb, "  ld a") ; push_int(sb, k) ; push_str(sb, ", ") ; push_int(sb, loff + k * 8) ; push_str(sb, "(s0)\n") ; k = k + 1 }
      done = true
    }
    if not done {
      pidx := rv_param_find(params_head, src, ns, nl, a)
      penl := rv_param_enum_nl(params_head, src, ns, nl, decls)
      if pidx >= 0 and penl != 0 {
        pens := rv_param_enum_ns(params_head, src, ns, nl, decls)
        w := 1 + i64(enum_max_arity(decls, src, pens, penl, a))
        push_str(sb, "  ld t0, ") ; push_int(sb, 16 + pidx * 8) ; push_str(sb, "(s0)\n")
        mut k := 0
        while k < w { push_str(sb, "  ld a") ; push_int(sb, k) ; push_str(sb, ", ") ; push_int(sb, k * 8) ; push_str(sb, "(t0)\n") ; k = k + 1 }
        done = true
      }
    }
  }
  if not done { push_str(sb, "  ebreak\n") }
}

## Materialize a struct-RETURNING CALL `f(…)` passed as a call ARGUMENT into a reserved RV_AGG block and
## leave the block ADDRESS in a0 (by-reference aggregate-argument convention, §8 piece 2). The callee
## delivers word k in a_k; store them into the block, then hand its address by reference.
emit_rv_callret_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  crs := rv_call_ret_struct_span(e, decls, src, a)
  words := i64(struct_words(decls, src, crs.s, crs.n, a))
  ok := crs.n != 0 and (RV_AGG + words * 8) <= RV_AGG_LIM
  if ok {
    blk := RV_AGG
    emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    mut k := 0
    while k < words { push_str(sb, "  sd a") ; push_int(sb, k) ; push_str(sb, ", ") ; push_int(sb, blk + k * 8) ; push_str(sb, "(s0)\n") ; k = k + 1 }
    push_str(sb, "  addi a0, s0, ") ; push_int(sb, blk) ; push_str(sb, "\n")
    RV_AGG = RV_AGG + words * 8
  }
  if not ok { push_str(sb, "  ebreak\n") }
}
## Materialize an enum-RETURNING CALL `f(…)` passed as a call ARGUMENT into a reserved RV_AGG block (§8
## piece 3): the callee delivers word 0 = disc, word k+1 = payload in a0.., stored to the block (full enum
## width), whose address is passed by reference.
emit_rv_enumret_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  cre := rv_call_ret_enum_span(e, decls, src, a)
  words := 1 + i64(enum_max_arity(decls, src, cre.s, cre.n, a))
  ok := cre.n != 0 and (RV_AGG + words * 8) <= RV_AGG_LIM
  if ok {
    blk := RV_AGG
    emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    mut k := 0
    while k < words { push_str(sb, "  sd a") ; push_int(sb, k) ; push_str(sb, ", ") ; push_int(sb, blk + k * 8) ; push_str(sb, "(s0)\n") ; k = k + 1 }
    push_str(sb, "  addi a0, s0, ") ; push_int(sb, blk) ; push_str(sb, "\n")
    RV_AGG = RV_AGG + words * 8
  }
  if not ok { push_str(sb, "  ebreak\n") }
}

## Materialize a WIDE (SRET) struct-returning CALL `f(…)` passed as a call ARGUMENT into a reserved RV_AGG
## block and leave the block ADDRESS in a0 (LP64 indirect result, argument position). Unlike the 1..8-word
## register struct-return there are no result registers to store from: the callee writes the whole struct
## through the a0 result pointer, and in argument position there is NO destination local to point it at. So
## reserve the block FIRST, hand its base down as the callee's a0 (the RV_SRET_DST one-shot, saved and
## restored so a NESTED / SIBLING wide-returning argument allocates its own DISTINCT block), then pass that
## same block by reference — the aggregate-parameter ABI. Was a fail-loud `ebreak` (no destination in scope).
emit_rv_sretcall_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  srs := rv_call_ret_sret_span(e, decls, src, a)
  words := i64(struct_words(decls, src, srs.s, srs.n, a))
  ok := srs.n != 0 and (RV_AGG + words * 8) <= RV_AGG_LIM
  if ok {
    blk := RV_AGG
    RV_AGG = RV_AGG + words * 8
    son := RV_SRET_DST_ON
    sof := RV_SRET_DST
    sid := RV_SRET_DST_IND
    RV_SRET_DST_ON = true
    RV_SRET_DST = blk
    RV_SRET_DST_IND = false
    emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    RV_SRET_DST_ON = son
    RV_SRET_DST = sof
    RV_SRET_DST_IND = sid
    push_str(sb, "  addi a0, s0, ") ; push_int(sb, blk) ; push_str(sb, "\n")
  }
  if not ok { push_str(sb, "  ebreak\n") }
}

## The wide-ENUM analogue of emit_rv_sretcall_arg (> 8 words): an enum-returning CALL wider than the
## 8-register budget also delivers through the LP64 indirect result, so in ARGUMENT position it needs the
## same reserved block + a0 hand-off + by-reference pass (the callee's enum param slot takes a POINTER to
## the {disc, payload…} block). Without it the call fell to the `sretcall and (not mysret)` fail-loud path.
emit_rv_enumsret_arg := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ers := rv_call_ret_enum_sret_span(e, decls, src, a)
  words := 1 + i64(enum_max_arity(decls, src, ers.s, ers.n, a))
  ok := ers.n != 0 and (RV_AGG + words * 8) <= RV_AGG_LIM
  if ok {
    blk := RV_AGG
    RV_AGG = RV_AGG + words * 8
    son := RV_SRET_DST_ON
    sof := RV_SRET_DST
    sid := RV_SRET_DST_IND
    RV_SRET_DST_ON = true
    RV_SRET_DST = blk
    RV_SRET_DST_IND = false
    emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    RV_SRET_DST_ON = son
    RV_SRET_DST = sof
    RV_SRET_DST_IND = sid
    push_str(sb, "  addi a0, s0, ") ; push_int(sb, blk) ; push_str(sb, "\n")
  }
  if not ok { push_str(sb, "  ebreak\n") }
}

## Emit a WIDE-SRET call used as a bare statement. The value is intentionally discarded, but the ABI still
## requires a valid destination pointer; reserve a frame block and reuse the same one-shot hand-off as an
## SRET call argument. This also covers generic `-> T` calls after their concrete type has been resolved.
emit_rv_sret_discard := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  srs := rv_call_ret_sret_span(e, decls, src, a)
  ers := rv_call_ret_enum_sret_span(e, decls, src, a)
  mut words := i64(0)
  if srs.n != 0 { words = i64(struct_words(decls, src, srs.s, srs.n, a)) }
  if srs.n == 0 and ers.n != 0 { words = 1 + i64(enum_max_arity(decls, src, ers.s, ers.n, a)) }
  ok := words > 0 and (RV_AGG + words * 8) <= RV_AGG_LIM
  if ok {
    blk := RV_AGG
    RV_AGG = RV_AGG + words * 8
    son := RV_SRET_DST_ON
    sof := RV_SRET_DST
    sid := RV_SRET_DST_IND
    RV_SRET_DST_ON = true
    RV_SRET_DST = blk
    RV_SRET_DST_IND = false
    emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    RV_SRET_DST_ON = son
    RV_SRET_DST = sof
    RV_SRET_DST_IND = sid
  }
  if not ok { push_str(sb, "  ebreak\n") }
}

emit_rv_epilogue := fn(frame : i64, in out sb : rt::StrBuf) {
  ## a float-returning fn delivers its result in fa0: move the value bits (a0) into fa0 before ret.
  if RV_RET_FLOAT { push_str(sb, "  fmv.d.x fa0, a0\n") }
  push_str(sb, "  mv sp, s0\n")
  push_str(sb, "  ld ra, 8(sp)\n  ld s0, 0(sp)\n")
  push_str(sb, "  addi sp, sp, ") ; push_int(sb, frame) ; push_str(sb, "\n")
  push_str(sb, "  ret\n")
}

emit_rv_stmts := fn(list_head : usize, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), frame : i64, bind_head : ptr(mut Bind), bind_base : i64) {
  mut s := list_head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        ## FLAT: a StructLit constructs fields; an EnumLit constructs {disc, payload…}; else scalar store.
        isslit := rv_is_slit(v)
        iselit := rv_is_elit(v)
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
          csl := rv_local_struct_nl(body_head, src, vcns, vcnl, a)
          if csl != 0 { copyw = i64(struct_words(decls, src, rv_local_struct_ns(body_head, src, vcns, vcnl, a), csl, a)) }
          cel := rv_local_enum_nl(body_head, src, vcns, vcnl, a)
          if copyw == 0 and cel != 0 { copyw = 1 + i64(enum_max_arity(decls, src, rv_local_enum_ns(body_head, src, vcns, vcnl, a), cel, a)) }
          if copyw > 0 { soff = rv_local_off(body_head, src, vcns, vcnl, pcount, a, decls) }
        }
        ## a standard-byte aggregate field copy `q := p.inner`: copy the leaf struct's words from its
        ## containing local at the cumulative byte offset. The standard tier only reuses word-copy when
        ## that byte offset is word-aligned; an unaligned aggregate remains fail-loud.
        ## CLAYOUT S3(b) — AND the child must be WORD-GRANULAR: this is a whole-WORD copy into a
        ## destination local that is read back at WORD offsets, so a byte-precise sub-word child (now
        ## constructible) would be silently mis-copied. Measured without the guard: exit 1 where the
        ## pre-S3(b) compiler trapped. A located `ebreak` until the byte-precise copier lands (I11).
        ## CLAYOUT S3(c) — AND WHEN IT IS NOT WORD-GRANULAR, THE BYTE-PRECISE COPIER TAKES IT.
        ## `stdbc` switches the copy LOOP below from words to the shared plan, so every `(not iscopy)`
        ## guard in this arm keeps working (the source place must not be evaluated as a value — the
        ## expression emitter has no aggregate-field load and would emit an `ebreak`). Only a child
        ## OUTSIDE the copier's domain is still a located `ebreak`.
        mut stdbc := false
        mut stdbcts := 0
        mut stdbctl := 0
        if ex_is_field(v) {
          sfp := rv_std_path_ty(v, body_head, src, a, decls)
          if rv_std_path_ok(v, body_head, src, a, decls) and sfp.n != 0 {
            sbn := base_type_name(src, sfp.s, sfp.n)
            wgokC := std_struct_is_word_granular(decls, src, sfp.s, sfp.n, a)
            if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 and wgokC {
              srootC := rv_std_path_root_off(v, body_head, src, pcount, a, decls)
              sboC := rv_std_path_bo(v, body_head, src, a, decls)
              if srootC >= 0 and sboC >= 0 and ((srootC + sboC) % 8) == 0 {
                copyw = i64(struct_words(decls, src, sbn.s, sbn.n, a))
                soff = srootC + sboC
              }
            }
            mut bckC := 0
            if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 and (not wgokC) { bckC = std_copy_kind(decls, src, sfp.s, sfp.n, a) }
            if bckC != 0 {
              srootB := rv_std_path_root_off(v, body_head, src, pcount, a, decls)
              sboB := rv_std_path_bo(v, body_head, src, a, decls)
              if srootB >= 0 and sboB >= 0 {
                copyw = i64(struct_words(decls, src, sfp.s, sfp.n, a))
                soff = srootB + sboB
                stdbc = copyw > 0
                stdbcts = sfp.s
                stdbctl = sfp.n
              }
            }
            if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 and (not wgokC) and (not stdbc) { push_str(sb, "  ebreak # standard byte-layout aggregate field extract outside the byte-precise copier's domain\n") }
          }
        }
        iscopy := copyw > 0 and soff >= 0
        ## a local bound to a struct-RETURNING CALL `p := mk()` (§8 piece 2): store all returned words.
        crs := rv_call_ret_struct_span(v, decls, src, a)
        iscr := crs.n != 0
        ## a local bound to an enum-RETURNING CALL `m := id(…)` (§8 piece 3): store the full enum width.
        cre := rv_call_ret_enum_span(v, decls, src, a)
        iscre := cre.n != 0
        ## a local bound to a WIDE-struct-returning CALL `s := mk(…)` (LP64 indirect result): the local's own
        ## frame slots ARE the destination — hand their address to the call, which writes the struct in place.
        crt := rv_call_ret_sret_span(v, decls, src, a)
        issret := crt.n != 0
        ## a local bound to a WIDE-ENUM-returning CALL `m := mk(…)` (> 8 words, LP64 indirect result): the
        ## local's own frame slots ARE the destination — hand their address to the call and the callee writes
        ## the whole {disc, payload…} block in place. Disjoint from iscre (the ≤8-word register gate).
        cres := rv_call_ret_enum_sret_span(v, decls, src, a)
        isenumsret := cres.n != 0
        ## a whole-ELEMENT copy `x := xs[i]` out of an array of scalar-only structs (a LOCAL array-lit or
        ## an array GLOBAL). The element is `eixw` words wide at base + i*eixw*8; x's own slots (sized to
        ## the same width by `rv_val_words`) receive the copy. 0 = not this shape (a scalar `x := xs[i]`
        ## over a scalar array keeps the ordinary one-word store).
        eixp := rv_index_elem_struct_span(v, src, a, decls)
        mut eixw := i64(0)
        mut eixbyte := false
        mut eixla := false
        mut eixga := false
        mut eixoff := i64(0) - 1
        mut eixnel := i64(0)
        if eixp.n != 0 {
          eibx := ex_index_base(v)
          eins := ex_var_ns(eibx)
          einl := ex_var_nl(eibx)
          eixla = rv_is_array_local(body_head, src, eins, einl, a)
          eixga = (not eixla) and rv_is_array_global(decls, src, eins, einl)
          if eixla { eixoff = rv_local_off(body_head, src, eins, einl, pcount, a, decls) ; eixnel = rv_array_nel(body_head, src, eins, einl, a) }
          if eixga { eixnel = rv_alit_nel(rv_global_value(decls, src, eins, einl)) }
          if (eixla and eixoff >= 0) or eixga {
            if std_array_elem_byte_tier(decls, src, eixp.s, eixp.n, a) { eixw = i64(array_elem_word_reservation(decls, src, eixp.s, eixp.n, a)) ; eixbyte = true }
            if not std_array_elem_byte_tier(decls, src, eixp.s, eixp.n, a) { eixw = i64(struct_words(decls, src, eixp.s, eixp.n, a)) }
          }
        }
        iseix := eixw > 0
        isagg := isslit or iselit or isalit or isslice
        if (not isagg) and (not iscr) and (not iscre) and (not issret) and (not isenumsret) and (not iscopy) and (not iseix) {
          if rv_direct_float_num(v, src, ns, nl) {
            emit_rv_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  fcvt.d") ; push_str(sb, ".l ft0, a0\n  fmv.x.d a0, ft0\n")
          } else { emit_rv_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        }
        pidx := rv_param_find(params_head, src, ns, nl, a)
        isglob := rv_is_global(decls, src, ns, nl, a)
        poff := rv_local_off(body_head, src, ns, nl, pcount, a, decls)
        mut voff := poff
        if pidx >= 0 { voff = 16 + pidx * 8 }
        mut outscalar := false
        if pidx >= 0 { if rv_param_out_scalar(params_head, src, decls, pidx) { outscalar = true } }
        useframe := (not isagg) and (not iscr) and (not iscre) and (not issret) and (not isenumsret) and (not iscopy) and (not iseix) and (not outscalar) and ((pidx >= 0) or (voff >= 0 and (not isglob)))
        gname := str_at((src + ns), nl)
        if outscalar { push_str(sb, "  ld t0, ") ; push_int(sb, voff) ; push_str(sb, "(s0)\n  sd a0, 0(t0)\n") }
        if useframe { push_str(sb, "  sd a0, ") ; push_int(sb, voff) ; push_str(sb, "(s0)\n") }
        ## agg-var copy: word-copy p's slots (soff) into q's slots (poff). Only when q has a frame home.
        if iscopy and poff >= 0 and (not stdbc) {
          mut cwk := i64(0)
          while cwk < copyw { push_str(sb, "  ld a0, ") ; push_int(sb, soff + cwk * 8) ; push_str(sb, "(s0)\n  sd a0, ") ; push_int(sb, poff + cwk * 8) ; push_str(sb, "(s0)\n") ; cwk = cwk + 1 }
        }
        ## CLAYOUT S3(c): the same copy, but byte-precise — the child's §6.1 image at `soff` into the
        ## destination's own tier at `poff`, per the shared plan.
        if iscopy and poff >= 0 and stdbc { rv_std_copy(stdbcts, stdbctl, soff, poff, sb, decls, src, a) }
        if iscopy and poff < 0 { push_str(sb, "  ebreak\n") }
        ## element copy: index → a0, scale by the element width, add the frame/label base into a2, then
        ## word-copy the element into x's slots. a2 survives the copy (no emit call in the loop).
        if iseix and poff >= 0 {
          emit_rv_expr(ex_index_idx(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if RV_CHK {
            if eixnel > 0 { push_str(sb, "  li a1, ") ; push_int(sb, eixnel) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
          }
          if eixbyte {
            push_str(sb, "  li a1, ") ; push_int(sb, i64(layout_elem_stride_bytes(decls, src, eixp.s, eixp.n, a))) ; push_str(sb, "\n  mul a0, a0, a1\n")
            if eixla { push_str(sb, "  add a2, a0, s0\n  addi a2, a2, ") ; push_int(sb, eixoff) ; push_str(sb, "\n") }
            if eixga { push_str(sb, "  la a2, ") ; push_str(sb, str_at((src + ex_var_ns(ex_index_base(v))), ex_var_nl(ex_index_base(v)))) ; push_str(sb, "\n  add a2, a2, a0\n") }
            nbix := i64(std_copy_image_bytes(decls, src, eixp.s, eixp.n, a))
            mut eckb := i64(0)
            while eckb < nbix {
              push_str(sb, "  lbu a0, ") ; push_int(sb, eckb) ; push_str(sb, "(a2)\n  sb a0, ") ; push_int(sb, poff + eckb) ; push_str(sb, "(s0)\n")
              eckb = eckb + 1
            }
          }
          if not eixbyte {
            push_str(sb, "  li a1, ") ; push_int(sb, eixw * 8) ; push_str(sb, "\n  mul a0, a0, a1\n")
            if eixla { push_str(sb, "  add a2, a0, s0\n  addi a2, a2, ") ; push_int(sb, eixoff) ; push_str(sb, "\n") }
            if eixga { push_str(sb, "  la a2, ") ; push_str(sb, str_at((src + ex_var_ns(ex_index_base(v))), ex_var_nl(ex_index_base(v)))) ; push_str(sb, "\n  add a2, a2, a0\n") }
            mut eck := i64(0)
            while eck < eixw {
              push_str(sb, "  ld a0, ") ; push_int(sb, eck * 8) ; push_str(sb, "(a2)\n  sd a0, ") ; push_int(sb, poff + eck * 8) ; push_str(sb, "(s0)\n")
              eck = eck + 1
            }
          }
        }
        if iseix and poff < 0 { push_str(sb, "  ebreak\n") }
        if (not isagg) and (not iscr) and (not iscre) and (not issret) and (not isenumsret) and (not iscopy) and (not iseix) and (not outscalar) and (not useframe) and isglob {
          push_str(sb, "  la t0, ") ; push_str(sb, gname) ; push_str(sb, "\n  sd a0, 0(t0)\n")
        }
        if (not isagg) and (not iscr) and (not iscre) and (not issret) and (not isenumsret) and (not iscopy) and (not iseix) and (not outscalar) and (not useframe) and (not isglob) { push_str(sb, "  ebreak\n") }
        ## WIDE-struct (SRET) bind: point the call at the local's slots (a0 = s0 + poff) and let the callee
        ## write the struct straight into them — no post-call word copy.
        if issret {
          if poff >= 0 {
            son := RV_SRET_DST_ON
            sof := RV_SRET_DST
            RV_SRET_DST_ON = true
            RV_SRET_DST = poff
            emit_rv_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            RV_SRET_DST_ON = son
            RV_SRET_DST = sof
          }
          if poff < 0 { push_str(sb, "  ebreak\n") }
        }
        ## WIDE-ENUM (SRET) bind `m := mk(…)`: identical a0 hand-off — set the one-shot destination (m's
        ## frame offset), emit the call (the call arm turns it into `addi a0, s0, <poff>` before the `call`),
        ## and the callee writes the whole {disc, payload…} block into m's slots (nothing to store after).
        ## A global / unresolved destination would need a temp → fail loud.
        if isenumsret {
          if poff >= 0 {
            eon := RV_SRET_DST_ON
            eof := RV_SRET_DST
            RV_SRET_DST_ON = true
            RV_SRET_DST = poff
            emit_rv_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            RV_SRET_DST_ON = eon
            RV_SRET_DST = eof
          }
          if poff < 0 { push_str(sb, "  ebreak\n") }
        }
        ## struct-returning-call bind: emit the call (delivers a0..a_(w-1)), store each word to p's slot.
        if iscr {
          mut crw := i64(struct_words(decls, src, crs.s, crs.n, a))
          if str_at((src + crs.s), 1) == "(" { crw = rv_tuple_words(src, crs.s, crs.n) }
          if poff >= 0 {
            emit_rv_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            mut ck := 0
            while ck < crw { push_str(sb, "  sd a") ; push_int(sb, ck) ; push_str(sb, ", ") ; push_int(sb, poff + ck * 8) ; push_str(sb, "(s0)\n") ; ck = ck + 1 }
          }
          if poff < 0 { push_str(sb, "  ebreak\n") }
        }
        ## enum-returning-call bind: emit the call (word 0 = disc, word k+1 = payload), store full width.
        if iscre {
          crew := 1 + i64(enum_max_arity(decls, src, cre.s, cre.n, a))
          if poff >= 0 {
            emit_rv_expr(v, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            mut ck := 0
            while ck < crew { push_str(sb, "  sd a") ; push_int(sb, ck) ; push_str(sb, ", ") ; push_int(sb, poff + ck * 8) ; push_str(sb, "(s0)\n") ; ck = ck + 1 }
          }
          if poff < 0 { push_str(sb, "  ebreak\n") }
        }
        stys := rv_slit_ns(v)
        styn := rv_slit_nl(v)
        slitstd := isslit and poff >= 0 and layout_kind_is_byte(layout_kind(decls, src, stys, styn, a))
        if slitstd { _stdw := rv_std_store_struct(v, poff, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        slitok := isslit and (not slitstd) and poff >= 0 and rv_struct_all_scalar(decls, src, stys, styn, a)
        if slitok {
          mut g := ex_struct_lit_args(v)
          mut k := 0
          while g != 0 {
            ga := deref(arg_p(g))
            emit_rv_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  sd a0, ") ; push_int(sb, poff + k * 8) ; push_str(sb, "(s0)\n")
            k += 1
            g = ga.next
          }
        }
        ## a NESTED struct literal (a field is itself a struct/enum — not all-scalar): materialize the full
        ## FLATTENED value into p's frame slots by writing each field at its RUNNING byte offset via the
        ## recursive multi-word writer. Disjoint from slitok. Only for a real struct decl.
        slitnest := isslit and (not slitok) and (not slitstd) and poff >= 0 and struct_decl_of(decls, src, stys, styn) >= 0
        if slitnest {
          mut sg := ex_struct_lit_args(v)
          mut soff := poff
          while sg != 0 {
            sga := deref(arg_p(sg))
            sw := emit_rv_store_payload_at(sga.e, soff, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            soff = soff + sw * 8
            sg = sga.next
          }
        }
        if isslit and (not slitok) and (not slitstd) and (not slitnest) { push_str(sb, "  ebreak\n") }
        vidx := variant_index(decls, src, rv_elit_ens(v), rv_elit_enl(v), rv_elit_vns(v), rv_elit_vnl(v), a)
        ## enum local construct `s := E.V(p…)`: disc at word 0, then each payload arg via the shared
        ## multi-word writer (scalar / struct / nested-enum payloads — §8 piece 3b; str stays loud).
        elitok := iselit and poff >= 0 and vidx >= 0
        if elitok {
          push_str(sb, "  li a0, ") ; push_int(sb, vidx) ; push_str(sb, "\n  sd a0, ") ; push_int(sb, poff) ; push_str(sb, "(s0)\n")
          mut eg := ex_enum_lit_args(v)
          mut ewo := 1
          while eg != 0 {
            ega := deref(arg_p(eg))
            ecw := emit_rv_store_payload_at(ega.e, poff + ewo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            ewo = ewo + ecw
            eg = ega.next
          }
        }
        if iselit and (not elitok) { push_str(sb, "  ebreak\n") }
        ## array construct `a := [e0,…]`: store each element at base + k*estride*8. A SCALAR element
        ## (estride 1) is one word; a STRUCT element (a StructLit, estride = struct_words) stores each
        ## positional field at base + (k*estride + fk)*8 (the aggregate-array layout — x86's stride).
        alitok := isalit and poff >= 0
        mut alitbyte := false
        if alitok {
          ag0 := ex_array_lit_ehead(v)
          if ag0 != 0 {
            aga0 := deref(arg_p(ag0))
            if rv_is_slit(aga0.e) and std_array_elem_byte_tier(decls, src, rv_slit_ns(aga0.e), rv_slit_nl(aga0.e), a) {
              alitbyte = true
              astrideB := i64(layout_elem_stride_bytes(decls, src, rv_slit_ns(aga0.e), rv_slit_nl(aga0.e), a))
              mut abg := ag0
              mut abo := poff
              while abg != 0 {
                abga := deref(arg_p(abg))
                if rv_is_slit(abga.e) { _abs := rv_std_store_struct(abga.e, abo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
                if not rv_is_slit(abga.e) { push_str(sb, "  ebreak # mixed byte-tier array literal\n") }
                abo = abo + astrideB
                abg = abga.next
              }
            }
          }
        }
        if alitok and (not alitbyte) {
          estrideA := rv_alit_stride(v, src, a, decls)
          mut ag := ex_array_lit_ehead(v)
          mut ak := 0
          while ag != 0 {
            aga := deref(arg_p(ag))
            if rv_is_slit(aga.e) {
              mut fg := ex_struct_lit_args(aga.e)
              mut fk := 0
              while fg != 0 {
                fga := deref(arg_p(fg))
                emit_rv_expr(fga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
                push_str(sb, "  sd a0, ") ; push_int(sb, poff + (ak * estrideA + fk) * 8) ; push_str(sb, "(s0)\n")
                fk += 1
                fg = fga.next
              }
            }
            if rv_is_elit(aga.e) {
              evx := variant_index(decls, src, rv_elit_ens(aga.e), rv_elit_enl(aga.e), rv_elit_vns(aga.e), rv_elit_vnl(aga.e), a)
              push_str(sb, "  li a0, ") ; push_int(sb, evx) ; push_str(sb, "\n  sd a0, ") ; push_int(sb, poff + ak * estrideA * 8) ; push_str(sb, "(s0)\n")
              mut pg := ex_enum_lit_args(aga.e)
              mut pk := 1
              while pg != 0 {
                pga := deref(arg_p(pg))
                emit_rv_expr(pga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
                push_str(sb, "  sd a0, ") ; push_int(sb, poff + (ak * estrideA + pk) * 8) ; push_str(sb, "(s0)\n")
                pk += 1
                pg = pga.next
              }
            }
            if (not rv_is_slit(aga.e)) and (not rv_is_elit(aga.e)) {
              emit_rv_expr(aga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
              push_str(sb, "  sd a0, ") ; push_int(sb, poff + ak * estrideA * 8) ; push_str(sb, "(s0)\n")
            }
            ak += 1
            ag = aga.next
          }
        }
        if isalit and (not alitok) { push_str(sb, "  ebreak\n") }
        ## range-slice binding `s := base[lo..hi]` — store a 2-word {ptr, len} view (word0 = &base[lo] =
        ## s0 + base-array byte-off + lo*8; word1 = hi - lo). Bounds re-evaluated per use (pure). Only a
        ## scalar frame-array base (`aoff >= 0`) is supported; anything else is fail-loud.
        if isslice {
          sbase := ex_slice_base(v)
          bns := ex_var_ns(sbase)
          bnl := ex_var_nl(sbase)
          aoff := rv_local_off(body_head, src, bns, bnl, pcount, a, decls)
          sliceok := poff >= 0 and bnl != 0 and rv_is_array_local(body_head, src, bns, bnl, a) and aoff >= 0
          if sliceok {
            ## word1 = hi - lo
            emit_rv_expr(ex_slice_hi(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
            emit_rv_expr(ex_slice_lo(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "  mv a1, a0\n  ld a0, 0(sp)\n  addi sp, sp, 16\n  sub a0, a0, a1\n  sd a0, ")
            push_int(sb, poff + 8) ; push_str(sb, "(s0)\n")
            ## word0 = &base[lo] = s0 + aoff + lo*estride*8 (estride = the base array's element words —
            ## 1 for a scalar array, byte-identical `slli 3`; struct/enum element scales lo by estride*8).
            estrideS := rv_iter_stride(body_head, src, sbase, a, decls)
            emit_rv_expr(ex_slice_lo(v), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if estrideS == 1 { push_str(sb, "  slli a0, a0, 3\n") }
            if estrideS != 1 { push_str(sb, "  li a1, ") ; push_int(sb, estrideS * 8) ; push_str(sb, "\n  mul a0, a0, a1\n") }
            push_str(sb, "  add a0, a0, s0\n  addi a0, a0, ")
            push_int(sb, aoff) ; push_str(sb, "\n  sd a0, ")
            push_int(sb, poff) ; push_str(sb, "(s0)\n")
          }
          if not sliceok { push_str(sb, "  ebreak\n") }
        }
        s = nx
      }
      Stmt::IndexAssign(ibase, iidx, ival, nx) => {
        ## `a[i] = v` for an ARRAY local: value → a0 (pushed), index → a0, addr = s0 + i*8 (+ base off in
        ## the store immediate), store.
        bns := ex_var_ns(ibase)
        bnl := ex_var_nl(ibase)
        mut isslice := false
        if bnl != 0 { if rv_is_slice_local(body_head, src, bns, bnl, a) { isslice = true } }
        isarr := bnl != 0 and rv_is_array_local(body_head, src, bns, bnl, a)
        aoff := rv_local_off(body_head, src, bns, bnl, pcount, a, decls)
        ## `xs[i] = v` — a whole-ELEMENT write into a fixed array of scalar-only STRUCTS (a LOCAL
        ## array-lit or an array GLOBAL). MUST be tested BEFORE the scalar `isarr` path: that path
        ## scales the index by 8 and stores ONE word, which for a multi-word element would land on the
        ## wrong element AND drop every field but the first — a silent miscompile.
        easp := rv_arrname_elem_struct_span(src, bns, bnl, a, decls)
        eaisla := easp.n != 0 and rv_is_array_local(body_head, src, bns, bnl, a)
        eaisga := easp.n != 0 and (not eaisla) and rv_is_array_global(decls, src, bns, bnl)
        ## the RHS must be a struct LITERAL of that type, or a bare Var naming a struct LOCAL (frame copy).
        eaislit := easp.n != 0 and rv_is_slit(ival)
        eavnl := ex_var_nl(ival)
        mut eavoff := i64(0) - 1
        if easp.n != 0 and (not eaislit) and eavnl != 0 {
          if rv_local_struct_nl(body_head, src, ex_var_ns(ival), eavnl, a) != 0 { eavoff = rv_local_off(body_head, src, ex_var_ns(ival), eavnl, pcount, a, decls) }
        }
        eaok := (eaisla or eaisga) and (eaislit or eavoff >= 0) and ((not eaisla) or aoff >= 0)
        mut eabyte := false
        if easp.n != 0 and std_array_elem_byte_tier(decls, src, easp.s, easp.n, a) { eabyte = true }
        ## the DEEP write shape: the base is not a bare array Var (`xs[i].arr[j] = v`), addressed by
        ## composition with a SCALAR one-word leaf. Tried last, after every closed-formula path.
        diaty := rv_place_idx_ty(ibase, body_head, src, a, decls)
        mut deepia := false
        if diaty.n != 0 {
          if ty_is_scalar(diaty.s, diaty.n, decls, src) {
            if rv_place_idx_ok(ibase, body_head, src, params_head, pcount, a, decls) { deepia = true }
          }
        }
        stdidxAssignTy := rv_std_idx_path_ty(ibase, body_head, src, a, decls)
        stdidxAssignEl := rv_arrty_elem(src, stdidxAssignTy.s, stdidxAssignTy.n)
        mut stdidxassign := false
        if rv_std_idx_path_ok(ibase, body_head, src, a, decls) and stdidxAssignEl.n != 0 and scalar_byte_size(src, stdidxAssignEl.s, stdidxAssignEl.n) == 1 { stdidxassign = true }
        if stdidxassign {
          ## `xs[i].data[j] = v`: preserve value and inner index while composing the outer element,
          ## then store exactly one byte at the nested array element.
          emit_rv_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_place_idx_addr(rv_std_idx_root_arr(ibase), rv_std_idx_root_idx(ibase), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          siboA := rv_std_idx_path_bo(ibase, body_head, src, a, decls)
          if siboA != 0 { push_str(sb, "  li a1, ") ; push_int(sb, siboA) ; push_str(sb, "\n  add a0, a0, a1\n") }
          push_str(sb, "  ld a1, 0(sp)\n  addi sp, sp, 16\n")
          if RV_CHK {
            snelA := rv_arrty_nel(src, stdidxAssignTy.s, stdidxAssignTy.n)
            if snelA > 0 { push_str(sb, "  li a2, ") ; push_int(sb, snelA) ; push_str(sb, "\n  bltu a1, a2, 1f\n  ebreak\n1:\n") }
          }
          push_str(sb, "  add a0, a0, a1\n  ld a2, 0(sp)\n  addi sp, sp, 16\n  sb a2, 0(a0)\n")
        }
        else if eaok {
          eaw := i64(struct_words(decls, src, easp.s, easp.n, a))
          mut eanel := 0
          if eaisla { eanel = rv_array_nel(body_head, src, bns, bnl, a) }
          if eaisga { eanel = rv_alit_nel(rv_global_value(decls, src, bns, bnl)) }
          ## element ADDRESS once → kept on the stack (each field emit clobbers the scratch registers).
          emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if RV_CHK {
            if eanel > 0 { push_str(sb, "  li a1, ") ; push_int(sb, eanel) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
          }
          mut estrideB := eaw * 8
          if eabyte { estrideB = i64(layout_elem_stride_bytes(decls, src, easp.s, easp.n, a)) }
          push_str(sb, "  li a1, ") ; push_int(sb, estrideB) ; push_str(sb, "\n  mul a0, a0, a1\n")
          if eaisla { push_str(sb, "  add a0, a0, s0\n  addi a0, a0, ") ; push_int(sb, aoff) ; push_str(sb, "\n") }
          if eaisga { push_str(sb, "  la a2, ") ; push_str(sb, str_at((src + bns), bnl)) ; push_str(sb, "\n  add a0, a0, a2\n") }
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          if eaislit and eabyte { _stdp := rv_std_store_struct_atptr(ival, 0, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
          if eaislit and (not eabyte) {
            ## each field at its RUNNING byte offset through the pointer-relative multi-word writer, so a
            ## NESTED struct / `[T; N]` field of the element literal lands in FULL and the fields after it
            ## stay aligned. Byte-identical to the old one-word-per-argument store for an all-scalar element.
            mut efg := ex_struct_lit_args(ival)
            mut efo := i64(0)
            while efg != 0 {
              efa := deref(arg_p(efg))
              efw := emit_rv_store_payload_atptr(efa.e, efo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
              efo = efo + efw * 8
              efg = efa.next
            }
          }
          if (not eaislit) and eabyte {
            nbp := i64(std_copy_image_bytes(decls, src, easp.s, easp.n, a))
            mut ebk := i64(0)
            while ebk < nbp {
              push_str(sb, "  lbu a0, ") ; push_int(sb, eavoff + ebk) ; push_str(sb, "(s0)\n  ld a1, 0(sp)\n  sb a0, ") ; push_int(sb, ebk) ; push_str(sb, "(a1)\n")
              ebk = ebk + 1
            }
          }
          if (not eaislit) and (not eabyte) {
            mut evk := i64(0)
            while evk < eaw {
              push_str(sb, "  ld a0, ") ; push_int(sb, eavoff + evk * 8) ; push_str(sb, "(s0)\n  ld a1, 0(sp)\n  sd a0, ") ; push_int(sb, evk * 8) ; push_str(sb, "(a1)\n")
              evk = evk + 1
            }
          }
          push_str(sb, "  addi sp, sp, 16\n")
        }
        else if easp.n != 0 { push_str(sb, "  ebreak\n") }
        else if isslice and aoff >= 0 {
          ## `s[i] = v` through a range-slice VIEW: store v at ptr (word0) + i*8. Bounds vs the runtime
          ## len (word1 at aoff+8) with t0 scratch (a0=index, a1=value, a2=ptr). Dropped under `unchecked`.
          emit_rv_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if RV_CHK {
            push_str(sb, "  ld t0, ") ; push_int(sb, aoff + 8) ; push_str(sb, "(s0)\n  bltu a0, t0, 1f\n  ebreak\n1:\n")
          }
          push_str(sb, "  slli a0, a0, 3\n  ld a2, ") ; push_int(sb, aoff) ; push_str(sb, "(s0)\n  add a2, a2, a0\n  ld a1, 0(sp)\n  addi sp, sp, 16\n  sd a1, 0(a2)\n")
        }
        else if isarr and aoff >= 0 {
          emit_rv_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  slli a0, a0, 3\n  add a0, a0, s0\n  ld a1, 0(sp)\n  addi sp, sp, 16\n  sd a1, ") ; push_int(sb, aoff) ; push_str(sb, "(a0)\n")
        }
        else if bnl != 0 and rv_is_array_global(decls, src, bns, bnl) {
          ## `TABLE[i] = v` on an ARRAY GLOBAL: store v at LABEL + i*8 (value pushed, index → a0, base
          ## label → a2). Bounds vs the static element count (dropped under `unchecked`).
          emit_rv_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if RV_CHK {
            gnelW := rv_alit_nel(rv_global_value(decls, src, bns, bnl))
            if gnelW > 0 { push_str(sb, "  li t0, ") ; push_int(sb, gnelW) ; push_str(sb, "\n  bltu a0, t0, 1f\n  ebreak\n1:\n") }
          }
          gcn := str_at((src + bns), bnl)
          push_str(sb, "  slli a0, a0, 3\n  la a2, ") ; push_str(sb, gcn) ; push_str(sb, "\n  add a2, a2, a0\n  ld a1, 0(sp)\n  addi sp, sp, 16\n  sd a1, 0(a2)\n")
        }
        else if deepia {
          ## `xs[i].arr[j] = v` — a DEEP element WRITE (the base is a FIELD, not a bare Var, so no closed
          ## frame formula exists). Value → a0 and PUSHED first: the address composition below evaluates
          ## the index and clobbers every scratch register. The composition is stack-BALANCED, so the
          ## pushed value is still at `0(sp)` when the address lands in a0.
          emit_rv_expr(ival, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_place_idx_addr(ibase, iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  ld a1, 0(sp)\n  addi sp, sp, 16\n  sd a1, 0(a0)\n")
        }
        else { push_str(sb, "  ebreak\n") }
        s = nx
      }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => {
        ## `p.f = v` for a struct LOCAL p: evaluate v → a0, store at (p base + field word offset).
        stys := rv_local_struct_ns(body_head, src, bns, bnl, a)
        styn := rv_local_struct_nl(body_head, src, bns, bnl, a)
        poff := rv_local_off(body_head, src, bns, bnl, pcount, a, decls)
        mut stdhandled := false
        if styn != 0 and poff >= 0 and layout_kind_is_byte(layout_kind(decls, src, stys, styn, a)) {
          sbo := standard_field_byte_offset(decls, src, stys, styn, fns, fnl, a)
          sft := field_type_span(decls, src, stys, styn, fns, fnl, a)
          if sbo >= 0 and sft.n != 0 {
            if std_ty_aggregate(sft.s, sft.n, decls, src) {
              if rv_is_slit(fv) { _stdw := rv_std_store_struct(fv, poff + sbo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
              if not rv_is_slit(fv) { push_str(sb, "  ebreak # unsupported standard aggregate field assign\n") }
              stdhandled = true
            }
            if not std_ty_aggregate(sft.s, sft.n, decls, src) {
              emit_rv_expr(fv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
              rv_std_store_scalar(poff + sbo, scalar_byte_size(src, sft.s, sft.n), sb)
              stdhandled = true
            }
          }
        }
        if not stdhandled { emit_rv_expr(fv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        ## gate on THIS FIELD being scalar (not the whole struct) — mirrors the Field-READ localok gate.
        ok := (not stdhandled) and styn != 0 and poff >= 0 and rv_field_is_scalar(decls, src, stys, styn, fns, fnl, a)
        if ok {
          woff := field_word_offset(decls, src, stys, styn, fns, fnl, a)
          push_str(sb, "  sd a0, ") ; push_int(sb, poff + woff * 8) ; push_str(sb, "(s0)\n")
        }
        ## `q.f = v` for a struct PARAM q (by-reference: `in out q : Box(T)` / a by-value struct param) —
        ## the param slot holds the base ADDRESS, so store v at `[base + field word offset]`. Mirrors the
        ## Field-READ paramok path; resolves the generic-struct param type via rv_param_struct_ns/nl.
        pidxFA := rv_param_find(params_head, src, bns, bnl, a)
        pstys := rv_param_struct_ns(params_head, src, bns, bnl, a, decls)
        pstyn := rv_param_struct_nl(params_head, src, bns, bnl, a, decls)
        paramok := (not ok) and pidxFA >= 0 and pstyn != 0 and rv_struct_all_scalar(decls, src, pstys, pstyn, a)
        if paramok {
          woffP := field_word_offset(decls, src, pstys, pstyn, fns, fnl, a)
          push_str(sb, "  ld t1, ") ; push_int(sb, 16 + pidxFA * 8) ; push_str(sb, "(s0)\n  sd a0, ") ; push_int(sb, woffP * 8) ; push_str(sb, "(t1)\n")
        }
        ## `G.f = v` for a struct GLOBAL G: store a0 at LABEL + field word offset (scalar field only).
        ## Disjoint from the local path (a global has no frame slot → poff < 0 → ok false).
        gv := rv_global_value(decls, src, bns, bnl)
        mut gok := false
        if unchecked bitcast(usize, gv) != 0 { if rv_is_slit(gv) {
          gstys := rv_slit_ns(gv)
          gstyn := rv_slit_nl(gv)
          gfts := field_type_span(decls, src, gstys, gstyn, fns, fnl, a)
          if ty_is_scalar(gfts.s, gfts.n, decls, src) {
            gwoff := field_word_offset(decls, src, gstys, gstyn, fns, fnl, a)
            if gwoff >= 0 {
              gok = true
              gcn := str_at((src + bns), bnl)
              push_str(sb, "  la t1, ") ; push_str(sb, gcn) ; push_str(sb, "\n  sd a0, ") ; push_int(sb, gwoff * 8) ; push_str(sb, "(t1)\n")
            }
          }
        } }
        if (not stdhandled) and (not ok) and (not gok) and (not paramok) { push_str(sb, "  ebreak\n") }
        s = nx
      }
      ## `G.a.b.c = v` — a nested scalar-field WRITE of a struct GLOBAL at ANY depth. Resolve the
      ## cumulative `.data` word offset (nested structs flattened) and store a0.
      Stmt::FieldPathAssign(place, fpv, nx) => {
        emit_rv_expr(fpv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        stdft := rv_std_path_ty(place, body_head, src, a, decls)
        stdfpok := rv_std_path_ok(place, body_head, src, a, decls) and stdft.n != 0 and (not std_ty_aggregate(stdft.s, stdft.n, decls, src))
        if stdfpok {
          sroot := rv_std_path_root_off(place, body_head, src, pcount, a, decls)
          sbo := rv_std_path_bo(place, body_head, src, a, decls)
          rv_std_store_scalar(sroot + sbo, scalar_byte_size(src, stdft.s, stdft.n), sb)
        }
        gtype := rv_gchain_type(place, decls, src, a)
        gwoff := rv_gchain_woff(place, decls, src, a)
        groot := rv_gchain_root(place)
        gpok := gwoff >= 0 and gtype.n != 0 and ty_is_scalar(gtype.s, gtype.n, decls, src)
        if gpok {
          gcn := str_at((src + groot.s), groot.n)
          push_str(sb, "  la t1, ") ; push_str(sb, gcn) ; push_str(sb, "\n  sd a0, ") ; push_int(sb, gwoff * 8) ; push_str(sb, "(t1)\n")
        }
        ## `c.v.a = e` — the LOCAL dual: a nested scalar-field WRITE of a struct LOCAL at ANY depth. Resolve
        ## the cumulative frame WORD offset (nested structs flattened) through the chain rooted at a struct
        ## local and store a0 at (root frame base + off*8). Disjoint from gpok.
        lroot := rv_gchain_root(place)
        ltype := rv_lchain_type(place, body_head, src, a, decls)
        lwoff := rv_lchain_woff(place, body_head, src, a, decls)
        lrootoff := rv_local_off(body_head, src, lroot.s, lroot.n, pcount, a, decls)
        lpok := (not stdfpok) and lwoff >= 0 and lrootoff >= 0 and ltype.n != 0 and ty_is_scalar(ltype.s, ltype.n, decls, src)
        if lpok { push_str(sb, "  sd a0, ") ; push_int(sb, lrootoff + lwoff * 8) ; push_str(sb, "(s0)\n") }
        ## `xs[i].b.c.cx = v` — the DEEP dual: the chain is rooted at an array ELEMENT (a RUNTIME address),
        ## so no cumulative frame offset exists. The value is already in a0 — PUSH it, compose the leaf
        ## address (that emit clobbers every scratch register), pop the value and store one word.
        mut deepfp := false
        if (not stdfpok) and (not gpok) and (not lpok) {
          if rv_deep_scalar_ok(place, body_head, src, params_head, pcount, a, decls) { deepfp = true }
        }
        if deepfp {
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_place_addr(place, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  ld a1, 0(sp)\n  addi sp, sp, 16\n")
          if rv_std_idx_path_ok(place, body_head, src, a, decls) {
            ptyb := rv_std_idx_path_ty(place, body_head, src, a, decls)
            pwb := scalar_byte_size(src, ptyb.s, ptyb.n)
            if pwb == 1 { push_str(sb, "  sb a1, 0(a0)\n") }
            if pwb == 2 { push_str(sb, "  sh a1, 0(a0)\n") }
            if pwb == 4 { push_str(sb, "  sw a1, 0(a0)\n") }
            if pwb == 8 { push_str(sb, "  sd a1, 0(a0)\n") }
          }
          if not rv_std_idx_path_ok(place, body_head, src, a, decls) { push_str(sb, "  sd a1, 0(a0)\n") }
        }
        if (not stdfpok) and (not gpok) and (not lpok) and (not deepfp) { push_str(sb, "  ebreak\n") }
        s = nx
      }
      ## `xs[i].f = e` — a scalar FIELD write into an ELEMENT of a fixed array of scalar-only structs
      ## (a LOCAL array-lit or an array GLOBAL): the WRITE dual of the `xs[i].f` read. Evaluate the value
      ## → a0 and PUSH it (the index expr clobbers every scratch register), form the element base in a2,
      ## then store the popped value at (element base + woff*8). Bounds vs the STATIC element count
      ## (dropped under `unchecked`, CG-7). Any other shape stays fail-loud.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => {
        fins := ex_var_ns(ifb)
        finl := ex_var_nl(ifb)
        fesp := rv_arrname_elem_struct_span(src, fins, finl, a, decls)
        fla := fesp.n != 0 and rv_is_array_local(body_head, src, fins, finl, a)
        fga := fesp.n != 0 and (not fla) and rv_is_array_global(decls, src, fins, finl)
        faoff := rv_local_off(body_head, src, fins, finl, pcount, a, decls)
        ## THIS FIELD must be SCALAR — an element struct may now carry a nested aggregate field, and a
        ## one-word `sd` at its offset would silently write only its word 0 (leaving the rest stale).
        ffscal := fesp.n != 0 and rv_field_is_scalar(decls, src, fesp.s, fesp.n, iffs, iffl, a)
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
          if fla { fnel = rv_array_nel(body_head, src, fins, finl, a) }
          if fga { fnel = rv_alit_nel(rv_global_value(decls, src, fins, finl)) }
          emit_rv_expr(ifv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_expr(ifi, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if RV_CHK {
            if fnel > 0 { push_str(sb, "  li a1, ") ; push_int(sb, fnel) ; push_str(sb, "\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
          }
          push_str(sb, "  li a1, ") ; push_int(sb, fstrb) ; push_str(sb, "\n  mul a0, a0, a1\n")
          if fla { push_str(sb, "  add a2, a0, s0\n  addi a2, a2, ") ; push_int(sb, faoff) ; push_str(sb, "\n") }
          if fga { push_str(sb, "  la a2, ") ; push_str(sb, str_at((src + fins), finl)) ; push_str(sb, "\n  add a2, a2, a0\n") }
          push_str(sb, "  ld a0, 0(sp)\n  addi sp, sp, 16\n")
          if fbyte {
            ftf := field_type_span(decls, src, fesp.s, fesp.n, iffs, iffl, a)
            fwf := scalar_byte_size(src, ftf.s, ftf.n)
            if fwf == 1 { push_str(sb, "  sb a0, ") ; push_int(sb, fwoffb) ; push_str(sb, "(a2)\n") }
            if fwf == 2 { push_str(sb, "  sh a0, ") ; push_int(sb, fwoffb) ; push_str(sb, "(a2)\n") }
            if fwf == 4 { push_str(sb, "  sw a0, ") ; push_int(sb, fwoffb) ; push_str(sb, "(a2)\n") }
            if fwf == 8 { push_str(sb, "  sd a0, ") ; push_int(sb, fwoffb) ; push_str(sb, "(a2)\n") }
          }
          if not fbyte { push_str(sb, "  sd a0, ") ; push_int(sb, fwoffb) ; push_str(sb, "(a2)\n") }
        }
        ## `b.cells[i].m = v` — the DEEP dual: the indexed base is an inline `[Struct; N]` FIELD (or any
        ## composable place), so the element address is COMPOSED and the scalar field stored at its word
        ## offset within the element. Value evaluated and PUSHED first (the composition clobbers scratch).
        difty := rv_place_idx_ty(ifb, body_head, src, a, decls)
        mut deepif := false
        if (not ifok) and difty.n != 0 {
          if struct_decl_of(decls, src, difty.s, difty.n) >= 0 {
            if rv_field_is_scalar(decls, src, difty.s, difty.n, iffs, iffl, a) {
              if rv_place_idx_ok(ifb, body_head, src, params_head, pcount, a, decls) { deepif = true }
            }
          }
        }
        if deepif {
          mut dwof := i64(field_word_offset(decls, src, difty.s, difty.n, iffs, iffl, a)) * 8
          if layout_kind_is_byte(layout_kind(decls, src, difty.s, difty.n, a)) { dwof = layout_field_offset_bytes(decls, src, difty.s, difty.n, iffs, iffl, a) }
          emit_rv_expr(ifv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_place_idx_addr(ifb, ifi, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  ld a1, 0(sp)\n  addi sp, sp, 16\n")
          if layout_kind_is_byte(layout_kind(decls, src, difty.s, difty.n, a)) {
            dft := field_type_span(decls, src, difty.s, difty.n, iffs, iffl, a)
            dfw := scalar_byte_size(src, dft.s, dft.n)
            if dfw == 1 { push_str(sb, "  sb a1, ") ; push_int(sb, dwof) ; push_str(sb, "(a0)\n") }
            if dfw == 2 { push_str(sb, "  sh a1, ") ; push_int(sb, dwof) ; push_str(sb, "(a0)\n") }
            if dfw == 4 { push_str(sb, "  sw a1, ") ; push_int(sb, dwof) ; push_str(sb, "(a0)\n") }
            if dfw == 8 { push_str(sb, "  sd a1, ") ; push_int(sb, dwof) ; push_str(sb, "(a0)\n") }
          }
          if not layout_kind_is_byte(layout_kind(decls, src, difty.s, difty.n, a)) { push_str(sb, "  sd a1, ") ; push_int(sb, dwof) ; push_str(sb, "(a0)\n") }
        }
        if (not ifok) and (not deepif) { push_str(sb, "  ebreak\n") }
        s = ifnx
      }
      Stmt::Return(rv, nx) => {
        ## a struct-returning fn (§8 piece 2) or enum-returning fn (§8 piece 3) delivers word k → a_k; a
        ## scalar/float fn uses the value emit.
        if RV_RET_STRUCT_NL != 0 { emit_rv_struct_value(rv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        if RV_RET_ENUM_NL != 0 { emit_rv_enum_value(rv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        ## a WIDE-struct (LP64 indirect-result) fn writes the value through the caller's destination pointer.
        if RV_RET_SRET_NL != 0 { emit_rv_sret_store(rv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        if RV_RET_STRUCT_NL == 0 and RV_RET_ENUM_NL == 0 and RV_RET_SRET_NL == 0 { emit_rv_expr(rv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        emit_rv_epilogue(frame, sb)
        s = nx
      }
      Stmt::While(c, b, nx) => {
        id := rv_next_label()
        ob := RV_BRK
        oc := RV_CONT
        RV_BRK = id
        RV_CONT = id
        push_str(sb, ".Lwtop") ; push_int(sb, id) ; push_str(sb, ":\n")
        emit_rv_expr(c, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  beqz a0, .Lwend") ; push_int(sb, id) ; push_str(sb, "\n")
        emit_rv_stmts(b, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        ## `continue` target: re-enter the guard (re-evaluate the condition).
        push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
        push_str(sb, "  j .Lwtop") ; push_int(sb, id) ; push_str(sb, "\n")
        push_str(sb, ".Lwend") ; push_int(sb, id) ; push_str(sb, ":\n")
        ## `break` target (fall-through exit).
        push_str(sb, ".Lbrk") ; push_int(sb, id) ; push_str(sb, ":\n")
        RV_BRK = ob
        RV_CONT = oc
        s = nx
      }
      Stmt::If(c, th, el, nx) => {
        id := rv_next_label()
        emit_rv_expr(c, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "  beqz a0, .Lielse") ; push_int(sb, id) ; push_str(sb, "\n")
        emit_rv_stmts(th, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        push_str(sb, "  j .Liend") ; push_int(sb, id) ; push_str(sb, "\n")
        push_str(sb, ".Lielse") ; push_int(sb, id) ; push_str(sb, ":\n")
        emit_rv_stmts(el, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        push_str(sb, ".Liend") ; push_int(sb, id) ; push_str(sb, ":\n")
        s = nx
      }
      Stmt::ExprStmt(e, nx) => {
        srs := rv_call_ret_sret_span(e, decls, src, a)
        ers := rv_call_ret_enum_sret_span(e, decls, src, a)
        if srs.n != 0 or ers.n != 0 { emit_rv_sret_discard(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        if srs.n == 0 and ers.n == 0 { emit_rv_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        s = nx
      }
      Stmt::Match(scrut, arms, nx) => {
        sns := ex_var_ns(scrut)
        snl := ex_var_nl(scrut)
        ens := rv_local_enum_ns(body_head, src, sns, snl, a)
        enl := rv_local_enum_nl(body_head, src, sns, snl, a)
        eoff := rv_local_off(body_head, src, sns, snl, pcount, a, decls)
        endid := rv_next_label()
        ## `match s[i]` on an enum `Slice(E)` PARAM: materialize the by-reference enum element (param-slot
        ## deref data ptr + i*stride*8) into RV_MTMP, then match on that frame offset.
        mut idxmatch := false
        if ex_is_index(scrut) {
          ibx := ex_index_base(scrut)
          ins := ex_var_ns(ibx)
          inl := ex_var_nl(ibx)
          ipidx := rv_param_find(params_head, src, ins, inl, a)
          ees := rv_slice_param_enum_span(params_head, src, ins, inl, decls)
          if ipidx >= 0 and ees.n != 0 {
            idxmatch = true
            stride := rv_slice_param_agg_stride(params_head, src, ins, inl, a, decls)
            pslot := 16 + ipidx * 8
            emit_rv_expr(ex_index_idx(scrut), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            if RV_CHK { push_str(sb, "  ld a3, ") ; push_int(sb, pslot) ; push_str(sb, "(s0)\n  ld a1, 8(a3)\n  bltu a0, a1, 1f\n  ebreak\n1:\n") }
            push_str(sb, "  ld a3, ") ; push_int(sb, pslot) ; push_str(sb, "(s0)\n  ld a2, 0(a3)\n  li a1, ") ; push_int(sb, stride * 8) ; push_str(sb, "\n  mul a0, a0, a1\n  add a2, a2, a0\n")
            mut ck := 0
            while ck < stride {
              push_str(sb, "  ld a0, ") ; push_int(sb, ck * 8) ; push_str(sb, "(a2)\n  sd a0, ") ; push_int(sb, RV_MTMP + ck * 8) ; push_str(sb, "(s0)\n")
              ck = ck + 1
            }
            emit_rv_match_arms(arms, ees.s, ees.n, RV_MTMP, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
            push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
          }
        }
        ok := (not idxmatch) and snl != 0 and enl != 0 and eoff >= 0
        ## a `match <enum PARAM>` (§8 piece 3): materialize the by-reference {disc,payload…} into RV_MTMP.
        pidxM := rv_param_find(params_head, src, sns, snl, a)
        penlM := rv_param_enum_nl(params_head, src, sns, snl, decls)
        paramok := (not idxmatch) and (not ok) and pidxM >= 0 and penlM != 0
        ## a nested `match <enum payload BINDING>` (§8 piece 3b): match directly at frame offset bind_base + 8.
        bagg := rv_bind_agg_span(bind_head, src, sns, snl, a, decls)
        bindok := (not idxmatch) and (not ok) and (not paramok) and bagg.n != 0 and enum_decl_of(decls, src, bagg.s, bagg.n) >= 0
        if ok {
          emit_rv_match_arms(arms, ens, enl, eoff, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
        if paramok {
          pensM := rv_param_enum_ns(params_head, src, sns, snl, decls)
          wM := 1 + i64(enum_max_arity(decls, src, pensM, penlM, a))
          push_str(sb, "  ld t0, ") ; push_int(sb, 16 + pidxM * 8) ; push_str(sb, "(s0)\n")
          mut km := 0
          while km < wM { push_str(sb, "  ld a0, ") ; push_int(sb, km * 8) ; push_str(sb, "(t0)\n  sd a0, ") ; push_int(sb, RV_MTMP + km * 8) ; push_str(sb, "(s0)\n") ; km = km + 1 }
          emit_rv_match_arms(arms, pensM, penlM, RV_MTMP, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
        if bindok {
          emit_rv_match_arms(arms, bagg.s, bagg.n, bind_base + 8, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
        }
        mut scalarok := false
        if (not ok) and (not idxmatch) and (not paramok) and (not bindok) {
          emit_rv_expr(scrut, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          emit_rv_scalar_match_arms(arms, endid, sb, a, src, params_head, pcount, body_head, decls, frame)
          push_str(sb, ".Lmend") ; push_int(sb, endid) ; push_str(sb, ":\n")
          scalarok = true
        }
        if (not ok) and (not idxmatch) and (not paramok) and (not bindok) and (not scalarok) { push_str(sb, "  ebreak\n") }
        s = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        ## RANGE `for i in lo..hi { … }`: `i` lives at its frame slot (rv_local_off). i := lo; loop while
        ## i < hi (SIGNED, x86 parity via setl); body; i += 1; back-edge.
        if unchecked bitcast(usize, fhi) == 0 {
          ## ITERABLE `for x in <arr/slice-view> { … }`: `x` binds each ELEMENT. `x` lives at its frame slot
          ## (voff); a hidden index rides the NEXT reserved word (voff+8 — the local scan reserves TWO words
          ## for an iterable For). Bound: an INLINE scalar/float array (elements at s0+aoff+i*8, static count)
          ## or a scalar slice VIEW (word0 = data ptr @ aoff, word1 = runtime len @ aoff+8; element at
          ## ptr+i*8). Element word copied BY VALUE (a float rides its bits). Anything else (slice PARAM /
          ## Vec / non-var) traps loud. `__i = 0; while __i < len { x = elem[__i] ; body ; __i += 1 }`.
          bns := ex_var_ns(flo)
          bnl := ex_var_nl(flo)
          voff := rv_local_off(body_head, src, fns, fnl, pcount, a, decls)
          ioff := voff + 8
          aoff := rv_local_off(body_head, src, bns, bnl, pcount, a, decls)
          mut isslice := false
          if bnl != 0 { if rv_is_slice_local(body_head, src, bns, bnl, a) { isslice = true } }
          mut isarr := false
          if (not isslice) and bnl != 0 { if rv_is_array_local(body_head, src, bns, bnl, a) { isarr = true } }
          pidxF := rv_param_find(params_head, src, bns, bnl, a)
          ## `for x in s` over a scalar `Slice(E)` PARAM: the param slot holds a POINTER to the caller's
          ## `{ptr,len}` block, so len = `8(blk)` and data ptr = `0(blk)` (a DOUBLE deref). Not a local, so
          ## `aoff` is -1; gate on the param slot. Guard `16 + pidxF*8` behind pidxF >= 0 (frozen-seed
          ## checked-add emits an UNSIGNED carry check → a negative pidxF would spuriously trap).
          mut isparamslice := false
          if (not isslice) and (not isarr) and pidxF >= 0 { if rv_slice_param_scalar(params_head, src, bns, bnl, a, decls) { isparamslice = true } }
          mut pslotF := 0
          if pidxF >= 0 { pslotF = 16 + pidxF * 8 }
          nel := rv_array_nel(body_head, src, bns, bnl, a)
          id := rv_next_label()
          ob := RV_BRK
          oc := RV_CONT
          RV_BRK = id
          RV_CONT = id
          ## AGGREGATE (struct-element) array iteration: the loop var occupies `estrideF` words (its element
          ## struct) + a hidden index word at voff+estrideF*8. Each iteration COPIES the estrideF-word element
          ## `a[i]` (base s0+aoff+i*estrideF*8) into the loop var slots; `p.field` then reads localok.
          estrideF := rv_iter_stride(body_head, src, flo, a, decls)
          mut isaggarr := false
          if isarr and estrideF > 1 { isaggarr = true }
          mut isaggslice := false
          if isslice and estrideF > 1 { isaggslice = true }
          ## a struct/enum-element `Slice(E)` PARAM base: param slot holds a POINTER to the `{ptr,len}` block;
          ## element base = block.word0 (data ptr) + i*stride*8. `aoff` is -1 (a param); gate on the slot.
          mut isaggparam := false
          if (not isslice) and (not isarr) and pidxF >= 0 { if rv_slice_param_agg_stride(params_head, src, bns, bnl, a, decls) > 0 { isaggparam = true } }
          mut okfi := false
          if voff >= 0 and ((isslice and not isaggslice) or (isarr and not isaggarr)) and aoff >= 0 { okfi = true }
          if voff >= 0 and isparamslice { okfi = true }
          mut aggdone := false
          canagg := voff >= 0 and (((isaggarr or isaggslice) and aoff >= 0) or isaggparam)
          if canagg {
            aggdone = true
            ioffA := voff + estrideF * 8
            push_str(sb, "  li a0, 0\n  sd a0, ") ; push_int(sb, ioffA) ; push_str(sb, "(s0)\n")
            push_str(sb, ".Lfitop") ; push_int(sb, id) ; push_str(sb, ":\n")
            push_str(sb, "  ld a0, ") ; push_int(sb, ioffA) ; push_str(sb, "(s0)\n")
            ## count (loop bound) → a1: ARRAY = static nel; VIEW = word1 at aoff+8; PARAM = block.word1
            if isaggarr { push_str(sb, "  li a1, ") ; push_int(sb, nel) ; push_str(sb, "\n") }
            if isaggslice { push_str(sb, "  ld a1, ") ; push_int(sb, aoff + 8) ; push_str(sb, "(s0)\n") }
            if isaggparam { push_str(sb, "  ld a3, ") ; push_int(sb, pslotF) ; push_str(sb, "(s0)\n  ld a1, 8(a3)\n") }
            push_str(sb, "  bge a0, a1, .Lfiend") ; push_int(sb, id) ; push_str(sb, "\n")
            ## element base → a2, then a2 += i*estrideF*8
            if isaggarr { push_str(sb, "  addi a2, s0, ") ; push_int(sb, aoff) ; push_str(sb, "\n") }
            if isaggslice { push_str(sb, "  ld a2, ") ; push_int(sb, aoff) ; push_str(sb, "(s0)\n") }
            if isaggparam { push_str(sb, "  ld a3, ") ; push_int(sb, pslotF) ; push_str(sb, "(s0)\n  ld a2, 0(a3)\n") }
            push_str(sb, "  li a1, ") ; push_int(sb, estrideF * 8) ; push_str(sb, "\n  mul a0, a0, a1\n  add a2, a2, a0\n")
            ## copy estrideF words into the loop var's slots (voff + k*8)
            mut ck := 0
            while ck < estrideF {
              push_str(sb, "  ld a0, ") ; push_int(sb, ck * 8) ; push_str(sb, "(a2)\n  sd a0, ") ; push_int(sb, voff + ck * 8) ; push_str(sb, "(s0)\n")
              ck = ck + 1
            }
            emit_rv_stmts(fb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
            push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
            push_str(sb, "  ld a0, ") ; push_int(sb, ioffA) ; push_str(sb, "(s0)\n  addi a0, a0, 1\n  sd a0, ") ; push_int(sb, ioffA) ; push_str(sb, "(s0)\n")
            push_str(sb, "  j .Lfitop") ; push_int(sb, id) ; push_str(sb, "\n")
            push_str(sb, ".Lfiend") ; push_int(sb, id) ; push_str(sb, ":\n")
          }
          if okfi {
            push_str(sb, "  li a0, 0\n  sd a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n")
            push_str(sb, ".Lfitop") ; push_int(sb, id) ; push_str(sb, ":\n")
            push_str(sb, "  ld a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n")
            ## len (loop bound) → a1
            if isparamslice { push_str(sb, "  ld t3, ") ; push_int(sb, pslotF) ; push_str(sb, "(s0)\n  ld a1, 8(t3)\n") }
            if isslice { push_str(sb, "  ld a1, ") ; push_int(sb, aoff + 8) ; push_str(sb, "(s0)\n") }
            if isarr { push_str(sb, "  li a1, ") ; push_int(sb, nel) ; push_str(sb, "\n") }
            push_str(sb, "  bge a0, a1, .Lfiend") ; push_int(sb, id) ; push_str(sb, "\n")
            ## data pointer → a2
            if isparamslice { push_str(sb, "  ld t3, ") ; push_int(sb, pslotF) ; push_str(sb, "(s0)\n  ld a2, 0(t3)\n") }
            if isslice { push_str(sb, "  ld a2, ") ; push_int(sb, aoff) ; push_str(sb, "(s0)\n") }
            if isarr { push_str(sb, "  addi a2, s0, ") ; push_int(sb, aoff) ; push_str(sb, "\n") }
            push_str(sb, "  ld a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n  slli a0, a0, 3\n  add a2, a2, a0\n  ld a0, 0(a2)\n")
            push_str(sb, "  sd a0, ") ; push_int(sb, voff) ; push_str(sb, "(s0)\n")
            emit_rv_stmts(fb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
            push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
            push_str(sb, "  ld a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n  addi a0, a0, 1\n  sd a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n")
            push_str(sb, "  j .Lfitop") ; push_int(sb, id) ; push_str(sb, "\n")
            push_str(sb, ".Lfiend") ; push_int(sb, id) ; push_str(sb, ":\n")
          }
          if (not okfi) and (not aggdone) {
            push_str(sb, "  ebreak\n")
          }
          ## `break` target (fall-through exit) + restore the enclosing loop's break/continue ids.
          push_str(sb, ".Lbrk") ; push_int(sb, id) ; push_str(sb, ":\n")
          RV_BRK = ob
          RV_CONT = oc
        } else {
          ioff := rv_local_off(body_head, src, fns, fnl, pcount, a, decls)
          id := rv_next_label()
          ob := RV_BRK
          oc := RV_CONT
          RV_BRK = id
          RV_CONT = id
          emit_rv_expr(flo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  sd a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n")
          push_str(sb, ".Lftop") ; push_int(sb, id) ; push_str(sb, ":\n")
          push_str(sb, "  ld a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_expr(fhi, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  mv a1, a0\n  ld a0, 0(sp)\n  addi sp, sp, 16\n  bge a0, a1, .Lfend") ; push_int(sb, id) ; push_str(sb, "\n")
          emit_rv_stmts(fb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
          ## `continue` target: the INCREMENT (so the loop index still advances).
          push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
          push_str(sb, "  ld a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n  addi a0, a0, 1\n  sd a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n")
          push_str(sb, "  j .Lftop") ; push_int(sb, id) ; push_str(sb, "\n")
          push_str(sb, ".Lfend") ; push_int(sb, id) ; push_str(sb, ":\n")
          push_str(sb, ".Lbrk") ; push_int(sb, id) ; push_str(sb, ":\n")
          RV_BRK = ob
          RV_CONT = oc
        }
        s = nx
      }
      ## Infinite `loop { body }`: a top label, the body (with `break` → `.Lbrk<id>`, `continue` →
      ## `.Lcont<id>` = the top), an unconditional back-edge, then the exit. `id` is fresh for this emission,
      ## including when the body is re-emitted by a generic/comptime instance.
      Stmt::Loop(lb, lnx) => {
        id := rv_next_label()
        ob := RV_BRK
        oc := RV_CONT
        RV_BRK = id
        RV_CONT = id
        push_str(sb, ".Lltop") ; push_int(sb, id) ; push_str(sb, ":\n")
        emit_rv_stmts(lb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        push_str(sb, ".Lcont") ; push_int(sb, id) ; push_str(sb, ":\n")
        push_str(sb, "  j .Lltop") ; push_int(sb, id) ; push_str(sb, "\n")
        push_str(sb, ".Lbrk") ; push_int(sb, id) ; push_str(sb, ":\n")
        RV_BRK = ob
        RV_CONT = oc
        s = lnx
      }
      ## Only the NEAREST-loop unlabeled form is modelled; a LABELED `break name`/`continue name`
      ## (`bd`/`cd != 0`) or a loop-EXPRESSION `break <expr>` (`bv != 0`, §7.2) fail-loud (`ebreak`)
      ## rather than silently branch to the wrong loop / drop the value.
      Stmt::Break(bv, bd, bnx) => {
        if bd != 0 or unchecked bitcast(usize, bv) != 0 { push_str(sb, "  ebreak\n") }
        else { push_str(sb, "  j .Lbrk") ; push_int(sb, RV_BRK) ; push_str(sb, "\n") }
        s = bnx
      }
      Stmt::Continue(cd, cnx) => {
        if cd != 0 { push_str(sb, "  ebreak\n") }
        else { push_str(sb, "  j .Lcont") ; push_int(sb, RV_CONT) ; push_str(sb, "\n") }
        s = cnx
      }
      ## `unchecked { body }` (Grammar §130 statement form): lower the body with checked verification OFF,
      ## then restore. Mirrors the `Expr::Unchecked` toggle + x86 lower.
      Stmt::Unchecked(ub, unx) => {
        ov := RV_CHK
        RV_CHK = false
        emit_rv_stmts(ub, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
        RV_CHK = ov
        s = unx
      }
      ## `deref(<scalar ptr>) = v` — STORE one word through the pointer (spec MEM-8). Value → a0 (pushed);
      ## pointer → a1; `sd a0, 0(a1)`. SCALAR value only: a struct/enum/array LITERAL value store is
      ## DEFERRED (multi-word), fail-loud (`ebreak`). Mirrors the x86 DerefAssign scalar fast path.
      Stmt::DerefAssign(pe, val, nx) => {
        isslitv := rv_is_slit(val)
        iselitv := rv_is_elit(val)
        isalitv := ex_is_array_lit(val)
        isslicev := ex_is_slice(val)
        if isslitv or iselitv or isalitv or isslicev { push_str(sb, "  ebreak\n") }
        else {
          emit_rv_expr(val, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  addi sp, sp, -16\n  sd a0, 0(sp)\n")
          emit_rv_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "  mv a1, a0\n  ld a0, 0(sp)\n  addi sp, sp, 16\n  sd a0, 0(a1)\n")
        }
        s = nx
      }
      ## `comptime if <cond> { then } else { else }` — fold the condition and emit ONLY the taken branch's
      ## statements (arch/verify predicates). Conforms to the x86 lower: `target.arch == Arch.x86_64` folds
      ## TRUE. An unfoldable condition (a `match typeinfo(T)` — needs the mono context the rv64 path lacks)
      ## emits a fail-loud `ebreak` (never a silent miscompile). No runtime branch: the erased condition
      ## disappears, the taken branch's statements emit inline.
      Stmt::CompIf(cc, th, el, nx) => {
        cv := rv_comp_cond_fold(cc, src)
        if cv == 1 { emit_rv_stmts(th, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base) }
        if cv == 0 { emit_rv_stmts(el, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base) }
        if cv < 0 { push_str(sb, "  ebreak\n") }
        s = nx
      }
      ## `comptime for i in lo .. hi { body }` — UNROLL at emit time: for each constant k in [lo, hi), store
      ## `comptime if <cond>` — fold the predicate (rv_comp_cond_fold) and emit ONLY the taken branch.
      ## Unfoldable (needs mono context) → fail-loud ebreak (never a silent miscompile).
      Stmt::CompIf(cc, th, el, nx) => {
        cv := rv_comp_cond_fold(cc, src)
        if cv == 1 { emit_rv_stmts(th, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base) }
        if cv == 0 { emit_rv_stmts(el, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base) }
        if cv < 0 { push_str(sb, "  ebreak\n") }
        s = nx
      }
      ## `comptime match typeinfo(T) { <Kind>(_) => …, _ => … }` (§8 mono) — fold on T's KIND inside a
      ## mono INSTANCE (RV_SUB active) and emit ONLY the matching arm (or the `_` arm). An inner
      ## `comptime match <scalar-kind>` keys off the SAME instance type. Outside an instance → fail-loud.
      Stmt::CompMatch(cmsc, cmah, cmnx) => {
        if RV_SUB_ITL == 0 { push_str(sb, "  ebreak\n") }
        else {
          kind := ct_type_kind(RV_SUB_ITS, RV_SUB_ITL, decls, src)
          nkind := ct_scalar_num_kind(RV_SUB_ITS, RV_SUB_ITL, src)
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
            emit_rv_stmts(cam2.body_stmts, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
          }
        }
        s = cmnx
      }
      ## `comptime for f in typeinfo(T).fields { body }` (§8 field-derive) — UNROLL over the concrete
      ## target struct's fields (from the explicit typeinfo argument, or a mono substitution): for each field bind the comptime loop context
      ## (RV_CF_* = loop-var name / field name / field type) then emit the body once. Inside, `v.(f)`
      ## resolves to a field READ and `f.type` (an explicit type-arg) to the field type. STRUCT only.
      Stmt::CompFor(cvs, cvl, cisvar, cbody, nx) => {
        mut cfdone := false
        mut cts := RV_SUB_ITS
        mut ctl := RV_SUB_ITL
        cia := compfor_iter_arg(src, cvs, cvl)
        if cia.n != 0 {
          cts = cia.s
          ctl = cia.n
          if RV_SUB_GPL != 0 and streq(src, cts, ctl, RV_SUB_GPS, RV_SUB_GPL) { cts = RV_SUB_ITS ; ctl = RV_SUB_ITL }
          else if RV_SUB_GPL2 != 0 and streq(src, cts, ctl, RV_SUB_GPS2, RV_SUB_GPL2) { cts = RV_SUB_ITS2 ; ctl = RV_SUB_ITL2 }
          else if RV_SUB_GPL3 != 0 and streq(src, cts, ctl, RV_SUB_GPS3, RV_SUB_GPL3) { cts = RV_SUB_ITS3 ; ctl = RV_SUB_ITL3 }
        }
        if ctl != 0 and cisvar == 0 {
          bn := base_type_name(src, cts, ctl)
          sdi := struct_decl_of(decls, src, bn.s, bn.n)
          if sdi >= 0 {
            sd := deref(decl_get(decls, usize(sdi)))
            ov_vs := RV_CF_VAR_S ; ov_vl := RV_CF_VAR_L
            ov_fs := RV_CF_FLD_S ; ov_fl := RV_CF_FLD_L
            ov_ts := RV_CF_TY_S ; ov_tl := RV_CF_TY_L
            mut fd := sd.fields_head
            while fd != 0 {
              fdd := deref(fld_p(fd))
              RV_CF_VAR_S = cvs ; RV_CF_VAR_L = cvl
              RV_CF_FLD_S = fdd.ns ; RV_CF_FLD_L = fdd.nl
              RV_CF_TY_S = fdd.ts ; RV_CF_TY_L = fdd.tl
              emit_rv_stmts(cbody, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
              fd = fdd.next
            }
            RV_CF_VAR_S = ov_vs ; RV_CF_VAR_L = ov_vl
            RV_CF_FLD_S = ov_fs ; RV_CF_FLD_L = ov_fl
            RV_CF_TY_S = ov_ts ; RV_CF_TY_L = ov_tl
            cfdone = true
          }
        }
        if not cfdone { push_str(sb, "  ebreak\n") }
        s = nx
      }
      ## k into the loop var's frame slot then emit the body (no runtime loop; the control flow is erased).
      ## Bounds are compile-time integer constants (rv_comp_range_bound: literal / module const). Mirrors
      ## the x86 lower's CompForRange numeric unroll. A null hi (the §7.1 pack form) is unsupported here.
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => {
        if unchecked bitcast(usize, rhi) == 0 { push_str(sb, "  ebreak\n") }
        else {
          ioff := rv_local_off(body_head, src, rvs, rvl, pcount, a, decls)
          if ioff < 0 { push_str(sb, "  ebreak\n") }
          else {
            lo := rv_comp_range_bound(rlo, decls, src)
            hi := rv_comp_range_bound(rhi, decls, src)
            if hi - lo > 100000 { push_str(sb, "  ebreak\n") }
            else {
              mut k := lo
              while k < hi {
                push_str(sb, "  li a0, ") ; push_int(sb, k) ; push_str(sb, "\n  sd a0, ") ; push_int(sb, ioff) ; push_str(sb, "(s0)\n")
                emit_rv_stmts(rb, sb, a, src, params_head, pcount, body_head, decls, frame, bind_head, bind_base)
                k = k + 1
              }
            }
          }
        }
        s = nx
      }
      _ => { push_str(sb, "  ebreak\n") ; s = 0 }
    }
  }
}


rv_fn_is_generic := fn(params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena) -> bool {
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
## (mirrors the x86_64/aarch64 versions; the marker is arch-agnostic).
rv_fn_is_naked := fn(src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut p := ns + nl
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return false }
  p += 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  str_at((src + p), 11) == "@abi(naked)"
}

## Emit one function: label, prologue (save ra/s0, allocate frame, spill params), body, tail expr,
## fall-through epilogue. A GENERIC fn (a `type` param) is a fail-loud `ebreak` (no monomorphization).
## Emit the `@export("sym")` alias for a fn (Modules §6.3): `.global sym` + a `sym:` label at its entry.
emit_rv_export := fn(in out sb : rt::StrBuf, src : ptr(u8), name_s : usize, name_l : usize) {
  exn := export_name(src, name_s, name_l)
  if exn.n != 0 {
    push_str(sb, ".global ") ; push_str(sb, str_at((src + exn.s), exn.n)) ; push_str(sb, "\n")
    push_str(sb, str_at((src + exn.s), exn.n)) ; push_str(sb, ":\n")
  }
}
## Emit the `call` target for a call to `[cs,cl)`: the callee's `@extern("sym")` external symbol
## (Modules §7.2) if it is a bodyless import, else the bare call name.
rv_emit_call_target := fn(in out sb : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize) {
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
emit_rv_fn := fn(d : Decl, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), decls : ptr(rt::Vec)) {
  ## an `@extern` fn (Modules §7.2) is a bodyless import — emit nothing (calls route to the external symbol).
  if extern_symbol(src, d.name_start, d.name_len).n != 0 { return }
  fname := str_at((src + d.name_start), d.name_len)
  isgen := rv_fn_is_generic(d.params_head, src, a)
  ## GENERICS (§8 mono): a generic fn emits NO standalone body — each instance is emitted separately.
  ## In INSTANCE mode (RV_SUB_ITL set by emit_rv_program's mono pass) with a single LEADING type-param,
  ## skip it (effective value params = params_head.next), set the substitution NAME (RV_SUB_GPS/GPL,
  ## read by rv_comp_cond_fold), and emit `<fn>__<tag>`. A non-instance generic keeps the fail-loud stub.
  RV_SUB_GPS = 0
  RV_SUB_GPL = 0
  RV_SUB_GPS2 = 0
  RV_SUB_GPL2 = 0
  RV_SUB_GPS3 = 0
  RV_SUB_GPL3 = 0
  mut ephead := d.params_head
  mut inst := false
  ## frame-slot index of a NON-LEADING type-param to skip in the spill loop (-1 = none / leading).
  mut rv_tp_skip := i64(0) - 1
  if isgen {
    cnt := decl_tparam_count(d, src)
    lead := decl_leading_tparam_run(d, src)
    ## SUPPORTED: a single type-param (any position), OR a leading RUN of 2..3 type-params (cnt == lead).
    gok := RV_SUB_ITL != 0 and cnt >= 1 and cnt <= 3 and (cnt == lead or cnt == 1)
    if not gok {
      push_str(sb, fname) ; push_str(sb, ":\n  ebreak\n  ret\n")
      return
    }
    inst = true
    ## LEADING RUN (cnt == lead, 1..3): DROP the run; substitute each type-param NAME → its instance type.
    ## `ephead` = the first value param after the run. FLAT ifs — this is a very large fn.
    mut pp := d.params_head
    mut li := i64(0)
    while li < lead {
      pm := deref(param_p(pp))
      if li == 0 { RV_SUB_GPS = pm.ns ; RV_SUB_GPL = pm.nl }
      if li == 1 { RV_SUB_GPS2 = pm.ns ; RV_SUB_GPL2 = pm.nl }
      if li == 2 { RV_SUB_GPS3 = pm.ns ; RV_SUB_GPL3 = pm.nl }
      pp = pm.next
      li = li + 1
    }
    if cnt == lead { ephead = pp }
    ## NON-LEADING single type-param (cnt==1, lead==0, `gf(s, T, k)`): keep the FULL param list but SKIP
    ## the type-param's slot in the spill loop.
    if cnt == 1 and lead == 0 {
      tpn := rv_tparam_name(d, src)
      RV_SUB_GPS = tpn.s
      RV_SUB_GPL = tpn.n
      rv_tp_skip = decl_tparam_pos(d, src)
    }
  }
  pcount := rv_count_params(ephead, a)
  ## stash params + decls so the frame scanners recognize a slice PARAM base (set BEFORE rv_count_locals).
  RV_PARAMS = unchecked bitcast(usize, ephead)
  RV_DECLS = unchecked bitcast(usize, decls)
  RV_BODY = unchecked bitcast(usize, d.body_stmts)
  nloc := rv_count_locals(d.body_stmts, src, a, decls)
  ## SLICE-ARG agg blocks (§8 slice-param caller): 2 reserved words per slice argument in the body + tail.
  nsargs := rv_slarg_count(d.body_stmts) + rv_slarg_count_e(d.value)
  ## ANONYMOUS AGGREGATE-VALUE args (§8, piece 1): a struct-literal passed by value → its full words,
  ## reserved in the SAME RV_AGG region (above the slice-arg blocks), tree-wide over body + tail.
  mut naggw := rv_aggval_words(d.body_stmts, src, a, decls) + rv_aggval_words_e(d.value, src, a, decls)
  naggw = naggw + rv_sret_discard_words(d.body_stmts, src, a, decls)
  if d.ret_tl == 0 { naggw = naggw + rv_sret_discard_words_e(d.value, src, a, decls) }
  ## MATCH-over-INDEX temp (§8 enum slice-param): reserve the largest such match's enum words.
  mut mtmp := rv_match_tmp_words(d.body_stmts, src, a)
  ## …and the SAME region is written by a `match <enum PARAM>` materialization, which the statement scanner
  ## above can miss (it never visits the trailing VALUE). Size it from the PARAM LIST too — an unreserved
  ## materialization writes past the frame top into the CALLER's frame (a raw fault, not a clean trap).
  pemt := rv_param_enum_tmp_words(ephead, src, decls, a)
  if pemt > mtmp { mtmp = pemt }
  ## WIDE-STRUCT SRET (LP64 indirect result): a fn returning a PLAIN struct of > 8 words takes the caller's
  ## destination pointer in a0 and must SPILL it to a reserved frame word (it has to survive nested calls
  ## and register churn up to every Return point). A generic INSTANCE is classified from its substituted
  ## concrete return type; its source declaration still says only `T`.
  mut sret_ts := d.ret_ts
  mut sret_tl := d.ret_tl
  if inst and RV_SUB_GPL != 0 and d.ret_tl == RV_SUB_GPL {
    rbs := bytes(str_at((src + d.ret_ts), d.ret_tl))
    gbs := bytes(str_at((src + RV_SUB_GPS), RV_SUB_GPL))
    mut alleq_sret := true
    mut bi_sret := 0
    while bi_sret < d.ret_tl { if rbs[bi_sret] != gbs[bi_sret] { alleq_sret = false } ; bi_sret = bi_sret + 1 }
    if alleq_sret { sret_ts = RV_SUB_ITS ; sret_tl = RV_SUB_ITL }
  }
  srbn := base_type_name(src, sret_ts, sret_tl)
  mut sret_extra := 0
  hassret := ((not isgen) or inst) and srbn.n != 0 and rv_ret_sret_words(decls, src, srbn.s, srbn.n, a) >= 1
  ## WIDE-ENUM SRET (> 8 words): a fn returning an enum wider than the 8-register budget also delivers via
  ## the LP64 indirect result, so it needs the SAME a0-spill slot (sret_extra = 1) PLUS a scratch block
  ## sized to the enum's full {disc, payload…} width, where a `return E.V(…)` literal is materialized before
  ## the word-copy through the destination. Generic instances use the same concrete substituted span.
  hasesret := ((not isgen) or inst) and srbn.n != 0 and rv_ret_enum_sret_words(decls, src, srbn.s, srbn.n, a) >= 1
  mut esret_w := 0
  if hasesret { esret_w = rv_ret_enum_sret_words(decls, src, srbn.s, srbn.n, a) }
  anysret := hassret or hasesret
  if anysret { sret_extra = 1 }
  ## frame = saved {s0, ra} (16 bytes) + one word per param/local slot + slice-arg + aggregate-value blocks
  ## + match-temp + the SRET pointer slot + the wide-enum scratch, /16.
  mut frame := 16 + (pcount + nloc + 2 * nsargs + naggw + mtmp + sret_extra + esret_w) * 8
  if frame % 16 != 0 { frame = frame + 8 }
  ## the SRET pointer slot sits ABOVE the match-temp region (only reserved when anysret). Kept in a LOCAL
  ## for the prologue store below — a global read mis-lowers in this very large fn (see the a64 twin).
  sret_slot := 16 + (pcount + nloc + 2 * nsargs + naggw + mtmp) * 8
  RV_SRET_SLOT = sret_slot
  ## the wide-enum materialization scratch sits right ABOVE the a0-spill slot (read only by the enum branch
  ## of emit_rv_sret_store); its byte offset stays consistent with the frame computed above.
  RV_ENUM_SRET_BLK = 16 + (pcount + nloc + 2 * nsargs + naggw + mtmp + sret_extra) * 8
  ## the agg region begins right ABOVE the locals (slice-arg blocks then aggregate-value blocks share the
  ## RV_AGG bump allocator); the match-temp region sits above that, up to RV_AGG_LIM.
  RV_AGG = 16 + (pcount + nloc) * 8
  RV_AGG_LIM = 16 + (pcount + nloc + 2 * nsargs + naggw) * 8
  RV_MTMP = 16 + (pcount + nloc + 2 * nsargs + naggw) * 8
  ## `@abi(naked)` (spec ch.80): label + raw body (asm() lines) + trailing value only; no prologue/epilogue.
  if rv_fn_is_naked(src, d.name_start, d.name_len) {
    emit_rv_export(sb, src, d.name_start, d.name_len)
    if d.kind == 5 { push_str(sb, "__test") ; push_int(sb, i64(RV_TEST_DECL_INDEX)) } else if d.name_len == 0 { rv_emit_lambda_label(sb, src, d.mod_start, d.mod_len, d.name_start) } else { push_str(sb, fname) } ; push_str(sb, ":\n")
    emit_rv_stmts(d.body_stmts, sb, a, src, ephead, pcount, d.body_stmts, decls, frame, 0, 0)
    if not ex_is_no_tail(d.value) { emit_rv_expr(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    return
  }
  ## GENERICS (§8 mono): a generic instance whose RETURN type IS the type-param `T` returns the concrete
  ## instance type — substitute the return span so the struct/enum-return ABI classification below fires.
  ## Gated on an active substitution + an exact type-param match (inline BYTE compare, not streq — which
  ## mis-lowers in this very large fn), so a non-instance / non-`T` return keeps rts = d.ret_ts.
  mut rts := d.ret_ts
  mut rtl := d.ret_tl
  if inst {
    if RV_SUB_GPL != 0 {
      if d.ret_tl == RV_SUB_GPL {
        rbs := bytes(str_at((src + d.ret_ts), d.ret_tl))
        gbs := bytes(str_at((src + RV_SUB_GPS), RV_SUB_GPL))
        mut alleq := true
        mut bi := 0
        while bi < d.ret_tl { if rbs[bi] != gbs[bi] { alleq = false } ; bi = bi + 1 }
        if alleq { rts = RV_SUB_ITS ; rtl = RV_SUB_ITL }
      }
    }
  }
  ## FLOAT ABI (SysV/RV): float params arrive in fa0–fa7, integer params in a0–a7 (INDEPENDENT counters),
  ## float return in fa0 (RV_RET_FLOAT drives the epilogue a0→fa0). The prologue spills each param from
  ## its class register (float `fsd fa<fidx>`, int `sd a<iidx>`) to its frame slot.
  RV_RET_FLOAT = scalar_name_is_float(src, rts, rtl)
  ## STRUCT-RETURN convention (§8 piece 2): record the returned all-scalar 1..8-word struct span so
  ## Return / trailing-value deliver word k → a_k (via emit_rv_struct_value). Otherwise 0/0.
  RV_RET_STRUCT_NS = 0
  RV_RET_STRUCT_NL = 0
  rsbn := base_type_name(src, rts, rtl)
  if rsbn.n != 0 and rv_ret_struct_words(decls, src, rsbn.s, rsbn.n, a) >= 1 { RV_RET_STRUCT_NS = rsbn.s ; RV_RET_STRUCT_NL = rsbn.n }
  if rv_fn_returns_tuple(d, src) {
    tw := rv_tuple_words(src, rts, rtl)
    if tw >= 1 and tw <= 7 { RV_RET_STRUCT_NS = rts ; RV_RET_STRUCT_NL = rtl }
  }
  ## ENUM-RETURN convention (§8 piece 3): a fn returning an enum of 1..8 words delivers disc+payload → a_k.
  RV_RET_ENUM_NS = 0
  RV_RET_ENUM_NL = 0
  if rsbn.n != 0 and enum_decl_of(decls, src, rsbn.s, rsbn.n) >= 0 {
    rew := 1 + i64(enum_max_arity(decls, src, rsbn.s, rsbn.n, a))
    if rew >= 1 and rew <= 8 { RV_RET_ENUM_NS = rsbn.s ; RV_RET_ENUM_NL = rsbn.n }
  }
  ## WIDE-STRUCT SRET (LP64 indirect result): Return / trailing-value write THROUGH the caller's pointer
  ## (emit_rv_sret_store). `hassret` was decided above, so the reserved slot always exists when this fires;
  ## the > 8-word split makes it mutually exclusive with the register struct-return above.
  RV_RET_SRET_NS = 0
  RV_RET_SRET_NL = 0
  if hassret { RV_RET_SRET_NS = srbn.s ; RV_RET_SRET_NL = srbn.n }
  ## a WIDE ENUM rides the SAME RV_RET_SRET span — emit_rv_sret_store's enum branch distinguishes it by
  ## enum_decl_of. Disjoint from RV_RET_ENUM above (the ≤8-word register gate) and from the wide-struct case
  ## (rv_ret_sret_words is struct-only), so at most one of the three return conventions fires per fn.
  if hasesret { RV_RET_SRET_NS = srbn.s ; RV_RET_SRET_NL = srbn.n }
  if inst {
    ## GENERICS (§8): the instance label `<fn>__<tag>` (bare-name scheme; no @export on an instance).
    ## Emitted INLINE (reading RV_SUB_ITS/ITL directly) — a span-through-params helper is miscompiled by
    ## the frozen seed (the type-arg args arrive as stack garbage).
    push_str(sb, str_at((src + d.name_start), d.name_len))
    push_str(sb, "__")
    ## type TAG, INLINE: TUPLE `(T0,…)` → `Tuple_<T0>_…`; ARRAY `[E;N]` → `Array_<E>_<N>`; else bare name.
    if str_at((src + RV_SUB_ITS), 1) == "[" {
      push_str(sb, "Array_")
      mut adep := 0
      mut asemi := RV_SUB_ITS + 1
      mut ap := RV_SUB_ITS + 1
      mut ago := true
      while ago and ap < RV_SUB_ITS + RV_SUB_ITL {
        ac := str_at((src + ap), 1)
        if ac == "(" or ac == "[" { adep = adep + 1 }
        else if (ac == ")" or ac == "]") and adep > 0 { adep = adep - 1 }
        else if ac == ";" and adep == 0 { asemi = ap ; ago = false }
        ap = ap + 1
      }
      mut aes := RV_SUB_ITS + 1
      while aes < asemi and str_at((src + aes), 1) == " " { aes = aes + 1 }
      mut aet := asemi
      while aet > aes and str_at((src + aet - 1), 1) == " " { aet = aet - 1 }
      push_str(sb, str_at((src + aes), aet - aes))
      push_str(sb, "_")
      mut alp := asemi + 1
      while alp < RV_SUB_ITS + RV_SUB_ITL {
        alc := str_at((src + alp), 1)
        if alc != " " and alc != "]" { push_str(sb, alc) }
        alp = alp + 1
      }
    } else if str_at((src + RV_SUB_ITS), 1) == "(" {
      push_str(sb, "Tuple")
      mut ddepth := 0
      mut dcs := RV_SUB_ITS + 1
      mut dp := RV_SUB_ITS + 1
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
      push_str(sb, str_at((src + RV_SUB_ITS), RV_SUB_ITL))
    }
    ## MULTI type-param: append `__<2nd>` / `__<3rd>` (bare scalar names) — matches the call-site tag.
    if RV_SUB_ITL2 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + RV_SUB_ITS2), RV_SUB_ITL2)) }
    if RV_SUB_ITL3 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + RV_SUB_ITS3), RV_SUB_ITL3)) }
    push_str(sb, ":\n")
  } else {
    emit_rv_export(sb, src, d.name_start, d.name_len)
    if d.kind == 5 { push_str(sb, "__test") ; push_int(sb, i64(RV_TEST_DECL_INDEX)) } else if d.name_len == 0 { rv_emit_lambda_label(sb, src, d.mod_start, d.mod_len, d.name_start) } else { push_str(sb, fname) } ; push_str(sb, ":\n")
  }
  push_str(sb, "  addi sp, sp, -") ; push_int(sb, frame) ; push_str(sb, "\n")
  push_str(sb, "  sd ra, 8(sp)\n  sd s0, 0(sp)\n  mv s0, sp\n")
  ## >8 args of a class OVERFLOW to the caller's outgoing stack block; at entry those bytes were at
  ## [old_sp + k*8], and old_sp = s0 + frame, so a stack param is read at [frame + k*8](s0) (k = source
  ## order among overflow params) — a raw 8-byte word (class-agnostic; a float's bits ride a GPR).
  ## WIDE-STRUCT SRET: spill the incoming indirect-result pointer (a0) to its reserved slot FIRST, and
  ## shift every INTEGER param one register up (a0 carries the destination, real args land in a1..a7).
  ## Uses the `sret_slot` LOCAL (a global read here mis-lowers in this very large fn).
  mut p_shift := 0
  if anysret { push_str(sb, "  sd a0, ") ; push_int(sb, sret_slot) ; push_str(sb, "(s0)\n") ; p_shift = 1 }
  mut pi := 0
  mut p_iidx := 0
  mut p_fidx := 0
  mut p_k := 0
  while pi < pcount {
    ## a NON-LEADING comptime type-param (pi == rv_tp_skip) consumes NO incoming register and has no
    ## spill; the register counters skip past it. FLAT ifs — this is a very large fn.
    skipp := i64(pi) == rv_tp_skip
    isfp := rv_param_is_float(ephead, src, pi, a)
    fromreg := (isfp and p_fidx < 8) or ((not isfp) and (p_iidx + p_shift) < 8)
    if (not skipp) and isfp and p_fidx < 8 { push_str(sb, "  fsd fa") ; push_int(sb, p_fidx) ; push_str(sb, ", ") ; push_int(sb, 16 + pi * 8) ; push_str(sb, "(s0)\n") }
    if (not skipp) and (not isfp) and (p_iidx + p_shift) < 8 { push_str(sb, "  sd a") ; push_int(sb, p_iidx + p_shift) ; push_str(sb, ", ") ; push_int(sb, 16 + pi * 8) ; push_str(sb, "(s0)\n") }
    if (not skipp) and (not fromreg) { push_str(sb, "  ld t1, ") ; push_int(sb, frame + p_k * 8) ; push_str(sb, "(s0)\n  sd t1, ") ; push_int(sb, 16 + pi * 8) ; push_str(sb, "(s0)\n") ; p_k += 1 }
    if (not skipp) and isfp { p_fidx += 1 }
    if (not skipp) and (not isfp) { p_iidx += 1 }
    pi += 1
  }
  void := d.ret_tl == 0
  emit_rv_stmts(d.body_stmts, sb, a, src, ephead, pcount, d.body_stmts, decls, frame, 0, 0)
  ## skip the no-tail sentinel (a tail statement, e.g. a match, already left the value in a0).
  if (not void) and (not ex_is_no_tail(d.value)) {
    ## a struct-returning fn delivers word k → a_k (§8 piece 2); an enum-returning fn delivers disc+payload
    ## (§8 piece 3); otherwise the scalar emit.
    if RV_RET_STRUCT_NL != 0 { emit_rv_struct_value(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    if RV_RET_ENUM_NL != 0 { emit_rv_enum_value(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    ## a WIDE-struct (SRET) fn's TRAILING value delivers through the LP64 indirect-result pointer too.
    if RV_RET_SRET_NL != 0 { emit_rv_sret_store(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    if RV_RET_STRUCT_NL == 0 and RV_RET_ENUM_NL == 0 and RV_RET_SRET_NL == 0 { emit_rv_expr(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
  }
  ## A void function can still end in a side-effecting call: the parser stores the final expression in
  ## Decl.value, while the value-return path above is intentionally skipped for void. Execute that tail;
  ## discarding its a0 result is correct, and dropping the call is a silent ABI-visible miscompile.
  if void and (not ex_is_no_tail(d.value)) {
    vrs := rv_call_ret_sret_span(d.value, decls, src, a)
    vre := rv_call_ret_enum_sret_span(d.value, decls, src, a)
    if vrs.n != 0 or vre.n != 0 { emit_rv_sret_discard(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
    if vrs.n == 0 and vre.n == 0 { emit_rv_expr(d.value, sb, a, src, ephead, pcount, d.body_stmts, decls, 0, 0) }
  }
  emit_rv_epilogue(frame, sb)
  RV_SUB_GPS = 0
  RV_SUB_GPL = 0
}

## If `e` is a print/println(StrLit) call, emit its `.Lstr<lbl>` data.
rv_str_data_if_print := fn(e : ptr(Expr), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  match deref(e) {
    Expr::Call(cs, cl, nargs, args_head) => {
      nm := str_at((src + cs), cl)
      ispln := nm == "println"
      isp := (nm == "print" or ispln) and args_head != 0
      mut sarg := unchecked bitcast(ptr(Expr), 0)
      if args_head != 0 { ga := deref(arg_p(args_head)) ; sarg = ga.e }
      ok := isp and rv_is_strlit(sarg)
      if ok { emit_rv_str_bytes(sb, src, rv_strlit_ss(sarg), rv_strlit_sl(sarg), rv_strlit_lbl(sarg)) }
    }
    _ => {}
  }
}
emit_rv_str_data := fn(list : ptr(mut Stmt), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  mut s := list
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::ExprStmt(e, nx) => { rv_str_data_if_print(e, sb, src, a) ; s = nx }
      Stmt::While(c, b, nx) => { emit_rv_str_data(b, sb, src, a) ; s = nx }
      Stmt::If(c, th, el, nx) => { emit_rv_str_data(th, sb, src, a) ; emit_rv_str_data(el, sb, src, a) ; s = nx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; emit_rv_str_data(am.body_stmts, sb, src, a) ; arm = am.next } ; s = mnx }
      Stmt::Assign(ns, nl, v, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, _ifv, ifnx) => { s = ifnx }
      Stmt::FieldPathAssign(_fpp, _fpv, fpnx) => { s = fpnx }
      Stmt::DerefAssign(_dpe, _dval, dnx) => { s = dnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { emit_rv_str_data(fb, sb, src, a) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { emit_rv_str_data(rb, sb, src, a) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { emit_rv_str_data(th, sb, src, a) ; emit_rv_str_data(el, sb, src, a) ; s = nx }
      Stmt::Loop(lb, lnx) => { emit_rv_str_data(lb, sb, src, a) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { emit_rv_str_data(ub, sb, src, a) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
}

## FLOAT rodata: `.Lflt<start>: .double <text>` for every FloatLit reachable from `e`.
emit_rv_float_data_expr := fn(e : ptr(Expr), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  match deref(e) {
    Expr::FloatLit(fs, fl) => { if rv_flt_first(fs) { push_str(sb, ".align 3\n.Lflt") ; push_int(sb, i64(fs)) ; push_str(sb, ":\n  .double ") ; push_str(sb, str_at((src + fs), fl)) ; push_str(sb, "\n") } }
    Expr::Bin(op, l, r) => { emit_rv_float_data_expr(l, sb, src, a) ; emit_rv_float_data_expr(r, sb, src, a) }
    Expr::If(c, t, f) => { emit_rv_float_data_expr(c, sb, src, a) ; emit_rv_float_data_expr(t, sb, src, a) ; emit_rv_float_data_expr(f, sb, src, a) }
    Expr::Call(cs, cl, n, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; emit_rv_float_data_expr(ga.e, sb, src, a) ; g = ga.next } }
    Expr::Field(base, fs, fl) => { emit_rv_float_data_expr(base, sb, src, a) }
    Expr::Index(base, idx) => { emit_rv_float_data_expr(base, sb, src, a) ; emit_rv_float_data_expr(idx, sb, src, a) }
    Expr::Unchecked(inner) => { emit_rv_float_data_expr(inner, sb, src, a) }
    ## FloatLits inside a struct / array / enum LITERAL — recurse so their `.Lflt` cells emit.
    Expr::StructLit(ss, sl, nf, fh) => { mut g := fh ; while g != 0 { ga := deref(arg_p(g)) ; emit_rv_float_data_expr(ga.e, sb, src, a) ; g = ga.next } }
    Expr::ArrayLit(nel, eh) => { mut g := eh ; while g != 0 { ga := deref(arg_p(g)) ; emit_rv_float_data_expr(ga.e, sb, src, a) ; g = ga.next } }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { mut g := ph ; while g != 0 { ga := deref(arg_p(g)) ; emit_rv_float_data_expr(ga.e, sb, src, a) ; g = ga.next } }
    _ => {}
  }
}
emit_rv_float_data := fn(list : ptr(mut Stmt), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  mut s := list
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { emit_rv_float_data_expr(v, sb, src, a) ; s = nx }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { emit_rv_float_data_expr(rv, sb, src, a) } ; s = nx }
      Stmt::ExprStmt(e, nx) => { emit_rv_float_data_expr(e, sb, src, a) ; s = nx }
      Stmt::While(c, b, nx) => { emit_rv_float_data_expr(c, sb, src, a) ; emit_rv_float_data(b, sb, src, a) ; s = nx }
      Stmt::If(c, th, el, nx) => { emit_rv_float_data_expr(c, sb, src, a) ; emit_rv_float_data(th, sb, src, a) ; emit_rv_float_data(el, sb, src, a) ; s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { emit_rv_float_data_expr(fv, sb, src, a) ; s = nx }
      Stmt::IndexFieldAssign(_ifb, _ifi, _iffs, _iffl, ifv, ifnx) => { emit_rv_float_data_expr(ifv, sb, src, a) ; s = ifnx }
      Stmt::IndexAssign(ib, ii, iv, nx) => { emit_rv_float_data_expr(iv, sb, src, a) ; s = nx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 { am := deref(arm_p(arm)) ; emit_rv_float_data(am.body_stmts, sb, src, a) ; arm = am.next } ; s = mnx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { emit_rv_float_data_expr(flo, sb, src, a) ; if unchecked bitcast(usize, fhi) != 0 { emit_rv_float_data_expr(fhi, sb, src, a) } ; emit_rv_float_data(fb, sb, src, a) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { emit_rv_float_data_expr(rlo, sb, src, a) ; if unchecked bitcast(usize, rhi) != 0 { emit_rv_float_data_expr(rhi, sb, src, a) } ; emit_rv_float_data(rb, sb, src, a) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { emit_rv_float_data(th, sb, src, a) ; emit_rv_float_data(el, sb, src, a) ; s = nx }
      Stmt::Loop(lb, lnx) => { emit_rv_float_data(lb, sb, src, a) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { emit_rv_float_data(ub, sb, src, a) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      _ => { s = 0 }
    }
  }
}

## TOOL-5 — the cross-target test filter and the scalar Result return convention mirror the AArch64
## runner. Each selected test is emitted with the original declaration index as its synthetic label.
rv_test_selected := fn(src : ptr(u8), start : usize, len : usize) -> bool {
  if RV_TEST_FILTER_N == 0 { return true }
  desc := str_at((src + start), len)
  needle := str_at(unchecked bitcast(ptr(u8), RV_TEST_FILTER_P), RV_TEST_FILTER_N)
  if needle.len > desc.len { return false }
  mut i := 0
  while i + needle.len <= desc.len {
    if str_at(unchecked bitcast(usize, desc.ptr) + i, needle.len) == needle { return true }
    i += 1
  }
  false
}

rv_test_is_result := fn(src : ptr(u8), d : Decl) -> bool {
  if d.ret_tl < 6 { return false }
  str_at((src + d.ret_ts), 6) == "Result"
}

rv_emit_test_desc := fn(in out sb : rt::StrBuf, src : ptr(u8), start : usize, len : usize, idx : usize) {
  push_str(sb, ".Lrvtestdesc") ; push_int(sb, i64(idx)) ; push_str(sb, ":\n  .byte ")
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

rv_emit_test_report := fn(in out sb : rt::StrBuf, idx : usize, dlen : usize, kind : usize) {
  push_str(sb, "  li a0, 1\n  la a1, .Lrvtestprefix\n  li a2, 5\n  li a7, 64\n  ecall\n  li a0, 1\n  la a1, .Lrvtestdesc") ; push_int(sb, i64(idx))
  push_str(sb, "\n  li a2, ") ; push_int(sb, i64(dlen)) ; push_str(sb, "\n  li a7, 64\n  ecall\n  li a0, 1\n  la a1, .Lrvtest")
  if kind == 0 { push_str(sb, "ok") }
  if kind == 1 { push_str(sb, "soft") }
  if kind == 2 { push_str(sb, "trap") }
  push_str(sb, "\n  li a2, ")
  if kind == 0 { push_int(sb, i64(5)) }
  if kind != 0 { push_int(sb, i64(14)) }
  push_str(sb, "\n  li a7, 64\n  ecall\n")
}

## A sequential RV64 Linux runner. `clone(SIGCHLD)` supplies the same one-child isolation contract as
## the native runner; wait4 status is decoded before the next test is launched.
rv_emit_test_runner := fn(decls : ptr(rt::Vec), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  push_str(sb, ".section .rodata\n.Lrvtestprefix: .byte 116, 101, 115, 116, 32\n.Lrvtestok: .byte 58, 32, 111, 107, 10\n.Lrvtestsoft: .byte 58, 32, 70, 65, 73, 76, 32, 40, 115, 111, 102, 116, 41, 10\n.Lrvtesttrap: .byte 58, 32, 70, 65, 73, 76, 32, 40, 116, 114, 97, 112, 41, 10\n")
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 5 and rv_test_selected(src, d.name_start, d.name_len) { rv_emit_test_desc(sb, src, d.name_start, d.name_len, i) }
    i += 1
  }
  push_str(sb, ".text\n.global _start\n_start:\n  li s2, 0\n")
  i = 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 5 and rv_test_selected(src, d.name_start, d.name_len) {
      push_str(sb, "  li a0, 17\n  li a1, 0\n  li a2, 0\n  li a3, 0\n  li a4, 0\n  li a7, 220\n  ecall\n  beqz a0, .Lrvchild") ; push_int(sb, i64(i)) ; push_str(sb, "\n  bltz a0, .Lrvforkfail") ; push_int(sb, i64(i)) ; push_str(sb, "\n  mv s3, a0\n  addi sp, sp, -16\n  mv a0, s3\n  mv a1, sp\n  li a2, 0\n  li a3, 0\n  li a7, 260\n  ecall\n  bltz a0, .Lrvwaitfail") ; push_int(sb, i64(i)) ; push_str(sb, "\n  ld t0, 0(sp)\n  addi sp, sp, 16\n  andi t1, t0, 127\n  bnez t1, .Lrvtrap") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      if rv_test_is_result(src, d) {
        push_str(sb, "  srli t1, t0, 8\n  andi t1, t1, 255\n  bnez t1, .Lrvsoft") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      }
      rv_emit_test_report(sb, i, d.name_len, 0)
      push_str(sb, "  j .Lrvnext") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      push_str(sb, ".Lrvsoft") ; push_int(sb, i64(i)) ; push_str(sb, ":\n")
      rv_emit_test_report(sb, i, d.name_len, 1)
      push_str(sb, "  addi s2, s2, 1\n")
      if not RV_TEST_KEEP { push_str(sb, "  j .Lrvdone\n") } else { push_str(sb, "  j .Lrvnext") ; push_int(sb, i64(i)) ; push_str(sb, "\n") }
      push_str(sb, ".Lrvtrap") ; push_int(sb, i64(i)) ; push_str(sb, ":\n")
      rv_emit_test_report(sb, i, d.name_len, 2)
      push_str(sb, "  addi s2, s2, 1\n")
      if not RV_TEST_KEEP { push_str(sb, "  j .Lrvdone\n") } else { push_str(sb, "  j .Lrvnext") ; push_int(sb, i64(i)) ; push_str(sb, "\n") }
      push_str(sb, ".Lrvforkfail") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  j .Lrvtrap") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      push_str(sb, ".Lrvwaitfail") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  addi sp, sp, 16\n  j .Lrvtrap") ; push_int(sb, i64(i)) ; push_str(sb, "\n")
      push_str(sb, ".Lrvchild") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  call __test") ; push_int(sb, i64(i))
      if rv_test_is_result(src, d) {
        push_str(sb, "\n  beqz a0, .Lrvchildok") ; push_int(sb, i64(i)) ; push_str(sb, "\n  li a0, 1\n  j .Lrvchildexit") ; push_int(sb, i64(i)) ; push_str(sb, "\n.Lrvchildok") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  li a0, 0\n")
      } else { push_str(sb, "\n  li a0, 0\n") }
      push_str(sb, ".Lrvchildexit") ; push_int(sb, i64(i)) ; push_str(sb, ":\n  li a7, 93\n  ecall\n")
      push_str(sb, ".Lrvnext") ; push_int(sb, i64(i)) ; push_str(sb, ":\n")
    }
    i += 1
  }
  push_str(sb, ".Lrvdone:\n  mv a0, s2\n  li a7, 93\n  ecall\n")
}

## Emit a complete runnable RV64 GAS program: `_start` (call main, exit(a0)) + every fn + `.data`.
pub emit_rv_program := fn(decls : ptr(rt::Vec), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  ## COMPTIME `when`-GUARD gating (Comptime §7.1/§9; CT-5) — BEFORE any callee resolution or emission,
  ## exactly where x86 `lower::emit_program` runs it. A decl gated on another arch is neutered to an
  ## as-if-absent no-op here, so an arch-gated raw-`asm` body (`lib/std/thread.al`) never reaches `as`.
  apply_when_guards(decls, src, rv_target_arch())
  ## Each program emission gets a fresh deterministic label namespace. Within it, rv_next_label remains
  ## monotonic across functions, nested control flow, and generic re-emission.
  RV_NL = 0
  ## `_start`: initialise the RISC-V GLOBAL POINTER `gp` before anything else, then call main and exit.
  ## The linker RELAXES a nearby `la sym` into gp-relative `addi rd, gp, off`; without gp set that
  ## dereferences garbage and segfaults (module_const's HEIGHT read). The `.option norelax` around the
  ## gp-load is mandatory — otherwise the linker relaxes the gp setup itself into nonsense.
  if RV_TEST_MODE { rv_emit_test_runner(decls, sb, src, a) }
  if not RV_TEST_MODE { push_str(sb, ".text\n.global _start\n_start:\n.option push\n.option norelax\n  la gp, __global_pointer$\n.option pop\n  call main\n  li a7, 93\n  ecall\n") }
  cnt := rt::vec_len(deref(decls))
  ## GENERICS (§8 mono): instances are RECORDED DURING EMIT — every generic CALL site (emit_rv_expr)
  ## resolves its type-arg and appends via rv_inst_add (dedup) into the fixed RV_INST_* arrays.
  ## Emitting the non-generic fns seeds the set; the mono loop below emits each instance, and an
  ## instance's own generic calls append further instances (transitive), the loop re-reading RV_INST_N.
  RV_INST_N = 0
  ## the float-literal pool is per PROGRAM, like the instance set (see RV_FLT_OFF).
  RV_FLT_N = 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 or (RV_TEST_MODE and d.kind == 5 and rv_test_selected(src, d.name_start, d.name_len)) {
      if d.kind == 5 { RV_TEST_DECL_INDEX = i }
      emit_rv_fn(d, sb, a, src, decls)
    }
    i += 1
  }
  ## emit one monomorphized instance per RECORDED (generic-fn, type) pair, with the instance
  ## substitution active (RV_SUB_ITS/ITL); emit_rv_fn skips the leading type-param. The loop re-reads
  ## RV_INST_N so instances discovered while emitting an earlier instance are also emitted.
  mut mi := 0
  while mi < RV_INST_N {
    mgi := RV_INST_GI[mi]
    RV_SUB_ITS = RV_INST_TS[mi]
    RV_SUB_ITL = RV_INST_TL[mi]
    RV_SUB_ITS2 = RV_INST_TS2[mi]
    RV_SUB_ITL2 = RV_INST_TL2[mi]
    RV_SUB_ITS3 = RV_INST_TS3[mi]
    RV_SUB_ITL3 = RV_INST_TL3[mi]
    gdi := deref(decl_get(decls, mgi))
    emit_rv_fn(gdi, sb, a, src, decls)
    RV_SUB_ITS = 0
    RV_SUB_ITL = 0
    RV_SUB_ITS2 = 0
    RV_SUB_ITL2 = 0
    RV_SUB_ITS3 = 0
    RV_SUB_ITL3 = 0
    mi = mi + 1
  }
  ## `__print_u64`: render a0 as unsigned decimal into `.Lnumbuf` (backward) and write it to fd 1.
  ## Numeric local labels (1:/1b); value 0 prints one '0'. RV64 M-extension divu/mul for the digits.
  push_str(sb, "__print_u64:\n  la a3, .Lnumbuf\n  addi a4, a3, 24\n  mv a5, a4\n  li a6, 10\n")
  push_str(sb, "1:\n  divu a7, a0, a6\n  mul t0, a7, a6\n  sub t0, a0, t0\n  addi t0, t0, 48\n  addi a5, a5, -1\n  sb t0, 0(a5)\n  mv a0, a7\n  bnez a0, 1b\n")
  push_str(sb, "  li a0, 1\n  mv a1, a5\n  sub a2, a4, a5\n  li a7, 64\n  ecall\n  ret\n")
  ## `.data`: a print newline byte + a 24-byte itoa buffer, then one `.quad` cell per module-level
  ## SCALAR global (8-byte aligned). Non-scalar globals get no cell → a read falls to the fail-loud ebreak.
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
    ## a FLOAT-valued global — `.data` cell is a `.double`. Null-guard d.value before touching it.
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 {
      if unchecked bitcast(usize, d.value) != 0 {
        if rv_is_floatlit(d.value) {
          gname := str_at((src + d.name_start), d.name_len)
          push_str(sb, ".align 3\n") ; push_str(sb, gname) ; push_str(sb, ":\n  .double ") ; push_str(sb, str_at((src + rv_floatlit_ss(d.value)), rv_floatlit_sl(d.value))) ; push_str(sb, "\n")
        }
      }
    }
    ## an AGGREGATE global (struct/array/enum initializer) — its `.data` cells emitted RECURSIVELY as
    ## ascending 8-byte cells (nested struct fields flattened), addressed by its plain-name label.
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 {
      if unchecked bitcast(usize, d.value) != 0 {
        if rv_value_is_agg(d.value) {
          gname := str_at((src + d.name_start), d.name_len)
          push_str(sb, ".align 3\n") ; push_str(sb, gname) ; push_str(sb, ":\n")
          emit_rv_global_cells(d.value, sb, decls, src, a)
        }
      }
    }
    gi += 1
  }
  mut si := 0
  while si < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), si)))
    if d.kind == 1 { emit_rv_str_data(d.body_stmts, sb, src, a) }
    si += 1
  }
  ## FLOAT rodata — one `.Lflt<start>: .double` cell per FloatLit in every fn body. The walk MUST
  ## cover the TRAILING RETURN EXPRESSION (`d.value`) as well as the statement list: a fn whose whole
  ## body IS an expression has an EMPTY `body_stmts`, so its FloatLits had no cell emitted at all
  ## while `emit_rv_expr`'s FloatLit arm still emitted `la t0, .Lflt<start>` — every `math_*` test
  ## then died at `ld` on an undefined `.Lflt…` coming out of `std::math::abs`
  ## (`fn(x : f64) -> f64 { if x < 0.0 { 0.0 - x } else { x } }`, a pure trailing `if` expression).
  ## `d.value` is the `Num(-1)` no-tail sentinel when a fn has no trailing expr, and may be null on a
  ## decl that carries no value — both guarded, mirroring `emit_rv_fn`'s own tail emit.
  mut fdi := 0
  while fdi < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), fdi)))
    if d.kind == 1 {
      emit_rv_float_data(d.body_stmts, sb, src, a)
      if unchecked bitcast(usize, d.value) != 0 {
        if not ex_is_no_tail(d.value) { emit_rv_float_data_expr(d.value, sb, src, a) }
      }
    }
    fdi += 1
  }
}
