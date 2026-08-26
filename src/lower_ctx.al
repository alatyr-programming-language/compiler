## selfhost::lower_ctx — shared foundation for the x86_64 lower back end (decomposition).
##
## `lower.al` (>13.5k lines) is being split into cohesive cluster submodules. The clusters share a small
## foundation — the arena node-pointer helper + the SlotEntry vector type (and, later, the `LCtx` ctx
## struct + the core span accessors). Those live HERE, in a base module both `lower.al` and its cluster
## submodules import, so a submodule never has to import `lower.al` back (which would form a module cycle).
##
## First extraction (probe): `SVec` (a plain struct) + `node_ptr` (the GENERIC arena accessor) — the latter
## verifies cross-module generic monomorphization works before the larger cluster moves. Second: the small
## expression-span accessors (`CSpan` + `var_name_span`/`asm_str_span`/`asm_digit`) the raw-asm cluster needs.
(Arg, Decl, Expr) := ast
arg_p := ast::arg_p
## Compatibility surface for lower_asm: the shared table lives only in lower_layout.
pub asm_digit := fn(c : str) -> i64 { lower_layout::dec_digit_val(c) }

## One name→frame-slot vector's raw storage (base offset + len + cap + arena). Used by the lower's
## SlotEntry / Inst vectors.
pub SVec := struct { base : usize, len : usize, cap : usize, arena : ptr(mut rt::Arena) }

## A typed pointer to arena node `h` (the arena base + the handle offset). The lean replacement for the
## generic `get`/`Handle` allocator surface — a bitcast accessor over the arena base (mirrors
## `parser::node_ptr`). Generic over the node type `T`.
pub node_ptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}

## A typed pointer to an AST declaration at absolute handle `h`, plus the indexed declaration lookup
## used by every backend. Keeping these beside `node_ptr` gives all emitters one implementation of the
## arena/vector handle recovery; the backend modules remain adapters for target-specific emission.
pub decl_at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }
pub decl_get := fn(decls : ptr(rt::Vec), i : usize) -> ptr(Decl) {
  hh := rt::vec_get(deref(decls), i)
  return decl_at(Decl, hh)
}

## Equality of two source-relative spans. The source pointer arithmetic is intentional (I11/CG-8):
## callers pass parser/lower offsets, including rebased comptime-synthesized spans.
pub streq := fn(src : ptr(u8), a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool {
  str_at((src + a_s), a_n) == str_at((src + b_s), b_n)
}

## Architecture-neutral Expr accessors shared by the scalar backends. Keep the scalar returns separate:
## the frozen seed has a known mis-lowering scar for newly introduced struct return types.
pub expr_is_struct_lit := fn(v : ptr(Expr)) -> bool {
  mut r := false
  match deref(v) { Expr::StructLit(ss, sn, nf, ah) => { r = true } _ => {} }
  r
}
pub expr_struct_lit_ns := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::StructLit(ss, sn, nf, ah) => { r = ss } _ => {} }
  r
}
pub expr_struct_lit_nl := fn(v : ptr(Expr)) -> usize {
  mut r := 0
  match deref(v) { Expr::StructLit(ss, sn, nf, ah) => { r = sn } _ => {} }
  r
}
pub expr_field_base := fn(e : ptr(Expr)) -> ptr(Expr) {
  mut r : ptr(Expr) = unchecked bitcast(ptr(Expr), 0)
  match deref(e) { Expr::Field(fb, ffs, ffl) => { r = fb } _ => {} }
  r
}
pub expr_field_name_s := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::Field(fb, ffs, ffl) => { r = ffs } _ => {} }
  r
}
pub expr_field_name_l := fn(e : ptr(Expr)) -> usize {
  mut r := 0
  match deref(e) { Expr::Field(fb, ffs, ffl) => { r = ffl } _ => {} }
  r
}

## The name span of a `Var` (0/0 if not a `Var`); the inner content span of a `StrLit` (`asm_str_span`);
## a single decimal digit's value (`asm_digit`) — small standalone accessors shared by the raw-asm cluster.
pub CSpan := struct { s : usize, n : usize }
pub var_name_span := fn(e : ptr(Expr)) -> CSpan {
  mut res := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::Var(s, n) => { res = CSpan(s = s, n = n) }
    _ => {}
  }
  res
}
pub asm_str_span := fn(e : ptr(Expr)) -> CSpan {
  mut res := CSpan(s = 0, n = 0)
  match deref(e) {
    Expr::StrLit(s, n, lbl) => { res = CSpan(s = s, n = n) }
    _ => {}
  }
  res
}
## The integer value of an `Expr::Num`/`BoolLit` (else 0); the i-th arg expr of an arg list (0-based,
## null Expr ptr if absent) — small shared accessors (moved from lower.al, §6 decomposition).
pub num_lit_value := fn(e : ptr(Expr)) -> i64 {
  mut res := 0
  match deref(e) {
    Expr::Num(v, s, n) => { res = i64(v) }
    Expr::BoolLit(v) => { res = i64(v) }
    _ => {}
  }
  res
}
pub arg_expr_at := fn(head : ptr(mut Arg), i : usize, a : rt::Arena) -> ptr(Expr) {
  mut g := head
  mut k := 0
  mut res := 0
  while g != 0 {
    ga := deref(arg_p(g))
    if k == i { res = unchecked bitcast(usize, ga.e) }
    k += 1
    g = ga.next
  }
  unchecked bitcast(ptr(Expr), res)
}

## The per-function lowering context (frame slots, return convention, control-flow targets, generic
## type-params, scratch bases). Shared by every emit fn (93 take `ptr(LCtx)`); lives in the base module so
## cluster submodules (lower_asm, …) can take a `ptr(LCtx)` param without importing lower.al (§6).
pub LCtx := struct {
  src : ptr(u8),
  slots : ptr(SVec),
  decls : ptr(rt::Vec),
  ## the AST arena as a POINTER (not a `rt::Arena` value field — see the PCtx note); read sites
  ## use `deref(cx.mar)` where a `rt::Arena` value is wanted.
  mar : ptr(mut rt::Arena),
  epi : usize,
  ret_enum : bool,
  ## true when the enclosing fn returns a 2-WORD STRUCT — delivered via the same two-register
  ## convention as an enum (field 0 in %rax, field 1 in %rdx). Larger structs need sret (deferred).
  ret_struct : bool,
  ## true when the enclosing fn returns a TUPLE `(…)` — delivered via the same register convention as
  ## a small struct (component k → %rax/%rdx/%rcx/…). Disjoint from ret_struct (a tuple has no Decl).
  ret_tuple : bool,
  ## true when the enclosing fn returns a `str` — delivered ptr/%rax, len/%rdx (the str dual of ret_struct).
  ret_str : bool,
  ## true when the enclosing fn returns an `f64`/`f32` — the return value is delivered in %xmm0 (the
  ## SSE return register): after the scalar value lands in %rax, `movq %rax, %xmm0` before the epilogue.
  ret_float : bool,
  ## the enclosing fn's RETURN-type name span (the struct's span when `ret_struct`). Lets a
  ## `return deref(p)` deref-COPY the right number of pointee words even when `p` is a
  ## ptr-to-struct LOCAL (slot ek 0, born of a `bitcast(ptr(S), …)` whose target type the parser
  ## discards) and so carries no struct span of its own — the return type is the source of truth.
  ret_ss : usize,
  ret_sl : usize,
  tslot : i64,
  ## STRING tier — the base frame-slot offset of a pool of 2-word str-MATERIALIZATION temp
  ## blocks (a str LITERAL passed as a call argument has no frame home, so it is materialized
  ## into one of these blocks and passed BY REFERENCE — see `emit_arg` / `str_arg_tmp_off`).
  ## The pool holds `max_str_lit_args` blocks (the max str-literal-argument count of any single
  ## call in the function body, from `scan_str_arg_temps`); -1 = no str-literal arg in this fn.
  str_tmp : i64,
  ## AGGREGATE-ARG tier — the base frame-slot offset of a temp block for materializing a
  ## struct/enum CONSTRUCTOR passed as a call argument (a non-place ctor has no frame home, so it
  ## is built into this block and passed BY REFERENCE, like a str literal). Sized to the widest
  ## single struct/enum-ctor argument in the function body (`scan_agg_arg_words`); -1 = none.
  ## (Handles one ctor arg per call — the common pass shape; reused across calls.)
  agg_tmp : i64,
  ## INLINE tier — the base frame-slot offset of the scratch region for expanding an `@inline` call at
  ## the call site (§3.1/§3.5): the callee's params (and later body-locals) are bound into this region,
  ## aliased by name for the body emit, then the body is emitted inline. Sized to the widest `@inline`
  ## callee used in the body (`inline_frame_need_*`). -1 when this fn makes NO `@inline` call (so a
  ## call-free fn reserves nothing → its frame is byte-identical → the mechanism is fixpoint-neutral).
  inl_tmp : i64,
  ## MODULE tier: the source span of the enclosing function's module — so an unqualified
  ## (same-module) `Call` mangles its callee to `<this-module>__callee` (a qualified `mod::f`
  ## call carries its own head and ignores this).
  mod_s : usize, mod_l : usize,
  ## CONTROL FLOW: the done-label of the nearest enclosing `loop`/`while`, the `break` target.
  ## -1 = no enclosing loop. The `while`/`loop` emitters save the old value, set their own
  ## done-label, emit the body, then restore — so a `break` inside a nested loop exits the
  ## innermost one and an outer-loop `break` after the inner loop still targets the outer.
  brk : i64,
  ## CONTROL FLOW: the CONTINUE target of the nearest enclosing loop, the `continue` jump label.
  ## -1 = no enclosing loop. Set by each loop emitter (a `while`'s guard, a `loop`'s top, a `for`'s
  ## increment label) and saved/restored around the body exactly like `brk`, so a nested-loop
  ## `continue` re-iterates the innermost loop.
  cont : i64,
  ## GENERICS: the enclosing fn's type-parameter name span (`gp_s`/`gp_l`, 0/0 if not generic)
  ## and, when emitting a monomorphization INSTANCE, the concrete type-argument span
  ## (`it_s`/`it_l`, 0/0 otherwise). `size(T)` resolves T to the concrete type via these (so the
  ## element STRIDE of a generic container `Vec(T)` is the real `size` of the instance's type).
  gp_s : usize, gp_l : usize,
  it_s : usize, it_l : usize,
  ## SECOND type-parameter (2-type-param generic `map(T, U, …)`): name span + instance concrete type.
  gp2_s : usize, gp2_l : usize,
  it2_s : usize, it2_l : usize,
  ## THIRD type-parameter (3-type-param generic `Result::map(T, E, U, …)`): name span + instance type.
  gp3_s : usize, gp3_l : usize,
  it3_s : usize, it3_l : usize,
  ## COMPTIME-FOR binding: while unrolling `comptime for <var> in typeinfo(T).fields`, `cf_var` is
  ## the loop-var name, `cf_fld` the CURRENT member's name, `cf_ty` its type. `v.(<var>)` (CompField)
  ## resolves to `Field(v, cf_fld)` and `<var>.type` (a generic type-arg) to `cf_ty`. cf_var_l == 0
  ## when not unrolling (single-level — nested comptime-for is not used by the stdlib).
  ## While unrolling a TUPLE `comptime for c in typeinfo(T).components` (T a tuple `(…)` — detected
  ## by `cx.it` starting `(`), `cf_fld_s` carries the CURRENT component INDEX and `cf_fld_l` is 0 (a
  ## tuple member has no name), so `v.(c)` resolves to a component word read at `-(cf_fld_s*8)(ptr)`
  ## and `c.type` to `cf_ty`. Reusing `cf_fld` (vs a new field) keeps LCtx's word count unchanged —
  ## growing the largest struct enlarges every function's aggregate scratch, and a bigger frame
  ## perturbs a latent uninitialised-stack read elsewhere in the compiler (flips unrelated checks).
  cf_var_s : usize, cf_var_l : usize,
  cf_fld_s : usize, cf_fld_l : usize,
  cf_ty_s : usize, cf_ty_l : usize,
  ## COMPTIME enum-arm PAYLOAD binding: inside a `match` arm, `cf_pay` names the (single) payload
  ## binding and `cf_pay_ty` its type. A generic call `g(cf_pay)` (derive's `hash(p)` — an IMPLICIT
  ## type-arg: the payload's own type) then routes to `g__<cf_pay_ty>` with the payload as the value
  ## arg (no erasure). cf_pay_l == 0 outside a single-binding arm body.
  cf_pay_s : usize, cf_pay_l : usize,
  cf_pay_ty_s : usize, cf_pay_ty_l : usize,
  ## The current variant name while emitting a comptime-for-variant arm's body — a nested `T.(v)`
  ## comptime-variant PATTERN (`wild == 3`) inside the body resolves to this. 0/0 when not in one.
  cf_curvar_s : usize, cf_curvar_l : usize,
  ## The comptime-for-VARIANT loop-var NAME (`var` in `comptime for var in typeinfo(T).variants`),
  ## captured from the `wild==2` template arm before `expand_variant_arms` overwrites `vs/vl` with
  ## each variant's own name. During a variant-arm body a `<var>.name` read (`display`'s enum arm)
  ## resolves to the CURRENT variant name (`cf_curvar_*`); a `comptime match <var>.payload` folds on
  ## the current variant's arity. 0/0 outside a comptime-for-variant unroll.
  cf_vloop_s : usize, cf_vloop_l : usize,
  ## COMPTIME VARIADIC pack (Functions §7.1): while expanding a `fn(…, p : ...)` call, `pack_args` is the
  ## Arg-list handle of the first TRAILING (pack) argument (0 = empty pack / not in a variadic body). The
  ## body's `comptime for v in p` is a `CompForRange` with a NULL hi (pack mode); its unroll walks
  ## `pack_args`, binding `v` to each pack argument in turn.
  pack_args : usize,
  ## AGGREGATE-VALUE call-arg temp pool (Functions §4 ABI) — a bump allocator. `agg_next` is the next
  ## free slot (starts at the pool base = `agg_tmp`); each aggregate-value arg materialized by `emit_arg`
  ## takes a distinct `agg_w`-word slice and advances `agg_next`, so N such args in one call get N
  ## distinct blocks (no aliasing). `emit_call_args` save/restores `agg_next` around a call's args, so a
  ## nested call's args stack ABOVE the enclosing call's live args. `agg_end` is the pool limit; a bump
  ## past it aborts (a loud overflow, never a silent miscompile — §8).
  agg_next : i64, agg_end : i64, agg_w : i64,
  ## MIXED-KIND tuple component layout (§4). A tuple is stored at CUMULATIVE offsets, but the array
  ## read model uses a UNIFORM element type+stride (the FIRST component) — wrong when a later component
  ## has a different kind/width (e.g. `(u64, Pt)`, `t.1.x` misreads). `tcomps` is a side-table of
  ## per-component entries for MIXED tuple LOCALS, populated by a body walk in `emit_fn`, each encoded in
  ## a `SlotEntry`: `ns` = the tuple's base slot offset, `nl` = component INDEX, `sns`/`snl` = the
  ## component's struct/enum TYPE span (0/0 = scalar), `off` = its CUMULATIVE word offset, `eek` = kind
  ## (2 struct / 3 enum / 0 scalar). The `t.N` read consults it so element N uses its OWN type + offset.
  tcomps : ptr(SVec),
  ## TAIL-VALUE position: true while emitting a statement list whose LAST statement produces the
  ## fn's RETURN value — a value-returning fn whose body ends in a braced `match` (the lean parser
  ## has no expression-`match`, so `*_info`/`enum_lit_info`/… that `return` a struct via bare arms
  ## flow their value through here). Set once by `emit_fn`; a directly-tail `match`/`if` inherits it
  ## (its arms/branches are emitted with the same `cx`), so the arm's trailing `ExprStmt` delivers
  ## via `emit_return_value` instead of being discarded. Carried in the ctx (NOT an `emit_stmts`
  ## parameter) to preserve the documented 4-param arg-register budget.
  tail : bool,
  ## the decl index of the call currently being lowered (set by the `Expr::Call` arms right before
  ## `emit_call_args`, read back into a LOCAL at its top) — so `emit_call_args` knows the callee and
  ## can pass an out-scalar argument BY ADDRESS (`callee_out_scalar`). Carried in the ctx rather than
  ## as a 7th `emit_call_args` parameter: a 7th param would push the threaded `in out nl` counter
  ## PAST the argument registers, which the Stage-0 seed cannot lower (in-out scalars must be a
  ## register arg). -1 = unknown / not in a call.
  call_cidx : i64,
  ## NESTED-MATCH SCRATCH DEPTH: a `match` on a by-ref / call-result enum materializes the scrutinee
  ## into the frame scratch region at base `tslot`; a match NESTED inside such an arm's body must not
  ## clobber the outer scrutinee's words (whose payload the outer arm's binding still aliases). So the
  ## materialization base is `tslot + mdepth * swidth`: `mdepth` is bumped around each match arm body,
  ## `swidth` is one level's width (`1 + widest enum payload`). The scratch region is reserved for
  ## `max_match_depth` levels. mdepth == 0 at top level → byte-identical for single (un-nested) matches.
  mdepth : usize, swidth : usize,
  ## SRET (struct return >7 words — too wide for the %rax..%r11 register-return convention). When the
  ## enclosing fn is sret, the caller passes a HIDDEN result-pointer as arg 0 (%rdi) and the real
  ## params shift to %rsi..; `ret_sret` gates the prologue's %rdi-save + param shift and the return's
  ## write-through-pointer. `sret_slot` is the frame slot holding the saved result pointer (-1 = not
  ## sret). `sret_call` is the frame slot whose ADDRESS to pass as the hidden %rdi for the CALL being
  ## lowered right now (set by the caller-binding site before emit_call_dispatch; -1 = ordinary call).
  ret_sret : bool, sret_slot : i64, sret_call : i64,
  ## VERIFICATION MODE (Types §4.2, CT-11/I11): `true` = checked (the DEFAULT —
  ## overflow/underflow/div-by-zero guards present), `false` = inside an `unchecked` scope
  ## (guards comptime-absent, raw wrapping instruction). A SCOPED mode: every writer saves the
  ## old value, sets its own, emits the inner construct, then restores (`emit_gas`'s
  ## `Expr::Unchecked` arm, `emit_stmts`'s `Stmt::Unchecked` arm, `emit_strat_pair`,
  ## `emit_inline_binop`, the three `emit_require_agg_*`), so the mode is `true` again at every
  ## function-emission boundary. `comptime_cond_eval` reads it to fold `verify.checked`.
  ## Carried HERE (was the module global `VERIFY_CHK`) because it is per-function frame state
  ## read across eight prospective submodules. The original reason was harder than taste: a
  ## module-level global did not cross a module boundary AT ALL — a descendant naming one silently
  ## got a fresh uninitialised frame local, measured as `movq -8(%rbp), %rax` where a RIP-relative
  ## read of the real symbol was due, with no diagnostic. That defect is FIXED: a bare read from a
  ## nested module and a qualified `<mod>::G` both now emit `<mod>__G(%rip)` and return the declared
  ## value. So this is no longer a PROHIBITION — but the field is still the right form, because
  ## per-function state in a module global is a re-entrancy hazard independent of module scope, and
  ## `LCtx`'s constructors zero it by construction where `emit_fn` used to do it by hand.
  vchk : bool,
  ## DEFER LEDGER (Control Flow §9.3 / Memory §5.8) — the pending `defer` cleanup actions of the
  ## function being emitted, in REGISTRATION order: each `__defer(<expr>)` marker stores the inner
  ## expr handle in `defer_inner[j]`; each `__deferblk()` block marker stores the block-head `Stmt`
  ## handle there and sets `defer_blk[j]` (so the block's statements run together at that LIFO
  ## position). `defer_n` is the count. `defer_frame` is the per-BLOCK frame stack — each entry is
  ## the `defer_n` at that block's entry, i.e. its drain BOUNDARY — and `defer_sp` its depth.
  ## `defer_active` (does ANY statement of this fn, at any depth, carry a `defer` marker) gates
  ## EVERY frame push/drain/`loop_dframe` write, so a defer-free fn pays nothing and emits no frame
  ## gas. The body walk appends; block exits / early exits / the epilogue drain LIFO
  ## (`emit_defer_chain`). `src/`+`lib/` produce no marker → `defer_n` stays 0 and `defer_active` is
  ## false for every self-host fn → the TOOL-1 fixpoint is neutral.
  ##
  ## Carried HERE (was the module globals `EMIT_DEFER_INNER`/`_N`/`_BLK`/`_FRAME`/`_SP` +
  ## `DEFER_ACTIVE`) because it is per-function frame state written by the `fn`/`stmt`/`deferloop`
  ## bands and read by the `expr`/`stmt`/`value` bands — per-function state in a module global is a
  ## re-entrancy hazard, and it additionally could not be read across a module boundary at all when
  ## these fields were introduced (see `vchk` above). Reset per fn by construction: the three `LCtx`
  ## constructors zero the ledger, which is exactly what `emit_fn` used to do by hand, and the
  ## push/pop pairs are balanced so `defer_sp` is 0 at every function boundary either way.
  defer_active : bool,
  defer_n : usize, defer_sp : usize,
  defer_inner : [usize; 128], defer_blk : [usize; 128],
  defer_frame : [usize; 64],
  ## LOOP-TARGET STACK (Control Flow §7.1) — one frame per lexically-enclosing loop of the function
  ## being emitted, mirroring the parser's `P_LOOP_*` label stack so a `break`/`continue` DEPTH
  ## indexes the same frame. Each frame records the loop's done-label (`loop_brk`, the break target),
  ## its continue-label (`loop_cont`), and whether the loop is VALUE-BEARING (`loop_isexpr` — an
  ## `Expr::Loop`, so `break <expr>` leaves its value on the stack at the done-label). `loop_sp` is
  ## the live depth. A depth-0 `break`/`continue` with no value still uses `cx.brk`/`cx.cont`
  ## (byte-identical to the pre-label lowering); the stack is consulted only for a labeled
  ## (depth > 0) or value-bearing break. `loop_dframe` records each loop's body defer-frame boundary
  ## (parallel to `loop_brk`) so a `break`/`continue` drains the defer ledger up to the TARGET loop's
  ## boundary without a nested scan; it is written only under `defer_active`.
  ##
  ## Carried HERE (was the module globals `LOOP_SP`/`LOOP_BRK`/`LOOP_CONT`/`LOOP_ISEXPR`/
  ## `LOOP_DFRAME`) for the same reason as the defer ledger above: the stack is pushed by the
  ## `deferloop` band and read by the `expr` and `stmt` bands (see `vchk` above for why a module
  ## global is the wrong form for per-function state). The `loop_push`/`loop_pop`
  ## pairs are balanced at every call site, so `loop_sp` was already 0 at each function boundary and
  ## per-function initialisation here is equivalent to the globals' cross-function persistence.
  loop_sp : usize,
  loop_brk : [i64; 64], loop_cont : [i64; 64], loop_isexpr : [usize; 64],
  loop_dframe : [usize; 64],
  ## STOP sentinel for `emit_stmts`: when non-zero, `emit_stmts` halts BEFORE the statement at this
  ## handle. Zero (the default) = walk the whole `nx` chain, so every ordinary `emit_stmts` caller is
  ## unaffected. Two users, both scoped save/restore around a single `emit_stmts(…, cx, …)` on the SAME
  ## ctx: the IR general-barrier splice (`ir_splice_one_stmt`, which must emit exactly one statement
  ## without constructing a `Stmt` value — the self-host lower cannot) and `emit_defer_chain`'s
  ## block-defer arm (whose block's `nx` chain continues past its `__deferblkend` marker into the
  ## ENCLOSING list, so an un-rebounded walk would re-emit the rest of the function).
  ## Carried HERE (was the module global `IR_EMIT_STOP`) because the writers sit in the `ir` and
  ## `deferloop` bands and the reader in `stmt`: it is the one global that would otherwise keep
  ## `lower/ir.al` — the cleanest 1 956-line band in the file, with 62 globals nobody else touches —
  ## from being extractable.
  ir_stop : usize,
  ## FN-6 — the float-ARGUMENT mask of the INDIRECT call whose arguments are about to be lowered
  ## (0 = an ordinary named call / no float argument). It supplies the argument CLASSES the parser
  ## dropped when it kept only the bare `fn` token for a fn-value's type; without them an `f64`
  ## argument rode a GPR while the callee read %xmm. Set by each `call *%rax` site right before
  ## `emit_call_args`, which captures it into a local and CLEARS it so a nested argument-call does not
  ## inherit it — the exact one-shot hand-off convention `call_cidx` and `sret_call` above already
  ## use, and for the same reason: an extra `emit_call_args` parameter would push the threaded
  ## `in out nl` counter past the argument registers. Was the module global `IND_FN_FMASK`.
  ind_fn_fmask : usize,
}
