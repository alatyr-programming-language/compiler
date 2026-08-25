## Issue #44 safety residual: an inline line comment after the bitcast comma must not hide the value
## boundary or fake target delimiters from source-aware pointer-target rejection.
## Failure-first baseline on amendment parent PR #77 HEAD cb2a8432fc60428d5e4e02efd3a7257e2ae69970:
## x86_64=4, WAT=4. After the fix x86_64 remains 4 while WAT must fail-loud with 134.
G := bitcast(ptr(u64), # inline gap comment ) ]
 4)

main := fn() -> u64 {
  x := @label(outer) loop {
    loop {
      break outer G
    }
    break 0
  }
  x
}
