## Issue #44 safety residual: line comments between the bitcast comma and value must not hide the
## source-aware pointer-target fence. Both single-hash and doc-comment spellings are exercised.
## Failure-first baseline on amendment parent PR #77 HEAD d73558abe38b4d89794ee68fbb02d92da25e67b7:
## x86_64=4, WAT=4. After the fix x86_64 remains 4 while WAT must fail-loud with 134.
main := fn() -> u64 {
  x := @label(outer) loop {
    loop {
      break outer unchecked bitcast(
        ptr(u64),
        # single-hash gap comment
        ## doc-comment gap comment
        4
      )
    }
    break 0
  }
  x
}
