## selfhost::regalloc — a DORMANT virtual-register instruction-IR + linear-scan register allocator
## (ROADMAP §0 "register allocator", COMMIT 1). Ported from the frozen Rust ancestor's
## `crates/alatyr-lower/src/regalloc.rs` — that ancestor is not published; `seed/VERSION` records the
## lineage.
##
## STATUS: standalone and **NOT wired into emission**. The x86 backend (`lower.al`) is still a pure
## text stack-machine; this module builds + tests the allocator over hand-built instruction streams in
## isolation. Because `emit_gas`/`emit_fn` never call anything here, the emitted GAS for the whole
## `src/`+`lib/` tree is byte-identical → the TOOL-1 fixpoint stays green with NO reseed. Wiring the
## allocator into `emit_fn` is a LATER commit.
##
## Reachability: `cli::run_cli` exposes a `selftest-regalloc` mode that runs `selftest` (the 6 ported
## unit cases). Reachable code is fixpoint-safe as long as it does not change EXISTING emission and is
## DETERMINISTIC — which this is: fixed register-pick order, array iteration only, no hash-map order
## dependence. (Determinism is mandatory; non-determinism would make Stage1 != Stage2 and break fixpoint.)
##
## LEAN-LOWER IDIOM (path B): no generics / no hash maps. The IR + allocator state live in fixed BSS
## module arrays (the `A64_INST_*` / `_sdc_*` idiom in aarch64.al / lower_layout.al) addressed as
## struct-of-arrays; liveness is flat 0/1 arrays; every loop is a `while` over a bounded index. All
## ops the self-host lower already emits, compiled identically by seed and Stage1.
##
## ---- Encoding legend --------------------------------------------------------------------------------
## Operand KIND:  0=None  1=Imm  2=Phys(reg id)  3=VReg(id)  4=Sym(label id)  5=Slot(frame disp)
## Instruction OP: 0=mov 1=add 2=sub 3=imul 4=cmp 5=mul(1-op, clobbers rax:rdx) 6=call 7=ret
##                 8=jmp(uncond) 9=jcc(cond) 10=label 11=udiv 12=idiv(both clobber rax:rdx) 13=ud2(trap)
##                 14=BARRIER (an unmodeled construct emitted via the TEXT emitter at render — a FULL
##                    register clobber: every allocatable reg is BUSY over it, so a live-across vreg spills)
##                 15=load `movq (o1), o0` (dst o0 written, address base o1 read; no clobber) — a memory
##                    LOAD through a register-held address (the slice-iteration element / base+len reads)
##                 16=and 17=or 18=xor (2-operand `<op>q o1, o0`; dst o0 read-modify-write, o1 read; no
##                    clobber) — the bitwise binops `&`/`|`/`^` on the scalar-leaf path
##                 19=shl 20=shr 21=sar (1-operand variable shift `<op>q %cl, o0`; dst o0 read-modify-
##                    write, count implicit in %cl → %rcx marked BUSY so no live value parks there) — the
##                    bit-shift operation-fns `shl`/`shr`(logical)/`sar`(arithmetic) on the scalar-leaf path
##                 22=LEA-SLOT `leaq disp(%rbp), o0` (dst o0 WRITTEN, no read, no clobber; the frame
##                    displacement rides o1 as an Imm) — materializes a frame ADDRESS into a vreg (the base
##                    `&element0` of an inline array local). NOT a load; the element is read with op 15.
##                 23=STMT-BARRIER (a STATEMENT the scalar-leaf IR does NOT model — an inline-array-literal
##                    INIT — emitted via the TEXT statement emitter at render, producing NO %rax result.
##                    Like op 14 it is a FULL register clobber, so every live-across scalar spills; o0 = Sym id)
##                 25=SCALED LOAD `movq (o1, o2, 8), o0` — the ONLY 3-operand op: o0=dst WRITTEN, o1=base
##                    READ, o2=index READ; the element scale is hardcoded 8 (a word element; a non-8 stride
##                    stays on the mul/add/load triple). Folds the per-iteration `mov;imul $8;add;load` address
##                    recompute of the for-over-Vec/slice/array element read into ONE x86 scaled-index memory
##                    operand. Uses a THIRD operand column (O2K/O2V) that is None(kind 0) for every other op.
##                 26=BYTE SCALED LOAD `movzbq (o1, o2, 1), o0` — the bounded Slice(u8) sibling: same operand
##                    roles as op 25, but a zero-extending byte load. Never use a qword load for byte data.
## Register ids:  0 rax  1 rbx  2 rcx  3 rdx  4 rsi  5 rdi  6 rbp  7 rsp
##                8 r8  9 r9  10 r10  11 r11  12 r12  13 r13  14 r14  15 r15
## Operand ROLE:  0=Read  1=Write  2=ReadWrite  (destination-first, matching the Rust `InsnModel`)
## -----------------------------------------------------------------------------------------------------

## ===== The instruction IR (struct-of-arrays; `RA_N` live entries) ====================================
## Capacity 64 instructions / 32 vregs / 16 physicals — a dormant self-test over tiny hand-built streams
## (the largest case is 11 instructions); sized to the 512-element BSS scale the tree already uses.
mut RA_OP  : [usize; 64] = [0; 64]
mut RA_O0K : [usize; 64] = [0; 64]
mut RA_O0V : [i64; 64]   = [0; 64]
mut RA_O1K : [usize; 64] = [0; 64]
mut RA_O1V : [i64; 64]   = [0; 64]
mut RA_O2K : [usize; 64] = [0; 64]   ## third operand (the scaled-load INDEX); kind None(0) for every other op
mut RA_O2V : [i64; 64]   = [0; 64]
mut RA_N := 0

## Rewritten output stream (`RA_OUT_N` live entries) — every VReg replaced by a Phys or a spill temp
## (with reload/store inserted around a spilled operand). No VReg kind survives here (`ra_verify_no_vreg`).
mut OUT_OP  : [usize; 64] = [0; 64]
mut OUT_O0K : [usize; 64] = [0; 64]
mut OUT_O0V : [i64; 64]   = [0; 64]
mut OUT_O1K : [usize; 64] = [0; 64]
mut OUT_O1V : [i64; 64]   = [0; 64]
mut OUT_O2K : [usize; 64] = [0; 64]   ## third output operand (the scaled-load INDEX); None(0) for every other op
mut OUT_O2V : [i64; 64]   = [0; 64]
mut RA_OUT_N := 0

## ===== Allocator config (per run) ====================================================================
mut RA_ALLOC  : [usize; 32] = [0; 32]   ## allocatable physical reg ids, in preference order
mut RA_NALLOC := 0
mut RA_CALLER : [usize; 32] = [0; 32]   ## caller-saved reg ids (clobbered by a `call`)
mut RA_NCALLER := 0
mut RA_ST0 := 10                        ## two reserved spill reload temps (default r10, r11)
mut RA_ST1 := 11

## COMMIT 2 emit-driver state: `RA_OVF` = the IR overflowed the 64-instruction capacity (fail-loud in
## the caller). Declared with the other module globals (top-of-module block).
mut RA_OVF : usize = 0
mut RA_SPILL_BASE := -64                ## frame disp of the first 8-byte spill slot (grows downward)

## ===== Liveness / interval / busy state ==============================================================
## BITMASK representation (one word PER INSTRUCTION; bit v = vreg v, bit r = phys reg r) so the FULL
## 64-instruction capacity fits in tiny `[usize; 64]` arrays — a flat `[instr*32+vreg]` layout would need
## 2048 entries whose `[0; 2048]` initializer overflows the seed's compile-time arena. vreg < 32 and
## reg < 16 both fit a 64-bit word. Under COMMIT 2 real fns reach ~30+ insts (the self-test's ≤11 also fit).
mut LIVEIN  : [usize; 64] = [0; 64]   ## bit v set = vreg v live-in at instr i (instr < 64)
mut LIVEOUT : [usize; 64] = [0; 64]   ## bit v set = vreg v live-out at instr i
mut BUSY    : [usize; 64] = [0; 64]   ## bit r set = phys reg r busy at instr i (pre-colored + clobber)
mut LABELIDX : [i64; 16]  = [0; 16]       ## label id -> instruction index (-1 = unresolved; ids < 16)

mut IV_PRESENT : [usize; 32] = [0; 32]    ## vreg has a live interval
mut IV_FIRST   : [i64; 32]   = [0; 32]    ## interval [first, last] inclusive
mut IV_LAST    : [i64; 32]   = [0; 32]

mut ASSIGN : [i64; 32] = [0; 32]          ## vreg -> phys reg id (-1 = spilled / unassigned)
mut SPILL  : [i64; 32] = [0; 32]          ## vreg -> spill slot index (-1 = not spilled)
mut RA_SPILL_SLOTS := 0

mut ORDER   : [usize; 32] = [0; 32]       ## vregs in linear-scan order (by interval start)
mut ORDER_N := 0
mut RA_BLK  : [usize; 16] = [0; 16]       ## scratch: physicals blocked for the current interval

## successors of the current instruction (backward-liveness CFG edges)
mut RA_S0 := 0
mut RA_S1 := 0
mut RA_SC := 0

## ra_rw_operand OUT registers (a rewritten operand + its reload/store obligations)
mut RW_K := 0
mut RW_V := 0
mut RW_RELOAD := false
mut RW_STORE := false
mut RW_DISP := 0

## ===== Instruction model (the ported `InsnModel`: roles + clobbers + call/return/branch) =============
## Role of operand 0, by opcode (destination-first). The safe over-approximation for an unknown mnemonic
## is a read (never a missed def), but every opcode this IR uses is classified exactly.
ra_role0 := fn(op : usize) -> usize {
  if op == 0 { return 1 }   ## mov: dst written
  if op == 1 { return 2 }   ## add: dst read-modify-write
  if op == 2 { return 2 }   ## sub
  if op == 3 { return 2 }   ## imul (2-op form)
  if op == 4 { return 0 }   ## cmp: read-only
  if op == 5 { return 0 }   ## mul (1-op): src read; rax:rdx defined via clobber
  if op == 6 { return 0 }   ## call: the Sym target is a read
  if op == 8 { return 0 }   ## jmp: Sym target read
  if op == 9 { return 0 }   ## jcc: Sym target read
  if op == 15 { return 1 }  ## load `movq (o1), o0`: dst (o0) written, addr base (o1) read
  if op == 16 { return 2 }  ## and: dst read-modify-write
  if op == 17 { return 2 }  ## or
  if op == 18 { return 2 }  ## xor
  if op == 19 { return 2 }  ## shl: dst read-modify-write (count implicit in %cl)
  if op == 20 { return 2 }  ## shr (logical)
  if op == 21 { return 2 }  ## sar (arithmetic)
  if op == 22 { return 1 }  ## lea-slot `leaq disp(%rbp), o0`: dst (o0) written, no read (disp is an Imm in o1)
  if op == 25 or op == 26 { return 1 }  ## scaled/byte load: dst (o0) written
  return 0
}
## Operand 1 is always a Read when present (mov src, add src, cmp rhs, scaled-load base) — no opcode writes it.
ra_role1 := fn(op : usize) -> usize { return 0 }
## Operand 2 exists ONLY on the scaled load (op 25) — the INDEX, always a Read. None(0) everywhere else.
ra_role2 := fn(op : usize) -> usize { return 0 }

ra_reads := fn(r : usize) -> bool { return r == 0 or r == 2 }
ra_writes := fn(r : usize) -> bool { return r == 1 or r == 2 }

## Does instruction `i` USE (read) virtual register `v`?
ra_uses_v := fn(i : usize, v : usize) -> bool {
  op := RA_OP[i]
  if RA_O0K[i] == 3 and RA_O0V[i] == i64(v) and ra_reads(ra_role0(op)) { return true }
  if RA_O1K[i] == 3 and RA_O1V[i] == i64(v) and ra_reads(ra_role1(op)) { return true }
  if RA_O2K[i] == 3 and RA_O2V[i] == i64(v) and ra_reads(ra_role2(op)) { return true }
  return false
}
## Does instruction `i` DEFINE (write) virtual register `v`?
ra_defs_v := fn(i : usize, v : usize) -> bool {
  op := RA_OP[i]
  if RA_O0K[i] == 3 and RA_O0V[i] == i64(v) and ra_writes(ra_role0(op)) { return true }
  if RA_O1K[i] == 3 and RA_O1V[i] == i64(v) and ra_writes(ra_role1(op)) { return true }
  if RA_O2K[i] == 3 and RA_O2V[i] == i64(v) and ra_writes(ra_role2(op)) { return true }
  return false
}

## ===== IR construction ===============================================================================
ra_emit := fn(op : usize, k0 : usize, v0 : i64, k1 : usize, v1 : i64) {
  RA_OP[RA_N] = op
  RA_O0K[RA_N] = k0
  RA_O0V[RA_N] = v0
  RA_O1K[RA_N] = k1
  RA_O1V[RA_N] = v1
  RA_O2K[RA_N] = 0                    ## a 2-operand op: clear any stale O2 from a prior fn at this index
  RA_O2V[RA_N] = 0
  RA_N = RA_N + 1
}
## The ONLY 3-operand emit — the scaled load. o2 (the index) carries a real operand; the others are cleared.
ra_emit3 := fn(op : usize, k0 : usize, v0 : i64, k1 : usize, v1 : i64, k2 : usize, v2 : i64) {
  RA_OP[RA_N] = op
  RA_O0K[RA_N] = k0
  RA_O0V[RA_N] = v0
  RA_O1K[RA_N] = k1
  RA_O1V[RA_N] = v1
  RA_O2K[RA_N] = k2
  RA_O2V[RA_N] = v2
  RA_N = RA_N + 1
}

ra_out_emit := fn(op : usize, k0 : usize, v0 : i64, k1 : usize, v1 : i64) {
  OUT_OP[RA_OUT_N] = op
  OUT_O0K[RA_OUT_N] = k0
  OUT_O0V[RA_OUT_N] = v0
  OUT_O1K[RA_OUT_N] = k1
  OUT_O1V[RA_OUT_N] = v1
  OUT_O2K[RA_OUT_N] = 0              ## clear any stale O2 from a prior fn at this output index
  OUT_O2V[RA_OUT_N] = 0
  RA_OUT_N = RA_OUT_N + 1
}
## The rewritten (vreg-free) scaled load: o2 (index) is a real Phys operand; the rest cleared.
ra_out_emit3 := fn(op : usize, k0 : usize, v0 : i64, k1 : usize, v1 : i64, k2 : usize, v2 : i64) {
  OUT_OP[RA_OUT_N] = op
  OUT_O0K[RA_OUT_N] = k0
  OUT_O0V[RA_OUT_N] = v0
  OUT_O1K[RA_OUT_N] = k1
  OUT_O1V[RA_OUT_N] = v1
  OUT_O2K[RA_OUT_N] = k2
  OUT_O2V[RA_OUT_N] = v2
  RA_OUT_N = RA_OUT_N + 1
}

## Reset all per-run state (state is BSS-global so the allocator is single-threaded/non-reentrant — fine
## for a dormant self-test; determinism comes from array-order iteration, not from clean-slate arrays).
ra_reset := fn() {
  RA_N = 0
  RA_OUT_N = 0
  RA_SPILL_SLOTS = 0
  mut v := 0
  while v < 32 {
    ASSIGN[v] = -1
    SPILL[v] = -1
    IV_PRESENT[v] = 0
    IV_FIRST[v] = 0
    IV_LAST[v] = -1
    v = v + 1
  }
  mut l := 0
  while l < 16 { LABELIDX[l] = -1; l = l + 1 }
}

ra_alloc_reset := fn() { RA_NALLOC = 0 }
ra_alloc_add := fn(r : usize) { RA_ALLOC[RA_NALLOC] = r; RA_NALLOC = RA_NALLOC + 1 }

## The System V x86_64 caller-saved set (rax, rcx, rdx, rsi, rdi, r8..r11).
ra_caller_std := fn() {
  RA_CALLER[0] = 0
  RA_CALLER[1] = 2
  RA_CALLER[2] = 3
  RA_CALLER[3] = 4
  RA_CALLER[4] = 5
  RA_CALLER[5] = 8
  RA_CALLER[6] = 9
  RA_CALLER[7] = 10
  RA_CALLER[8] = 11
  RA_NCALLER = 9
}

## ===== CFG liveness ==================================================================================
## Map every label id to its instruction index (for branch-target resolution).
ra_build_labels := fn(n : usize) {
  mut i := 0
  while i < n {
    if RA_OP[i] == 10 { LABELIDX[usize(RA_O0V[i])] = i64(i) }
    i = i + 1
  }
}

## Control-flow successors of instruction `i`, written to RA_S0/RA_S1 (RA_SC = count 0..2).
ra_succ := fn(i : usize, n : usize) {
  RA_SC = 0
  op := RA_OP[i]
  if op == 7 or op == 13 { return }        ## ret / ud2-trap: no successor (a dead end)
  if op == 8 {                             ## jmp: unconditional target only
    ti := LABELIDX[usize(RA_O0V[i])]
    if ti >= 0 { RA_S0 = usize(ti); RA_SC = 1 }
    return
  }
  if op == 9 {                             ## jcc: target + fall-through
    ti := LABELIDX[usize(RA_O0V[i])]
    if ti >= 0 { RA_S0 = usize(ti); RA_SC = 1 }
    if i + 1 < n {
      if RA_SC == 0 { RA_S0 = i + 1; RA_SC = 1 } else { RA_S1 = i + 1; RA_SC = 2 }
    }
    return
  }
  if i + 1 < n { RA_S0 = i + 1; RA_SC = 1 }  ## everything else falls through
}

## Read bit `b` of word `w`.
ra_bit := fn(w : usize, b : usize) -> usize { return w.shr(b) & 1 }

## Iterative backward liveness (loop back-edges extend intervals via the fixpoint).
##   live_out[i] = ∪ live_in[succ];  live_in[i] = use[i] ∪ (live_out[i] − def[i]).
## Each per-instruction live set is a single-word bitmask over vregs (bit v = vreg v).
ra_liveness := fn(n : usize) {
  mut i := 0
  while i < n { LIVEIN[i] = 0; LIVEOUT[i] = 0; i = i + 1 }
  mut changed := true
  while changed {
    changed = false
    mut ii := n
    while ii > 0 {
      ii = ii - 1
      ra_succ(ii, n)
      ## live-out = union (bitwise-OR) of the successors' live-in masks.
      mut o := 0
      if RA_SC >= 1 { o = o | LIVEIN[RA_S0] }
      if RA_SC >= 2 { o = o | LIVEIN[RA_S1] }
      if o != LIVEOUT[ii] { LIVEOUT[ii] = o; changed = true }
      ## live-in = use ∪ (live-out − def), computed bit by bit over the vregs.
      mut ni := 0
      mut v := 0
      while v < 32 {
        mut b := 0
        if ra_uses_v(ii, v) { b = 1 }
        if b == 0 and ra_bit(o, v) == 1 and ra_defs_v(ii, v) == false { b = 1 }
        if b == 1 { ni = ni | usize(1).shl(v) }
        v = v + 1
      }
      if ni != LIVEIN[ii] { LIVEIN[ii] = ni; changed = true }
    }
  }
}

## Grow vreg `v`'s inclusive interval to cover index `at`.
ra_note := fn(v : usize, at : usize) {
  if IV_PRESENT[v] == 0 {
    IV_PRESENT[v] = 1
    IV_FIRST[v] = i64(at)
    IV_LAST[v] = i64(at)
  } else {
    if i64(at) < IV_FIRST[v] { IV_FIRST[v] = i64(at) }
    if i64(at) > IV_LAST[v] { IV_LAST[v] = i64(at) }
  }
}

## Build inclusive live intervals from def/use plus live-out (a value live after `i` reaches `i` and the
## next index — so a loop-carried value spans the whole body). Conservative; never under-approximates.
## CLEAN-SLATE the interval + assignment state first: the coalescer reallocates the SAME fn many times
## (measuring each tentative merge), and `ra_note` only GROWS an interval — a vreg that a prior trial marked
## present but that a later merge renamed AWAY would otherwise keep a stale `IV_PRESENT`/interval and still
## claim a register in `ra_linscan`, making the measurement diverge from a clean allocation. Resetting here
## makes every allocation deterministic and history-independent (idempotent for the once-per-fn HEAD path,
## where `ra_reset` already zeroed these). ASSIGN/SPILL are re-set by `ra_linscan` for present vregs; clearing
## them too keeps a renamed-away vreg from carrying a stale assignment into `ra_rewrite`.
ra_intervals := fn(n : usize) {
  mut rv := 0
  while rv < 32 {
    IV_PRESENT[rv] = 0
    IV_FIRST[rv] = 0
    IV_LAST[rv] = -1
    ASSIGN[rv] = -1
    SPILL[rv] = -1
    rv = rv + 1
  }
  mut i := 0
  while i < n {
    mut v := 0
    while v < 32 {
      if ra_defs_v(i, v) { ra_note(v, i) }
      if ra_uses_v(i, v) { ra_note(v, i) }
      if ra_bit(LIVEOUT[i], v) == 1 {
        ra_note(v, i)
        mut nx := i + 1
        if nx >= n { nx = n - 1 }
        ra_note(v, nx)
      }
      v = v + 1
    }
    i = i + 1
  }
}

## Physicals occupied at each index: pre-colored Phys operands + per-instruction clobbers (mul → rax:rdx;
## call → every caller-saved). A vreg cannot take a physical busy anywhere in its interval.
ra_build_busy := fn(n : usize) {
  mut i := 0
  while i < n {
    mut m := 0
    op := RA_OP[i]
    if RA_O0K[i] == 2 { m = m | usize(1).shl(usize(RA_O0V[i])) }
    if RA_O1K[i] == 2 { m = m | usize(1).shl(usize(RA_O1V[i])) }
    if RA_O2K[i] == 2 { m = m | usize(1).shl(usize(RA_O2V[i])) }
    if op == 5 or op == 11 or op == 12 { m = m | usize(1).shl(0) | usize(1).shl(3) }   ## mul / udiv(11) / idiv(12) clobber rax, rdx
    ## SHIFT (op 19/20/21): the variable count lives in %cl (low byte of %rcx), so %rcx is BUSY over the
    ## shift — a value live across it can hold no register but %rcx (denied here), exactly like the mul's
    ## rax:rdx pin. The count was moved into %rcx by a preceding `mov %rcx, count` (a pre-colored write).
    if op == 19 or op == 20 or op == 21 { m = m | usize(1).shl(2) }
    if op == 6 {
      mut c := 0
      while c < RA_NCALLER { m = m | usize(1).shl(RA_CALLER[c]); c = c + 1 }
    }
    ## BARRIER (op 14): the spliced text snippet may touch ANY register, so mark every physical BUSY over
    ## it — a vreg whose interval spans the barrier can hold NO register and is forced to a spill slot
    ## (its value survives in memory, untouched by the snippet). r10/r11 (spill reload temps) and rbp/rsp
    ## are non-allocatable, so marking them is harmless; the point is to deny rbx/r12..r15 too (unlike a
    ## `call`, which spares the callee-saved set — the barrier spares nothing).
    ## STMT-BARRIER (op 23): same full clobber as op 14 — the spliced text statement (an inline-array-literal
    ## init emitted via the text emitter) may touch ANY register, so every live-across scalar vreg spills.
    ## GENERAL STMT-BARRIER (op 24): the whole statement (a Vec-build call / push) is spliced through the text
    ## emitter — it may `call` (clobbering caller-saved) and touch any register, so the same full clobber.
    if op == 14 or op == 23 or op == 24 {
      mut cb := 0
      while cb < 16 { m = m | usize(1).shl(cb); cb = cb + 1 }
    }
    BUSY[i] = m
    i = i + 1
  }
}

## ===== Linear-scan allocation ========================================================================
## Two intervals overlap iff first_a <= last_b and first_b <= last_a.
ra_overlaps := fn(x : usize, y : usize) -> bool {
  return IV_FIRST[x] <= IV_LAST[y] and IV_FIRST[y] <= IV_LAST[x]
}

ra_linscan := fn(n : usize) {
  ## Collect present vregs (ascending id) then selection-sort by interval start — deterministic order.
  ORDER_N = 0
  mut v := 0
  while v < 32 {
    if IV_PRESENT[v] == 1 { ORDER[ORDER_N] = v; ORDER_N = ORDER_N + 1 }
    v = v + 1
  }
  mut i := 0
  while i < ORDER_N {
    mut mn := i
    mut j := i + 1
    while j < ORDER_N {
      if IV_FIRST[ORDER[j]] < IV_FIRST[ORDER[mn]] { mn = j }
      j = j + 1
    }
    t := ORDER[i]; ORDER[i] = ORDER[mn]; ORDER[mn] = t
    i = i + 1
  }
  ## Assign each interval a free allocatable physical (not busy anywhere in [first,last], not already held
  ## by an overlapping interval) or a fresh spill slot.
  RA_SPILL_SLOTS = 0
  mut k := 0
  while k < ORDER_N {
    vv := ORDER[k]
    mut r := 0
    while r < 16 { RA_BLK[r] = 0; r = r + 1 }
    ## pre-colored / clobber busy across the interval
    mut at := usize(IV_FIRST[vv])
    lastc := usize(IV_LAST[vv])
    while at <= lastc {
      mut rr := 0
      while rr < 16 { if ra_bit(BUSY[at], rr) == 1 { RA_BLK[rr] = 1 } ; rr = rr + 1 }
      at = at + 1
    }
    ## physicals held by already-assigned overlapping intervals
    mut k2 := 0
    while k2 < k {
      jv := ORDER[k2]
      if ASSIGN[jv] >= 0 {
        if ra_overlaps(jv, vv) { RA_BLK[usize(ASSIGN[jv])] = 1 }
      }
      k2 = k2 + 1
    }
    ## pick the first free allocatable, else spill
    mut picked := -1
    mut ai := 0
    while ai < RA_NALLOC and picked < 0 {
      cand := RA_ALLOC[ai]
      if RA_BLK[cand] == 0 { picked = i64(cand) }
      ai = ai + 1
    }
    if picked >= 0 {
      ASSIGN[vv] = picked
    } else {
      SPILL[vv] = i64(RA_SPILL_SLOTS)
      RA_SPILL_SLOTS = RA_SPILL_SLOTS + 1
    }
    k = k + 1
  }
}

## ===== Rewrite (replace every vreg; insert reload before a spilled use / store after a spilled def) ==
## Rewrite one operand into RW_K/RW_V, recording reload/store obligations for a spilled vreg (temp = the
## reserved spill temp handed to this operand position).
ra_rw_operand := fn(k : usize, v : i64, role : usize, temp : usize) {
  RW_RELOAD = false
  RW_STORE = false
  RW_DISP = 0
  if k == 3 {
    vv := usize(v)
    if ASSIGN[vv] >= 0 {
      RW_K = 2
      RW_V = ASSIGN[vv]                       ## a physical register
    } else {
      slot := SPILL[vv]
      RW_DISP = RA_SPILL_BASE - slot * 8       ## frame-relative spill slot
      if ra_reads(role) { RW_RELOAD = true }
      if ra_writes(role) { RW_STORE = true }
      RW_K = 2
      RW_V = i64(temp)                         ## the value lives in the reserved temp around the insn
    }
  } else {
    RW_K = k
    RW_V = v
  }
}

ra_rewrite := fn(n : usize) {
  RA_OUT_N = 0
  ## bind the spill temps to locals first (a bare global scalar as a call argument mis-resolves).
  mut t0 := RA_ST0
  mut t1 := RA_ST1
  mut i := 0
  while i < n {
    op := RA_OP[i]
    if op == 25 or op == 26 {
      ## SCALED LOAD / BYTE SCALED LOAD — a 3-operand op rewritten with only the 2 reserved spill
      ## temps: base→t0, index→t1, dst→t0. dst's store is emitted AFTER the load, and the load consumes base
      ## (from t0) to form the address BEFORE writing dst into t0 — so dst safely reuses t0 (movq (%t0,%t1,8),
      ## %t0 is well-defined: address read first, dst written after). Both index-reload and base-reload precede
      ## the load and use distinct temps, so no third temp is ever needed.
      ra_rw_operand(RA_O1K[i], RA_O1V[i], 0, t0)           ## base (read) → t0
      bk := RW_K; bv := RW_V; brel := RW_RELOAD; bdsp := RW_DISP
      ra_rw_operand(RA_O2K[i], RA_O2V[i], 0, t1)           ## index (read) → t1
      xk := RW_K; xv := RW_V; xrel := RW_RELOAD; xdsp := RW_DISP
      ra_rw_operand(RA_O0K[i], RA_O0V[i], 1, t0)           ## dst (write) → t0 (store after; reuses t0)
      dk := RW_K; dv := RW_V; dsto := RW_STORE; ddsp := RW_DISP
      if brel { ra_out_emit(0, 2, i64(t0), 5, bdsp) }      ## reload base into t0
      if xrel { ra_out_emit(0, 2, i64(t1), 5, xdsp) }      ## reload index into t1
      ra_out_emit3(op, dk, dv, bk, bv, xk, xv)             ## op 25 movq(...,8) or op 26 movzbq(...,1)
      if dsto { ra_out_emit(0, 5, ddsp, 2, i64(t0)) }      ## store dst from t0
      i = i + 1
    } else {
    r0 := ra_role0(op)
    r1 := ra_role1(op)
    ra_rw_operand(RA_O0K[i], RA_O0V[i], r0, t0)
    n0k := RW_K; n0v := RW_V; rel0 := RW_RELOAD; sto0 := RW_STORE; dsp0 := RW_DISP
    ra_rw_operand(RA_O1K[i], RA_O1V[i], r1, t1)
    n1k := RW_K; n1v := RW_V; rel1 := RW_RELOAD; sto1 := RW_STORE; dsp1 := RW_DISP
    ## reloads (before the instruction): mov temp, slot
    if rel0 { ra_out_emit(0, 2, i64(t0), 5, dsp0) }
    if rel1 { ra_out_emit(0, 2, i64(t1), 5, dsp1) }
    ## the (rewritten) instruction
    ra_out_emit(op, n0k, n0v, n1k, n1v)
    ## stores (after the instruction): mov slot, temp
    if sto0 { ra_out_emit(0, 5, dsp0, 2, i64(t0)) }
    if sto1 { ra_out_emit(0, 5, dsp1, 2, i64(t1)) }
    i = i + 1
    }
  }
}

## Hard guard (the "no VReg reaches render" invariant): a leaked vreg in the rewritten stream is fatal.
ra_verify_no_vreg := fn() {
  mut i := 0
  while i < RA_OUT_N {
    if OUT_O0K[i] == 3 { panic("regalloc: leaked vreg in rewritten output") }
    if OUT_O1K[i] == 3 { panic("regalloc: leaked vreg in rewritten output") }
    if OUT_O2K[i] == 3 { panic("regalloc: leaked vreg in rewritten output") }
    i = i + 1
  }
}

## Is there a reload (a `mov temp, [disp]`) from spill slot at frame disp `disp` in the output?
ra_has_reload_disp := fn(disp : i64) -> bool {
  mut i := 0
  while i < RA_OUT_N {
    if OUT_OP[i] == 0 and OUT_O1K[i] == 5 and OUT_O1V[i] == disp { return true }
    i = i + 1
  }
  return false
}

## ===== Conservative move coalescing =================================================================
## Merge a vreg→vreg copy `mov a, b` (BOTH operands vregs) into ONE vreg when a and b do NOT interfere, so
## the copy collapses to `mov %rX, %rX` — a self-move dropped at render (ir_render). This removes the
## redundant `mov`s the linear-scan leaves around every reused accumulator (`sum = sum + x` → the three
## `mov %r8,%r9 ; add %rbx,%r9 ; mov %r9,%r8` becomes a single `add %rbx,%r8`).
##
## Interference is the PRECISE Chaitin test over the per-instruction LIVEOUT bitmasks (NOT the coarse union
## interval `IV_FIRST/IV_LAST`, which would falsely reject a live-across accumulator): a and b interfere iff
## some instruction DEFINES one while the OTHER is live-out there — EXCEPT the copy between them itself (a
## copy's dst and src are equal at that point, so they never interfere there — the essence of coalescing).
## This is necessary AND sufficient for a correct merge: any point where a and b must hold different values
## is a def of one with the other still live-out (caught), and their own copy makes them equal (excluded).
##
## SAFETY: only vreg↔vreg copies are coalesced — a vreg↔PHYSICAL copy (param bind `mov v, argreg`, return
## staging `mov rax, v`) is left untouched, so precolor/clobber constraints are never disturbed. A wrong
## merge is impossible (Chaitin correctness); the worst outcome is an extra spill (perf, never wrong), which
## the e2e/sweeps would surface as unchanged results anyway. DETERMINISM (the only fixpoint hazard): copies
## are scanned in IR index order, the rename is a FIXED direction (src id → dst id), and every loop is
## array-order — so Stage1 and Stage2 produce byte-identical GAS.

## Is instruction `j` the copy `mov a, b` (or `mov b, a`) between vregs a and b? (Its def/use are equal → no
## interference is contributed there.)
ra_is_copy_between := fn(j : usize, a : i64, b : i64) -> bool {
  if RA_OP[j] != 0 { return false }
  if RA_O0K[j] != 3 or RA_O1K[j] != 3 { return false }
  if RA_O0V[j] == a and RA_O1V[j] == b { return true }
  if RA_O0V[j] == b and RA_O1V[j] == a { return true }
  return false
}

## Do vregs a and b interfere? Chaitin: a def of one while the other is live-out, outside their own copy.
## Requires LIVEOUT already built for the CURRENT IR.
ra_interfere := fn(a : i64, b : i64, n : usize) -> bool {
  mut j := 0
  while j < n {
    if ra_is_copy_between(j, a, b) == false {
      if ra_defs_v(j, usize(a)) and ra_bit(LIVEOUT[j], usize(b)) == 1 { return true }
      if ra_defs_v(j, usize(b)) and ra_bit(LIVEOUT[j], usize(a)) == 1 { return true }
    }
    j = j + 1
  }
  return false
}

## Is either vreg live ACROSS a full-clobber barrier (op 14 BARRIER / 23 STMT-BARRIER / 24 general STMT-
## BARRIER)? Such a value CANNOT hold a register over the barrier (the spliced text may touch every register)
## — the allocator MUST park it in a spill slot (`ra_build_busy` marks all 16 regs BUSY there). Coalescing a
## barrier-crossing (must-spill) value with an ordinary register temp is DECLINED: it would fuse a spilled
## live range with a register one, and keeping the result in a register would let the barrier clobber it.
## Barriers do not name a vreg operand, so "crossing" == live-in or live-out at the barrier index. Requires
## LIVEIN/LIVEOUT built for the CURRENT IR. (Calls, op 6, are NOT gated here — they clobber only the
## caller-saved set, so the allocator keeps a live-across value in a callee-saved reg; the cost guard catches
## any regression there.)
ra_crosses_barrier := fn(a : i64, b : i64, n : usize) -> bool {
  mut j := 0
  while j < n {
    op := RA_OP[j]
    if op == 14 or op == 23 or op == 24 {
      if ra_bit(LIVEOUT[j], usize(a)) == 1 { return true }
      if ra_bit(LIVEOUT[j], usize(b)) == 1 { return true }
      if ra_bit(LIVEIN[j], usize(a)) == 1 { return true }
      if ra_bit(LIVEIN[j], usize(b)) == 1 { return true }
    }
    j = j + 1
  }
  return false
}

## Rename every VReg operand equal to `from` into `to` across the IR (apply a merge).
ra_rename_vreg := fn(from : i64, to : i64, n : usize) {
  mut i := 0
  while i < n {
    if RA_O0K[i] == 3 and RA_O0V[i] == from { RA_O0V[i] = to }
    if RA_O1K[i] == 3 and RA_O1V[i] == from { RA_O1V[i] = to }
    if RA_O2K[i] == 3 and RA_O2V[i] == from { RA_O2V[i] = to }
    i = i + 1
  }
}

## Backup of the IR vreg-value columns (the only arrays a merge mutates — rename touches RA_O0V/RA_O1V,
## keeping every kind at 3). Used to REVERT a tentative merge that turned out to raise the spill count.
mut BAK_O0V : [i64; 64] = [0; 64]
mut BAK_O1V : [i64; 64] = [0; 64]
mut BAK_O2V : [i64; 64] = [0; 64]
ra_ir_snapshot := fn(n : usize) {
  mut i := 0
  while i < n { BAK_O0V[i] = RA_O0V[i]; BAK_O1V[i] = RA_O1V[i]; BAK_O2V[i] = RA_O2V[i]; i = i + 1 }
}
ra_ir_restore := fn(n : usize) {
  mut i := 0
  while i < n { RA_O0V[i] = BAK_O0V[i]; RA_O1V[i] = BAK_O1V[i]; RA_O2V[i] = BAK_O2V[i]; i = i + 1 }
}

## The EMITTED-instruction cost of the current rewritten output (`OUT_*`, `RA_OUT_N` entries): every insn
## counts ONE, EXCEPT a self-move `movq %rX,%rX` (dropped at render → free), plus 2 per callee-saved reg the
## allocation used (its prologue save + epilogue restore). This is the exact size the emitter produces, so a
## merge that trades a removed `mov` for a spill reload/store or a callee-save pair shows up as NO net win.
ra_out_cost := fn() -> usize {
  mut c := 0
  mut i := 0
  while i < RA_OUT_N {
    selfmv := OUT_OP[i] == 0 and OUT_O0K[i] == 2 and OUT_O1K[i] == 2 and OUT_O0V[i] == OUT_O1V[i]
    if selfmv == false { c = c + 1 }
    i = i + 1
  }
  if ra_out_uses_reg(1) { c = c + 2 }        ## rbx  (callee-saved: save + restore)
  if ra_out_uses_reg(12) { c = c + 2 }       ## r12
  if ra_out_uses_reg(13) { c = c + 2 }       ## r13
  if ra_out_uses_reg(14) { c = c + 2 }       ## r14
  if ra_out_uses_reg(15) { c = c + 2 }       ## r15
  return c
}

## Run the full allocation + rewrite over the CURRENT IR and return its emitted-instruction cost. (A cheap
## measurement over tiny per-fn IR; used to compare "before this merge" vs "after this merge".)
ra_measure_cost := fn(n : usize) -> usize {
  ra_liveness(n)
  ra_intervals(n)
  ra_build_busy(n)
  ra_linscan(n)
  ra_rewrite(n)
  return ra_out_cost()
}

## Guarded coalescing (a bounded greedy fixpoint): scan copies in IR index order; for each non-interfering
## vreg→vreg copy, TENTATIVELY merge (src→dst) and reallocate — KEEP it only if the emitted cost STRICTLY
## DROPS, otherwise REVERT that one merge. Accepting only strict improvements makes the pass monotonic: NO
## function's emitted code can grow (a merge that would trade its removed `mov` for a spill reload/store or a
## callee-save pair scores no win and is declined), while a genuinely redundant copy collapses. Deterministic:
## fixed scan order, fixed rename direction (src→dst), array-order iteration; a merge is accepted purely on
## the deterministic cost, so Stage1 and Stage2 choose identically. Leaves the IR in its final (accepted-
## merge) form; the caller does one clean final allocation over it.
ra_coalesce := fn(n : usize) {
  mut cur := ra_measure_cost(n)              ## emitted-cost floor for the uncoalesced IR
  mut changed := true
  while changed {
    changed = false
    mut i := 0
    while i < n and changed == false {
      if RA_OP[i] == 0 and RA_O0K[i] == 3 and RA_O1K[i] == 3 {
        a := RA_O0V[i]                        ## dst vreg
        b := RA_O1V[i]                        ## src vreg
        if a != b and ra_interfere(a, b, n) == false and ra_crosses_barrier(a, b, n) == false {
          ra_ir_snapshot(n)                   ## save so a non-improving merge can be reverted
          ra_rename_vreg(b, a, n)             ## merge src into dst (fixed direction → deterministic)
          sp := ra_measure_cost(n)            ## reallocate + rewrite; also refreshes liveness for interfere()
          if sp < cur {
            cur = sp                          ## strictly cheaper — keep it, restart the scan
            changed = true
          } else {
            ra_ir_restore(n)                  ## no net win — undo this merge
            ra_liveness(n)                    ## restore liveness for the following interference tests
          }
        }
      }
      i = i + 1
    }
  }
}

## Fold the exact two-instruction shape emitted for a scalar expression whose BOTH operands are immediate:
## `mov v, $lhs; op v, $rhs` → `mov v, $(lhs op rhs)`. Bitwise ops are always safe: they have no checked-mode
## trap. Add/sub/imul are folded only when the next instruction is NOT a jcc overflow guard; that admits the
## unchecked/zero-left raw arithmetic shape while leaving every checked arithmetic op + its flags-dependent
## guard intact. This is deliberately narrower than general constant propagation: it does not inspect calls,
## memory, aggregates, CFG edges, shifts, division, or any other opcode. Wrapping arithmetic is evaluated in
## an unchecked compiler expression, matching the scalar IR's native-width bit pattern. It runs after semantic
## lowering and before liveness/allocation, so the optimization is deterministic and the `ALATYR_RA=0` lowering
## fallback remains untouched.
ra_fold_const_scalar := fn(n : usize) -> usize {
  mut i := 0
  mut left := n
  mut folded := 0
  while i + 1 < left {
    first := RA_OP[i] == 0 and RA_O0K[i] == 3 and RA_O1K[i] == 1
    second := RA_O0K[i + 1] == 3 and RA_O1K[i + 1] == 1 and RA_O0V[i + 1] == RA_O0V[i]
    op := RA_OP[i + 1]
    bitop := op == 16 or op == 17 or op == 18
    arith := op == 1 or op == 2 or op == 3
    ## Checked add/sub/imul are followed immediately by jcc (the overflow guard). Do not fold that
    ## flags-producing instruction; the guard is part of the language semantics, not dead scaffolding.
    guarded := i + 2 < left and RA_OP[i + 2] == 9
    if first and second and (bitop or (arith and not guarded)) {
      mut value := RA_O1V[i]
      if op == 1 { value = unchecked { value + RA_O1V[i + 1] } }
      if op == 2 { value = unchecked { value - RA_O1V[i + 1] } }
      if op == 3 { value = unchecked { value * RA_O1V[i + 1] } }
      if op == 16 { value = value & RA_O1V[i + 1] }
      if op == 17 { value = value | RA_O1V[i + 1] }
      if op == 18 { value = value ^ RA_O1V[i + 1] }
      RA_O1V[i] = value
      mut j := i + 1
      while j + 1 < left {
        RA_OP[j] = RA_OP[j + 1]
        RA_O0K[j] = RA_O0K[j + 1]
        RA_O0V[j] = RA_O0V[j + 1]
        RA_O1K[j] = RA_O1K[j + 1]
        RA_O1V[j] = RA_O1V[j + 1]
        RA_O2K[j] = RA_O2K[j + 1]
        RA_O2V[j] = RA_O2V[j + 1]
        j = j + 1
      }
      left = left - 1
      RA_N = left
      folded = folded + 1
    } else {
      i = i + 1
    }
  }
  folded
}

## Fold the unchecked immediate shift shape emitted by `shl`/logical `shr` operation-fns:
## `mov v, $value; mov %rcx, $count; shift v` → `mov v, $(value shift count)`. The checked path has
## `cmp/jcc/ud2/label` between the `%rcx` move and the shift, so it is deliberately not touched; arithmetic
## `sar` is also left alone because signed right-shift evaluation needs a separate signed bit-pattern helper.
## Counts use x86's native low-six-bit rule, matching the unchecked backend operation exactly. The scalar IR
## admits only native-width values, and the transform removes no calls, memory, effects, or guards.
ra_fold_const_shift := fn(n : usize) -> usize {
  mut i := 0
  mut left := n
  mut folded := 0
  while i + 2 < left {
    first := RA_OP[i] == 0 and RA_O0K[i] == 3 and RA_O1K[i] == 1
    count_mov := RA_OP[i + 1] == 0 and RA_O0K[i + 1] == 2 and RA_O0V[i + 1] == 2 and RA_O1K[i + 1] == 1
    shift := (RA_OP[i + 2] == 19 or RA_OP[i + 2] == 20) and RA_O0K[i + 2] == 3 and RA_O0V[i + 2] == RA_O0V[i]
    if first and count_mov and shift {
      mut value := usize(RA_O1V[i])
      count := usize(RA_O1V[i + 1]) & 63
      if RA_OP[i + 2] == 19 { value = unchecked { value.shl(count) } }
      else { value = unchecked { value.shr(count) } }
      RA_O1V[i] = i64(value)
      mut j := i + 1
      while j + 2 < left {
        RA_OP[j] = RA_OP[j + 2]
        RA_O0K[j] = RA_O0K[j + 2]
        RA_O0V[j] = RA_O0V[j + 2]
        RA_O1K[j] = RA_O1K[j + 2]
        RA_O1V[j] = RA_O1V[j + 2]
        RA_O2K[j] = RA_O2K[j + 2]
        RA_O2V[j] = RA_O2V[j + 2]
        j = j + 1
      }
      left = left - 2
      RA_N = left
      folded = folded + 1
    } else {
      i = i + 1
    }
  }
  folded
}

## Does `v` fit x86-64's ONE immediate encoding for the 2-operand ALU/compare group — a 32-bit field that is
## SIGN-EXTENDED to 64 bits? Only `[-2^31, 2^31-1]` is representable, so an unsigned mask like `0xFFFFFFFF`
## does NOT fit even though it occupies 32 bits, and a 64-bit hex literal that parsed to a negative `i64`
## fits only when it sign-extends from 32 bits.
ra_imm32_fits := fn(v : i64) -> bool {
  if v > 2147483647 { return false }
  if v < 0 - 2147483648 { return false }
  return true
}

## MATERIALIZE an out-of-range immediate. `addq`/`subq`/`imulq`/`cmpq`/`andq`/`orq`/`xorq` (ops 1/2/3/4/16/
## 17/18) have NO imm64 encoding — `as` rejects `addq $4294967296, %rcx` with `operand type mismatch for
## 'add'` — so an immediate source operand that fails `ra_imm32_fits` is loaded into a FRESH vreg by an
## inserted `mov` and the operation becomes register-to-register. `movq $imm, %reg` (op 0) is the one form
## that DOES take a full 64-bit immediate (`as` renders it `movabsq`), which is why the inserted move needs
## no further widening; every OTHER Imm operand in this IR is not an arithmetic immediate at all (op 9's o1
## is a condition code, op 22's o1 a frame displacement, op 5/11/12 take no immediate, and a shift count
## travels through `mov %rcx, $count` — an op-0 move — with x86's low-six-bit rule applied by the hardware).
##
## Runs AFTER both constant folds (so the folds still match their exact `mov; op $imm` shapes and a FOLDED
## wide immediate is widened too) and BEFORE label building / liveness / allocation, so the inserted vreg is
## allocated and, if necessary, spilled like any other. The inserted `mov` goes immediately BEFORE its
## operation, so it can never separate a flags-producing instruction from a following `jcc`: the widened op
## keeps its own position relative to the NEXT instruction, and none of the widened opcodes READS flags.
## Every checked guard (`cmp`/`jcc`/`ud2`) therefore survives byte-for-byte, only with its comparand in a
## register. Fail-loud on capacity: a wrong encoding is a miscompile, a panic is not.
ra_widen_imm64 := fn(n : usize) -> usize {
  mut left := n
  ## the first UNUSED vreg id (the IR's vreg numbering is dense from 0, so max-in-use + 1 is fresh)
  mut next_vreg := 0
  mut s := 0
  while s < left {
    if RA_O0K[s] == 3 and RA_O0V[s] >= next_vreg { next_vreg = RA_O0V[s] + 1 }
    if RA_O1K[s] == 3 and RA_O1V[s] >= next_vreg { next_vreg = RA_O1V[s] + 1 }
    if RA_O2K[s] == 3 and RA_O2V[s] >= next_vreg { next_vreg = RA_O2V[s] + 1 }
    s = s + 1
  }
  mut widened := 0
  mut i := 0
  while i < left {
    op := RA_OP[i]
    alu := op == 1 or op == 2 or op == 3 or op == 4 or op == 16 or op == 17 or op == 18
    if alu and RA_O1K[i] == 1 and ra_imm32_fits(RA_O1V[i]) == false {
      if left >= 64 { panic("regalloc: imm64 materialization exceeds the 64-instruction IR capacity") }
      if next_vreg >= 32 { panic("regalloc: imm64 materialization exceeds the 32-vreg capacity") }
      mut j := left
      while j > i {
        RA_OP[j] = RA_OP[j - 1]
        RA_O0K[j] = RA_O0K[j - 1]
        RA_O0V[j] = RA_O0V[j - 1]
        RA_O1K[j] = RA_O1K[j - 1]
        RA_O1V[j] = RA_O1V[j - 1]
        RA_O2K[j] = RA_O2K[j - 1]
        RA_O2V[j] = RA_O2V[j - 1]
        j = j - 1
      }
      t := next_vreg
      next_vreg = next_vreg + 1
      RA_OP[i] = 0                             ## mov vt, $imm   (assembles as movabsq)
      RA_O0K[i] = 3
      RA_O0V[i] = t
      RA_O1K[i] = 1
      RA_O1V[i] = RA_O1V[i + 1]                ## the shifted copy still holds the original immediate
      RA_O2K[i] = 0
      RA_O2V[i] = 0
      RA_O1K[i + 1] = 3                        ## the operation now reads the register, not the immediate
      RA_O1V[i + 1] = t
      left = left + 1
      RA_N = left
      widened = widened + 1
      i = i + 2
    } else {
      i = i + 1
    }
  }
  widened
}

## The full pipeline over the current IR (`RA_N` instructions). Reads the global count into a local
## FIRST (a bare global scalar passed as a call argument mis-resolves in the lean lower — the documented
## bind-to-local idiom; the same is why the sub-passes take `n` as a param, not the global).
ra_allocate := fn() {
  mut n := RA_N
  ra_fold_const_scalar(n)
  n = RA_N
  ra_fold_const_shift(n)
  n = RA_N
  ra_widen_imm64(n)                            ## no ALU/compare opcode encodes an imm64 — put it in a reg
  n = RA_N
  ra_build_labels(n)
  ra_liveness(n)
  ra_coalesce(n)                             ## merge non-interfering vreg copies (spill-guarded, in place)
  ra_liveness(n)                             ## clean liveness for the final (accepted-merge) IR
  ra_intervals(n)
  ra_build_busy(n)
  ra_linscan(n)
  ra_rewrite(n)
  ra_verify_no_vreg()
}

## ===== Self-test (the 6 ported unit cases) ==========================================================
ra_report := fn(in out sb : rt::StrBuf, name : str, ok : bool) -> usize {
  if ok { h := rt::push_str(sb, "PASS ") } else { h := rt::push_str(sb, "FAIL ") }
  h2 := rt::push_str(sb, name)
  h3 := rt::push_str(sb, "\n")
  if ok { return 0 }
  return 1
}

## Run all 6 cases; print PASS/FAIL lines + a summary to stdout; return the failure count (the exit code).
pub selftest := fn(in out a : rt::Arena) -> usize {
  mut sb := rt::strbuf(a, 65536)
  mut fails := 0

  ## Case 1 — two simultaneously-live vregs get DISTINCT physicals.
  ## v0 = 1; v1 = 2; v0 += v1   (v0, v1 overlap at the add)
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64; RA_ST0 = 10; RA_ST1 = 11
  ra_alloc_add(8); ra_alloc_add(9)              ## allocatable = r8, r9
  ra_emit(0, 3, 0, 1, 1)                        ## mov v0, $1
  ra_emit(0, 3, 1, 1, 2)                        ## mov v1, $2
  ra_emit(1, 3, 0, 3, 1)                        ## add v0, v1
  ra_allocate()
  ok1 := ASSIGN[0] >= 0 and ASSIGN[1] >= 0 and ASSIGN[0] != ASSIGN[1] and RA_SPILL_SLOTS == 0
  fails = fails + ra_report(sb, "straight_line_two_vregs_get_distinct_physicals", ok1)

  ## Case 2 — REUSE a register after last use (non-overlapping vregs share the one physical).
  ## v0 = 1; use v0; v1 = 2; use v1   with ONLY r8 available
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64
  ra_alloc_add(8)                               ## allocatable = r8 only
  ra_emit(0, 3, 0, 1, 1)                        ## mov v0, $1
  ra_emit(0, 2, 0, 3, 0)                        ## mov rax, v0
  ra_emit(0, 3, 1, 1, 2)                        ## mov v1, $2
  ra_emit(0, 2, 0, 3, 1)                        ## mov rax, v1
  ra_allocate()
  ok2 := ASSIGN[0] == 8 and ASSIGN[1] == 8 and RA_SPILL_SLOTS == 0
  fails = fails + ra_report(sb, "reuse_after_last_use", ok2)

  ## Case 3 — SPILL when out of registers (three simultaneously-live vregs, two physicals → one spills).
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64; RA_ST0 = 10; RA_ST1 = 11
  ra_alloc_add(8); ra_alloc_add(9)              ## allocatable = r8, r9
  ra_emit(0, 3, 0, 1, 1)                        ## mov v0, $1
  ra_emit(0, 3, 1, 1, 2)                        ## mov v1, $2
  ra_emit(0, 3, 2, 1, 3)                        ## mov v2, $3
  ra_emit(1, 3, 0, 3, 1)                        ## add v0, v1
  ra_emit(1, 3, 0, 3, 2)                        ## add v0, v2
  ra_allocate()
  ok3 := RA_SPILL_SLOTS == 1 and ra_has_reload_disp(-64)
  fails = fails + ra_report(sb, "spill_when_out_of_registers", ok3)

  ## Case 4 — a PRE-COLORED CLOBBER is respected (v0 live across a mul → dodges rax/rdx).
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64
  ra_alloc_add(0); ra_alloc_add(3); ra_alloc_add(8)  ## offer rax, rdx first, then r8
  ra_emit(0, 3, 0, 1, 7)                        ## mov v0, $7
  ra_emit(5, 2, 9, 0, 0)                        ## mul r9        (clobbers rax:rdx)
  ra_emit(0, 2, 5, 3, 0)                        ## mov rdi, v0
  ra_allocate()
  ok4 := ASSIGN[0] == 8                         ## v0 must be r8, not the clobbered rax/rdx
  fails = fails + ra_report(sb, "precolored_clobber_is_respected", ok4)

  ## Case 5 — a LOOP-CARRIED interval spans the whole body (CFG liveness across the back-edge).
  ## acc(v0)=0; i(v1)=0; L0: v2=5; v2+=v1; v0+=v2; v1+=1; cmp; jb L0; use v0, v1.
  ## v0,v1 hold the two regs across the loop; the body temp v2 must spill.
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64; RA_ST0 = 10; RA_ST1 = 11
  ra_alloc_add(8); ra_alloc_add(9)              ## allocatable = r8, r9 (only two)
  ra_emit(0, 3, 0, 1, 0)                        ## mov v0, $0
  ra_emit(0, 3, 1, 1, 0)                        ## mov v1, $0
  ra_emit(10, 4, 0, 0, 0)                       ## L0:
  ra_emit(0, 3, 2, 1, 5)                        ## mov v2, $5
  ra_emit(1, 3, 2, 3, 1)                        ## add v2, v1
  ra_emit(1, 3, 0, 3, 2)                        ## add v0, v2
  ra_emit(1, 3, 1, 1, 1)                        ## add v1, $1
  ra_emit(4, 3, 1, 1, 10)                       ## cmp v1, $10
  ra_emit(9, 4, 0, 0, 0)                        ## jb L0
  ra_emit(0, 2, 5, 3, 0)                        ## mov rdi, v0
  ra_emit(0, 2, 4, 3, 1)                        ## mov rsi, v1
  ra_allocate()
  ok5 := RA_SPILL_SLOTS == 1
  fails = fails + ra_report(sb, "loop_carried_vreg_spans_the_body", ok5)

  ## Case 6 — a vreg LIVE ACROSS A CALL avoids caller-saved (gets a callee-saved register).
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64
  ra_alloc_add(9); ra_alloc_add(1)              ## offer r9 (caller-saved) first, then rbx (callee-saved)
  ra_emit(0, 3, 0, 1, 42)                       ## mov v0, $42
  ra_emit(6, 4, 0, 0, 0)                        ## call f    (clobbers all caller-saved)
  ra_emit(0, 2, 5, 3, 0)                        ## mov rdi, v0
  ra_allocate()
  ok6 := ASSIGN[0] == 1                         ## v0 must be rbx (callee-saved), not r9
  fails = fails + ra_report(sb, "vreg_live_across_a_call_avoids_caller_saved", ok6)

  ## Case 7 — the Proposal #2 local fold removes only the exact immediate bitwise pair and keeps the
  ## folded value as the source immediate of the defining move.
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64
  ra_emit(0, 3, 0, 1, 40)                       ## mov v0, $40
  ra_emit(16, 3, 0, 1, 2)                       ## and v0, $2
  mut fold_n := RA_N
  ra_fold_const_scalar(fold_n)
  ok7 := RA_N == 1 and RA_OP[0] == 0 and RA_O0V[0] == 0 and RA_O1V[0] == 0
  fails = fails + ra_report(sb, "fold_immediate_bitwise_pair", ok7)

  ## Case 8 — unchecked scalar add/sub/imul fold to their native-width immediate values, while the
  ## immediately-following jcc guard keeps a checked arithmetic pair out of the fold.
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64
  ra_emit(0, 3, 0, 1, 40); ra_emit(1, 3, 0, 1, 2)
  ra_emit(0, 3, 1, 1, 40); ra_emit(2, 3, 1, 1, 2)
  ra_emit(0, 3, 2, 1, 6); ra_emit(3, 3, 2, 1, 7)
  ra_emit(0, 3, 3, 1, 40); ra_emit(1, 3, 3, 1, 2); ra_emit(9, 4, 0, 1, 10)
  mut arith_n := RA_N
  ra_fold_const_scalar(arith_n)
  mut ok8 := RA_N == 6 and RA_OP[0] == 0 and RA_O1V[0] == 42 and RA_OP[1] == 0 and RA_O1V[1] == 38
  ok8 = ok8 and RA_OP[2] == 0 and RA_O1V[2] == 42 and RA_OP[3] == 0 and RA_O1V[3] == 40
  ok8 = ok8 and RA_OP[4] == 1 and RA_OP[5] == 9
  fails = fails + ra_report(sb, "fold_unchecked_scalar_arithmetic_keep_checked_guard", ok8)

  ## Case 9 — unchecked immediate logical shifts fold around the implicit %rcx count move; signed SAR and
  ## checked shift guards are intentionally covered by the source-level regressions, not this fold.
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  ra_emit(0, 3, 0, 1, 17); ra_emit(0, 2, 2, 1, 1); ra_emit(19, 3, 0, 0, 0)
  ra_emit(0, 3, 1, 1, 17); ra_emit(0, 2, 2, 1, 1); ra_emit(20, 3, 1, 0, 0)
  mut shift_n := RA_N
  ra_fold_const_shift(shift_n)
  ok9 := RA_N == 2 and RA_OP[0] == 0 and RA_O1V[0] == 34 and RA_OP[1] == 0 and RA_O1V[1] == 8
  fails = fails + ra_report(sb, "fold_unchecked_logical_shift_immediates", ok9)

  ## Case 10 — the imm32 widening. x86-64's ALU/compare immediate field is 32 bits SIGN-EXTENDED, so an
  ## out-of-range immediate is materialized into a fresh vreg and the operation becomes register-to-register:
  ## `$2^32` (add) and `$0xFFFFFFFF` (and — 32 bits UNSIGNED, still out of signed range) are both widened,
  ## `$2^31-1` (cmp — the largest value that fits) is left folded into the instruction, and the trailing
  ## checked `jcc` guard stays IMMEDIATELY after its operation (an inserted move never separates them).
  ra_reset(); ra_alloc_reset(); ra_caller_std()
  RA_SPILL_BASE = -64
  ra_emit(0, 2, 0, 1, 5)                        ## mov %rax, $5
  ra_emit(1, 2, 0, 1, 4294967296)               ## add %rax, $2^32          -> widened
  ra_emit(4, 2, 0, 1, 2147483647)               ## cmp %rax, $2^31-1        -> fits, untouched
  ra_emit(16, 2, 0, 1, 4294967295)              ## and %rax, $0xFFFFFFFF    -> widened
  ra_emit(9, 4, 0, 1, 11)                       ## jnc CONT                 -> stays adjacent to the `and`
  mut wide_n := RA_N
  ra_widen_imm64(wide_n)
  mut ok10 := RA_N == 7
  ok10 = ok10 and RA_OP[1] == 0 and RA_O0K[1] == 3 and RA_O0V[1] == 0 and RA_O1K[1] == 1 and RA_O1V[1] == 4294967296
  ok10 = ok10 and RA_OP[2] == 1 and RA_O1K[2] == 3 and RA_O1V[2] == 0
  ok10 = ok10 and RA_OP[3] == 4 and RA_O1K[3] == 1 and RA_O1V[3] == 2147483647
  ok10 = ok10 and RA_OP[4] == 0 and RA_O0K[4] == 3 and RA_O0V[4] == 1 and RA_O1V[4] == 4294967295
  ok10 = ok10 and RA_OP[5] == 16 and RA_O1K[5] == 3 and RA_O1V[5] == 1
  ok10 = ok10 and RA_OP[6] == 9
  ok10 = ok10 and ra_imm32_fits(2147483647) and ra_imm32_fits(0 - 2147483648)
  ok10 = ok10 and ra_imm32_fits(2147483648) == false and ra_imm32_fits(0 - 2147483649) == false
  fails = fails + ra_report(sb, "widen_out_of_range_alu_immediate_into_a_register", ok10)

  if fails == 0 {
    h := rt::push_str(sb, "*** regalloc selftest: all 10 cases passed ***\n")
  } else {
    h := rt::push_str(sb, "*** regalloc selftest: FAILURES present ***\n")
  }
  d := rt::sb_flush(sb, 1)
  ## A self-test that cannot report its result is not a successful self-test.  Check both
  ## negative errno and short writes with the signed-to-unsigned comparison used by CLI.
  if unchecked bitcast(usize, d) != sb.len { return 70 }
  return fails
}

## ===== COMMIT 2: emit-from-IR driver API (x86_64 SCALAR-LEAF profile) ================================
## A thin `pub` surface over the allocator so the x86 backend (`lower.al`) can build a per-fn `Vec(Inst)`,
## allocate it, and read the rewritten stream back — WITHOUT touching the BSS state directly (a cross-module
## `mut`-global read mis-resolves in the lean lower; every access goes through a function). GATED behind
## `lower`'s `--ra` flag (default OFF): the self-host build never calls this, so `src/`+`lib/` GAS is
## byte-identical and the TOOL-1 fixpoint is untouched. Determinism is inherited from the allocator
## (fixed register-pick order, array-order iteration) so a flag-ON self-build would still be reproducible.
##
## PROFILE (COMMIT 5 — non-leaf / calls): the CALLER-SAVED set {rcx, rsi, rdi, r8, r9} is offered FIRST
## (a value NOT live across any call takes one, so a leaf fn / a between-calls temp keeps the exact former
## assignment — no callee-save prologue), then the CALLEE-SAVED set {rbx, r12, r13, r14, r15} is offered
## AFTER it. A value LIVE ACROSS A CALL cannot take a caller-saved reg (the `call` clobber marks every
## caller-saved BUSY over its interval — `ra_build_busy` op 6), so it falls to a callee-saved reg (which
## the callee preserves → the emitter save/restores it in the prologue/epilogue) or, if none is free, a
## spill slot. rax/rdx stay reserved (return staging + div rax:rdx + the unsigned-`mul` high half);
## r10/r11 are the two spill reload temps; spill slots start just below %rbp (disp -(slot+1)*8), and the
## callee-save frame slots sit BELOW all spill slots (the emitter lays them out after allocation).
pub ra_scalarleaf_begin := fn() {
  ra_reset()
  ra_alloc_reset()
  ra_caller_std()
  RA_ST0 = 10
  RA_ST1 = 11
  RA_SPILL_BASE = -8
  RA_OVF = 0
  ra_alloc_add(2)                  ## rcx   (caller-saved)
  ra_alloc_add(4)                  ## rsi
  ra_alloc_add(5)                  ## rdi
  ra_alloc_add(8)                  ## r8
  ra_alloc_add(9)                  ## r9
  ra_alloc_add(1)                  ## rbx   (callee-saved — used only when a value is live across a call
  ra_alloc_add(12)                 ## r12     or a leaf fn spills; the emitter save/restores any it uses)
  ra_alloc_add(13)                 ## r13
  ra_alloc_add(14)                 ## r14
  ra_alloc_add(15)                 ## r15
}

## After allocation, did the rewritten output place any value in physical register `r`? (The emitter uses
## this over the callee-saved set {rbx=1, r12..r15} to decide which registers to save/restore.) Scans the
## VReg-free output stream for a Phys operand naming `r`.
pub ra_out_uses_reg := fn(r : usize) -> bool {
  mut i := 0
  while i < RA_OUT_N {
    if OUT_O0K[i] == 2 and OUT_O0V[i] == i64(r) { return true }
    if OUT_O1K[i] == 2 and OUT_O1V[i] == i64(r) { return true }
    if OUT_O2K[i] == 2 and OUT_O2V[i] == i64(r) { return true }
    i = i + 1
  }
  false
}
## Append one instruction (capacity-guarded). OP/operand encoding is the module legend (0=mov 1=add 2=sub
## 3=imul 4=cmp 6=call 7=ret 8=jmp 9=jcc 10=label, plus 11=udiv 12=idiv — both clobber rax:rdx like mul).
pub ra_ir_emit := fn(op : usize, k0 : usize, v0 : i64, k1 : usize, v1 : i64) {
  if RA_N >= 64 { RA_OVF = 1; return }
  ra_emit(op, k0, v0, k1, v1)
}
## Emit the scaled-indexed element LOAD `movq (base, index, 8), dst` (op 25): dst/base/index are VReg ids.
## The element scale is hardcoded 8 (a word element). Folds the for-loop's mov/imul $8/add/load address
## recompute into ONE x86 memory operand. Capacity-guarded like `ra_ir_emit`.
pub ra_ir_emit_sload := fn(dst : i64, base : i64, index : i64) {
  if RA_N >= 64 { RA_OVF = 1; return }
  ra_emit3(25, 3, dst, 3, base, 3, index)
}
## Emit a zero-extending byte indexed load `movzbq (base, index, 1), dst` (op 26). The allocator treats
## it like the word scaled load for liveness/spills, while the renderer preserves the byte-width contract.
pub ra_ir_emit_bload := fn(dst : i64, base : i64, index : i64) {
  if RA_N >= 64 { RA_OVF = 1; return }
  ra_emit3(26, 3, dst, 3, base, 3, index)
}
pub ra_ir_ovf := fn() -> bool { return RA_OVF == 1 }
## Override the first spill slot's frame displacement (used by a BARRIER fn: its TEXT slot map occupies
## the frame TOP at -8.., so the RA spill slots move BELOW it). Must be called AFTER `ra_scalarleaf_begin`
## (which resets it to -8) and BEFORE `ra_ir_run`. A barrier-free fn never calls this → layout unchanged.
pub ra_set_spill_base := fn(b : i64) { RA_SPILL_BASE = b }
pub ra_ir_run := fn() { ra_allocate() }
## Read the allocated (VReg-free) output stream back.
pub ra_out_count := fn() -> usize { return RA_OUT_N }
pub ra_out_op := fn(i : usize) -> usize { return OUT_OP[i] }
pub ra_out_k0 := fn(i : usize) -> usize { return OUT_O0K[i] }
pub ra_out_v0 := fn(i : usize) -> i64 { return OUT_O0V[i] }
pub ra_out_k1 := fn(i : usize) -> usize { return OUT_O1K[i] }
pub ra_out_v1 := fn(i : usize) -> i64 { return OUT_O1V[i] }
pub ra_out_k2 := fn(i : usize) -> usize { return OUT_O2K[i] }
pub ra_out_v2 := fn(i : usize) -> i64 { return OUT_O2V[i] }
pub ra_spill_slots := fn() -> usize { return RA_SPILL_SLOTS }
