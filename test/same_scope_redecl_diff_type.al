## Issue #414 / Declarations §6.2 — a name already bound in the same scope may not be bound again.
## The DIFFERENT-TYPE spelling: two sibling `:=` declarations of `r` in the function body's own
## statement list, the second under a different aggregate type. On the parent this passed `check`,
## and the four backends then disagreed — x86_64's lowering fence refused it, while aarch64, riscv64
## and wasm emitted code that trapped at run time. §6.2 makes the program ill-formed, so the refusal
## belongs to `check` and must reach every build and emit surface identically.
pick := fn() -> usize {
  r := Result(usize, u32).Ok(7)
  r := Option(usize).Some(9)
  mut out : usize = 77
  match r {
    Some(v) => { out = 100 + v }
    None => { out = 50 }
  }
  return out
}

main := fn() -> u64 { return u64(pick()) }
