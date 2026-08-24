## sema/§ limits (I5/I9, FND-10): the `unchecked { … }` BLOCK must be caught wherever it is NESTED, not
## only as a top-level statement of the function body — the `no_unchecked` scan is DEEP. Here the block
## sits under `match` → `while` → `if`, three structured bodies deep, and the unit declares
## `@limits(no_unchecked)` → REJECT.
##
## The block-form escape (see `reject_limit_no_unchecked_block.al`) was invisible at EVERY depth, so this
## is the deep-walk half of the same contract: `stmts_have_unchecked` already recursed through
## `Match`/`While`/`If` bodies, it simply never treated the `Stmt::Unchecked` it arrived at as a
## violation. Without the limit this is a valid program → 42.
@limits(no_unchecked)
f := fn(a : u64, b : u64) -> u64 {
  mut r : u64 = 0
  match 1 {
    1 => {
      mut i : u64 = 0
      while i < 1 {
        if a > 0 { unchecked { r = a + b } }
        i = i + 1
      }
    }
    _ => { r = 0 }
  }
  return r
}
main := fn() -> u64 { return f(40, 2) }
