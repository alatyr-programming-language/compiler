## Declarations §6.2 forbids re-declaring a name already bound in the SAME scope, so the sequential
## case cannot spell its rebinding as a second `x :=` beside the first (issue #414 rejects that in
## `check`; the reject fixture `same_scope_redecl_comptime` now owns that shape). What #268 is about
## survives unchanged: the comptime binding must carry its real value, 5, not 0.
seq := fn() -> u64 {
  comptime x := 5
  if x != 5 { return 1 }
  y := 7
  return y
}

branch := fn(cond : bool) -> u64 {
  if cond {
    comptime x := 5
    return x
  } else {
    x := 7
    return x
  }
}

block := fn() -> u64 {
  if true {
    comptime x := 5
    if x != 5 { return 1 }
  }
  x := 7
  return x
}

main := fn() -> u64 {
  return seq() + branch(true) + branch(false) + block()
}
