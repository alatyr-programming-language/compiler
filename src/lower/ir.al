## selfhost::lower::ir — the SCALAR-LEAF IR fast path: the shape PREDICATE that decides whether a
## function may bypass the text emitter, the IR builder (`ir_lower_*`), the barrier side-tables that let
## an unmodelled construct fall back to `emit_gas`/`emit_stmts` mid-body, and the renderer that turns the
## allocated IR back into GAS. 57 functions, one type (`IROperand`).
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. Every UNQUALIFIED name it does not import — `streq`,
## `decl_get`, `emit_gas`, `emit_stmts`, `emit_mangled_call`, `is_signed_expr`, the sixty-three `IR*`
## globals, and the `PCtx`/`SlotEntry` TYPES — binds `lower.al`'s OWN declaration through the ancestor
## chain (Modules §3 for values, P1-TYPE-ANCESTOR for types).
##
## State: ALL sixty-three `IR*` globals stay declared in `src/lower.al` and are read and written from
## here through the ancestor chain. That is not conservatism — `emit_fn_ir` (which stays in the parent,
## see below) resets nine of them per function (`IRV_N`, `IRV_NEXT`, `IRL_N`, `IRC_N`, `IRCA_TOP`,
## `IRBR_N`, `IRSB_N`, `IRGSB_N`, `IRP_NGBAR`), and §3 is one-way, so splitting the block by which
## counter the parent happens to touch would be arbitrary and fragile. Keeping the whole block in the
## parent costs nothing: a descendant's write emits `lower__IRV_N(%rip)`.
##
## `emit_fn_ir` — the IR-emit DRIVER — deliberately does NOT move. It calls `collect_slots`, which is
## already a CHILD (`src/lower/collect_slots.al`), and a bare call from one child to another is a
## SIBLING reach: Modules §3 gives it no legal spelling. Left in the parent, its call to
## `collect_slots` stays parent -> child, which §3 does sanction, and its calls into this band become
## parent -> child too, through the bare-name re-import below. That is the general rule this lane
## found: a band is movable only when nothing in it calls into an already-moved sibling.
##
## NOTE the import ORDER: a BARE module alias (`strbuf := rt`) followed by a listed projection is a
## parse error in the self-host parser unless a QUALIFIED alias (`x := m::y`) separates them.
strbuf := rt
arg_p := ast::arg_p
fld_p := ast::fld_p
param_p := ast::param_p
stmt_p := ast::stmt_p
local_type_span := ast::local_type_span
fn_is_naked := lower_asm::fn_is_naked
(Arg, Decl, Expr, Stmt) := ast
(push_str, push_int) := strbuf
(CSpan, LCtx, SVec, var_name_span) := lower_ctx
(base_type_name, is_packed, std_struct_has_byte_layout, struct_decl_of) := lower_layout

## An IR operand as (kind, value): kind 1=Imm, 2=Phys(reg id), 3=VReg(id), 5=Slot(frame disp). Two words.
IROperand := struct { k : usize, v : i64 }
## The vreg for a Var name (assign a fresh one on first sight — a stable per-fn identity).
pub ir_var_vreg := fn(cx : ptr(LCtx), s : usize, n : usize) -> usize {
  mut i := 0
  while i < IRV_N {
    if streq(cx.src, IRV_S[i], IRV_L[i], s, n) { return IRV_V[i] }
    i += 1
  }
  vr := IRV_NEXT
  IRV_NEXT = IRV_NEXT + 1
  IRV_S[IRV_N] = s
  IRV_L[IRV_N] = n
  IRV_V[IRV_N] = vr
  IRV_N = IRV_N + 1
  vr
}
ir_fresh_vreg := fn() -> usize { r := IRV_NEXT; IRV_NEXT = IRV_NEXT + 1; r }
ir_fresh_label := fn() -> usize { r := IRL_N; IRL_N = IRL_N + 1; r }

## SysV integer argument register id for parameter `i` (rdi rsi rdx rcx r8 r9).
pub ir_argreg_id := fn(i : usize) -> usize {
  if i == 0 { return 5 }
  if i == 1 { return 4 }
  if i == 2 { return 3 }
  if i == 3 { return 2 }
  if i == 4 { return 8 }
  9
}

## The `i`-th CALLEE-SAVED register id, in the fixed prologue save order (rbx, r12, r13, r14, r15). These
## are the registers the emitter must save/restore when the allocator parks a live-across-call value there.
pub ir_csreg_id := fn(i : usize) -> usize {
  if i == 0 { return 1 }    ## rbx
  if i == 1 { return 12 }   ## r12
  if i == 2 { return 13 }   ## r13
  if i == 3 { return 14 }   ## r14
  15                        ## r15
}

## Force an operand into a register (materialize an immediate into a fresh vreg) — `cmp`/`div`/the
## `dst` of an arithmetic op cannot take an immediate in operand-0 position.
ir_to_reg := fn(o : IROperand) -> IROperand {
  if o.k == 1 {
    t := ir_fresh_vreg()
    regalloc::ra_ir_emit(0, 3, i64(t), 1, o.v)   ## mov vreg t, $imm
    return IROperand(k = 3, v = i64(t))
  }
  o
}

## Lower a value-position expression to an operand (recursive). Fails loud on anything the predicate
## should have excluded (defence in depth — never a silent miscompile).
pub ir_lower_expr := fn(e : ptr(Expr), cx : ptr(LCtx), unch : bool) -> IROperand {
  match deref(e) {
    Expr::Num(v, s, n) => { IROperand(k = 1, v = v) }
    Expr::BoolLit(v) => { IROperand(k = 1, v = v) }
    Expr::Var(s, n) => { IROperand(k = 3, v = i64(ir_var_vreg(cx, s, n))) }
    Expr::Unchecked(inner) => { ir_lower_expr(inner, cx, true) }
    Expr::Bitcast(inner, _bcs, _bcl) => { ir_lower_expr(inner, cx, true) }
    Expr::Bin(op, l, r) => { ir_lower_bin(op, l, r, cx, unch) }
    Expr::Call(cs, cl, na, ah) => { ir_lower_call(cs, cl, na, ah, cx, unch) }
    ## a SCALAR field read of a by-ref struct param (predicate-validated) → a BARRIER: the whole `e` is
    ## emitted by the text `emit_gas` at render, so it takes the same path as the text-machine build.
    Expr::Field(fb, ffs, ffl) => { ir_lower_barrier(e, cx) }
    _ => { panic("selfhost: regalloc emit — unsupported value expr in scalar-leaf IR path"); IROperand(k = 1, v = 0) }
  }
}

## Is an integer conversion operand a leaf whose 64-bit word may be reused unchanged? Conversion lowering can
## wrap the source in `unchecked`/`bitcast`; peel those wrappers, but never admit a binary op, call, field, or
## index here. In particular `u64(a + b)` must remain text-lowered so a narrow checked `a + b` keeps its guard.
ir_u64_identity_arg := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Var(s, n) => { true }
    Expr::Num(v, s, n) => { true }
    Expr::BoolLit(v) => { true }
    Expr::Unchecked(inner) => { ir_u64_identity_arg(inner) }
    Expr::Bitcast(inner, _s, _n) => { ir_u64_identity_arg(inner) }
    _ => { false }
  }
}

## A target-native `usize` is the x86_64 alias of `u64`. Keep this follow-up narrower than the existing
## u64 leaf rule: only an already-proven native `u64(<scalar leaf>)` conversion may be peeled. This makes
## `usize(u64(x))` a word identity without admitting a direct index, a call, a binary/narrow operation, or
## a guessed u8-to-usize text shape whose fallback does not preserve the byte load.
ir_usize_identity_arg := fn(src : ptr(u8), e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => {
      if str_at((src + cs), cl) == "u64" and na == 1 {
        return ir_u64_identity_arg(deref(arg_p(ah)).e)
      }
      false
    }
    _ => { false }
  }
}

## Lower a BARRIERED value expression: record it, emit the FULL-CLOBBER barrier (op 14 — the text snippet
## may touch any register, so every live-across scalar vreg spills), then read the %rax-delivered result
## into a fresh vreg (the SAME staging as a `call` return). The result vreg is DEFINED right after the
## barrier, so its interval starts past the clobber — it can hold an ordinary register.
ir_lower_barrier := fn(e : ptr(Expr), cx : ptr(LCtx)) -> IROperand {
  id := IRBR_N
  if id >= 16 { panic("selfhost: regalloc emit — barrier side-table overflow (predicate too permissive)") }
  IRBR_E[id] = unchecked bitcast(usize, e)
  IRBR_N = IRBR_N + 1
  regalloc::ra_ir_emit(14, 4, i64(id), 0, 0)                    ## BARRIER: emit_gas(e) → %rax, clobbers all
  t := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(t), 2, 0)                      ## mov t, %rax
  IROperand(k = 3, v = i64(t))
}

## Lower a SCALAR CALL `f(a0, …, ak)` (k < 6, scalar args + scalar return) modelling the SysV convention.
## Args are lowered LEFT-TO-RIGHT to operands onto the arg stack (so a nested call resolves fully before
## an outer arg reg is touched), THEN each is moved into its physical argument register (rdi rsi rdx rcx
## r8 r9) as a PRE-COLORED write, THEN `call` (op 6 — the allocator clobbers every caller-saved reg so a
## value live across it lands in a callee-saved reg / spill, never corrupted), THEN the result is read out
## of %rax into a fresh vreg IMMEDIATELY (nothing the rewriter inserts between the call and this mov
## touches %rax — a spill store is a `movq` to a frame slot). The callee symbol is recorded in the call
## side-table and rendered via `emit_mangled_call`.
ir_lower_call := fn(cs : usize, cl : usize, na : usize, ah : ptr(mut Arg), cx : ptr(LCtx), unch : bool) -> IROperand {
  ## BIT SHIFT `shl`/`shr(v, n)` (OP-6): an operation-FN, not a real call (no `call` inst). The count `n`
  ## must sit in %cl (the sole variable-count shift register), so lower v→a fresh vreg `t`, lower n, move
  ## n into %rcx (a pre-colored write — the shift op marks %rcx BUSY so no live value parks there), then
  ## the shift RMW on `t`. `shl`→op 19 (shlq); `shr` picks op 21 (sarq, arithmetic) when the VALUE is
  ## signed else op 20 (shrq, logical) — the exact rule the text path uses. CHECKED (not `unchecked`): the
  ## over-width trap (count >= native width 64) is the same `cmpq $64,<cnt>; jb CONT; ud2; CONT:` guard the
  ## text path emits (emit_shift_width_guard), so a register-allocated shift never drops the I11 guard.
  cnm := str_at((cx.src + cs), cl)
  if cnm == "shl" or cnm == "shr" {
    a0 := deref(arg_p(ah)).e                        ## the value v
    a1 := deref(arg_p(deref(arg_p(ah)).next)).e     ## the count n
    vo := ir_lower_expr(a0, cx, unch)
    co := ir_lower_expr(a1, cx, unch)
    t := ir_fresh_vreg()
    regalloc::ra_ir_emit(0, 3, i64(t), vo.k, vo.v)          ## mov t, v
    regalloc::ra_ir_emit(0, 2, 2, co.k, co.v)               ## mov %rcx, n  (count → %cl)
    if not unch {
      cont := ir_fresh_label()
      regalloc::ra_ir_emit(4, 2, 2, 1, 64)                  ## cmp %rcx, $64  (flags: n - 64)
      regalloc::ra_ir_emit(9, 4, i64(cont), 1, 6)           ## jb CONT  (n < 64 → skip the trap)
      regalloc::ra_ir_emit(13, 0, 0, 0, 0)                  ## ud2      (over-width shift → fault)
      regalloc::ra_ir_emit(10, 4, i64(cont), 0, 0)          ## CONT:
    }
    mut sop := 19                                           ## shl → shlq
    if cnm == "shr" {
      if is_signed_expr(a0, cx) { sop = 21 } else { sop = 20 }   ## signed → sarq (21), else shrq (20)
    }
    regalloc::ra_ir_emit(sop, 3, i64(t), 0, 0)              ## <shl|shr|sar>q %cl, t
    return IROperand(k = 3, v = i64(t))
  }
  ## NATIVE INTEGER CONVERSION `u64(x)` (P3-RA-AGG follow-up): the scalar IR already represents every
  ## admitted integer as one 64-bit word. The Slice(u8) loop's dedicated `movzbq` defines x as the correct
  ## zero-extended value, so the native-width conversion is an identity and must not demote this codec-like
  ## loop to TEXT. Narrow conversions remain excluded: they need the width-specific instruction/guard path.
  if cnm == "u64" {
    if na != 1 { panic("selfhost: regalloc emit — u64 conversion arity mismatch") }
    if not ir_u64_identity_arg(deref(arg_p(ah)).e) { panic("selfhost: regalloc emit — u64 conversion requires a scalar leaf") }
    return ir_lower_expr(deref(arg_p(ah)).e, cx, unch)
  }
  ## TARGET-NATIVE ALIAS CONVERSION `usize(u64(x))` (P3-RA-AGG next seam): on x86_64 `usize` and `u64`
  ## occupy the same unsigned native word. The inner u64 identity has already proved that the operand is a
  ## scalar leaf; lowering the outer alias as the same operand cannot change bits, traps, or calls.
  if cnm == "usize" {
    if na != 1 { panic("selfhost: regalloc emit — usize conversion arity mismatch") }
    if not ir_usize_identity_arg(cx.src, deref(arg_p(ah)).e) { panic("selfhost: regalloc emit — usize conversion requires u64(scalar leaf)") }
    return ir_lower_expr(deref(arg_p(ah)).e, cx, unch)
  }
  base := IRCA_TOP
  ## 1) lower every arg to an operand onto the stack (nested calls complete + pop here).
  mut g := ah
  while g != 0 {
    ga := deref(arg_p(g))
    o := ir_lower_expr(ga.e, cx, unch)
    if IRCA_TOP >= 32 { panic("selfhost: regalloc emit — call-arg stack overflow (predicate too permissive)") }
    IRCA_K[IRCA_TOP] = o.k
    IRCA_V[IRCA_TOP] = o.v
    IRCA_TOP = IRCA_TOP + 1
    g = ga.next
  }
  ## 2) move each arg into its SysV integer argument register (pre-colored Phys, in order).
  mut j := 0
  while j < na {
    regalloc::ra_ir_emit(0, 2, i64(ir_argreg_id(j)), IRCA_K[base + j], IRCA_V[base + j])
    j = j + 1
  }
  IRCA_TOP = base
  ## 3) record the callee symbol + emit the `call`.
  id := IRC_N
  if id >= 32 { panic("selfhost: regalloc emit — call side-table overflow (predicate too permissive)") }
  IRC_CS[id] = cs
  IRC_CL[id] = cl
  IRC_MS[id] = cx.mod_s
  IRC_ML[id] = cx.mod_l
  IRC_N = IRC_N + 1
  regalloc::ra_ir_emit(6, 4, i64(id), 0, 0)                    ## call <mangled>
  ## 4) read the SysV integer return (%rax) into a fresh vreg RIGHT AFTER the call.
  t := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(t), 2, 0)                     ## mov t, %rax
  IROperand(k = 3, v = i64(t))
}

## Emit the inline overflow guard `jcc CONT; ud2; CONT:` after an arithmetic op that has set FLAGS —
## exactly modelling the text path's `jno 1f; ud2; 1:` (signed) / `jnc 1f; ud2; 1:` (unsigned). The op +
## this guard are an ATOMIC unit: the only thing the allocator may schedule between the op and the `jcc`
## is a spill STORE of the op's result (a `movq`, which does NOT touch OF/CF), so the guard reads the op's
## flags intact. The `ud2` (op 13) is a dead end (no successor); the `CONT:` label is a block boundary the
## allocator already splits on, and the op's result stays live across it because a later use references it.
ir_emit_ovf_guard := fn(signed : bool) {
  cont := ir_fresh_label()
  mut cc := 11                                                  ## unsigned: jnc (no carry)
  if signed { cc = 10 }                                         ## signed: jno (no overflow)
  regalloc::ra_ir_emit(9, 4, i64(cont), 1, i64(cc))            ## jno/jnc CONT  (skip the trap on no-overflow)
  regalloc::ra_ir_emit(13, 0, 0, 0, 0)                         ## ud2           (overflow → fault)
  regalloc::ra_ir_emit(10, 4, i64(cont), 0, 0)                 ## CONT:
}

## Emit the CHECKED DIVISION guards (I11 / CG-13) on the register-allocated IR path — the exact dual of the
## text path's `testq %rbx,%rbx; jnz 1f; ud2; 1:` (+ the signed `MIN / -1` arm). The caller has already
## emitted `mov %rax, L`, so %rax holds the dividend and (`rok`,`rov`) the register-resident divisor.
## Division by zero and `MIN / -1` fail through the SAME `ud2` as the overflow family, emitted BEFORE the
## divide, so the x86_64 hardware `#DE` (SIGFPE) is never the observable failure. `ud2` (op 13) is a dead
## end and each CONT label is a block boundary the allocator already splits on; `cmp` (op 4) is read-only,
## so no vreg is defined across a branch except the short-lived INT64_MIN constant.
ir_emit_div_guard := fn(rok : usize, rov : i64, signed : bool) {
  cz := ir_fresh_label()
  regalloc::ra_ir_emit(4, rok, rov, 1, 0)                      ## cmp R, $0
  regalloc::ra_ir_emit(9, 4, i64(cz), 1, 1)                    ## jne CONT   (non-zero divisor: no trap)
  regalloc::ra_ir_emit(13, 0, 0, 0, 0)                         ## ud2        (division by zero)
  regalloc::ra_ir_emit(10, 4, i64(cz), 0, 0)                   ## CONT:
  if signed {
    co := ir_fresh_label()
    regalloc::ra_ir_emit(4, rok, rov, 1, 0 - 1)                ## cmp R, $-1
    regalloc::ra_ir_emit(9, 4, i64(co), 1, 1)                  ## jne CONT2  (divisor not -1: no trap)
    t := ir_fresh_vreg()
    mut mn : i64 = 0 - 9223372036854775807
    mn = mn - 1                                                 ## INT64_MIN (the AST has no negative literal)
    regalloc::ra_ir_emit(0, 3, i64(t), 1, mn)                  ## mov t, $INT64_MIN
    regalloc::ra_ir_emit(4, 2, 0, 3, i64(t))                   ## cmp %rax, t
    regalloc::ra_ir_emit(9, 4, i64(co), 1, 1)                  ## jne CONT2  (dividend not MIN: no trap)
    regalloc::ra_ir_emit(13, 0, 0, 0, 0)                       ## ud2        (MIN / -1 division overflow)
    regalloc::ra_ir_emit(10, 4, i64(co), 0, 0)                 ## CONT2:
  }
}

## Lower an arithmetic / division binary op to an operand. `unch` = inside an `unchecked` scope (no
## overflow guard emitted). For the scalar-leaf shape every operand is a NATIVE-width scalar (u64/usize/
## i64/isize) — no narrow-width truncation and no pointer arithmetic are reachable here (there is no
## conversion / field / call expr in the admitted set), so the ONLY guard distinction is signed (`jno`)
## vs unsigned (`jnc`), matching the text path where `ovf_narrow`/pointer are both false. A literal-`0`
## LEFT operand (`0 - x` / `0 * x`) skips the guard, exactly as the text path's `expr_is_zero(l)` does.
ir_lower_bin := fn(op : u8, l : ptr(Expr), r : ptr(Expr), cx : ptr(LCtx), unch : bool) -> IROperand {
  dsigned := is_signed_expr(l, cx) or is_signed_expr(r, cx)
  ## A NEGATED operand (`30 + -a`) forces the SIGNED overflow guard — `-a`'s runtime word is a large
  ## unsigned pattern, so the unsigned CARRY guard would spuriously trap a sum that fits as a signed
  ## wrapping subtraction (mirrors the text-path `gsigned` rule).
  gsigned := dsigned or expr_is_uneg(l) or expr_is_uneg(r)
  if op == 16 or op == 17 {
    ## Preserve a literal left operand as an immediate. The destination still receives a fresh vreg, so the
    ## arithmetic instruction remains valid (`mov t, $lhs; op t, R`) and the scalar-IR constant fold can
    ## see both immediate operands. Non-immediate left operands are unchanged; checked guards remain emitted
    ## below and the allocator's fold refuses their immediately-following jcc.
    lo := ir_lower_expr(l, cx, unch)
    ro := ir_lower_expr(r, cx, unch)
    t := ir_fresh_vreg()
    regalloc::ra_ir_emit(0, 3, i64(t), lo.k, lo.v)              ## mov t, L
    mut iop := 1
    if op == 17 { iop = 2 }
    regalloc::ra_ir_emit(iop, 3, i64(t), ro.k, ro.v)           ## t (+|-)= R  (sets OF/CF)
    ## CHECKED overflow (I11 / CG-8): trap on native-width `+`/`-` overflow — unless `unchecked` or a
    ## `0 - x` negation. Signed → `jno`; unsigned → `jnc` (carry/borrow).
    if (not unch) and (not expr_is_zero(l)) { ir_emit_ovf_guard(gsigned) }
    return IROperand(k = 3, v = i64(t))
  }
  if op == 18 {
    ## CHECKED `*`: SIGNED via 2-operand `imul` (op 3, sets OF on a >64-bit signed product → `jno`);
    ## UNSIGNED via 1-operand `mul` (op 5, rdx:rax, sets CF iff the high half is nonzero → `jnc`) — the
    ## same split the text path uses. `unchecked` (or a `0 * x`) keeps the plain `imul`, no guard.
    if unch or expr_is_zero(l) or dsigned {
      ## Keep an immediate left operand visible to the scalar-IR fold; the fresh destination vreg makes the
      ## `mov t, $lhs` form legal for the following two-operand imul.
      lo := ir_lower_expr(l, cx, unch)
      ro := ir_lower_expr(r, cx, unch)
      t := ir_fresh_vreg()
      regalloc::ra_ir_emit(0, 3, i64(t), lo.k, lo.v)            ## mov t, L
      regalloc::ra_ir_emit(3, 3, i64(t), ro.k, ro.v)           ## imul t, R  (sets OF signed)
      if (not unch) and (not expr_is_zero(l)) { ir_emit_ovf_guard(true) }   ## dsigned here → jno
      return IROperand(k = 3, v = i64(t))
    }
    ## checked UNSIGNED multiply: mov rax, L; mul R; jnc CONT; ud2; CONT:; mov t, rax.
    lo := ir_lower_expr(l, cx, unch)
    ro := ir_to_reg(ir_lower_expr(r, cx, unch))
    regalloc::ra_ir_emit(0, 2, 0, lo.k, lo.v)                  ## mov rax, L
    regalloc::ra_ir_emit(5, ro.k, ro.v, 0, 0)                  ## mul R  (rdx:rax; CF set on overflow)
    ir_emit_ovf_guard(false)                                   ## jnc
    t := ir_fresh_vreg()
    regalloc::ra_ir_emit(0, 3, i64(t), 2, 0)                   ## mov t, rax (low product; rax not allocatable)
    return IROperand(k = 3, v = i64(t))
  }
  if op == 19 or op == 29 {
    ## divide `/` (19) / modulo `%` (29): rax = L; (cqto | rdx=0 in the renderer); div R; quotient in
    ## rax, remainder in rdx. SIGNED (`idivq`) iff a known signed operand, else UNSIGNED (`divq`) —
    ## the exact rule the text path uses (see the emit_gas op 19/29 arm). A CHECKED division emits the
    ## CG-13 guards (`ir_emit_div_guard`) BEFORE the divide — a zero divisor, plus `MIN / -1` on a signed
    ## divide — so the failure is the family's one `ud2`, never the hardware `#DE`. Under `unchecked` the
    ## guard is absent and the machine decides (CG-7); a positive-literal divisor elides it (provably
    ## neither condition, the same `expr_is_pos_num` test the text path uses, so `ALATYR_RA=0` agrees).
    lo := ir_lower_expr(l, cx, unch)
    ro := ir_to_reg(ir_lower_expr(r, cx, unch))
    regalloc::ra_ir_emit(0, 2, 0, lo.k, lo.v)                  ## mov rax, L
    if (not unch) and (not expr_is_pos_num(r)) { ir_emit_div_guard(ro.k, ro.v, dsigned) }
    if dsigned { regalloc::ra_ir_emit(12, ro.k, ro.v, 0, 0) }  ## idiv R (renderer: cqto)
    else { regalloc::ra_ir_emit(11, ro.k, ro.v, 0, 0) }        ## udiv R (renderer: xorq %rdx,%rdx)
    t := ir_fresh_vreg()
    if op == 19 { regalloc::ra_ir_emit(0, 3, i64(t), 2, 0) }   ## quotient (%rax)
    else { regalloc::ra_ir_emit(0, 3, i64(t), 2, 3) }          ## remainder (%rdx)
    return IROperand(k = 3, v = i64(t))
  }
  if op == 34 or op == 35 or op == 36 {
    ## BITWISE `&` (34) / `|` (35) / `^` (36): a 2-operand read-modify-write on the low 64 bits, no
    ## overflow possible (never a checked guard) — `mov t, L; <and|or|xor>q R, t`. IR opcode 16/17/18.
    ## Keep an immediate left operand in the exact `mov t, $imm; bitop t, $imm` shape consumed by the
    ## scalar-IR fold. `ir_to_reg` would materialize it into one vreg and the destination copy below would
    ## hide the two immediate operands behind an unnecessary `mov t, v`; non-immediate operands already
    ## arrive as vregs and follow the same destination-first lowering.
    lo := ir_lower_expr(l, cx, unch)
    ro := ir_lower_expr(r, cx, unch)
    t := ir_fresh_vreg()
    regalloc::ra_ir_emit(0, 3, i64(t), lo.k, lo.v)             ## mov t, L
    mut bop := 16
    if op == 35 { bop = 17 }
    if op == 36 { bop = 18 }
    regalloc::ra_ir_emit(bop, 3, i64(t), ro.k, ro.v)          ## t (&|^)= R
    return IROperand(k = 3, v = i64(t))
  }
  panic("selfhost: regalloc emit — unsupported binary op in scalar-leaf IR path")
  IROperand(k = 1, v = 0)
}

## The jcc condition-code (renderer legend: 0 e,1 ne,2 l,3 le,4 g,5 ge,6 b,7 be,8 a,9 ae) that branches
## when the comparison `op` is FALSE (so a `while`/`if` guard jumps PAST its body). `ucmp` picks the
## unsigned ordering codes; the signed codes are the default (matching the text path's setcc choice).
ir_neg_cc := fn(op : u8, ucmp : bool) -> usize {
  if op == 20 { return 1 }                       ## ==  false → jne
  if op == 28 { return 0 }                        ## !=  false → je
  if op == 24 { if ucmp { return 9 } return 5 }   ## <   false → jae / jge
  if op == 25 { if ucmp { return 7 } return 3 }   ## >   false → jbe / jle
  if op == 26 { if ucmp { return 8 } return 4 }   ## <=  false → ja  / jg
  if ucmp { return 6 }                            ## >=  false → jb  / jl
  2
}

## Lower a condition: emit a compare + a jcc to `lfalse` taken when the condition is FALSE.
ir_lower_cond := fn(c : ptr(Expr), lfalse : usize, cx : ptr(LCtx), unch : bool) {
  match deref(c) {
    Expr::Unchecked(inner) => { ir_lower_cond(inner, lfalse, cx, true) }
    Expr::Bitcast(inner, _bcs, _bcl) => { ir_lower_cond(inner, lfalse, cx, true) }
    Expr::Bin(op, l, r) => {
      if op == 20 or op == 24 or op == 25 or op == 26 or op == 27 or op == 28 {
        lo := ir_to_reg(ir_lower_expr(l, cx, unch))
        ro := ir_lower_expr(r, cx, unch)
        ucmp := is_unsigned_cmp(l, r, cx)
        regalloc::ra_ir_emit(4, lo.k, lo.v, ro.k, ro.v)              ## cmp L, R
        regalloc::ra_ir_emit(9, 4, i64(lfalse), 1, i64(ir_neg_cc(op, ucmp)))
      } else {
        panic("selfhost: regalloc emit — unsupported condition op in scalar-leaf IR path")
      }
    }
    _ => {
      ## a plain scalar/bool value used as a condition: false when zero.
      o := ir_to_reg(ir_lower_expr(c, cx, unch))
      regalloc::ra_ir_emit(4, o.k, o.v, 1, 0)                        ## cmp val, $0
      regalloc::ra_ir_emit(9, 4, i64(lfalse), 1, 0)                 ## je lfalse
    }
  }
}

## Lower a statement list to the IR. `unch` = inside an `unchecked` scope.
## ITERABLE `for x in s` over a by-ref `Slice(scalar)` PARAM (COMMIT 6c) — factored out of `ir_lower_stmts`
## to keep that (recursive) function small (a large emit function pressures the seed's per-fn scratch). `s`'s
## incoming pointer P is in its spilled text slot (byte -(pidx+1)*8; the barrier prologue put it there).
## Extract data base = *(P) and len = *(P+8) ONCE into vregs, run a counted loop over a loop-carried index,
## and load each element `*(base + idx*8)` into the loop var's vreg through a register-held address:
##   base=*(P); len=*(P+8); idx=0; lg: cmp idx,len; jge done; x=*(base+idx*8); <body>; idx+=1; jmp lg; done:
ir_lower_slice_for := fn(fns : usize, fnl : usize, flo : ptr(Expr), fb : ptr(mut Stmt), cx : ptr(LCtx), unch : bool) {
  fv := var_name_span(flo)
  pidx := ir_slice_param_idx(cx.src, fv.s, fv.n)                  ## >= 0 (predicate-validated)
  bent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, fv.s, fv.n)))
  byte_elem := ir_slice_param_byte(cx.src, bent.ns, bent.nl)
  slotdisp := 0 - i64(usize(pidx) + 1) * 8
  pV := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(pV), 5, slotdisp)               ## mov P, slot(%rbp)  (the param pointer)
  baseV := ir_fresh_vreg()
  regalloc::ra_ir_emit(15, 3, i64(baseV), 3, i64(pV))            ## load base, (P)      (data ptr = word 0)
  tL := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(tL), 3, i64(pV))                ## mov tL, P
  regalloc::ra_ir_emit(1, 3, i64(tL), 1, 8)                      ## add tL, $8
  lenV := ir_fresh_vreg()
  regalloc::ra_ir_emit(15, 3, i64(lenV), 3, i64(tL))             ## load len, (P+8)     (word 1)
  idxV := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(idxV), 1, 0)                    ## mov idx, $0
  lg := ir_fresh_label()
  ld := ir_fresh_label()
  regalloc::ra_ir_emit(10, 4, i64(lg), 0, 0)                     ## lg:
  regalloc::ra_ir_emit(4, 3, i64(idxV), 3, i64(lenV))            ## cmp idx, len
  regalloc::ra_ir_emit(9, 4, i64(ld), 1, 5)                      ## jge done  (idx >= len → exit)
  xV := ir_var_vreg(cx, fns, fnl)                                ## the loop element var
  if byte_elem {
    regalloc::ra_ir_emit_bload(i64(xV), i64(baseV), i64(idxV))    ## movzbq (base, idx, 1), x
  } else {
    regalloc::ra_ir_emit_sload(i64(xV), i64(baseV), i64(idxV))    ## movq (base, idx, 8), x
  }
  ir_lower_stmts(fb, cx, unch)                                   ## loop body
  regalloc::ra_ir_emit(1, 3, i64(idxV), 1, 1)                    ## idx += 1
  regalloc::ra_ir_emit(8, 4, i64(lg), 0, 0)                      ## jmp lg
  regalloc::ra_ir_emit(10, 4, i64(ld), 0, 0)                     ## done:
}
## ITERABLE `for x in ys` over an inline SCALAR ARRAY LOCAL (COMMIT 6d). The array `ys` is FRAME-RESIDENT
## (its N element words reserved at the frame top by `collect_slots`; its init went through the statement
## barrier). Materialize the base `&element0` = `-(bslot+1)*8(%rbp)` ONCE into a vreg with a LEA-SLOT (op
## 22), take the STATIC element count (`snl`, recorded by `bind_array_slot`) as an IMMEDIATE, then run a
## counted loop over a loop-carried index, loading each element `*(base + idx*estride*8)` into the loop
## var's vreg through a register-held address — matching the text path's `is_arr` branch byte-for-answer:
##   base=&elem0; len=$N; idx=0; lg: cmp idx,len; jge done; x=*(base+idx*8); <body>; idx+=1; jmp lg; done:
ir_lower_array_for := fn(fns : usize, fnl : usize, flo : ptr(Expr), fb : ptr(mut Stmt), cx : ptr(LCtx), unch : bool) {
  fv := var_name_span(flo)
  bent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, fv.s, fv.n)))
  bslot := bent.off
  estride := bent.estride                                        ## words per element (1 for a scalar array)
  count := bent.snl                                              ## static element count (bind_array_slot)
  disp := 0 - i64(bslot + 1) * 8
  baseV := ir_fresh_vreg()
  regalloc::ra_ir_emit(22, 3, i64(baseV), 1, disp)              ## leaq disp(%rbp), base   (&element0)
  lenV := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(lenV), 1, i64(count))          ## mov len, $N             (static count)
  idxV := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(idxV), 1, 0)                    ## mov idx, $0
  lg := ir_fresh_label()
  ld := ir_fresh_label()
  regalloc::ra_ir_emit(10, 4, i64(lg), 0, 0)                     ## lg:
  regalloc::ra_ir_emit(4, 3, i64(idxV), 3, i64(lenV))            ## cmp idx, len
  regalloc::ra_ir_emit(9, 4, i64(ld), 1, 5)                      ## jge done  (idx >= len → exit)
  xV := ir_var_vreg(cx, fns, fnl)                                ## the loop element var
  if estride == 1 {
    regalloc::ra_ir_emit_sload(i64(xV), i64(baseV), i64(idxV))   ## movq (base, idx, 8), x  (folded, word element)
  } else {
    aX := ir_fresh_vreg()
    regalloc::ra_ir_emit(0, 3, i64(aX), 3, i64(idxV))            ## mov addr, idx
    regalloc::ra_ir_emit(3, 3, i64(aX), 1, i64(estride) * 8)     ## imul addr, $(estride*8)   (non-word stride)
    regalloc::ra_ir_emit(1, 3, i64(aX), 3, i64(baseV))          ## add addr, base
    regalloc::ra_ir_emit(15, 3, i64(xV), 3, i64(aX))             ## load x, (base + idx*estride*8)
  }
  ir_lower_stmts(fb, cx, unch)                                   ## loop body
  regalloc::ra_ir_emit(1, 3, i64(idxV), 1, 1)                    ## idx += 1
  regalloc::ra_ir_emit(8, 4, i64(lg), 0, 0)                      ## jmp lg
  regalloc::ra_ir_emit(10, 4, i64(ld), 0, 0)                     ## done:
}
## ITERABLE `for x in v` over an arena-backed `Vec(T)` LOCAL (the Vec-LOCAL increment). The Vec is a 4-word
## `@owning struct { idx, len, cap, arena }` FRAME-RESIDENT local (built by the text barriers just above); its
## word 0 (idx) is the arena HANDLE (a byte offset), NOT a raw pointer — so the element base is `arena.base +
## idx`, resolved ONCE into a vreg here (mirroring the text is_vec path). §4 up-growing: field k of the local
## lives at slot `vec_bslot - k` (frame `-(vec_bslot - k + 1)*8`). Hoisted ONCE: base = *(arena_ptr) + idx and
## len = *(field 1); then a counted loop over a loop-carried index loads each element `*(base + idx*8)` through
## a register-held address — no per-iteration frame reload of base/len/index. Scalar/word elements (arraysum).
## ACCUMULATOR HOIST (ROADMAP 6e follow-up): find THE scalar accumulator of a for-over-Vec body so the
## sum-loop keeps it in a REGISTER (not a per-iteration frame round-trip). The accumulator = the UNIQUE
## scalar local that a TOP-LEVEL body `Stmt::Assign` READS-AND-WRITES (`sum = sum + x` / `sum += x`), that
## is already MODELED (has an IRV vreg — i.e. declared before the loop, e.g. `mut sum := 0`), has a scalar
## (`ek == 0`) FRAME slot (so a surrounding barrier that reads its slot stays correct), and is NOT the loop
## element var. Returns its IRV INDEX, or -1 (none / ambiguous / any non-Assign top-level stmt ⇒ no hoist,
## body lowered byte-identically to before). Reuses the IRRD read-walker (re-init here; barrier syncs
## re-init it independently, so the transient clobber is safe).
ir_find_accum := fn(cx : ptr(LCtx), fns : usize, fnl : usize, fb : ptr(mut Stmt)) -> i64 {
  mut acc_s := 0
  mut acc_l := 0
  mut count := 0
  mut s := fb
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => {
        if (not streq(cx.src, ns, nl, fns, fnl)) and ir_var_vreg_lookup(cx, ns, nl) >= 0 {
          IRRD_N = 0
          IRRD_OK = true
          ir_rd_expr(cx.src, v)                                  ## collect the RHS read set
          mut reads := false
          mut k := 0
          while k < IRRD_N { if streq(cx.src, IRRD_S[k], IRRD_L[k], ns, nl) { reads = true } ; k += 1 }
          if reads {
            off := slot_of(cx.slots, cx.src, ns, nl)
            if off >= 0 {
              ek := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, ns, nl))).ek
              if ek == 0 {
                if not (acc_l != 0 and streq(cx.src, acc_s, acc_l, ns, nl)) { count += 1; acc_s = ns; acc_l = nl }
              }
            }
          }
        }
        s = nx
      }
      _ => { s = 0 }                                             ## non-Assign top-level stmt ⇒ stop (surgical)
    }
  }
  if count == 1 {
    mut i := 0
    while i < IRV_N { if streq(cx.src, IRV_S[i], IRV_L[i], acc_s, acc_l) { return i64(i) } ; i += 1 }
    0 - 1
  } else { 0 - 1 }
}
ir_lower_vec_for := fn(fns : usize, fnl : usize, flo : ptr(Expr), fb : ptr(mut Stmt), cx : ptr(LCtx), unch : bool) {
  fv := var_name_span(flo)
  bent := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, fv.s, fv.n)))
  ## authoritative slot guard: the loop var must be a Vec struct LOCAL (`ek == 2`, base type name "Vec").
  ## The predicate admits `for x in v` from the RHS call's return type; this catches any false positive
  ## LOUD (never a silent miscompile) — matching the text is_vec detection.
  if not (bent.ek == 2 and bent.snl != 0) { panic("selfhost: regalloc emit — vec-for over a non-struct local") }
  vbn := base_type_name(cx.src, bent.sns, bent.snl)
  if str_at((cx.src + vbn.s), vbn.n) != "Vec" { panic("selfhost: regalloc emit — vec-for over a non-Vec local") }
  vb := bent.off                                                 ## vec_bslot (word-0 = idx slot)
  arenaP := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(arenaP), 5, 0 - (i64(vb) - 2) * 8)  ## mov arenaP, arena(%rbp) (Vec field 3)
  baseV := ir_fresh_vreg()
  regalloc::ra_ir_emit(15, 3, i64(baseV), 3, i64(arenaP))         ## load base, (arenaP)       (arena.base = word 0)
  vidxV := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(vidxV), 5, 0 - (i64(vb) + 1) * 8)   ## mov vidx, idx(%rbp)     (Vec field 0 = handle)
  regalloc::ra_ir_emit(1, 3, i64(baseV), 3, i64(vidxV))          ## base += idx               (element base)
  lenV := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(lenV), 5, 0 - i64(vb) * 8)        ## mov len, len(%rbp)        (Vec field 1)
  idxV := ir_fresh_vreg()
  regalloc::ra_ir_emit(0, 3, i64(idxV), 1, 0)                    ## mov idx, $0
  ## ACCUMULATOR HOIST: if the body accumulates into a slot-resident scalar (`sum += x`), COPY that scalar's
  ## modeled vreg into a FRESH loop-carried vreg (accV) here — accV's interval spans only the loop (no op-24
  ## barrier), so linear-scan keeps it register-resident; the body's reads/writes of the accumulator are then
  ## re-pointed to accV (see below), and accV is stored back to the original vreg AFTER the loop. The original
  ## vreg (`sumVr`) still spans the surrounding barriers and spills — but a barrier's sync-store reads sumVr,
  ## which now holds the initial value BEFORE the loop and the final sum AFTER it, so the barrier-sync contract
  ## (any barrier reading the accumulator's frame slot sees the up-to-date value) is preserved exactly.
  accIdx := ir_find_accum(cx, fns, fnl, fb)
  mut accV : usize = 0
  mut sumVr : usize = 0
  if accIdx >= 0 {
    sumVr = IRV_V[accIdx]
    accV = ir_fresh_vreg()
    regalloc::ra_ir_emit(0, 3, i64(accV), 3, i64(sumVr))         ## mov accV, sumVr  (accumulator → loop reg)
    IRV_V[accIdx] = accV                                         ## body reads/writes the accumulator via accV
  }
  lg := ir_fresh_label()
  ld := ir_fresh_label()
  regalloc::ra_ir_emit(10, 4, i64(lg), 0, 0)                     ## lg:
  regalloc::ra_ir_emit(4, 3, i64(idxV), 3, i64(lenV))            ## cmp idx, len
  regalloc::ra_ir_emit(9, 4, i64(ld), 1, 5)                      ## jge done  (idx >= len → exit)
  xV := ir_var_vreg(cx, fns, fnl)                                ## the loop element var
  regalloc::ra_ir_emit_sload(i64(xV), i64(baseV), i64(idxV))     ## movq (base, idx, 8), x  (folded scaled load)
  ir_lower_stmts(fb, cx, unch)                                   ## loop body (accumulator re-pointed to accV)
  regalloc::ra_ir_emit(1, 3, i64(idxV), 1, 1)                    ## idx += 1
  regalloc::ra_ir_emit(8, 4, i64(lg), 0, 0)                     ## jmp lg
  regalloc::ra_ir_emit(10, 4, i64(ld), 0, 0)                     ## done:
  if accIdx >= 0 {
    IRV_V[accIdx] = sumVr                                        ## restore the accumulator's original binding
    regalloc::ra_ir_emit(0, 3, i64(sumVr), 3, i64(accV))         ## mov sumVr, accV  (final sum → modeled vreg)
  }
}
## Is expr `e` a CALL (possibly under `unchecked`)? Strips a leading `Unchecked` (`r := unchecked mmap(…)`).
ir_is_call_rhs := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => { true }
    Expr::Unchecked(inner) => { ir_is_call_rhs(inner) }
    _ => { false }
  }
}
## The TAIL segment (after the last `::`) of a callee name span — a decl's own name is just the tail, so a
## qualified `alloc::vec::with_capacity` matches the `with_capacity` decl.
ir_call_tail := fn(src : ptr(u8), cs : usize, cl : usize) -> CSpan {
  mut ts := cs
  mut ti := 0
  while ti + 1 < cl {
    if str_at((src + cs + ti), 2) == "::" { ts = cs + ti + 2 }
    ti += 1
  }
  CSpan(s = ts, n = cl - (ts - cs))
}
## STRICT WHITELIST for a general STATEMENT BARRIER — the ONLY calls admitted as a text-spliced Vec-build
## barrier: a `@abi(syscall)` fn (kind 4 — the `mmap` region), a fn RETURNING `Vec(_)` (`with_capacity`/`new`),
## a fn RETURNING `Arena` (`arena_over`), or a `push`. Anything else (fmt/display/print/io helpers, any general
## call) is NOT a barrier → the fn falls to the text path. Resolved by TAIL name across all decls. This — with
## the final Vec-shape gate — is why NO fmt/display/print/inject fn is ever admitted to the RA barrier path.
ir_is_vecbuild_call := fn(src : ptr(u8), decls : ptr(rt::Vec), e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Unchecked(inner) => { ir_is_vecbuild_call(src, decls, inner) }
    Expr::Call(cs, cl, na, ah) => {
      t := ir_call_tail(src, cs, cl)
      pushname := str_at((src + t.s), t.n) == "push"
      cnt := rt::vec_len(deref(decls))
      mut i := 0
      while i < cnt {
        d := deref(decl_get(decls, i))
        if (d.kind == 1 or d.kind == 4) and streq(src, d.name_start, d.name_len, t.s, t.n) {
          if d.kind == 4 { return true }                          ## a @abi(syscall) fn (mmap)
          bn := base_type_name(src, d.ret_ts, d.ret_tl)
          rn := str_at((src + bn.s), bn.n)
          if rn == "Vec" or rn == "Arena" { return true }         ## with_capacity / new / arena_over
          if pushname and rn == "Result" { return true }          ## alloc::vec::push (→ Result)
        }
        i += 1
      }
      false
    }
    _ => { false }
  }
}
## Does the CALL RHS `e` resolve (by TAIL name) to a fn whose RETURN type base name is "Vec"? (→ `v` is an
## admissible Vec LOCAL for `for x in v`.) Backstopped by the lower-time slot assertion in ir_lower_vec_for.
ir_call_returns_vec := fn(src : ptr(u8), decls : ptr(rt::Vec), e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Unchecked(inner) => { ir_call_returns_vec(src, decls, inner) }
    Expr::Call(cs, cl, na, ah) => {
      t := ir_call_tail(src, cs, cl)
      cnt := rt::vec_len(deref(decls))
      mut i := 0
      while i < cnt {
        d := deref(decl_get(decls, i))
        if d.is_fn and streq(src, d.name_start, d.name_len, t.s, t.n) {
          bn := base_type_name(src, d.ret_ts, d.ret_tl)
          if str_at((src + bn.s), bn.n) == "Vec" { return true }
        }
        i += 1
      }
      false
    }
    _ => { false }
  }
}
## Record a GENERAL STATEMENT BARRIER for the statement at handle `sp` — emit a full-clobber op 24 carrying
## its side-table index; the render splices the WHOLE statement through the text `emit_stmts` (halting at its
## `nx` via the STOP sentinel so exactly one emits). Used for the Vec-build chain (mmap/arena/with_capacity/push).
ir_emit_gbarrier := fn(sp : usize) {
  id := IRGSB_N
  if id >= 16 { panic("selfhost: regalloc emit — general stmt-barrier side-table overflow (predicate too permissive)") }
  IRGSB_P[id] = sp
  IRGSB_N = IRGSB_N + 1
  regalloc::ra_ir_emit(24, 4, i64(id), 0, 0)
}
## add a DISTINCT read var span (dedup keeps the sync count tight); overflow → give up (reject the fn).
ir_rd_add := fn(src : ptr(u8), s : usize, n : usize) {
  mut i := 0
  while i < IRRD_N { if streq(src, IRRD_S[i], IRRD_L[i], s, n) { return } ; i += 1 }
  if IRRD_N < 32 { IRRD_S[IRRD_N] = s; IRRD_L[IRRD_N] = n; IRRD_N = IRRD_N + 1 } else { IRRD_OK = false }
}
## Collect every Var READ in a value expression into IRRD; a form the walker cannot decompose → give up.
ir_rd_expr := fn(src : ptr(u8), e : ptr(Expr)) {
  match deref(e) {
    Expr::Num(v, s, n) => {}
    Expr::BoolLit(v) => {}
    Expr::StrLit(ss, sl, si) => {}
    Expr::FloatLit(fs, fl) => {}
    Expr::Var(s, n) => { ir_rd_add(src, s, n) }
    Expr::Bin(op, l, r) => { ir_rd_expr(src, l); ir_rd_expr(src, r) }
    Expr::Unchecked(inner) => { ir_rd_expr(src, inner) }
    Expr::Bitcast(inner, bcs, bcl) => { ir_rd_expr(src, inner) }
    Expr::Field(b, fs, fl) => { ir_rd_expr(src, b) }
    Expr::Deref(p) => { ir_rd_expr(src, p) }
    Expr::AddrOf(p) => { ir_rd_expr(src, p) }
    Expr::Try(p) => { ir_rd_expr(src, p) }
    Expr::Index(b, ix) => { ir_rd_expr(src, b); ir_rd_expr(src, ix) }
    Expr::If(c, t, f) => { ir_rd_expr(src, c); ir_rd_expr(src, t); ir_rd_expr(src, f) }
    Expr::Call(cs, cl, na, ah) => { mut g := ah; while g != 0 { ga := deref(arg_p(g)); ir_rd_expr(src, ga.e); g = ga.next } }
    Expr::StructLit(ns, nl, nf, fh) => { mut g := fh; while g != 0 { ga := deref(arg_p(g)); ir_rd_expr(src, ga.e); g = ga.next } }
    _ => { IRRD_OK = false }
  }
}
## Collect every Var READ across a statement LIST (a barriered `while` body); an unhandled stmt → give up.
ir_rd_stmts := fn(src : ptr(u8), head : ptr(mut Stmt)) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { ir_rd_expr(src, v); s = nx }
      Stmt::ExprStmt(e, nx) => { ir_rd_expr(src, e); s = nx }
      Stmt::If(c, th, el, nx) => { ir_rd_expr(src, c); ir_rd_stmts(src, th); ir_rd_stmts(src, el); s = nx }
      Stmt::While(c, b, nx) => { ir_rd_expr(src, c); ir_rd_stmts(src, b); s = nx }
      Stmt::Loop(b, nx) => { ir_rd_stmts(src, b); s = nx }
      Stmt::Unchecked(b, nx) => { ir_rd_stmts(src, b); s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { ir_rd_expr(src, flo); if unchecked bitcast(usize, fhi) != 0 { ir_rd_expr(src, fhi) } ; ir_rd_stmts(src, fb); s = nx }
      _ => { IRRD_OK = false; s = 0 }
    }
  }
}
## Reset IRRD and collect the READ set of a barrier statement `sp` (an Assign RHS / an ExprStmt call / a
## whole barriered `while`). `IRRD_OK` false ⇒ the walker met a form it could not analyse ⇒ reject the fn.
ir_collect_barrier_reads := fn(src : ptr(u8), sp : usize) {
  IRRD_N = 0
  IRRD_OK = true
  st := deref(stmt_p(Stmt, unchecked bitcast(ptr(mut Stmt), sp)))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { ir_rd_expr(src, v) }
    Stmt::ExprStmt(e, nx) => { ir_rd_expr(src, e) }
    Stmt::While(c, b, nx) => { ir_rd_expr(src, c); ir_rd_stmts(src, b) }
    _ => { IRRD_OK = false }
  }
}
## The vreg id already assigned to a NAMED var (-1 = not modeled yet — a frame-resident build target or a
## not-yet-lowered local). Unlike `ir_var_vreg` this NEVER creates one, so a sync only fires for a var the
## modeled path has genuinely register-allocated.
ir_var_vreg_lookup := fn(cx : ptr(LCtx), s : usize, n : usize) -> i64 {
  mut i := 0
  while i < IRV_N { if streq(cx.src, IRV_S[i], IRV_L[i], s, n) { return i64(IRV_V[i]) } ; i += 1 }
  0 - 1
}
## Before a general barrier: store every MODELED scalar the barrier reads into its TEXT frame slot. Only a
## var already in IRV (modeled + defined) with a scalar (ek 0) slot; a frame-resident Vec/Arena/build target
## is not in IRV → never synced. The store reads the vreg (kept live to here) and writes the reserved slot.
ir_sync_before_barrier := fn(cx : ptr(LCtx), sp : usize) {
  ir_collect_barrier_reads(cx.src, sp)
  mut i := 0
  while i < IRRD_N {
    vr := ir_var_vreg_lookup(cx, IRRD_S[i], IRRD_L[i])
    if vr >= 0 {
      off := slot_of(cx.slots, cx.src, IRRD_S[i], IRRD_L[i])
      if off >= 0 {
        ek := deref(svec_at(SlotEntry, cx.slots, entry_of(cx.slots, cx.src, IRRD_S[i], IRRD_L[i]))).ek
        if ek == 0 { regalloc::ra_ir_emit(0, 5, 0 - (off + 1) * 8, 3, vr) }   ## movq %vreg, slot(%rbp)
      }
    }
    i += 1
  }
}
## Sync live modeled scalars into their frame slots, THEN emit the op-24 barrier (text-splices `sp`).
ir_gbarrier := fn(sp : usize, cx : ptr(LCtx)) {
  ir_sync_before_barrier(cx, sp)
  ir_emit_gbarrier(sp)
}
## Predicate mirror of `ir_sync_before_barrier`: count the modeled-scalar syncs the barrier `sp` will emit
## (into IRP_NSYNC — the inst budget) and REJECT the fn if the read walker gave up. "Modeled scalar" =
## bound, not a global / by-ref struct param / slice-param / array-local / Vec-local / frame-resident build
## target — a superset of "in IRV at emit", so the count is a SOUND upper bound of the emitted stores.
ir_count_barrier_syncs := fn(src : ptr(u8), decls : ptr(rt::Vec), sp : usize) {
  ir_collect_barrier_reads(src, sp)
  if not IRRD_OK { IRP_OK = false }
  mut i := 0
  while i < IRRD_N {
    modeled := ir_bound_has(src, IRRD_S[i], IRRD_L[i]) and (not ir_name_is_global(decls, src, IRRD_S[i], IRRD_L[i])) and ir_sp_idx(src, IRRD_S[i], IRRD_L[i]) < 0 and ir_slice_param_idx(src, IRRD_S[i], IRRD_L[i]) < 0 and ir_array_local_idx(src, IRRD_S[i], IRRD_L[i]) < 0 and ir_vec_local_idx(src, IRRD_S[i], IRRD_L[i]) < 0 and ir_fr_idx(src, IRRD_S[i], IRRD_L[i]) < 0
    if modeled { IRP_NSYNC = IRP_NSYNC + 1 }
    i += 1
  }
}
## Does a statement LIST contain a WHITELISTED Vec-build call (a `push`/`with_capacity`/`arena_over`/mmap)?
## Marks a `while i < n { v.push(…) }` build loop → the WHOLE loop becomes ONE text barrier (its cursor +
## pushes stay frame-resident). A plain arithmetic `while` has none → stays a MODELED loop (unchanged).
ir_stmts_have_vecbuild := fn(src : ptr(u8), decls : ptr(rt::Vec), head : ptr(mut Stmt)) -> bool {
  mut s := head
  mut r := false
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { if ir_is_call_rhs(v) and ir_is_vecbuild_call(src, decls, v) { r = true } ; s = nx }
      Stmt::ExprStmt(e, nx) => { if ir_is_call_rhs(e) and ir_is_vecbuild_call(src, decls, e) { r = true } ; s = nx }
      Stmt::Unchecked(b, nx) => { if ir_stmts_have_vecbuild(src, decls, b) { r = true } ; s = nx }
      Stmt::If(c, th, el, nx) => { if ir_stmts_have_vecbuild(src, decls, th) or ir_stmts_have_vecbuild(src, decls, el) { r = true } ; s = nx }
      Stmt::While(c, b, nx) => { if ir_stmts_have_vecbuild(src, decls, b) { r = true } ; s = nx }
      Stmt::Loop(b, nx) => { if ir_stmts_have_vecbuild(src, decls, b) { r = true } ; s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { if ir_stmts_have_vecbuild(src, decls, fb) { r = true } ; s = nx }
      _ => { s = 0 }
    }
  }
  r
}
pub ir_lower_stmts := fn(head : ptr(mut Stmt), cx : ptr(LCtx), unch : bool) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl2, v, nx) => {
        ## an inline SCALAR array local's array-literal INIT (`ys := [10,20,3,9]`) → a STATEMENT BARRIER:
        ## the whole init is emitted through the text `emit_array_assign` at render (writing the element
        ## words into the array's FRAME slots), bracketed by a full-clobber op 23 so any live-across scalar
        ## spills. It produces NO scalar result (no result vreg / `mov`). The array stays frame-resident.
        if array_lit_info(v).is_a {
          bslot := slot_of(cx.slots, cx.src, ns, nl2)
          id := IRSB_N
          if id >= 8 { panic("selfhost: regalloc emit — stmt-barrier side-table overflow (predicate too permissive)") }
          IRSB_E[id] = unchecked bitcast(usize, v)
          IRSB_B[id] = bslot
          IRSB_N = IRSB_N + 1
          regalloc::ra_ir_emit(23, 4, i64(id), 0, 0)                ## STMT BARRIER: emit_array_assign(v, bslot)
        } else if ir_is_call_rhs(v) and ir_is_vecbuild_call(cx.src, cx.decls, v) {
          ## a Vec-build assign (`r := mmap(…)`, `ar := arena_over(…)`, `v := with_capacity(…)`) — the whole
          ## statement is text-spliced into its FRAME slots via a GENERAL BARRIER (the aggregate stays in
          ## memory); no scalar result vreg is produced. Any modeled scalar its args read is synced first.
          ir_gbarrier(s, cx)
        } else {
          vr := ir_var_vreg(cx, ns, nl2)
          o := ir_lower_expr(v, cx, unch)
          regalloc::ra_ir_emit(0, 3, i64(vr), o.k, o.v)             ## mov vr, RHS
        }
        s = nx
      }
      ## a bare-call ExprStmt — a GENERAL BARRIER (result discarded): a Vec-build side effect
      ## (`v.push(x).expect(…)`, the mutation lands in the frame-resident Vec) OR the trailing `fmt::print`
      ## of the result (its `sum` arg is synced to its frame slot first). Both text-spliced via op-24.
      Stmt::ExprStmt(e, nx) => { ir_gbarrier(s, cx); s = nx }
      Stmt::If(c, th, el, nx) => {
        lelse := ir_fresh_label()
        lend := ir_fresh_label()
        ir_lower_cond(c, lelse, cx, unch)
        ir_lower_stmts(th, cx, unch)
        regalloc::ra_ir_emit(8, 4, i64(lend), 0, 0)                 ## jmp lend
        regalloc::ra_ir_emit(10, 4, i64(lelse), 0, 0)              ## lelse:
        ir_lower_stmts(el, cx, unch)
        regalloc::ra_ir_emit(10, 4, i64(lend), 0, 0)               ## lend:
        s = nx
      }
      Stmt::While(c, b, nx) => {
        if ir_stmts_have_vecbuild(cx.src, cx.decls, b) {
          ## a Vec-BUILD `while` (`while i < n { v.push(…) }`): the WHOLE loop is a GENERAL BARRIER —
          ## text-spliced verbatim, so its cursor + pushes stay frame-resident (the modeled cursor `i` set
          ## just above is synced to its slot first). The `for x in v` sum loop over the built Vec is the
          ## register-allocated hot loop that follows.
          ir_gbarrier(s, cx)
        } else {
          lg := ir_fresh_label()
          ld := ir_fresh_label()
          regalloc::ra_ir_emit(10, 4, i64(lg), 0, 0)                 ## lguard:
          ir_lower_cond(c, ld, cx, unch)
          ir_lower_stmts(b, cx, unch)
          regalloc::ra_ir_emit(8, 4, i64(lg), 0, 0)                  ## jmp lguard
          regalloc::ra_ir_emit(10, 4, i64(ld), 0, 0)                 ## ldone:
        }
        s = nx
      }
      ## `alloc::with(A) { body }` (MEM-5): the ambient-allocator scope is a COMPILE-TIME wrapper — the
      ## driver already elided each body call's allocator arg into the AST, so lowering just processes the
      ## body statements (the `with_capacity`/`push` build barriers + the register-allocated `for x in v`).
      Stmt::AllocWith(ae, b, nx) => { ir_lower_stmts(b, cx, unch); s = nx }
      Stmt::Return(rv, nx) => {
        o := ir_lower_expr(rv, cx, unch)
        regalloc::ra_ir_emit(0, 2, 0, o.k, o.v)                    ## mov rax, val
        regalloc::ra_ir_emit(7, 0, 0, 0, 0)                        ## ret (renderer: jmp epilogue)
        s = nx
      }
      ## RANGE `for i in lo..hi { body }` — a counted loop (predicate admits ONLY `fhi != 0`). Lowers to:
      ##   index = lo ; hi_r = hi (once, before the loop) ; lg: cmp index, hi_r ; jge/exit done ;
      ##   <body> ; index += 1 ; jmp lg ; done:
      ## The index is a loop-carried vreg whose interval spans the body (the allocator's loop-carried path).
        ## The exit test follows the upper bound's proven signedness (`jae` for unsigned, `jge` for
        ## signed), matching the text path's `setb`/`setl` semantics. An unresolved bound stays signed.
        ## The `+= 1` increment is UNCHECKED (no overflow guard), exactly as the text path.
      ## The bounds are evaluated ONCE before the loop (pure scalar exprs → equivalent to per-iteration
      ## re-eval, but cheaper); a non-trivial `hi` is materialized into a reg via `ir_to_reg`.
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        if unchecked bitcast(usize, fhi) == 0 {
          ## ITERABLE `for x in <iterable>`: a `Slice(scalar)` PARAM (slice-for) OR an inline scalar ARRAY
          ## LOCAL (array-for). The predicate admitted only these two; dispatch on which the base names.
          fv := var_name_span(flo)
          if ir_slice_param_idx(cx.src, fv.s, fv.n) >= 0 {
            ir_lower_slice_for(fns, fnl, flo, fb, cx, unch)
          } else if ir_vec_local_idx(cx.src, fv.s, fv.n) >= 0 {
            ir_lower_vec_for(fns, fnl, flo, fb, cx, unch)
          } else {
            ir_lower_array_for(fns, fnl, flo, fb, cx, unch)
          }
          s = nx
        } else {
        ivr := ir_var_vreg(cx, fns, fnl)
        lo_op := ir_lower_expr(flo, cx, unch)
        regalloc::ra_ir_emit(0, 3, i64(ivr), lo_op.k, lo_op.v)         ## mov index, lo
        hi_op := ir_to_reg(ir_lower_expr(fhi, cx, unch))               ## hi in a reg (evaluated once)
        lg := ir_fresh_label()
        ld := ir_fresh_label()
        regalloc::ra_ir_emit(10, 4, i64(lg), 0, 0)                     ## lg:
        regalloc::ra_ir_emit(4, 3, i64(ivr), hi_op.k, hi_op.v)         ## cmp index, hi
        regalloc::ra_ir_emit(9, 4, i64(ld), 1, i64(ir_neg_cc(24, range_bound_is_unsigned(fhi, cx))))
                                                                        ## jae/jge done (index >= hi → exit)
        ir_lower_stmts(fb, cx, unch)                                   ## loop body (continue/break not admitted)
        regalloc::ra_ir_emit(1, 3, i64(ivr), 1, 1)                     ## index += 1 (unchecked)
        regalloc::ra_ir_emit(8, 4, i64(lg), 0, 0)                      ## jmp lg
        regalloc::ra_ir_emit(10, 4, i64(ld), 0, 0)                     ## done:
        s = nx
        }
      }
      Stmt::Unchecked(b, nx) => { ir_lower_stmts(b, cx, true); s = nx }
      _ => { panic("selfhost: regalloc emit — unsupported statement in scalar-leaf IR path"); s = 0 }
    }
  }
}

## Physical register name by id (0 rax … 15 r15).
pub ir_phys_name := fn(id : usize) -> str {
  if id == 0 { return "%rax" }
  if id == 1 { return "%rbx" }
  if id == 2 { return "%rcx" }
  if id == 3 { return "%rdx" }
  if id == 4 { return "%rsi" }
  if id == 5 { return "%rdi" }
  if id == 6 { return "%rbp" }
  if id == 7 { return "%rsp" }
  if id == 8 { return "%r8" }
  if id == 9 { return "%r9" }
  if id == 10 { return "%r10" }
  if id == 11 { return "%r11" }
  if id == 12 { return "%r12" }
  if id == 13 { return "%r13" }
  if id == 14 { return "%r14" }
  "%r15"
}
ir_op_mnem := fn(op : usize) -> str {
  if op == 0 { return "movq" }
  if op == 1 { return "addq" }
  if op == 2 { return "subq" }
  if op == 3 { return "imulq" }
  if op == 16 { return "andq" }
  if op == 17 { return "orq" }
  if op == 18 { return "xorq" }
  "cmpq"
}
ir_cc_mnem := fn(cc : usize) -> str {
  if cc == 0 { return "je" }
  if cc == 1 { return "jne" }
  if cc == 2 { return "jl" }
  if cc == 3 { return "jle" }
  if cc == 4 { return "jg" }
  if cc == 5 { return "jge" }
  if cc == 6 { return "jb" }
  if cc == 7 { return "jbe" }
  if cc == 8 { return "ja" }
  if cc == 10 { return "jno" }   ## no signed overflow (checked +/-/* guard)
  if cc == 11 { return "jnc" }   ## no carry/borrow (checked unsigned +/-/* guard)
  "jae"
}
ir_emit_iralabel := fn(in out sb : strbuf::StrBuf, prefix : usize, id : usize) {
  push_str(sb, ".Lra")
  push_int(sb, i64(prefix))
  push_str(sb, "_")
  push_int(sb, i64(id))
}
ir_emit_operand := fn(in out sb : strbuf::StrBuf, k : usize, v : i64) {
  ## kinds are disjoint → independent `if`s (Imm / Phys / Slot); a surviving VReg (3) fails loud.
  ## a str-returning call must be BOUND to a local before `push_str` (an inline str arg drops its length).
  if k == 1 { push_str(sb, "$"); push_int(sb, v) }
  if k == 2 { pn := ir_phys_name(usize(v)); push_str(sb, pn) }
  if k == 5 { push_int(sb, v); push_str(sb, "(%rbp)") }
  if k == 3 { panic("selfhost: regalloc emit — leaked vreg reached render") }
}

## Splice EXACTLY ONE statement (the general-barrier target at handle `sp`) through the text `emit_stmts`.
## `emit_stmts` walks the `nx` chain; the self-host lower cannot CONSTRUCT a `Stmt` value to null `nx`, so
## instead the statement's OWN `nx` is installed as a STOP sentinel (`cx.ir_stop`) that `emit_stmts` halts
## at — emitting just this one statement (its result lands in its FRAME slots / its call side-effect runs).
## %rsp is at the frame base here (the IR body never pushes) so the spliced call is ABI-aligned.
ir_splice_one_stmt := fn(sp : usize, in out sb : strbuf::StrBuf, cx : ptr(LCtx), in out nl : usize) {
  hp := unchecked bitcast(ptr(mut Stmt), sp)
  cx.ir_stop = lower_stmt_nx(sp, arena_of(cx))
  emit_stmts(hp, sb, cx, nl)
  cx.ir_stop = 0
}

## Render the allocated (VReg-free) output stream to GAS. `raprefix` namespaces the IR-internal labels
## (`.Lra<prefix>_<id>`); a `ret` becomes a `jmp` to the shared epilogue label `lepi`.
pub ir_render := fn(in out sb : strbuf::StrBuf, raprefix : usize, lepi : usize, cx : ptr(LCtx), a : rt::Arena, in out nl : usize) {
  cnt := regalloc::ra_out_count()
  mut i := 0
  while i < cnt {
    op := regalloc::ra_out_op(i)
    k0 := regalloc::ra_out_k0(i)
    v0 := regalloc::ra_out_v0(i)
    k1 := regalloc::ra_out_k1(i)
    v1 := regalloc::ra_out_v1(i)
    k2 := regalloc::ra_out_k2(i)
    v2 := regalloc::ra_out_v2(i)
    ## op values are disjoint, so independent `if`s (no `else`) select exactly one rendering.
    ## BARRIER: splice the recorded value expr through the text `emit_gas` (it reads the struct param from
    ## its TEXT frame slot and PUSHES the scalar result), then `popq %rax` — the following `mov <vreg>,%rax`
    ## in the allocated stream copies it into the result vreg's home. %rsp is at the frame base here (the IR
    ## body never pushes), so emit_gas's balanced push/pop returns %rsp intact.
    if op == 14 {
      be := unchecked bitcast(ptr(Expr), IRBR_E[usize(v0)])
      emit_gas(be, sb, cx, a, nl)
      push_str(sb, "  popq %rax\n")
    }
    ## STMT-BARRIER (op 23): splice the recorded inline-array-literal INIT through the text `emit_array_assign`
    ## — it writes each element word into the array's FRAME slots (base slot recorded in IRSB_B). Produces NO
    ## %rax result (unlike the op-14 value barrier). %rsp is at the frame base here (the IR body never pushes),
    ## and emit_array_assign's per-element push/pop is balanced, so %rsp returns intact.
    if op == 23 {
      sbe := unchecked bitcast(ptr(Expr), IRSB_E[usize(v0)])
      emit_array_assign(sbe, IRSB_B[usize(v0)], sb, cx, nl)
    }
    ## GENERAL STMT-BARRIER (op 24): splice the whole recorded Vec-build statement through the text `emit_stmts`
    ## (its result lands in FRAME slots / its call side-effects run). Produces no %rax result the IR consumes.
    if op == 24 {
      ir_splice_one_stmt(IRGSB_P[usize(v0)], sb, cx, nl)
    }
    ## LEA-SLOT (op 22): `leaq disp(%rbp), o0` — the frame displacement rides o1 as an Imm (used raw, no `$`).
    ## Materializes a frame ADDRESS (the base `&element0` of an inline array local) into a register.
    if op == 22 {
      push_str(sb, "  leaq ")
      push_int(sb, v1)
      push_str(sb, "(%rbp), ")
      ir_emit_operand(sb, k0, v0)
      push_str(sb, "\n")
    }
    if op == 10 { ir_emit_iralabel(sb, raprefix, usize(v0)); push_str(sb, ":\n") }
    if op == 7 { push_str(sb, "  jmp "); emit_label(sb, lepi); push_str(sb, "\n") }
    if op == 6 {
      ## SysV `call`: the Sym value indexes the call side-table; replay the SAME mangler the text path
      ## and the callee's own def use, so the symbol matches byte-for-byte. %rsp is 16-aligned here (the
      ## whole frame is one `subq`; no body pushes), so the call is ABI-correct.
      push_str(sb, "  call ")
      emit_mangled_call(sb, cx.src, IRC_CS[usize(v0)], IRC_CL[usize(v0)], IRC_MS[usize(v0)], IRC_ML[usize(v0)], cx.decls)
      push_str(sb, "\n")
    }
    if op == 8 { push_str(sb, "  jmp "); ir_emit_iralabel(sb, raprefix, usize(v0)); push_str(sb, "\n") }
    if op == 9 {
      ccm := ir_cc_mnem(usize(v1))
      push_str(sb, "  ")
      push_str(sb, ccm)
      push_str(sb, " ")
      ir_emit_iralabel(sb, raprefix, usize(v0))
      push_str(sb, "\n")
    }
    if op == 5 { push_str(sb, "  mulq "); ir_emit_operand(sb, k0, v0); push_str(sb, "\n") }
    if op == 11 { push_str(sb, "  xorq %rdx, %rdx\n  divq "); ir_emit_operand(sb, k0, v0); push_str(sb, "\n") }
    if op == 12 { push_str(sb, "  cqto\n  idivq "); ir_emit_operand(sb, k0, v0); push_str(sb, "\n") }
    if op == 13 { push_str(sb, "  ud2\n") }
    ## LOAD `movq (o1), o0`: o1 holds the (register-resident) source ADDRESS, o0 the destination. Both are
    ## Phys after allocation (a spilled operand was reloaded into a temp just above). Used by the slice-
    ## iteration lowering for the base/len extraction and each element read.
    if op == 15 {
      push_str(sb, "  movq (")
      ir_emit_operand(sb, k1, v1)
      push_str(sb, "), ")
      ir_emit_operand(sb, k0, v0)
      push_str(sb, "\n")
    }
    ## SCALED LOAD `movq (base, index, 8), dst` (op 25): o1 = base (register-resident), o2 = index (register-
    ## resident), o0 = dst. The scale is the constant word-element stride (8). Both address operands are Phys
    ## after allocation (any spilled operand was reloaded into a temp just above). Folds the for-over-Vec/slice/
    ## array element read's per-iteration `mov;imul $8;add;load` address recompute into ONE memory operand.
    if op == 25 {
      push_str(sb, "  movq (")
      ir_emit_operand(sb, k1, v1)             ## base
      push_str(sb, ", ")
      ir_emit_operand(sb, k2, v2)             ## index
      push_str(sb, ", 8), ")
      ir_emit_operand(sb, k0, v0)             ## dst
      push_str(sb, "\n")
    }
    if op == 26 {
      push_str(sb, "  movzbq (")
      ir_emit_operand(sb, k1, v1)             ## base
      push_str(sb, ", ")
      ir_emit_operand(sb, k2, v2)             ## index
      push_str(sb, ", 1), ")
      ir_emit_operand(sb, k0, v0)             ## dst
      push_str(sb, "\n")
    }
    ## SHIFT `<op>q %cl, o0`: o0 is the (register-resident, rmw) value; the count was moved into %rcx by a
    ## preceding `mov %rcx, count`, so %cl (its low byte) is the implicit shift count. `shlq`/`shrq` are
    ## logical; `sarq` is arithmetic (sign-preserving) — selected by the value's signedness at lower time.
    if op == 19 { push_str(sb, "  shlq %cl, "); ir_emit_operand(sb, k0, v0); push_str(sb, "\n") }
    if op == 20 { push_str(sb, "  shrq %cl, "); ir_emit_operand(sb, k0, v0); push_str(sb, "\n") }
    if op == 21 { push_str(sb, "  sarq %cl, "); ir_emit_operand(sb, k0, v0); push_str(sb, "\n") }
    ## self-move elimination: `movq %rX, %rX` (dst phys == src phys after allocation, e.g. a coalesced copy)
    ## is a no-op — skip it. Only op 0 (mov) qualifies; `addq %rX,%rX` etc. are NOT no-ops.
    selfmove := op == 0 and k0 == 2 and k1 == 2 and v0 == v1
    if (op == 0 or op == 1 or op == 2 or op == 3 or op == 4 or op == 16 or op == 17 or op == 18) and selfmove == false {
      opm := ir_op_mnem(op)
      push_str(sb, "  ")
      push_str(sb, opm)
      push_str(sb, " ")
      ir_emit_operand(sb, k1, v1)             ## AT&T: source first
      push_str(sb, ", ")
      ir_emit_operand(sb, k0, v0)             ## destination
      push_str(sb, "\n")
    }
    i += 1
  }
}
## The PARAM index of an admitted slice-param name `[s, n)` (-1 = not a slice param).
ir_slice_param_idx := fn(src : ptr(u8), s : usize, n : usize) -> i64 {
  mut i := 0
  while i < IRSL_N {
    if streq(src, IRSL_S[i], IRSL_L[i], s, n) { return i64(IRSL_PIDX[i]) }
    i += 1
  }
  0 - 1
}
## Keep byte elements separate from ir_native_scalar: widening scalar parameters to u8 would make qword
## arithmetic depend on unspecified high bits. Only the aggregate view iterable uses this zero-ext load.
ir_slice_param_byte := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  es := slice_param_elem_span(src, s, n)
  es.n != 0 and str_at((src + es.s), es.n) == "u8"
}
## The index of an admitted array-local name `[s, n)` (-1 = not an admitted array local).
ir_array_local_idx := fn(src : ptr(u8), s : usize, n : usize) -> i64 {
  mut i := 0
  while i < IRARR_N {
    if streq(src, IRARR_S[i], IRARR_L[i], s, n) { return i64(i) }
    i += 1
  }
  0 - 1
}
ir_vec_local_idx := fn(src : ptr(u8), s : usize, n : usize) -> i64 {
  mut i := 0
  while i < IRVEC_N {
    if streq(src, IRVEC_S[i], IRVEC_L[i], s, n) { return i64(i) }
    i += 1
  }
  0 - 1
}
ir_fr_idx := fn(src : ptr(u8), s : usize, n : usize) -> i64 {
  mut i := 0
  while i < IRFR_N {
    if streq(src, IRFR_S[i], IRFR_L[i], s, n) { return i64(i) }
    i += 1
  }
  0 - 1
}
## Are ALL elements of an ArrayLit compile-time scalar CONSTANTS (Num / BoolLit)? The array-literal init is
## spliced through the TEXT emitter at render, where a non-constant element (a Var / call) would read the
## register-resident local's (unwritten) FRAME slot — garbage. Constants keep the barrier emit self-contained.
ir_arraylit_all_const := fn(ehead : ptr(mut Arg)) -> bool {
  mut g := ehead
  mut ok := true
  while g != 0 {
    ga := deref(arg_p(g))
    match deref(ga.e) {
      Expr::Num(v, s, n) => {}
      Expr::BoolLit(v) => {}
      _ => { ok = false }
    }
    g = ga.next
  }
  ok
}

## Is type `[ts, tl)` a user STRUCT whose EVERY field is a native-width scalar? (A by-ref param of such a
## type is barrier-admissible: `p.f` is always a single scalar word.) An empty / non-struct / any-aggregate-
## field type → false → the whole fn stays on the text path.
ir_all_scalar_struct := fn(src : ptr(u8), decls : ptr(rt::Vec), ts : usize, tl : usize) -> bool {
  bn := base_type_name(src, ts, tl)
  di := struct_decl_of(decls, src, bn.s, bn.n)
  if di < 0 { return false }
  cd := deref(decl_get(decls, usize(di)))
  mut f := cd.fields_head
  mut any := false
  mut ok := true
  while f != 0 {
    fdn := deref(fld_p(f))
    any = true
    if not ir_native_scalar(src, fdn.ts, fdn.tl) { ok = false }
    f = fdn.next
  }
  any and ok
}
## Is type `[ts, tl)` a NON-GENERIC, non-packed, word-layout user STRUCT whose every leaf is a native
## scalar. This is deliberately separate from `ir_all_scalar_struct`: that helper guards the scalar IR
## barrier and only admits direct fields, while aggregate-array equality needs the same proof recursively
## for nested struct fields. A generic instance, byte-layout field, packed nested type, array/tuple/str/
## float/enum/pointer field, or unresolved type returns false, keeping the corresponding comparison loud.
pub index_plain_scalar_struct := fn(src : ptr(u8), decls : ptr(rt::Vec), ts : usize, tl : usize, a : rt::Arena) -> bool {
  bn := base_type_name(src, ts, tl)
  di := struct_decl_of(decls, src, bn.s, bn.n)
  if di < 0 { return false }
  d := deref(decl_get(decls, usize(di)))
  if d.is_generic { return false }
  if is_packed(decls, src, ts, tl) { return false }
  if std_struct_has_byte_layout(decls, src, ts, tl, a) { return false }
  mut f := d.fields_head
  mut any := false
  while f != 0 {
    fd := deref(fld_p(f))
    any = true
    if not ir_native_scalar(src, fd.ts, fd.tl) {
      if not index_plain_scalar_struct(src, decls, fd.ts, fd.tl, a) { return false }
    }
    f = fd.next
  }
  any
}
## The index of struct-param name `[bs, bn)` in the admitted set (-1 = not a struct param).
ir_sp_idx := fn(src : ptr(u8), bs : usize, bn : usize) -> i64 {
  mut i := 0
  while i < IRSP_N {
    if streq(src, IRSP_S[i], IRSP_L[i], bs, bn) { return i64(i) }
    i += 1
  }
  0 - 1
}
## A barrierable field read: base is a `Var` naming an admitted all-scalar-struct param, and `[fs, fl)` is
## a real field of that struct. Both hold ⇒ `p.f` is a scalar the barrier can splice.
ir_field_barrier_ok := fn(src : ptr(u8), decls : ptr(rt::Vec), base : ptr(Expr), fs : usize, fl : usize) -> bool {
  match deref(base) {
    Expr::Var(bs, bn) => {
      idx := ir_sp_idx(src, bs, bn)
      if idx < 0 { return false }
      mar := deref(unchecked bitcast(ptr(rt::Arena), IRP_MARP))
      btn := base_type_name(src, IRSP_TS[usize(idx)], IRSP_TL[usize(idx)])
      struct_field_index(decls, src, btn.s, btn.n, fs, fl, mar) >= 0
    }
    _ => { false }
  }
}

pub ir_native_scalar := fn(src : ptr(u8), ts : usize, tl : usize) -> bool {
  if tl == 0 { return false }
  bn := base_type_name(src, ts, tl)
  t := str_at((src + bn.s), bn.n)
  t == "u64" or t == "usize" or t == "i64" or t == "isize" or t == "bool"
}
ir_bound_has := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  mut i := 0
  while i < IRB_N {
    if streq(src, IRB_S[i], IRB_L[i], s, n) { return true }
    i += 1
  }
  false
}
ir_bound_add := fn(s : usize, n : usize) {
  if IRB_N < 64 { IRB_S[IRB_N] = s; IRB_L[IRB_N] = n; IRB_N = IRB_N + 1 }
}
## PRE-PASS: collect every Assign target name (function-flat locals) into the bound set.
ir_collect_binds := fn(head : ptr(mut Stmt)) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl2, v, nx) => { ir_bound_add(ns, nl2); s = nx }
      Stmt::If(c, th, el, nx) => { ir_collect_binds(th); ir_collect_binds(el); s = nx }
      Stmt::While(c, b, nx) => { ir_collect_binds(b); s = nx }
      ## a RANGE `for i in lo..hi` binds the index `i` (a fresh scalar local) + collects the body's assigns.
      ## (The iterable form `fhi==0` is rejected later by ir_check_stmts; adding the index here is harmless.)
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { ir_bound_add(fns, fnl); ir_collect_binds(fb); s = nx }
      Stmt::Unchecked(b, nx) => { ir_collect_binds(b); s = nx }
      ## `alloc::with(A) { body }`: collect the body's binds (its Vec/cursor locals) and CONTINUE past it.
      Stmt::AllocWith(ae, b, nx) => { ir_collect_binds(b); s = nx }
      ## a bare-call ExprStmt (a Vec `push` side effect) binds nothing — skip it and CONTINUE (do not STOP;
      ## a following scalar Assign like the loop accumulator still needs its target collected).
      Stmt::ExprStmt(e, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      ## an unhandled stmt kind: STOP (`nx` is NOT bound in the `_` arm — reading it would be garbage,
      ## an unbounded-pointer walk). The fn will be rejected by `ir_check_stmts` anyway.
      _ => { s = 0 }
    }
  }
}
## Is name `[s, n)` a MODULE GLOBAL (a `mut NAME := …` runtime global OR a `NAME := const` module const)?
## Such a name is NOT a register-resident local — the scalar-leaf IR treats every Var as a vreg, so a
## fn that reads/writes a module global would read an UNINITIALISED vreg (garbage) and never touch the
## global's memory (a silent miscompile — `IRV_NEXT = IRV_NEXT + 1` was the crash). Reject any fn that
## references one → it falls through to the text path (which addresses the global correctly). This is the
## teeth behind the shape's "every Var a param/local — no module-global — hence LEAF" claim.
ir_name_is_global := fn(decls : ptr(rt::Vec), src : ptr(u8), s : usize, n : usize) -> bool {
  if unchecked bitcast(usize, mut_global_value(decls, src, s, n)) != 0 { return true }
  if unchecked bitcast(usize, module_const_value(decls, src, s, n)) != 0 { return true }
  false
}
## Verify a VALUE-position expression (no comparison allowed here). `unch` = inside an unchecked scope.
ir_check_expr := fn(src : ptr(u8), decls : ptr(rt::Vec), e : ptr(Expr), unch : bool) {
  match deref(e) {
    Expr::Num(v, s, n) => {}
    Expr::BoolLit(v) => {}
    ## a bare Var use: must be a bound param/local, not a global, and NOT a struct param (a struct param is
    ## frame-resident, not a vreg — only its `p.f` field reads are modeled; a bare `p` would read an
    ## uninitialized vreg). A struct-field read is the `Expr::Field` arm below.
    Expr::Var(s, n) => { if (not ir_bound_has(src, s, n)) or ir_name_is_global(decls, src, s, n) or ir_sp_idx(src, s, n) >= 0 or ir_slice_param_idx(src, s, n) >= 0 or ir_array_local_idx(src, s, n) >= 0 or ir_vec_local_idx(src, s, n) >= 0 or ir_fr_idx(src, s, n) >= 0 { IRP_OK = false } }
    Expr::Unchecked(inner) => { ir_check_expr(src, decls, inner, true) }
    Expr::Bitcast(inner, _bcs, _bcl) => { ir_check_expr(src, decls, inner, true) }
    Expr::Bin(op, l, r) => {
      if op == 16 or op == 17 or op == 18 {
        ## CHECKED `+`/`-`/`*` are now MODELLED (op + inline overflow guard), so admitted whether checked
        ## or `unchecked` — the emit reproduces the text path's `jno`/`jnc ... ud2` guard exactly. A CHECKED
        ## one (not `unch`) emits an extra guard (jcc + ud2 + CONT label), budgeted via IRP_NCHK.
        IRP_NBIN = IRP_NBIN + 1
        if not unch { IRP_NCHK = IRP_NCHK + 1 }
        ir_check_expr(src, decls, l, unch)
        ir_check_expr(src, decls, r, unch)
      } else if op == 19 or op == 29 {
        ## `/`/`%` (checked OR `unchecked`): admitted either way. On x86 the CHECKED div-by-zero and signed
        ## INT_MIN/-1 overflow traps are delivered by the HARDWARE `#DE` (→ SIGFPE, exit 136 ≥ 128, an I11
        ## trap) from the plain `divq`/`idivq` the reference (text) path also emits for a checked division —
        ## no software guard exists there to reproduce, so the IR's plain `divq`/`idivq` (ir_lower_bin op
        ## 19/29) already matches the reference semantics for both modes.
        IRP_NBIN = IRP_NBIN + 1
        ir_check_expr(src, decls, l, unch)
        ir_check_expr(src, decls, r, unch)
      } else if op == 34 or op == 35 or op == 36 {
        ## bitwise `&`/`|`/`^`: a plain 2-operand op (no overflow, no clobber) — admit checked or unchecked.
        IRP_NBIN = IRP_NBIN + 1
        ir_check_expr(src, decls, l, unch)
        ir_check_expr(src, decls, r, unch)
      } else {
        IRP_OK = false                              ## a comparison / bool op in value position → reject
      }
    }
    Expr::Call(cs, cl, na, ah) => {
      ## Native-width `u64(x)` is an identity over the IR's 64-bit integer word. Keep the operand walk so
      ## globals, aggregate values, calls, fields, and other unsupported shapes remain rejected normally.
      if str_at((src + cs), cl) == "u64" {
        if na != 1 { IRP_OK = false }
        else if ir_u64_identity_arg(deref(arg_p(ah)).e) { ir_check_expr(src, decls, deref(arg_p(ah)).e, unch) }
        else { IRP_OK = false }
      } else if str_at((src + cs), cl) == "usize" {
        ## Only the exact native-alias wrapper over the already-admitted u64 leaf is identity-safe here.
        if na != 1 { IRP_OK = false }
        else if ir_usize_identity_arg(src, deref(arg_p(ah)).e) { ir_check_expr(src, decls, deref(arg_p(ah)).e, unch) }
        else { IRP_OK = false }
      } else { ir_check_call(src, decls, cs, cl, na, ah, unch) }
    }
    ## a SCALAR field read of a by-ref struct param → a BARRIER (text emit_gas). Admit iff the base names an
    ## admitted all-scalar-struct param and the field exists; anything else (a field of a non-param, a nested
    ## field path, a struct-typed field) → reject → text path.
    Expr::Field(fb, ffs, ffl) => {
      if ir_field_barrier_ok(src, decls, fb, ffs, ffl) { IRP_NBARR = IRP_NBARR + 1 } else { IRP_OK = false }
    }
    _ => { IRP_OK = false }
  }
}
## Verify a modeled CALL: the callee must resolve to a UNIQUE, NON-generic, NON-variadic, NON-overloaded,
## NON-extern plain fn (kind 1) with a native-scalar return and all params native-scalar plain-`in`, arity
## == nargs, nargs ≤ 6 — and NOT a scalar conversion `T(x)` (which emits no `call`). Anything else falls to
## the text path. Args are checked as value exprs. Sets IRP_OK = false on any mismatch (defence in depth:
## `emit_fn_ir` also fails loud, never silently miscompiles).
ir_check_call := fn(src : ptr(u8), decls : ptr(rt::Vec), cs : usize, cl : usize, na : usize, ah : ptr(mut Arg), unch : bool) {
  ## BIT SHIFT `shl`/`shr(v, n)` (OP-6): MODELLED by `ir_lower_call` as opcodes 19/20/21 (no real `call`),
  ## so admit it here BEFORE the callee-resolution reject below (a shift resolves to no decl → would be
  ## rejected as an intrinsic). Requires exactly 2 args, both admissible value exprs (a non-scalar / global
  ## / struct-param arg is rejected by `ir_check_expr`). Budget: reuse a Bin's allowance (≤2 vregs, ≤4 base
  ## insts: mov t + mov %rcx + shift + slack); a CHECKED shift adds the over-width guard (cmp+jb+ud2+CONT
  ## label) budgeted via IRP_NCHK exactly like a checked arith bin. `rotl`/`rotr` are NOT modelled — they
  ## fall through to the callee-resolution reject (intrinsic → text path).
  cnm := str_at((src + cs), cl)
  if cnm == "shl" or cnm == "shr" {
    if na != 2 { IRP_OK = false }
    IRP_NBIN = IRP_NBIN + 1
    if not unch { IRP_NCHK = IRP_NCHK + 1 }
    mut gs := ah
    while gs != 0 { gas := deref(arg_p(gs)); ir_check_expr(src, decls, gas.e, unch); gs = gas.next }
    return
  }
  ## a scalar conversion `T(x)` (int/float) is NOT a function call (no `call` inst) → reject.
  if conv_kind(str_at((src + cs), cl)) >= 0 { IRP_OK = false }
  if na > 6 { IRP_OK = false }
  idx := callee_decl_idx(decls, src, cs, cl, IRP_MS, IRP_ML)
  if idx < 0 {
    IRP_OK = false                                  ## unresolved / intrinsic (str_at/bitcast/…) → reject
  } else {
    cd := deref(decl_get(decls, usize(idx)))
    if cd.kind != 1 { IRP_OK = false }              ## plain fn only (not a syscall-fn / struct / enum)
    if cd.is_generic { IRP_OK = false }
    if extern_symbol(src, cd.name_start, cd.name_len).n != 0 { IRP_OK = false }   ## keep to internal fns
    if overload_set_count(decls, src, cd.name_start, cd.name_len, cd.mod_start, cd.mod_len) >= 2 { IRP_OK = false }
    if not ir_native_scalar(src, cd.ret_ts, cd.ret_tl) { IRP_OK = false }         ## scalar return
    if cd.arity != na { IRP_OK = false }
    mut pp := cd.params_head
    while pp != 0 {
      pm := deref(param_p(pp))
      if pm.pmode != 0 { IRP_OK = false }           ## no out / in out (by-ref)
      if pm.tl == 2 and str_at((src + pm.ts), 2) == ".." { IRP_OK = false }   ## no comptime-variadic
      if not ir_native_scalar(src, pm.ts, pm.tl) { IRP_OK = false }           ## all params native scalar
      pp = pm.next
    }
    IRP_NCALL = IRP_NCALL + 1
    IRP_NCALLARG = IRP_NCALLARG + na
  }
  ## check every arg as a value expr (safe to walk even if the callee mismatched).
  mut g := ah
  while g != 0 {
    ga := deref(arg_p(g))
    ir_check_expr(src, decls, ga.e, unch)
    g = ga.next
  }
}
## Verify a CONDITION expression (a top-level comparison, or a plain scalar/bool value).
ir_check_cond := fn(src : ptr(u8), decls : ptr(rt::Vec), c : ptr(Expr), unch : bool) {
  match deref(c) {
    Expr::Unchecked(inner) => { ir_check_cond(src, decls, inner, true) }
    Expr::Bitcast(inner, _bcs, _bcl) => { ir_check_cond(src, decls, inner, true) }
    Expr::Bin(op, l, r) => {
      if op == 20 or op == 24 or op == 25 or op == 26 or op == 27 or op == 28 {
        IRP_NBIN = IRP_NBIN + 1
        ir_check_expr(src, decls, l, unch)
        ir_check_expr(src, decls, r, unch)
      } else {
        IRP_OK = false                              ## and/or/not not modelled
      }
    }
    Expr::Var(s, n) => { if (not ir_bound_has(src, s, n)) or ir_name_is_global(decls, src, s, n) or ir_sp_idx(src, s, n) >= 0 or ir_slice_param_idx(src, s, n) >= 0 or ir_array_local_idx(src, s, n) >= 0 or ir_vec_local_idx(src, s, n) >= 0 or ir_fr_idx(src, s, n) >= 0 { IRP_OK = false } }
    Expr::BoolLit(v) => {}
    Expr::Num(v, s, n) => {}
    _ => { IRP_OK = false }
  }
}
ir_check_stmts := fn(src : ptr(u8), decls : ptr(rt::Vec), head : ptr(mut Stmt), unch : bool) {
  mut s := head
  while s != 0 {
    IRP_NSTMT = IRP_NSTMT + 1
    st := deref(stmt_p(Stmt, s))
    match st {
      ## an Assign whose TARGET is a module global is a global WRITE (not a local binding) → reject: the
      ## IR would update a vreg, never the global's `.data` word.
      Stmt::Assign(ns, nl2, v, nx) => {
        if array_lit_info(v).is_a {
          ## an inline SCALAR array local init `ys : [<native-scalar>; N] = [<const>, …]` (COMMIT 6d) → the
          ## statement barrier + a frame-resident array iterated by `for x in ys`. Admit iff: the target is a
          ## real local (not a global / struct param); its declared annotation is `[T; N]` with N == the
          ## literal's element count (`parse_arr_len > 0` also excludes a scalar TUPLE — also an ArrayLit, but
          ## with no `; N` annotation); the element kind is scalar-word (eek 0, stride 1); and every element
          ## is a compile-time constant (Num/BoolLit — the barrier's text emit must not read a register local).
          ai := array_lit_info(v)
          mar := deref(unchecked bitcast(ptr(rt::Arena), IRP_MARP))
          lts := local_type_span(src, ns, nl2)
          aln := parse_arr_len(src, lts.s, lts.n)
          aei := arr_elem_info(ai.ehead, src, decls, mar, unchecked bitcast(ptr(SVec), 0))
          okarr := (not ir_name_is_global(decls, src, ns, nl2)) and ir_sp_idx(src, ns, nl2) < 0 and aln > 0 and aln == ai.nel and aei.eek == 0 and aei.stride == 1 and ir_arraylit_all_const(ai.ehead) and IRARR_N < 4
          if okarr {
            IRARR_S[IRARR_N] = ns
            IRARR_L[IRARR_N] = nl2
            IRARR_N = IRARR_N + 1
            IRP_NARRINIT = IRP_NARRINIT + 1
          } else { IRP_OK = false }
          s = nx
        } else if ir_is_call_rhs(v) and ir_is_vecbuild_call(src, decls, v) {
          ## a Vec-build assign (`r := mmap(…)`, `ar := arena_over(…)`, `v := with_capacity(…)`) → a GENERAL
          ## STATEMENT BARRIER (text-spliced into FRAME slots; the aggregate stays in memory). WHITELISTED:
          ## only a syscall / Vec- or Arena-returning / `push` call reaches here, so NO fmt/display/print/general
          ## call becomes a barrier. Admit iff the target is a real local; the side-tables have room. Barriers
          ## may now FOLLOW modeled statements (barriers-not-first) — a modeled scalar the RHS reads is synced to
          ## its slot at emit (counted into IRP_NSYNC here). A Vec-RETURNING call additionally records `v` as the
          ## iterable Vec local. RHS stays TEXT. The target is recorded frame-resident (IRFR) → a modeled read
          ## of it rejects. Barrier statements cost ~1 IR inst (op-24), not 3× a modeled stmt → cancel the +1.
          okg := (not ir_name_is_global(decls, src, ns, nl2)) and ir_sp_idx(src, ns, nl2) < 0 and IRP_NGBAR < 16 and IRFR_N < 8
          if okg {
            IRFR_S[IRFR_N] = ns
            IRFR_L[IRFR_N] = nl2
            IRFR_N = IRFR_N + 1
            IRP_NGBAR = IRP_NGBAR + 1
            IRP_NSTMT = IRP_NSTMT - 1
            ir_count_barrier_syncs(src, decls, s)
            if ir_call_returns_vec(src, decls, v) and IRVEC_N < 4 {
              IRVEC_S[IRVEC_N] = ns
              IRVEC_L[IRVEC_N] = nl2
              IRVEC_N = IRVEC_N + 1
            }
          } else { IRP_OK = false }
          s = nx
        } else {
          if ir_name_is_global(decls, src, ns, nl2) or ir_sp_idx(src, ns, nl2) >= 0 { IRP_OK = false }
          IRP_SAWMODEL = true
          ir_check_expr(src, decls, v, unch)
          s = nx
        }
      }
      ## a bare-call ExprStmt → a GENERAL STATEMENT BARRIER (side effect only, result discarded): a Vec-build
      ## (`v.push(x).expect(…)`) OR the trailing `fmt::print(…)` of the result. Admitted for ANY call (so it is
      ## NO LONGER whitelisted here) — the VEC-SHAPE final gate is the sole narrowing: only an arity-0 fn that
      ## also register-allocates a `for x in <Vec local>` survives, so NO fmt/display/print/io helper fn (all
      ## take the value-to-format as a PARAM → arity != 0) is ever admitted. A non-call ExprStmt cannot be
      ## modeled → reject. A modeled scalar the call reads (the printed `sum`) is synced to its slot at emit.
      Stmt::ExprStmt(e, nx) => {
        if ir_is_call_rhs(e) and IRP_NGBAR < 16 {
          IRP_NGBAR = IRP_NGBAR + 1
          IRP_NSTMT = IRP_NSTMT - 1
          ir_count_barrier_syncs(src, decls, s)
        } else { IRP_OK = false }
        s = nx
      }
      Stmt::If(c, th, el, nx) => {
        IRP_SAWMODEL = true
        IRP_NCTRL = IRP_NCTRL + 1
        ir_check_cond(src, decls, c, unch)
        ir_check_stmts(src, decls, th, unch)
        ir_check_stmts(src, decls, el, unch)
        s = nx
      }
      Stmt::While(c, b, nx) => {
        if ir_stmts_have_vecbuild(src, decls, b) {
          ## a Vec-BUILD `while` (`while i < n { v.push(…) }`) → the WHOLE loop is a GENERAL BARRIER (text-
          ## spliced verbatim). Its cursor/pushes stay frame-resident; a modeled scalar it reads (the cursor
          ## `i` set above) is synced to its slot at emit (counted into IRP_NSYNC). Gated by the vec-shape
          ## final gate like every barrier. Costs ~1 IR inst (op-24), not 3× a modeled stmt → cancel the +1.
          if IRP_NGBAR < 16 {
            IRP_NGBAR = IRP_NGBAR + 1
            IRP_NSTMT = IRP_NSTMT - 1
            ir_count_barrier_syncs(src, decls, s)
          } else { IRP_OK = false }
        } else {
          IRP_SAWMODEL = true
          IRP_NCTRL = IRP_NCTRL + 1
          ir_check_cond(src, decls, c, unch)
          ir_check_stmts(src, decls, b, unch)
        }
        s = nx
      }
      ## `alloc::with(A) { body }` (MEM-5): a compile-time allocator scope (the driver already elided the
      ## body calls' allocator args). Recurse into the body — its build barriers + register-allocated
      ## `for x in v` are checked exactly as at the top level.
      Stmt::AllocWith(ae, b, nx) => { ir_check_stmts(src, decls, b, unch); s = nx }
      ## RANGE `for i in lo..hi { body }` (`fhi != 0`): the counted-loop form. Admit iff its bounds are
      ## native-scalar value exprs and its body stays within the whitelist — the loop lowers to an index
      ## vreg + a header cmp/jcc + a `+= 1` back-edge (a loop-carried interval the allocator handles). The
      ## ITERABLE / Vec form (`fhi == 0`: `for x in <collection>`) models an aggregate iterand and MUST stay
      ## on the text path → reject. Budget: +1 NCTRL (2 labels: header + done) and +1 NBIN (the synthetic
      ## cmp + the `+= 1` increment + the index vreg — a conservative inst/vreg allowance).
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        IRP_SAWMODEL = true
        if unchecked bitcast(usize, fhi) == 0 {
          ## ITERABLE `for x in s` (COMMIT 6c + P3-RA-AGG): admit ONLY when `s` names an admitted
          ## `Slice(native-scalar)` or bounded `Slice(u8)` PARAM. The byte case has a dedicated zero-ext
          ## load. Any other iterable (Vec / array / a non-slice-param) stays on the text path.
          fv := var_name_span(flo)
          if fv.n != 0 and ir_slice_param_idx(src, fv.s, fv.n) >= 0 {
            IRP_NSLFOR = IRP_NSLFOR + 1
            ir_bound_add(fns, fnl)                          ## the loop element var is a fresh scalar local
            ir_check_stmts(src, decls, fb, unch)
            s = nx
          } else if fv.n != 0 and ir_array_local_idx(src, fv.s, fv.n) >= 0 {
            ## `for x in <inline scalar array local>` (COMMIT 6d): the array is frame-resident; the element
            ## base is a LEA-SLOT and each element loads through an indexed address (budget: IRP_NARRFOR).
            IRP_NARRFOR = IRP_NARRFOR + 1
            ir_bound_add(fns, fnl)                          ## the loop element var is a fresh scalar local
            ir_check_stmts(src, decls, fb, unch)
            s = nx
          } else if fv.n != 0 and ir_vec_local_idx(src, fv.s, fv.n) >= 0 {
            ## `for x in <arena-backed Vec LOCAL>` (Vec-LOCAL increment): the Vec is frame-resident (built by
            ## the general barriers); base = arena.base + idx and len are hoisted ONCE into vregs, then each
            ## element loads through a register-held address (budget: IRP_NVECFOR).
            IRP_NVECFOR = IRP_NVECFOR + 1
            ir_bound_add(fns, fnl)                          ## the loop element var is a fresh scalar local
            ir_check_stmts(src, decls, fb, unch)
            s = nx
          } else { IRP_OK = false; s = 0 }
        }
        else {
          IRP_NCTRL = IRP_NCTRL + 1
          IRP_NBIN = IRP_NBIN + 1
          ir_bound_add(fns, fnl)                          ## the loop index is a fresh scalar local
          ir_check_expr(src, decls, flo, unch)
          ir_check_expr(src, decls, fhi, unch)
          ir_check_stmts(src, decls, fb, unch)
          s = nx
        }
      }
      Stmt::Return(rv, nx) => { IRP_SAWMODEL = true; ir_check_expr(src, decls, rv, unch); s = nx }
      Stmt::Unchecked(b, nx) => { ir_check_stmts(src, decls, b, true); s = nx }
      ## an unhandled stmt kind → reject + STOP (`nx` is NOT bound in the `_` arm; walking it is garbage).
      _ => { IRP_OK = false; s = 0 }
    }
  }
}
pub is_scalar_leaf_shape := fn(d : Decl, p : ptr(PCtx)) -> bool {
  if d.kind != 1 { return false }                   ## a plain fn only (not struct/enum/test/syscall)
  if d.is_generic { return false }
  if p.inst { return false }
  if d.name_len == 0 { return false }               ## not a lifted lambda
  if fn_is_naked(p.src, d.name_start, d.name_len) { return false }
  if export_name(p.src, d.name_start, d.name_len).n != 0 { return false }
  if overload_set_count(p.decls, p.src, d.name_start, d.name_len, d.mod_start, d.mod_len) >= 2 { return false }
  if fn_returns_sret(d, p.decls, p.src, deref(p.mar)) or fn_returns_enum_sret(d, p.decls, p.src, deref(p.mar)) { return false }
  if not ir_native_scalar(p.src, d.ret_ts, d.ret_tl) { return false }   ## scalar return, real tail value
  if expr_is_no_tail(d.value) { return false }
  if d.arity > 6 { return false }
  ## params: each is either a native-scalar plain-`in` param (→ a vreg), OR a by-ref STRUCT param whose
  ## every field is native-scalar (→ addressed through the text slot map; its scalar field reads route
  ## through a BARRIER). Anything else (out / in-out, array, slice, mixed-field struct) → text path.
  IRSP_N = 0
  IRSL_N = 0
  IRARR_N = 0
  mut pp := d.params_head
  mut ppidx := 0
  while pp != 0 {
    pm := deref(param_p(pp))
    if pm.pmode != 0 { return false }
    if not ir_native_scalar(p.src, pm.ts, pm.tl) {
      ## a by-ref STRUCT param (all-scalar fields → barriered field reads) OR a `Slice(native-scalar-word)` /
      ## bounded `Slice(u8)` PARAM (iterated by `for x in s`). A byte slice is not a native scalar ABI param;
      ## it is admitted only as an aggregate view iterable with the dedicated zero-ext load.
      slelem := slice_param_elem_span(p.src, pm.ns, pm.nl)
      slbase := base_type_name(p.src, pm.ts, pm.tl)
      is_slice := slelem.n != 0 and str_at((p.src + slbase.s), slbase.n) == "Slice" and (ir_native_scalar(p.src, slelem.s, slelem.n) or str_at((p.src + slelem.s), slelem.n) == "u8")
      if is_slice {
        if IRSL_N >= 4 { return false }
        IRSL_S[IRSL_N] = pm.ns
        IRSL_L[IRSL_N] = pm.nl
        IRSL_PIDX[IRSL_N] = ppidx
        IRSL_N = IRSL_N + 1
      } else {
        if not ir_all_scalar_struct(p.src, p.decls, pm.ts, pm.tl) { return false }
        if IRSP_N >= 8 { return false }
        IRSP_S[IRSP_N] = pm.ns
        IRSP_L[IRSP_N] = pm.nl
        IRSP_TS[IRSP_N] = pm.ts
        IRSP_TL[IRSP_N] = pm.tl
        IRSP_N = IRSP_N + 1
      }
    }
    ppidx = ppidx + 1
    pp = pm.next
  }
  ## body walk.
  IRB_N = 0
  IRP_OK = true
  IRP_NBIN = 0
  IRP_NCHK = 0
  IRP_NCTRL = 0
  IRP_NSTMT = 0
  IRP_NCALL = 0
  IRP_NCALLARG = 0
  IRP_NSLFOR = 0
  IRP_NARRFOR = 0
  IRP_NARRINIT = 0
  IRP_NBARR = 0
  IRP_NVECFOR = 0
  IRP_NGBAR = 0
  IRP_NSYNC = 0
  IRP_SAWMODEL = false
  IRVEC_N = 0
  IRFR_N = 0
  IRP_MARP = unchecked bitcast(usize, p.mar)
  IRP_MS = d.mod_start
  IRP_ML = d.mod_len
  mut qp := d.params_head
  while qp != 0 { qpm := deref(param_p(qp)); ir_bound_add(qpm.ns, qpm.nl); qp = qpm.next }
  ir_collect_binds(d.body_stmts)
  ir_check_stmts(p.src, p.decls, d.body_stmts, false)
  ir_check_expr(p.src, p.decls, d.value, false)
  if not IRP_OK { return false }
  ## conservative capacity budget = a SOUND upper bound on the emitted IR (allocator caps: 32 vregs,
  ## 64 insts, 16 labels). Each Bin ≤ 4 base insts (unchecked/div: mov rax,L + to_reg + op + result);
  ## a CHECKED arith bin adds ≤ 4 more (unsigned `*`: mov rax,L + mul + jnc + ud2 + mov result vs the
  ## imul it replaces ≈ +4; `+`/`-`: jcc + ud2 ≈ +2) — budgeted per checked bin via IRP_NCHK, so an
  ## UNCHECKED-only fn keeps the tight base estimate (is_prime stayed admitted). Each stmt ≤ 3 insts of
  ## control overhead (already counted in IRP_NSTMT). Each Bin ≤ 2 fresh vregs. Labels: 2 per if/while,
  ## plus 1 per CHECKED bin (its guard CONT label). Each CALL: 1 result vreg; (nargs arg-movs + call +
  ## result-mov) insts; no labels; and it consumes one call side-table slot (cap 32) + up to nargs arg-stack
  ## slots (cap 32) — both bounded well under the inst budget below.
  ## Each BARRIER (field read): +1 result vreg, +2 insts (the op-14 clobber + the `mov result,%rax`); its
  ## spliced GAS is TEXT (not IR insts) so it costs no further IR budget; it consumes one barrier side-table
  ## slot (cap 16). The barrier's clobber forces every live-across scalar to a spill slot — accounted for by
  ## the allocator's own spill-slot count, not this budget.
  ## Each slice-`for` (COMMIT 6c): ≤6 fresh vregs (P/base/tL/len/idx/addr), ≤16 insts (6 setup: slot-load +
  ## base-load + tL-mov + tL+8 + len-load + idx=0; ~10 loop: header label + cmp + jge + addr mov/imul/add +
  ## element load + `idx += 1` + back-jmp + done label — the body's own stmts are already counted in NSTMT),
  ## and 2 labels (header + done).
  ## Each ARRAY-`for` (COMMIT 6d): ≤6 fresh vregs (base/len/idx/addr + slack; the element var `x` is a named
  ## vreg already counted in IRB_N), ≤16 insts (base LEA + len-immediate + idx=0 setup; ~header cmp/jge +
  ## addr mov/imul/add + element load + `idx += 1` + back-jmp + 2 labels — the body's stmts are in NSTMT),
  ## and 2 labels (header + done). Each ARRAY INIT (statement barrier): +2 insts (the op-23 clobber + slack);
  ## its spliced GAS is TEXT (no IR insts) and it consumes one stmt-barrier side-table slot (cap 8).
  ## Each Vec-`for` (Vec-LOCAL increment): ≤8 fresh vregs (arenaP/base/vidx/len/idx/addr + slack; the element
  ## var `x` is a named vreg already in IRB_N), ≤16 insts, 2 labels. A GENERAL BARRIER emits ONE IR inst (the
  ## op-24 clobber); its `3 * IRP_NSTMT` term already over-covers that (no separate NGBAR inst term — double-
  ## counting it overflowed the budget for the Vec shape).
  ## Each GENERAL BARRIER = exactly ONE op-24 IR inst (its spliced GAS is TEXT, not IR insts); a barrier
  ## statement's `IRP_NSTMT` +1 was CANCELLED in its arm, so it is NOT triple-counted. `IRP_NSYNC` is the
  ## (over-estimated) modeled-scalar sync stores emitted before the barriers (`movq %vreg, slot(%rbp)`).
  vregs := IRB_N + 2 * IRP_NBIN + IRP_NCALL + IRP_NBARR + 6 * IRP_NSLFOR + 6 * IRP_NARRFOR + 8 * IRP_NVECFOR + 2
  insts := d.arity + 4 * IRP_NBIN + 4 * IRP_NCHK + 3 * IRP_NSTMT + 2 * IRP_NCALL + IRP_NCALLARG + 2 * IRP_NBARR + 16 * IRP_NSLFOR + 16 * IRP_NARRFOR + 16 * IRP_NVECFOR + 2 * IRP_NARRINIT + 2 * IRP_NGBAR + IRP_NSYNC + 6
  labels := 2 * IRP_NCTRL + IRP_NCHK + 2 * IRP_NSLFOR + 2 * IRP_NARRFOR + 2 * IRP_NVECFOR + 2
  if vregs >= 30 { return false }
  if insts >= 60 { return false }
  if labels >= 15 { return false }
  if IRP_NCALL >= 30 { return false }        ## call side-table capacity (32)
  if IRP_NBARR >= 15 { return false }        ## barrier side-table capacity (16)
  if IRP_NARRINIT >= 8 { return false }      ## stmt-barrier side-table capacity (8)
  if IRP_NGBAR >= 16 { return false }        ## general stmt-barrier side-table capacity (16)
  ## VEC-SHAPE GATE (the primary narrowing): general barriers are admitted ONLY in a fn that ALSO has a
  ## register-allocated `for x in <Vec local>`. No fmt/display/print/io/general fn builds AND iterates a Vec
  ## LOCAL, so none is ever admitted to the barrier path. A barrier fn must also have NO params (a scalar param
  ## is a vreg, not frame-resident, so a barrier's `emit_gas` reading a param would read a stale frame slot;
  ## `main`/`_start` take none). Non-barrier scalar-leaf fns are unaffected (IRP_NGBAR == 0).
  if IRP_NGBAR > 0 and (IRP_NVECFOR == 0 or IRVEC_N == 0 or d.arity != 0) { return false }
  true
}
