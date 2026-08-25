## Issue #44 residual guard: an aggregate `break outer <expr>` must remain fail-loud in WAT rather than
## passing a linear-memory address through the scalar `(result i64)` loop block.
## Failure-first and post-fix baseline on parent origin/main e82a54e2686c3fd10ca00fa02ef5d8e4b87af8b9:
## WAT=134 in both cases. This is deliberately outside the scalar integer slice.
Pt := struct { x : u64, y : u64 }

main := fn() -> u64 {
  x := @label(outer) loop {
    loop { break outer Pt(x = 40, y = 2) }
    break Pt(x = 0, y = 0)
  }
  x.x
}
