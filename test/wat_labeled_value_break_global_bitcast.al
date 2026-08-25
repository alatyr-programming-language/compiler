## Issue #44 safety residual: a global pointer-target `bitcast` must not pass the scalar named-value
## admission through the global literal path.
## Failure-first baseline on amendment parent PR #77 HEAD d73558abe38b4d89794ee68fbb02d92da25e67b7:
## x86_64=4, WAT=4. After the fix x86_64 remains 4 while WAT must fail-loud with 134.
G := bitcast(ptr(u64), 4)

main := fn() -> u64 {
  x := @label(outer) loop {
    loop { break outer G }
    break 0
  }
  x
}
