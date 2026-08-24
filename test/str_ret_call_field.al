## e2e — `.len` / `.ptr` taken DIRECTLY on a `str`-returning CALL result (Types §9.4: a `str` IS the
## 2-word {ptr, len} pair). The result is NOT bound to a local, so the pair lives only in the return
## registers (ptr/%rax, len/%rdx). The `Expr::Field` arm had a `slice_ret_call` case for a `-> Slice(T)`
## call but no `str` dual: `rd().len` matched no arm, fell through to the slot default and pushed a
## garbage/zero word — a SILENT MISCOMPILE (`s := rd(); s.len`, the BOUND spelling, read 5, so the two
## spellings disagreed). Locks the direct read in every operand position (a binding RHS, an `if`
## condition, a call argument, arithmetic, an explicit `return`), since only the bare tail-expression
## form is exercised elsewhere. Returns 42 iff every read is exact.
rd   := fn() -> str { return "hello" }
emp  := fn() -> str { return "" }
pick := fn(b : bool) -> str { if b { return "abcd" } return "xy" }
takes := fn(k : usize) -> u64 { u64(k) }

main := fn() -> u64 {
  if rd().len != 5 { return 1 }                     ## an `if` condition — was 0
  n := rd().len                                     ## a binding RHS — was 0
  if u64(n) != 5 { return 2 }
  if takes(rd().len) != 5 { return 3 }              ## a call ARGUMENT
  if u64(rd().len) + 1 != 6 { return 4 }            ## an arithmetic operand
  if emp().len != 0 { return 5 }                    ## an empty str is genuinely 0 (not the old accident)
  s := rd()
  if s.len != rd().len { return 6 }                 ## bound and direct must agree
  if pick(true).len != 4 { return 7 }               ## a call WITH ARGS, through a branch
  if pick(false).len != 2 { return 8 }
  if rd().len + pick(false).len != 7 { return 9 }   ## two direct reads in one expression
  ## `.ptr` on the call result must be the SAME data pointer the bound spelling reads.
  if unchecked bitcast(usize, rd().ptr) != unchecked bitcast(usize, s.ptr) { return 10 }
  return 42
}
