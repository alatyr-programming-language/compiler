## Issue #44 safety residual: grouped global aliases with target and value-gap comments must remain
## outside the scalar named-value admission, even when the break expression adds `+ 0`.
## Failure-first baseline on amendment parent PR #77 HEAD 8412a7fdac8015f3b92c67b82c43b9b3a31af0b1:
## x86_64=4, WAT=4. After the fix x86_64 remains 4 while WAT must fail-loud with 134.
G := bitcast( ## target )
  ptr(u64),
  # value-gap )
  (4)
)

main := fn() -> u64 {
  x := @label(outer) loop {
    loop {
      break outer (G + 0)
    }
    break 0
  }
  x
}
