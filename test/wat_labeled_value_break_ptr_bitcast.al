## Issue #44 safety residual: a pointer-target `bitcast` must not pass the scalar named-value admission.
## Failure-first baseline on amendment parent PR #77 HEAD 9865e414e4ad7111c0d365bc4a7a2dcf70d024ee:
## x86_64=4, WAT=4. After the fix x86_64 remains 4 while WAT must fail-loud with 134.
## The source deliberately casts the integer word 4 to `ptr(u64)`; pointer/aggregate/unknown targets are
## outside the scalar integer slice and must not be admitted merely because WAT represents them as i64.
main := fn() -> u64 {
  x := @label(outer) loop {
    loop { break outer unchecked bitcast(ptr(u64), 4) }
    break 0
  }
  x
}
