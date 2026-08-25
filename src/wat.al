## selfhost::wat (backend breadth), item 1: WASM → WAT.
##
## A SECOND backend emitting against the SAME parsed `Decl` model the x86_64 lower consumes
## (`lower::emit_program`), rather than a fork of the front end. Scope (the scalar kernel): every
## function (kind 1) — value-returning (`-> u64`) or void — with `i64` value parameters, module-level
## scalar `mut`/const globals (WASM `global.get`/`global.set`), local `:=` bindings + reassignment,
## expressions over literals (`Num`/`BoolLit`), params/locals/globals (`Var`), arithmetic + comparison
## + boolean `Bin` (uniform i64 value model), value-position `if` (`Expr::If`), direct calls
## (`Call`), statement lists with `while` (block/loop/br_if), statement-`if`, `return` at any depth,
## and call-as-statement (`ExprStmt`, dropping a non-void result), plus scalar `defer` cleanup actions
## including `defer { … }` block forms. It emits a WASI module whose
## exported `_start` calls `$main` and turns the `i64` result into `proc_exit`'s `i32` exit code —
## `wat2wasm` (structural + type validation) then `wasmtime` (exit code, checked like the x86_64 e2e)
## prove the module round-trips. Anything outside the kernel (structs, strings, print, arch
## intrinsics, width casts, nested new `:=`) emits `(unreachable)` — a fail-loud trap, never a
## silently-wrong result.
##
## ADDITIVE: nothing in the self-build invokes `emit_wat_program`, so the x86_64 GAS the tree emits
## for itself is byte-for-byte unchanged and the TOOL-1 fixpoint (seed==Stage1==Stage2) is unaffected.
##
## BREADCRUMB SPELLING — every `(unreachable)` above carries a note saying WHICH construct was out of
## scope, and each one is written in WAT's BLOCK-comment form `(; … ;)`, never the line form. The line
## form was a live defect: a note emitted in EXPRESSION position runs to the end of the LINE, so it
## swallowed the rest of the enclosing s-expression — the call's remaining operands AND its own closing
## paren — leaving the module unbalanced, at which point the next module-level `(func …)` read as a
## continuation of the previous function's body and `wat2wasm` refused the whole file. Six corpus rows
## (the FN-6 §6.2 capturing-closure family) failed to ASSEMBLE for exactly that reason, and the fault
## was not local to the note: whether a note ends a line depends on the CALLER's emission, so a
## line-form note is unsafe at every one of these sites, not just the ones observed failing. The block
## form is closed explicitly, so it is safe in expression AND statement position — a note can never
## again change what the surrounding text means. A trap is an acceptable outcome for an unsupported
## construct; text the assembler refuses is not. (An emit-time REJECT is NOT the alternative here:
## `scripts/wasm_sweep.sh` defines a WAT-emit failure for a program x86_64 accepted as its WRONG
## verdict, so refusing at emit time would turn these rows red rather than green.)
##
## NOTE ordering: the destructure imports come FIRST. A bare-Var alias `x := rt` immediately followed
## by a line starting `(` parses as a CALL `rt(...)` — newlines do not terminate a decl and the
## call-postfix binds across the line. `rt::` is referenced qualified here, so no `strbuf := rt` alias
## is needed; leading with the `(…) :=` destructures sidesteps the glue entirely.
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
variant_payload_type := lower_layout::variant_payload_type
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
field_type_span := lower::field_type_span
compfor_iter_arg := lower::compfor_iter_arg
(CSpan) := lower_ctx

## A typed pointer to a Decl node at absolute handle `h` (the per-module `decl_at`, duplicated per
## module in the self-host tree — mirrors lower.al / driver.al).
decl_at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
## a direct typed accessor for decl `i` (encapsulates the usize-handle recovery).
decl_get := fn(decls : ptr(rt::Vec), i : usize) -> ptr(Decl) { hh := rt::vec_get(deref(decls), i) ; return decl_at(Decl, hh) }

## A typed pointer to an AST node at arena OFFSET `h` (Stmt/Arg/Param handles are offsets into the AST
## arena `a`; `Expr` children carried as `ptr(Expr)` are absolute and deref directly).
node_ptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}

## Span equality over the shared source (the per-module `streq`).
streq := fn(src : ptr(u8), a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool {
  ## `src + a_s`/`src + b_s` are POINTER arithmetic (a span start may be a REBASED handle for a
  ## comptime-synthesized name) → route through `rt::addr`, not a checked integer `+` (I11 / CG-8).
  wa := str_at((src + a_s), a_n)
  wb := str_at((src + b_s), b_n)
  wa == wb
}

## The EXACT linker symbol of a `@export("name")` attribute attached to `[name_s, name_s+name_l)`
## (Modules §6.3), or {0,0}. The parser discards attributes, so recover declaration-prefix and
## value-position `name := [attributes] fn(…)` forms consistently with the GAS/check-side scans.
wat_export_name := fn(src : ptr(u8), name_s : usize, name_l : usize) -> WSpan {
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
                return WSpan(s = es, n = ee - es)
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
  if p < 11 { return WSpan(s = 0, n = 0) }
  if str_at((src + p - 1), 1) != ")" { return WSpan(s = 0, n = 0) }
  clq := p - 2
  if str_at((src + clq), 1) != "\"" { return WSpan(s = 0, n = 0) }
  mut oq := clq
  while oq > 0 and str_at((src + oq - 1), 1) != "\"" { oq = oq - 1 }
  if oq == 0 { return WSpan(s = 0, n = 0) }
  opq := oq - 1
  if opq < 8 { return WSpan(s = 0, n = 0) }
  if str_at((src + opq - 8), 9) != "@export(\"" { return WSpan(s = 0, n = 0) }
  WSpan(s = oq, n = clq - oq)
}

## The EXTERNAL linker symbol a `@extern` fn (declared at `name_s`, length `name_l`) resolves to
## (Modules §7.2): the EXACT `@extern("sym")` name if given, else the DECLARED name, else {0,0} when
## the fn is not `@extern`. The WAT twin of `lower::extern_symbol` — scans FORWARD over `:= @extern`
## (a value-position attribute). Drives the WASM `(import …)` emit + skipping the (bodyless) func.
wat_extern_symbol := fn(src : ptr(u8), name_s : usize, name_l : usize) -> WSpan {
  mut p := name_s + name_l
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return WSpan(s = 0, n = 0) }
  p = p + 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 7) != "@extern" { return WSpan(s = 0, n = 0) }
  mut q := p + 7
  bc := str_at((src + q), 1)
  if not (bc == "(" or bc == " " or bc == "\n" or bc == "\t" or bc == "\r") { return WSpan(s = 0, n = 0) }
  while str_at((src + q), 1) == " " or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t" or str_at((src + q), 1) == "\r" { q = q + 1 }
  if str_at((src + q), 1) == "(" {
    q = q + 1
    while str_at((src + q), 1) == " " or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t" or str_at((src + q), 1) == "\r" { q = q + 1 }
    if str_at((src + q), 1) == "\"" {
      oq := q + 1
      mut clq := oq
      while str_at((src + clq), 1) != "\"" { clq = clq + 1 }
      return WSpan(s = oq, n = clq - oq)
    }
  }
  WSpan(s = name_s, n = name_l)
}

wat_local_ann_signed := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
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
## The `:=` RHS expr of a top-level local (0 if not found) — recovers an un-annotated `b := shr(s, 1)`'s
## signed type from the shift RHS (OP-6: shl/shr/rotl/rotr return the left operand's type). Without this the
## annotation-only signedness read chose `i64.div_u` for `b / 2` → a silent WAT miscompile.
wat_local_rhs := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> ptr(Expr) {
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
wat_shift_call_signed := fn(v : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(v) {
    Expr::Call(cs, cl, na, ah) => {
      cn := str_at((src + cs), cl)
      if cn == "shl" or cn == "shr" or cn == "rotl" or cn == "rotr" { if wat_operand_signed(arg_expr_at(ah, 0, a), params_head, body_head, src, a) { r = true } }
    }
    _ => {}
  }
  r
}
wat_operand_signed := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(e) {
    Expr::Var(s, n) => {
      if param_ann_signed(params_head, src, s, n, a) { r = true }
      if wat_local_ann_signed(body_head, src, s, n, a) { r = true }
      if r == false { rhs := wat_local_rhs(body_head, src, s, n, a); if unchecked bitcast(usize, rhs) != 0 { if wat_shift_call_signed(rhs, params_head, body_head, src, a) { r = true } } }
    }
    Expr::Call(cs, cl, na, ah) => { cn := str_at((src + cs), cl) ; if cn == "i8" or cn == "i16" or cn == "i32" or cn == "i64" or cn == "isize" { r = true } }
    _ => {}
  }
  r
}

wat_local_ann_unsigned := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
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
wat_unchecked_init_unsigned := fn(v : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(v) {
    Expr::Unchecked(inner) => { r = wat_operand_unsigned(inner, params_head, body_head, src, a) }
    _ => {}
  }
  r
}
wat_operand_unsigned := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  mut r := false
  match deref(e) {
    Expr::Var(s, n) => {
      if param_ann_unsigned(params_head, src, s, n, a) { r = true }
      if wat_local_ann_unsigned(body_head, src, s, n, a) { r = true }
      ## un-annotated `s := unchecked (<init>)` — recover the unsignedness the wrapper swallowed
      ## (mirrors the SIGNED side's `wat_shift_call_signed` recovery above).
      if r == false { rhs := wat_local_rhs(body_head, src, s, n, a); if unchecked bitcast(usize, rhs) != 0 { if wat_unchecked_init_unsigned(rhs, params_head, body_head, src, a) { r = true } } }
    }
    Expr::Call(cs, cl, na, ah) => { cn := str_at((src + cs), cl) ; if cn == "u8" or cn == "u16" or cn == "u32" or cn == "u64" or cn == "usize" { r = true } }
    ## The two SHAPES that CARRY an operand's unsignedness but have no annotation of their own, so the
    ## source scan above could never prove them unsigned and the comparison fell back to the always-
    ## SIGNED `i64.lt_s`/`gt_s`/`le_s`/`ge_s` — a `u64` word above 2^63 then ordered as NEGATIVE and
    ## `0 < 18446744073709551610` answered FALSE (a valid module, a non-trap exit, a wrong value):
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
    Expr::Unchecked(inner) => { r = wat_operand_unsigned(inner, params_head, body_head, src, a) }
    Expr::Bin(op, bl, br) => {
      if op == 16 or op == 17 or op == 18 or op == 19 or op == 29 or op == 34 or op == 35 or op == 36 {
        ul := wat_operand_unsigned(bl, params_head, body_head, src, a)
        ur := wat_operand_unsigned(br, params_head, body_head, src, a)
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
wat_cmp_unsigned := fn(l : ptr(Expr), r : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> bool {
  ul := wat_operand_unsigned(l, params_head, body_head, src, a)
  ur := wat_operand_unsigned(r, params_head, body_head, src, a)
  if ul and ur { return true }
  if ul and ex_is_num_lit(r) { return true }
  if ur and ex_is_num_lit(l) { return true }
  false
}
wat_local_narrow := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> str {
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
wat_operand_narrow := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena) -> str {
  mut r := ""
  match deref(e) {
    Expr::Var(s, n) => {
      mut p := params_head
      while p != 0 { pm := deref(param_p(p)) ; if streq(src, pm.ns, pm.nl, s, n) { nn := scalar_name_narrow(src, pm.ts, pm.tl) ; if nn != "" { r = nn } } ; p = pm.next }
      if r == "" { r = wat_local_narrow(body_head, src, s, n, a) }
    }
    Expr::Call(cs, cl, na, ah) => { r = scalar_name_narrow(src, cs, cl) }
    _ => {}
  }
  r
}

wat_binop := fn(op : u8, dsigned : bool) -> str {
  if op == 16 { return "i64.add" }
  if op == 17 { return "i64.sub" }
  if op == 18 { return "i64.mul" }
  ## `/` (19) / `%` (29): SIGNED only when an operand is a known `iN`; else UNSIGNED (Alatyr default) —
  ## formerly always `..._s`, reading a high-bit `u64` as negative (a silent wrong result vs x86_64).
  if op == 19 { if dsigned { return "i64.div_s" } ; return "i64.div_u" }
  if op == 29 { if dsigned { return "i64.rem_s" } ; return "i64.rem_u" }
  if op == 34 { return "i64.and" }
  if op == 35 { return "i64.or" }
  if op == 36 { return "i64.xor" }
  if op == 40 { return "i64.and" }
  if op == 41 { return "i64.or" }
  return "i64.add"
}

## The S-expression PREFIX / SUFFIX that wrap a conversion `name(x)`'s argument to narrow it (mirrors
## x86_64 emit_int_narrow_reg): a `uN` masks the low N bits (`i64.and … (i64.const 2^N-1)`), an `iN`
## sign-extends (`i64.extendN_s`). Native widths (u64/i64/usize/isize) return "" → the arg passes through.
wat_narrow_pre := fn(name : str) -> str {
  if name == "u8" or name == "u16" or name == "u32" { return "(i64.and " }
  if name == "i8" { return "(i64.extend8_s " }
  if name == "i16" { return "(i64.extend16_s " }
  if name == "i32" { return "(i64.extend32_s " }
  ""
}
wat_narrow_post := fn(name : str) -> str {
  if name == "u8" { return " (i64.const 255))" }
  if name == "u16" { return " (i64.const 65535))" }
  if name == "u32" { return " (i64.const 4294967295))" }
  if name == "i8" or name == "i16" or name == "i32" { return ")" }
  ""
}
## CHECKED narrow-width OVERFLOW check for WAT (I11 / CG-6/CG-8) — the WASM dual: the value in
## `$__ovo` must fit the narrow type, else `(unreachable)`. UNSIGNED `uN` overflows iff any bit above
## bit N is set (`shr_u` nonzero); SIGNED `iN` iff the sign-extension of the low N bits differs.
wat_narrow_trap_check := fn(name : str) -> str {
  if name == "u8" { return " (if (i64.ne (i64.shr_u (global.get $__ovo) (i64.const 8)) (i64.const 0)) (then (unreachable)))" }
  if name == "u16" { return " (if (i64.ne (i64.shr_u (global.get $__ovo) (i64.const 16)) (i64.const 0)) (then (unreachable)))" }
  if name == "u32" { return " (if (i64.ne (i64.shr_u (global.get $__ovo) (i64.const 32)) (i64.const 0)) (then (unreachable)))" }
  if name == "i8" { return " (if (i64.ne (i64.extend8_s (global.get $__ovo)) (global.get $__ovo)) (then (unreachable)))" }
  if name == "i16" { return " (if (i64.ne (i64.extend16_s (global.get $__ovo)) (global.get $__ovo)) (then (unreachable)))" }
  if name == "i32" { return " (if (i64.ne (i64.extend32_s (global.get $__ovo)) (global.get $__ovo)) (then (unreachable)))" }
  ""
}

## Does `op` have a WASM stack-op in `wat_binop`? Guards the Bin arm so an UNHANDLED op traps
## (fail-loud) instead of silently defaulting to i64.add (the language has no shifts; the bindable
## operator set is otherwise arithmetic/bitwise/boolean, all listed here).
is_arith_op := fn(op : u8) -> bool {
  op == 16 or op == 17 or op == 18 or op == 19 or op == 29 or op == 34 or op == 35 or op == 36 or op == 40 or op == 41
}


## The SOURCE GLYPH a comparison op byte was written as — the NAME a user operator-overload decl
## (`@inline < := fn(a : Ver, b : Ver) -> u64`) carries, and hence the WASM function id it is emitted
## under (`emit_wat_fn` uses the decl name verbatim). "" for a non-comparison op.
wat_cmp_glyph := fn(op : u8) -> str {
  if op == 20 { return "==" }
  if op == 24 { return "<" }
  if op == 25 { return ">" }
  if op == 26 { return "<=" }
  if op == 27 { return ">=" }
  if op == 28 { return "!=" }
  return ""
}

## Is there a user OPERATOR-OVERLOAD fn decl named exactly the glyph `g` whose FIRST parameter is
## declared with the struct type `[ss,sn)`? (Stdlib §2 operator overloading.) The type match is what
## keeps an unrelated overload from capturing a comparison over a different struct.
wat_op_fn_match := fn(decls : ptr(rt::Vec), src : ptr(u8), g : str, ss : usize, sn : usize) -> bool {
  if sn == 0 { return false }
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut found := false
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 {
      if str_at((src + d.name_start), d.name_len) == g {
        p0 := d.params_head
        if unchecked bitcast(usize, p0) != 0 {
          pm := deref(param_p(p0))
          if streq(src, pm.ts, pm.tl, ss, sn) { found = true }
        }
      }
    }
    i += 1
  }
  found
}

## Is the callee named `[cs, cs+cl)` a SCALAR-TYPE name — i.e. a width conversion `u64(x)`/`u8(x)`/…
## parsed as a Call, not a real function? The i64 kernel does not model narrowing → `(unreachable)`.
is_cast_callee := fn(src : ptr(u8), cs : usize, cl : usize) -> bool {
  nm := str_at((src + cs), cl)
  nm == "u8" or nm == "u16" or nm == "u32" or nm == "u64" or nm == "i8" or nm == "i16" or nm == "i32" or nm == "i64" or nm == "usize" or nm == "isize" or nm == "f64" or nm == "f32"
}

## Is `[ns,nl)` a module-level FLOAT global (a kind-0 decl with a FloatLit init)? WASM float globals are
## NOT modelled (a const-expr forbids `reinterpret`) → their access TRAPS (not mis-treated as a local).
wat_is_float_global := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> bool {
  cnt := rt::vec_len(deref(decls)) ; mut i := 0 ; mut r := false
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    ## a kind-0/arity-0 module global whose value is NOT a modelled scalar (Num/Bool) — i.e. a float
    ## (or otherwise unmodelled) global. Catching it here TRAPS its access instead of the wasm local
    ## collection mis-treating the reassigned name as an uninitialised local (the float_global miscompile).
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 {
      if streq(src, d.name_start, d.name_len, ns, nl) {
        if not ex_value_is_scalar(d.value) { r = true }
      }
    }
    i += 1
  }
  r
}
## The float LITERAL text initialising a float module global declared at `name_s`(len `name_l`).
## Scans FORWARD over `:=`/`=` (like the extern/export scanners) and captures the numeric token
## (digits / `.` / sign / exponent) — its text feeds a WASM `(f64.const …)`. This SOURCE scan
## sidesteps the value-node detection ambiguity (a FloatLit `d.value` reads as non-scalar here but
## did not survive a direct node-match): the literal is recovered verbatim from the source instead.
wat_float_global_init := fn(src : ptr(u8), name_s : usize, name_l : usize) -> WSpan {
  mut p := name_s + name_l
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) == ":=" { p = p + 2 } else if str_at((src + p), 1) == "=" { p = p + 1 } else { return WSpan(s = 0, n = 0) }
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  mut q := p
  mut scanning := true
  while scanning {
    c := str_at((src + q), 1)
    if dec_digit_val(c) >= 0 or c == "." or c == "-" or c == "+" or c == "e" or c == "E" { q = q + 1 } else { scanning = false }
  }
  if q == p { return WSpan(s = 0, n = 0) }
  WSpan(s = p, n = q - p)
}
## True when the float global NAMED at a USE site (`ns`,`nl`) has a recoverable init — i.e. its
## `(mut f64)` cell was emitted, so reads/writes may reinterpret it. The init scan MUST run from the
## DECLARATION (`:=` follows the name only there); a use-site scan sees `+`/`)` and fails. Looks the
## decl up by name, then scans from ITS name_start.
wat_float_global_init_ok := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize) -> bool {
  cnt := rt::vec_len(deref(decls)) ; mut i := 0 ; mut r := false
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 {
      if streq(src, d.name_start, d.name_len, ns, nl) {
        if wat_float_global_init(src, d.name_start, d.name_len).n != 0 { r = true }
      }
    }
    i += 1
  }
  r
}
## Does the LOCAL `[ns,nl)` name a float ARRAY (`xs := [<FloatLit>, …]`)? First element float via the
## shared detector; `done` set only on the array-lit match (mirrors is_array_local).
wat_array_is_float := fn(body_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec)) -> bool {
  mut s := body_head ; mut r := false ; mut done := false
  while s != 0 and (not done) {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) and ex_is_array_lit(v) {
          eh := ex_array_lit_ehead(v)
          if eh != 0 { fe := arg_p(eh) ; if wat_is_float_expr(deref(fe).e, body_head, src, a, params_head, decls, 0) { r = true } }
          done = true
        }
        ## a slice-VIEW binding (`fv := base[lo..hi]`) inherits its backing array's element float-ness —
        ## recurse on the slice base so `fv[i]` reads via the float path (else it mis-reads the bits as int).
        if streq(src, ans, anl, ns, nl) and ex_is_slice(v) {
          bn2 := expr_var_name(ex_slice_base(v))
          if wat_array_is_float(body_head, src, bn2.s, bn2.n, a, params_head, decls) { r = true }
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
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  r
}
wat_is_float_local := fn(body_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec), dep : i64) -> bool {
  if dep > 24 { return false }
  mut r := false
  d := lower_layout::local_decl_assign(body_head, src, ns, nl)
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => {
        if ann_scan_float(src, ans + anl) { r = true }
        if wat_is_float_expr(v, body_head, src, a, params_head, decls, dep + 1) { r = true }
      }
      _ => {}
    }
  }
  r
}
wat_int_const_expr := fn(e : ptr(Expr)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Num(_v, _s, _n) => { r = true }
    Expr::Bin(op, l, rr) => {
      if (op == 16 or op == 17 or op == 18) and wat_int_const_expr(l) and wat_int_const_expr(rr) { r = true }
    }
    _ => {}
  }
  r
}
wat_direct_float_num := fn(e : ptr(Expr), src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut r := false
  if ann_scan_float(src, ns + nl) { if wat_int_const_expr(e) { r = true } }
  r
}
wat_is_float_expr := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, params_head : ptr(mut Param), decls : ptr(rt::Vec), dep : i64) -> bool {
  if dep > 24 { return false }
  mut r := false
  match deref(e) {
    Expr::FloatLit(fs, fl) => { r = true }
    Expr::Var(ns, nl) => {
      if wat_is_float_local(body_head, src, ns, nl, a, params_head, decls, dep + 1) { r = true }
      if named_param_is_float(params_head, src, ns, nl, a) { r = true }
    }
    Expr::Bin(op, l, rr) => {
      if op == 16 or op == 17 or op == 18 or op == 19 {
        if wat_is_float_expr(l, body_head, src, a, params_head, decls, dep + 1) { r = true }
        if wat_is_float_expr(rr, body_head, src, a, params_head, decls, dep + 1) { r = true }
      }
    }
    Expr::Call(cs, cl, n, ah) => { nm := str_at((src + cs), cl) ; if nm == "f64" { r = true } ; if nm == "f32" { r = true } ; if callee_ret_is_float(decls, src, cs, cl) { r = true } }
    ## a struct FIELD of declared type f64/f32.
    Expr::Field(base, fs, fl) => {
      bn := expr_var_name(base)
      if bn.n != 0 {
        styp := base_struct_type(params_head, body_head, src, bn.s, bn.n, a, decls)
        if styp.n != 0 { if field_type_is_float(decls, src, styp.s, styp.n, fs, fl, a) { r = true } }
      }
    }
    ## an ARRAY element `xs[i]` whose array local has float elements.
    Expr::Index(base, idx) => {
      bn := expr_var_name(base)
      if bn.n != 0 { if wat_array_is_float(body_head, src, bn.s, bn.n, a, params_head, decls) { r = true } }
    }
    _ => {}
  }
  r
}
## WASM float op mnemonic for an arith op byte.
wat_fbinop := fn(op : u8) -> str {
  if op == 16 { return "f64.add" }
  if op == 17 { return "f64.sub" }
  if op == 18 { return "f64.mul" }
  return "f64.div"
}

## The WASM (i32-producing) mnemonic for a signed i64 comparison operator byte.
wat_cmpop := fn(op : u8) -> str {
  if op == 20 { return "i64.eq" }
  if op == 24 { return "i64.lt_s" }
  if op == 25 { return "i64.gt_s" }
  if op == 26 { return "i64.le_s" }
  if op == 27 { return "i64.ge_s" }
  if op == 28 { return "i64.ne" }
  return "i64.eq"
}
## UNSIGNED ordering mnemonic — the DUAL of `wat_cmpop`, used when BOTH operands are provably unsigned
## (`wat_cmp_unsigned`): `<`=lt_u, `>`=gt_u, `<=`=le_u, `>=`=ge_u. So a `u64`/`usize` comparison whose
## operands straddle 2^63 (`0 < u64::MAX`) reads TRUE instead of treating the high-bit operand as
## negative. Equality (`eq`/`ne`) is sign-agnostic and unchanged.
wat_ucmpop := fn(op : u8) -> str {
  if op == 20 { return "i64.eq" }
  if op == 24 { return "i64.lt_u" }
  if op == 25 { return "i64.gt_u" }
  if op == 26 { return "i64.le_u" }
  if op == 27 { return "i64.ge_u" }
  if op == 28 { return "i64.ne" }
  return "i64.eq"
}
## WASM f64 comparison mnemonic — all ORDERED (NaN → 0, except `ne` → 1) = correct NaN semantics.
wat_fcmpop := fn(op : u8) -> str {
  if op == 20 { return "f64.eq" }
  if op == 24 { return "f64.lt" }
  if op == 25 { return "f64.gt" }
  if op == 26 { return "f64.le" }
  if op == 27 { return "f64.ge" }
  if op == 28 { return "f64.ne" }
  return "f64.eq"
}


## Number of VALUE parameters of a fn (a comptime `T : type` param occupies no WASM slot → not counted,
## so the local-slot base = value-param count, consistent with param_find / emit_wat_params).
count_params := fn(params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena) -> i64 {
  mut p := params_head
  mut k := 0
  while p != 0 {
    pm := deref(param_p(p))
    if str_at((src + pm.ts), pm.tl) == "type" {} else { k += 1 }
    p = pm.next
  }
  i64(k)
}



## Resolve the concrete type named by a `typeinfo(X)` range-bound expression. The `.fields.len` and
## `.variants.len` forms leave one Field wrapper around the Call; `.n` passes the Call directly. Unlike
## the old range fold, this keeps the explicit X and substitutes whichever active generic parameter it
## names instead of always using WAT_SUB_ITS.
wat_range_typeinfo_arg := fn(base : ptr(Expr), field_s : usize, src : ptr(u8)) -> CSpan {
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
      if WAT_SUB_GPL != 0 and n != 0 and streq(src, s, n, WAT_SUB_GPS, WAT_SUB_GPL) { s = WAT_SUB_ITS ; n = WAT_SUB_ITL }
      else if WAT_SUB_GPL2 != 0 and n != 0 and streq(src, s, n, WAT_SUB_GPS2, WAT_SUB_GPL2) { s = WAT_SUB_ITS2 ; n = WAT_SUB_ITL2 }
      else if WAT_SUB_GPL3 != 0 and n != 0 and streq(src, s, n, WAT_SUB_GPS3, WAT_SUB_GPL3) { s = WAT_SUB_ITS3 ; n = WAT_SUB_ITL3 }
      r = CSpan(s = s, n = n)
    }
  }
  r
}

## The mutability bit of `<f>.mutable` for the ACTIVE comptime field descriptor (Comptime §5.1). Field
## mutability is a source-level marker, so recover it from the current field name exactly as x86 does.
## -1 means this is not an active mutable query; the ordinary field path then remains fail-loud.
wat_cf_mutable_value := fn(e : ptr(Expr), src : ptr(u8)) -> i64 {
  if WAT_CF_VAR_L == 0 { return 0 - 1 }
  match deref(e) {
    Expr::Field(base, fs, fl) => {
      if str_at((src + fs), fl) != "mutable" { return 0 - 1 }
      vn_s := ex_var_ns(base)
      vn_l := ex_var_nl(base)
      if vn_l == 0 or not streq(src, vn_s, vn_l, WAT_CF_VAR_S, WAT_CF_VAR_L) { return 0 - 1 }
      if ast::local_is_mut(src, WAT_CF_FLD_S) { return 1 }
      return 0
    }
    _ => { return 0 - 1 }
  }
}

## Resolve a comptime-for RANGE BOUND to its constant value: a literal, or a module-level const `N := k`
## resolved by name (comptime_for_range's `0..N`). Mirrors the subset of the x86 lower's global_init_value
## the corpus range bounds use (literal + module const; no const arithmetic — range bounds carry none).
wat_comp_range_bound := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8)) -> i64 {
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
    ## instance. STRUCT → field count, ENUM → variant count, TUPLE → top-level-comma+1, ARRAY `[E;N]` → N.
    Expr::Field(b, fs, fl) => {
      fnm := str_at((src + fs), fl)
      rt := wat_range_typeinfo_arg(b, fs, src)
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
          ## TUPLE component count = top-level commas + 1 (scanned inline over the `(…)` source span).
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
          ## ARRAY `[E; N]` element COUNT = N. Find the top-level `;`, parse the digits.
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

## Is `[ns, ns+nl)` a module-level SCALAR global (a kind-0 value decl, arity 0, scalar init)? Such a
## name lowers to `global.get`/`global.set $name`.
is_global := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut found := false
  while i < cnt and (not found) {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, ns, nl) and ex_value_is_scalar(d.value) { found = true }
    i += 1
  }
  found
}

## Is `v` an aggregate literal (StructLit/EnumLit/ArrayLit) — the init form of an aggregate GLOBAL?
value_is_agg := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) {
    Expr::StructLit(a0, b0, c0, d0) => { r = true }
    Expr::EnumLit(a1, b1, c1, d1, e1, f1) => { r = true }
    Expr::ArrayLit(a2, b2) => { r = true }
    _ => {}
  }
  r
}

## The word size of an aggregate global's value (struct_words, 1+enum_max_arity for an enum, or
## nel*element-stride for an array).
agg_value_words := fn(decls : ptr(rt::Vec), src : ptr(u8), v : ptr(Expr), a : rt::Arena) -> usize {
  sn := expr_struct_name(v)
  if sn.n != 0 { return struct_words(decls, src, sn.s, sn.n, a) }
  en := expr_enum_name(v)
  if en.n != 0 { return 1 + enum_max_arity(decls, src, en.s, en.n, a) }
  if ex_is_array_lit(v) { return array_lit_nel(v) * usize(array_lit_stride(v, src, a, decls)) }
  return 0
}

## The fixed linear-memory byte offset of the aggregate GLOBAL named `[ns, ns+nl)` — 1024 + the total
## byte size of every aggregate global declared before it — or -1 if it is not an aggregate global.
## (Aggregate globals occupy [1024, agg_globals_end); `$__sp` scratch starts at agg_globals_end.)
agg_global_base := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> i64 {
  cnt := rt::vec_len(deref(decls))
  mut off := 1024
  mut res := 0 - 1
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 and value_is_agg(d.value) {
      if streq(src, d.name_start, d.name_len, ns, nl) { res = off }
      off += i64(agg_value_words(decls, src, d.value, a)) * 8
    }
    i += 1
  }
  res
}

## The first free offset after all aggregate globals (= where `$__sp` scratch begins).
agg_globals_end := fn(decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> i64 {
  cnt := rt::vec_len(deref(decls))
  mut off := 1024
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 and value_is_agg(d.value) {
      off += i64(agg_value_words(decls, src, d.value, a)) * 8
    }
    i += 1
  }
  off
}

## The enum-type name of an enum GLOBAL named `[ns, ns+nl)` (from its EnumLit init), else {0,0}.
global_enum_type := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> WSpan {
  cnt := rt::vec_len(deref(decls))
  mut rs := 0
  mut rn := 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and streq(src, d.name_start, d.name_len, ns, nl) {
      en := expr_enum_name(d.value)
      if en.n != 0 { rs = en.s ; rn = en.n }
    }
    i += 1
  }
  WSpan(s = rs, n = rn)
}

## The struct-type name of a struct GLOBAL named `[ns, ns+nl)` (from its StructLit init), else {0,0}.
global_struct_type := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> WSpan {
  cnt := rt::vec_len(deref(decls))
  mut rs := 0
  mut rn := 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and streq(src, d.name_start, d.name_len, ns, nl) {
      sn := expr_struct_name(d.value)
      if sn.n != 0 { rs = sn.s ; rn = sn.n }
    }
    i += 1
  }
  WSpan(s = rs, n = rn)
}

## --- NESTED struct-GLOBAL field-chain access (`STATE.a.b.c`, any depth). A struct global lives at a
## fixed linear-memory base (agg_global_base of its root var); a field chain rooted at it reads/writes
## at base + cumulative-word-offset*8 (nested structs FLATTENED). Mirrors aarch64/riscv64's gchain. ---
## STRUCT-type name span of the place `e` (a field chain rooted at a struct GLOBAL), else {0,0}.
wat_gchain_type := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => { r = global_struct_type(decls, src, s, n, a) }
    Expr::Field(base, fs, fl) => {
      bt := wat_gchain_type(base, decls, src, a)
      if bt.n != 0 { if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { fts := field_type_span(decls, src, bt.s, bt.n, fs, fl, a) ; r = WSpan(s = fts.s, n = fts.n) } }
    }
    _ => {}
  }
  r
}

## Cumulative WORD offset of the place `e` within its root struct global's memory image, or -1.
wat_gchain_woff := fn(e : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> i64 {
  mut r := 0 - 1
  match deref(e) {
    Expr::Var(s, n) => { st := global_struct_type(decls, src, s, n, a) ; if st.n != 0 { r = 0 } }
    Expr::Field(base, fs, fl) => {
      boff := wat_gchain_woff(base, decls, src, a)
      bt := wat_gchain_type(base, decls, src, a)
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
wat_gchain_root := fn(e : ptr(Expr)) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => { r = WSpan(s = s, n = n) }
    Expr::Field(base, fs, fl) => { r = wat_gchain_root(base) }
    _ => {}
  }
  r
}


## Is the module GLOBAL named `[ns,nl]` an ARRAY global (kind-0 arity-0 with an array-literal init)?
wat_is_array_global := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut r := false
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, ns, nl) { if ex_is_array_lit(d.value) { r = true } }
    i += 1
  }
  r
}

## The element COUNT of the array GLOBAL named `[ns,nl]` (0 if not one) — the static bound for a checked
## index guard.
wat_array_global_nel := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> i64 {
  cnt := rt::vec_len(deref(decls))
  mut r := 0
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, ns, nl) { if ex_is_array_lit(d.value) { r = i64(array_lit_nel(d.value)) } }
    i += 1
  }
  r
}

## The element STRUCT span of an ARRAY LITERAL `v` — its first element's StructLit name, but ONLY when
## EVERY element is a StructLit of that SAME struct. A TUPLE literal (`(Pt(…), 12)` for `(Pt, u64)`)
## parses as an ArrayLit too, and its components have DIFFERENT widths — they are not uniformly-strided
## elements, so reading one as an aggregate array element would land on the wrong offset. A mixed literal
## therefore yields {0,0} and the caller falls back to its scalar path / fails loud.
wat_arr_lit_elem_struct := fn(v : ptr(Expr), src : ptr(u8)) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  eh := ex_array_lit_ehead(v)
  if eh == 0 { return r }
  a0 := deref(arg_p(eh))
  f := expr_struct_name(a0.e)
  if f.n == 0 { return r }
  mut g := eh
  mut ok := true
  while g != 0 {
    ga := deref(arg_p(g))
    en := expr_struct_name(ga.e)
    if en.n == 0 { ok = false }
    if en.n != 0 { if not streq(src, en.s, en.n, f.s, f.n) { ok = false } }
    g = ga.next
  }
  if ok { r = f }
  r
}

## Element WORD stride of the array GLOBAL named `[ns,nl]` — its ArrayLit's element stride (struct_words
## for a StructLit element, 1+enum_max_arity for an EnumLit one, else 1). 1 when it is not an array global.
## The `.data` image emit_wat_agg_cells writes is FLATTENED at exactly this stride, so element i of a
## struct-element array global starts at (base + i*stride*8) — the global dual of array_local_stride.
wat_array_global_stride := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> i64 {
  cnt := rt::vec_len(deref(decls))
  mut r := 1
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, ns, nl) {
      if ex_is_array_lit(d.value) { r = array_lit_stride(d.value, src, a, decls) }
    }
    i += 1
  }
  r
}

## The element STRUCT span of the array GLOBAL named `[ns,nl]` (its first ArrayLit element's StructLit
## name), else {0,0} — the global dual of arr_elem_struct_span. Types `ARR[i]` / `ARR[i].f`.
wat_array_global_elem_struct := fn(decls : ptr(rt::Vec), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> WSpan {
  cnt := rt::vec_len(deref(decls))
  mut r := WSpan(s = 0, n = 0)
  mut i := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and streq(src, d.name_start, d.name_len, ns, nl) {
      if ex_is_array_lit(d.value) { r = wat_arr_lit_elem_struct(d.value, src) }
    }
    i += 1
  }
  r
}

## Emit an i64 as 8 little-endian bytes (WAT data-string escapes) — for aggregate-global constant init.
emit_i64_le := fn(in out sb : rt::StrBuf, v : i64) {
  ## Extract the RAW two's-complement little-endian bytes of `v` via UNSIGNED shifts — `x` is `u64`
  ## so `/`/`%` are the logical (`divq`) forms, correct for a NEGATIVE `v` too (a signed `idivq` would
  ## round toward zero and mis-encode). (Before scalar type tracking `x := v` was untyped and defaulted
  ## to unsigned; now the type is explicit so a negative i64 global init still encodes correctly.)
  mut x : u64 = unchecked bitcast(u64, v)
  mut i := 0
  while i < 8 {
    emit_byte_esc(sb, u8(x % 256))
    x = x / 256
    i += 1
  }
}

## Is the callee `[cs, cs+cl)` a fn DEFINED in this module (a kind-1 decl)? A call to anything else —
## a qualified lib/builtin (`atomic::load`, `std::io::print`), an arch intrinsic — has no WASM func to
## target, so it emits `(unreachable)` rather than a bogus `(call $undefined)` that fails wat2wasm.
callee_defined := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, a : rt::Arena) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut found := false
  while i < cnt and (not found) {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and streq(src, d.name_start, d.name_len, cs, cl) { found = true }
    i += 1
  }
  found
}

## Does the callee `[cs, cs+cl)` return no value (a void fn, `ret_tl == 0`)? Then it is emitted without
## a `(result i64)` and a call-as-statement leaves nothing to drop.
callee_is_void := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, a : rt::Arena) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut void := false
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and streq(src, d.name_start, d.name_len, cs, cl) and d.ret_tl == 0 { void = true }
    i += 1
  }
  void
}

## The struct-type name RETURNED by the callee `[cs, cs+cl)` — its `-> R` annotation IF `R` names a
## struct decl, else {0,0}. A struct-returning fn yields the value's i64 base address (built in the
## `$__sp` bump region, which survives the return), so a local bound to such a call is a struct local.
callee_ret_struct := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, args_head : ptr(mut Arg), a : rt::Arena) -> WSpan {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut rs := 0
  mut rn := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and streq(src, d.name_start, d.name_len, cs, cl) and d.ret_tl != 0 {
      ## effective return base type-name span. GENERICS (§8): a generic callee returning its type-param
      ## `T` resolves to the call's EXPLICIT leading type-arg (arg 0, a bare type NAME Var), so
      ## `p := id(P, …)` sees the concrete struct `P`. Mirrors a64_call_ret_struct_span.
      mut ebs := d.ret_ts
      mut ebn := d.ret_tl
      if d.is_generic {
        tpn := wat_tparam_name(d, src)
        if tpn.n != 0 and d.ret_tl == tpn.n and streq(src, d.ret_ts, d.ret_tl, tpn.s, tpn.n) {
          if arg_list_count(args_head, a) == i64(d.arity) {
            ea := arg_expr_at(args_head, 0, a)
            evn := expr_var_name(ea)
            if evn.n != 0 { ebs = evn.s ; ebn = evn.n }
          }
        }
      }
      if struct_decl_of(decls, src, ebs, ebn) >= 0 { rs = ebs ; rn = ebn }
    }
    i += 1
  }
  WSpan(s = rs, n = rn)
}

## Are all of enum `[s, s+n)`'s variant payloads single-word (the subset the WASM match/binding
## machinery models: each `E::V(x)` binding aliases exactly ONE payload word)? A variant with a
## WIDE payload — a struct/enum/`str` field (`arity == 1` but > 1 word) — is NOT modelled; such an
## enum must stay fail-loud rather than be delivered by base address and mis-bound. Mirrors
## `struct_all_scalar`. Unit variants (arity 0) and single-scalar variants (arity 1, 1 word) are fine.
enum_all_scalar := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := enum_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut ok := true
  while f != 0 {
    fd := deref(fld_p(f))
    if fd.arity == 1 {
      if field_words(decls, src, fd.ts, fd.tl, fd.wsize, a) != 1 { ok = false }
    }
    f = fd.next
  }
  ok
}

## The enum-type name RETURNED by the callee `[cs, cs+cl)` — its `-> R` annotation IF `R` names an
## enum decl WITH ALL-SCALAR PAYLOADS, else {0,0}. Mirrors `callee_ret_struct`: the value's i64 base
## address is built in the `$__sp` bump region (survives the return), so a local bound to such a call
## is an enum local. A wide-payload enum stays unresolved → its `match` falls through to fail-loud.
callee_ret_enum := fn(decls : ptr(rt::Vec), src : ptr(u8), cs : usize, cl : usize, args_head : ptr(mut Arg), a : rt::Arena) -> WSpan {
  cnt := rt::vec_len(deref(decls))
  mut i := 0
  mut rs := 0
  mut rn := 0
  while i < cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 and streq(src, d.name_start, d.name_len, cs, cl) and d.ret_tl != 0 {
      ## effective return base type-name span. GENERICS (§8): a generic callee returning its type-param
      ## `T` resolves to the call's EXPLICIT leading type-arg (arg 0), so `o := id(Opt, …)` sees `Opt`.
      ## Mirrors a64_call_ret_enum_span.
      mut ebs := d.ret_ts
      mut ebn := d.ret_tl
      if d.is_generic {
        tpn := wat_tparam_name(d, src)
        if tpn.n != 0 and d.ret_tl == tpn.n and streq(src, d.ret_ts, d.ret_tl, tpn.s, tpn.n) {
          if arg_list_count(args_head, a) == i64(d.arity) {
            ea := arg_expr_at(args_head, 0, a)
            evn := expr_var_name(ea)
            if evn.n != 0 { ebs = evn.s ; ebn = evn.n }
          }
        }
      }
      if enum_decl_of(decls, src, ebs, ebn) >= 0 and enum_all_scalar(decls, src, ebs, ebn, a) { rs = ebs ; rn = ebn }
    }
    i += 1
  }
  WSpan(s = rs, n = rn)
}

## The tryable ENUM type span of a WAT `?` operand. Calls use their declared enum return type; enum
## locals use the same PARAM/LOCAL resolver as value-position `match`. The wrappers preserve the
## expression's type while the emitter handles the actual early return.
wat_try_enum_type := fn(inner : ptr(Expr), params_head : ptr(mut Param), fn_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  match deref(inner) {
    Expr::Var(vs, vn) => { return base_enum_type(params_head, fn_head, src, vs, vn, a, decls) }
    Expr::Call(cs, cl, nargs, ah) => { return callee_ret_enum(decls, src, cs, cl, ah, a) }
    Expr::Unchecked(x) => { return wat_try_enum_type(x, params_head, fn_head, src, a, decls) }
    Expr::Bitcast(x, _ts, _tl) => { return wat_try_enum_type(x, params_head, fn_head, src, a, decls) }
    _ => {}
  }
  WSpan(s = 0, n = 0)
}

## The discriminant of the SUCCESS variant for a WAT `?`: `Some` for Option and `Ok` for Result. The
## shipped stdlib Option is `{None, Some}`, so this must not assume variant zero. An unresolved type
## folds to zero, matching the native lower's safe default.
wat_try_success_disc := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> i64 {
  ebn := base_type_name(src, s, n)
  di := enum_decl_of(decls, src, ebn.s, ebn.n)
  if di < 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut idx := 0
  mut res := 0
  while f != 0 {
    fd := deref(fld_p(f))
    nm := str_at((src + fd.ns), fd.nl)
    if nm == "Some" { res = idx }
    if nm == "Ok" { res = idx }
    idx += 1
    f = fd.next
  }
  res
}

## The callee-name span of an expression IF it is a `Call` (`f(…)`), else {0,0}.
expr_call_name := fn(v : ptr(Expr)) -> WSpan {
  mut rs := 0
  mut rn := 0
  match deref(v) {
    Expr::Call(cs, cl, nn, ah) => { rs = cs ; rn = cl }
    _ => {}
  }
  WSpan(s = rs, n = rn)
}

## The BASE sub-expression of a `Field` (`o.i` for `o.i.v`), else the expression itself. Single-level
## match (a doubly-nested match mis-lowers under the seed) — the FieldPathAssign arm uses this + the
## field span below to reach a nested place without an inline nested match.
expr_field_base := fn(v : ptr(Expr)) -> ptr(Expr) {
  mut r := v
  match deref(v) {
    Expr::Field(base, fs, fl) => { r = base }
    _ => {}
  }
  r
}

## The FIELD-name span of a `Field` expression (`v` in `o.i.v`), else {0,0}.
expr_field_span := fn(v : ptr(Expr)) -> WSpan {
  mut rs := 0
  mut rn := 0
  match deref(v) {
    Expr::Field(base, fs, fl) => { rs = fs ; rn = fl }
    _ => {}
  }
  WSpan(s = rs, n = rn)
}

## 0-based index of the PARAM named `[ns, ns+nl)` in the fn's VALUE-param list, or -1 if not a value
## param. A comptime `T : type` param occupies NO WASM slot (its type-arg is erased at every call site
## — see the generic-call arg-emission), so it is SKIPPED without advancing the index. In a LEADING
## instance the params_head is already value-only (ephead = pm.next), so this skip is a no-op there; a
## NON-LEADING type-param (`gf(s, T, k)`) keeps the full list and this restores the value-relative slot.
param_find := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> i64 {
  mut p := params_head
  mut idx := 0
  while p != 0 {
    pm := deref(param_p(p))
    if str_at((src + pm.ts), pm.tl) == "type" {} else {
      if streq(src, pm.ns, pm.nl, ns, nl) { return i64(idx) }
      idx += 1
    }
    p = pm.next
  }
  return -1
}

## The handle of the FIRST Assign of name `[ns, ns+nl)` anywhere in the fn tree (pre-order:
## top-level then nested while/if/match bodies), or 0 if the name is never assigned. Pure
## value-returning recursion — no early return inside a match arm, no ptr(mut) (both mis-lower /
## are UB in the lean lower; see build-env memory). Each distinct name → one such handle, so
## `first_assign_handle(fn_head, name) == s` gives every name ONE WASM slot tree-wide.
first_assign_handle := fn(list : ptr(mut Stmt), ns : usize, nl : usize, src : ptr(u8), a : rt::Arena) -> usize {
  mut s := list
  mut res := 0
  while s != 0 and res == 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { if streq(src, ans, anl, ns, nl) { res = s } ; s = nx }
      Stmt::While(c, b, nx) => { res = first_assign_handle(b, ns, nl, src, a) ; s = nx }
      Stmt::If(c, th, el, nx) => { res = first_assign_handle(th, ns, nl, src, a) ; if res == 0 { res = first_assign_handle(el, ns, nl, src, a) } ; s = nx }
      Stmt::Match(msc, mah, mnx) => { mut arm := mah ; while arm != 0 and res == 0 { am := deref(arm_p(arm)) ; res = first_assign_handle(am.body_stmts, ns, nl, src, a) ; arm = am.next } ; s = mnx }
      ## a `for i in lo..hi` DECLARES the loop var `i`: this For is its first handle; otherwise recurse the body.
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { if streq(src, fns, fnl, ns, nl) { res = s } else { res = first_assign_handle(fb, ns, nl, src, a) } ; s = nx }
      ## a `comptime for i in lo..hi` DECLARES the loop var `i` (like a range `for`): this CompForRange is
      ## its first handle; otherwise recurse the body. CONTINUE past (a `_ => s = 0` would mis-resolve a
      ## local declared after the unrolled loop → silent miscompile).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { if streq(src, rvs, rvl, ns, nl) { res = s } else { res = first_assign_handle(rb, ns, nl, src, a) } ; s = nx }
      ## a `comptime if` folds to ONE branch but its locals live in the fn frame — recurse BOTH branches
      ## (mirroring local_slot_scan's both-branch scan) and CONTINUE past it, so a local declared after a
      ## CompIf is still found (a `_ => s = 0` would stop the scan and mis-resolve it → silent miscompile).
      Stmt::CompIf(cc, th, el, nx) => { res = first_assign_handle(th, ns, nl, src, a) ; if res == 0 { res = first_assign_handle(el, ns, nl, src, a) } ; s = nx }
      Stmt::Loop(lb, lnx) => { res = first_assign_handle(lb, ns, nl, src, a) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { res = first_assign_handle(ub, ns, nl, src, a) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      ## an index assign declares no local but MUST NOT terminate the scan (a leading `TABLE[2] = …`
      ## before the `mut` locals would otherwise hide them).
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  res
}

## Pre-order scan for the WASM slot of the local whose first-occurrence Assign is `target`, counting
## DISTINCT non-global first-occ locals seen so far in `before`. If `target` is found in this list's
## subtree, returns the NEGATIVE encoding `-(index+1)` (index = slot minus pcount); otherwise returns
## the non-negative running count after this whole subtree. Value-returning recursion with a `found`
## flag (loop exits on `not found`) — NO early return inside an arm, NO ptr(mut). With `target == 0`
## (no real handle) nothing is ever found, so it returns the TOTAL distinct-local count (count_locals).
local_slot_scan := fn(list : ptr(mut Stmt), fn_head : ptr(mut Stmt), target : usize, before : i64, src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
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
          if first_assign_handle(fn_head, ans, anl, src, a) == s and (not is_global(decls, src, ans, anl, a)) { b = b + 1 }
          s = nx
        }
      }
      Stmt::While(c, body, nx) => {
        r := local_slot_scan(body, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = nx }
      }
      Stmt::If(c, th, el, nx) => {
        r := local_slot_scan(th, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true }
        else {
          r2 := local_slot_scan(el, fn_head, target, r, src, a, decls)
          if r2 < 0 { result = r2 ; found = true } else { b = r2 ; s = nx }
        }
      }
      Stmt::Match(msc, mah, mnx) => {
        mut arm := mah
        while arm != 0 and (not found) {
          am := deref(arm_p(arm))
          r := local_slot_scan(am.body_stmts, fn_head, target, b, src, a, decls)
          if r < 0 { result = r ; found = true } else { b = r ; arm = am.next }
        }
        if (not found) { s = mnx }
      }
      ## a `for … in …` loop var: a RANGE `for i in lo..hi` occupies ONE slot; an ITERABLE `for x in xs`
      ## (null `fhi`) occupies TWO — the element var PLUS a hidden index at var-slot+1. First-occurrence
      ## at this For; then scan the body.
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        if s == target { result = 0 - (b + 1) ; found = true }
        else {
          if first_assign_handle(fn_head, fns, fnl, src, a) == s { if unchecked bitcast(usize, fhi) == 0 { b = b + 2 } else { b = b + 1 } }
          r := local_slot_scan(fb, fn_head, target, b, src, a, decls)
          if r < 0 { result = r ; found = true } else { b = r ; s = nx }
        }
      }
      ## a `comptime for i in lo..hi` DECLARES a scalar loop var `i` = ONE slot (like a RANGE for), reserved
      ## at its first-handle; then scan the body (emitted once per unroll iteration into these same slots).
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => {
        if s == target { result = 0 - (b + 1) ; found = true }
        else {
          if first_assign_handle(fn_head, rvs, rvl, src, a) == s { b = b + 1 }
          r := local_slot_scan(rb, fn_head, target, b, src, a, decls)
          if r < 0 { result = r ; found = true } else { b = r ; s = nx }
        }
      }
      ## `loop { }` / `unchecked { }` body scanned like a while body (function-frame locals at the running
      ## offset); `break`/`continue` declare nothing (skip).
      Stmt::Loop(lb, lnx) => {
        r := local_slot_scan(lb, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = lnx }
      }
      Stmt::Unchecked(ub, unx) => {
        r := local_slot_scan(ub, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true } else { b = r ; s = unx }
      }
      ## a `comptime if` folds to ONE branch but its locals live in the fn frame — scan BOTH branches
      ## sequentially (a safe superset; consistent with first_assign_handle's both-branch order) and
      ## CONTINUE past it, so a local declared after a CompIf still gets a slot (no silent miscompile).
      Stmt::CompIf(cc, th, el, nx) => {
        r := local_slot_scan(th, fn_head, target, b, src, a, decls)
        if r < 0 { result = r ; found = true }
        else {
          r2 := local_slot_scan(el, fn_head, target, r, src, a, decls)
          if r2 < 0 { result = r2 ; found = true } else { b = r2 ; s = nx }
        }
      }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      ## an index assign declares no local but MUST advance the scan (see first_assign_handle).
      Stmt::IndexAssign(ib, ii, iv, nx) => { s = nx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  if found { result } else { b }
}

## Total number of distinct non-global local names in the fn tree (how many `(local i64)` to declare).
count_locals := fn(fn_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  local_slot_scan(fn_head, fn_head, 0, 0, src, a, decls)
}

## Is the assign at handle `target` the FIRST occurrence of its name anywhere in the fn tree?
is_first_occ := fn(body_head : ptr(mut Stmt), target : usize, ns : usize, nl : usize, src : ptr(u8), a : rt::Arena) -> bool {
  first_assign_handle(body_head, ns, nl, src, a) == target
}

## WASM local index of the local `[ns, ns+nl)` (tree-wide, incl. nested scopes): params 0..pcount-1,
## then distinct non-global local names in pre-order of first occurrence (`:=` and every later `=`, and
## any nested occurrence of the same name, share ONE slot). Uses local_slot_scan (value recursion, no
## ptr(mut), no early-return-in-arm). Falls back to `pcount` if the name is unresolved.
name_local_index := fn(body_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  target := first_assign_handle(body_head, ns, nl, src, a)
  r := local_slot_scan(body_head, body_head, target, 0, src, a, decls)
  mut result := pcount
  if r < 0 { result = pcount + ((0 - r) - 1) }
  result
}

## Is `[ns, ns+nl)` a local ANYWHERE in the fn tree (a `:=`/`=` in any scope — top-level or nested)?
## (Was TOP-LEVEL only; now tree-wide, so a nested local resolves as a local rather than trapping.)
is_toplevel_local := fn(fn_head : ptr(mut Stmt), ns : usize, nl : usize, src : ptr(u8), a : rt::Arena) -> bool {
  first_assign_handle(fn_head, ns, nl, src, a) != 0
}

## A source span (a struct type name), or {0,0} for "none".
WSpan := struct { s : usize, n : usize }

## The struct-type name of an expression IF it is a `StructLit` (`Pt(x=…, y=…)`), else {0,0}.
## Single-level match in its own fn — a nested match inside another arm mis-lowers under the seed.
expr_struct_name := fn(v : ptr(Expr)) -> WSpan {
  mut rs := 0
  mut rn := 0
  match deref(v) {
    Expr::StructLit(ss, sn, nf, ah) => { rs = ss ; rn = sn }
    _ => {}
  }
  WSpan(s = rs, n = rn)
}


## The ENUM TYPE name of an expression IF it is an `EnumLit` (`E.V(…)`), else {0,0}.
expr_enum_name := fn(v : ptr(Expr)) -> WSpan {
  mut rs := 0
  mut rn := 0
  match deref(v) {
    Expr::EnumLit(es, en, vs, vn, nf, ah) => { rs = es ; rn = en }
    _ => {}
  }
  WSpan(s = rs, n = rn)
}

## The VARIANT name of an `EnumLit`, else {0,0}.
expr_enum_variant := fn(v : ptr(Expr)) -> WSpan {
  mut rs := 0
  mut rn := 0
  match deref(v) {
    Expr::EnumLit(es, en, vs, vn, nf, ah) => { rs = vs ; rn = vn }
    _ => {}
  }
  WSpan(s = rs, n = rn)
}


## The enum-type name of the LOCAL `[ns, ns+nl)` — from its `:=` EnumLit init (`e := E.V(…)`), else
## {0,0}. Lets a `match e { … }` resolve the scrutinee's variant discriminants.
local_enum_type := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut s := fn_head
  mut rs := 0
  mut rn := 0
  mut done := false
  while s != 0 and (not done) {
    stmt := deref(stmt_p(Stmt, s))
    match stmt {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) {
          en := expr_enum_name(v)
          if en.n != 0 { rs = en.s ; rn = en.n ; done = true }
          ## a local bound to an enum-returning CALL (`o := make_opt()`) is an enum local — its slot
          ## holds the returned base address (the callee built it in the `$__sp` bump region).
          if en.n == 0 {
            cn := expr_call_name(v)
            if cn.n != 0 {
              cr := callee_ret_enum(decls, src, cn.s, cn.n, ex_call_argh(v), a)
              if cr.n != 0 { rs = cr.s ; rn = cr.n ; done = true }
            }
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
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::Match(msc, mah, mnx) => { s = mnx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  WSpan(s = rs, n = rn)
}


## The name span of an expression IF it is a bare `Var`, else {0,0} (the struct-base place must be a
## simple local for now — `p.field`, not `expr.field`).
expr_var_name := fn(v : ptr(Expr)) -> WSpan {
  mut rs := 0
  mut rn := 0
  match deref(v) {
    Expr::Var(vs, vn) => { rs = vs ; rn = vn }
    _ => {}
  }
  WSpan(s = rs, n = rn)
}


## THIS BACKEND'S OWN ARCH IDENTITY (Tooling §2.7) — and the one place the SPEC IS SILENT. `target.*` is
## the RESOLVED SELECTED machine model, the machine being compiled FOR; but `Arch := enum { x86_64,
## i386, aarch64, aarch32, riscv32, riscv64 }` (Manifest §3.2, Assembly §10) has NO wasm variant — WASM
## is an ADDITIVE backend (FND-6; Overview / CG-4), so v1 does not NAME the machine this emitter targets.
## What v1 DOES decide is that the wasm target is none of those six, so `target.arch == Arch.<variant>`
## is FALSE here for every variant and `!=` is TRUE — which is what this sentinel spelling gives (no
## `Arch` variant can be spelled `<none>`; it is not an identifier). Folding as `x86_64` instead (the
## old behaviour, "so the sweep compares like-for-like") made `target.arch == Arch.x86_64` TRUE while
## emitting WASM, selecting x86-only bodies — including the raw x86 GAS `asm(…)` of `lib/std/thread.al`
## — into a WASM module. ONE accessor so the `comptime if` fold and the `when`-guard fold cannot drift.
wat_target_arch := fn() -> str { "<none>" }

## Fold a `comptime if <cond>` predicate at emit time — the wat dual of the x86 lower's `decl_guard_fold`.
## 1 = TRUE (emit the then-branch), 0 = FALSE (emit the else-branch), -1 = cannot fold (a typeinfo /
## type-param predicate — emit NEITHER; deferred, it needs the monomorphization context the wat path
## lacks). Same SHAPE as `decl_guard_fold`/`comptime_cond_eval` on the x86 path, folded against THIS
## target: every `target.arch == Arch.<v1 variant>` is FALSE (`wat_target_arch()`, see above),
## composed with `and`/`or`/`not` (op codes 40/41/42). A `verify.checked`
## / `match typeinfo(T)` predicate is unfoldable here (-1). FLAT ifs + self-recursion (no nested match).
wat_comp_cond_fold := fn(cond : ptr(Expr), src : ptr(u8)) -> i64 {
  mut r := 0 - 1
  match deref(cond) {
    Expr::Bin(op, l, rr) => {
      an := arch_rhs_span(rr, src)
      if an.n != 0 {
        eq := str_at((src + an.s), an.n) == wat_target_arch()
        if op == 20 { if eq { r = 1 } else { r = 0 } }
        if op == 28 { if eq { r = 0 } else { r = 1 } }
      }
      ## TYPE-name equality `T == <type>` / `T != <type>` inside a mono INSTANCE (WAT_SUB active, §8): the
      ## LHS names the instance's type-param, the RHS a bare type name → compare the concrete instance
      ## type's base name. Mirrors a64_comp_cond_fold / x86 comptime_cond_eval.
      if an.n == 0 and (op == 20 or op == 28) and WAT_SUB_GPL != 0 {
        lv := expr_var_name(l)
        rv := expr_var_name(rr)
        if lv.n != 0 and rv.n != 0 and streq(src, lv.s, lv.n, WAT_SUB_GPS, WAT_SUB_GPL) {
          itb := base_type_name(src, WAT_SUB_ITS, WAT_SUB_ITL)
          teq := streq(src, itb.s, itb.n, rv.s, rv.n)
          if op == 20 { if teq { r = 1 } else { r = 0 } }
          if op == 28 { if teq { r = 0 } else { r = 1 } }
        }
      }
      if an.n == 0 and op == 42 {
        lv := wat_comp_cond_fold(l, src)
        if lv == 1 { r = 0 }
        if lv == 0 { r = 1 }
      }
      if an.n == 0 and op == 40 {
        lv := wat_comp_cond_fold(l, src)
        rv := wat_comp_cond_fold(rr, src)
        if lv == 0 or rv == 0 { r = 0 }
        if lv == 1 and rv == 1 { r = 1 }
      }
      if an.n == 0 and op == 41 {
        lv := wat_comp_cond_fold(l, src)
        rv := wat_comp_cond_fold(rr, src)
        if lv == 1 or rv == 1 { r = 1 }
        if lv == 0 and rv == 0 { r = 0 }
      }
    }
    ## `verify.checked` (CT-11): the current verification mode (WAT_CHK — checked by default, cleared
    ## inside `unchecked {}`). Mirrors a64/x86 so a `comptime if verify.checked` predicate folds identically.
    Expr::Field(b, fs, fl) => {
      bn := expr_var_name(b)
      if bn.n != 0 and str_at((src + bn.s), bn.n) == "verify" {
        if WAT_CHK { r = 1 } else { r = 0 }
      }
    }
    ## `match typeinfo(T) { <Kind>(_) => true; _ => false }` used as a comptime-if CONDITION (§8): fold
    ## by T's KIND inside a mono INSTANCE (WAT_SUB active). The FIRST arm's variant name is the tested
    ## kind; a match → 1, else 0. wat_decls() supplies decls (set per-fn in emit_wat_body).
    Expr::Match(scrut, arms_head) => {
      if WAT_SUB_ITL != 0 {
        kind := ct_type_kind(WAT_SUB_ITS, WAT_SUB_ITL, wat_decls(), src)
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



## Is `e` a bare `Var` that names a STRUCT param/local? Such a value is a memory address, so it must
## not feed a scalar arithmetic `Bin` (that would add addresses) — the Bin arm traps on it (a user
## operator-overload `p + q` over a struct is not modelled).
expr_is_struct_var := fn(e : ptr(Expr), params_head : ptr(mut Param), fn_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  vn := expr_var_name(e)
  if vn.n == 0 { return false }
  st := base_struct_type(params_head, fn_head, src, vn.s, vn.n, a, decls)
  if st.n == 0 { return false }
  ## a param's type span is returned unconditionally by param_struct_type — confirm it names an actual
  ## STRUCT decl (a scalar param like `x : u64` must NOT be flagged, else `x * x` wrongly traps).
  return struct_decl_of(decls, src, st.s, st.n) >= 0
}

## Is `e` a bare PLACE whose WASM local holds an AGGREGATE BASE ADDRESS (a `$__sp` linear-memory
## block) instead of the value itself — a struct, TUPLE, fixed ARRAY, SLICE view or ENUM local/param?
## A scalar `i64.eq`/`i64.lt_u` over such a local compares ADDRESSES, never contents (Stdlib §2.6):
## two field-equal blocks read UNEQUAL and two distinct blocks read ordered by allocation. That is the
## one forbidden outcome — a SILENT MISCOMPILE — so the compare arm must fail loud on all of them.
## `expr_is_struct_var` alone recognizes only a NAMED-struct decl, which is why a TUPLE (the parser
## builds one as an `ArrayLit`, so it carries no struct decl), a fixed ARRAY, a SLICE and an ENUM all
## slipped past that guard into the scalar compare below. Var-only by construction: an INDEX/FIELD
## operand (`xs[0] == ys[0]`, `p.x == q.x`) already yields a loaded scalar and must keep comparing.
wat_is_agg_place := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if expr_is_struct_var(e, params_head, body_head, src, a, decls) { return true }
  vn := expr_var_name(e)
  if vn.n == 0 { return false }
  et := base_enum_type(params_head, body_head, src, vn.s, vn.n, a, decls)
  if et.n != 0 { return true }
  if is_array_local(body_head, src, vn.s, vn.n, a) { return true }
  if is_slice_local(body_head, src, vn.s, vn.n, a) { return true }
  false
}
## The INDEX twin: `xs[i]` over an AGGREGATE-ELEMENT array/slice/global yields the ELEMENT's base
## address (elements are by-reference), so `ps[0] == ps[1]` compared addresses — two field-EQUAL
## elements read UNEQUAL. Kept separate from `wat_is_agg_place`'s Var scan because the base name has
## to be peeled off the Index first; a SCALAR-element array (`xs[0] == ys[0]`) yields a loaded value
## and stays on the ordinary compare.
wat_is_agg_index := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_index(e) { return false }
  bn := expr_var_name(ex_index_base(e))
  if bn.n == 0 { return false }
  es := wat_arr_elem_struct(body_head, src, bn.s, bn.n, a, decls)
  es.n != 0
}

array_lit_nel := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) {
    Expr::ArrayLit(al_n, al_e) => { r = al_n }
    _ => {}
  }
  r
}
## Tuple return types are balanced `(T0, …)` spans. WASM represents a small tuple as a linear-memory
## word block and returns its base address, matching the existing aggregate-local representation.
wat_fn_returns_tuple := fn(d : Decl, src : ptr(u8)) -> bool {
  if d.ret_tl == 0 { return false }
  str_at((src + d.ret_ts), 1) == "("
}
wat_tuple_words := fn(src : ptr(u8), ts : usize, tl : usize) -> i64 {
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
wat_call_ret_tuple_words := fn(v : ptr(Expr), decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) -> i64 {
  cn := expr_call_name(v)
  mut r := 0
  if cn.n != 0 {
    cnt := rt::vec_len(deref(decls))
    mut i := 0
    while i < cnt {
      d := deref(decl_get(decls, i))
      if d.is_fn and d.name_len != 0 and streq(src, d.name_start, d.name_len, cn.s, cn.n) {
        if wat_fn_returns_tuple(d, src) {
          tw := wat_tuple_words(src, d.ret_ts, d.ret_tl)
          if tw >= 1 and tw <= 7 { r = tw }
        }
      }
      i = i + 1
    }
  }
  r
}
## Is the LOCAL `[ns, ns+nl)` a range-SLICE view (its `:=` init is an Expr::Slice)?
is_slice_local := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  d := lower_layout::local_decl_assign(fn_head, src, ns, nl)
  mut r := false
  if unchecked bitcast(usize, d) != 0 {
    stmt := deref(stmt_p(Stmt, d))
    match stmt {
      Stmt::Assign(ans, anl, v, nx) => { if ex_is_slice(v) { r = true } }
      _ => {}
    }
  }
  r
}

## The ELEMENT-type span of a `Slice(E)` PARAM named `[s,n)`, by scanning SOURCE forward from the param
## name (`: Slice(E)`) — the wasm twin of lower.al's `slice_param_elem_span`. {0,0} when not a slice param.
wat_slice_elem_span := fn(src : ptr(u8), s : usize, n : usize) -> WSpan {
  mut p := s + n
  end := p + 512
  mut c := str_at((src + p), 1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") { p = p + 1 ; c = str_at((src + p), 1) }
  if c != ":" { return WSpan(s = 0, n = 0) }
  p = p + 1
  c = str_at((src + p), 1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") { p = p + 1 ; c = str_at((src + p), 1) }
  if str_at((src + p), 6) != "Slice(" { return WSpan(s = 0, n = 0) }
  es := p + 6
  mut ee := es
  while ee < end and str_at((src + ee), 1) != ")" { ee = ee + 1 }
  if ee == end { return WSpan(s = 0, n = 0) }
  if ee == es { return WSpan(s = 0, n = 0) }
  WSpan(s = es, n = ee - es)
}
## Is the PARAM `[ns,nl]` a `Slice(E)` param with a SCALAR element E? In WASM a slice PARAM has the SAME
## shape as a local slice VIEW: the param (a WASM local) holds the base address of a `{ptr,len}` block in
## linear memory (word0 = data ptr, word1 = runtime len). So the read paths reuse the slice-VIEW emit,
## taking the base local index from `param_find` instead of `name_local_index`. Struct/enum element = follow-up.
wat_slice_param_scalar := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut p := params_head
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      es := wat_slice_elem_span(src, pm.ns, pm.nl)
      if es.n != 0 {
        if struct_decl_of(decls, src, es.s, es.n) < 0 and enum_decl_of(decls, src, es.s, es.n) < 0 { r = true }
      }
    }
    p = pm.next
  }
  r
}
## The CURRENT fn's params + decls, stashed as module globals at the top of emit_wat_body (so the
## element-struct resolver local_struct_type, which takes no params_head, can recognize a slice PARAM base).
mut WAT_PARAMS := 0
wat_params := fn() -> ptr(mut Param) { unchecked bitcast(ptr(mut Param), WAT_PARAMS) }
mut WAT_DECLS := 0
wat_decls := fn() -> ptr(rt::Vec) { unchecked bitcast(ptr(rt::Vec), WAT_DECLS) }
## Number of components in the current function's tuple return. ArrayLit is also fixed-array syntax;
## only a tuple RETURN may materialize it as the WASM aggregate-result block.
mut WAT_RET_TUPLE := 0

## --- GENERICS (§8 monomorphization on wat) -----------------------------------------------------
## The wat backend emits monomorphized instances of a generic fn (a `T : type` param) as `$<fn>__<tag>`
## and routes each generic CALL to its instance. WASM is a stack machine — there is no register-delivery
## ABI, so a scalar instance is byte-identical to a plain fn; a struct/enum type-arg rides its i64 base
## address (later clusters). The instance's substitution (`T`'s name span → the concrete type span) rides
## module globals, set per-instance in `emit_wat_program`'s mono pass and read by the comptime folds.
## Zero → no substitution. (The A64_* dual; WAT labels are function-local, so each emitted function
## gets its own deterministic monotonic namespace. The allocator is reset at emit_wat_body entry so
## repeated generic instances and repeated program emissions are independent of prior backend state.)
mut WAT_SUB_GPS := 0    ## the generic type-param NAME span start …
mut WAT_SUB_GPL := 0    ## … and length (0 = no active substitution)
mut WAT_SUB_ITS := 0    ## the instance's concrete type span start …
mut WAT_SUB_ITL := 0    ## … and length (non-zero while emitting an instance = instance mode)
## 2nd/3rd LEADING type-param of a 2/3-type-param generic (`pick3(A, B, C, …)`): NAME → instance-type
## substitution for the 2nd (GPS2/GPL2 → ITS2/ITL2) and 3rd (GPS3/GPL3 → ITS3/ITL3). 0 = absent. The
## A64_SUB_*2/*3 dual.
mut WAT_SUB_GPS2 := 0
mut WAT_SUB_GPL2 := 0
mut WAT_SUB_ITS2 := 0
mut WAT_SUB_ITL2 := 0
mut WAT_SUB_GPS3 := 0
mut WAT_SUB_GPL3 := 0
mut WAT_SUB_ITS3 := 0
mut WAT_SUB_ITL3 := 0
## The collected instance set: parallel FIXED module arrays (generic-decl index / type-arg span
## start / length; plus the 2nd/3rd type-arg spans for a multi-type-param generic), WAT_INST_N live
## entries. Fixed BSS (not arena-bump — the storage must not ride a by-value arena copy). Instances are
## RECORDED DURING EMIT at each generic call site (wat_inst_add) and consumed to emit one `$<fn>__<tag>`
## per entry. The wat backend runs only for single-file cross-checks (never the self-build), so this BSS
## is otherwise inert.
mut WAT_INST_GI : [usize; 512] = [0; 512]
mut WAT_INST_TS : [usize; 512] = [0; 512]
mut WAT_INST_TL : [usize; 512] = [0; 512]
mut WAT_INST_TS2 : [usize; 512] = [0; 512]
mut WAT_INST_TL2 : [usize; 512] = [0; 512]
mut WAT_INST_TS3 : [usize; 512] = [0; 512]
mut WAT_INST_TL3 : [usize; 512] = [0; 512]
mut WAT_INST_N := 0
## Resolved-type-arg OUT registers (avoid returning a multi-word span from a helper — the frozen seed
## can truncate such a return in some call contexts). wat_resolve_typearg writes here; callers read it.
## S2/N2, S3/N3 = the 2nd/3rd leading type-arg of a multi-type-param call.
mut WAT_TA_S := 0
mut WAT_TA_N := 0
mut WAT_TA_S2 := 0
mut WAT_TA_N2 := 0
mut WAT_TA_S3 := 0
mut WAT_TA_N3 := 0
## comptime FIELD-unroll context (`Stmt::CompFor` over `typeinfo(T).fields`). Set/restored per field in
## the CompFor arm; WAT_CF_VAR_L == 0 = NOT inside a field unroll (all `v.(f)`/`f.type` inert). `v.(f)`
## (Expr::CompField) reads the CURRENT field (WAT_CF_FLD_*) of `v`; `f.type` (a type-arg) → WAT_CF_TY_*.
mut WAT_CF_VAR_S := 0
mut WAT_CF_VAR_L := 0
mut WAT_CF_FLD_S := 0
mut WAT_CF_FLD_L := 0
mut WAT_CF_TY_S := 0
mut WAT_CF_TY_L := 0
## The byte offset of `<f>.offset` for the ACTIVE comptime field descriptor. The field loop is
## emitted only for a concrete struct instance (`WAT_SUB_*`); reuse the shared layout calculators so
## packed, standard byte-array, and ordinary word-granular structs report the same offsets as value code.
## Return -1 for a non-active/dynamic descriptor shape; the caller keeps the existing fail-loud path.
wat_cf_offset_value := fn(e : ptr(Expr), src : ptr(u8), decls : ptr(rt::Vec), a : rt::Arena) -> i64 {
  if WAT_CF_VAR_L == 0 or WAT_SUB_ITL == 0 { return 0 - 1 }
  match deref(e) {
    Expr::Field(base, fs, fl) => {
      if str_at((src + fs), fl) != "offset" { return 0 - 1 }
      bns := ex_var_ns(base)
      bnl := ex_var_nl(base)
      if bnl == 0 or not streq(src, bns, bnl, WAT_CF_VAR_S, WAT_CF_VAR_L) { return 0 - 1 }
      ct := base_type_name(src, WAT_SUB_ITS, WAT_SUB_ITL)
      if ct.n == 0 { return 0 - 1 }
      ## THE ORACLE (`lower_layout::layout_kind`) picks the tier — the same decision the value
      ## paths and the x86 dual use, so four emitters cannot drift apart on one offset.
      lk := layout_kind(decls, src, ct.s, ct.n, a)
      if layout_kind_is_packed(lk) { return packed_field_byte_offset(decls, src, ct.s, ct.n, WAT_CF_FLD_S, WAT_CF_FLD_L, a) }
      if layout_kind_is_byte(lk) { return standard_field_byte_offset(decls, src, ct.s, ct.n, WAT_CF_FLD_S, WAT_CF_FLD_L, a) }
      fwo := field_word_offset(decls, src, ct.s, ct.n, WAT_CF_FLD_S, WAT_CF_FLD_L, a)
      if fwo >= 0 { return fwo * 8 }
      return 0 - 1
    }
    _ => { return 0 - 1 }
  }
}

## The struct-type span of the PARAM `[ns,nl]`, WITH the generic substitution applied (a `v : T` param in
## a mono instance resolves to the instance struct type), then generic-application stripped (`Box(T)` →
## `Box`), else 0/0. Mirrors a64_param_struct_ns/nl. Returns WSpan (safe — wat helpers return WSpan freely).
wat_param_struct_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut p := params_head
  mut r := WSpan(s = 0, n = 0)
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      mut ets := pm.ts
      mut etl := pm.tl
      if WAT_SUB_GPL != 0 and streq(src, pm.ts, pm.tl, WAT_SUB_GPS, WAT_SUB_GPL) { ets = WAT_SUB_ITS ; etl = WAT_SUB_ITL }
      bt := base_type_name(src, ets, etl)
      if struct_decl_of(decls, src, bt.s, bt.n) >= 0 { r = WSpan(s = bt.s, n = bt.n) }
    }
    p = pm.next
  }
  r
}
## The ENUM-type span of the PARAM `[ns,nl]`, WITH the generic substitution applied (a `v : T` enum param
## in a mono instance resolves to the instance enum type), else 0/0. The enum twin of wat_param_struct_span.
wat_param_enum_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut p := params_head
  mut r := WSpan(s = 0, n = 0)
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) {
      mut ets := pm.ts
      mut etl := pm.tl
      if WAT_SUB_GPL != 0 and streq(src, pm.ts, pm.tl, WAT_SUB_GPS, WAT_SUB_GPL) { ets = WAT_SUB_ITS ; etl = WAT_SUB_ITL }
      bt := base_type_name(src, ets, etl)
      if enum_decl_of(decls, src, bt.s, bt.n) >= 0 { r = WSpan(s = bt.s, n = bt.n) }
    }
    p = pm.next
  }
  r
}
## GENERICS (§8 mono): the ELEMENT WORD STRIDE of a param `[ns,nl]` whose declared type is the active
## instance's type-param resolving to an ARRAY `[E; N]` (WAT_SUB_ITS points at `[`) with a SCALAR element.
## Such a param is passed BY REFERENCE (its WASM local holds the array base address), so `a[i]` loads at
## `base + i*stride*8`. Returns 1 (scalar element = 1 word), else 0 (struct/enum element → fail-loud index).
## Reads the substitution GLOBALS + scans the element span INLINE. Mirrors a64_param_gen_arr_stride.
wat_param_gen_arr_stride := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if WAT_SUB_GPL == 0 { return 0 }
  if str_at((src + WAT_SUB_ITS), 1) != "[" { return 0 }
  mut p := params_head
  mut isgen := false
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { if streq(src, pm.ts, pm.tl, WAT_SUB_GPS, WAT_SUB_GPL) { isgen = true } }
    p = pm.next
  }
  if not isgen { return 0 }
  mut adep := 0
  mut asemi := WAT_SUB_ITS + 1
  mut ap := WAT_SUB_ITS + 1
  mut ago := true
  while ago and ap < WAT_SUB_ITS + WAT_SUB_ITL {
    ac := str_at((src + ap), 1)
    if ac == "(" or ac == "[" { adep = adep + 1 }
    else if (ac == ")" or ac == "]") and adep > 0 { adep = adep - 1 }
    else if ac == ";" and adep == 0 { asemi = ap ; ago = false }
    ap = ap + 1
  }
  mut aes := WAT_SUB_ITS + 1
  while aes < asemi and str_at((src + aes), 1) == " " { aes = aes + 1 }
  mut aet := asemi
  while aet > aes and str_at((src + aet - 1), 1) == " " { aet = aet - 1 }
  if struct_decl_of(decls, src, aes, aet - aes) >= 0 { return 0 }
  if enum_decl_of(decls, src, aes, aet - aes) >= 0 { return 0 }
  1
}
## GENERICS (§8 mono): the element COUNT N of the active instance array type `[E; N]` (WAT_SUB_ITS/ITL),
## for the CG-7 bounds check on a generic array-param index. 0 if the instance type is not an array.
## Inline `;`-scan + digit parse over the globals. Mirrors a64_sub_arr_len.
wat_sub_arr_len := fn(src : ptr(u8)) -> i64 {
  if str_at((src + WAT_SUB_ITS), 1) != "[" { return 0 }
  mut ndep := 0
  mut nsemi := WAT_SUB_ITS + 1
  mut np := WAT_SUB_ITS + 1
  mut ngo := true
  while ngo and np < WAT_SUB_ITS + WAT_SUB_ITL {
    nc := str_at((src + np), 1)
    if nc == "(" or nc == "[" { ndep = ndep + 1 }
    else if (nc == ")" or nc == "]") and ndep > 0 { ndep = ndep - 1 }
    else if nc == ";" and ndep == 0 { nsemi = np ; ngo = false }
    np = np + 1
  }
  mut nlp := nsemi + 1
  mut nval := 0
  while nlp < WAT_SUB_ITS + WAT_SUB_ITL {
    nbs := bytes(str_at((src + nlp), 1))
    nb := nbs[0]
    if nb >= 48 and nb <= 57 { nval = nval * 10 + i64(nb - 48) }
    nlp = nlp + 1
  }
  nval
}
## The CURRENT match arm's variant context (§8 comptime-variant unroll), set per generated arm in
## emit_wat_stmt_match's wild==2 unroll: the scrutinee enum span (WAT_ARM_ENS/ENL), the CURRENT variant
## (WAT_ARM_VS/VL), and the arm's payload binding-list head (WAT_ARM_BINDS, pointer bits). An IMPLICIT
## generic call `hash(p)` in the body infers its type-arg from `p`'s variant-payload type via these.
## WAT_ARM_ENL == 0 = not inside such an arm. WAT_CFVAR = the unroll's current variant name (`T.(v)`).
mut WAT_ARM_ENS := 0
mut WAT_ARM_ENL := 0
mut WAT_ARM_VS := 0
mut WAT_ARM_VL := 0
mut WAT_ARM_BINDS := 0
mut WAT_CFVAR_S := 0
mut WAT_CFVAR_L := 0

## Does the fn (its param list) have a `T : type` comptime type-param?
wat_fn_is_generic := fn(params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena) -> bool {
  mut p := params_head
  mut g := false
  while p != 0 { pm := deref(param_p(p)) ; if str_at((src + pm.ts), pm.tl) == "type" { g = true } ; p = pm.next }
  g
}
## The first type-param's NAME span (the `T` of `T : type`), 0/0 if none.
wat_tparam_name := fn(d : Decl, src : ptr(u8)) -> WSpan {
  mut p := d.params_head
  mut r := WSpan(s = 0, n = 0)
  while p != 0 { pm := deref(param_p(p)) ; if r.n == 0 and str_at((src + pm.ts), pm.tl) == "type" { r = WSpan(s = pm.ns, n = pm.nl) } ; p = pm.next }
  r
}
## Resolve the concrete type-arg span of a generic call `[cs,cl](args)` into WAT_TA_S / WAT_TA_N (0/0
## when unresolved → the caller uses a fail-loud trap). EXPLICIT (`argc == arity`): the arg at the
## type-param's source position (a bare type NAME Var). IMPLICIT (`id(k)`): infer from the value arg
## whose param is the type-param `T` — a Var naming an enclosing PARAM yields that param's declared
## type; a struct/enum LITERAL yields its bare type name. Then the ENCLOSING instance's own type-param
## is substituted (a nested generic call inside an instance). Single leading type-param (cluster 1).
wat_resolve_typearg := fn(decls : ptr(rt::Vec), src : ptr(u8), gi : i64, args_head : ptr(mut Arg), penv : ptr(mut Param), a : rt::Arena) {
  gd := deref(decl_get(decls, usize(gi)))
  argc := arg_list_count(args_head, a)
  mut ts := 0
  mut tl := 0
  if argc == i64(gd.arity) {
    tpp := decl_tparam_pos(gd, src)
    ea := arg_expr_at(args_head, usize(tpp), a)
    evn := expr_var_name(ea)
    ts = evn.s
    tl = evn.n
    ## a TUPLE `(T0, …)` / ARRAY `[T; N]` type-arg parses as an ArrayLit (not a Var) — recover its full
    ## `(…)`/`[…]` source span (mono keys + the tag mangling both read it). Mirrors a64/x86.
    if tl == 0 {
      tt := tuple_typearg_span(ea, src, a)
      ts = tt.s
      tl = tt.n
    }
    ## `f.type` (§8 field-derive): the type-arg is `Field(Var(f), "type")` where `f` is the active
    ## comptime field-unroll loop var (WAT_CF_VAR set) → the CURRENT field's TYPE (WAT_CF_TY), so
    ## `hash(f.type, v.(f))` routes into the per-field concrete instance. Mirrors a64/x86 cf_ty. Uses the
    ## Field accessors (NOT an inline match — a nested match mis-lowers under the seed).
    if tl == 0 and WAT_CF_VAR_L != 0 {
      cfb := expr_field_base(ea)
      cfsp := expr_field_span(ea)
      cfbn := expr_var_name(cfb)
      if cfbn.n != 0 and cfsp.n != 0 and streq(src, cfbn.s, cfbn.n, WAT_CF_VAR_S, WAT_CF_VAR_L) and str_at((src + cfsp.s), cfsp.n) == "type" {
        ts = WAT_CF_TY_S
        tl = WAT_CF_TY_L
      }
    }
  } else {
    tpn := wat_tparam_name(gd, src)
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
    avn := expr_var_name(a0)
    if avn.n != 0 {
      mut p := penv
      while p != 0 { pm := deref(param_p(p)) ; if tl == 0 and streq(src, pm.ns, pm.nl, avn.s, avn.n) { ts = pm.ts ; tl = pm.tl } ; p = pm.next }
    }
    if tl == 0 { sn := expr_struct_name(a0) ; if sn.n != 0 { ts = sn.s ; tl = sn.n } }
    if tl == 0 { en := expr_enum_name(a0) ; if en.n != 0 { ts = en.s ; tl = en.n } }
    ## a Var naming the CURRENT match arm's SINGLE payload BINDING (`hash(p)` inside `T.(var)(p) => …`):
    ## infer T from the variant's payload type (WAT_ARM_* context). Verified against the arm's bind list
    ## so an unrelated local is never mis-resolved. Enables the enum-derive recursion (comptime_enum_hash).
    if tl == 0 and avn.n != 0 and WAT_ARM_ENL != 0 and WAT_ARM_BINDS != 0 {
      bh := unchecked bitcast(ptr(mut Bind), WAT_ARM_BINDS)
      bidx := bind_list_index(bh, src, avn.s, avn.n, a)
      mut bcnt := 0
      mut bb := bh
      while unchecked bitcast(usize, bb) != 0 { bcnt = bcnt + 1 ; bb = bnd_next(bb) }
      if bidx == 0 and bcnt == 1 {
        pty := variant_payload_type(decls, src, WAT_ARM_ENS, WAT_ARM_ENL, WAT_ARM_VS, WAT_ARM_VL, a)
        if pty.n != 0 { ts = pty.s ; tl = pty.n }
      }
    }
  }
  if WAT_SUB_GPL != 0 and tl != 0 and streq(src, ts, tl, WAT_SUB_GPS, WAT_SUB_GPL) { ts = WAT_SUB_ITS ; tl = WAT_SUB_ITL }
  WAT_TA_S = ts
  WAT_TA_N = tl
  ## MULTI type-param (leading RUN, `pick3(A, B, C, …)`): resolve the 2nd/3rd EXPLICIT type-args (bare
  ## scalar names at source positions 1/2). Reset first so a single-type-param instance carries 0/0.
  ## Mirrors a64_resolve_typearg.
  WAT_TA_S2 = 0
  WAT_TA_N2 = 0
  WAT_TA_S3 = 0
  WAT_TA_N3 = 0
  lead := decl_leading_tparam_run(gd, src)
  cntt := decl_tparam_count(gd, src)
  if argc == i64(gd.arity) and cntt == lead and lead >= 2 {
    e1 := arg_expr_at(args_head, 1, a)
    e1v := expr_var_name(e1)
    mut s2 := e1v.s
    mut l2 := e1v.n
    if WAT_SUB_GPL != 0 and l2 != 0 and streq(src, s2, l2, WAT_SUB_GPS, WAT_SUB_GPL) { s2 = WAT_SUB_ITS ; l2 = WAT_SUB_ITL }
    WAT_TA_S2 = s2
    WAT_TA_N2 = l2
  }
  if argc == i64(gd.arity) and cntt == lead and lead >= 3 {
    e2 := arg_expr_at(args_head, 2, a)
    e2v := expr_var_name(e2)
    mut s3 := e2v.s
    mut l3 := e2v.n
    if WAT_SUB_GPL != 0 and l3 != 0 and streq(src, s3, l3, WAT_SUB_GPS, WAT_SUB_GPL) { s3 = WAT_SUB_ITS ; l3 = WAT_SUB_ITL }
    WAT_TA_S3 = s3
    WAT_TA_N3 = l3
  }
}
## Record instance (gi, ts, tl + the 2nd/3rd type-args from WAT_TA_*2/*3) if new (dedup by gi + all
## type-arg text). The 2nd/3rd spans are read from the resolver's OUT globals (set by the immediately
## preceding wat_resolve_typearg). Bounded by the array size.
wat_inst_add := fn(src : ptr(u8), gi : usize, ts : usize, tl : usize) {
  mut i := 0
  mut found := false
  while i < WAT_INST_N {
    same0 := WAT_INST_GI[i] == gi and streq(src, WAT_INST_TS[i], WAT_INST_TL[i], ts, tl)
    same2 := streq(src, WAT_INST_TS2[i], WAT_INST_TL2[i], WAT_TA_S2, WAT_TA_N2)
    same3 := streq(src, WAT_INST_TS3[i], WAT_INST_TL3[i], WAT_TA_S3, WAT_TA_N3)
    if same0 and same2 and same3 { found = true }
    i = i + 1
  }
  if (not found) and WAT_INST_N < 512 {
    WAT_INST_GI[WAT_INST_N] = gi
    WAT_INST_TS[WAT_INST_N] = ts
    WAT_INST_TL[WAT_INST_N] = tl
    WAT_INST_TS2[WAT_INST_N] = WAT_TA_S2
    WAT_INST_TL2[WAT_INST_N] = WAT_TA_N2
    WAT_INST_TS3[WAT_INST_N] = WAT_TA_S3
    WAT_INST_TL3[WAT_INST_N] = WAT_TA_N3
    WAT_INST_N = WAT_INST_N + 1
  }
}
## The element-type span E of the `Slice(E)` PARAM `[ns,nl]`, or {0,0}.
wat_slice_param_elem_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize) -> WSpan {
  mut p := params_head
  mut r := WSpan(s = 0, n = 0)
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { r = wat_slice_elem_span(src, pm.ns, pm.nl) }
    p = pm.next
  }
  r
}
## Element WORD stride of the `Slice(E)` PARAM `[ns,nl]`: struct_words for struct E, 1+enum_max_arity for
## enum E, else 0.
wat_slice_param_agg_stride := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  es := wat_slice_param_elem_span(params_head, src, ns, nl)
  mut r := 0
  if es.n != 0 {
    if struct_decl_of(decls, src, es.s, es.n) >= 0 { r = i64(struct_words(decls, src, es.s, es.n, a)) }
    if enum_decl_of(decls, src, es.s, es.n) >= 0 { r = 1 + i64(enum_max_arity(decls, src, es.s, es.n, a)) }
  }
  r
}
## Element STRUCT span of the `Slice(P)` PARAM `[ns,nl]` (P a struct), else {0,0}.
wat_slice_param_struct_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> WSpan {
  es := wat_slice_param_elem_span(params_head, src, ns, nl)
  mut r := WSpan(s = 0, n = 0)
  if es.n != 0 { if struct_decl_of(decls, src, es.s, es.n) >= 0 { r = es } }
  r
}
## Element ENUM span of the `Slice(E)` PARAM `[ns,nl]` (E an enum), else {0,0}.
wat_slice_param_enum_span := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> WSpan {
  es := wat_slice_param_elem_span(params_head, src, ns, nl)
  mut r := WSpan(s = 0, n = 0)
  if es.n != 0 { if enum_decl_of(decls, src, es.s, es.n) >= 0 { r = es } }
  r
}

## Is the `.len()` receiver a slice this backend can read — a scalar `Slice(E)` PARAM or a local slice VIEW?
wat_len_recv_slice := fn(recv : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), body_head : ptr(mut Stmt), decls : ptr(rt::Vec), a : rt::Arena) -> bool {
  rn := expr_var_name(recv)
  mut r := false
  if rn.n != 0 {
    if wat_slice_param_scalar(params_head, src, rn.s, rn.n, a, decls) { r = true }
    if is_slice_local(body_head, src, rn.s, rn.n, a) { r = true }
  }
  r
}

## Is the LOCAL `[ns, ns+nl)` an ARRAY (its `:=` init is an ArrayLit)? An array local holds the base
## address of its elements in linear memory; `a[i]` loads word `i` (scalar elements, stride 8).
is_array_local := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> bool {
  d := lower_layout::local_decl_assign(fn_head, src, ns, nl)
  mut r := false
  if unchecked bitcast(usize, d) != 0 {
    stmt := deref(stmt_p(Stmt, d))
    match stmt {
      Stmt::Assign(ans, anl, v, nx) => {
        if ex_is_array_lit(v) { r = true }
        if (not r) and wat_call_ret_tuple_words(v, wat_decls(), src, a) > 0 { r = true }
        ## `mut xs : [E; N]` — an explicitly UNINITIALIZED fixed-array local. The parser plants a
        ## Num(0) sentinel, so its array-ness lives only in the source annotation.
        if (not r) and wat_ann_arr_nel(src, ans, anl, v) > 0 { r = true }
      }
      _ => {}
    }
  }
  r
}

## The element COUNT of the array LOCAL `[ns,nl]` (its `:=` ArrayLit length), 0 if none — the static
## bound for a `verify.checked` index guard (the WASM analogue of x86_64's `ent.snl`). Same scan shape
## as `is_array_local`.
array_local_nel := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> usize {
  mut s := fn_head
  mut r := 0
  mut done := false
  while s != 0 and (not done) {
    stmt := deref(stmt_p(Stmt, s))
    match stmt {
      ## `mut xs : [E; N]` — the UNINITIALIZED form: the static bound comes from the annotation.
      Stmt::Assign(ans, anl, v, nx) => { if streq(src, ans, anl, ns, nl) { if ex_is_array_lit(v) { r = array_lit_nel(v) } else { tw := wat_call_ret_tuple_words(v, wat_decls(), src, a) ; if tw > 0 { r = usize(tw) } else { an := wat_ann_arr_nel(src, ans, anl, v) ; if an > 0 { r = usize(an) } } } ; done = true } ; s = nx }
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
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::Match(msc, mah, mnx) => { s = mnx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  r
}

## Element WORD stride of an ARRAY-LIT `v`: struct_words for a StructLit first element, 1+enum_max_arity
## for an EnumLit first element, else 1 (scalar). Drives multi-word aggregate-array layout — the WASM dual
## of x86_64's `ent.estride`. An empty array-lit → 1 (scalar-neutral).
array_lit_stride := fn(v : ptr(Expr), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut w := 1
  eh := ex_array_lit_ehead(v)
  if eh != 0 {
    a0 := deref(arg_p(eh))
    e0 := a0.e
    sp := expr_struct_name(e0)
    if sp.n != 0 {
      if std_array_elem_byte_tier(decls, src, sp.s, sp.n, a) { w = i64(array_elem_word_reservation(decls, src, sp.s, sp.n, a)) }
      if not std_array_elem_byte_tier(decls, src, sp.s, sp.n, a) { require_no_byte_layout_array_elem(decls, src, sp.s, sp.n, a) ; w = i64(struct_words(decls, src, sp.s, sp.n, a)) }
    }
    ep := expr_enum_name(e0)
    if ep.n != 0 { w = 1 + i64(enum_max_arity(decls, src, ep.s, ep.n, a)) }
  }
  w
}
## Element WORD stride of the array LOCAL `[ns,nl]` via its `:=` ArrayLit — 1 for a scalar/unknown base.
array_local_stride := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  mut s := fn_head
  mut r := 1
  mut done := false
  while s != 0 and (not done) {
    stmt := deref(stmt_p(Stmt, s))
    match stmt {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) {
          if ex_is_array_lit(v) { r = array_lit_stride(v, src, a, decls) ; done = true }
          ## a slice VIEW `s := base[lo..hi]` inherits the base ARRAY's element stride.
          if ex_is_slice(v) { bn := expr_var_name(ex_slice_base(v)) ; r = array_local_stride(fn_head, src, bn.s, bn.n, a, decls) ; done = true }
          ## `mut xs : [E; N]` — the UNINITIALIZED form: the stride is the DECLARED element's word width.
          if not done {
            ae := wat_ann_arr_elem(src, ans, anl, v)
            if ae.n != 0 { aw := wat_tyname_words(src, ae.s, ae.n, a, decls) ; if aw > 0 { r = aw ; done = true } }
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
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::Match(msc, mah, mnx) => { s = mnx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  ## not a body local — a struct/enum-element `Slice(E)` PARAM base has its stride from the param annotation.
  if not done { ps := wat_slice_param_agg_stride(wat_params(), src, ns, nl, a, wat_decls()) ; if ps > 0 { r = ps } }
  r
}
## The element STRUCT span of the array LOCAL `[ns,nl]` (or a slice VIEW over one) — its first ArrayLit
## element's StructLit name — or {0,0}. Types an aggregate for-loop var so `p.field` reads resolve.
arr_elem_struct_span := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> WSpan {
  mut s := fn_head
  mut r := WSpan(s = 0, n = 0)
  mut done := false
  while s != 0 and (not done) {
    stmt := deref(stmt_p(Stmt, s))
    match stmt {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) {
          if ex_is_array_lit(v) {
            r = wat_arr_lit_elem_struct(v, src)
            done = true
          }
          if ex_is_slice(v) { bn := expr_var_name(ex_slice_base(v)) ; r = arr_elem_struct_span(fn_head, src, bn.s, bn.n, a) ; done = true }
          ## `mut xs : [E; N]` — the UNINITIALIZED form: the element struct comes from the annotation.
          ## Only a real STRUCT element is reported (this resolver's contract); a scalar-element array
          ## keeps {0,0} so nothing types a `u64` element as an aggregate.
          if not done {
            ae := wat_ann_arr_elem(src, ans, anl, v)
            if ae.n != 0 { if struct_decl_of(wat_decls(), src, ae.s, ae.n) >= 0 { r = ae ; done = true } }
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
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::Match(msc, mah, mnx) => { s = mnx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  ## not a body local — a struct-element `Slice(P)` PARAM base takes its element struct from the annotation.
  if not done { ps := wat_slice_param_struct_span(wat_params(), src, ns, nl, wat_decls()) ; if ps.n != 0 { r = ps } }
  r
}

## --- AGGREGATE-ELEMENT ARRAYS (`[S; N]`, S a struct). `a[i]` is NOT a word load: the element occupies
## `stride` words, so the element VALUE is its BASE ADDRESS in linear memory (the by-reference convention
## a struct local/param already uses). These two resolvers unify the four bases an indexed place can have
## — an array LOCAL, a range-slice VIEW local, an array GLOBAL, and a `Slice(S)` PARAM — so the Index /
## Field / Assign / IndexAssign arms all key off one predicate. ---
## The element STRUCT span of the ARRAY-ish place named `[ns,nl]`, else {0,0}.
wat_arr_elem_struct := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  if nl == 0 { return r }
  if is_array_local(fn_head, src, ns, nl, a) { return arr_elem_struct_span(fn_head, src, ns, nl, a) }
  if is_slice_local(fn_head, src, ns, nl, a) { return arr_elem_struct_span(fn_head, src, ns, nl, a) }
  if wat_is_array_global(decls, src, ns, nl, a) { return wat_array_global_elem_struct(decls, src, ns, nl, a) }
  return wat_slice_param_struct_span(wat_params(), src, ns, nl, decls)
}

## The element WORD stride of the ARRAY-ish place named `[ns,nl]` — 1 when unknown/scalar. An array
## GLOBAL reads its ArrayLit; everything else routes through array_local_stride (which itself falls back
## to the slice-PARAM annotation).
wat_arr_elem_stride := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if nl == 0 { return 1 }
  if wat_is_array_global(decls, src, ns, nl, a) { return wat_array_global_stride(decls, src, ns, nl, a) }
  return array_local_stride(fn_head, src, ns, nl, a, decls)
}

## --- TYPED-DECLARATION (annotation) SOURCE-SCAN: `mut xs : [Cell; 3]` (Types §9.4) ---
## The parser keeps the `Stmt.Assign` shape for an explicitly uninitialized `name : T` and plants a
## `Num(0)` SENTINEL value (so no bootstrap-sensitive AST field is added), which leaves the element TYPE
## and COUNT recorded ONLY in the source. These scans recover them — the same source-scan technique
## `ann_scan_signed` already uses for `iN` signedness — so the declaration can RESERVE a linear-memory
## block and the element paths can TYPE it. Without them a `mut xs : [S; N]` set its WASM local to
## `(i64.const 0)` (no storage at all) and every access was fail-loud.


## The `: T` annotation span that FOLLOWS the declaration name `[ns,nl)`, or {0,0} for `:=` (inferred),
## a missing annotation, or a malformed one. `[`/`(` nesting is tracked so `[Cell; 3]` spans whole; the
## span ENDS at a depth-0 `=` (an INITIALIZED `name : T = v` still yields its annotation), newline, `;`
## or `}`. Mirrors rv_ann_span / ast::local_type_span but returns the wat `WSpan`.
wat_ann_span := fn(src : ptr(u8), ns : usize, nl : usize) -> WSpan {
  mut p := ns + nl
  lim := p + 512
  mut go := true
  while go { c := str_at((src + p), 1) ; if c == " " or c == "\t" or c == "\r" { p = p + 1 } else { go = false } }
  if str_at((src + p), 1) != ":" { return WSpan(s = 0, n = 0) }
  p = p + 1
  go = true
  while go { c := str_at((src + p), 1) ; if c == " " or c == "\t" or c == "\r" { p = p + 1 } else { go = false } }
  if str_at((src + p), 1) == "=" { return WSpan(s = 0, n = 0) }
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
  if not term { return WSpan(s = 0, n = 0) }
  mut te := p
  mut trim := true
  while trim and te > ts {
    t := str_at((src + te - 1), 1)
    if t == " " or t == "\t" or t == "\r" { te = te - 1 } else { trim = false }
  }
  if te <= ts { return WSpan(s = 0, n = 0) }
  WSpan(s = ts, n = te - ts)
}


## `[E; N]` → the ELEMENT type span E (trimmed), else {0,0}.
wat_arrty_elem := fn(src : ptr(u8), ts : usize, tl : usize) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  semi := arrty_semi(src, ts, tl)
  if semi == 0 { return r }
  mut es := ts + 1
  mut go := true
  while go and es < semi { c := str_at((src + es), 1) ; if c == " " or c == "\t" { es = es + 1 } else { go = false } }
  mut ee := semi
  mut trim := true
  while trim and ee > es { t := str_at((src + ee - 1), 1) ; if t == " " or t == "\t" { ee = ee - 1 } else { trim = false } }
  if ee > es { r = WSpan(s = es, n = ee - es) }
  r
}

## `[E; N]` → the static element COUNT N, else 0 (not a fixed-array type, or a non-literal length — a
## `[T; <comptime expr>]` stays 0 so every dependent path falls back to the fail-loud default).
wat_arrty_nel := fn(src : ptr(u8), ts : usize, tl : usize) -> i64 {
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
wat_tyname_words := fn(src : ptr(u8), ts : usize, tl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
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
  es := wat_arrty_elem(src, ts, tl)
  if es.n != 0 {
    ew := wat_tyname_words(src, es.s, es.n, a, decls)
    nel := wat_arrty_nel(src, ts, tl)
    if ew > 0 { if nel > 0 { r = nel * ew } }
    return r
  }
  if str_at((src + ts), tl) == "str" { return r }
  1
}

## Runtime ARRAY-ELEMENT stride in BYTES. Reservation remains word-denominated; only the proven
## standard byte-tier struct element diverges from the historical word model here.
wat_arr_elem_stride_bytes := fn(src : ptr(u8), ts : usize, tl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if std_array_elem_byte_tier(decls, src, ts, tl, a) { return i64(layout_elem_stride_bytes(decls, src, ts, tl, a)) }
  i64(wat_tyname_words(src, ts, tl, a, decls)) * 8
}

## Is the type `[ts,tl)` a genuine ONE-WORD SCALAR? `ty_is_scalar` alone says yes to a `[u64; 3]`
## array type (no struct/enum decl, not `str`), which would let a one-word `i64.load` stand in for a
## whole array — so the word width must agree too.
wat_ty_word_scalar := fn(src : ptr(u8), ts : usize, tl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if tl == 0 { return r }
  if not ty_is_scalar(ts, tl, decls, src) { return r }
  if wat_tyname_words(src, ts, tl, a, decls) == 1 { r = true }
  r
}

## The static element COUNT of a declaration `name : [E; N]` whose value is NOT an array literal (the
## explicitly uninitialized form), else 0 — so an INITIALIZED `xs : [E;N] = [..]` keeps every existing
## ArrayLit-driven answer byte-identical.
wat_ann_arr_nel := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr)) -> i64 {
  if ex_is_array_lit(v) { return 0 }
  an := wat_ann_span(src, ns, nl)
  if an.n == 0 { return 0 }
  wat_arrty_nel(src, an.s, an.n)
}

## The declared ELEMENT type span of the same, else {0,0}.
wat_ann_arr_elem := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr)) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  if ex_is_array_lit(v) { return r }
  an := wat_ann_span(src, ns, nl)
  if an.n != 0 { r = wat_arrty_elem(src, an.s, an.n) }
  r
}

## The linear-memory WORDS a declaration `mut xs : [E; N]` must RESERVE, else 0. Gated on the value
## being the parser's `Num(0)` SENTINEL (the explicitly-uninitialized form) AND the annotation being the
## fixed-array form, so a `name : T = <value>` declaration keeps taking its existing emit path unchanged.
wat_ann_arr_words := fn(src : ptr(u8), ns : usize, nl : usize, v : ptr(Expr), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not ex_is_zero_lit(v) { return 0 }
  an := wat_ann_span(src, ns, nl)
  if an.n == 0 { return 0 }
  if arrty_semi(src, an.s, an.n) == 0 { return 0 }
  wat_tyname_words(src, an.s, an.n, a, decls)
}

## The `: T` annotation at the DECLARATION SITE of the LOCAL `[ns,nl]` (an `Expr::Var` carries the span
## of its USE, not of the binding), or {0,0}. Same scan shape as `is_array_local` — every Stmt kind is
## walked past, so a local declared after any statement is still found.
wat_local_ann_span := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  d := lower_layout::local_decl_assign(head, src, ns, nl)
  if unchecked bitcast(usize, d) != 0 {
    st := deref(stmt_p(Stmt, d))
    match st {
      Stmt::Assign(ans, anl, v, nx) => { r = wat_ann_span(src, ans, anl) }
      _ => {}
    }
  }
  r
}

## The DECLARED fixed-array type span of the local `[ns,nl]` (`mut xs : [Cell; 3]` → `[Cell; 3]`), or
## {0,0}. This is the only place a LOCAL's array TYPE (rather than its literal) is recovered.
wat_local_arrty_span := fn(head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  an := wat_local_ann_span(head, src, ns, nl, a)
  if an.n == 0 { return r }
  if arrty_semi(src, an.s, an.n) != 0 { r = an }
  r
}

## --- DEEP AGGREGATE PLACES (Types §9.4): an ADDRESS composed from a frame-local root + N hops ---
## `xs[i].b.c.cx`, `xs[i].arr[j]`, `b.cells[i].m` — an arbitrary chain of FIELD and INDEX hops rooted at
## a struct or fixed-array LOCAL. The one-hop element paths address `element base + field offset` with a
## CLOSED formula; anything deeper (a second field hop, or an index into an inline `[T; N]` FIELD) has no
## such formula, so every such access was fail-loud. These resolvers COMPOSE it instead. In WASM an
## address is an ordinary i64 EXPRESSION — no scratch register, no push/pop — so a hop is one nested
## `(i64.add …)`: a FIELD hop adds `woff*8`, an INDEX hop adds `(i64.mul <index> (i64.const ew*8))`.
## The LEAF load/store is a SINGLE word, gated on the leaf type being a one-word SCALAR; an aggregate
## leaf stays fail-loud. FRAME-LOCAL roots only (a param / bind / global root keeps its existing path).


## STANDARD BYTE-LAYOUT PLACE RESOLUTION (CLAYOUT S3a). A standard-byte struct local already holds
## a linear-memory base address in its WASM local; the only change is that FIELD hops use byte offsets,
## not the legacy word offsets. Keep this resolver narrow: a local struct root followed by FIELD hops,
## with no params/globals/indexes. Other shapes keep their existing fail-loud paths.
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
wat_std_path_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  if ex_is_field(e) {
    bt := wat_std_path_ty(expr_field_base(e), body_head, src, a, decls)
    if bt.n != 0 { r = struct_field_type(decls, src, bt.s, bt.n, expr_field_span(e).s, expr_field_span(e).n, a) }
  }
  if not ex_is_field(e) {
    vn := expr_var_name(e)
    if vn.n != 0 {
      rs := local_struct_type(body_head, src, vn.s, vn.n, a, decls)
      if rs.n != 0 and layout_kind_is_byte(layout_kind(decls, src, rs.s, rs.n, a)) { r = rs }
    }
  }
  r
}

wat_std_path_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_field(e) { return false }
  base := expr_field_base(e)
  bt := wat_std_path_ty(base, body_head, src, a, decls)
  if bt.n == 0 { return false }
  layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_span(e).s, expr_field_span(e).n, a) >= 0
}

wat_std_path_bo := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not wat_std_path_ok(e, body_head, src, a, decls) { return 0 - 1 }
  base := expr_field_base(e)
  mut pbo := i64(0)
  if ex_is_field(base) { pbo = wat_std_path_bo(base, body_head, src, a, decls) }
  bt := wat_std_path_ty(base, body_head, src, a, decls)
  pbo + layout_field_offset_bytes(decls, src, bt.s, bt.n, expr_field_span(e).s, expr_field_span(e).n, a)
}

wat_std_path_root_idx := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not wat_std_path_ok(e, body_head, src, a, decls) { return 0 - 1 }
  base := expr_field_base(e)
  if ex_is_field(base) { return wat_std_path_root_idx(base, body_head, src, pcount, a, decls) }
  vn := expr_var_name(base)
  name_local_index(body_head, src, vn.s, vn.n, pcount, a, decls)
}

## PARAMETER twin of the standard-byte path. WASM struct parameters already carry a linear-memory base
## address in their parameter local, so the byte-tier consumer only needs to resolve that local and apply
## the shared byte offset. It is separate from the local-only path to leave every existing non-byte route
## unchanged and fail-loud.
wat_std_param_path_ty := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  if ex_is_field(e) {
    base := expr_field_base(e)
    bt := wat_std_param_path_ty(base, params_head, src, a, decls)
    if bt.n != 0 {
      fs := expr_field_span(e)
      r = struct_field_type(decls, src, bt.s, bt.n, fs.s, fs.n, a)
    }
  }
  if not ex_is_field(e) {
    vn := expr_var_name(e)
    if vn.n != 0 and param_find(params_head, src, vn.s, vn.n, a) >= 0 {
      rs := wat_param_struct_span(params_head, src, vn.s, vn.n, a, decls)
      if rs.n != 0 and layout_kind_is_byte(layout_kind(decls, src, rs.s, rs.n, a)) { r = rs }
    }
  }
  r
}

wat_std_param_path_ok := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_field(e) { return false }
  base := expr_field_base(e)
  bt := wat_std_param_path_ty(base, params_head, src, a, decls)
  if bt.n == 0 { return false }
  fs := expr_field_span(e)
  layout_field_offset_bytes(decls, src, bt.s, bt.n, fs.s, fs.n, a) >= 0
}

wat_std_param_path_bo := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not wat_std_param_path_ok(e, params_head, src, a, decls) { return 0 - 1 }
  base := expr_field_base(e)
  mut pbo := i64(0)
  if ex_is_field(base) { pbo = wat_std_param_path_bo(base, params_head, src, a, decls) }
  bt := wat_std_param_path_ty(base, params_head, src, a, decls)
  fs := expr_field_span(e)
  pbo + layout_field_offset_bytes(decls, src, bt.s, bt.n, fs.s, fs.n, a)
}

wat_std_param_path_idx := fn(e : ptr(Expr), params_head : ptr(mut Param), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  if not wat_std_param_path_ok(e, params_head, src, a, decls) { return 0 - 1 }
  base := expr_field_base(e)
  if ex_is_field(base) { return wat_std_param_path_idx(base, params_head, src, a, decls) }
  vn := expr_var_name(base)
  param_find(params_head, src, vn.s, vn.n, a)
}

## STANDARD BYTE-LAYOUT ARRAY-ELEMENT path. Its root is an Index into a supported byte-tier struct
## array; every following Field hop is resolved with the shared byte-offset oracle. Keeping this
## separate from wat_std_path preserves the fixed frame-local path and its historical emission.
wat_std_idx_path_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  if ex_is_index(e) {
    bt := wat_place_ty(ex_index_base(e), body_head, src, a, decls)
    if bt.n != 0 {
      et := wat_arrty_elem(src, bt.s, bt.n)
      if et.n != 0 and std_array_elem_byte_tier(decls, src, et.s, et.n, a) { r = et }
    }
    return r
  }
  if ex_is_field(e) {
    base := expr_field_base(e)
    bt := wat_std_idx_path_ty(base, body_head, src, a, decls)
    if bt.n != 0 {
      fs := expr_field_span(e)
      bo := layout_field_offset_bytes(decls, src, bt.s, bt.n, fs.s, fs.n, a)
      if bo >= 0 { r = struct_field_type(decls, src, bt.s, bt.n, fs.s, fs.n, a) }
    }
  }
  r
}

wat_std_idx_path_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  if not ex_is_index(e) and not ex_is_field(e) { return false }
  wat_std_idx_path_ty(e, body_head, src, a, decls).n != 0
}


## The TYPE span of the place `e` — a struct name, a `[E; N]` array-type span, or a scalar type name.
## A root Var takes its LOCAL's struct type, else its DECLARED fixed-array type; a Field hop takes the
## field's type within its (plain struct) base; an Index hop takes its base array type's element.
wat_place_ty := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  ## ONE `mut` accumulator + a bare `return r`, never `return <nested-call>` for a struct result: that
  ## shape is the lean lower's documented mis-lower.
  mut r := WSpan(s = 0, n = 0)
  if unchecked bitcast(usize, e) == 0 { return r }
  if ex_is_field(e) {
    bt := wat_place_ty(expr_field_base(e), body_head, src, a, decls)
    fsp := expr_field_span(e)
    mut fok := false
    if bt.n != 0 {
      if struct_decl_of(decls, src, bt.s, bt.n) >= 0 {
        if struct_plain(decls, src, bt.s, bt.n) { fok = true }
      }
    }
    if fok { r = struct_field_type(decls, src, bt.s, bt.n, fsp.s, fsp.n, a) }
    return r
  }
  if ex_is_index(e) {
    bt := wat_place_ty(ex_index_base(e), body_head, src, a, decls)
    if bt.n != 0 { r = wat_arrty_elem(src, bt.s, bt.n) }
    return r
  }
  vn := expr_var_name(e)
  if vn.n == 0 { return r }
  ls := local_struct_type(body_head, src, vn.s, vn.n, a, decls)
  if ls.n != 0 { r = ls }
  if ls.n == 0 { r = wat_local_arrty_span(body_head, src, vn.s, vn.n, a) }
  r
}

## Can `base[…]` be addressed as an aggregate/array element? (`base` resolvable, its type a `[E; N]`
## form, and E's word width known.) The INDEX-hop half of wat_place_ok, split out so the statement
## forms — which carry the base and the index as SEPARATE fields, with no `Expr::Index` node to pass —
## can ask the same question.
wat_place_idx_ok := fn(base : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if not wat_place_ok(base, body_head, src, params_head, pcount, a, decls) { return r }
  bt := wat_place_ty(base, body_head, src, a, decls)
  if bt.n == 0 { return r }
  if arrty_semi(src, bt.s, bt.n) == 0 { return r }
  et := wat_arrty_elem(src, bt.s, bt.n)
  if et.n == 0 { return r }
  if wat_arr_elem_stride_bytes(src, et.s, et.n, a, decls) > 0 { r = true }
  r
}

## The ELEMENT type span of `base[…]`, else {0,0} — the statement-form twin of wat_place_ty's Index hop.
wat_place_idx_ty := fn(base : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut r := WSpan(s = 0, n = 0)
  bt := wat_place_ty(base, body_head, src, a, decls)
  if bt.n != 0 { r = wat_arrty_elem(src, bt.s, bt.n) }
  r
}

## Is EVERY hop of the place `e` resolvable, with a frame-LOCAL root? A param / match-binding / global
## root is rejected (their storage is by-reference or label-based, addressed by the existing paths).
wat_place_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if unchecked bitcast(usize, e) == 0 { return r }
  if ex_is_field(e) {
    fbase := expr_field_base(e)
    fsp := expr_field_span(e)
    if not wat_place_ok(fbase, body_head, src, params_head, pcount, a, decls) { return r }
    bt := wat_place_ty(fbase, body_head, src, a, decls)
    if bt.n == 0 { return r }
    if struct_decl_of(decls, src, bt.s, bt.n) < 0 { return r }
    if not struct_plain(decls, src, bt.s, bt.n) { return r }
    mut foffok := field_word_offset(decls, src, bt.s, bt.n, fsp.s, fsp.n, a) >= 0
    if wat_std_idx_path_ok(e, body_head, src, a, decls) { foffok = layout_field_offset_bytes(decls, src, bt.s, bt.n, fsp.s, fsp.n, a) >= 0 }
    if not foffok { return r }
    ## FLATTENED-STORAGE guard. An ALL-SCALAR struct is written POSITIONALLY (one word per constructor
    ## argument) by the pre-existing emit — which agrees with `field_word_offset` for a genuinely SCALAR
    ## field, but NOT for a ONE-WORD nested STRUCT field: that word holds the inner block's ADDRESS
    ## (by-reference), so composing an offset THROUGH it would read a wrong address as data. A struct
    ## with any multi-word field goes through the new FLATTENED writer, where every hop is inline.
    ft := struct_field_type(decls, src, bt.s, bt.n, fsp.s, fsp.n, a)
    mut flat := true
    if struct_all_scalar(decls, src, bt.s, bt.n, a) {
      if not wat_ty_word_scalar(src, ft.s, ft.n, a, decls) { flat = false }
    }
    if flat { r = true }
    return r
  }
  if ex_is_index(e) {
    if wat_place_idx_ok(ex_index_base(e), body_head, src, params_head, pcount, a, decls) { r = true }
    return r
  }
  vn := expr_var_name(e)
  if vn.n == 0 { return r }
  if param_find(params_head, src, vn.s, vn.n, a) >= 0 { return r }
  if is_global(decls, src, vn.s, vn.n, a) { return r }
  pt := wat_place_ty(e, body_head, src, a, decls)
  if pt.n == 0 { return r }
  if is_toplevel_local(body_head, vn.s, vn.n, src, a) { r = true }
  r
}

## Is the place `e` a fully-composable DEEP place with a ONE-WORD SCALAR leaf? The single gate every deep
## read/write site shares. An aggregate leaf (a whole struct/array through a deep chain) stays fail-loud
## — it needs multi-word delivery, not an `i64.load`/`i64.store`.
wat_deep_scalar_ok := fn(e : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  if not wat_place_ok(e, body_head, src, params_head, pcount, a, decls) { return r }
  ty := wat_place_ty(e, body_head, src, a, decls)
  if ty.n == 0 { return r }
  if wat_ty_word_scalar(src, ty.s, ty.n, a, decls) { r = true }
  r
}

## Is `base[idx]` a composable DEEP index whose ELEMENT is a one-word scalar? (`xs[i].arr[j]`.)
wat_deep_idx_scalar_ok := fn(base : ptr(Expr), body_head : ptr(mut Stmt), src : ptr(u8), params_head : ptr(mut Param), pcount : i64, a : rt::Arena, decls : ptr(rt::Vec)) -> bool {
  mut r := false
  ety := wat_place_idx_ty(base, body_head, src, a, decls)
  if ety.n == 0 { return r }
  if not wat_ty_word_scalar(src, ety.s, ety.n, a, decls) { return r }
  if wat_place_idx_ok(base, body_head, src, params_head, pcount, a, decls) { r = true }
  r
}

## The WASM verification mode (I11 / CG-6/CG-7), mirroring the x86_64 lower's `LCtx.vchk` and the
## native backends' `A64_CHK`/`RV_CHK`: `checked` by default, cleared inside an `unchecked` scope. Its
## own global because each backend runs its own emit (not routed through `lower.al`).
mut WAT_CHK := true
## LOOP break/continue targets (per-fn, the WAT_CHK pattern — no threaded param). Each holds the WASM
## label id of the nearest enclosing loop: `break` → `(br $brk<WAT_BRK>)`, `continue` → `(br $cont<WAT_CONT>)`.
## Every loop names its outer `(block $brk<id>` (break = exit) and wraps its body in `(block $cont<id>`
## (continue = fall through to the increment/back-edge). Saved/restored around each loop so nesting
## resolves to the innermost. Mirrors x86 `cx.brk`/`cx.cont`.
mut WAT_LABEL_NEXT := 0
wat_next_label := fn() -> i64 { r := WAT_LABEL_NEXT ; WAT_LABEL_NEXT = WAT_LABEL_NEXT + 1 ; r }
mut WAT_BRK := 0
mut WAT_CONT := 0
## DEFER (Control Flow §9.3 / Memory §5.8) — the PENDING-CLEANUP stack of the fn being emitted. The
## parser desugars `defer <expr>` to a marker call `__defer(<expr>)` that STAYS in the statement list
## (so every scan sees the action's uses for free); the WAT emitter INTERCEPTS the marker — it never
## emits it inline — pushes the action here, and REPLAYS the pending actions LIFO at every NORMAL exit
## of the registering scope: the block's fall-through, a `break`/`continue` out of a loop body, a
## `return` and the fn's tail value (both of which drain the WHOLE stack, innermost first). A JUMP drain
## replays WITHOUT popping (the fall-through path still owes those cleanups); a SCOPE-END drain pops.
## Per-fn (reset in emit_wat_body), the WAT_CHK/WAT_BRK pattern — no threaded parameter. A program with
## more than 64 simultaneously-live defers overflows the stack; the push then fail-louds (see
## wat_defer_push) rather than silently dropping a cleanup.
mut WAT_DEF_E : [usize; 64] = [0; 64]
mut WAT_DEF_BLOCK : [bool; 64] = [false; 64]
mut WAT_DEF_N := 0
mut WAT_DEF_OVF := false
## When non-zero, emit_wat_stmts stops BEFORE this statement handle. A block defer's linked list
## continues through its __deferblkend marker into the enclosing list, so the drain temporarily sets
## this stop to keep the deferred unit together and avoid re-emitting the enclosing statements.
mut WAT_DEF_STOP := 0
## The defer-stack depth at the ENTRY of the nearest enclosing loop body — `break`/`continue` replay
## down to it (exactly the actions registered inside that body). Saved/restored around each loop
## alongside WAT_BRK/WAT_CONT, so a nested loop drains only its own.
mut WAT_BRK_DB := 0
mut WAT_CONT_DB := 0
## Recursion depth of the local-struct-type resolver's `q := p` (aggregate-COPY) chain. `local_struct_type`
## asks `base_struct_type` for the SOURCE var's type, which can land back in `local_struct_type` — a
## mutually-recursive pair a pathological `p := q ; q := p` would spin forever. Capped (6) so a deep but
## finite copy chain still resolves while a cycle bottoms out at {0,0} (fail-loud, never a wrong type).
mut WAT_LSD := 0

## The struct-type name of the LOCAL `[ns, ns+nl)` — found from its `:=` StructLit initializer in the
## fn's top-level body (`p := Pt(…)`), else {0,0}. Lets a `p.field` read resolve the field offset.
local_struct_type := fn(fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut s := fn_head
  mut rs := 0
  mut rn := 0
  mut done := false
  while s != 0 and (not done) {
    stmt := deref(stmt_p(Stmt, s))
    match stmt {
      Stmt::Assign(ans, anl, v, nx) => {
        if streq(src, ans, anl, ns, nl) {
          sp := expr_struct_name(v)
          if sp.n != 0 { rs = sp.s ; rn = sp.n ; done = true }
          ## a local bound to a struct-returning CALL (`p := make()`) is a struct local — its slot
          ## holds the returned base address (the callee built it in the `$__sp` bump region).
          if sp.n == 0 {
            cn := expr_call_name(v)
            if cn.n != 0 {
              cr := callee_ret_struct(decls, src, cn.s, cn.n, ex_call_argh(v), a)
              if cr.n != 0 { rs = cr.s ; rn = cr.n ; done = true }
            }
          }
          ## `x := arr[i]` over an AGGREGATE-element array/slice: x is a fresh copy of the element
          ## struct, so its slot holds a base address of that struct type.
          if rn == 0 and ex_is_index(v) {
            ibn := expr_var_name(ex_index_base(v))
            es := wat_arr_elem_struct(fn_head, src, ibn.s, ibn.n, a, decls)
            if es.n != 0 { rs = es.s ; rn = es.n ; done = true }
          }
          ## `q := p` — a whole-aggregate COPY from a struct VAR (local or param): q takes p's type.
          ## Depth-capped (WAT_LSD) because base_struct_type can re-enter this resolver.
          if rn == 0 and WAT_LSD < 6 {
            vn := expr_var_name(v)
            if vn.n != 0 {
              WAT_LSD = WAT_LSD + 1
              bs := base_struct_type(wat_params(), fn_head, src, vn.s, vn.n, a, decls)
              WAT_LSD = WAT_LSD - 1
              if bs.n != 0 { rs = bs.s ; rn = bs.n ; done = true }
            }
          }
          ## a standard-byte aggregate field copy `q := p.inner` takes the leaf struct type. The source
          ## address/byte offset is handled by the Assign emitter; this scan only types q's own slot.
          if rn == 0 and ex_is_field(v) {
            sfp := wat_std_path_ty(v, fn_head, src, a, decls)
            if wat_std_path_ok(v, fn_head, src, a, decls) and sfp.n != 0 {
              sbn := base_type_name(src, sfp.s, sfp.n)
              if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { rs = sbn.s ; rn = sbn.n ; done = true }
            }
          }
        }
        s = nx
      }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        ## an ITERABLE for over a struct-element array types its loop var as the element struct, so
        ## `p.field` reads resolve through it (the loop var holds `&a[i]` — a pointer to the element).
        if streq(src, fns, fnl, ns, nl) and unchecked bitcast(usize, fhi) == 0 {
          bn := expr_var_name(flo)
          es := arr_elem_struct_span(fn_head, src, bn.s, bn.n, a)
          if es.n != 0 { rs = es.s ; rn = es.n ; done = true }
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
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::Match(msc, mah, mnx) => { s = mnx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  WSpan(s = rs, n = rn)
}

## The declared struct-type name of the PARAM `[ns, ns+nl)` (its `: T` annotation span), else {0,0}.
## A struct param is passed as its i64 base address, so `p.field` in the callee loads from it.
param_struct_type := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena) -> WSpan {
  mut p := params_head
  mut rs := 0
  mut rn := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) { rs = pm.ts ; rn = pm.tl }
    p = pm.next
  }
  WSpan(s = rs, n = rn)
}

## The struct-type name of a base place named `[ns, ns+nl)` — a struct PARAM (by annotation) or a
## struct LOCAL (by its StructLit init), else {0,0}.
base_struct_type := fn(params_head : ptr(mut Param), fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  ps := param_struct_type(params_head, src, ns, nl, a)
  if ps.n != 0 { return ps }
  return local_struct_type(fn_head, src, ns, nl, a, decls)
}

## The declared TYPE-name span of field `[fs, fs+fl)` within struct type `[s, s+n)`, else {0,0}.
## Used to walk a nested field access (`o.i.v`): the type of `o.i` is field `i`'s declared type.
## Delegates to the shared field_type_span, which routes subst_field_ty: a type-PARAM field of a
## generic INSTANCE resolves to the instance's concrete type-arg (NESTED-GENERIC §8 — `Box(Pair(u64))`'s
## `v : T` → `Pair(u64)`), so a nested read `c.v.a` types `c.v` as the concrete aggregate. Aggregate-gated
## inside subst_field_ty (a scalar type-arg returns the param `T` unchanged, byte-identical). The struct
## span `[s,n]` MUST carry the type-args (`Box(Pair(u64))`, not the stripped base) for the recovery to fire.
## Mirrors a64's struct_all_scalar field-type subst.
struct_field_type := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, fs : usize, fl : usize, a : rt::Arena) -> WSpan {
  eff := field_type_span(decls, src, s, n, fs, fl, a)
  WSpan(s = eff.s, n = eff.n)
}

## The STRUCT-type name an expression evaluates to, for a nested struct PLACE: a bare `Var` (via
## base_struct_type) or a `Field` chain (`o.i` → field `i`'s declared type within `o`'s struct type,
## recursively). {0,0} for anything else. A nested struct field is stored BY REFERENCE (word holds the
## inner base address), so `o.i` as a value already yields the inner base — the Field arm then loads
## the sub-field from it. Value-returning recursion (no ptr(mut)); `match deref(e)` inline (seed-safe).
expr_struct_type_of := fn(e : ptr(Expr), params_head : ptr(mut Param), body_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut rs := 0
  mut rn := 0
  match deref(e) {
    Expr::Var(vs, vl) => {
      st := base_struct_type(params_head, body_head, src, vs, vl, a, decls)
      rs = st.s ; rn = st.n
    }
    Expr::Field(base, fs, fl) => {
      bt := expr_struct_type_of(base, params_head, body_head, src, a, decls)
      if bt.n != 0 {
        ft := struct_field_type(decls, src, bt.s, bt.n, fs, fl, a)
        rs = ft.s ; rn = ft.n
      }
    }
    ## `arr[i]` over an AGGREGATE-element array/slice: the element is a struct whose VALUE is its base
    ## address (the Index arm yields the address), so `arr[i].f` reads it like any nested struct place.
    Expr::Index(ib, ii) => {
      ibn := expr_var_name(ib)
      es := wat_arr_elem_struct(body_head, src, ibn.s, ibn.n, a, decls)
      rs = es.s ; rn = es.n
    }
    _ => {}
  }
  WSpan(s = rs, n = rn)
}

## The STRUCT span of an aggregate PLACE `v` — a struct VAR (local/param) or an `arr[i]` element of an
## aggregate-element array/slice — else {0,0}. A place is LIVE STORAGE someone else owns, so binding or
## storing from it must COPY its words, not alias its base address (`q := p` then `p.x = …` must not
## move `q.x`). StructLit/call RHSs are deliberately EXCLUDED: those already own a fresh block.
wat_place_agg_span := fn(v : ptr(Expr), params_head : ptr(mut Param), fn_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  if ex_is_index(v) {
    ibn := expr_var_name(ex_index_base(v))
    return wat_arr_elem_struct(fn_head, src, ibn.s, ibn.n, a, decls)
  }
  if ex_is_field(v) {
    sfp := wat_std_path_ty(v, fn_head, src, a, decls)
    if wat_std_path_ok(v, fn_head, src, a, decls) and sfp.n != 0 {
      sbn := base_type_name(src, sfp.s, sfp.n)
      if struct_decl_of(decls, src, sbn.s, sbn.n) >= 0 { return WSpan(s = sbn.s, n = sbn.n) }
    }
  }
  vn := expr_var_name(v)
  if vn.n != 0 { return base_struct_type(params_head, fn_head, src, vn.s, vn.n, a, decls) }
  return WSpan(s = 0, n = 0)
}

## The STRUCT span an aggregate-valued RHS delivers: a place (above), a struct LITERAL, or a
## struct-returning CALL. Every one of those evaluates to a linear-memory BASE ADDRESS, so a
## whole-element store can copy `struct_words` words from it. {0,0} = not an aggregate RHS → fail-loud.
wat_rhs_agg_span := fn(v : ptr(Expr), params_head : ptr(mut Param), fn_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  sn := expr_struct_name(v)
  if sn.n != 0 { return sn }
  cn := expr_call_name(v)
  if cn.n != 0 {
    cr := callee_ret_struct(decls, src, cn.s, cn.n, ex_call_argh(v), a)
    if cr.n != 0 { return cr }
  }
  return wat_place_agg_span(v, params_head, fn_head, src, a, decls)
}

## The declared ENUM-type name of the PARAM `[ns, ns+nl)` (its `: T` annotation, only if `T` names an
## enum decl), else {0,0}. An enum param is passed as its i64 base address (like a struct).
param_enum_type := fn(params_head : ptr(mut Param), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  mut p := params_head
  mut rs := 0
  mut rn := 0
  while p != 0 {
    pm := deref(param_p(p))
    if streq(src, pm.ns, pm.nl, ns, nl) and enum_decl_of(decls, src, pm.ts, pm.tl) >= 0 { rs = pm.ts ; rn = pm.tl }
    p = pm.next
  }
  WSpan(s = rs, n = rn)
}

## The enum-type name of a scrutinee place `[ns, ns+nl)` — an enum PARAM (by annotation) or an enum
## LOCAL (by its EnumLit init), else {0,0}.
base_enum_type := fn(params_head : ptr(mut Param), fn_head : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, a : rt::Arena, decls : ptr(rt::Vec)) -> WSpan {
  pe := param_enum_type(params_head, src, ns, nl, a, decls)
  if pe.n != 0 { return pe }
  return local_enum_type(fn_head, src, ns, nl, a, decls)
}

## Are ALL fields of struct `[s, s+n)` single-word scalars? Only scalar-field structs are laid out in
## WASM linear memory for now — a multi-word field (str/nested aggregate) makes the struct unsupported.
struct_all_scalar := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize, a : rt::Arena) -> bool {
  di := struct_decl_of(decls, src, s, n)
  if di < 0 { return false }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut ok := true
  while f != 0 {
    fd := deref(fld_p(f))
    if field_words(decls, src, fd.ts, fd.tl, fd.wsize, a) != 1 { ok = false }
    f = fd.next
  }
  ok
}

## Emit the linear-memory address operand (an i32) for a base + `byte_off`. `base_idx >= 0` is a WASM
## LOCAL holding the base address (`local.get`); `base_idx < 0` encodes a COMPILE-TIME-CONSTANT base
## `(0 - base_idx - 1)` (an aggregate GLOBAL's fixed offset) → a plain `i32.const`. The negative
## encoding lets const bases flow through the same match/field/bind machinery as local bases.
emit_wat_addr := fn(in out sb : rt::StrBuf, base_idx : i64, byte_off : i64) {
  if base_idx < 0 {
    push_str(sb, "(i32.const ")
    push_int(sb, (0 - base_idx - 1) + byte_off)
    push_str(sb, ")")
  } else {
    push_str(sb, "(i32.wrap_i64 (i64.add (local.get ")
    push_int(sb, base_idx)
    push_str(sb, ") (i64.const ")
    push_int(sb, byte_off)
    push_str(sb, ")))")
  }
}

## STANDARD BYTE-LAYOUT scalar loads/stores and recursive literal writer. `bidx` is the WASM local
## holding the aggregate base address; unlike the native backends there is no inline frame offset to
## add. A direct byte array uses load8/store8, while nested word-granular aggregates recurse at the
## containing field's byte offset.
## The WIDTH-based core of the standard-byte scalar load. CLAYOUT S3(c) needs it: the shared copy
## plan (`layout_copy_step`) carries a width + signedness, not a type span, because the plan is computed
## once in `lower_layout` for all four backends.
wat_std_load_width := fn(bidx : i64, off : i64, width : usize, signed : bool, in out sb : rt::StrBuf) {
  if width == 1 and signed { push_str(sb, "(i64.load8_s ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, ")") }
  if width == 1 and (not signed) { push_str(sb, "(i64.load8_u ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, ")") }
  if width == 2 and signed { push_str(sb, "(i64.load16_s ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, ")") }
  if width == 2 and (not signed) { push_str(sb, "(i64.load16_u ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, ")") }
  if width == 4 and signed { push_str(sb, "(i64.load32_s ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, ")") }
  if width == 4 and (not signed) { push_str(sb, "(i64.load32_u ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, ")") }
  if width == 8 { push_str(sb, "(i64.load ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, ")") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "(unreachable) (; unsupported standard scalar width ;)") }
}

wat_std_load_scalar := fn(bidx : i64, off : i64, ts : usize, tl : usize, in out sb : rt::StrBuf, src : ptr(u8)) {
  width := scalar_byte_size(src, ts, tl)
  signed := tl != 0 and str_at((src + ts), 1) == "i"
  wat_std_load_width(bidx, off, width, signed, sb)
}

## CLAYOUT S3(c) — THE ONE BYTE-PRECISE WHOLE-VALUE COPIER, WASM's spelling. There is no inline
## frame here: `sidx` is the local holding the SOURCE root's base address and `sbo` the child's
## accumulated §6.1 byte offset from it, while `didx` holds the destination block's base address (its
## word `w` at byte `w*8`, its byte `k` at byte `k`). WHICH of the two the destination is read at is
## decided by `std_copy_kind` in `lower_layout`, shared with the other three backends. A word-granular
## child never reaches here — for it the existing word copy IS the byte copy.
wat_std_copy := fn(ts : usize, tl : usize, sidx : i64, sbo : i64, didx : i64, in out sb : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) {
  ck := std_copy_kind(decls, src, ts, tl, a)
  if ck == 0 { push_str(sb, "    (unreachable) (; whole-value copy outside the byte-precise copier's domain ;)\n") }
  if ck == 1 {
    nb := i64(std_copy_image_bytes(decls, src, ts, tl, a))
    mut k := i64(0)
    while k < nb {
      push_str(sb, "    (i64.store8 ") ; emit_wat_addr(sb, didx, k) ; push_str(sb, " ")
      push_str(sb, "(i64.load8_u ") ; emit_wat_addr(sb, sidx, sbo + k) ; push_str(sb, "))\n")
      k = k + 1
    }
  }
  if ck == 2 {
    ns := i64(layout_copy_nsteps(decls, src, ts, tl, a))
    mut i := i64(0)
    while i < ns {
      st := layout_copy_step(decls, src, ts, tl, i, a)
      if st.found { push_str(sb, "    (i64.store ") ; emit_wat_addr(sb, didx, st.dwo * 8) ; push_str(sb, " ") }
      if st.found { wat_std_load_width(sidx, sbo + st.sbo, st.sz, st.signed, sb) }
      if st.found { push_str(sb, ")\n") }
      if not st.found { push_str(sb, "    (unreachable) (; byte-precise copy plan shorter than its own step count ;)\n") }
      i = i + 1
    }
  }
}

wat_std_store_expr := fn(pe : ptr(Expr), bidx : i64, off : i64, ts : usize, tl : usize, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  width := scalar_byte_size(src, ts, tl)
  if width == 1 { push_str(sb, "    (i64.store8 ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, " ") ; emit_wat_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) ; push_str(sb, ")\n") }
  if width == 2 { push_str(sb, "    (i64.store16 ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, " ") ; emit_wat_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) ; push_str(sb, ")\n") }
  if width == 4 { push_str(sb, "    (i64.store32 ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, " ") ; emit_wat_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) ; push_str(sb, ")\n") }
  if width == 8 { push_str(sb, "    (i64.store ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, " ") ; emit_wat_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) ; push_str(sb, ")\n") }
  if width != 1 and width != 2 and width != 4 and width != 8 { push_str(sb, "    (unreachable) (; unsupported standard scalar width ;)\n") }
}

wat_std_store_value := fn(pe : ptr(Expr), bidx : i64, off : i64, ts : usize, tl : usize, wsize : usize, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  es := wat_arrty_elem(src, ts, tl)
  if es.n != 0 {
    mut bytearr := false
    if scalar_byte_size(src, es.s, es.n) == 1 { bytearr = true }
    if bytearr and ex_is_array_lit(pe) {
      mut g := ex_array_lit_ehead(pe)
      mut k := i64(0)
      while g != 0 {
        ga := deref(arg_p(g))
        push_str(sb, "    (i64.store8 ") ; emit_wat_addr(sb, bidx, off + k) ; push_str(sb, " ")
        emit_wat_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, ")\n")
        k = k + 1
        g = ga.next
      }
      return k
    }
    push_str(sb, "    (unreachable) (; unsupported standard array field construction ;)\n")
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
    wsgn := expr_struct_name(pe)
    if wsgn.n != 0 and std_struct_is_byte_writable(decls, src, ts, tl, a) { return wat_std_store_struct(pe, bidx, off, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    push_str(sb, "    (unreachable) (; unsupported standard aggregate field construction ;)\n")
    return i64(struct_words(decls, src, ts, tl, a))
  }
  wat_std_store_expr(pe, bidx, off, ts, tl, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  i64(standard_type_byte_size(decls, src, ts, tl, wsize, a))
}

wat_std_store_struct := fn(pe : ptr(Expr), bidx : i64, off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  sn := expr_struct_name(pe)
  di := struct_decl_of(decls, src, sn.s, sn.n)
  if di < 0 { push_str(sb, "    (unreachable) (; unknown standard struct literal ;)\n") ; return 0 }
  d := deref(decl_at(Decl, rt::vec_get(deref(decls), usize(di))))
  mut f := d.fields_head
  mut g := ex_struct_lit_args(pe)
  while f != 0 and g != 0 {
    fd := deref(fld_p(f))
    ga := deref(arg_p(g))
    bo := standard_field_byte_offset(decls, src, sn.s, sn.n, fd.ns, fd.nl, a)
    ft := field_type_span(decls, src, sn.s, sn.n, fd.ns, fd.nl, a)
    if bo >= 0 and ft.n != 0 { _sw := wat_std_store_value(ga.e, bidx, off + bo, ft.s, ft.n, fd.wsize, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
    if bo < 0 or ft.n == 0 { push_str(sb, "    (unreachable) (; unresolved standard struct field ;)\n") }
    f = fd.next
    g = ga.next
  }
  i64(standard_type_byte_size(decls, src, sn.s, sn.n, 1, a))
}

## Address operand for `$__tmp + byte_off` — the base of an aggregate under construction in
## EXPRESSION position (see the StructLit/EnumLit expr arms).
emit_wat_tmp_addr := fn(in out sb : rt::StrBuf, byte_off : i64) {
  push_str(sb, "(i32.wrap_i64 (i64.add (global.get $__tmp) (i64.const ")
  push_int(sb, byte_off)
  push_str(sb, ")))")
}

## Emit a value-position match's arms as a nested-if chain on the scrutinee's discriminant (word 0 of
## its linear-memory image at local `sidx`). A wildcard arm `_` emits its body unconditionally; a
## variant arm `E.V => body` tests `disc == variant_index(V)`. NO payload binding yet — an arm body
## that references a payload var resolves to `(unreachable)` (fail-loud), never a wrong value. An
## exhausted chain (no arm matched) traps.
emit_wat_match_arms := fn(arm : usize, es : usize, en : usize, sidx : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec)) {
  if arm == 0 {
    push_str(sb, "(unreachable) (; no matching arm ;)\n")
  } else {
    am := deref(arm_p(arm))
    if am.wild == 5 or am.wild == 6 {
      ## RANGE pattern arm (Control Flow §5.4) — x86_64-only in v1. Fail LOUD (`(unreachable)`),
      ## never a silent miscompile: the wasm sweep requires a trap or reject, not a wrong value.
      push_str(sb, "(unreachable) (; range-pattern match arm not supported on wasm (x86_64 only) ;)")
    } else if am.wild == 1 {
      emit_wat_expr(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, sidx)
    } else {
      vidx := variant_index(decls, src, es, en, am.vs, am.vl, a)
      if vidx < 0 {
        ## FAIL-LOUD: an unresolved variant (a comptime-variant TEMPLATE arm whose placeholder name
        ## didn't resolve, or an enum-span mismatch) — emit `(unreachable)`, NEVER a `-1` comparison
        ## arm that can never match and lets control fall through to a wrong value (silent miscompile).
        push_str(sb, "(unreachable)")
      } else {
        push_str(sb, "(if (result i64) (i64.eq (i64.load ")
        emit_wat_addr(sb, sidx, 0)
        push_str(sb, ") (i64.const ")
        push_int(sb, vidx)
        push_str(sb, ")) (then ")
        emit_wat_expr(am.body, sb, a, src, params_head, pcount, body_head, decls, am.binds_head, sidx)
        push_str(sb, ") (else ")
        emit_wat_match_arms(am.next, es, en, sidx, sb, a, src, params_head, pcount, body_head, decls)
        push_str(sb, "))")
      }
    }
  }
}

## A print-call detection result: the string-literal argument's inner span + label, and whether the
## callee was `println` (append a newline). `ok` false = not a `print(<literal>)`/`println(<literal>)`.
PInfo := struct { ok : bool, ss : usize, sl : usize, lbl : usize, nl : bool, ah : ptr(mut Arg) }

## Recognize `print("…")` / `println("…")` — a Call whose callee names print/println and whose FIRST
## argument is a string LITERAL. (Templates / value args are a follow-up; a print with a non-literal
## arg falls through to the generic call path, which traps as an undefined callee.)
print_call_info := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena) -> PInfo {
  mut r := PInfo(ok = false, ss = 0, sl = 0, lbl = 0, nl = false, ah = 0)
  match deref(e) {
    Expr::Call(cs, cl, nn, ah) => {
      nm := str_at((src + cs), cl)
      isp := nm == "print"
      ispl := nm == "println"
      if (isp or ispl) and ah != 0 {
        ga := deref(arg_p(ah))
        sinfo := str_lit_span(ga.e)
        if sinfo.ok { r = PInfo(ok = true, ss = sinfo.ss, sl = sinfo.sl, lbl = sinfo.lbl, nl = ispl, ah = ah) }
      }
    }
    _ => {}
  }
  r
}

## The inner span + label of a StrLit expression (else ok=false). Single-level match in its own fn
## (a nested match inside another arm mis-lowers under the seed).
SLSpan := struct { ok : bool, ss : usize, sl : usize, lbl : usize }
str_lit_span := fn(e : ptr(Expr)) -> SLSpan {
  mut r := SLSpan(ok = false, ss = 0, sl = 0, lbl = 0)
  match deref(e) {
    Expr::StrLit(ss, sl, lbl) => { r = SLSpan(ok = true, ss = ss, sl = sl, lbl = lbl) }
    _ => {}
  }
  r
}

## The linear-memory offset where string label `lbl`'s bytes live (a fixed per-label slab high in the
## page, clear of the `$__sp` scratch). Slab = 256 bytes; strings longer overflow into the next (a
## tracer limit — test strings are short).
str_data_off := fn(lbl : usize) -> i64 { 32768 + i64(lbl) * 256 }

## Emit one byte as a WAT data-string escape `\HH` (two lowercase hex digits).
emit_byte_esc := fn(in out sb : rt::StrBuf, b : u8) {
  hexd := "0123456789abcdef"
  push_str(sb, "\\")
  push_str(sb, str_at(unchecked bitcast(usize, hexd.ptr) + usize(b) / 16, 1))
  push_str(sb, str_at(unchecked bitcast(usize, hexd.ptr) + usize(b) % 16, 1))
}

wat_hex_digit := fn(c : u8) -> u8 {
  if c >= 48 and c <= 57 { return c - 48 }
  if c >= 65 and c <= 70 { return c - 65 + 10 }
  if c >= 97 and c <= 102 { return c - 97 + 10 }
  0
}
wat_hex_byte := fn(hi : u8, lo : u8) -> u8 { wat_hex_digit(hi) * 16 + wat_hex_digit(lo) }

## Emit a WASM `(data …)` segment for a print string at `str_data_off(lbl)` (+ trailing newline when
## `nl`). `sl` is the DECODED length, while `ss` points at the RAW inner bytes — so decode the raw
## span, emitting exactly `sl` bytes (mirrors how the x86_64 path lets GAS `.ascii` decode). An
## x-escape is four raw bytes, so the over-view is sized for the maximum raw span.
emit_str_data_seg := fn(in out sb : rt::StrBuf, src : ptr(u8), ss : usize, sl : usize, lbl : usize, nl : bool, a : rt::Arena) {
  push_str(sb, "  (data (i32.const ")
  push_int(sb, str_data_off(lbl))
  push_str(sb, ") \"")
  raw := str_at((src + ss), sl * 4 + 16)
  mut k := 0
  mut emitted := 0
  while emitted < sl {
    if bytes(raw)[k] == 92 {
      if bytes(raw)[k + 1] == 120 {
        emit_byte_esc(sb, wat_hex_byte(bytes(raw)[k + 2], bytes(raw)[k + 3]))
        k += 4
      } else {
        nb := str_esc_byte(bytes(raw)[k + 1])
        emit_byte_esc(sb, nb)
        k += 2
      }
    } else {
      emit_byte_esc(sb, bytes(raw)[k])
      k += 1
    }
    emitted += 1
  }
  if nl { emit_byte_esc(sb, 10) }
  push_str(sb, "\")\n")
}

## Emit the WASI `fd_write(1, iov, 1, nwritten)` call for a print string: an iovec {ptr,len} at
## scratch offset 0, result dropped. len includes the println newline.
emit_print := fn(in out sb : rt::StrBuf, pi : PInfo) {
  mut len := i64(pi.sl)
  if pi.nl { len = len + 1 }
  push_str(sb, "    (i32.store (i32.const 0) (i32.const ")
  push_int(sb, str_data_off(pi.lbl))
  push_str(sb, "))\n")
  push_str(sb, "    (i32.store (i32.const 4) (i32.const ")
  push_int(sb, len)
  push_str(sb, "))\n")
  push_str(sb, "    (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8)))\n")
}

## Does the string `[ss, ss+sl)` contain a `{}` format hole?
has_hole := fn(src : ptr(u8), ss : usize, sl : usize, a : rt::Arena) -> bool {
  s := str_at((src + ss), sl)
  mut i := 0
  mut r := false
  while i + 1 < sl {
    if bytes(s)[i] == 123 and bytes(s)[i + 1] == 125 { r = true }
    i += 1
  }
  r
}

## fd_write a fixed linear-memory range `[off, off+len)` to stdout (iovec at scratch offset 0).
emit_print_run := fn(in out sb : rt::StrBuf, off : i64, len : i64) {
  push_str(sb, "    (i32.store (i32.const 0) (i32.const ")
  push_int(sb, off)
  push_str(sb, "))\n    (i32.store (i32.const 4) (i32.const ")
  push_int(sb, len)
  push_str(sb, "))\n    (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8)))\n")
}

## Print a single newline (the byte at fixed offset 12, initialized by a data segment).
emit_print_nl := fn(in out sb : rt::StrBuf) {
  push_str(sb, "    (i32.store (i32.const 0) (i32.const 12))\n    (i32.store (i32.const 4) (i32.const 1))\n    (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8)))\n")
}

## Print an i64 value as decimal via the $__itoa runtime helper (writes digits at [$__istart, 40),
## returns the length) then fd_write that range.
emit_print_int := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  push_str(sb, "    (i32.store (i32.const 4) (call $__itoa ")
  emit_wat_expr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, "))\n    (i32.store (i32.const 0) (global.get $__istart))\n    (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8)))\n")
}

## Emit a `{}`-template print: walk the format string, fd_write each literal RUN (a sub-range of the
## whole string's data segment — the `{}` bytes are skipped) and itoa+print each hole's argument (the
## args after the format string). println appends a newline. Escapes are decoded into the data segment,
## and the raw scanner advances four bytes for `\xHH`.
emit_print_template := fn(pi : PInfo, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ## scan the RAW format bytes but track the DECODED offset (dpos) into the data segment — an escape
  ## is 2 raw bytes → 1 decoded byte (or 4 for `\xHH`), so run offsets (which index the decoded data
  ## segment) advance by decoded count. A `{}` hole occupies 2 decoded bytes (both braces are literal decoded chars) that
  ## the runs skip.
  raw := str_at((src + pi.ss), pi.sl * 4 + 16)
  firstarg := deref(arg_p(pi.ah))
  mut argp := firstarg.next
  mut k := 0
  mut dpos := 0
  mut runstart := 0
  while dpos < pi.sl {
    if bytes(raw)[k] == 123 and bytes(raw)[k + 1] == 125 {
      if dpos > runstart { emit_print_run(sb, str_data_off(pi.lbl) + i64(runstart), i64(dpos - runstart)) }
      if argp != 0 {
        ga := deref(arg_p(argp))
        emit_print_int(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
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
  if pi.sl > runstart { emit_print_run(sb, str_data_off(pi.lbl) + i64(runstart), i64(pi.sl - runstart)) }
  if pi.nl { emit_print_nl(sb) }
}

## Emit one expression in WAT folded (S-expression) form — always leaving a single i64 on the stack.
## Emit the linear-memory BASE ADDRESS (an i64 value) of `arr[i]` where `arr` is an AGGREGATE-element
## array/slice — the by-reference value of a multi-word element. `ibase`/`iidx` are the indexed place's
## base and index (an `Expr::Index`'s two halves — passed apart so `Stmt::IndexAssign`, which never
## builds an Index node, can reuse it). Address = element-region base + i*stride*8, where the region
## base is the local's pointer (array LOCAL), word0 of the view block (range-slice VIEW / `Slice(S)`
## PARAM), or the fixed `.data` offset (array GLOBAL). Under `verify.checked` the index is stashed in the
## scratch local and range-tested first — against the static element count (array local/global) or the
## runtime len in word1 (slice); `i64.ge_u` so a negative index traps too.
emit_wat_agg_elem_addr := fn(ibase : ptr(Expr), iidx : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  bn := expr_var_name(ibase)
  stride := wat_arr_elem_stride(body_head, src, bn.s, bn.n, a, decls)
  mut strideb := stride * 8
  esp := wat_arr_elem_struct(body_head, src, bn.s, bn.n, a, decls)
  if esp.n != 0 and std_array_elem_byte_tier(decls, src, esp.s, esp.n, a) { strideb = i64(layout_elem_stride_bytes(decls, src, esp.s, esp.n, a)) }
  isarr := is_array_local(body_head, src, bn.s, bn.n, a)
  isslc := (not isarr) and is_slice_local(body_head, src, bn.s, bn.n, a)
  isglb := (not isarr) and (not isslc) and wat_is_array_global(decls, src, bn.s, bn.n, a)
  ## the base LOCAL: a body array/slice local resolves by slot, everything else is a param local.
  mut bidx := param_find(params_head, src, bn.s, bn.n, a)
  if isarr or isslc { bidx = name_local_index(body_head, src, bn.s, bn.n, pcount, a, decls) }
  ## static element count (array local / global); 0 = unknown → no static guard (a slice checks word1).
  mut nel := 0
  if isarr { nel = i64(array_local_nel(body_head, src, bn.s, bn.n, a)) }
  if isglb { nel = wat_array_global_nel(decls, src, bn.s, bn.n, a) }
  mut docheck := WAT_CHK
  if (isarr or isglb) and nel <= 0 { docheck = false }
  sc := pcount + count_locals(body_head, src, a, decls)
  push_str(sb, "(i64.add ")
  if isarr {
    push_str(sb, "(local.get ") ; push_int(sb, bidx) ; push_str(sb, ")")
  } else if isglb {
    push_str(sb, "(i64.const ") ; push_int(sb, agg_global_base(decls, src, bn.s, bn.n, a)) ; push_str(sb, ")")
  } else {
    push_str(sb, "(i64.load ") ; emit_wat_addr(sb, bidx, 0) ; push_str(sb, ")")
  }
  push_str(sb, " (i64.mul ")
  if docheck {
    push_str(sb, "(block (result i64) (local.set ") ; push_int(sb, sc) ; push_str(sb, " ")
    emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, ") (if (i64.ge_u (local.get ") ; push_int(sb, sc) ; push_str(sb, ") ")
    if isarr or isglb {
      push_str(sb, "(i64.const ") ; push_int(sb, nel) ; push_str(sb, ")")
    } else {
      push_str(sb, "(i64.load ") ; emit_wat_addr(sb, bidx, 8) ; push_str(sb, ")")
    }
    push_str(sb, ") (then (unreachable))) (local.get ") ; push_int(sb, sc) ; push_str(sb, "))")
  } else {
    emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  }
  push_str(sb, " (i64.const ") ; push_int(sb, strideb) ; push_str(sb, ")))")
}

## Emit the linear-memory ADDRESS (an i64 VALUE) of `base[idx]` for a DEEP place (assumes
## wat_place_idx_ok). Address = <address of base> + index * element-words * 8. Bounds vs the array
## type's STATIC element count via the reusable scratch local (`i64.ge_u`, so a negative i64 index traps
## as a huge unsigned), dropped under `unchecked` (CG-7). NESTING IS SAFE: WASM evaluates operands
## left-to-right, so an outer hop's guarded index is already consumed onto the operand stack before an
## inner hop's guard overwrites the shared scratch local.
emit_wat_place_idx_addr := fn(base : ptr(Expr), idx : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  bt := wat_place_ty(base, body_head, src, a, decls)
  et := wat_arrty_elem(src, bt.s, bt.n)
  mut estride := wat_arr_elem_stride_bytes(src, et.s, et.n, a, decls)
  ## An inline scalar array field inside a byte-tier element is packed by the scalar's byte width,
  ## not by the ordinary one-word scalar stride.
  if wat_std_idx_path_ok(base, body_head, src, a, decls) {
    sw := scalar_byte_size(src, et.s, et.n)
    if sw == 1 or sw == 2 or sw == 4 or sw == 8 { estride = i64(sw) }
  }
  nel := wat_arrty_nel(src, bt.s, bt.n)
  sc := pcount + count_locals(body_head, src, a, decls)
  push_str(sb, "(i64.add ")
  emit_wat_place_addr(base, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, " (i64.mul ")
  if WAT_CHK and nel > 0 {
    push_str(sb, "(block (result i64) (local.set ") ; push_int(sb, sc) ; push_str(sb, " ")
    emit_wat_expr(idx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, ") (if (i64.ge_u (local.get ") ; push_int(sb, sc) ; push_str(sb, ") (i64.const ") ; push_int(sb, nel)
    push_str(sb, ")) (then (unreachable))) (local.get ") ; push_int(sb, sc) ; push_str(sb, "))")
  } else {
    emit_wat_expr(idx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  }
  push_str(sb, " (i64.const ") ; push_int(sb, estride) ; push_str(sb, ")))")
}

## Emit the linear-memory ADDRESS (an i64 VALUE) of the DEEP place `e` (assumes wat_place_ok). Flat
## standalone ifs — an if/else-if chain as a fn body reads as a tail value-if under the lean lower.
## The ROOT is a frame local whose WASM local already HOLDS the block's base address.
emit_wat_place_addr := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  isf := ex_is_field(e)
  isi := ex_is_index(e)
  if isf {
    fbase := expr_field_base(e)
    fsp := expr_field_span(e)
    bt := wat_place_ty(fbase, body_head, src, a, decls)
    mut boff := i64(field_word_offset(decls, src, bt.s, bt.n, fsp.s, fsp.n, a)) * 8
    if wat_std_idx_path_ok(e, body_head, src, a, decls) { boff = layout_field_offset_bytes(decls, src, bt.s, bt.n, fsp.s, fsp.n, a) }
    push_str(sb, "(i64.add ")
    emit_wat_place_addr(fbase, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
    push_str(sb, " (i64.const ") ; push_int(sb, boff) ; push_str(sb, "))")
  }
  if isi {
    emit_wat_place_idx_addr(ex_index_base(e), ex_index_idx(e), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  }
  if (not isf) and (not isi) {
    vidx := name_local_index(body_head, src, ex_var_ns(e), ex_var_nl(e), pcount, a, decls)
    push_str(sb, "(local.get ") ; push_int(sb, vidx) ; push_str(sb, ")")
  }
}

## Store the (possibly NESTED) aggregate value `pe` at `[<base held in WASM local `bidx`> + off]`,
## returning the WORDS written. This is the FLATTENED writer: a nested struct / `[T; N]` field is laid
## out INLINE at its cumulative word offset, exactly the layout `struct_words` / `field_word_offset`
## describe — which is what the deep-place composition walks. The pre-existing positional writer (one
## word per constructor argument) stores a one-word nested struct BY REFERENCE and drops every word of a
## wider one, so this replaces it ONLY where the aggregate has a multi-word field (an all-scalar
## aggregate keeps the byte-identical positional emit). `bidx` may be the negative CONSTANT-base
## encoding `emit_wat_addr` understands.
emit_wat_store_payload_at := fn(pe : ptr(Expr), bidx : i64, off : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) -> i64 {
  sn := expr_struct_name(pe)
  if sn.n != 0 {
    mut g := ex_struct_lit_args(pe)
    mut o2 := off
    while g != 0 {
      ga := deref(arg_p(g))
      w := emit_wat_store_payload_at(ga.e, bidx, o2, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      o2 = o2 + w * 8
      g = ga.next
    }
    return i64(struct_words(decls, src, sn.s, sn.n, a))
  }
  en := expr_enum_name(pe)
  if en.n != 0 {
    ev := expr_enum_variant(pe)
    vidx := variant_index(decls, src, en.s, en.n, ev.s, ev.n, a)
    push_str(sb, "    (i64.store ") ; emit_wat_addr(sb, bidx, off)
    push_str(sb, " (i64.const ") ; push_int(sb, vidx) ; push_str(sb, "))\n")
    mut g := ex_enum_lit_args(pe)
    mut wo := 1
    while g != 0 {
      ga := deref(arg_p(g))
      cw := emit_wat_store_payload_at(ga.e, bidx, off + wo * 8, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      wo = wo + cw
      g = ga.next
    }
    return 1 + i64(enum_max_arity(decls, src, en.s, en.n, a))
  }
  if ex_is_array_lit(pe) {
    mut ag := ex_array_lit_ehead(pe)
    mut ao := off
    mut atot := 0
    while ag != 0 {
      aga := deref(arg_p(ag))
      aw := emit_wat_store_payload_at(aga.e, bidx, ao, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      ao = ao + aw * 8
      atot = atot + aw
      ag = aga.next
    }
    return atot
  }
  push_str(sb, "    (i64.store ") ; emit_wat_addr(sb, bidx, off) ; push_str(sb, " ")
  emit_wat_expr(pe, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
  push_str(sb, ")\n")
  return 1
}

## Emit a WORD-WISE aggregate COPY of `nw` words from the address in local `srcidx` to the address in
## local `dstidx` (both hold i64 base addresses). Ascending, word k at +k*8 — the layout every aggregate
## place uses, so it is safe for disjoint blocks (the only kind these callers produce: a fresh `$__sp`
## block, or an array element vs. an independently-built RHS).
emit_wat_word_copy := fn(in out sb : rt::StrBuf, dstidx : i64, srcidx : i64, nw : i64) {
  mut k := 0
  while k < nw {
    push_str(sb, "    (i64.store ")
    emit_wat_addr(sb, dstidx, k * 8)
    push_str(sb, " (i64.load ")
    emit_wat_addr(sb, srcidx, k * 8)
    push_str(sb, "))\n")
    k += 1
  }
}

wat_emit_lambda_label := fn(in out sb : rt::StrBuf, src : ptr(u8), ms : usize, ml : usize, fnpos : usize) {
  if not lower::is_root_mod(ms, ml) {
    if ml == 0 { push_str(sb, "main") } else { push_str(sb, str_at((src + ms), ml)) }
    push_str(sb, "__")
  }
  push_str(sb, "lam")
  push_int(sb, i64(fnpos))
}

wat_bound_lambda := fn(body : ptr(mut Stmt), src : ptr(u8), ns : usize, nl : usize, decls : ptr(rt::Vec)) -> i64 {
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

emit_wat_expr := fn(e : ptr(Expr), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, body_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  match deref(e) {
    Expr::FnRef(fnpos, fms, fml) => {
      push_str(sb, "(unreachable) (; FnRef value unsupported on WAT ;)")
    }
    Expr::Num(v, s, n) => { push_str(sb, "(i64.const "); push_int(sb, i64(v)); push_str(sb, ")") }
    ## FLOAT literal: its IEEE bits as an i64 (WASM `f64.const` folded, then reinterpreted) — the bits
    ## ride the i64 value path; only arith/conversion reinterpret back to `f64`.
    Expr::FloatLit(fs, fl) => {
      push_str(sb, "(i64.reinterpret_f64 (f64.const ")
      push_str(sb, str_at((src + fs), fl))
      push_str(sb, "))")
    }
    Expr::BoolLit(v) => { push_str(sb, "(i64.const "); push_int(sb, i64(v)); push_str(sb, ")") }
    Expr::Var(ns, nl) => {
      bidx := bind_list_index(bind_head, src, ns, nl, a)
      pidx := param_find(params_head, src, ns, nl, a)
      if wat_bound_lambda(body_head, src, ns, nl, decls) >= 0 {
        push_str(sb, "(unreachable) (; bare local lambda value unsupported on WAT ;)")
      } else if bidx >= 0 {
        ## an active match-arm payload binding: load the scrutinee's payload word (bidx+1)
        push_str(sb, "(i64.load ")
        emit_wat_addr(sb, bind_base, (bidx + 1) * 8)
        push_str(sb, ")")
      } else if pidx >= 0 {
        push_str(sb, "(local.get ")
        push_int(sb, pidx)
        push_str(sb, ")")
      } else if is_global(decls, src, ns, nl, a) {
        gname := str_at((src + ns), nl)
        push_str(sb, "(global.get $")
        push_str(sb, gname)
        push_str(sb, ")")
      } else if wat_is_float_global(decls, src, ns, nl) {
        ## a float module global: its `(mut f64)` cell reinterpreted to the i64 bits the value model
        ## carries. When the init text is not recoverable the cell was never emitted → TRAP instead.
        if wat_float_global_init_ok(decls, src, ns, nl) {
          push_str(sb, "(i64.reinterpret_f64 (global.get $")
          push_str(sb, str_at((src + ns), nl))
          push_str(sb, "))")
        } else {
          push_str(sb, "(unreachable) (; float module global (wasm: no init) ;)\n")
        }
      } else if is_toplevel_local(body_head, ns, nl, src, a) {
        push_str(sb, "(local.get ")
        push_int(sb, name_local_index(body_head, src, ns, nl, pcount, a, decls))
        push_str(sb, ")")
      } else {
        push_str(sb, "(unreachable) (; unresolved var ;)\n")
      }
    }
    Expr::Bin(op, l, r) => {
      ## bind the mnemonic to a local FIRST — an inline str-returning call as a str argument scrambles
      ## its {ptr,len}. Uniform i64: cmp extends i32→i64, `not` (Bin 42, both slots) is `x == 0`.
      mut wisflt := false
      if wat_is_float_expr(e, body_head, src, a, params_head, decls, 0) { wisflt = true }
      ## FLOAT comparison (`a < b` over float operands) is NOT modelled on wasm (fcmp / NaN ordering) —
      ## it TRAPS rather than comparing the raw IEEE bits as integers (a silent miscompile: wrong ordering
      ## + NaN semantics). Detected on the operands (the cmp Bin itself is not float-typed).
      mut wfcmp := false
      if ex_is_cmp_op(op) {
        if wat_is_float_expr(l, body_head, src, a, params_head, decls, 0) { wfcmp = true }
        if wat_is_float_expr(r, body_head, src, a, params_head, decls, 0) { wfcmp = true }
      }
      if op == 42 {
        push_str(sb, "(i64.extend_i32_u (i64.eqz ")
        emit_wat_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "))")
      } else if wisflt and is_arith_op(op) {
        ## FLOAT arithmetic: reinterpret both operands' bits to f64, run the FP op, reinterpret back to
        ## i64 bits. Detect on the whole Bin `e` (destructured operands mis-lower through the detector).
        ## Bind the mnemonic to a local FIRST — an inline str-returning call as a push_str arg scrambles
        ## its {ptr,len} under the seed (the documented wat-emit scar).
        fopn := wat_fbinop(op)
        push_str(sb, "(i64.reinterpret_f64 (")
        push_str(sb, fopn)
        push_str(sb, " (f64.reinterpret_i64 ")
        emit_wat_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, ") (f64.reinterpret_i64 ")
        emit_wat_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, ")))")
      } else if wfcmp {
        ## FLOAT comparison: reinterpret both operands' bits to f64, apply the ordered f64 compare
        ## (i32 result → extend to i64). Bind the mnemonic to a local first (the wat push_str-arg scar).
        fcop := wat_fcmpop(op)
        push_str(sb, "(i64.extend_i32_u (")
        push_str(sb, fcop)
        push_str(sb, " (f64.reinterpret_i64 ")
        emit_wat_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, ") (f64.reinterpret_i64 ")
        emit_wat_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, ")))")
      } else if ex_is_cmp_op(op) and (wat_is_agg_place(l, params_head, body_head, src, a, decls) or wat_is_agg_place(r, params_head, body_head, src, a, decls) or wat_is_agg_index(l, body_head, src, a, decls) or wat_is_agg_index(r, body_head, src, a, decls)) {
        ## AGGREGATE comparison (`p == q`, `p < q` over MULTI-WORD by-value structs, Stdlib §2.6): the
        ## operand locals hold linear-memory BASE ADDRESSES, so an `i64.eq`/`i64.lt_u` on them compares
        ## POINTERS, not contents — a SILENT MISCOMPILE (`p == q` on two equal-valued distinct blocks is
        ## false; `p < q` reports allocation order). x86_64 routes these to the structural
        ## `base::derive::eq`/`lt`. wat has no structural derive, but it DOES already emit a user
        ## OPERATOR OVERLOAD (`@inline < := fn(a : Ver, b : Ver)`) as an ordinary `$<` function — so route
        ## to it when one is declared for this operand type, and fail LOUD otherwise. Mirrors the guard the
        ## arith branch below already carries. Previously unreachable only because a nested-aggregate local
        ## stopped the emit one statement earlier, which is why the address compare went unnoticed.
        ## The operand test is `wat_is_agg_place`, NOT `expr_is_struct_var`: a TUPLE local (an `ArrayLit`,
        ## so no struct decl), a fixed ARRAY local, a SLICE view and an ENUM local/param carry a base
        ## address too and used to fall through to the scalar `i64.eq` below — `(5,7) == (5,9)` and
        ## `E.A(5) == E.A(5)` (params) both answered on ADDRESSES, a silent miscompile.
        ## Bind the glyph to a local FIRST — an inline str-returning call as a push_str arg scrambles its
        ## {ptr,len} under the seed (the documented wat-emit scar).
        gly := wat_cmp_glyph(op)
        lsty := expr_struct_type_of(l, params_head, body_head, src, a, decls)
        mut opok := false
        if gly != "" {
          if wat_op_fn_match(decls, src, gly, lsty.s, lsty.n) { opok = true }
        }
        if opok {
          push_str(sb, "(call $")
          push_str(sb, gly)
          push_str(sb, " ")
          emit_wat_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, " ")
          emit_wat_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ")")
        } else {
          push_str(sb, "(unreachable) (; aggregate comparison needs structural eq/lt ;)\n")
        }
      } else if ex_is_cmp_op(op) {
        ## SIGNED mnemonic (`wat_cmpop`) is the DEFAULT — kept for every signed/unknown operand. When
        ## BOTH operands are PROVABLY unsigned, switch to the UNSIGNED mnemonic (`wat_ucmpop`) so a
        ## `u64`/`usize` comparison across 2^63 is correct (mirrors the x86_64 `is_unsigned_cmp` gate).
        ## Bind the mnemonic to a local FIRST (an inline str-returning call as a push_str arg scrambles
        ## its {ptr,len} under the seed — the documented wat-emit scar).
        mut cop := wat_cmpop(op)
        if wat_cmp_unsigned(l, r, params_head, body_head, src, a) { cop = wat_ucmpop(op) }
        push_str(sb, "(i64.extend_i32_u (")
        push_str(sb, cop)
        push_str(sb, " ")
        emit_wat_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, " ")
        emit_wat_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "))")
      } else if is_arith_op(op) and (not expr_is_struct_var(l, params_head, body_head, src, a, decls)) and (not expr_is_struct_var(r, params_head, body_head, src, a, decls)) {
        dl := wat_operand_signed(l, params_head, body_head, src, a)
        dr := wat_operand_signed(r, params_head, body_head, src, a)
        opname := wat_binop(op, dl or dr)
        ## NARROW-WIDTH WRAP (§4 value model): a +/-/* over a narrow-typed (uN/iN, N<64) operand truncates
        ## its result — the wat dual is an `(i64.and … mask)` / `(i64.extendN_s …)` WRAPPING the binop.
        mut nw := ""
        ## op 36 (`^`, incl. the narrow `~` = `x^(-1)` desugar) also masks to the operand width — its
        ## mask rides the plain fallback pre/post path below, NOT the checked-overflow blocks (a bit op
        ## never overflows), so the two checked blocks are gated to arith 16/17/18 only.
        if op == 16 or op == 17 or op == 18 or op == 36 {
          nw = wat_operand_narrow(l, params_head, body_head, src, a)
          if nw == "" { nw = wat_operand_narrow(r, params_head, body_head, src, a) }
        }
        ## CHECKED overflow on `+` (I11 / CG-8): WASM has no flags, so mirror num.al's comparison. Both
        ## operands are evaluated onto the VALUE STACK first, THEN captured straight-line into the scratch
        ## globals ($__ova/$__ovb/$__ovo) — nesting-safe (a nested checked add inside `l`/`r` overwrites
        ## the globals during its own evaluation, but the outer captures fresh from the stack afterward,
        ## exactly like the register backends' a0/a1). UNSIGNED overflow iff out <u a; SIGNED iff
        ## (a^out)&(b^out) < 0. `unreachable` traps. Dropped under `unchecked` (WAT_CHK false) and skipped
        ## for a narrow width. POINTER offsetting routes through `rt::addr` (unchecked), never reaching here.
        if (op == 16 or op == 17 or op == 18) and WAT_CHK and nw == "" and (not ex_is_zero_lit(l)) {
          push_str(sb, "(block (result i64) ")
          emit_wat_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, " ")
          emit_wat_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, " global.set $__ovb global.set $__ova")
          ## result into $__ovo via the op's WASM stack instruction (add/sub/mul)
          if op == 16 { push_str(sb, " (global.set $__ovo (i64.add (global.get $__ova) (global.get $__ovb)))") }
          if op == 17 { push_str(sb, " (global.set $__ovo (i64.sub (global.get $__ova) (global.get $__ovb)))") }
          if op == 18 { push_str(sb, " (global.set $__ovo (i64.mul (global.get $__ova) (global.get $__ovb)))") }
          ## overflow condition — mirrors num.al (WASM lacks flags AND a widening mul):
          ##   +  unsigned: out <u a   ; signed: (a^out)&(b^out) < 0
          ##   -  unsigned: out >u a   ; signed: (a^b)&(a^out) < 0
          ##   *  a != 0 and out/a != b  (div_u unsigned / div_s signed; div_s MIN/-1 self-traps = overflow)
          if op == 16 {
            if dl or dr { push_str(sb, " (if (i64.lt_s (i64.and (i64.xor (global.get $__ova) (global.get $__ovo)) (i64.xor (global.get $__ovb) (global.get $__ovo))) (i64.const 0)) (then (unreachable)))") }
            else { push_str(sb, " (if (i64.lt_u (global.get $__ovo) (global.get $__ova)) (then (unreachable)))") }
          }
          if op == 17 {
            if dl or dr { push_str(sb, " (if (i64.lt_s (i64.and (i64.xor (global.get $__ova) (global.get $__ovb)) (i64.xor (global.get $__ova) (global.get $__ovo))) (i64.const 0)) (then (unreachable)))") }
            else { push_str(sb, " (if (i64.gt_u (global.get $__ovo) (global.get $__ova)) (then (unreachable)))") }
          }
          ## NB: `i64.ne` yields an i32 boolean, so the two comparisons combine with `i32.and` (not
          ## `i64.and`) and the `if` takes the i32 result. (The signed +/- checks above `i64.and` two
          ## i64 xor-values → i64, correct there.)
          ## `i32.and` is a plain operator, NOT short-circuiting: BOTH operands are evaluated, so the
          ## `a != 0` test does NOT protect the division — `0 * b` (a very ordinary multiply, e.g. an
          ## accumulator starting at 0) reached `div (0 / 0)` and took WASM's "integer divide by zero"
          ## trap: a valid program trapping, the fail-loud design's opposite failure. The DIVISOR is
          ## therefore forced non-zero (`select a, 1` on `a != 0`); when a == 0 the quotient is a
          ## harmless 0 and the `a != 0` conjunct already makes the guard false.
          if op == 18 {
            if dl or dr { push_str(sb, " (if (i32.and (i64.ne (global.get $__ova) (i64.const 0)) (i64.ne (i64.div_s (global.get $__ovo) (select (global.get $__ova) (i64.const 1) (i64.ne (global.get $__ova) (i64.const 0)))) (global.get $__ovb))) (then (unreachable)))") }
            else { push_str(sb, " (if (i32.and (i64.ne (global.get $__ova) (i64.const 0)) (i64.ne (i64.div_u (global.get $__ovo) (select (global.get $__ova) (i64.const 1) (i64.ne (global.get $__ova) (i64.const 0)))) (global.get $__ovb))) (then (unreachable)))") }
          }
          push_str(sb, " (global.get $__ovo))")
          return
        }
        ## CHECKED narrow-width path: compute the binop into $__ovo, TRAP if it doesn't fit the width,
        ## then apply the value-model wrap. Mirrors the native block above (globals are nesting-safe).
        if nw != "" and (op == 16 or op == 17 or op == 18) and WAT_CHK and (not ex_is_zero_lit(l)) {
          push_str(sb, "(block (result i64) ")
          emit_wat_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, " ")
          emit_wat_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, " global.set $__ovb global.set $__ova")
          if op == 16 { push_str(sb, " (global.set $__ovo (i64.add (global.get $__ova) (global.get $__ovb)))") }
          if op == 17 { push_str(sb, " (global.set $__ovo (i64.sub (global.get $__ova) (global.get $__ovb)))") }
          if op == 18 { push_str(sb, " (global.set $__ovo (i64.mul (global.get $__ova) (global.get $__ovb)))") }
          ntchk := wat_narrow_trap_check(nw)
          push_str(sb, ntchk)
          ntpre := wat_narrow_pre(nw)
          ntpost := wat_narrow_post(nw)
          push_str(sb, " ")
          push_str(sb, ntpre)
          push_str(sb, "(global.get $__ovo)")
          push_str(sb, ntpost)
          push_str(sb, ")")
          return
        }
        ## bind pre/post to locals FIRST — an inline str-returning call as a push_str arg scrambles it.
        pre := wat_narrow_pre(nw)
        post := wat_narrow_post(nw)
        push_str(sb, pre)
        push_str(sb, "(")
        push_str(sb, opname)
        push_str(sb, " ")
        emit_wat_expr(l, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, " ")
        emit_wat_expr(r, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, ")")
        push_str(sb, post)
      } else {
        ## an unhandled op byte (no WASM stack-op) or a struct operand (user operator-overload) —
        ## trap rather than silently defaulting to i64.add / adding addresses.
        push_str(sb, "(unreachable) (; unsupported binary op or struct operand ;)\n")
      }
    }
    Expr::If(c, t, el) => {
      push_str(sb, "(if (result i64) (i32.wrap_i64 ")
      emit_wat_expr(c, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, ") (then ")
      emit_wat_expr(t, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, ") (else ")
      emit_wat_expr(el, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      push_str(sb, "))")
    }
    Expr::Call(cs, cl, nargs, args_head) => {
      if is_cast_callee(src, cs, cl) {
        cvn := str_at((src + cs), cl)
        isicv := scalar_name_is_int_conv(cvn)
        mut isfcv := false
        if cvn == "f64" { isfcv = true }
        if cvn == "f32" { isfcv = true }
        if args_head != 0 {
          gcv := deref(arg_p(args_head))
          argisf := wat_is_float_expr(gcv.e, body_head, src, a, params_head, decls, 0)
          if isfcv {
            ## int → float: `f64.convert_i64_s` then reinterpret to i64 bits; float → float is identity.
            if argisf { emit_wat_expr(gcv.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
            else {
              push_str(sb, "(i64.reinterpret_f64 (f64.convert_i64_s ")
              emit_wat_expr(gcv.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
              push_str(sb, "))")
            }
          } else if argisf {
            ## float → int: reinterpret the bits to f64, TRUNCATE toward zero (u → `trunc_f64_u`, i →
            ## `trunc_f64_s`), then apply the width narrow (native widths pass through).
            pre := wat_narrow_pre(cvn)
            post := wat_narrow_post(cvn)
            push_str(sb, pre)
            if str_at((src + cs), 1) == "u" { push_str(sb, "(i64.trunc_f64_u (f64.reinterpret_i64 ") } else { push_str(sb, "(i64.trunc_f64_s (f64.reinterpret_i64 ") }
            emit_wat_expr(gcv.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, "))")
            push_str(sb, post)
          } else {
            ## integer CONVERSION `uN(x)`/`iN(x)` (§8): mask (uN) / sign-extend (iN); native = passthrough.
            pre := wat_narrow_pre(cvn)
            post := wat_narrow_post(cvn)
            push_str(sb, pre)
            emit_wat_expr(gcv.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, post)
          }
        } else {
          push_str(sb, "(unreachable) (; empty conversion ;)\n")
        }
      } else if str_at((src + cs), cl) == "shl" or str_at((src + cs), cl) == "shr" or str_at((src + cs), cl) == "rotl" or str_at((src + cs), cl) == "rotr" {
        ## bit shift/rotate ops (OP-6): WASM's native `i64.shl`/`shr_u`/`shr_s`/`rotl`/`rotr`, each popping
        ## v then n. `shr` picks `_s`/`_u` by the value's signedness (wat_operand_signed), like `/`. WASM
        ## masks the count mod 64; rotation is total, but in checked mode a shift traps before native masking
        ## when `n >= 64` (I11 / Concurrency §6), using the fn's reusable scratch local.
        wscn := str_at((src + cs), cl)
        wsv := arg_expr_at(args_head, 0, a)
        wsn := arg_expr_at(args_head, 1, a)
        if wscn == "shl" { push_str(sb, "(i64.shl ") }
        else if wscn == "shr" { if wat_operand_signed(wsv, params_head, body_head, src, a) { push_str(sb, "(i64.shr_s ") } else { push_str(sb, "(i64.shr_u ") } }
        else if wscn == "rotl" { push_str(sb, "(i64.rotl ") }
        else { push_str(sb, "(i64.rotr ") }
        emit_wat_expr(wsv, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, " ")
        if WAT_CHK and (wscn == "shl" or wscn == "shr") {
          sc := pcount + count_locals(body_head, src, a, decls)
          push_str(sb, "(block (result i64) (local.set ")
          push_int(sb, sc)
          push_str(sb, " ")
          emit_wat_expr(wsn, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") (if (i64.ge_u (local.get ")
          push_int(sb, sc)
          push_str(sb, ") (i64.const 64)) (then (unreachable))) (local.get ")
          push_int(sb, sc)
          push_str(sb, "))")
        } else {
          emit_wat_expr(wsn, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        }
        push_str(sb, ")")
      } else if str_at((src + cs), cl) == "len" and args_head != 0 and wat_len_recv_slice(arg_expr_at(args_head, 0, a), params_head, src, body_head, decls, a) {
        ## `s.len()` (UFCS-desugared to `Call("len", [s])`) on a slice receiver — the runtime length = word1
        ## of the `{ptr,len}` block. A slice PARAM (a WASM local holding the block base) and a local slice
        ## VIEW share the same shape; the base local index comes from `param_find` (param) or
        ## `name_local_index` (local). `i64.load` at base + 8.
        rcv := arg_expr_at(args_head, 0, a)
        rn := expr_var_name(rcv)
        pidxL := param_find(params_head, src, rn.s, rn.n, a)
        mut isparam := false
        if pidxL >= 0 { if wat_slice_param_scalar(params_head, src, rn.s, rn.n, a, decls) { isparam = true } }
        mut lbidx := pidxL
        if not isparam { lbidx = name_local_index(body_head, src, rn.s, rn.n, pcount, a, decls) }
        push_str(sb, "(i64.load ")
        emit_wat_addr(sb, lbidx, 8)
        push_str(sb, ")")
      } else if gen_call_ok(decls, src, cs, cl) {
        ## GENERICS (§8 mono): route a generic call to its monomorphized instance `$<fn>__<tag>`. Resolve
        ## the type-arg (explicit `f(u64,…)` / implicit `id(k)`), RECORD the instance (dedup) so the mono
        ## pass emits `$<fn>__<tag>`, ERASE an explicit type-arg from the runtime args, and pass the kept
        ## VALUE args positionally on the stack. An unresolved type-arg falls to a fail-loud `(unreachable)`.
        gi := generic_gi(decls, src, cs, cl)
        wat_resolve_typearg(decls, src, gi, args_head, params_head, a)
        tas := WAT_TA_S
        tan := WAT_TA_N
        if tan == 0 {
          push_str(sb, "(unreachable) (; generic call: unresolved type-arg ;)\n")
        } else {
          wat_inst_add(src, usize(gi), tas, tan)
          gd := deref(decl_get(decls, usize(gi)))
          argc := arg_list_count(args_head, a)
          ## ERASE the comptime type-arg(s) when passed explicitly (argc == arity): a leading run erases
          ## indices [0, lead); a single non-leading type-param erases its one position. Implicit calls
          ## carry none. FLAT ifs.
          mut erase_lead := 0
          mut erase_one := usize(argc) + 1
          if argc == i64(gd.arity) {
            cntc := decl_tparam_count(gd, src)
            leadc := decl_leading_tparam_run(gd, src)
            if cntc == leadc { erase_lead = usize(leadc) }
            if cntc == 1 and leadc == 0 { erase_one = usize(decl_tparam_pos(gd, src)) }
          }
          push_str(sb, "(call $")
          push_str(sb, str_at((src + gd.name_start), gd.name_len))
          push_str(sb, "__")
          ## type TAG — INLINE (see the def-label site; a StrBuf helper segfaults under the seed). MUST
          ## match the def label exactly: bare / `Tuple_…` / `Array_<elem>_<N>`.
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
          ## MULTI type-param: append `__<2nd>` / `__<3rd>` (bare scalar names) — matches the def-side tag.
          ## Read before the arg loop below (a nested generic-call arg would clobber WAT_TA_*2/*3).
          if WAT_TA_N2 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + WAT_TA_S2), WAT_TA_N2)) }
          if WAT_TA_N3 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + WAT_TA_S3), WAT_TA_N3)) }
          mut g := args_head
          mut gidx := 0
          while g != 0 {
            ga := deref(arg_p(g))
            keeparg := usize(gidx) >= erase_lead and usize(gidx) != erase_one
            if keeparg {
              push_str(sb, " ")
              emit_wat_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            }
            gidx = gidx + 1
            g = ga.next
          }
          push_str(sb, ")")
        }
      } else if wat_bound_lambda(body_head, src, cs, cl, decls) >= 0 {
        td := deref(decl_get(decls, usize(wat_bound_lambda(body_head, src, cs, cl, decls))))
        push_str(sb, "(call $") ; wat_emit_lambda_label(sb, src, td.mod_start, td.mod_len, td.name_start)
        mut g := args_head
        while g != 0 { ga := deref(arg_p(g)) ; push_str(sb, " ") ; emit_wat_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) ; g = ga.next }
        push_str(sb, ")")
      } else if not callee_defined(decls, src, cs, cl, a) {
        push_str(sb, "(unreachable) (; call to undefined/builtin fn ")
        push_str(sb, str_at((src + cs), cl))
        push_str(sb, " ;)\n")
      } else {
        push_str(sb, "(call $")
        cname := str_at((src + cs), cl)
        push_str(sb, cname)
        mut g := args_head
        while g != 0 {
          ga := deref(arg_p(g))
          push_str(sb, " ")
          emit_wat_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          g = ga.next
        }
        push_str(sb, ")")
      }
    }
    ## `v.(f)` (Expr::CompField) — a member access named by the comptime field-unroll loop var `f`. When
    ## `f` is the active loop var (WAT_CF_VAR set), reduce to a scalar field READ of `v` at the CURRENT
    ## field (WAT_CF_FLD): the local/param holds `v`'s base address in linear memory → i64.load at
    ## (base + field word offset). A struct PARAM typed `T` resolves via the substituting struct-span
    ## helper. A non-scalar field / non-struct base is DEFERRED (fail-loud, never silent). Mirrors a64.
    Expr::CompField(cfbase0, cfidx0) => {
      ## SCALAR var accessors on the match bindings — a WSpan (2-word) accessor whose arg is the 2nd
      ## match-bound child (cfidx0) mis-lowers to 0 under the frozen seed; SCALAR returns do not. Mirrors a64.
      cvns := ex_var_ns(cfidx0)
      cvnl := ex_var_nl(cfidx0)
      cbns := ex_var_ns(cfbase0)
      cbnl := ex_var_nl(cfbase0)
      cfactive := WAT_CF_VAR_L != 0 and cvnl != 0 and streq(src, cvns, cvnl, WAT_CF_VAR_S, WAT_CF_VAR_L)
      cpidx := param_find(params_head, src, cbns, cbnl, a)
      mut cstys := 0
      mut cstyn := 0
      if cpidx >= 0 {
        psp := wat_param_struct_span(params_head, src, cbns, cbnl, a, decls)
        cstys = psp.s ; cstyn = psp.n
      } else {
        lsp := local_struct_type(body_head, src, cbns, cbnl, a, decls)
        cstys = lsp.s ; cstyn = lsp.n
      }
      cok := cfactive and cbnl != 0 and cstyn != 0 and struct_all_scalar(decls, src, cstys, cstyn, a)
      if cok {
        cwoff := field_word_offset(decls, src, cstys, cstyn, WAT_CF_FLD_S, WAT_CF_FLD_L, a)
        mut cbidx := cpidx
        if cpidx < 0 { cbidx = name_local_index(body_head, src, cbns, cbnl, pcount, a, decls) }
        push_str(sb, "(i64.load ")
        emit_wat_addr(sb, cbidx, cwoff * 8)
        push_str(sb, ")")
      } else {
        push_str(sb, "(unreachable) (; unsupported comptime-field access ;)\n")
      }
    }
    Expr::Field(base, fs, fl) => {
      ## `f.offset` — a comptime FIELD descriptor read. Fold it before ordinary field lowering sees
      ## the erased loop variable as a runtime name; unresolved forms keep the existing trap path.
      cfo := wat_cf_offset_value(e, src, decls, a)
      if cfo >= 0 {
        push_str(sb, "(i64.const ") ; push_int(sb, cfo) ; push_str(sb, ")")
        return
      }
      ## `f.mutable` — a comptime FIELD descriptor read. It has no runtime storage; emit the source-level
      ## mutability bit as an immediate before ordinary field machinery sees `f` as a runtime variable.
      cfm := wat_cf_mutable_value(e, src)
      if cfm >= 0 {
        push_str(sb, "(i64.const ") ; push_int(sb, cfm) ; push_str(sb, ")")
        return
      }
      ## `p.field` for a struct PARAM or LOCAL `p` in linear memory: i64.load at (p's base + offset).
      bn := expr_var_name(base)
      gagg := agg_global_base(decls, src, bn.s, bn.n, a)
      gstyp := global_struct_type(decls, src, bn.s, bn.n, a)
      styp0 := base_struct_type(params_head, body_head, src, bn.s, bn.n, a, decls)
      bpidx := param_find(params_head, src, bn.s, bn.n, a)
      isloc := is_toplevel_local(body_head, bn.s, bn.n, src, a)
      ## GENERICS (§8): for a struct PARAM typed `T`, resolve the instance struct type (T → the concrete
      ## struct) via the substituting helper so `w.v` reads the right layout inside a mono instance
      ## (`g(T, w : T)` at `T = W`). Byte-identical for a non-generic param (same struct span) / a local.
      mut styp := styp0
      if bpidx >= 0 { psp0 := wat_param_struct_span(params_head, src, bn.s, bn.n, a, decls) ; if psp0.n != 0 { styp = psp0 } }
      ## `s.len` on a range-slice local — the runtime length is word1 (i64.load at s-base + 8).
      mut isslicelen := false
      if bn.n != 0 { if is_slice_local(body_head, src, bn.s, bn.n, a) { if str_at((src + fs), fl) == "len" { isslicelen = true } } }
      mut stdty := wat_std_path_ty(e, body_head, src, a, decls)
      mut stdpath := wat_std_path_ok(e, body_head, src, a, decls) and stdty.n != 0
      mut stdparampath := false
      if not stdpath {
        if wat_std_param_path_ok(e, params_head, src, a, decls) {
          stdty = wat_std_param_path_ty(e, params_head, src, a, decls)
          stdpath = true
          stdparampath = true
        }
      }
      if stdpath {
        mut sidx := i64(0)
        if stdparampath { sidx = wat_std_param_path_idx(e, params_head, src, a, decls) }
        if not stdparampath { sidx = wat_std_path_root_idx(e, body_head, src, pcount, a, decls) }
        mut sbo := i64(0)
        if stdparampath { sbo = wat_std_param_path_bo(e, params_head, src, a, decls) }
        if not stdparampath { sbo = wat_std_path_bo(e, body_head, src, a, decls) }
        if std_ty_aggregate(stdty.s, stdty.n, decls, src) {
          push_str(sb, "(i64.add (local.get ") ; push_int(sb, sidx) ; push_str(sb, ") (i64.const ") ; push_int(sb, sbo) ; push_str(sb, "))")
        }
        if not std_ty_aggregate(stdty.s, stdty.n, decls, src) { wat_std_load_scalar(sidx, sbo, stdty.s, stdty.n, sb, src) }
      } else if isslicelen {
        bidx := name_local_index(body_head, src, bn.s, bn.n, pcount, a, decls)
        push_str(sb, "(i64.load ")
        emit_wat_addr(sb, bidx, 8)
        push_str(sb, ")")
      } else if gagg >= 0 and gstyp.n != 0 and struct_all_scalar(decls, src, gstyp.s, gstyp.n, a) {
        woff := field_word_offset(decls, src, gstyp.s, gstyp.n, fs, fl, a)
        push_str(sb, "(i64.load ")
        emit_wat_addr(sb, 0 - (gagg + 1), woff * 8)
        push_str(sb, ")")
      } else if bn.n != 0 and styp.n != 0 and struct_all_scalar(decls, src, styp.s, styp.n, a) and (bpidx >= 0 or isloc) {
        woff := field_word_offset(decls, src, styp.s, styp.n, fs, fl, a)
        mut bidx := bpidx
        if bpidx < 0 { bidx = name_local_index(body_head, src, bn.s, bn.n, pcount, a, decls) }
        push_str(sb, "(i64.load ")
        emit_wat_addr(sb, bidx, woff * 8)
        push_str(sb, ")")
      } else if ex_is_index(base) and wat_slice_param_struct_span(params_head, src, expr_var_name(ex_index_base(base)).s, expr_var_name(ex_index_base(base)).n, decls).n != 0 {
        ## `s[i].field`: FIELD over an INDEX into a struct-element `Slice(P)` PARAM. The param local holds the
        ## `{ptr,len}` block base; element i is by-reference at word0 (data ptr) + i*stride*8; the field is at
        ## (element base + woff*8). Bounds vs word1 (count) via the reusable scratch local `sc` (checked mode).
        ibn := expr_var_name(ex_index_base(base))
        psp := wat_slice_param_struct_span(params_head, src, ibn.s, ibn.n, decls)
        ipidx := param_find(params_head, src, ibn.s, ibn.n, a)
        stride := wat_slice_param_agg_stride(params_head, src, ibn.s, ibn.n, a, decls)
        woff := field_word_offset(decls, src, psp.s, psp.n, fs, fl, a)
        sc := pcount + count_locals(body_head, src, a, decls)
        push_str(sb, "(i64.load (i32.wrap_i64 (i64.add (i64.add (i64.load ")
        emit_wat_addr(sb, ipidx, 0)
        push_str(sb, ") (i64.mul ")
        if WAT_CHK {
          push_str(sb, "(block (result i64) (local.set ") ; push_int(sb, sc) ; push_str(sb, " ")
          emit_wat_expr(ex_index_idx(base), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") (if (i64.ge_u (local.get ") ; push_int(sb, sc) ; push_str(sb, ") (i64.load ")
          emit_wat_addr(sb, ipidx, 8)
          push_str(sb, ")) (then (unreachable))) (local.get ") ; push_int(sb, sc) ; push_str(sb, "))")
        } else {
          emit_wat_expr(ex_index_idx(base), sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        }
        push_str(sb, " (i64.const ") ; push_int(sb, stride * 8) ; push_str(sb, "))) (i64.const ") ; push_int(sb, woff * 8) ; push_str(sb, "))))")
      } else {
        ## First try a NESTED struct-GLOBAL chain (`STATE.a.b.c`): the root global sits at a fixed
        ## linear-memory base, so a scalar leaf loads at (base + cumulative-word-offset*8) — a const
        ## address, nested structs FLATTENED (unlike a local, where a nested struct is by-reference).
        groot := wat_gchain_root(e)
        gbase := agg_global_base(decls, src, groot.s, groot.n, a)
        gtype := wat_gchain_type(e, decls, src, a)
        gwoff := wat_gchain_woff(e, decls, src, a)
        gchainok := gbase >= 0 and gwoff >= 0 and gtype.n != 0 and ty_is_scalar(gtype.s, gtype.n, decls, src)
        if gchainok {
          push_str(sb, "(i64.load ")
          emit_wat_addr(sb, 0 - (gbase + 1), gwoff * 8)
          push_str(sb, ")")
        } else if wat_deep_scalar_ok(e, body_head, src, params_head, pcount, a, decls) {
          ## DEEP place read — `xs[i].inner.x` / `xs[i].b.c.cx` (a field chain off an array ELEMENT) and
          ## `b.cells[i].m` (through an inline `[Struct; N]` FIELD). None has a closed frame-offset formula
          ## (the element base is a RUNTIME address), so the address is COMPOSED hop by hop and the scalar
          ## leaf loaded from it. Tried BEFORE the by-reference nested-field path below, but gated on
          ## wat_place_ok's FLATTENED-STORAGE guard, so every shape that path already emits keeps it.
          dty := wat_place_ty(e, body_head, src, a, decls)
          dw := scalar_byte_size(src, dty.s, dty.n)
          dsigned := dty.n != 0 and str_at((src + dty.s), 1) == "i"
          if wat_std_idx_path_ok(e, body_head, src, a, decls) {
            if dw == 1 and dsigned { push_str(sb, "(i64.load8_s (i32.wrap_i64 ") }
            if dw == 1 and (not dsigned) { push_str(sb, "(i64.load8_u (i32.wrap_i64 ") }
            if dw == 2 and dsigned { push_str(sb, "(i64.load16_s (i32.wrap_i64 ") }
            if dw == 2 and (not dsigned) { push_str(sb, "(i64.load16_u (i32.wrap_i64 ") }
            if dw == 4 and dsigned { push_str(sb, "(i64.load32_s (i32.wrap_i64 ") }
            if dw == 4 and (not dsigned) { push_str(sb, "(i64.load32_u (i32.wrap_i64 ") }
            if dw == 8 { push_str(sb, "(i64.load (i32.wrap_i64 ") }
          }
          if not wat_std_idx_path_ok(e, body_head, src, a, decls) { push_str(sb, "(i64.load (i32.wrap_i64 ") }
          emit_wat_place_addr(e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, "))")
        } else {
          ## NESTED field access `o.i.v` on a LOCAL: the base is itself a struct-yielding place. A nested
          ## struct field is stored by-reference (the word holds the inner base address), so emitting the
          ## base as a VALUE already yields the inner struct's base — load the sub-field from base + offset.
          btype := expr_struct_type_of(base, params_head, body_head, src, a, decls)
          if btype.n != 0 and struct_all_scalar(decls, src, btype.s, btype.n, a) {
            woff := field_word_offset(decls, src, btype.s, btype.n, fs, fl, a)
            push_str(sb, "(i64.load (i32.wrap_i64 (i64.add ")
            emit_wat_expr(base, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
            push_str(sb, " (i64.const ")
            push_int(sb, woff * 8)
            push_str(sb, "))))")
          } else {
            push_str(sb, "(unreachable) (; unsupported field access ;)\n")
          }
        }
      }
    }
    Expr::Match(scrut, arms_head) => {
      ## `match e { … }` in value position: dispatch on e's discriminant. e must be a top-level enum
      ## LOCAL (its type recovered from its EnumLit init); payload binds are not modelled (arms that
      ## use them trap in the Var arm).
      sn := expr_var_name(scrut)
      agg := agg_global_base(decls, src, sn.s, sn.n, a)
      etype := base_enum_type(params_head, body_head, src, sn.s, sn.n, a, decls)
      spidx := param_find(params_head, src, sn.s, sn.n, a)
      isloc := is_toplevel_local(body_head, sn.s, sn.n, src, a)
      if agg >= 0 {
        ## enum GLOBAL scrutinee: its value lives at the fixed offset `agg` — a const base (negative
        ## sidx encoding). Payload binds load from the same const base.
        gtype := global_enum_type(decls, src, sn.s, sn.n, a)
        if gtype.n != 0 { emit_wat_match_arms(arms_head, gtype.s, gtype.n, 0 - (agg + 1), sb, a, src, params_head, pcount, body_head, decls) }
        else { push_str(sb, "(unreachable) (; non-enum agg global match ;)\n") }
      } else if sn.n != 0 and etype.n != 0 and (spidx >= 0 or isloc) {
        mut sidx := spidx
        if spidx < 0 { sidx = name_local_index(body_head, src, sn.s, sn.n, pcount, a, decls) }
        emit_wat_match_arms(arms_head, etype.s, etype.n, sidx, sb, a, src, params_head, pcount, body_head, decls)
      } else {
        push_str(sb, "(unreachable) (; unsupported match ;)\n")
      }
    }
    Expr::StructLit(ss, sn, nf, ah) => {
      ## a struct literal in expression position (e.g. passed directly as a fn arg): construct in
      ## linear memory via $__tmp and YIELD its base address (a block-with-result).
      if struct_all_scalar(decls, src, ss, sn, a) {
        sz := struct_words(decls, src, ss, sn, a)
        push_str(sb, "(block (result i64) (global.set $__tmp (global.get $__sp)) (global.set $__sp (i64.add (global.get $__sp) (i64.const ")
        push_int(sb, i64(sz) * 8)
        push_str(sb, "))) ")
        mut g := ah
        mut k := 0
        while g != 0 {
          ga := deref(arg_p(g))
          push_str(sb, "(i64.store ")
          emit_wat_tmp_addr(sb, i64(k) * 8)
          push_str(sb, " ")
          emit_wat_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") ")
          k += 1
          g = ga.next
        }
        push_str(sb, "(global.get $__tmp))")
      } else {
        push_str(sb, "(unreachable) (; non-scalar struct literal ;)\n")
      }
    }
    Expr::EnumLit(es, en, vs, vn, nf, ah) => {
      ## an enum literal in expression position: construct {disc, payload…} via $__tmp, yield base.
      vidx := variant_index(decls, src, es, en, vs, vn, a)
      if vidx >= 0 {
        sz := 1 + enum_max_arity(decls, src, es, en, a)
        push_str(sb, "(block (result i64) (global.set $__tmp (global.get $__sp)) (global.set $__sp (i64.add (global.get $__sp) (i64.const ")
        push_int(sb, i64(sz) * 8)
        push_str(sb, "))) (i64.store ")
        emit_wat_tmp_addr(sb, 0)
        push_str(sb, " (i64.const ")
        push_int(sb, vidx)
        push_str(sb, ")) ")
        mut g := ah
        mut k := 1
        while g != 0 {
          ga := deref(arg_p(g))
          push_str(sb, "(i64.store ")
          emit_wat_tmp_addr(sb, i64(k) * 8)
          push_str(sb, " ")
          emit_wat_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") ")
          k += 1
          g = ga.next
        }
        push_str(sb, "(global.get $__tmp))")
      } else {
        push_str(sb, "(unreachable) (; unknown enum variant ;)\n")
      }
    }
    Expr::ArrayLit(nel, ah) => {
      ## A tuple value `(e0, …)` is an ArrayLit.  Materialize its scalar components into a fresh
      ## word block and yield the base address; callers bind that address exactly like an array local.
      ## Fixed arrays in expression position remain unsupported unless this scalar tuple path applies.
      if WAT_RET_TUPLE > 0 and nel == usize(WAT_RET_TUPLE) and nel >= 1 and nel <= 7 {
        push_str(sb, "(block (result i64) (global.set $__tmp (global.get $__sp)) (global.set $__sp (i64.add (global.get $__sp) (i64.const ")
        push_int(sb, i64(nel) * 8)
        push_str(sb, "))) ")
        mut g := ah
        mut k := 0
        while g != 0 {
          ga := deref(arg_p(g))
          push_str(sb, "(i64.store ")
          emit_wat_tmp_addr(sb, i64(k) * 8)
          push_str(sb, " ")
          emit_wat_expr(ga.e, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") ")
          k = k + 1
          g = ga.next
        }
        push_str(sb, "(global.get $__tmp))")
      } else { push_str(sb, "(unreachable) (; unsupported expr ;)\n") }
    }
    Expr::Index(ibase, iidx) => {
      ## `a[i]` for an ARRAY local: load word `i` (scalar elements, stride 8) at base + i*8.
      bn := expr_var_name(ibase)
      mut isslice := false
      if bn.n != 0 { if is_slice_local(body_head, src, bn.s, bn.n, a) { isslice = true } }
      ## `s[i]` on a scalar `Slice(E)` PARAM: identical to a VIEW in WASM (the param local holds the block
      ## base; block[0]=ptr, block[1]=len). Take the base local from `param_find` (the param IS a WASM local).
      pidxidx := param_find(params_head, src, bn.s, bn.n, a)
      mut isparamslice := false
      if (not isslice) and pidxidx >= 0 { if wat_slice_param_scalar(params_head, src, bn.s, bn.n, a, decls) { isparamslice = true } }
      tupn := if (not isslice) and (not isparamslice) and pidxidx >= 0 { param_tuple_allscalar_n(params_head, src, bn.s, bn.n, decls, a) } else { 0 }
      ## AGGREGATE element (`[S; N]` / `Slice(S)`, S a struct): the element spans `stride` words, so its
      ## VALUE is its base address — NOT a word load. Must be tested BEFORE every scalar path below,
      ## whose hard-coded stride-8 `i64.load` would otherwise return word 0 of the element (a wrong
      ## scalar). A non-scalar-field element struct is not laid out in linear memory → fail LOUD.
      aggel := wat_arr_elem_struct(body_head, src, bn.s, bn.n, a, decls)
      ## a multi-word element with NO resolvable all-scalar struct (an enum-element array, a nested
      ## aggregate) must trap for the same reason — never fall through to the stride-8 scalar load.
      aggstride := if aggel.n == 0 { wat_arr_elem_stride(body_head, src, bn.s, bn.n, a, decls) } else { 1 }
      mut stdarr := wat_std_path_ty(ibase, body_head, src, a, decls)
      mut stdpathok := wat_std_path_ok(ibase, body_head, src, a, decls)
      mut stdparamidx := false
      if not stdpathok {
        if wat_std_param_path_ok(ibase, params_head, src, a, decls) {
          stdarr = wat_std_param_path_ty(ibase, params_head, src, a, decls)
          stdpathok = true
          stdparamidx = true
        }
      }
      stdel := wat_arrty_elem(src, stdarr.s, stdarr.n)
      mut stdidx := false
      if stdpathok and stdel.n != 0 {
        if scalar_byte_size(src, stdel.s, stdel.n) == 1 { stdidx = true }
      }
      if stdidx {
        ## Byte-array field read (`p.bytes[i]`): standard field offset is a byte offset and the element
        ## stride is one byte, not the legacy word stride used by the branches below.
        mut sidx := i64(0)
        if stdparamidx { sidx = wat_std_param_path_idx(ibase, params_head, src, a, decls) }
        if not stdparamidx { sidx = wat_std_path_root_idx(ibase, body_head, src, pcount, a, decls) }
        mut sbo := i64(0)
        if stdparamidx { sbo = wat_std_param_path_bo(ibase, params_head, src, a, decls) }
        if not stdparamidx { sbo = wat_std_path_bo(ibase, body_head, src, a, decls) }
        sc := pcount + count_locals(body_head, src, a, decls)
        push_str(sb, "(i64.load8_u (i32.wrap_i64 (i64.add (i64.add (local.get ") ; push_int(sb, sidx) ; push_str(sb, ") (i64.const ") ; push_int(sb, sbo) ; push_str(sb, ") ")
        if WAT_CHK {
          snel := wat_arrty_nel(src, stdarr.s, stdarr.n)
          push_str(sb, "(block (result i64) (local.set ") ; push_int(sb, sc) ; push_str(sb, " ")
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          if snel > 0 { push_str(sb, ") (if (i64.ge_u (local.get ") ; push_int(sb, sc) ; push_str(sb, ") (i64.const ") ; push_int(sb, snel) ; push_str(sb, ")) (then (unreachable))) (local.get ") ; push_int(sb, sc) ; push_str(sb, "))") }
          if snel <= 0 { push_str(sb, ") (local.get ") ; push_int(sb, sc) ; push_str(sb, "))") }
        } else { emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base) }
        push_str(sb, "))))")
      } else if aggel.n != 0 {
        ## A NESTED-AGGREGATE element struct is now IN: `a[i]` only needs the element's ADDRESS, and the
        ## stride (`struct_words`) is width-correct for a nested field too. Only a PLAIN (arity-0) decl —
        ## a generic / comptime-value type-fn element would panic in `struct_words`.
        if struct_all_scalar(decls, src, aggel.s, aggel.n, a) or struct_plain(decls, src, aggel.s, aggel.n) {
          emit_wat_agg_elem_addr(ibase, iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        } else {
          push_str(sb, "(unreachable) (; non-scalar-field struct element ;)\n")
        }
      } else if aggstride > 1 {
        push_str(sb, "(unreachable) (; multi-word non-struct array element ;)\n")
      } else if tupn > 0 {
        ## `t.N` (= Index(Var(t), Num(N))) on an ALL-SCALAR tuple PARAM: the param wasm local (`pidxidx`)
        ## holds the caller's tuple base address in linear memory (by-reference). Each component is one word,
        ## so element i is at `base + i*8`: `(i64.load (base + (i * 8)))`. Bounds vs the static component
        ## count via the scratch local (WAT_CHK); `i64.ge_u` so a negative index also traps.
        push_str(sb, "(i64.load (i32.wrap_i64 (i64.add (local.get ")
        push_int(sb, pidxidx)
        push_str(sb, ") (i64.mul ")
        if WAT_CHK {
          sc := pcount + count_locals(body_head, src, a, decls)
          push_str(sb, "(block (result i64) (local.set ")
          push_int(sb, sc)
          push_str(sb, " ")
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") (if (i64.ge_u (local.get ")
          push_int(sb, sc)
          push_str(sb, ") (i64.const ")
          push_int(sb, tupn)
          push_str(sb, ")) (then (unreachable))) (local.get ")
          push_int(sb, sc)
          push_str(sb, "))")
        } else {
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        }
        push_str(sb, " (i64.const 8)))))")
      } else if isslice or isparamslice {
        ## `s[i]` on a range-slice VIEW / PARAM: element addr = ptr (word0, i64.load at s-base+0) + i*8, then
        ## load. Bounds (WAT_CHK): stash i in the scratch local, trap (`unreachable`) if i >= the RUNTIME
        ## len (word1, i64.load at s-base+8); `i64.ge_u` is unsigned so a negative index traps too.
        mut bidx := pidxidx
        if isslice { bidx = name_local_index(body_head, src, bn.s, bn.n, pcount, a, decls) }
        push_str(sb, "(i64.load (i32.wrap_i64 (i64.add (i64.load ")
        emit_wat_addr(sb, bidx, 0)
        push_str(sb, ") (i64.mul ")
        if WAT_CHK {
          sc := pcount + count_locals(body_head, src, a, decls)
          push_str(sb, "(block (result i64) (local.set ")
          push_int(sb, sc)
          push_str(sb, " ")
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") (if (i64.ge_u (local.get ")
          push_int(sb, sc)
          push_str(sb, ") (i64.load ")
          emit_wat_addr(sb, bidx, 8)
          push_str(sb, ")) (then (unreachable))) (local.get ")
          push_int(sb, sc)
          push_str(sb, "))")
        } else {
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        }
        push_str(sb, " (i64.const 8)))))")
      } else if bn.n != 0 and is_array_local(body_head, src, bn.s, bn.n, a) {
        bidx := name_local_index(body_head, src, bn.s, bn.n, pcount, a, decls)
        push_str(sb, "(i64.load (i32.wrap_i64 (i64.add (local.get ")
        push_int(sb, bidx)
        push_str(sb, ") (i64.mul ")
        ## CHECKED BOUNDS (I11 / CG-7): stash the index in the scratch local (`pcount + nloc`), trap
        ## (`unreachable`) if it is `>=` the array's static count, else yield it. `i64.ge_u` is unsigned,
        ## so a negative i64 index (huge unsigned) also traps. Dropped under `unchecked` (WAT_CHK false).
        wnel := array_local_nel(body_head, src, bn.s, bn.n, a)
        if WAT_CHK and wnel > 0 {
          sc := pcount + count_locals(body_head, src, a, decls)
          push_str(sb, "(block (result i64) (local.set ")
          push_int(sb, sc)
          push_str(sb, " ")
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") (if (i64.ge_u (local.get ")
          push_int(sb, sc)
          push_str(sb, ") (i64.const ")
          push_int(sb, i64(wnel))
          push_str(sb, ")) (then (unreachable))) (local.get ")
          push_int(sb, sc)
          push_str(sb, "))")
        } else {
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        }
        push_str(sb, " (i64.const 8)))))")
      } else if bn.n != 0 and wat_is_array_global(decls, src, bn.s, bn.n, a) {
        ## `TABLE[i]` on an ARRAY GLOBAL: element i at the fixed base + i*8 (a const-base add). Bounds vs
        ## the static count via the scratch local (WAT_CHK); i64.ge_u so a negative index also traps.
        gbase := agg_global_base(decls, src, bn.s, bn.n, a)
        push_str(sb, "(i64.load (i32.wrap_i64 (i64.add (i64.const ")
        push_int(sb, gbase)
        push_str(sb, ") (i64.mul ")
        wnelg := wat_array_global_nel(decls, src, bn.s, bn.n, a)
        if WAT_CHK and wnelg > 0 {
          sc := pcount + count_locals(body_head, src, a, decls)
          push_str(sb, "(block (result i64) (local.set ") ; push_int(sb, sc) ; push_str(sb, " ")
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") (if (i64.ge_u (local.get ") ; push_int(sb, sc) ; push_str(sb, ") (i64.const ") ; push_int(sb, wnelg) ; push_str(sb, ")) (then (unreachable))) (local.get ") ; push_int(sb, sc) ; push_str(sb, "))")
        } else {
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        }
        push_str(sb, " (i64.const 8)))))")
      } else if pidxidx >= 0 and wat_param_gen_arr_stride(params_head, src, bn.s, bn.n, a, decls) > 0 {
        ## `a[i]` on a GENERIC array PARAM (`a : T`, T → `[E; N]` scalar element in this instance): the
        ## param wasm local (`pidxidx`) holds the array BASE ADDRESS (passed by-reference by the caller),
        ## so element i (1 word) is at `base + i*8`. Bounds vs the static N (from the instance array type),
        ## dropped under `unchecked`. Mirrors a64_param_gen_arr_stride / a64_sub_arr_len.
        push_str(sb, "(i64.load (i32.wrap_i64 (i64.add (local.get ")
        push_int(sb, pidxidx)
        push_str(sb, ") (i64.mul ")
        wnelp := wat_sub_arr_len(src)
        if WAT_CHK and wnelp > 0 {
          sc := pcount + count_locals(body_head, src, a, decls)
          push_str(sb, "(block (result i64) (local.set ") ; push_int(sb, sc) ; push_str(sb, " ")
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          push_str(sb, ") (if (i64.ge_u (local.get ") ; push_int(sb, sc) ; push_str(sb, ") (i64.const ") ; push_int(sb, wnelp) ; push_str(sb, ")) (then (unreachable))) (local.get ") ; push_int(sb, sc) ; push_str(sb, "))")
        } else {
          emit_wat_expr(iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        }
        push_str(sb, " (i64.const 8)))))")
      } else if wat_deep_idx_scalar_ok(ibase, body_head, src, params_head, pcount, a, decls) {
        ## DEEP index read — `xs[i].arr[j]` (an index into an inline `[T; N]` FIELD of an array element).
        ## The base is NOT a bare Var, so no closed formula exists; compose the address hop by hop. Tried
        ## LAST, so every array/slice/global/param shape above keeps its exact emit.
        dity := wat_place_idx_ty(ibase, body_head, src, a, decls)
        diw := scalar_byte_size(src, dity.s, dity.n)
        disigned := dity.n != 0 and str_at((src + dity.s), 1) == "i"
        if wat_std_idx_path_ok(ibase, body_head, src, a, decls) {
          if diw == 1 and disigned { push_str(sb, "(i64.load8_s (i32.wrap_i64 ") }
          if diw == 1 and (not disigned) { push_str(sb, "(i64.load8_u (i32.wrap_i64 ") }
          if diw == 2 and disigned { push_str(sb, "(i64.load16_s (i32.wrap_i64 ") }
          if diw == 2 and (not disigned) { push_str(sb, "(i64.load16_u (i32.wrap_i64 ") }
          if diw == 4 and disigned { push_str(sb, "(i64.load32_s (i32.wrap_i64 ") }
          if diw == 4 and (not disigned) { push_str(sb, "(i64.load32_u (i32.wrap_i64 ") }
          if diw == 8 { push_str(sb, "(i64.load (i32.wrap_i64 ") }
        }
        if not wat_std_idx_path_ok(ibase, body_head, src, a, decls) { push_str(sb, "(i64.load (i32.wrap_i64 ") }
        emit_wat_place_idx_addr(ibase, iidx, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, "))")
      } else {
        push_str(sb, "(unreachable) (; unsupported index ;)\n")
      }
    }
    ## `inner?` — evaluate a tryable enum into its linear-memory base, then inspect word 0. The
    ## success variant yields payload word 0; any other variant returns the WHOLE enum from the
    ## enclosing function. WAT's `return` is stack-polymorphic, so the failure arm remains a valid
    ## i64 expression while still running all pending defers before it returns.
    Expr::Try(inner) => {
      tsp := wat_try_enum_type(inner, params_head, body_head, src, a, decls)
      if tsp.n == 0 {
        push_str(sb, "(unreachable) (; unsupported try operand ;)\n")
      } else {
        sdisc := wat_try_success_disc(decls, src, tsp.s, tsp.n, a)
        dsc := wat_defer_scratch(pcount, body_head, src, a, decls)
        push_str(sb, "(block (result i64) (local.set ")
        push_int(sb, dsc)
        push_str(sb, " ")
        emit_wat_expr(inner, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, ") (if (result i64) (i64.eq (i64.load (i32.wrap_i64 (local.get ")
        push_int(sb, dsc)
        push_str(sb, "))) (i64.const ")
        push_int(sb, sdisc)
        push_str(sb, ")) (then (i64.load (i32.wrap_i64 (i64.add (local.get ")
        push_int(sb, dsc)
        push_str(sb, ") (i64.const 8))))) (else\n")
        if WAT_DEF_N > 0 {
          sv := WAT_DEF_N
          wat_defer_drain(WAT_DEF_N, 0, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
          WAT_DEF_N = sv
        }
        push_str(sb, "    (return (local.get ")
        push_int(sb, dsc)
        push_str(sb, "))\n    )))")
      }
    }
    Expr::Slice(sbe, slo, shi) => {
      ## a slice VALUE in expression position — an `f(xs[lo..hi])` ARGUMENT (§8 slice-param caller).
      ## Materialize a 2-word `{ptr,len}` block in the `$__sp` bump region via `$__tmp` (word0 = base-array
      ## ptr + lo*8, word1 = hi - lo) and YIELD its base address — the by-reference slice convention: the
      ## callee's `Slice(T)` param local receives this address and reads block[0]=ptr / block[1]=len,
      ## identical to a local slice VIEW. Only a scalar frame-array-LOCAL base; else fail-loud.
      bn := expr_var_name(sbe)
      mut ok := false
      if bn.n != 0 { if is_array_local(body_head, src, bn.s, bn.n, a) { ok = true } }
      if ok {
        abidx := name_local_index(body_head, src, bn.s, bn.n, pcount, a, decls)
        ## element stride of the base array (1 for scalar → lo*8; struct/enum → lo*stride*8).
        estrideS := array_local_stride(body_head, src, bn.s, bn.n, a, decls)
        push_str(sb, "(block (result i64) (global.set $__tmp (global.get $__sp)) (global.set $__sp (i64.add (global.get $__sp) (i64.const 16))) ")
        push_str(sb, "(i64.store ") ; emit_wat_tmp_addr(sb, 0)
        push_str(sb, " (i64.add (local.get ") ; push_int(sb, abidx) ; push_str(sb, ") (i64.mul ")
        emit_wat_expr(slo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, " (i64.const ") ; push_int(sb, estrideS * 8) ; push_str(sb, ")))) ")
        push_str(sb, "(i64.store ") ; emit_wat_tmp_addr(sb, 8)
        push_str(sb, " (i64.sub ")
        emit_wat_expr(shi, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, " ")
        emit_wat_expr(slo, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
        push_str(sb, ")) (global.get $__tmp))")
      }
      if not ok { push_str(sb, "(unreachable) (; unsupported slice value ;)\n") }
    }
    ## Anything else the scalar kernel does not model (Deref/StrLit/…) traps rather than
    ## silently miscomputing. `unreachable` is stack-polymorphic, so it satisfies the expected i64.
    Expr::Unchecked(inner) => {
      ov := WAT_CHK
      WAT_CHK = false
      emit_wat_expr(inner, sb, a, src, params_head, pcount, body_head, decls, bind_head, bind_base)
      WAT_CHK = ov
    }
    _ => { push_str(sb, "(unreachable) (; unsupported expr ;)\n") }
  }
}

## Does an expr-statement produce a value that must be `drop`ped? Everything does EXCEPT a call to a
## void fn (which leaves nothing on the stack).
exprstmt_needs_drop := fn(e : ptr(Expr), src : ptr(u8), decls : ptr(rt::Vec), a : rt::Arena) -> bool {
  mut r := true
  match deref(e) {
    Expr::Call(cs, cl, nargs, args_head) => { if callee_is_void(decls, src, cs, cl, a) { r = false } }
    _ => {}
  }
  r
}

## The next statement handle of an arena-linked Stmt. Defer blocks are physically linked into their
## enclosing list, so the WAT emitter needs the same exhaustive chain walk as the parser and native
## lowerers when it skips a consumed block. Keep this exhaustive: a new Stmt variant must not silently
## truncate the scan at the first statement after it.
wat_stmt_next := fn(h : usize) -> usize {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { nx }
    Stmt::While(c, b, nx) => { nx }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { nx }
    Stmt::Return(rv, nx) => { nx }
    Stmt::If(c, th, el, nx) => { nx }
    Stmt::Match(sc, ah, nx) => { nx }
    Stmt::For(fns, fnl, flo, fhi, fb, nx) => { nx }
    Stmt::DerefAssign(p, v, nx) => { nx }
    Stmt::IndexAssign(b, i, v, nx) => { nx }
    Stmt::Loop(b, nx) => { nx }
    Stmt::Unchecked(b, nx) => { nx }
    Stmt::AllocWith(ae, b, nx) => { nx }
    Stmt::Break(bv, bd, nx) => { nx }
    Stmt::Continue(cd, nx) => { nx }
    Stmt::ExprStmt(e, nx) => { nx }
    Stmt::CompIf(c, th, el, nx) => { nx }
    Stmt::CompFor(vs, vl, iv, b, nx) => { nx }
    Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { nx }
    Stmt::CompMatch(sc, ah, nx) => { nx }
    Stmt::FieldPathAssign(pl, pv, nx) => { nx }
    Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { nx }
  }
}

## The ACTION expression of a `defer` marker statement — the single argument of the synthetic
## `__defer(<expr>)` call the parser desugars `defer <expr>` to — else a NULL pointer (not a defer).
## Returns ptr(Expr) (NOT a new struct — the frozen seed miscompiles a new struct return type).
wat_defer_action := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  match deref(e) {
    Expr::Call(cs, cl, nn, ah) => {
      if str_at((src + cs), cl) == "__defer" and ah != 0 { r = arg_expr_at(ah, 0, a) }
    }
    _ => {}
  }
  r
}

## Is `e` the START of a `defer { … }` BLOCK-action chain? That form desugars to a 3-part chain
## `__deferblk()` → the block's statements (which remain inline in the list) → `__deferblkend()`.
wat_is_defer_blk := fn(e : ptr(Expr), src : ptr(u8)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Call(cs, cl, nn, ah) => {
      nm := str_at((src + cs), cl)
      if nm == "__deferblk" { r = true }
    }
    _ => {}
  }
  r
}

## Is `e` the END marker of a `defer { … }` BLOCK-action chain?
wat_is_defer_blk_end := fn(e : ptr(Expr), src : ptr(u8)) -> bool {
  mut r := false
  match deref(e) {
    Expr::Call(cs, cl, nn, ah) => {
      if str_at((src + cs), cl) == "__deferblkend" { r = true }
    }
    _ => {}
  }
  r
}

## Find the `__deferblkend()` marker belonging to a block head. A missing marker violates the parser's
## pairing invariant; return 0 so the emitter can fail loud rather than register a truncated cleanup.
wat_defer_blk_end := fn(start : usize, src : ptr(u8)) -> usize {
  mut s := start
  mut r := 0
  while s != 0 and r == 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::ExprStmt(e, nx) => {
        if wat_is_defer_blk_end(e, src) { r = s } else { s = wat_stmt_next(s) }
      }
      _ => { s = wat_stmt_next(s) }
    }
  }
  r
}

## Register a defer action on the pending stack. A full stack sets WAT_DEF_OVF — the fn then emits a
## fail-loud `(unreachable)` at its first drain rather than silently losing a cleanup.
wat_defer_push := fn(e : ptr(Expr)) {
  if WAT_DEF_N < 64 { WAT_DEF_E[WAT_DEF_N] = unchecked bitcast(usize, e) ; WAT_DEF_BLOCK[WAT_DEF_N] = false ; WAT_DEF_N = WAT_DEF_N + 1 }
  else { WAT_DEF_OVF = true }
}

## Register a whole `defer { … }` chain as ONE pending unit. The block statements run together at this
## entry's LIFO position, rather than becoming separate deferred actions.
wat_defer_push_block := fn(head : usize) {
  if WAT_DEF_N < 64 { WAT_DEF_E[WAT_DEF_N] = head ; WAT_DEF_BLOCK[WAT_DEF_N] = true ; WAT_DEF_N = WAT_DEF_N + 1 }
  else { WAT_DEF_OVF = true }
}

## Replay the pending defer actions with stack index in [base, top), LIFO (highest index first) — the
## cleanup emission shared by every exit path. Emission ONLY: the caller decides whether the entries
## are popped (a scope end) or kept (a jump — the fall-through path still owes them).
wat_defer_drain := fn(top : i64, base : i64, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, fn_head : ptr(mut Stmt), decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  if WAT_DEF_OVF { push_str(sb, "    (unreachable) (; defer stack overflow (wasm: >64 live defers) ;)\n") }
  mut k := top
  while k > base {
    k = k - 1
    if WAT_DEF_BLOCK[k] {
      bh := WAT_DEF_E[k]
      bend := wat_defer_blk_end(bh, src)
      if bend == 0 {
        push_str(sb, "    (unreachable) (; defer block end marker missing ;)\n")
      } else {
        ostop := WAT_DEF_STOP
        WAT_DEF_STOP = bend
        emit_wat_stmts(bh, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
        WAT_DEF_STOP = ostop
      }
    } else {
      de := unchecked bitcast(ptr(Expr), WAT_DEF_E[k])
      push_str(sb, "    ")
      emit_wat_expr(de, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
      if exprstmt_needs_drop(de, src, decls, a) { push_str(sb, " (drop)") }
      push_str(sb, "\n")
    }
  }
}

## The dedicated defer RETURN-VALUE scratch local (index `pcount + nlocals + 3` — the FOURTH extra
## local emit_wat_body declares, past the bounds / element-base / copy-source scratches). A `return e`
## (or a tail value) reached with pending defers must evaluate `e` BEFORE the cleanups run — mirroring
## the x86 lower preserving the return registers across the drain — so the value parks here meanwhile.
wat_defer_scratch := fn(pcount : i64, fn_head : ptr(mut Stmt), src : ptr(u8), a : rt::Arena, decls : ptr(rt::Vec)) -> i64 {
  return pcount + count_locals(fn_head, src, a, decls) + 3
}

## If `bs` is a statement list consisting of exactly ONE bare-expression statement (`{ expr }` — a
## braced match arm whose value is that expr), return the expr pointer; else a null pointer. Returns
## ptr(Expr) (NOT a new struct — the frozen seed miscompiles a new struct return type).
arm_single_expr := fn(bs : usize, a : rt::Arena) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  if bs != 0 {
    st := deref(stmt_p(Stmt, bs))
    match st {
      Stmt::ExprStmt(e, nx) => { if nx == 0 { r = e } }
      _ => {}
    }
  }
  r
}

## Is the fn body a SINGLE tail `Stmt::Match` (the whole body is `match … { … }`)? Such a match in a
## value-returning fn yields the fn's value (each braced arm's tail expr is the result).
body_is_single_match := fn(head : ptr(mut Stmt), a : rt::Arena) -> bool {
  mut r := false
  if head != 0 {
    st := deref(stmt_p(Stmt, head))
    match st {
      Stmt::Match(msc, mah, mnx) => { if mnx == 0 { r = true } }
      _ => {}
    }
  }
  r
}

## Emit one match-arm body. In a VALUE-yielding match (`vyield`), a single-expression arm `{ e }`
## delivers the fn value via `(return e)`; a multi-statement value arm is not modelled (trap). In a
## statement (side-effect) match, run the body normally via emit_wat_stmts.
emit_wat_arm_body := fn(bs : usize, vyield : bool, fn_head : ptr(mut Stmt), in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ## `vyield` IS the arm body's tail_value: with it set, emit_wat_stmts turns the arm's trailing
  ## expression statement into `(return …)` — handling single-expr AND multi-statement value arms.
  emit_wat_stmts(bs, fn_head, true, vyield, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
}

## Statement-position match dispatch: a nested value-less WASM `if` chain on the scrutinee's
## discriminant (word 0 at local `sidx`). `vyield` = the match is in fn-value position (each arm
## returns its tail expr). Mutually recursive with emit_wat_stmts.
emit_wat_stmt_match := fn(arm : usize, es : usize, en : usize, sidx : i64, fn_head : ptr(mut Stmt), vyield : bool, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, decls : ptr(rt::Vec)) {
  if arm != 0 {
    am := deref(arm_p(arm))
    if am.wild == 5 or am.wild == 6 {
      ## RANGE pattern arm (Control Flow §5.4) — x86_64-only in v1. Fail LOUD (`(unreachable)`),
      ## never a silent miscompile: the wasm sweep requires a trap or reject, not a wrong exit.
      push_str(sb, "    (unreachable) (; range-pattern match arm not supported on wasm (x86_64 only) ;)\n")
    } else if am.wild == 1 {
      emit_wat_arm_body(am.body_stmts, vyield, fn_head, sb, a, src, params_head, pcount, decls, am.binds_head, sidx)
    } else if am.wild == 2 {
      ## COMPTIME-VARIANT TEMPLATE (`comptime for var in typeinfo(T).variants { T.(var)(p) => body }`):
      ## UNROLL into one dispatch per variant of the scrutinee enum `es/en` (concrete in a mono instance).
      ## Each generated arm binds the payload `p` (bind_base = sidx, word 1) + sets the WAT_ARM_*/WAT_CFVAR
      ## context so an IMPLICIT `hash(p)` in the body infers its type-arg from the variant's payload type.
      ## FLAT ifs — the derive bodies `return`, so no else-nesting is needed. A non-concrete-enum scrutinee
      ## is a fail-loud `(unreachable)` (never the `-1` never-matching arm that sank the reverted attempt).
      edi := enum_decl_of(decls, src, es, en)
      if edi < 0 {
        push_str(sb, "    (unreachable) (; comptime-variant unroll: scrutinee enum not concrete ;)\n")
      } else {
        edd := deref(decl_get(decls, usize(edi)))
        mut vf := edd.fields_head
        while vf != 0 {
          vfm := deref(fld_p(vf))
          vvidx := variant_index(decls, src, es, en, vfm.ns, vfm.nl, a)
          push_str(sb, "    (if (i64.eq (i64.load ")
          emit_wat_addr(sb, sidx, 0)
          push_str(sb, ") (i64.const ")
          push_int(sb, vvidx)
          push_str(sb, ")) (then\n")
          oens := WAT_ARM_ENS ; oenl := WAT_ARM_ENL ; ovs := WAT_ARM_VS ; ovl := WAT_ARM_VL
          obinds := WAT_ARM_BINDS ; ocvs := WAT_CFVAR_S ; ocvl := WAT_CFVAR_L
          WAT_ARM_ENS = es ; WAT_ARM_ENL = en ; WAT_ARM_VS = vfm.ns ; WAT_ARM_VL = vfm.nl
          WAT_ARM_BINDS = unchecked bitcast(usize, am.binds_head) ; WAT_CFVAR_S = vfm.ns ; WAT_CFVAR_L = vfm.nl
          emit_wat_arm_body(am.body_stmts, vyield, fn_head, sb, a, src, params_head, pcount, decls, am.binds_head, sidx)
          WAT_ARM_ENS = oens ; WAT_ARM_ENL = oenl ; WAT_ARM_VS = ovs ; WAT_ARM_VL = ovl
          WAT_ARM_BINDS = obinds ; WAT_CFVAR_S = ocvs ; WAT_CFVAR_L = ocvl
          push_str(sb, "    ))\n")
          vf = vfm.next
        }
        emit_wat_stmt_match(am.next, es, en, sidx, fn_head, vyield, sb, a, src, params_head, pcount, decls)
      }
    } else {
      vidx := variant_index(decls, src, es, en, am.vs, am.vl, a)
      if vidx < 0 {
        ## FAIL-LOUD: an unresolved variant (comptime-variant TEMPLATE arm whose placeholder didn't
        ## resolve, or an enum-span mismatch) — trap, NEVER a `-1` arm that never matches and falls
        ## through to the source tail `return` (a silent miscompile — the reverted-attempt bug).
        push_str(sb, "    (unreachable)\n")
      } else {
        push_str(sb, "    (if (i64.eq (i64.load ")
        emit_wat_addr(sb, sidx, 0)
        push_str(sb, ") (i64.const ")
        push_int(sb, vidx)
        push_str(sb, ")) (then\n")
        emit_wat_arm_body(am.body_stmts, vyield, fn_head, sb, a, src, params_head, pcount, decls, am.binds_head, sidx)
        push_str(sb, "    ) (else\n")
        emit_wat_stmt_match(am.next, es, en, sidx, fn_head, vyield, sb, a, src, params_head, pcount, decls)
        push_str(sb, "    ))\n")
      }
    }
  }
}

## Statement-position SCALAR match dispatch. The caller stores the already-evaluated integer scrutinee
## in the supplied scratch local; literal arms compare that local and wildcard arms run unconditionally.
## This is separate from emit_wat_stmt_match because enum arms load a discriminant from linear memory,
## while scalar matches have no aggregate address or payload-binding context.
emit_wat_scalar_stmt_match := fn(arm : usize, sidx : i64, fn_head : ptr(mut Stmt), vyield : bool, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, decls : ptr(rt::Vec)) {
  if arm == 0 {
    push_str(sb, "    (unreachable) (; no matching scalar arm ;)\n")
  } else {
    am := deref(arm_p(arm))
    if am.wild == 5 or am.wild == 6 {
      push_str(sb, "    (unreachable) (; range-pattern match arm not supported on wasm (x86_64 only) ;)\n")
    } else if am.wild != 0 and am.wild != 1 {
      push_str(sb, "    (unreachable) (; unsupported scalar match pattern on wasm ;)\n")
    } else if am.wild == 1 {
      emit_wat_arm_body(am.body_stmts, vyield, fn_head, sb, a, src, params_head, pcount, decls, am.binds_head, 0)
    } else {
      push_str(sb, "    (if (i64.eq (local.get ") ; push_int(sb, sidx) ; push_str(sb, ") (i64.const ") ; push_int(sb, am.lit) ; push_str(sb, ")) (then\n")
      emit_wat_arm_body(am.body_stmts, vyield, fn_head, sb, a, src, params_head, pcount, decls, am.binds_head, 0)
      push_str(sb, "    ) (else\n")
      emit_wat_scalar_stmt_match(am.next, sidx, fn_head, vyield, sb, a, src, params_head, pcount, decls)
      push_str(sb, "    ))\n")
    }
  }
}

## Emit a statement LIST (recursively for nested while/if bodies). `fn_head` is the FUNCTION's
## top-level head — resolution keys off it, so a reassignment inside a loop/branch binds the same
## local/global as at top level. Return→WASM `return`; While→block/loop+br_if; If→value-less WASM if;
## ExprStmt→the expr (dropping a non-void result). A nested NEW `:=` (name not top-level, not a global)
## traps rather than colliding with a slot.
emit_wat_stmts := fn(list_head : usize, fn_head : ptr(mut Stmt), nested : bool, tail_value : bool, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, decls : ptr(rt::Vec), bind_head : ptr(mut Bind), bind_base : i64) {
  ## DEFER (§9.3): this list IS a scope. Record the pending-cleanup depth on entry; a `defer` inside
  ## pushes above it and the FALL-THROUGH end of the list replays + POPS everything back down to it.
  ## The FUNCTION-body list (`nested` false) is the exception — its drain belongs AFTER the tail
  ## expression is evaluated, so emit_wat_body owns it (see there).
  dscope := WAT_DEF_N
  mut s := list_head
  while s != 0 and s != WAT_DEF_STOP {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        slit := expr_struct_name(v)
        elit := expr_enum_name(v)
        ## the struct span of an aggregate PLACE RHS (`q := p` / `x := arr[i]`) — a whole-aggregate COPY.
        cpsp := wat_place_agg_span(v, params_head, fn_head, src, a, decls)
        lami := wat_bound_lambda(fn_head, src, ns, nl, decls)
        if lami >= 0 {
          idx := name_local_index(fn_head, src, ns, nl, pcount, a, decls)
          push_str(sb, "    (local.set ") ; push_int(sb, idx) ; push_str(sb, " (i64.const 0))\n")
          s = nx
        } else if wat_is_float_global(decls, src, ns, nl) {
          ## a float module global WRITE: the RHS yields i64 bits (value model) → reinterpret to f64
          ## for the `(mut f64)` cell. When the init text is not recoverable (cell never emitted) → TRAP.
          if wat_float_global_init_ok(decls, src, ns, nl) {
            push_str(sb, "    (global.set $")
            push_str(sb, str_at((src + ns), nl))
            push_str(sb, " (f64.reinterpret_i64 ")
            emit_wat_expr(v, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, "))\n")
          } else {
            push_str(sb, "    (unreachable) (; float module global assign (wasm: no init) ;)\n")
          }
          s = nx
        } else if is_global(decls, src, ns, nl, a) {
          gname := str_at((src + ns), nl)
          push_str(sb, "    (global.set $")
          push_str(sb, gname)
          push_str(sb, " ")
          if wat_direct_float_num(v, src, ns, nl) {
            push_str(sb, "(i64.reinterpret_f64 (f64.convert_i64_s ")
            emit_wat_expr(v, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, "))")
          } else { emit_wat_expr(v, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
          push_str(sb, ")\n")
          s = nx
        } else if slit.n != 0 {
          ## struct construction `p := S(f0=v0, …)`: bump-allocate `struct_words*8` bytes in linear
          ## memory, put the base address in p's local, store each (positional) field value.
          idx := name_local_index(fn_head, src, ns, nl, pcount, a, decls)
          if layout_kind_is_byte(layout_kind(decls, src, slit.s, slit.n, a)) {
            ## Standard §6.1 construction: reserve the rounded byte size and write every field at its
            ## shared byte offset. This is distinct from the legacy word-addressed constructor below.
            szb := standard_type_byte_size(decls, src, slit.s, slit.n, 1, a)
            push_str(sb, "    (local.set ") ; push_int(sb, idx) ; push_str(sb, " (global.get $__sp))\n")
            push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const ") ; push_int(sb, i64(szb)) ; push_str(sb, ")))\n")
            _stdw := wat_std_store_struct(v, idx, 0, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            s = nx
          } else if struct_all_scalar(decls, src, slit.s, slit.n, a) {
            sz := struct_words(decls, src, slit.s, slit.n, a)
            push_str(sb, "    (local.set ")
            push_int(sb, idx)
            push_str(sb, " (global.get $__sp))\n")
            push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const ")
            push_int(sb, i64(sz) * 8)
            push_str(sb, ")))\n")
            ## store each positional field value at base + k*8 (scalar fields → one word each)
            mut g := ex_struct_lit_args(v)
            mut k := 0
            while g != 0 {
              ga := deref(arg_p(g))
              push_str(sb, "    (i64.store ")
              emit_wat_addr(sb, idx, i64(k) * 8)
              push_str(sb, " ")
              emit_wat_expr(ga.e, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
              push_str(sb, ")\n")
              k += 1
              g = ga.next
            }
            s = nx
          } else if struct_plain(decls, src, slit.s, slit.n) {
            ## a struct with a MULTI-WORD field (a nested struct, an inline `[T; N]`, an enum): reserve the
            ## FLATTENED width and write the literal through the flattened writer, so every nested value
            ## lands INLINE at the cumulative offset `field_word_offset` reports (what the deep-place
            ## composition walks). The all-scalar branch above is untouched, so its positional emit — and
            ## its one-word BY-REFERENCE nested field — stays byte-identical.
            szf := struct_words(decls, src, slit.s, slit.n, a)
            push_str(sb, "    (local.set ") ; push_int(sb, idx) ; push_str(sb, " (global.get $__sp))\n")
            push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const ") ; push_int(sb, i64(szf) * 8) ; push_str(sb, ")))\n")
            wf := emit_wat_store_payload_at(v, idx, 0, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            s = nx
          } else {
            push_str(sb, "    (unreachable) (; unsupported non-scalar struct ;)\n")
            s = 0
          }
        } else if elit.n != 0 {
          ## enum construction `e := E.V(payload…)`: bump-allocate 1 (disc) + enum_max_arity payload
          ## words, store the variant index at word 0, then each scalar payload at words 1,2,…
          idx := name_local_index(fn_head, src, ns, nl, pcount, a, decls)
          sz := 1 + enum_max_arity(decls, src, elit.s, elit.n, a)
          evar := expr_enum_variant(v)
          vidx := variant_index(decls, src, elit.s, elit.n, evar.s, evar.n, a)
          push_str(sb, "    (local.set ")
          push_int(sb, idx)
          push_str(sb, " (global.get $__sp))\n")
          push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const ")
          push_int(sb, i64(sz) * 8)
          push_str(sb, ")))\n")
          push_str(sb, "    (i64.store ")
          emit_wat_addr(sb, idx, 0)
          push_str(sb, " (i64.const ")
          push_int(sb, vidx)
          push_str(sb, "))\n")
          mut g := ex_enum_lit_args(v)
          mut k := 1
          while g != 0 {
            ga := deref(arg_p(g))
            push_str(sb, "    (i64.store ")
            emit_wat_addr(sb, idx, i64(k) * 8)
            push_str(sb, " ")
            emit_wat_expr(ga.e, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ")\n")
            k += 1
            g = ga.next
          }
          s = nx
        } else if ex_is_array_lit(v) {
          ## array construction `a := [e0, …]`: bump nel*estride words, store each element at base +
          ## k*estride*8. A SCALAR element (estride 1) is one word; a STRUCT element (a StructLit, estride
          ## = struct_words) stores each positional field at base + (k*estride + fk)*8 (the aggregate-array
          ## layout — x86's stride). The local holds the region base (elements are by-reference words).
          idx := name_local_index(fn_head, src, ns, nl, pcount, a, decls)
          anel := array_lit_nel(v)
          estrideA := array_lit_stride(v, src, a, decls)
          push_str(sb, "    (local.set ")
          push_int(sb, idx)
          push_str(sb, " (global.get $__sp))\n")
          push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const ")
          push_int(sb, i64(anel) * estrideA * 8)
          push_str(sb, ")))\n")
          mut g := ex_array_lit_ehead(v)
          mut k := 0
          while g != 0 {
            ga := deref(arg_p(g))
            sp := expr_struct_name(ga.e)
            ep := expr_enum_name(ga.e)
            if sp.n != 0 {
              ## a NESTED-AGGREGATE element struct goes through the FLATTENED writer (positional
              ## one-word-per-argument stores would keep only word 0 of a multi-word field and misalign
              ## every field after it); an ALL-SCALAR element keeps the byte-identical positional emit.
              mut flatel := false
              if struct_plain(decls, src, sp.s, sp.n) { if not struct_all_scalar(decls, src, sp.s, sp.n, a) { flatel = true } }
              if flatel {
                wfe := emit_wat_store_payload_at(ga.e, idx, i64(k) * estrideA * 8, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
              } else {
                mut fg := ex_struct_lit_args(ga.e)
                mut fk := 0
                while fg != 0 {
                  fga := deref(arg_p(fg))
                  push_str(sb, "    (i64.store ")
                  emit_wat_addr(sb, idx, (i64(k) * estrideA + fk) * 8)
                  push_str(sb, " ")
                  emit_wat_expr(fga.e, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
                  push_str(sb, ")\n")
                  fk += 1
                  fg = fga.next
                }
              }
            }
            if ep.n != 0 {
              evar := expr_enum_variant(ga.e)
              evx := variant_index(decls, src, ep.s, ep.n, evar.s, evar.n, a)
              push_str(sb, "    (i64.store ")
              emit_wat_addr(sb, idx, i64(k) * estrideA * 8)
              push_str(sb, " (i64.const ") ; push_int(sb, evx) ; push_str(sb, "))\n")
              mut pg := ex_enum_lit_args(ga.e)
              mut pk := 1
              while pg != 0 {
                pga := deref(arg_p(pg))
                push_str(sb, "    (i64.store ")
                emit_wat_addr(sb, idx, (i64(k) * estrideA + pk) * 8)
                push_str(sb, " ")
                emit_wat_expr(pga.e, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
                push_str(sb, ")\n")
                pk += 1
                pg = pga.next
              }
            }
            if sp.n == 0 and ep.n == 0 {
              push_str(sb, "    (i64.store ")
              emit_wat_addr(sb, idx, i64(k) * estrideA * 8)
              push_str(sb, " ")
              emit_wat_expr(ga.e, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
              push_str(sb, ")\n")
            }
            k += 1
            g = ga.next
          }
          s = nx
        } else if ex_is_slice(v) {
          ## range-slice binding `s := base[lo..hi]` — a 2-word {ptr, len} view in the `$__sp` region
          ## (like a struct): word0 = &base[lo] = base-array pointer + lo*8; word1 = hi - lo. Only a
          ## scalar array-local base is supported; anything else is fail-loud (`unreachable`).
          idx := name_local_index(fn_head, src, ns, nl, pcount, a, decls)
          bn := expr_var_name(ex_slice_base(v))
          bidx := name_local_index(fn_head, src, bn.s, bn.n, pcount, a, decls)
          mut sliceok := false
          if bn.n != 0 { if is_array_local(fn_head, src, bn.s, bn.n, a) { if bidx >= 0 { sliceok = true } } }
          if sliceok {
            ## element stride of the base array (1 for scalar → lo*8, byte-identical; struct/enum → lo*stride*8).
            estrideS := array_local_stride(fn_head, src, bn.s, bn.n, a, decls)
            push_str(sb, "    (local.set ") ; push_int(sb, idx) ; push_str(sb, " (global.get $__sp))\n")
            push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const 16)))\n")
            ## word0 = &base[lo] = base-array pointer + lo*estride*8
            push_str(sb, "    (i64.store ") ; emit_wat_addr(sb, idx, 0)
            push_str(sb, " (i64.add (local.get ") ; push_int(sb, bidx) ; push_str(sb, ") (i64.mul ")
            emit_wat_expr(ex_slice_lo(v), sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, " (i64.const ") ; push_int(sb, estrideS * 8) ; push_str(sb, "))))\n")
            ## word1 = hi - lo
            push_str(sb, "    (i64.store ") ; emit_wat_addr(sb, idx, 8)
            push_str(sb, " (i64.sub ")
            emit_wat_expr(ex_slice_hi(v), sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, " ")
            emit_wat_expr(ex_slice_lo(v), sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, "))\n")
          }
          if not sliceok { push_str(sb, "    (unreachable) (; unsupported slice binding ;)\n") }
          s = nx
        } else if cpsp.n != 0 {
          ## whole-aggregate COPY `q := p` / `x := arr[i]`: the RHS is a PLACE someone else owns, so the
          ## binding gets its OWN `$__sp` block and the struct's words are copied into it (aliasing the
          ## source would make a later write to either show through the other). The source base address is
          ## stashed in the 3rd scratch local FIRST — evaluating it can bump `$__sp` itself.
          idx := name_local_index(fn_head, src, ns, nl, pcount, a, decls)
          sc3 := pcount + count_locals(fn_head, src, a, decls) + 2
          ## `struct_words` is the FLATTENED width and the copy is word-wise, so a NESTED-AGGREGATE field
          ## rides along correctly — only a PLAIN (arity-0) decl is required, not an all-scalar one.
          ## CLAYOUT S3(b) — EXCEPT when the place is a FIELD of a standard byte-layout root, which
          ## `wat_place_agg_span` resolves through `wat_std_path_*`: there the SOURCE is a byte-precise
          ## sub-place while the destination block is read back at WORD offsets, so a word-wise copy is
          ## only right for a WORD-GRANULAR child. S3(b) made a sub-word child constructible and thereby
          ## put one in front of this copy for the first time: measured without the guard,
          ## `copy := o.inner` over `struct { data : [u8;8], inner : struct { a : u16, b : u16 } }`
          ## returned exit 1 (`copy.a` read 0) where the pre-S3(b) compiler trapped — a wrong value
          ## where there was a trap, which I11 forbids. A whole-struct copy `q := o` of the byte-layout
          ## ROOT itself is untouched: source and destination have the same layout there, so the guard
          ## is restricted to the FIELD place. The byte-precise COPIER is its own consumer (audit S3).
          mut cpwg := true
          if ex_is_field(v) and (not std_struct_is_word_granular(decls, src, cpsp.s, cpsp.n, a)) { cpwg = false }
          ## CLAYOUT S3(c) — THE BYTE-PRECISE COPIER takes exactly what the word copy above cannot.
          ## `std_copy_kind` (shared, `lower_layout`) decides whether this child has a byte-precise copy
          ## and of which shape; the SOURCE address is the root's base local plus the path's §6.1 byte
          ## offset (`wat_std_path_root_idx` + `wat_std_path_bo`) rather than `emit_wat_expr`, which has
          ## no aggregate-field load at all and would emit an `(unreachable)`. A child OUTSIDE the
          ## copier's domain keeps the located trap below.
          mut cpbc := 0
          mut cpsidx := i64(0) - 1
          mut cpsbo := i64(0) - 1
          if (not cpwg) {
            cpbc = std_copy_kind(decls, src, cpsp.s, cpsp.n, a)
            cpsidx = wat_std_path_root_idx(v, fn_head, src, pcount, a, decls)
            cpsbo = wat_std_path_bo(v, fn_head, src, a, decls)
          }
          mut cpbok := false
          if cpbc != 0 and cpsidx >= 0 and cpsbo >= 0 { cpbok = true }
          if cpbok {
            cpwb := i64(struct_words(decls, src, cpsp.s, cpsp.n, a))
            push_str(sb, "    (local.set ") ; push_int(sb, idx) ; push_str(sb, " (global.get $__sp))\n")
            push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const ") ; push_int(sb, cpwb * 8) ; push_str(sb, ")))\n")
            wat_std_copy(cpsp.s, cpsp.n, cpsidx, cpsbo, idx, sb, decls, src, a)
          }
          if (not cpbok) and cpwg and (struct_all_scalar(decls, src, cpsp.s, cpsp.n, a) or struct_plain(decls, src, cpsp.s, cpsp.n)) {
            cpw := i64(struct_words(decls, src, cpsp.s, cpsp.n, a))
            push_str(sb, "    (local.set ") ; push_int(sb, sc3) ; push_str(sb, " ")
            emit_wat_expr(v, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ")\n")
            push_str(sb, "    (local.set ") ; push_int(sb, idx) ; push_str(sb, " (global.get $__sp))\n")
            push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const ") ; push_int(sb, cpw * 8) ; push_str(sb, ")))\n")
            emit_wat_word_copy(sb, idx, sc3, cpw)
          }
          if (not cpbok) and (not (cpwg and (struct_all_scalar(decls, src, cpsp.s, cpsp.n, a) or struct_plain(decls, src, cpsp.s, cpsp.n)))) {
            push_str(sb, "    (unreachable) (; aggregate copy: non-scalar-field, or a byte-layout field extract outside the byte-precise copier's domain ;)\n")
          }
          s = nx
        } else if wat_ann_arr_words(src, ns, nl, v, a, decls) > 0 {
          ## `mut xs : [E; N]` — an explicitly UNINITIALIZED fixed-array local. The parser plants a Num(0)
          ## SENTINEL value, so the array's storage exists only in the source annotation; the `(local.set
          ## idx (i64.const 0))` fall-through below gave the slot NO block at all and every access trapped.
          ## Reserve N*width(E) words in the `$__sp` bump region and put the base in the slot, exactly as an
          ## array LITERAL declaration does — the elements are then written by `xs[i] = …`.
          idx := name_local_index(fn_head, src, ns, nl, pcount, a, decls)
          annw := wat_ann_arr_words(src, ns, nl, v, a, decls)
          push_str(sb, "    (local.set ") ; push_int(sb, idx) ; push_str(sb, " (global.get $__sp))\n")
          push_str(sb, "    (global.set $__sp (i64.add (global.get $__sp) (i64.const ") ; push_int(sb, annw * 8) ; push_str(sb, ")))\n")
          s = nx
        } else {
          idx := name_local_index(fn_head, src, ns, nl, pcount, a, decls)
          push_str(sb, "    (local.set ")
          push_int(sb, idx)
          push_str(sb, " ")
          if wat_direct_float_num(v, src, ns, nl) {
            push_str(sb, "(i64.reinterpret_f64 (f64.convert_i64_s ")
            emit_wat_expr(v, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, "))")
          } else { emit_wat_expr(v, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
          push_str(sb, ")\n")
          s = nx
        }
      }
      Stmt::Return(rv, nx) => {
        ## DEFER (§9.3): a `return` drains the WHOLE pending stack (every enclosing scope, innermost
        ## first) on the way out. The return value is evaluated FIRST and parked in the defer scratch
        ## local, so a cleanup that mutates the value's inputs cannot change what is returned (the x86
        ## lower's "preserve the return registers across the drain"). No pending defers → byte-identical.
        if WAT_DEF_N > 0 and (not ex_is_no_tail(rv)) {
          dsc := wat_defer_scratch(pcount, fn_head, src, a, decls)
          push_str(sb, "    (local.set ")
          push_int(sb, dsc)
          push_str(sb, " ")
          emit_wat_expr(rv, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
          wat_defer_drain(WAT_DEF_N, 0, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, "    (return (local.get ")
          push_int(sb, dsc)
          push_str(sb, "))\n")
        } else {
          if WAT_DEF_N > 0 { wat_defer_drain(WAT_DEF_N, 0, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
          push_str(sb, "    (return ")
          emit_wat_expr(rv, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        }
        s = nx
      }
      Stmt::ExprStmt(e, nx) => {
        ## DEFER (§9.3): `defer <expr>` arrives as the marker call `__defer(<expr>)`. REGISTER the action
        ## (emitting NOTHING here) — it is replayed at the exits of THIS scope. Checked before every other
        ## ExprStmt shape (incl. the tail-value one), since a marker is never the block's value.
        dact := wat_defer_action(e, src, a)
        pi := print_call_info(e, src, a)
        mut dstop := false
        mut dnext := nx
        if unchecked bitcast(usize, dact) != 0 {
          wat_defer_push(dact)
        } else if wat_is_defer_blk(e, src) {
          ## Register the whole linked chain and jump over its inline body. The body is emitted only by
          ## wat_defer_drain, at the cleanup's LIFO position; a malformed chain remains fail-loud.
          bh := unchecked bitcast(usize, nx)
          bend := wat_defer_blk_end(bh, src)
          if bend == 0 {
            push_str(sb, "    (unreachable) (; defer block end marker missing ;)\n")
            dstop = true
          } else {
            wat_defer_push_block(bh)
            dnext = unchecked bitcast(ptr(mut Stmt), wat_stmt_next(bend))
          }
        } else if pi.ok {
          if has_hole(src, pi.ss, pi.sl, a) { emit_print_template(pi, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
          else { emit_print(sb, pi) }
        } else if tail_value and nx == 0 and exprstmt_needs_drop(e, src, decls, a) {
          ## the fn/arm's TAIL expression statement in value position → it IS the result: return it
          ## (exprstmt_needs_drop true = the expr yields a value; a void call is not returnable).
          ## DEFER: with pending cleanups the value is parked in the scratch local first, the stack
          ## drains LIFO, then the parked value is returned (evaluate-then-clean-then-return).
          if WAT_DEF_N > 0 {
            dsc := wat_defer_scratch(pcount, fn_head, src, a, decls)
            push_str(sb, "    (local.set ")
            push_int(sb, dsc)
            push_str(sb, " ")
            emit_wat_expr(e, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ")\n")
            wat_defer_drain(WAT_DEF_N, 0, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, "    (return (local.get ")
            push_int(sb, dsc)
            push_str(sb, "))\n")
          } else {
            push_str(sb, "    (return ")
            emit_wat_expr(e, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ")\n")
          }
        } else {
          push_str(sb, "    ")
          emit_wat_expr(e, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          if exprstmt_needs_drop(e, src, decls, a) { push_str(sb, " (drop)") }
          push_str(sb, "\n")
        }
        if dstop { s = 0 } else { s = dnext }
      }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => {
        ## `p.field = v` for a struct PARAM or LOCAL p: i64.store v at (p's base + field offset).
        gagg := agg_global_base(decls, src, bns, bnl, a)
        gstyp := global_struct_type(decls, src, bns, bnl, a)
        styp := base_struct_type(params_head, fn_head, src, bns, bnl, a, decls)
        bpidx := param_find(params_head, src, bns, bnl, a)
        isloc := is_toplevel_local(fn_head, bns, bnl, src, a)
        mut stdhandled := false
        if isloc and styp.n != 0 and layout_kind_is_byte(layout_kind(decls, src, styp.s, styp.n, a)) {
          sbo := standard_field_byte_offset(decls, src, styp.s, styp.n, fns, fnl, a)
          sft := struct_field_type(decls, src, styp.s, styp.n, fns, fnl, a)
          bidxS := name_local_index(fn_head, src, bns, bnl, pcount, a, decls)
          if sbo >= 0 and sft.n != 0 {
            if std_ty_aggregate(sft.s, sft.n, decls, src) {
              if expr_struct_name(fv).n != 0 { _stdw := wat_std_store_struct(fv, bidxS, sbo, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
              if expr_struct_name(fv).n == 0 { push_str(sb, "    (unreachable) (; unsupported standard aggregate field assign ;)\n") }
              stdhandled = true
            }
            if not std_ty_aggregate(sft.s, sft.n, decls, src) {
              wat_std_store_expr(fv, bidxS, sbo, sft.s, sft.n, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
              stdhandled = true
            }
          }
        }
        if (not stdhandled) and gagg >= 0 and gstyp.n != 0 and struct_all_scalar(decls, src, gstyp.s, gstyp.n, a) {
          woff := field_word_offset(decls, src, gstyp.s, gstyp.n, fns, fnl, a)
          push_str(sb, "    (i64.store ")
          emit_wat_addr(sb, 0 - (gagg + 1), woff * 8)
          push_str(sb, " ")
          emit_wat_expr(fv, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else if (not stdhandled) and styp.n != 0 and struct_all_scalar(decls, src, styp.s, styp.n, a) and (bpidx >= 0 or isloc) {
          woff := field_word_offset(decls, src, styp.s, styp.n, fns, fnl, a)
          mut bidx := bpidx
          if bpidx < 0 { bidx = name_local_index(fn_head, src, bns, bnl, pcount, a, decls) }
          push_str(sb, "    (i64.store ")
          emit_wat_addr(sb, bidx, woff * 8)
          push_str(sb, " ")
          emit_wat_expr(fv, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else if not stdhandled {
          push_str(sb, "    (unreachable) (; unsupported field assign ;)\n")
        }
        s = nx
      }
      Stmt::IndexAssign(ibase, iidx, ival, nx) => {
        ## `a[i] = v` (ARRAY local) / `s[i] = v` (range-SLICE view): i64.store v at the element address.
        ## Array base = the local's pointer; slice base = word0 (data ptr, i64.load at s-base). Bounds
        ## (WAT_CHK): stash i in the scratch local, trap (unreachable) if i >= the count — a static N for
        ## an array, the runtime len (word1) for a slice; i64.ge_u so a negative index also traps.
        bn := expr_var_name(ibase)
        mut isslice := false
        if bn.n != 0 { if is_slice_local(fn_head, src, bn.s, bn.n, a) { isslice = true } }
        isarr := bn.n != 0 and is_array_local(fn_head, src, bn.s, bn.n, a)
        sc := pcount + count_locals(fn_head, src, a, decls)
        ## AGGREGATE element (`arr[i] = <struct>`): the element is `stride` words wide, so the single
        ## stride-8 `i64.store` below would keep only word 0 and drop the rest. Copy every word from the
        ## RHS aggregate's base instead. Both bases are stashed in scratch locals first (evaluating either
        ## can bump `$__sp`), then copied ascending. Tested BEFORE the scalar paths; anything not
        ## resolvable — a non-scalar-field element, a non-aggregate RHS, a mismatched width, or a
        ## multi-word NON-struct element — traps rather than storing a partial/aliased element.
        aggel := wat_arr_elem_struct(fn_head, src, bn.s, bn.n, a, decls)
        aggstride := if aggel.n == 0 { wat_arr_elem_stride(fn_head, src, bn.s, bn.n, a, decls) } else { 1 }
        if aggel.n != 0 {
          rhsp := wat_rhs_agg_span(ival, params_head, fn_head, src, a, decls)
          sc2 := sc + 1
          sc3 := sc + 2
          mut wok := false
          if rhsp.n != 0 and struct_all_scalar(decls, src, aggel.s, aggel.n, a) and struct_all_scalar(decls, src, rhsp.s, rhsp.n, a) {
            if struct_words(decls, src, rhsp.s, rhsp.n, a) == struct_words(decls, src, aggel.s, aggel.n, a) { wok = true }
          }
          ## a NESTED-AGGREGATE element written from a struct LITERAL (`xs[i] = Cell(pad=…, inner=Leaf(…),
          ## z=…)`): the FLATTENED writer lays the literal out INLINE at the element address, so a nested
          ## struct / `[T; N]` field lands in FULL and the fields after it stay aligned. The word-COPY path
          ## above cannot serve it — a nested struct literal has no linear-memory image to copy FROM (the
          ## StructLit expression arm is itself all-scalar-only). The element address is stashed in the
          ## scratch local FIRST, since the field value emits can bump `$__sp`.
          mut lok := false
          if (not wok) and expr_struct_name(ival).n != 0 {
            if struct_plain(decls, src, aggel.s, aggel.n) {
              esn := expr_struct_name(ival)
              if streq(src, esn.s, esn.n, aggel.s, aggel.n) { lok = true }
            }
          }
          if lok {
            push_str(sb, "    (local.set ") ; push_int(sb, sc2) ; push_str(sb, " ")
            emit_wat_agg_elem_addr(ibase, iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ")\n")
            if std_array_elem_byte_tier(decls, src, aggel.s, aggel.n, a) { wle := wat_std_store_struct(ival, sc2, 0, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
            if not std_array_elem_byte_tier(decls, src, aggel.s, aggel.n, a) { wle := emit_wat_store_payload_at(ival, sc2, 0, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
          } else if wok {
            ew := i64(struct_words(decls, src, aggel.s, aggel.n, a))
            push_str(sb, "    (local.set ") ; push_int(sb, sc3) ; push_str(sb, " ")
            emit_wat_expr(ival, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ")\n")
            push_str(sb, "    (local.set ") ; push_int(sb, sc2) ; push_str(sb, " ")
            emit_wat_agg_elem_addr(ibase, iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ")\n")
            emit_wat_word_copy(sb, sc2, sc3, ew)
          } else {
            push_str(sb, "    (unreachable) (; unsupported aggregate element assign ;)\n")
          }
        } else if aggstride > 1 {
          push_str(sb, "    (unreachable) (; multi-word non-struct array element assign ;)\n")
        } else if isslice {
          bidx := name_local_index(fn_head, src, bn.s, bn.n, pcount, a, decls)
          push_str(sb, "    (i64.store (i32.wrap_i64 (i64.add (i64.load ")
          emit_wat_addr(sb, bidx, 0)
          push_str(sb, ") (i64.mul ")
          if WAT_CHK {
            push_str(sb, "(block (result i64) (local.set ")
            push_int(sb, sc)
            push_str(sb, " ")
            emit_wat_expr(iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ") (if (i64.ge_u (local.get ")
            push_int(sb, sc)
            push_str(sb, ") (i64.load ")
            emit_wat_addr(sb, bidx, 8)
            push_str(sb, ")) (then (unreachable))) (local.get ")
            push_int(sb, sc)
            push_str(sb, "))")
          } else {
            emit_wat_expr(iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          }
          push_str(sb, " (i64.const 8)))) ")
          emit_wat_expr(ival, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else if isarr {
          bidx := name_local_index(fn_head, src, bn.s, bn.n, pcount, a, decls)
          wnel := array_local_nel(fn_head, src, bn.s, bn.n, a)
          push_str(sb, "    (i64.store (i32.wrap_i64 (i64.add (local.get ")
          push_int(sb, bidx)
          push_str(sb, ") (i64.mul ")
          if WAT_CHK and wnel > 0 {
            push_str(sb, "(block (result i64) (local.set ")
            push_int(sb, sc)
            push_str(sb, " ")
            emit_wat_expr(iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ") (if (i64.ge_u (local.get ")
            push_int(sb, sc)
            push_str(sb, ") (i64.const ")
            push_int(sb, i64(wnel))
            push_str(sb, ")) (then (unreachable))) (local.get ")
            push_int(sb, sc)
            push_str(sb, "))")
          } else {
            emit_wat_expr(iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          }
          push_str(sb, " (i64.const 8)))) ")
          emit_wat_expr(ival, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else if bn.n != 0 and wat_is_array_global(decls, src, bn.s, bn.n, a) {
          ## `TABLE[i] = v` on an ARRAY GLOBAL: store v at the fixed base + i*8. Bounds vs the static
          ## count via the scratch local (WAT_CHK); i64.ge_u so a negative index also traps.
          gbase := agg_global_base(decls, src, bn.s, bn.n, a)
          wnelg := wat_array_global_nel(decls, src, bn.s, bn.n, a)
          push_str(sb, "    (i64.store (i32.wrap_i64 (i64.add (i64.const ")
          push_int(sb, gbase)
          push_str(sb, ") (i64.mul ")
          if WAT_CHK and wnelg > 0 {
            push_str(sb, "(block (result i64) (local.set ") ; push_int(sb, sc) ; push_str(sb, " ")
            emit_wat_expr(iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ") (if (i64.ge_u (local.get ") ; push_int(sb, sc) ; push_str(sb, ") (i64.const ") ; push_int(sb, wnelg) ; push_str(sb, ")) (then (unreachable))) (local.get ") ; push_int(sb, sc) ; push_str(sb, "))")
          } else {
            emit_wat_expr(iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          }
          push_str(sb, " (i64.const 8)))) ")
          emit_wat_expr(ival, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else if wat_deep_idx_scalar_ok(ibase, fn_head, src, params_head, pcount, a, decls) {
          ## `xs[i].arr[j] = v` — a DEEP element WRITE (the base is a FIELD, not a bare Var, so no closed
          ## formula exists). WASM evaluates the store's ADDRESS operand before its VALUE operand, so the
          ## composed address is already on the stack when the value emit reuses the shared scratch local.
          dity := wat_place_idx_ty(ibase, fn_head, src, a, decls)
          diw := scalar_byte_size(src, dity.s, dity.n)
          if wat_std_idx_path_ok(ibase, fn_head, src, a, decls) {
            if diw == 1 { push_str(sb, "    (i64.store8 (i32.wrap_i64 ") }
            if diw == 2 { push_str(sb, "    (i64.store16 (i32.wrap_i64 ") }
            if diw == 4 { push_str(sb, "    (i64.store32 (i32.wrap_i64 ") }
            if diw == 8 { push_str(sb, "    (i64.store (i32.wrap_i64 ") }
          }
          if not wat_std_idx_path_ok(ibase, fn_head, src, a, decls) { push_str(sb, "    (i64.store (i32.wrap_i64 ") }
          emit_wat_place_idx_addr(ibase, iidx, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ") ")
          emit_wat_expr(ival, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else {
          push_str(sb, "    (unreachable) (; unsupported index assign ;)\n")
        }
        s = nx
      }
      ## `xs[i].f = v` / `b.cells[i].m = v` — a scalar FIELD write into an ELEMENT of a fixed array. The
      ## wat backend had NO arm for this statement at all (it fell to the `_` default, which both trapped
      ## AND stopped emitting the rest of the list). The element address is COMPOSED (the indexed base may
      ## itself be an inline `[Struct; N]` FIELD) and the scalar field stored at its word offset within the
      ## element; the field must be a genuine ONE-WORD scalar, so an aggregate field stays fail-loud.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => {
        difty := wat_place_idx_ty(ifb, fn_head, src, a, decls)
        mut deepif := false
        if difty.n != 0 {
          if struct_decl_of(decls, src, difty.s, difty.n) >= 0 {
            if struct_plain(decls, src, difty.s, difty.n) {
              dft := struct_field_type(decls, src, difty.s, difty.n, iffs, iffl, a)
              if wat_ty_word_scalar(src, dft.s, dft.n, a, decls) {
                if wat_place_idx_ok(ifb, fn_head, src, params_head, pcount, a, decls) { deepif = true }
              }
            }
          }
        }
        if deepif {
          mut dboff := i64(field_word_offset(decls, src, difty.s, difty.n, iffs, iffl, a)) * 8
          mut difbyte := false
          if std_array_elem_byte_tier(decls, src, difty.s, difty.n, a) { dboff = layout_field_offset_bytes(decls, src, difty.s, difty.n, iffs, iffl, a) ; difbyte = true }
          dft := struct_field_type(decls, src, difty.s, difty.n, iffs, iffl, a)
          dfw := scalar_byte_size(src, dft.s, dft.n)
          if difbyte {
            if dfw == 1 { push_str(sb, "    (i64.store8 (i32.wrap_i64 (i64.add ") }
            if dfw == 2 { push_str(sb, "    (i64.store16 (i32.wrap_i64 (i64.add ") }
            if dfw == 4 { push_str(sb, "    (i64.store32 (i32.wrap_i64 (i64.add ") }
            if dfw == 8 { push_str(sb, "    (i64.store (i32.wrap_i64 (i64.add ") }
          }
          if not difbyte { push_str(sb, "    (i64.store (i32.wrap_i64 (i64.add ") }
          emit_wat_place_idx_addr(ifb, ifi, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, " (i64.const ") ; push_int(sb, dboff) ; push_str(sb, "))) ")
          emit_wat_expr(ifv, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else {
          push_str(sb, "    (unreachable) (; unsupported index-field assign ;)\n")
        }
        s = ifnx
      }
      Stmt::FieldPathAssign(place, val, nx) => {
        ## NESTED field write `o.i.v = e`: the place is a `Field` chain. Store `e` at
        ## (base-of-`o.i` + field `v`'s offset); the base emitted as a value yields the inner
        ## struct's base (nested structs are by-reference). Mirrors the nested field READ. The
        ## base/field are extracted via single-level-match helpers (no inline nested match).
        base := expr_field_base(place)
        fsp := expr_field_span(place)
        stdft := wat_std_path_ty(place, fn_head, src, a, decls)
        stdfpok := wat_std_path_ok(place, fn_head, src, a, decls) and stdft.n != 0 and (not std_ty_aggregate(stdft.s, stdft.n, decls, src))
        if stdfpok {
          sidx := wat_std_path_root_idx(place, fn_head, src, pcount, a, decls)
          sbo := wat_std_path_bo(place, fn_head, src, a, decls)
          wat_std_store_expr(val, sidx, sbo, stdft.s, stdft.n, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
        }
        ## First try a NESTED struct-GLOBAL chain (`STATE.a.b.c = e`): store at the const address
        ## (root global base + cumulative-word-offset*8), nested structs FLATTENED.
        groot := wat_gchain_root(place)
        gbase := agg_global_base(decls, src, groot.s, groot.n, a)
        gtype := wat_gchain_type(place, decls, src, a)
        gwoff := wat_gchain_woff(place, decls, src, a)
        gchainok := gbase >= 0 and gwoff >= 0 and gtype.n != 0 and ty_is_scalar(gtype.s, gtype.n, decls, src)
        btype := expr_struct_type_of(base, params_head, fn_head, src, a, decls)
        if (not stdfpok) and gchainok {
          push_str(sb, "    (i64.store ")
          emit_wat_addr(sb, 0 - (gbase + 1), gwoff * 8)
          push_str(sb, " ")
          emit_wat_expr(val, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else if (not stdfpok) and wat_deep_scalar_ok(place, fn_head, src, params_head, pcount, a, decls) {
          ## `xs[i].b.c.cx = v` / `xs[i].inner.x = v` — the DEEP dual of the composed field READ: the chain
          ## is rooted at an array ELEMENT (a RUNTIME address), so no cumulative frame offset exists.
          ## Address operand first (WASM evaluates it before the value), then the one-word store. Tried
          ## BEFORE the by-reference nested-field path below, under the same FLATTENED-STORAGE guard.
          dpty := wat_place_ty(place, fn_head, src, a, decls)
          dpw := scalar_byte_size(src, dpty.s, dpty.n)
          if wat_std_idx_path_ok(place, fn_head, src, a, decls) {
            if dpw == 1 { push_str(sb, "    (i64.store8 (i32.wrap_i64 ") }
            if dpw == 2 { push_str(sb, "    (i64.store16 (i32.wrap_i64 ") }
            if dpw == 4 { push_str(sb, "    (i64.store32 (i32.wrap_i64 ") }
            if dpw == 8 { push_str(sb, "    (i64.store (i32.wrap_i64 ") }
          }
          if not wat_std_idx_path_ok(place, fn_head, src, a, decls) { push_str(sb, "    (i64.store (i32.wrap_i64 ") }
          emit_wat_place_addr(place, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ") ")
          emit_wat_expr(val, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else if (not stdfpok) and fsp.n != 0 and btype.n != 0 and struct_all_scalar(decls, src, btype.s, btype.n, a) {
          ## NESTED field write on a LOCAL: the base emitted as a value yields the inner struct's base
          ## (nested structs are by-reference). Mirrors the nested field READ.
          woff := field_word_offset(decls, src, btype.s, btype.n, fsp.s, fsp.n, a)
          push_str(sb, "    (i64.store (i32.wrap_i64 (i64.add ")
          emit_wat_expr(base, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, " (i64.const ")
          push_int(sb, woff * 8)
          push_str(sb, "))) ")
          emit_wat_expr(val, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
        } else if not stdfpok {
          push_str(sb, "    (unreachable) (; unsupported field-path assign ;)\n")
        }
        s = nx
      }
      Stmt::While(c, b, nx) => {
        id := wat_next_label()
        ob := WAT_BRK
        oc := WAT_CONT
        odb := WAT_BRK_DB
        odc := WAT_CONT_DB
        WAT_BRK = id
        WAT_CONT = id
        ## DEFER: the body's entry depth — `break`/`continue` inside it replay down to here.
        WAT_BRK_DB = WAT_DEF_N
        WAT_CONT_DB = WAT_DEF_N
        push_str(sb, "    (block $brk") ; push_int(sb, id) ; push_str(sb, " (loop $lp") ; push_int(sb, id) ; push_str(sb, "\n")
        push_str(sb, "      (br_if 1 (i32.eqz (i32.wrap_i64 ")
        emit_wat_expr(c, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
        push_str(sb, ")))\n")
        ## `continue` target: exit this inner block → fall through to the `(br 0)` back-edge (re-eval cond).
        push_str(sb, "      (block $cont") ; push_int(sb, id) ; push_str(sb, "\n")
        emit_wat_stmts(b, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
        push_str(sb, "      )\n")
        push_str(sb, "      (br 0)\n    ))\n")
        WAT_BRK = ob
        WAT_CONT = oc
        WAT_BRK_DB = odb
        WAT_CONT_DB = odc
        s = nx
      }
      Stmt::If(c, th, el, nx) => {
        push_str(sb, "    (if (i32.wrap_i64 ")
        emit_wat_expr(c, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
        push_str(sb, ") (then\n")
        emit_wat_stmts(th, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
        push_str(sb, "    ) (else\n")
        emit_wat_stmts(el, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
        push_str(sb, "    ))\n")
        s = nx
      }
      Stmt::Match(scrut, arms_head, nx) => {
        ## value-yielding when this match is the fn's TAIL statement (tail_value) and last (nx==0) —
        ## each arm returns its braced tail expr; else a side-effect match.
        vy := tail_value and nx == 0
        sn := expr_var_name(scrut)
        agg := agg_global_base(decls, src, sn.s, sn.n, a)
        etype0 := base_enum_type(params_head, fn_head, src, sn.s, sn.n, a, decls)
        ## GENERICS (§8): a `match v` where `v : T` is an enum PARAM in a mono instance — resolve the
        ## instance enum type (T → E) so the comptime-variant unroll has a concrete enum. Only kicks in
        ## when the raw annotation didn't already name an enum (byte-identical for a non-generic match).
        esub := wat_param_enum_span(params_head, src, sn.s, sn.n, a, decls)
        mut etype := etype0
        if etype.n == 0 { etype = esub }
        spidx := param_find(params_head, src, sn.s, sn.n, a)
        isloc := is_toplevel_local(fn_head, sn.s, sn.n, src, a)
        ## `match s[i]` on an enum `Slice(E)` PARAM: the by-reference element address (block.word0 data ptr +
        ## i*stride*8) is placed in the MATCH scratch local (index pcount+nloc+1); the match then reads disc +
        ## payload through it (emit_wat_stmt_match keys off a base local). Bounds vs word1 via the sc scratch.
        mut idxmatch := false
        if ex_is_index(scrut) {
          ibn := expr_var_name(ex_index_base(scrut))
          ipidx := param_find(params_head, src, ibn.s, ibn.n, a)
          ees := wat_slice_param_enum_span(params_head, src, ibn.s, ibn.n, decls)
          if ipidx >= 0 and ees.n != 0 {
            idxmatch = true
            stride := wat_slice_param_agg_stride(params_head, src, ibn.s, ibn.n, a, decls)
            nloc := count_locals(fn_head, src, a, decls)
            sc := pcount + nloc
            msc := pcount + nloc + 1
            push_str(sb, "    (local.set ") ; push_int(sb, msc) ; push_str(sb, " (i64.add (i64.load ")
            emit_wat_addr(sb, ipidx, 0)
            push_str(sb, ") (i64.mul ")
            if WAT_CHK {
              push_str(sb, "(block (result i64) (local.set ") ; push_int(sb, sc) ; push_str(sb, " ")
              emit_wat_expr(ex_index_idx(scrut), sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
              push_str(sb, ") (if (i64.ge_u (local.get ") ; push_int(sb, sc) ; push_str(sb, ") (i64.load ")
              emit_wat_addr(sb, ipidx, 8)
              push_str(sb, ")) (then (unreachable))) (local.get ") ; push_int(sb, sc) ; push_str(sb, "))")
            } else {
              emit_wat_expr(ex_index_idx(scrut), sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            }
            push_str(sb, " (i64.const ") ; push_int(sb, stride * 8) ; push_str(sb, "))))\n")
            emit_wat_stmt_match(arms_head, ees.s, ees.n, msc, fn_head, vy, sb, a, src, params_head, pcount, decls)
          }
        }
        if (not idxmatch) and agg >= 0 {
          gtype := global_enum_type(decls, src, sn.s, sn.n, a)
          if gtype.n != 0 { emit_wat_stmt_match(arms_head, gtype.s, gtype.n, 0 - (agg + 1), fn_head, vy, sb, a, src, params_head, pcount, decls) }
          else { push_str(sb, "    (unreachable) (; non-enum agg global match ;)\n") }
        } else if (not idxmatch) and sn.n != 0 and etype.n != 0 and (spidx >= 0 or isloc) {
          mut sidx := spidx
          if spidx < 0 { sidx = name_local_index(fn_head, src, sn.s, sn.n, pcount, a, decls) }
          emit_wat_stmt_match(arms_head, etype.s, etype.n, sidx, fn_head, vy, sb, a, src, params_head, pcount, decls)
        } else if not idxmatch {
          mut scalar_shape := true
          mut scalar_arm := arms_head
          while scalar_arm != 0 {
            sam := deref(arm_p(scalar_arm))
            if sam.wild != 1 and (sam.wild != 0 or sam.vs != 0 or sam.vl != 0) { scalar_shape = false }
            scalar_arm = sam.next
          }
          if scalar_shape {
            ## Scalar statement match: park the value in the first per-function scratch local so arm
            ## comparisons survive body emission. The scratch is reused by nested bodies only after the
            ## outer comparison has selected an arm.
            nloc := count_locals(fn_head, src, a, decls)
            sidx := pcount + nloc
            push_str(sb, "    (local.set ") ; push_int(sb, sidx) ; push_str(sb, " ")
            emit_wat_expr(scrut, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
            push_str(sb, ")\n")
            emit_wat_scalar_stmt_match(arms_head, sidx, fn_head, vy, sb, a, src, params_head, pcount, decls)
          } else {
            push_str(sb, "    (unreachable) (; unsupported non-scalar statement match ;)\n")
          }
        }
        s = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        ## RANGE `for i in lo..hi { … }`: `i` is a WASM local (name_local_index). i := lo; `(block (loop …))`
        ## exits (br_if 1) when i >= hi (SIGNED, x86 parity via setl); body; i += 1; `(br 0)` back-edge.
        if unchecked bitcast(usize, fhi) == 0 {
          ## ITERABLE `for x in <arr/slice-view> { … }`: `x` binds each ELEMENT. `x` is a WASM local
          ## (name_local_index); a hidden index rides the NEXT local (var-slot+1 — the local scan reserves
          ## TWO for an iterable For). Bound: an INLINE scalar/float array (base @ its local, static count)
          ## or a scalar slice VIEW (word0 = data ptr, word1 = runtime len, in its bump region; element at
          ## ptr+i*8). Element word copied BY VALUE (a float rides its bits). Anything else traps loud.
          idF := wat_next_label()
          obF := WAT_BRK
          ocF := WAT_CONT
          odbF := WAT_BRK_DB
          odcF := WAT_CONT_DB
          WAT_BRK = idF
          WAT_CONT = idF
          ## DEFER: the body's entry depth — `break`/`continue` inside it replay down to here.
          WAT_BRK_DB = WAT_DEF_N
          WAT_CONT_DB = WAT_DEF_N
          bn := expr_var_name(flo)
          varidx := name_local_index(fn_head, src, fns, fnl, pcount, a, decls)
          ididx := varidx + 1
          mut isslice := false
          if bn.n != 0 { if is_slice_local(fn_head, src, bn.s, bn.n, a) { isslice = true } }
          mut isarr := false
          if (not isslice) and bn.n != 0 { if is_array_local(fn_head, src, bn.s, bn.n, a) { isarr = true } }
          ## `for x in s` over a scalar `Slice(E)` PARAM: identical to a VIEW (the param local holds the block
          ## base; word0 = ptr, word1 = len). Base local from `param_find` (the param IS a WASM local).
          pidxF := param_find(params_head, src, bn.s, bn.n, a)
          mut isparamslice := false
          if (not isslice) and (not isarr) and pidxF >= 0 { if wat_slice_param_scalar(params_head, src, bn.s, bn.n, a, decls) { isparamslice = true } }
          ## AGGREGATE (struct-element) iteration over an ARRAY local or a slice VIEW of one: the loop var
          ## holds `&elem[i]` = dataptr + i*stride*8 (an ADDRESS, not a loaded word); `p.field` reads through
          ## it as a struct pointer (localok). No per-element copy — WASM aggregates are by-reference. Data
          ## pointer: ARRAY = the local (region base); VIEW = word0 of its region. Count: ARRAY = static nel;
          ## VIEW = word1.
          mut estrideF := 1
          if isarr { estrideF = array_local_stride(fn_head, src, bn.s, bn.n, a, decls) }
          if isslice { estrideF = array_local_stride(fn_head, src, bn.s, bn.n, a, decls) }
          ## a struct/enum-element `Slice(E)` PARAM base: in WASM it has the SAME shape as a VIEW (the param
          ## local holds the block base; word0 = data ptr, word1 = count), so it shares the VIEW emit with
          ## bidx = the param's local. estrideF from the param annotation.
          mut isaggparam := false
          if (not isslice) and (not isarr) and pidxF >= 0 { pstr := wat_slice_param_agg_stride(params_head, src, bn.s, bn.n, a, decls) ; if pstr > 1 { isaggparam = true ; estrideF = pstr } }
          mut isaggarr := false
          if isarr and estrideF > 1 { isaggarr = true }
          mut isaggview := false
          if isslice and estrideF > 1 { isaggview = true }
          if isaggarr or isaggview or isaggparam {
            mut bidx := pidxF
            if isaggarr or isaggview { bidx = name_local_index(fn_head, src, bn.s, bn.n, pcount, a, decls) }
            push_str(sb, "    (local.set ") ; push_int(sb, ididx) ; push_str(sb, " (i64.const 0))\n")
            push_str(sb, "    (block $brk") ; push_int(sb, idF) ; push_str(sb, " (loop $lp") ; push_int(sb, idF) ; push_str(sb, "\n")
            push_str(sb, "      (br_if 1 (i64.ge_s (local.get ") ; push_int(sb, ididx) ; push_str(sb, ") ")
            if isaggarr { push_str(sb, "(i64.const ") ; push_int(sb, i64(array_local_nel(fn_head, src, bn.s, bn.n, a))) ; push_str(sb, ")") }
            if isaggview or isaggparam { push_str(sb, "(i64.load ") ; emit_wat_addr(sb, bidx, 8) ; push_str(sb, ")") }
            push_str(sb, "))\n")
            ## p = dataptr + i*(estride*8)
            push_str(sb, "      (local.set ") ; push_int(sb, varidx) ; push_str(sb, " (i64.add ")
            if isaggarr { push_str(sb, "(local.get ") ; push_int(sb, bidx) ; push_str(sb, ")") }
            if isaggview or isaggparam { push_str(sb, "(i64.load ") ; emit_wat_addr(sb, bidx, 0) ; push_str(sb, ")") }
            push_str(sb, " (i64.mul (local.get ") ; push_int(sb, ididx) ; push_str(sb, ") (i64.const ") ; push_int(sb, estrideF * 8) ; push_str(sb, "))))\n")
            push_str(sb, "      (block $cont") ; push_int(sb, idF) ; push_str(sb, "\n")
            emit_wat_stmts(fb, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
            push_str(sb, "      )\n")
            push_str(sb, "      (local.set ") ; push_int(sb, ididx) ; push_str(sb, " (i64.add (local.get ") ; push_int(sb, ididx) ; push_str(sb, ") (i64.const 1)))\n")
            push_str(sb, "      (br 0)\n    ))\n")
          } else if isslice or isarr or isparamslice {
            mut bidx := pidxF
            if isslice or isarr { bidx = name_local_index(fn_head, src, bn.s, bn.n, pcount, a, decls) }
            push_str(sb, "    (local.set ") ; push_int(sb, ididx) ; push_str(sb, " (i64.const 0))\n")
            push_str(sb, "    (block $brk") ; push_int(sb, idF) ; push_str(sb, " (loop $lp") ; push_int(sb, idF) ; push_str(sb, "\n")
            push_str(sb, "      (br_if 1 (i64.ge_s (local.get ") ; push_int(sb, ididx) ; push_str(sb, ") ")
            if isslice or isparamslice { push_str(sb, "(i64.load ") ; emit_wat_addr(sb, bidx, 8) ; push_str(sb, ")") }
            else { push_str(sb, "(i64.const ") ; push_int(sb, i64(array_local_nel(fn_head, src, bn.s, bn.n, a))) ; push_str(sb, ")") }
            push_str(sb, "))\n")
            push_str(sb, "      (local.set ") ; push_int(sb, varidx) ; push_str(sb, " (i64.load (i32.wrap_i64 (i64.add ")
            if isslice or isparamslice { push_str(sb, "(i64.load ") ; emit_wat_addr(sb, bidx, 0) ; push_str(sb, ")") }
            else { push_str(sb, "(local.get ") ; push_int(sb, bidx) ; push_str(sb, ")") }
            push_str(sb, " (i64.mul (local.get ") ; push_int(sb, ididx) ; push_str(sb, ") (i64.const 8))))))\n")
            push_str(sb, "      (block $cont") ; push_int(sb, idF) ; push_str(sb, "\n")
            emit_wat_stmts(fb, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
            push_str(sb, "      )\n")
            push_str(sb, "      (local.set ") ; push_int(sb, ididx) ; push_str(sb, " (i64.add (local.get ") ; push_int(sb, ididx) ; push_str(sb, ") (i64.const 1)))\n")
            push_str(sb, "      (br 0)\n    ))\n")
          } else {
            push_str(sb, "    (unreachable) (; unsupported for-in-iterable ;)\n")
          }
          WAT_BRK = obF
          WAT_CONT = ocF
          WAT_BRK_DB = odbF
          WAT_CONT_DB = odcF
        } else {
          idx := name_local_index(fn_head, src, fns, fnl, pcount, a, decls)
          id := wat_next_label()
          ob := WAT_BRK
          oc := WAT_CONT
          odbR := WAT_BRK_DB
          odcR := WAT_CONT_DB
          WAT_BRK = id
          WAT_CONT = id
          ## DEFER: the body's entry depth — `break`/`continue` inside it replay down to here.
          WAT_BRK_DB = WAT_DEF_N
          WAT_CONT_DB = WAT_DEF_N
          push_str(sb, "    (local.set ") ; push_int(sb, idx) ; push_str(sb, " ")
          emit_wat_expr(flo, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, ")\n")
          push_str(sb, "    (block $brk") ; push_int(sb, id) ; push_str(sb, " (loop $lp") ; push_int(sb, id) ; push_str(sb, "\n")
          push_str(sb, "      (br_if 1 (i64.ge_s (local.get ") ; push_int(sb, idx) ; push_str(sb, ") ")
          emit_wat_expr(fhi, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
          push_str(sb, "))\n")
          ## `continue` target: exit this inner block → fall through to the increment below.
          push_str(sb, "      (block $cont") ; push_int(sb, id) ; push_str(sb, "\n")
          emit_wat_stmts(fb, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
          push_str(sb, "      )\n")
          push_str(sb, "      (local.set ") ; push_int(sb, idx) ; push_str(sb, " (i64.add (local.get ") ; push_int(sb, idx) ; push_str(sb, ") (i64.const 1)))\n")
          push_str(sb, "      (br 0)\n    ))\n")
          WAT_BRK = ob
          WAT_CONT = oc
          WAT_BRK_DB = odbR
          WAT_CONT_DB = odcR
        }
        s = nx
      }
      ## Infinite `loop { body }`: `(block $brk (loop $lp (block $cont <body>) (br 0)))`. `continue` exits
      ## `$cont` → falls to the `(br 0)` back-edge (re-iterate); `break` exits `$brk`.
      Stmt::Loop(lb, lnx) => {
        id := wat_next_label()
        ob := WAT_BRK
        oc := WAT_CONT
        odbL := WAT_BRK_DB
        odcL := WAT_CONT_DB
        WAT_BRK = id
        WAT_CONT = id
        ## DEFER: the body's entry depth — `break`/`continue` inside it replay down to here.
        WAT_BRK_DB = WAT_DEF_N
        WAT_CONT_DB = WAT_DEF_N
        push_str(sb, "    (block $brk") ; push_int(sb, id) ; push_str(sb, " (loop $lp") ; push_int(sb, id) ; push_str(sb, "\n")
        push_str(sb, "      (block $cont") ; push_int(sb, id) ; push_str(sb, "\n")
        emit_wat_stmts(lb, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
        push_str(sb, "      )\n")
        push_str(sb, "      (br 0)\n    ))\n")
        WAT_BRK = ob
        WAT_CONT = oc
        WAT_BRK_DB = odbL
        WAT_CONT_DB = odcL
        s = lnx
      }
      ## `break`: the WAT backend targets only the NEAREST loop (WAT_BRK) — a LABELED `break name`
      ## (`bd != 0`) or a loop-EXPRESSION `break <expr>` (`bv != 0`, §7.2) is not modelled, so fail-loud
      ## with `(unreachable)` rather than silently branch to the wrong loop / drop the value.
      Stmt::Break(bv, bd, bnx) => {
        if bd != 0 or unchecked bitcast(usize, bv) != 0 { push_str(sb, "    (unreachable)\n") }
        else {
          ## DEFER (§9.3): leaving the loop body runs the cleanups registered INSIDE it (down to the
          ## body's entry depth WAT_BRK_DB), LIFO, before the branch. Replay only — the fall-through
          ## path out of the same body still owes them, so nothing is popped here.
          if WAT_DEF_N > WAT_BRK_DB { wat_defer_drain(WAT_DEF_N, WAT_BRK_DB, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
          push_str(sb, "    (br $brk") ; push_int(sb, WAT_BRK) ; push_str(sb, ")\n")
        }
        s = bnx
      }
      Stmt::Continue(cd, cnx) => {
        if cd != 0 { push_str(sb, "    (unreachable)\n") }
        else {
          ## DEFER (§9.3): `continue` ends THIS ITERATION of the body — its cleanups run per iteration.
          if WAT_DEF_N > WAT_CONT_DB { wat_defer_drain(WAT_DEF_N, WAT_CONT_DB, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base) }
          push_str(sb, "    (br $cont") ; push_int(sb, WAT_CONT) ; push_str(sb, ")\n")
        }
        s = cnx
      }
      ## `unchecked { body }` (Grammar §130 statement form): lower the body with checked verification OFF,
      ## then restore. Mirrors the `Expr::Unchecked` toggle + x86 lower.
      Stmt::Unchecked(ub, unx) => {
        ov := WAT_CHK
        WAT_CHK = false
        emit_wat_stmts(ub, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
        WAT_CHK = ov
        s = unx
      }
      ## `comptime if <cond> { then } else { else }` — fold the condition and emit ONLY the taken branch's
      ## statements INLINE (arch/verify predicates; no runtime `(if …)`, the condition is erased). Conforms
      ## to the x86 lower: `target.arch == Arch.x86_64` folds TRUE. The taken branch inherits THIS CompIf's
      ## `nested` and is tail-valued only when the CompIf is itself the tail (`tail_value and nx == 0`),
      ## mirroring the x86 `cx.tail = ov_tail and nx == 0`. An unfoldable condition (a `match typeinfo(T)`
      ## — needs the mono context the wat path lacks) emits a fail-loud `(unreachable)` (never silent).
      Stmt::CompIf(cc, th, el, nx) => {
        cv := wat_comp_cond_fold(cc, src)
        if cv == 1 { emit_wat_stmts(th, fn_head, nested, tail_value and nx == 0, sb, a, src, params_head, pcount, decls, bind_head, bind_base) }
        if cv == 0 { emit_wat_stmts(el, fn_head, nested, tail_value and nx == 0, sb, a, src, params_head, pcount, decls, bind_head, bind_base) }
        if cv < 0 { push_str(sb, "    (unreachable) (; comptime-if: unfoldable condition (needs mono context) ;)\n") }
        s = nx
      }
      ## `comptime for i in lo .. hi { body }` — UNROLL at emit time: for each constant k in [lo, hi), set
      ## the loop var's WASM local to k then emit the body (no runtime loop; the control flow is erased).
      ## Bounds are compile-time integer constants (wat_comp_range_bound: literal / module const). Mirrors
      ## the x86 lower's CompForRange numeric unroll. A null hi (the §7.1 pack form) is unsupported here.
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => {
        if unchecked bitcast(usize, rhi) == 0 { push_str(sb, "    (unreachable) (; comptime-for pack unroll unsupported ;)\n") }
        else {
          vidx := name_local_index(fn_head, src, rvs, rvl, pcount, a, decls)
          if vidx < 0 { push_str(sb, "    (unreachable) (; comptime-for loop var unresolved ;)\n") }
          else {
            lo := wat_comp_range_bound(rlo, decls, src)
            hi := wat_comp_range_bound(rhi, decls, src)
            if hi - lo > 100000 { push_str(sb, "    (unreachable) (; comptime-for range exceeds the unroll budget ;)\n") }
            else {
              mut k := lo
              while k < hi {
                push_str(sb, "    (local.set ") ; push_int(sb, vidx) ; push_str(sb, " (i64.const ") ; push_int(sb, k) ; push_str(sb, "))\n")
                emit_wat_stmts(rb, fn_head, true, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
                k = k + 1
              }
            }
          }
        }
        s = nx
      }
      ## `comptime match typeinfo(T) { <Kind>(_) => …, _ => … }` (§8 mono) — fold on T's KIND inside a
      ## mono INSTANCE (WAT_SUB active) and emit ONLY the matching arm's statements (or the `_` arm). An
      ## inner `comptime match <scalar-kind>` keys off the SAME instance type (its scrutinee is ignored).
      ## Outside an instance it is a fail-loud `(unreachable)` (never silent). Mirrors emit_a64_stmts.
      Stmt::CompMatch(cmsc, cmah, cmnx) => {
        if WAT_SUB_ITL == 0 { push_str(sb, "    (unreachable) (; comptime-match: needs mono context ;)\n") }
        else {
          kind := ct_type_kind(WAT_SUB_ITS, WAT_SUB_ITL, decls, src)
          nkind := ct_scalar_num_kind(WAT_SUB_ITS, WAT_SUB_ITL, src)
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
            emit_wat_stmts(cam2.body_stmts, fn_head, nested, tail_value and cmnx == 0, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
          }
        }
        s = cmnx
      }
      ## `comptime for f in typeinfo(T).fields { body }` (§8 field-derive core) — UNROLL over the concrete
      ## target struct's fields (from the explicit typeinfo argument, or a mono substitution): for each field, bind the comptime loop
      ## context (WAT_CF_* = loop-var name / field name / field type) then emit the body once. Inside,
      ## `v.(f)` (Expr::CompField) resolves to a field READ and `f.type` (a type-arg) to the field type.
      ## Only for a STRUCT target (cisvar 1 = `.variants`, the match-arm unroll's job; tuple/array/
      ## unresolved target stays fail-loud). Saved/restored (single-level). Mirrors emit_a64_stmts.
      Stmt::CompFor(cvs, cvl, cisvar, cbody, cnx) => {
        mut cfdone := false
        mut cts := WAT_SUB_ITS
        mut ctl := WAT_SUB_ITL
        cia := compfor_iter_arg(src, cvs, cvl)
        if cia.n != 0 {
          cts = cia.s
          ctl = cia.n
          if WAT_SUB_GPL != 0 and streq(src, cts, ctl, WAT_SUB_GPS, WAT_SUB_GPL) { cts = WAT_SUB_ITS ; ctl = WAT_SUB_ITL }
          else if WAT_SUB_GPL2 != 0 and streq(src, cts, ctl, WAT_SUB_GPS2, WAT_SUB_GPL2) { cts = WAT_SUB_ITS2 ; ctl = WAT_SUB_ITL2 }
          else if WAT_SUB_GPL3 != 0 and streq(src, cts, ctl, WAT_SUB_GPS3, WAT_SUB_GPL3) { cts = WAT_SUB_ITS3 ; ctl = WAT_SUB_ITL3 }
        }
        if ctl != 0 and cisvar == 0 {
          cbn := base_type_name(src, cts, ctl)
          csdi := struct_decl_of(decls, src, cbn.s, cbn.n)
          if csdi >= 0 {
            csd := deref(decl_get(decls, usize(csdi)))
            ov_vs := WAT_CF_VAR_S ; ov_vl := WAT_CF_VAR_L
            ov_fs := WAT_CF_FLD_S ; ov_fl := WAT_CF_FLD_L
            ov_ts := WAT_CF_TY_S ; ov_tl := WAT_CF_TY_L
            mut cfd := csd.fields_head
            while cfd != 0 {
              cfdd := deref(fld_p(cfd))
              WAT_CF_VAR_S = cvs ; WAT_CF_VAR_L = cvl
              WAT_CF_FLD_S = cfdd.ns ; WAT_CF_FLD_L = cfdd.nl
              WAT_CF_TY_S = cfdd.ts ; WAT_CF_TY_L = cfdd.tl
              emit_wat_stmts(cbody, fn_head, nested, false, sb, a, src, params_head, pcount, decls, bind_head, bind_base)
              cfd = cfdd.next
            }
            WAT_CF_VAR_S = ov_vs ; WAT_CF_VAR_L = ov_vl
            WAT_CF_FLD_S = ov_fs ; WAT_CF_FLD_L = ov_fl
            WAT_CF_TY_S = ov_ts ; WAT_CF_TY_L = ov_tl
            cfdone = true
          }
        }
        if not cfdone { push_str(sb, "    (unreachable) (; comptime-for fields: needs a struct mono instance ;)\n") }
        s = cnx
      }
      _ => { push_str(sb, "    (unreachable) (; unsupported stmt ;)\n") ; s = 0 }
    }
  }
  ## DEFER (§9.3): the scope's FALL-THROUGH exit — replay the cleanups registered in THIS list, LIFO,
  ## and pop them (they are no longer live past the block). The fn-body list is drained by emit_wat_body
  ## instead, so its cleanups can run AFTER the tail expression is evaluated.
  if nested and WAT_DEF_N > dscope {
    wat_defer_drain(WAT_DEF_N, dscope, sb, a, src, params_head, pcount, fn_head, decls, bind_head, bind_base)
    WAT_DEF_N = dscope
  }
}

## Emit a fn body: declare one `(local i64)` per DISTINCT top-level `:=` name that is NOT a global,
## emit the statements, and — for a value-returning fn with no explicit top-level `return` — leave the
## tail expression on the stack as the `(result i64)`. A void fn emits no tail.
emit_wat_body := fn(head : ptr(mut Stmt), tail : ptr(Expr), void : bool, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), params_head : ptr(mut Param), pcount : i64, decls : ptr(rt::Vec)) {
  ## WAT branch labels are local to one function. Reset both the allocator and the saved nearest-loop
  ## targets so a prior function (or a prior generic instance) cannot leak stale IDs.
  WAT_LABEL_NEXT = 0
  WAT_BRK = 0
  WAT_CONT = 0
  WAT_BRK_DB = 0
  WAT_CONT_DB = 0
  WAT_DEF_STOP = 0
  ## pass 1: declare one (local i64) per distinct non-global local name in the WHOLE fn tree
  ## (top-level + nested scopes). count_locals and name_local_index share local_slot_scan, so the
  ## slot each Var resolves to is exactly its pre-order declaration index.
  ## stash params + decls so the element-struct resolver (local_struct_type) recognizes a slice PARAM base.
  WAT_PARAMS = unchecked bitcast(usize, params_head)
  WAT_DECLS = unchecked bitcast(usize, decls)
  nloc := count_locals(head, src, a, decls)
  mut li := 0
  ## declare THREE extra `(local i64)` past the named locals: the reusable SCRATCH slot (index
  ## `pcount + nloc`) a `verify.checked` array-index bounds guard uses to hold the index while
  ## range-tested; a SECOND scratch (`+ 1`) that `match s[i]` on an enum slice PARAM and an aggregate
  ## element WRITE use to hold an element's by-reference base address; and a THIRD (`+ 2`) holding the
  ## SOURCE base of a whole-aggregate word copy (WASM has no scratch register); and a FOURTH (`+ 3`)
  ## parking a `return`/tail value across a DEFER drain (§9.3 — the cleanups run between evaluating the
  ## value and returning it). Unused ones are harmless.
  while li < nloc + 4 {
    push_str(sb, "    (local i64)\n")
    li += 1
  }
  ## does the body have an explicit top-level return?
  mut has_ret := false
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Return(rv, nx) => { has_ret = true ; s = nx }
      Stmt::Assign(ns, nl, v, nx) => { s = nx }
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
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::Match(msc, mah, mnx) => { s = mnx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
  ## DEFER (§9.3): the pending-cleanup stack is PER FUNCTION — start empty (a previous fn's leftovers
  ## would replay into this one) and clear the overflow flag with it.
  WAT_DEF_N = 0
  WAT_DEF_OVF = false
  ## emit the statements; a TAIL Stmt::Match (nx==0 in the top-level list) is emitted value-yielding
  ## by emit_wat_stmts via the tail_value flag (each arm returns its tail expr).
  emit_wat_stmts(head, head, false, (not void) and (not has_ret), sb, a, src, params_head, pcount, decls, 0, 0)
  if (not void) and (not has_ret) {
    if ex_is_no_tail(tail) {
      ## no tail EXPRESSION: either a tail value-match just returned in every arm (this caps the
      ## all-arms-return if-chain so the fn's i64 end is unreachable), or the value truly is not
      ## delivered (a multi-stmt value arm) → either way `(unreachable)` is correct.
      push_str(sb, "    (unreachable) (; fn value from tail statement (value-match) or undelivered ;)\n")
    } else if WAT_DEF_N > 0 {
      ## DEFER: the fn-body scope's fall-through, with the TAIL as the value — evaluate the tail into
      ## the defer scratch local, replay the whole stack LIFO, then leave the parked value as the result.
      dscb := wat_defer_scratch(pcount, head, src, a, decls)
      push_str(sb, "    (local.set ")
      push_int(sb, dscb)
      push_str(sb, " ")
      emit_wat_expr(tail, sb, a, src, params_head, pcount, head, decls, 0, 0)
      push_str(sb, ")\n")
      wat_defer_drain(WAT_DEF_N, 0, sb, a, src, params_head, pcount, head, decls, 0, 0)
      push_str(sb, "    (local.get ")
      push_int(sb, dscb)
      push_str(sb, ")\n")
      WAT_DEF_N = 0
    } else {
      push_str(sb, "    ")
      emit_wat_expr(tail, sb, a, src, params_head, pcount, head, decls, 0, 0)
      push_str(sb, "\n")
    }
  } else if WAT_DEF_N > 0 {
    ## a VOID fn (or one whose paths all `return`): the body-scope cleanups still run at the
    ## fall-through end. For the all-return shape this is dead code after a `(return …)` — harmless.
    wat_defer_drain(WAT_DEF_N, 0, sb, a, src, params_head, pcount, head, decls, 0, 0)
    WAT_DEF_N = 0
  }
}

## Emit `(param i64)` for each value parameter of a fn (in declaration order).
emit_wat_params := fn(params_head : ptr(mut Param), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  mut p := params_head
  while p != 0 {
    pm := deref(param_p(p))
    ## a comptime `T : type` param occupies no WASM slot (its type-arg is erased at the call site).
    if str_at((src + pm.ts), pm.tl) == "type" {} else { push_str(sb, " (param i64)") }
    p = pm.next
  }
}

## Walk a fn's statement list (recursing into while/if bodies + match arms) and emit a `(data …)`
## segment for every `print`/`println` string literal encountered — so its bytes are in linear memory
## before fd_write references them. Must cover the SAME statement shapes emit_wat_stmts prints from.
## Emit a `(data …)` segment for each aggregate GLOBAL's CONSTANT init at its fixed offset: an enum
## global is {variant_index, payload…} padded to 1+enum_max_arity words; a struct global is its
## fields — each word an i64 little-endian. Non-constant fields fall back to 0 (rare for a global).
## Write an aggregate INITIALIZER's linear-memory cells RECURSIVELY as little-endian i64 bytes (the
## WASM twin of lower::emit_global_data_cells / a64's emit_a64_global_cells): a struct-lit writes its
## field args in order (a nested struct field flattens), an array-lit its elements, an enum-lit
## {variant_index, payload…} padded to 1+enum_max_arity, and any scalar leaf its i64 value. Keeps the
## byte image consistent with agg_value_words (the offset allocator) so nested/array globals lay out right.
emit_wat_agg_cells := fn(e : ptr(Expr), in out sb : rt::StrBuf, decls : ptr(rt::Vec), src : ptr(u8), a : rt::Arena) {
  sn := expr_struct_name(e)
  en := expr_enum_name(e)
  if sn.n != 0 {
    mut g := ex_struct_lit_args(e)
    while g != 0 { ga := deref(arg_p(g)) ; emit_wat_agg_cells(ga.e, sb, decls, src, a) ; g = ga.next }
  } else if ex_is_array_lit(e) {
    mut ag := ex_array_lit_ehead(e)
    while ag != 0 { aga := deref(arg_p(ag)) ; emit_wat_agg_cells(aga.e, sb, decls, src, a) ; ag = aga.next }
  } else if en.n != 0 {
    evar := expr_enum_variant(e)
    emit_i64_le(sb, variant_index(decls, src, en.s, en.n, evar.s, evar.n, a))
    maxp := enum_max_arity(decls, src, en.s, en.n, a)
    mut g := ex_enum_lit_args(e)
    mut w := 0
    while g != 0 { ga := deref(arg_p(g)) ; emit_i64_le(sb, ex_value_init(ga.e)) ; w += 1 ; g = ga.next }
    while w < maxp { emit_i64_le(sb, 0) ; w = w + 1 }
  } else {
    emit_i64_le(sb, ex_value_init(e))
  }
}
emit_agg_global_data := fn(decls : ptr(rt::Vec), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  cnt := rt::vec_len(deref(decls))
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 and value_is_agg(d.value) {
      base := agg_global_base(decls, src, d.name_start, d.name_len, a)
      push_str(sb, "  (data (i32.const ")
      push_int(sb, base)
      push_str(sb, ") \"")
      emit_wat_agg_cells(d.value, sb, decls, src, a)
      push_str(sb, "\")\n")
    }
  }
}

emit_wat_str_data_stmts := fn(head : ptr(mut Stmt), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::ExprStmt(e, nx) => { pi := print_call_info(e, src, a) ; if pi.ok { emit_str_data_seg(sb, src, pi.ss, pi.sl, pi.lbl, pi.nl, a) } ; s = nx }
      Stmt::While(c, b, nx) => { emit_wat_str_data_stmts(b, sb, src, a) ; s = nx }
      Stmt::If(c, th, el, nx) => { emit_wat_str_data_stmts(th, sb, src, a) ; emit_wat_str_data_stmts(el, sb, src, a) ; s = nx }
      Stmt::Match(sc, ah, nx) => { mut arm := ah ; while arm != 0 { am := deref(arm_p(arm)) ; emit_wat_str_data_stmts(am.body_stmts, sb, src, a) ; arm = am.next } ; s = nx }
      Stmt::Assign(ns, nl, v, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { s = nx }
      Stmt::FieldPathAssign(fpp, fpv, fpnx) => { s = fpnx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { emit_wat_str_data_stmts(fb, sb, src, a) ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { emit_wat_str_data_stmts(rb, sb, src, a) ; s = nx }
      Stmt::CompIf(cc, th, el, nx) => { emit_wat_str_data_stmts(th, sb, src, a) ; emit_wat_str_data_stmts(el, sb, src, a) ; s = nx }
      Stmt::Loop(lb, lnx) => { emit_wat_str_data_stmts(lb, sb, src, a) ; s = lnx }
      Stmt::Unchecked(ub, unx) => { emit_wat_str_data_stmts(ub, sb, src, a) ; s = unx }
      Stmt::Break(_bv, _bd, bnx) => { s = bnx }
      Stmt::Continue(_cd, cnx) => { s = cnx }
      ## `xs[i].f = v` declares no local but MUST NOT terminate the scan (a `_ => s = 0` would
      ## hide every local declared after it → a wrong WASM slot / a missed type. See first_assign_handle.
      Stmt::IndexFieldAssign(ifb, ifi, iffs, iffl, ifv, ifnx) => { s = ifnx }
      _ => { s = 0 }
    }
  }
}

## Emit a complete WASI WAT module for the program `decls`: module-level scalar globals become WASM
## globals; every fn (kind 1) a WASM func; `_start` calls `$main` and hands the (wrapped) result to
## `proc_exit`.
## Emit ONE function definition `$name … (result i64)? body`, plus its `@export` alias. A GENERIC fn
## (a `type` param) emits NO standalone body — it is emitted only as instances: in INSTANCE mode
## (WAT_SUB_ITL set by emit_wat_program's mono pass) with a SINGLE LEADING type-param, drop that
## type-param, set the substitution NAME (WAT_SUB_GPS/GPL, read by the comptime folds), and emit
## `$<fn>__<tag>`. `ephead` = the effective (value) param list. An `@extern` fn is a bodyless import
## (emitted elsewhere) → skip.
emit_wat_fn := fn(d : Decl, in out sb : rt::StrBuf, a : rt::Arena, src : ptr(u8), decls : ptr(rt::Vec)) {
  is_ext := wat_extern_symbol(src, d.name_start, d.name_len).n != 0
  if is_ext { return }
  isgen := wat_fn_is_generic(d.params_head, src, a)
  WAT_SUB_GPS = 0
  WAT_SUB_GPL = 0
  WAT_SUB_GPS2 = 0
  WAT_SUB_GPL2 = 0
  WAT_SUB_GPS3 = 0
  WAT_SUB_GPL3 = 0
  mut ephead := d.params_head
  if isgen {
    ## a generic fn: emit nothing unless we are emitting a concrete instance for it
    if WAT_SUB_ITL == 0 { return }
    cnt := decl_tparam_count(d, src)
    lead := decl_leading_tparam_run(d, src)
    ## SUPPORTED: a SINGLE type-param (any position) OR a LEADING RUN of 2..3 (cnt == lead). Else skip →
    ## the call falls to its own fail-loud trap, never a bad instance.
    gok := cnt == 1 or (cnt == lead and cnt >= 2 and cnt <= 3)
    if not gok { return }
    if cnt == 1 and lead == 0 {
      ## cluster 2: SINGLE NON-LEADING type-param (`gf(s, T, k)`) — KEEP the full param list; the type-arg
      ## is erased at the call site and emit_wat_params / count_params / param_find SKIP the type-param
      ## slot, so the value params keep their positions. Mirrors a64 a64_tp_skip.
      tpn := wat_tparam_name(d, src)
      WAT_SUB_GPS = tpn.s
      WAT_SUB_GPL = tpn.n
      ephead = d.params_head
    } else {
      ## cluster 1 (lead==1) / cluster 3 (lead 2..3): DROP the leading RUN; substitute each type-param NAME
      ## → its instance type (GPS/GPL, GPS2/GPL2, GPS3/GPL3). `ephead` = the first value param after the run.
      mut pp := d.params_head
      mut li := i64(0)
      while li < lead {
        pm := deref(param_p(pp))
        if li == 0 { WAT_SUB_GPS = pm.ns ; WAT_SUB_GPL = pm.nl }
        if li == 1 { WAT_SUB_GPS2 = pm.ns ; WAT_SUB_GPL2 = pm.nl }
        if li == 2 { WAT_SUB_GPS3 = pm.ns ; WAT_SUB_GPL3 = pm.nl }
        pp = pm.next
        li = li + 1
      }
      ephead = pp
    }
  }
  push_str(sb, "  (func $")
  fname := str_at((src + d.name_start), d.name_len)
  if d.name_len == 0 { wat_emit_lambda_label(sb, src, d.mod_start, d.mod_len, d.name_start) } else { push_str(sb, fname) }
  ## instance TYPE TAG `$<fn>__<tag>` — INLINE (a helper taking `in out StrBuf` is mis-passed by the
  ## frozen seed → segfault; the a64 landmine). Bare name verbatim; TUPLE `(T0,…)` → `Tuple_<t0>_…`;
  ## ARRAY `[E; N]` → `Array_<elem>_<N>` (`(`/`)`/`[`/`;`/space/comma are invalid WAT `$id` chars). MUST
  ## match the call-site tag exactly.
  if isgen {
    push_str(sb, "__")
    dtas := WAT_SUB_ITS
    dtan := WAT_SUB_ITL
    if str_at((src + dtas), 1) == "[" {
      push_str(sb, "Array_")
      mut cadep := 0
      mut casemi := dtas + 1
      mut cap := dtas + 1
      mut cago := true
      while cago and cap < dtas + dtan {
        cac := str_at((src + cap), 1)
        if cac == "(" or cac == "[" { cadep = cadep + 1 }
        else if (cac == ")" or cac == "]") and cadep > 0 { cadep = cadep - 1 }
        else if cac == ";" and cadep == 0 { casemi = cap ; cago = false }
        cap = cap + 1
      }
      mut caes := dtas + 1
      while caes < casemi and str_at((src + caes), 1) == " " { caes = caes + 1 }
      mut caet := casemi
      while caet > caes and str_at((src + caet - 1), 1) == " " { caet = caet - 1 }
      push_str(sb, str_at((src + caes), caet - caes))
      push_str(sb, "_")
      mut calp := casemi + 1
      while calp < dtas + dtan {
        calc := str_at((src + calp), 1)
        if calc != " " and calc != "]" { push_str(sb, calc) }
        calp = calp + 1
      }
    } else if str_at((src + dtas), 1) == "(" {
      push_str(sb, "Tuple")
      mut cdepth := 0
      mut ccs := dtas + 1
      mut cp := dtas + 1
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
      push_str(sb, str_at((src + dtas), dtan))
    }
    ## MULTI type-param: append `__<2nd>` / `__<3rd>` (bare scalar names; the resolver rejects array/tuple
    ## for the 2nd/3rd). MUST match the call-site tag so the `(call $<fn>__<t0>__<t1>__<t2>)` resolves.
    if WAT_SUB_ITL2 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + WAT_SUB_ITS2), WAT_SUB_ITL2)) }
    if WAT_SUB_ITL3 != 0 { push_str(sb, "__") ; push_str(sb, str_at((src + WAT_SUB_ITS3), WAT_SUB_ITL3)) }
  }
  emit_wat_params(ephead, sb, src, a)
  void := d.ret_tl == 0
  if not void { push_str(sb, " (result i64)") }
  push_str(sb, "\n")
  pc := count_params(ephead, src, a)
  WAT_RET_TUPLE = 0
  if wat_fn_returns_tuple(d, src) {
    tw := wat_tuple_words(src, d.ret_ts, d.ret_tl)
    if tw >= 1 and tw <= 7 { WAT_RET_TUPLE = tw }
  }
  emit_wat_body(d.body_stmts, d.value, void, sb, a, src, ephead, pc, decls)
  WAT_RET_TUPLE = 0
  push_str(sb, "  )\n")
  ## `@export("name")` — a generic base fn is never emitted standalone, so only a concrete fn exports.
  if not isgen {
    xn := wat_export_name(src, d.name_start, d.name_len)
    if xn.n != 0 {
      push_str(sb, "  (export \"")
      push_str(sb, str_at((src + xn.s), xn.n))
      push_str(sb, "\" (func $")
      push_str(sb, fname)
      push_str(sb, "))\n")
    }
  }
}

pub emit_wat_program := fn(decls : ptr(rt::Vec), in out sb : rt::StrBuf, src : ptr(u8), a : rt::Arena) {
  ## COMPTIME `when`-GUARD gating (Comptime §7.1/§9; CT-5) — BEFORE any import/global/func emission,
  ## exactly where x86 `lower::emit_program` runs it. A decl gated on an arch that is not this target is
  ## neutered to an as-if-absent no-op here, so an arch-gated raw-GAS `asm(…)` body never reaches WAT.
  ## It runs FIRST so `agg_globals_end` / `agg_global_base` / `emit_agg_global_data` all lay out linear
  ## memory over the SAME (already-gated) decl set and cannot disagree about an offset.
  apply_when_guards(decls, src, wat_target_arch())
  push_str(sb, "(module\n")
  push_str(sb, "  (import \"wasi_snapshot_preview1\" \"proc_exit\" (func $proc_exit (param i32)))\n")
  push_str(sb, "  (import \"wasi_snapshot_preview1\" \"fd_write\" (func $fd_write (param i32 i32 i32 i32) (result i32)))\n")
  ## `@extern("sym")` FFI imports (Modules §7.2) — MUST precede every definition (the WASM
  ## abbreviated-import rule). A bodyless `name := @extern("sym") fn(…)` becomes an imported func
  ## `$name` from module "env", so a `(call $name)` routes to the host symbol; its (absent) body is
  ## then skipped below. The internal-linking pairing the native backends allow (an `@extern` to an
  ## `@export`ed sibling) does not link under WASM — imports come from the host — so such a program
  ## is a structurally-valid module that only RUNS when the host provides "env"."sym".
  ecnt := rt::vec_len(deref(decls))
  for i in 0..ecnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 {
      esym := wat_extern_symbol(src, d.name_start, d.name_len)
      if esym.n != 0 {
        push_str(sb, "  (import \"env\" \"")
        push_str(sb, str_at((src + esym.s), esym.n))
        push_str(sb, "\" (func $")
        push_str(sb, str_at((src + d.name_start), d.name_len))
        emit_wat_params(d.params_head, sb, src, a)
        if d.ret_tl != 0 { push_str(sb, " (result i64)") }
        push_str(sb, "))\n")
      }
    }
  }
  ## WASI command modules require an exported linear memory named "memory".
  push_str(sb, "  (memory (export \"memory\") 1)\n")
  ## `$__sp` — a bump pointer into linear memory for struct-local storage (starts at 1024, leaving low
  ## memory free; no reclamation, so struct construction in a hot loop can exhaust the page — a tracer
  ## limit). Emitted unconditionally; a struct-free program simply never touches it.
  push_str(sb, "  (global $__sp (mut i64) (i64.const ")
  push_int(sb, agg_globals_end(decls, src, a))
  push_str(sb, "))\n")
  emit_agg_global_data(decls, sb, src, a)
  ## `$__tmp` holds the base address of an aggregate constructed in EXPRESSION position (so the
  ## constructing block can yield it). Non-nested only — a construction inside another's field
  ## clobbers it (rare; deferred).
  push_str(sb, "  (global $__tmp (mut i64) (i64.const 0))\n")
  ## Scratch cells for the checked integer OVERFLOW guard (I11 / CG-8): $__ova/$__ovb capture the two
  ## operands off the value stack, $__ovo the result — used only in the straight-line guard sequence
  ## (nesting-safe, see the `Expr::Bin` overflow path).
  push_str(sb, "  (global $__ova (mut i64) (i64.const 0))\n")
  push_str(sb, "  (global $__ovb (mut i64) (i64.const 0))\n")
  push_str(sb, "  (global $__ovo (mut i64) (i64.const 0))\n")
  ## `$__istart` — start offset of the last integer rendered by $__itoa; the newline byte lives at
  ## offset 12 (a data segment). fd_write's iovec uses scratch [0,8), nwritten [8,12).
  push_str(sb, "  (global $__istart (mut i32) (i32.const 0))\n")
  push_str(sb, "  (data (i32.const 12) \"\\0a\")\n")
  ## $__itoa: render an unsigned i64 as decimal, digits written BACKWARD into [.., 40); records the
  ## start in $__istart and returns the byte length. (Signed/negative is a follow-up.)
  push_str(sb, "  (func $__itoa (param $n i64) (result i32) (local $p i32)\n")
  push_str(sb, "    (local.set $p (i32.const 40))\n")
  push_str(sb, "    (block (loop\n")
  push_str(sb, "      (local.set $p (i32.sub (local.get $p) (i32.const 1)))\n")
  push_str(sb, "      (i32.store8 (local.get $p) (i32.wrap_i64 (i64.add (i64.const 48) (i64.rem_u (local.get $n) (i64.const 10)))))\n")
  push_str(sb, "      (local.set $n (i64.div_u (local.get $n) (i64.const 10)))\n")
  push_str(sb, "      (br_if 0 (i64.ne (local.get $n) (i64.const 0)))\n")
  push_str(sb, "    ))\n")
  push_str(sb, "    (global.set $__istart (local.get $p))\n")
  push_str(sb, "    (i32.sub (i32.const 40) (local.get $p)))\n")
  cnt := rt::vec_len(deref(decls))
  ## module-level scalar globals (mut or const → all emitted mutable; a const one is simply never set)
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    ## `name_len != 0`: a `when`-guarded decl that folded FALSE for this target was neutered to a
    ## NAMELESS kind-0 no-op (`lower_layout::apply_when_guards`); a nameless `(global $ …)` is not valid WAT.
    ## As-if-absent means no cell. The three aggregate-global walkers carry the same guard so the
    ## linear-memory offsets they compute stay in agreement.
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 and ex_value_is_scalar(d.value) {
      push_str(sb, "  (global $")
      gname := str_at((src + d.name_start), d.name_len)
      push_str(sb, gname)
      push_str(sb, " (mut i64) (i64.const ")
      push_int(sb, ex_value_init(d.value))
      push_str(sb, "))\n")
    }
  }
  ## float module globals — a `(mut f64)` cell initialised from the SOURCE float literal. Reads
  ## reinterpret f64→i64 (the bits ride the integer value model); writes reinterpret i64→f64. Only
  ## emitted when the init text is recoverable; otherwise the read/write sites TRAP (unmodelled).
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.name_len != 0 and wat_is_float_global(decls, src, d.name_start, d.name_len) {
      init := wat_float_global_init(src, d.name_start, d.name_len)
      if init.n != 0 {
        push_str(sb, "  (global $")
        push_str(sb, str_at((src + d.name_start), d.name_len))
        push_str(sb, " (mut f64) (f64.const ")
        push_str(sb, str_at((src + init.s), init.n))
        push_str(sb, "))\n")
      }
    }
  }
  ## data segments for every print/println string literal (must precede the funcs that reference them)
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 { emit_wat_str_data_stmts(d.body_stmts, sb, src, a) }
  }
  ## GENERICS (§8 mono): instances are RECORDED DURING EMIT — each generic CALL site (emit_wat_expr)
  ## resolves its type-arg and appends via wat_inst_add (dedup) into the fixed WAT_INST_* arrays. The
  ## base loop below emits the non-generic fns (seeding the set + skipping generic bases); then the mono
  ## loop emits each instance with the substitution active, re-reading WAT_INST_N so transitively
  ## discovered instances are emitted too.
  WAT_INST_N = 0
  for i in 0..cnt {
    d := deref(decl_get(decls, i))
    if d.kind == 1 { emit_wat_fn(d, sb, a, src, decls) }
  }
  ## emit one monomorphized instance per RECORDED (generic-fn, type) pair. WAT_SUB_ITS/ITL select the
  ## instance; emit_wat_fn drops the leading type-param and mangles `$<fn>__<tag>`.
  mut mi := 0
  while mi < WAT_INST_N {
    mgi := WAT_INST_GI[mi]
    WAT_SUB_ITS = WAT_INST_TS[mi]
    WAT_SUB_ITL = WAT_INST_TL[mi]
    WAT_SUB_ITS2 = WAT_INST_TS2[mi]
    WAT_SUB_ITL2 = WAT_INST_TL2[mi]
    WAT_SUB_ITS3 = WAT_INST_TS3[mi]
    WAT_SUB_ITL3 = WAT_INST_TL3[mi]
    gdi := deref(decl_get(decls, mgi))
    emit_wat_fn(gdi, sb, a, src, decls)
    WAT_SUB_ITS = 0
    WAT_SUB_ITL = 0
    WAT_SUB_ITS2 = 0
    WAT_SUB_ITL2 = 0
    WAT_SUB_ITS3 = 0
    WAT_SUB_ITL3 = 0
    mi = mi + 1
  }
  push_str(sb, "  (func $_start\n")
  push_str(sb, "    (call $proc_exit (i32.wrap_i64 (call $main))))\n")
  push_str(sb, "  (export \"_start\" (func $_start))\n")
  push_str(sb, ")\n")
}
