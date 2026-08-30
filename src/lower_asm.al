## selfhost::lower_asm — the x86_64 RAW-ASM emit cluster (spec ch.80 / CG-2), extracted from lower.al
## (§6 decomposition). Register operands, structured instruction intrinsics, the asm("<GAS>", op…) escape
## with {i} substitution, and @abi(naked) detection. Imports ctx + accessors from the shared base lower_ctx
## (no cycle back to lower.al). NB: imports are DESTRUCTURES (no single-name `x := rt` alias before a
## `(`-line — that parser footgun binds `rt(push_str,…)` across the newline; see the idiomatic-style memo).
(Arg, Expr) := ast
arg_p := ast::arg_p
(push_str, push_int) := rt
(LCtx, node_ptr, var_name_span, num_lit_value, arg_expr_at, asm_str_span, asm_digit) := lower_ctx

## Emit the stable local GAS name for a source code-point label. The declaration emission index is
## unique across generic instances, while the label spelling is the function-scoped target name.
pub emit_code_label_name := fn(in out sb : rt::StrBuf, cx : ptr(LCtx), s : usize, n : usize) {
  push_str(sb, ".Lcp_")
  push_int(sb, i64(cx.fn_id))
  push_str(sb, "_")
  push_str(sb, str_at((cx.src + s), n))
}

## RAW-ASM register operand (spec ch.80 §6): the x86_64 GP register named `nm` → its GAS spelling
## (`rax` → `%rax`), or "" if `nm` is not a GP register. Registers are arch-data prelude identifiers
## (case-sensitive lowercase), NOT keywords.
pub x86_gpreg := fn(nm : str) -> str {
  if nm == "rax" { return "%rax" }
  if nm == "rbx" { return "%rbx" }
  if nm == "rcx" { return "%rcx" }
  if nm == "rdx" { return "%rdx" }
  if nm == "rsi" { return "%rsi" }
  if nm == "rdi" { return "%rdi" }
  if nm == "rbp" { return "%rbp" }
  if nm == "rsp" { return "%rsp" }
  if nm == "r8" { return "%r8" }
  if nm == "r9" { return "%r9" }
  if nm == "r10" { return "%r10" }
  if nm == "r11" { return "%r11" }
  if nm == "r12" { return "%r12" }
  if nm == "r13" { return "%r13" }
  if nm == "r14" { return "%r14" }
  if nm == "r15" { return "%r15" }
  return ""
}

## Is the fn whose NAME occupies `src[ns .. ns+nl)` an `@abi(naked)` fn (spec ch.80 — a raw-asm fn)?
## The parser leaves a naked fn as an ordinary kind-1 decl (it distinguishes the selector but records
## no flag), so the lower recovers the marker by source-scan: the decl reads `name := @abi(naked) fn …`,
## so from just past the name we skip whitespace, the `:=`, whitespace, and test for the `@abi(naked)`
## effector. (Compact spelling — the norm; a spaced `@abi( naked )` is not matched, acceptable for now.)
pub fn_is_naked := fn(src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut p := ns + nl
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  if str_at((src + p), 2) != ":=" { return false }
  p += 2
  while str_at((src + p), 1) == " " or str_at((src + p), 1) == "\n" or str_at((src + p), 1) == "\t" or str_at((src + p), 1) == "\r" { p = p + 1 }
  str_at((src + p), 11) == "@abi(naked)"
}

## Is `e` a RAW-ASM instruction call over REGISTER operands (spec ch.80 §2) — the naked/raw surface,
## distinct from the local-mutating `x86_64.<mnem>` form: `movq(<reg>, <imm|reg>)` (register dest) or
## `syscall()`. Distinguished from an ordinary call by the register dest / the `syscall` mnemonic, so a
## user fn named `movq` over a non-register first arg is NOT matched.
pub is_raw_instr_call := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena) -> bool {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => {
      nm := str_at((src + cs), cl)
      if (nm == "syscall" or nm == "ret") and na == 0 { true }
      else if nm == "asm" and na >= 1 { true }   ## `asm("…GAS…", op…)` raw escape, {i}-substituted (§4/§11)
      else if nm == "jmp" and na == 1 and ah != 0 {
        a0 := deref(arg_p(ah))
        dv := var_name_span(a0.e)
        if dv.n != 0 and x86_gpreg(str_at((src + dv.s), dv.n)) == "" { true } else { false }
      }
      else if (nm == "negq" or nm == "notq") and na == 1 {   ## 1-operand register-form (`negq(rax)` → `negq %rax`)
        a0 := deref(arg_p(ah))
        dv := var_name_span(a0.e)
        if dv.n != 0 { x86_gpreg(str_at((src + dv.s), dv.n)) != "" } else { false }
      }
      else if (nm == "movq" or nm == "addq" or nm == "subq" or nm == "andq" or nm == "orq" or nm == "xorq" or nm == "shlq" or nm == "shrq" or nm == "sarq" or nm == "imulq") and na == 2 {
        a0 := deref(arg_p(ah))
        dv := var_name_span(a0.e)
        if dv.n != 0 { x86_gpreg(str_at((src + dv.s), dv.n)) != "" } else { false }
      } else { false }
    }
    _ => { false }
  }
}

## Emit a RAW-ASM instruction over register operands (spec ch.80 §2/§6) — one GAS instruction, no guard
## (I1/§3), no stack value. `movq(dest, src)` is destination-first (spec §2.2) → AT&T `movq <src>, <dest>`
## (src = a Num immediate `$N` or a register `%r`). `syscall()` → `syscall`. Emitted directly in
## statement position WITHOUT the discard-pop, so it does not clobber the register just written.
pub emit_raw_instr := fn(e : ptr(Expr), in out sb : rt::StrBuf, cx : ptr(LCtx), a : rt::Arena) {
  match deref(e) {
    Expr::Call(cs, cl, na, ah) => {
      nm := str_at((cx.src + cs), cl)
      ## 0-operand instruction (`syscall()` / `ret()`) — emit the bare mnemonic. `ret()` is used only
      ## inside an `@abi(naked)` fn (no prologue/epilogue), so it returns on the caller's exact stack.
      if nm == "syscall" or nm == "ret" { push_str(sb, "  "); push_str(sb, nm); push_str(sb, "\n") }
      else if nm == "asm" {
        ## `asm("…GAS…", op…)` raw escape (spec ch.80 §4/§11): emit the template as one GAS line,
        ## validated only by `as`, with the fixed positional-`{i}` substitution scheme — each `{i}`
        ## (zero-based) is replaced by the GAS spelling of operand `i` (arg `i+1`; arg 0 is the template):
        ## a register `Var` → `%reg`, else a `Num` immediate → `$N`. A `{` not followed by a digit is
        ## literal (so no-operand templates emit verbatim). Single-line template (no `\n` escape).
        a0 := deref(arg_p(ah))
        sp := asm_str_span(a0.e)
        push_str(sb, "  ")
        mut j := 0
        while j < sp.n {
          c := str_at((cx.src + sp.s + j), 1)
          d0 := if j + 1 < sp.n { asm_digit(str_at((cx.src + sp.s + j + 1), 1)) } else { -1 }
          if c == "{" and d0 >= 0 {
            mut k := j + 1
            mut idx := 0
            while k < sp.n and asm_digit(str_at((cx.src + sp.s + k), 1)) >= 0 {
              idx = idx * 10 + usize(asm_digit(str_at((cx.src + sp.s + k), 1)))
              k += 1
            }
            oe := arg_expr_at(ah, idx + 1, a)   ## operand `idx` = arg `idx+1` (arg 0 is the template)
            sv := var_name_span(oe)
            mut reg := ""
            if sv.n != 0 { reg = x86_gpreg(str_at((cx.src + sv.s), sv.n)) }
            if reg == "" { push_str(sb, "$"); push_int(sb, num_lit_value(oe)) } else { push_str(sb, reg) }
            if k < sp.n and str_at((cx.src + sp.s + k), 1) == "}" { k = k + 1 }   ## skip the closing '}'
            j = k
          } else {
            push_str(sb, c)
            j += 1
          }
        }
        push_str(sb, "\n")
      }
      else if nm == "jmp" {
        a0 := deref(arg_p(ah))
        dv := var_name_span(a0.e)
        push_str(sb, "  jmp ")
        emit_code_label_name(sb, cx, dv.s, dv.n)
        push_str(sb, "\n")
      }
      else if nm == "negq" or nm == "notq" {
        ## 1-operand register-form (`negq(rax)` → `negq %rax` two's-complement negate; `notq` bitwise NOT).
        ## BIND `dreg` before pushing (a nested `push_str(sb, x86_gpreg(str_at(…)))` — a call-returning-str
        ## passed inline as the arg — crashes the seed; the 2-operand path binds it too).
        a0 := deref(arg_p(ah))
        dv := var_name_span(a0.e)
        dreg := x86_gpreg(str_at((cx.src + dv.s), dv.n))
        push_str(sb, "  ")
        push_str(sb, nm)
        push_str(sb, " ")
        push_str(sb, dreg)
        push_str(sb, "\n")
      }
      else if nm == "movq" or nm == "addq" or nm == "subq" or nm == "andq" or nm == "orq" or nm == "xorq" or nm == "shlq" or nm == "shrq" or nm == "sarq" or nm == "imulq" {
        ## 2-operand register-form instruction (`movq`/`addq`/`subq`/`andq`/`orq`/`xorq`/`shlq`/`shrq`/`sarq`/`imulq`),
        ## destination-first (spec §2.2) → AT&T `<mnem> <src>, <dest>` (the mnemonic is a valid GAS spelling as-is).
        ## `addq(rax, rbx)` => `addq %rbx, %rax` (rax += rbx); `shlq(rax, 2)` => `shlq $2, %rax` (a shift-by-immediate,
        ## the common form). `dest` is a register; `src` is a register or an immediate.
        a0 := deref(arg_p(ah))
        dv := var_name_span(a0.e)
        dreg := x86_gpreg(str_at((cx.src + dv.s), dv.n))
        a1 := deref(arg_p(a0.next))
        push_str(sb, "  ")
        push_str(sb, nm)
        push_str(sb, " ")
        ## src operand — a register or an immediate. Use the STANDALONE accessors `var_name_span` /
        ## `num_lit_value` (an inline `match deref(a1.e)` here degenerates the local-Expr payload read —
        ## it bound the Num's `v` to the node pointer, emitting a garbage immediate).
        sv := var_name_span(a1.e)
        mut sreg := ""
        if sv.n != 0 { sreg = x86_gpreg(str_at((cx.src + sv.s), sv.n)) }
        if sreg == "" {
          push_str(sb, "$")
          push_int(sb, num_lit_value(a1.e))
        } else {
          push_str(sb, sreg)
        }
        push_str(sb, ", ")
        push_str(sb, dreg)
        push_str(sb, "\n")
      }
    }
    _ => {}
  }
}
